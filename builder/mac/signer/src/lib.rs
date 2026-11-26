//! Cartouche for Mac's signer: renews Cartouche on the player's iPhone with
//! a new provisioning profile, as SideStore does on the iPhone, from the
//! Mac it is plugged in to, without signing or installing anything again
//! (README.md, decision 165). The Mac keeps the player's Apple session,
//! never their password.
//!
//! It signs in as the Cartouche Installer does (installer/src-tauri), with
//! isideload and idevice, and is tested against the Installer's fakes.

pub mod error;
pub mod iphone;
pub mod profile;
pub mod protocol;
pub mod renew;
pub mod rules;
pub mod session;

use std::path::PathBuf;

use idevice::usbmuxd::UsbmuxdAddr;

pub use error::{Failure, Kind, Result, Stage};

/// Cartouche's identifier, before the team's is added at its signing.
pub const BUNDLE_ID: &str = "io.github.clabeuhtegrite.cartouche";
/// The app group SideStore and Cartouche share, the team's added
/// (isideload, for an app that carries SideStore).
pub const APP_GROUP: &str = "group.com.SideStore.SideStore";
/// The label of the signer's connections to the iPhone.
pub const PROVIDER_LABEL: &str = "cartouche-signer";
/// The Installer's anisette server, which the Mac's sign-in takes too.
pub const DEFAULT_ANISETTE: &str = "https://mac-ani.jkcoxson.com";

/// Picks rustls's cryptography, as the Installer does (ring is in the tree
/// too), and isideload's error reports. Once, before anything reaches
/// Apple; again is nothing.
pub fn init() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
        let _ = isideload::init();
    });
}

/// What the signer reaches, and where it keeps its files: the system's in
/// the app, the fakes' in the tests.
#[derive(Clone, Debug)]
pub struct Environment {
    /// usbmuxd, which reaches the iPhone.
    pub usbmuxd: UsbmuxdAddr,
    /// The proxy isideload sends Apple's requests through: none in the app.
    pub apple_proxy: Option<String>,
    pub anisette_url: String,
    /// The signer's folder, readable by the player's account alone: the
    /// session (session.json) and isideload's files (the anisette machine).
    pub folder: PathBuf,
}

impl Environment {
    /// The Mac's usbmuxd, as idevice finds it (USBMUXD_SOCKET_ADDRESS, or
    /// /var/run/usbmuxd).
    pub fn system(folder: PathBuf, anisette_url: Option<String>) -> Result<Self> {
        let usbmuxd = UsbmuxdAddr::from_env_var()
            .map_err(|e| Failure::new(Kind::NoIphone, Stage::Iphone, format!("usbmuxd: {e}")))?;
        Ok(Environment {
            usbmuxd,
            apple_proxy: None,
            anisette_url: anisette_url.unwrap_or_else(|| DEFAULT_ANISETTE.to_string()),
            folder,
        })
    }

    pub fn session_file(&self) -> PathBuf {
        self.folder.join("session.json")
    }

    pub fn isideload_folder(&self) -> PathBuf {
        self.folder.join("isideload")
    }

    /// Makes the signer's folder, readable by the player's account alone.
    pub fn ensure_folder(&self) -> Result<()> {
        for folder in [&self.folder, &self.isideload_folder()] {
            std::fs::create_dir_all(folder).map_err(|e| internal(format!("{}: {e}", folder.display())))?;
            private(folder, 0o700)?;
        }
        Ok(())
    }
}

#[cfg(unix)]
pub(crate) fn private(path: &std::path::Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
        .map_err(|e| internal(format!("{}: {e}", path.display())))
}

#[cfg(not(unix))]
pub(crate) fn private(_path: &std::path::Path, _mode: u32) -> Result<()> {
    Ok(())
}

pub(crate) fn internal(message: impl Into<String>) -> Failure {
    Failure::new(Kind::Internal, Stage::Session, message)
}
