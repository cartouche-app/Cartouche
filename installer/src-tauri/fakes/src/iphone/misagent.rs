//! misagent, which keeps the provisioning profiles the iPhone holds: those
//! the apps were installed with, and those installed on their own since, as
//! SideStore and a Mac renew an app. An app runs as long as one of them
//! covers it: its App ID, this iPhone, and the certificate it was signed
//! with (`FakeIphone::runs_until`).

use std::{io, time::SystemTime};

use tokio::net::TcpStream;

use super::{FakeIphone, verify};
use crate::{
    dict,
    wire::{get_str, read_plist, write_plist},
};

/// What misagent answers for a profile it does not take. The fake's own
/// numbers: idevice only reads that the status is not 0.
pub const NOT_A_PROFILE: u64 = 0xe800_8001;
pub const NOT_FOR_THIS_IPHONE: u64 = 0xe800_801c;
pub const REFUSED: u64 = 0xe800_8012;

/// A profile the iPhone holds, as installed.
#[derive(Clone, Debug)]
pub struct HeldProfile {
    pub uuid: String,
    pub bytes: Vec<u8>,
    pub plist: plist::Dictionary,
}

impl HeldProfile {
    pub fn read(bytes: &[u8]) -> Result<HeldProfile, String> {
        let plist = verify::read_profile(bytes)?;
        let uuid = plist
            .get("UUID")
            .and_then(|v| v.as_string())
            .ok_or("the profile has no UUID")?
            .to_string();
        Ok(HeldProfile { uuid, bytes: bytes.to_vec(), plist })
    }

    pub fn expires(&self) -> Option<SystemTime> {
        self.plist
            .get("ExpirationDate")
            .and_then(|v| v.as_date())
            .map(SystemTime::from)
    }

    pub fn application_identifier(&self) -> Option<&str> {
        self.plist
            .get("Entitlements")
            .and_then(|v| v.as_dictionary())
            .and_then(|e| e.get("application-identifier"))
            .and_then(|v| v.as_string())
    }

    pub fn lists_device(&self, udid: &str) -> bool {
        self.plist.get("ProvisionsAllDevices").and_then(|v| v.as_boolean()) == Some(true)
            || self
                .plist
                .get("ProvisionedDevices")
                .and_then(|v| v.as_array())
                .is_some_and(|a| a.iter().any(|v| v.as_string() == Some(udid)))
    }

    pub fn lists_certificate(&self, der: &[u8]) -> bool {
        self.plist
            .get("DeveloperCertificates")
            .and_then(|v| v.as_array())
            .is_some_and(|a| a.iter().any(|v| v.as_data() == Some(der)))
    }
}

pub async fn serve(iphone: FakeIphone, mut stream: TcpStream) -> io::Result<()> {
    loop {
        let Some(request) = read_plist(&mut stream).await? else {
            return Ok(());
        };
        let kind = get_str(&request, "MessageType").unwrap_or("").to_string();
        let profile_type = get_str(&request, "ProfileType").unwrap_or("").to_string();
        if profile_type != "Provisioning" {
            iphone.note(format!("misagent: {kind} of {profile_type:?} profiles"));
            write_plist(&mut stream, &dict! { "Status" => REFUSED }).await?;
            continue;
        }
        match kind.as_str() {
            "Install" => {
                let bytes = request.get("Profile").and_then(|v| v.as_data()).unwrap_or(&[]).to_vec();
                let status = install(&iphone, &bytes);
                write_plist(&mut stream, &dict! { "Status" => status }).await?;
            }
            "CopyAll" | "Copy" => {
                let payload: Vec<plist::Value> = iphone
                    .state()
                    .profiles
                    .iter()
                    .map(|p| plist::Value::Data(p.bytes.clone()))
                    .collect();
                iphone.note(format!("misagent: copy {} profiles", payload.len()));
                write_plist(&mut stream, &dict! { "Payload" => payload, "Status" => 0u64 }).await?;
            }
            "Remove" => {
                let id = get_str(&request, "ProfileID").unwrap_or("").to_string();
                let removed = {
                    let mut state = iphone.state();
                    let before = state.profiles.len();
                    state.profiles.retain(|p| p.uuid != id);
                    before != state.profiles.len()
                };
                iphone.note(format!("misagent: remove {id}: {removed}"));
                write_plist(&mut stream, &dict! { "Status" => if removed { 0 } else { REFUSED } }).await?;
            }
            other => {
                iphone.note(format!("misagent: unknown message {other}"));
                write_plist(&mut stream, &dict! { "Status" => REFUSED }).await?;
            }
        }
    }
}

/// Installs a profile as misagent does, and answers its status.
fn install(iphone: &FakeIphone, bytes: &[u8]) -> u64 {
    let refused = iphone.state().fail_profile_install.take();
    if let Some(status) = refused {
        iphone.note(format!("misagent: install refused, injected {status:#x}"));
        return status;
    }
    let profile = match HeldProfile::read(bytes) {
        Ok(p) => p,
        Err(why) => {
            iphone.note(format!("misagent: install refused: {why}"));
            return NOT_A_PROFILE;
        }
    };
    if !profile.lists_device(iphone.udid()) {
        iphone.note(format!("misagent: install refused: {} does not list this iPhone", profile.uuid));
        return NOT_FOR_THIS_IPHONE;
    }
    iphone.note(format!(
        "misagent: installed {} for {}",
        profile.uuid,
        profile.application_identifier().unwrap_or("?")
    ));
    iphone.hold_profile(profile);
    0
}

impl FakeIphone {
    /// Keeps PROFILE, as iOS does with an app's own when it installs it, and
    /// with one misagent installs: a profile of the same UUID is replaced.
    pub fn hold_profile(&self, profile: HeldProfile) {
        let mut state = self.state();
        state.profiles.retain(|p| p.uuid != profile.uuid);
        state.profiles.push(profile);
    }

    /// Until when the installed app BUNDLE_ID runs: the latest expiry of the
    /// profiles the iPhone holds for its App ID, this iPhone and the
    /// certificate that signed it. None when no profile covers it, or the
    /// app is not there.
    pub fn runs_until(&self, bundle_id: &str) -> Option<SystemTime> {
        let state = self.state();
        let app = state.apps.get(bundle_id)?;
        let app_id = format!("{}.{}", app.signature.team_id, app.bundle_id);
        let udid = &self.0.config.udid;
        state
            .profiles
            .iter()
            .filter(|p| p.application_identifier() == Some(app_id.as_str()))
            .filter(|p| p.lists_device(udid))
            .filter(|p| p.lists_certificate(&app.signature.signer_certificate))
            .filter_map(HeldProfile::expires)
            .max()
    }

    /// The profiles the iPhone holds for App ID APP_ID (team.bundle).
    pub fn profiles_for(&self, app_id: &str) -> Vec<HeldProfile> {
        self.state()
            .profiles
            .iter()
            .filter(|p| p.application_identifier() == Some(app_id))
            .cloned()
            .collect()
    }
}
