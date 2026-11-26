//! The signer as Cartouche for Mac runs it, with the Cartouche Installer's
//! fakes all around (installer/src-tauri/tests/README.md): an iPhone behind
//! usbmuxd, Apple and an anisette server. Cartouche is put on the iPhone as
//! the Installer puts it, with isideload, so that the signer finds it as it
//! is on a player's iPhone.

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Once},
    time::{Duration, SystemTime},
};

pub use cartouche_installer_fakes::{
    AccountConfig, FakeAnisette, FakeApple, FakeIphone, FakeUsbmuxd, IphoneConfig,
    ipa::CartoucheIpa,
    iphone::{HeldProfile, misagent},
};
use cartouche_signer::{
    Environment,
    session::{self, CodeAsker, SessionInfo},
};
use futures::FutureExt;
use idevice::usbmuxd::UsbmuxdAddr;
use isideload::{
    auth::apple_account::TwoFactorCallbackResponse,
    sideload::{
        SideloaderBuilder,
        builder::{ExtensionsBehavior, ExtensionsBehaviorSelection, MaxCertsBehavior},
    },
    util::{
        callbacks::{ExtensionsBehaviorCallbackBox, MaxCertsCallbackBox},
        fs_storage::FsStorage,
    },
};

pub const EMAIL: &str = "camille.testeur@example.com";
pub const PASSWORD: &str = "Correct-Horse-7";
pub const CARTOUCHE: &str = "io.github.clabeuhtegrite.cartouche";
pub const HOUR: Duration = Duration::from_secs(3600);
pub const DAY: Duration = Duration::from_secs(86_400);

fn init_logging() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        // CARTOUCHE_TEST_LOG=1 shows what the signer and the fakes did.
        if std::env::var_os("CARTOUCHE_TEST_LOG").is_some() {
            let _ = tracing_subscriber::fmt().with_max_level(tracing::Level::DEBUG).with_test_writer().try_init();
        }
    });
}

pub struct Harness {
    pub usbmuxd: FakeUsbmuxd,
    pub iphone: FakeIphone,
    pub apple: FakeApple,
    pub anisette: FakeAnisette,
    pub account: AccountConfig,
    pub team_id: String,
    pub env: Environment,
    /// This test's own folder: the signer's, the Installer's and the IPA.
    pub dir: tempfile::TempDir,
}

impl Harness {
    /// A Mac with an iPhone 17 Pro plugged in, which trusts it, and the
    /// free Apple Account of a player who gets a code on a trusted device.
    pub async fn new() -> Harness {
        Self::with(IphoneConfig::iphone_17_pro(1), AccountConfig::new(EMAIL, PASSWORD)).await
    }

    pub async fn with(iphone: IphoneConfig, account: AccountConfig) -> Harness {
        init_logging();
        let usbmuxd = FakeUsbmuxd::start().await.expect("fake usbmuxd");
        let apple = FakeApple::start().await;
        let anisette = FakeAnisette::start().await;
        let iphone = FakeIphone::new(iphone);
        usbmuxd.plug(&iphone);
        let team_id = apple.add_account(account.clone());
        let dir = tempfile::tempdir().expect("test folder");
        let env = Environment {
            usbmuxd: UsbmuxdAddr::TcpSocket(usbmuxd.addr()),
            apple_proxy: Some(apple.proxy_url()),
            anisette_url: anisette.url(),
            folder: dir.path().join("Signer"),
        };
        Harness { usbmuxd, iphone, apple, anisette, account, team_id, env, dir }
    }

    pub fn udid(&self) -> String {
        self.iphone.udid().to_string()
    }

    /// Cartouche's identifier as the iPhone lists it, signed by this team.
    pub fn bundle_id(&self) -> String {
        format!("{CARTOUCHE}.{}", self.team_id)
    }

    pub fn app_id(&self) -> String {
        format!("{}.{}", self.team_id, self.bundle_id())
    }

    /// Answers each code Apple asks for with the account's.
    pub fn codes(&self) -> CodeAsker {
        let code = self.account.code.clone();
        Arc::new(move |_| {
            let code = code.clone();
            async move { Ok(TwoFactorCallbackResponse::SubmitCode(code)) }.boxed()
        })
    }

    pub async fn sign_in(&self) -> SessionInfo {
        session::sign_in(&self.env, EMAIL, PASSWORD, self.codes())
            .await
            .unwrap_or_else(|e| panic!("sign-in: {e}\n{}", self.report()))
    }

    /// Installs Cartouche as the Installer does: signed with isideload for
    /// this account, its App ID with the app group and Increased Memory
    /// Limit, then installed on the iPhone, which keeps its profile.
    pub async fn install_cartouche(&self) {
        let resumed = session::resume(&self.env).await.expect("session for the install");
        // isideload unpacks an IPA in the system's temporary folder, by the
        // IPA's name: a name of this test's own.
        let unique = self.dir.path().file_name().unwrap().to_string_lossy().into_owned();
        let ipa = self.dir.path().join(format!("Cartouche-{unique}.ipa"));
        std::fs::write(&ipa, CartoucheIpa::new("0.16.2").build()).expect("IPA");
        let mut sideloader = SideloaderBuilder::<MaxCertsCallbackBox, ExtensionsBehaviorCallbackBox>::new(
            resumed.developer,
            EMAIL.to_string(),
        )
        .machine_name("Cartouche".into())
        .storage(Box::new(FsStorage::new(self.dir.path().join("Installer"))))
        .extensions_behavior(ExtensionsBehaviorSelection::Fixed(ExtensionsBehavior::ReuseMain))
        .max_certs_behavior(MaxCertsBehavior::Error)
        .build();
        let device = {
            let mut usbmuxd = self.env.usbmuxd.connect(0).await.expect("usbmuxd");
            usbmuxd.get_device(self.iphone.udid()).await.expect("the iPhone")
        };
        let provider = device.to_provider(self.env.usbmuxd.clone(), "cartouche-installer");
        sideloader
            .install_app(&provider, ipa, true, None::<fn(f32) -> std::future::Ready<()>>, None)
            .await
            .unwrap_or_else(|e| panic!("install: {e}\n{}", self.report()));
        assert!(self.iphone.app(&self.bundle_id()).is_some(), "Cartouche is not on the iPhone");
    }

    /// Until when Cartouche opens on the iPhone, as iOS takes it.
    pub fn runs_until(&self) -> Option<SystemTime> {
        self.iphone.runs_until(&self.bundle_id())
    }

    /// Makes Cartouche's profiles on the iPhone end LEFT from now (before
    /// now when negative), as days pass: each signed again by the fake
    /// Apple, under its own UUID.
    pub fn age_cartouche(&self, left: Duration, already_ended: bool) {
        let app_id = self.app_id();
        let ends = if already_ended { SystemTime::now() - left } else { SystemTime::now() + left };
        let aged: Vec<HeldProfile> = self
            .iphone
            .profiles_for(&app_id)
            .into_iter()
            .map(|held| {
                let mut plist = held.plist.clone();
                plist.insert("ExpirationDate".into(), plist::Value::Date(ends.into()));
                plist.insert("CreationDate".into(), plist::Value::Date((ends - 7 * DAY).into()));
                HeldProfile::read(&self.apple.ca().profile(&plist)).expect("aged profile")
            })
            .collect();
        assert!(!aged.is_empty(), "no profile of Cartouche on the iPhone");
        for profile in aged {
            self.iphone.hold_profile(profile);
        }
    }

    /// The developer services' requests Apple got, in order.
    pub fn developer_requests(&self) -> Vec<String> {
        self.apple.log().into_iter().filter(|l| l.starts_with("developer ")).collect()
    }

    pub fn sign_ins(&self) -> usize {
        self.apple.log().iter().filter(|l| l.starts_with("sign-in:")).count()
    }

    /// Every file of the signer's folder, with its contents.
    pub fn signer_files(&self) -> Vec<(PathBuf, Vec<u8>)> {
        fn walk(dir: &Path, out: &mut Vec<(PathBuf, Vec<u8>)>) {
            for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
                let path = entry.path();
                if path.is_dir() {
                    walk(&path, out);
                } else if let Ok(data) = std::fs::read(&path) {
                    out.push((path, data));
                }
            }
        }
        let mut out = Vec::new();
        walk(&self.env.folder, &mut out);
        out
    }

    /// What the fakes did, for a failure's message.
    pub fn report(&self) -> String {
        format!(
            "iPhone: {:#?}\nApple: {:#?}\nanisette: {:#?}",
            self.iphone.log(),
            self.apple.log(),
            self.anisette.state().log
        )
    }
}

/// Whether TIME is within a minute of WANT.
pub fn about(time: Option<SystemTime>, want: SystemTime) -> bool {
    time.is_some_and(|t| {
        let gap = if t > want { t.duration_since(want) } else { want.duration_since(t) };
        gap.unwrap_or_default() < Duration::from_secs(60)
    })
}
