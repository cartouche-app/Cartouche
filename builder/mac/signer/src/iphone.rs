//! The iPhones this Mac reaches through usbmuxd: by the cable, or on the
//! same Wi-Fi once Wi-Fi sync is on, as the Finder sees them. Never through
//! Tailscale: usbmuxd finds an iPhone on the network by Bonjour.
//!
//! What the signer does there: lists the apps (installation_proxy), reads
//! and installs provisioning profiles (misagent), and writes the renewal's
//! date in Cartouche's Documents (house_arrest), for Cartouche to read.

use std::time::SystemTime;

use idevice::{
    IdeviceService,
    afc::opcode::AfcFopenMode,
    house_arrest::HouseArrestClient,
    installation_proxy::InstallationProxyClient,
    lockdown::LockdownClient,
    misagent::MisagentClient,
    provider::UsbmuxdProvider,
    usbmuxd::{Connection, UsbmuxdDevice},
};
use serde::Serialize;

use crate::{
    BUNDLE_ID, Environment, Failure, Kind, PROVIDER_LABEL, Result, Stage,
    profile::{self, Profile},
    protocol::time,
    rules::{self, Due},
};

/// Where the signer writes the renewal's date, in Cartouche's container:
/// Cartouche takes the later of it, its embedded profile's and SideStore's
/// (CartoucheSignature).
pub const RENEWAL_RECORD: &str = "/Documents/.cartouche/renewal.json";

/// An iPhone, as the Mac's iPhone page shows it.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Iphone {
    pub udid: String,
    pub name: Option<String>,
    pub ios: Option<String>,
    /// "usb" or "network".
    pub link: &'static str,
    /// The copies of Cartouche on it: one, or one per Apple Account that
    /// installed it.
    pub cartouche: Vec<Cartouche>,
    /// Why the rest is not known: the iPhone did not answer.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<Failure>,
}

/// A copy of Cartouche on the iPhone.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Cartouche {
    /// As the iPhone lists it: "io.github.clabeuhtegrite.cartouche.TEAM".
    pub bundle_id: String,
    pub version: Option<String>,
    /// The team that signed it, from its identifier.
    pub team_id: Option<String>,
    /// Until when it opens, from the profiles the iPhone holds for it.
    #[serde(with = "time::option")]
    pub expires: Option<SystemTime>,
    #[serde(flatten)]
    pub due: Option<Due>,
}

/// The renewal's date, as Cartouche reads it: the fields of SideStore's
/// own record of an app (widget_data.json), and who renewed it.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RenewalRecord {
    pub bundle_identifier: String,
    #[serde(with = "time")]
    pub expiration_date: SystemTime,
    #[serde(with = "time")]
    pub refreshed_date: SystemTime,
    /// "mac".
    pub by: &'static str,
}

/// Whether BUNDLE_ID is Cartouche's, as the Installer reads it: its own
/// identifier, or with a team's after it.
pub fn is_cartouche(bundle_id: &str) -> bool {
    bundle_id == BUNDLE_ID
        || bundle_id
            .strip_prefix(BUNDLE_ID)
            .and_then(|rest| rest.strip_prefix('.'))
            .is_some_and(|team| !team.is_empty() && team.chars().all(|c| c.is_ascii_alphanumeric()))
}

/// The team in a signed copy's identifier.
pub fn team_of(bundle_id: &str) -> Option<String> {
    bundle_id
        .strip_prefix(BUNDLE_ID)
        .and_then(|rest| rest.strip_prefix('.'))
        .filter(|team| !team.is_empty())
        .map(str::to_string)
}

fn iphone_failure(e: idevice::IdeviceError) -> Failure {
    Failure::from_iphone(&e)
}

/// The iPhones usbmuxd lists, each once: by the cable when it is plugged
/// in, else on the network.
pub async fn devices(env: &Environment) -> Result<Vec<UsbmuxdDevice>> {
    let mut usbmuxd = env
        .usbmuxd
        .connect(0)
        .await
        .map_err(|e| Failure::new(Kind::NoIphone, Stage::Iphone, format!("usbmuxd does not answer: {e}")))?;
    let mut found = usbmuxd.get_devices().await.map_err(iphone_failure)?;
    found.sort_by_key(|d| !matches!(d.connection_type, Connection::Usb));
    let mut seen = std::collections::HashSet::new();
    found.retain(|d| seen.insert(d.udid.clone()));
    Ok(found)
}

/// The connection to the iPhone UDID.
pub async fn connect(env: &Environment, udid: &str) -> Result<(UsbmuxdDevice, UsbmuxdProvider)> {
    let device = devices(env).await?.into_iter().find(|d| d.udid.eq_ignore_ascii_case(udid)).ok_or_else(|| {
        Failure::new(Kind::NoIphone, Stage::Iphone, "The iPhone is not plugged in to this Mac, nor on its Wi-Fi")
    })?;
    let provider = device.to_provider(env.usbmuxd.clone(), PROVIDER_LABEL);
    Ok((device, provider))
}

pub fn link(device: &UsbmuxdDevice) -> &'static str {
    match device.connection_type {
        Connection::Usb => "usb",
        _ => "network",
    }
}

/// Its name and iOS version, as lockdown gives them without a session.
pub async fn describe(provider: &UsbmuxdProvider) -> Result<(Option<String>, Option<String>)> {
    let mut lockdown = LockdownClient::connect(provider).await.map_err(iphone_failure)?;
    let mut value = async |key: &str| {
        lockdown.get_value(Some(key), None).await.ok().and_then(|v| v.as_string().map(str::to_string))
    };
    let name = value("DeviceName").await;
    let ios = value("ProductVersion").await;
    Ok((name, ios))
}

/// Cartouche's copies, as installation_proxy lists them, with their versions.
pub async fn installed(provider: &UsbmuxdProvider) -> Result<Vec<(String, Option<String>)>> {
    let mut proxy = InstallationProxyClient::connect(provider).await.map_err(iphone_failure)?;
    let apps = proxy.get_apps(Some("User"), None).await.map_err(iphone_failure)?;
    let mut found: Vec<(String, Option<String>)> = apps
        .into_iter()
        .filter(|(id, _)| is_cartouche(id))
        .map(|(id, app)| {
            let version = app
                .as_dictionary()
                .and_then(|d| d.get("CFBundleShortVersionString"))
                .and_then(|v| v.as_string())
                .map(str::to_string);
            (id, version)
        })
        .collect();
    found.sort();
    Ok(found)
}

/// The provisioning profiles the iPhone holds, as misagent gives them.
pub async fn profiles(provider: &UsbmuxdProvider) -> Result<Vec<Profile>> {
    let mut misagent = MisagentClient::connect(provider).await.map_err(iphone_failure)?;
    let all = misagent.copy_all().await.map_err(iphone_failure)?;
    Ok(all.iter().filter_map(|bytes| Profile::parse(bytes)).collect())
}

/// Installs PROFILE, as SideStore does to renew an app.
pub async fn install_profile(provider: &UsbmuxdProvider, profile: &Profile) -> Result<()> {
    let mut misagent = MisagentClient::connect(provider).await.map_err(iphone_failure)?;
    misagent.install(profile.bytes.clone()).await.map_err(|e| match e {
        idevice::IdeviceError::MisagentFailure => {
            Failure::new(Kind::ProfileRefused, Stage::Iphone, "The iPhone did not take Cartouche's new profile")
        }
        e => iphone_failure(e),
    })
}

/// Writes RECORD in Cartouche's Documents.
pub async fn write_record(provider: &UsbmuxdProvider, record: &RenewalRecord) -> Result<()> {
    let data = serde_json::to_vec_pretty(record).map_err(|e| crate::internal(e.to_string()))?;
    let house_arrest = HouseArrestClient::connect(provider).await.map_err(iphone_failure)?;
    let mut afc = house_arrest.vend_documents(record.bundle_identifier.clone()).await.map_err(iphone_failure)?;
    let folder = RENEWAL_RECORD.rsplit_once('/').map(|(f, _)| f).unwrap_or("/Documents");
    afc.mk_dir(folder).await.map_err(iphone_failure)?;
    let mut file = afc.open(RENEWAL_RECORD, AfcFopenMode::Wr).await.map_err(iphone_failure)?;
    file.write_entire(&data).await.map_err(iphone_failure)?;
    file.close().await.map_err(iphone_failure)?;
    Ok(())
}

/// Each copy of Cartouche on the iPhone, with until when it opens.
pub async fn cartouches(
    provider: &UsbmuxdProvider,
    udid: &str,
    now: SystemTime,
) -> Result<(Vec<Cartouche>, Vec<Profile>)> {
    let installed = installed(provider).await?;
    if installed.is_empty() {
        return Ok((Vec::new(), Vec::new()));
    }
    let held = profiles(provider).await?;
    let copies = installed
        .into_iter()
        .map(|(bundle_id, version)| {
            let expires = profile::latest_for(&held, &bundle_id, udid).map(|p| p.expires);
            Cartouche {
                team_id: team_of(&bundle_id),
                due: expires.map(|e| rules::due(e, now)),
                expires,
                version,
                bundle_id,
            }
        })
        .collect();
    Ok((copies, held))
}

/// Every iPhone, with its copies of Cartouche: what the Mac's iPhone page
/// shows. An iPhone that does not answer is listed with why.
pub async fn list(env: &Environment) -> Result<Vec<Iphone>> {
    let now = SystemTime::now();
    let mut out = Vec::new();
    for device in devices(env).await? {
        let provider = device.to_provider(env.usbmuxd.clone(), PROVIDER_LABEL);
        let mut iphone = Iphone {
            udid: device.udid.clone(),
            name: None,
            ios: None,
            link: link(&device),
            cartouche: Vec::new(),
            error: None,
        };
        match describe(&provider).await {
            Ok((name, ios)) => {
                iphone.name = name;
                iphone.ios = ios;
            }
            Err(e) => iphone.error = Some(e),
        }
        if iphone.error.is_none() {
            match cartouches(&provider, &device.udid, now).await {
                Ok((copies, _)) => iphone.cartouche = copies,
                Err(e) => iphone.error = Some(e),
            }
        }
        out.push(iphone);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cartouche_with_or_without_its_team() {
        assert!(is_cartouche("io.github.clabeuhtegrite.cartouche"));
        assert!(is_cartouche("io.github.clabeuhtegrite.cartouche.ABCDE12345"));
        assert!(!is_cartouche("io.github.clabeuhtegrite.cartouche."));
        assert!(!is_cartouche("io.github.clabeuhtegrite.cartouche.A.B"));
        assert!(!is_cartouche("io.github.clabeuhtegrite.cartouchex"));
        assert_eq!(team_of("io.github.clabeuhtegrite.cartouche.ABCDE12345").as_deref(), Some("ABCDE12345"));
        assert_eq!(team_of("io.github.clabeuhtegrite.cartouche"), None);
    }
}
