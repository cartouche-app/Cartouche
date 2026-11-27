//! Installing Cartouche again over the copy on the iPhone, as the Cartouche
//! Installer does (installer/src-tauri), for the one case a new profile
//! does not open it: the certificate it was signed with is gone from the
//! account (`Kind::CertificateGone`, renew.rs), revoked by another app or
//! computer with the same Apple Account.
//!
//! The newest Cartouche its source lists, signed with a certificate of this
//! Mac's for the session's team, which is the copy's: the same identifier,
//! so that iOS installs it over the copy and keeps its container, with the
//! games, the saves, Increased Memory Limit on its App ID and SideStore's
//! pairing file. The certificate goes in Cartouche too, for its built-in
//! SideStore to renew it with (isideload, for a LiveContainer+SideStore).
//! Never a copy another Apple Account installed, and never a certificate
//! revoked: when the account has as many as Apple allows, the signer says
//! so (`Kind::NoCertificateLeft`) and installs nothing.

use std::{
    path::{Path, PathBuf},
    time::{Instant, SystemTime},
};

use isideload::{
    sideload::{
        SideloaderBuilder,
        application::SpecialApp,
        builder::{ExtensionsBehavior, ExtensionsBehaviorSelection, MaxCertsBehavior},
    },
    util::{
        callbacks::{ExtensionsBehaviorCallbackBox, MaxCertsCallbackBox},
        fs_storage::FsStorage,
    },
};
use serde::Serialize;

use crate::{
    Environment, Failure, Kind, Result, Stage, iphone, profile,
    protocol::time,
    release, renew,
    rules::{self, Due},
    session::{self, Resumed},
};

/// The name of this Mac's certificate on the Apple Account, as the Cartouche
/// Installer's certificates page and Apple list it.
pub const MACHINE_NAME: &str = "Cartouche for Mac";

/// Where the signer keeps the IPA while it installs it, in its own folder.
pub const DOWNLOADS: &str = "Downloads";

/// What an install over Cartouche did.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Reinstall {
    pub reinstalled: bool,
    pub bundle_id: String,
    /// The version installed now, and the one before.
    pub version: String,
    pub previous_version: Option<String>,
    /// Until when Cartouche opened before, and after.
    #[serde(with = "time::option")]
    pub before: Option<SystemTime>,
    #[serde(with = "time::option")]
    pub expires: Option<SystemTime>,
    /// Whether it was due, before.
    #[serde(flatten)]
    pub due: Due,
    /// Whether Apple gave the session a new Xcode token on the way.
    pub refreshed_session: bool,
    /// "usb" or "network".
    pub link: &'static str,
    pub seconds: f64,
}

/// Where an install is: "download", "sign" or "install", and the fraction
/// of that step done, from 0 to 1.
pub type Progress<'a> = &'a (dyn Fn(&str, f64) + Send + Sync);

/// Installs the newest Cartouche over the copy of the session's team on
/// the iPhone UDID.
pub async fn reinstall(env: &Environment, udid: &str, progress: Progress<'_>) -> Result<Reinstall> {
    let started = Instant::now();
    let now = SystemTime::now();
    let saved = session::load(env)?
        .ok_or_else(|| Failure::new(Kind::NoSession, Stage::Session, "No Apple Account on this Mac"))?;
    let (device, provider) = iphone::connect(env, udid).await?;
    let link = iphone::link(&device);
    let (copies, held) = iphone::cartouches(&provider, &device.udid, now).await?;
    let copy = renew::choose(&copies, &saved.team_id)?.clone();
    let before = profile::latest_for(&held, &copy.bundle_id, &device.udid).map(|p| p.expires);
    let due = rules::due(before.unwrap_or(SystemTime::UNIX_EPOCH), now);

    let resumed = session::resume(env).await?;
    let refreshed_session = resumed.refreshed;
    if resumed.team.team_id != copy.team_id.clone().unwrap_or_default() {
        return Err(renew::other_team());
    }
    let release = release::latest(env).await?;
    let downloads = env.folder.join(DOWNLOADS);
    std::fs::create_dir_all(&downloads).map_err(|e| crate::internal(format!("{}: {e}", downloads.display())))?;
    crate::private(&downloads, 0o700)?;
    let ipa = downloads.join(ipa_name(&release.version));
    release::download(env, &release, &ipa, |fraction| progress("download", fraction)).await?;
    let installed = sign_and_install(env, resumed, &provider, &ipa, &copy.bundle_id, &device.udid, progress).await;
    clean_up(&ipa);
    installed?;

    // What the iPhone lists now: the copy, signed until later than before.
    let (copies, held) = iphone::cartouches(&provider, &device.udid, SystemTime::now()).await?;
    let now_copy = copies.iter().find(|c| c.bundle_id == copy.bundle_id).ok_or_else(|| {
        Failure::new(Kind::Iphone, Stage::Iphone, "The iPhone does not list Cartouche after its install")
    })?;
    let expires = profile::latest_for(&held, &copy.bundle_id, &device.udid).map(|p| p.expires);
    if expires <= before {
        return Err(Failure::new(Kind::Iphone, Stage::Iphone, "The iPhone does not list Cartouche's new signature"));
    }
    Ok(Reinstall {
        reinstalled: true,
        bundle_id: copy.bundle_id.clone(),
        version: now_copy.version.clone().unwrap_or_else(|| release.version.clone()),
        previous_version: copy.version.clone(),
        before,
        expires,
        due,
        refreshed_session,
        link,
        seconds: started.elapsed().as_secs_f64(),
    })
}

/// Signs the IPA for the session's team, with this Mac's certificate, then
/// installs it over BUNDLE_ID, which it must be.
async fn sign_and_install(
    env: &Environment,
    resumed: Resumed,
    provider: &idevice::provider::UsbmuxdProvider,
    ipa: &Path,
    bundle_id: &str,
    udid: &str,
    progress: Progress<'_>,
) -> Result<()> {
    let apple = |r: rootcause::Report| Failure::from_apple(&r, Stage::Apple, false);
    let team = resumed.team.clone();
    let storage = Box::new(FsStorage::new(env.isideload_folder()));
    let mut sideloader = SideloaderBuilder::<MaxCertsCallbackBox, ExtensionsBehaviorCallbackBox>::new(
        resumed.developer,
        resumed.saved.email,
    )
    .machine_name(MACHINE_NAME.into())
    .storage(storage)
    .extensions_behavior(ExtensionsBehaviorSelection::Fixed(ExtensionsBehavior::ReuseMain))
    // Never a certificate revoked: as many as Apple allows is said.
    .max_certs_behavior(MaxCertsBehavior::Error)
    .build();
    let signing = |fraction: f32| {
        progress("sign", f64::from(fraction).clamp(0.0, 1.0));
        std::future::ready(())
    };
    let (signed, special) = sideloader
        .sign_app(ipa.to_path_buf(), Some(team), true, Some(signing), None, Some(udid))
        .await
        .map_err(apple)?;
    install_signed(provider, &signed, special, bundle_id, progress).await
}

async fn install_signed(
    provider: &idevice::provider::UsbmuxdProvider,
    signed: &Path,
    special: Option<SpecialApp>,
    bundle_id: &str,
    progress: Progress<'_>,
) -> Result<()> {
    // isideload gives SideStore its certificate only in an app it takes
    // for a LiveContainer+SideStore: Cartouche, by its SideStore framework.
    if special != Some(SpecialApp::SideStoreLc) {
        return Err(Failure::new(Kind::Download, Stage::Download, "The IPA of the source is not Cartouche"));
    }
    let signed_id = signed_bundle_id(signed);
    if signed_id.as_deref() != Some(bundle_id) {
        return Err(Failure::new(
            Kind::OtherTeam,
            Stage::Apple,
            format!("Cartouche signed for {}, not over {bundle_id}", signed_id.unwrap_or_default()),
        ));
    }
    isideload::sideload::install::install_app(provider, signed, |percent| {
        progress("install", (percent as f64 / 100.0).clamp(0.0, 1.0))
    })
    .await
    .map_err(|r| Failure::from_apple(&r, Stage::Iphone, false))
}

/// The identifier of the app at SIGNED, as its Info.plist says.
fn signed_bundle_id(signed: &Path) -> Option<String> {
    let info = plist::Value::from_file(signed.join("Info.plist")).ok()?;
    info.as_dictionary()?.get("CFBundleIdentifier")?.as_string().map(str::to_string)
}

/// isideload unpacks an IPA in the system's temporary folder, by the IPA's
/// name: a name of this install's own, as two iPhones may be at it at once.
fn ipa_name(version: &str) -> String {
    static INSTALLS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let n = INSTALLS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    format!("Cartouche-{version}-{}-{n}.ipa", std::process::id())
}

/// The IPA, and what isideload unpacked of it in the system's temporary
/// folder: a whole copy of Cartouche each time otherwise.
fn clean_up(ipa: &Path) {
    let _ = std::fs::remove_file(ipa);
    let Some(name) = ipa.file_name() else { return };
    let unpacked: PathBuf = std::env::temp_dir().join(format!("{}_extracted", name.to_string_lossy()));
    if unpacked.is_dir()
        && let Err(e) = std::fs::remove_dir_all(&unpacked)
    {
        tracing::warn!("Failed to remove {}: {e}", unpacked.display());
    }
}
