//! Installing Cartouche again over its copy on the iPhone, from the Mac,
//! when the certificate it was signed with is gone: the newest release,
//! signed for the same team, over the same identifier, its games and saves
//! kept; never a certificate revoked, never another account's copy.

use std::{sync::Mutex, time::SystemTime};

use cartouche_signer::{
    Kind,
    reinstall::{self, MACHINE_NAME},
    renew::{self, Options},
    rules::Due,
};

use crate::harness::*;

/// Cartouche 0.16.2, installed by the Installer, its certificate then
/// revoked on another computer, and VERSION published since.
async fn revoked(version: &str) -> Harness {
    let h = Harness::new().await;
    h.sign_in().await;
    h.install_cartouche().await;
    h.age_cartouche(HOUR, false);
    h.apple.with_account(EMAIL, |a| a.team.certificates.clear());
    h.publish_cartouche("0.16.2");
    h.publish_cartouche(version);
    h
}

/// Each step and fraction the signer gave, in order.
#[derive(Default)]
struct Steps(Mutex<Vec<(String, f64)>>);

impl Steps {
    fn record(&self, step: &str, fraction: f64) {
        self.0.lock().unwrap().push((step.to_string(), fraction));
    }

    /// The steps, each once, in the order they came.
    fn names(&self) -> Vec<String> {
        let mut names: Vec<String> = Vec::new();
        for (step, _) in self.0.lock().unwrap().iter() {
            if names.last() != Some(step) {
                names.push(step.clone());
            }
        }
        names
    }
}

/// Files of Cartouche's own the iPhone holds now: its version, the files
/// of the .app and the profiles, to say nothing was changed.
fn iphone_now(h: &Harness) -> (Option<String>, usize, usize) {
    let files = h.iphone.app(&h.bundle_id()).map(|a| a.files.len()).unwrap_or_default();
    (h.cartouche_version(), files, h.iphone.state().profiles.len())
}

fn installs_since(h: &Harness, log: usize) -> Vec<String> {
    h.iphone.log()[log..].iter().filter(|l| l.starts_with("installation_proxy: install")).cloned().collect()
}

/// What the signer leaves of an install in the Downloads folder.
fn downloads(h: &Harness) -> Vec<String> {
    std::fs::read_dir(h.env.folder.join(reinstall::DOWNLOADS))
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect()
}

/// What isideload unpacked of an IPA of VERSION in the temporary folder.
fn unpacked(version: &str) -> Vec<String> {
    let prefix = format!("Cartouche-{version}-{}-", std::process::id());
    std::fs::read_dir(std::env::temp_dir())
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with(&prefix))
        .collect()
}

#[tokio::test(flavor = "multi_thread")]
async fn installs_the_newest_cartouche_over_its_copy_and_keeps_its_games() {
    // A version no other test publishes, for what is left in the
    // temporary folder.
    let h = revoked("0.17.0").await;
    {
        let mut state = h.iphone.state();
        let container = &mut state.apps.get_mut(&h.bundle_id()).unwrap().container;
        container.mkdir_p("Documents/Saves").unwrap();
        container.write("Documents/Saves/0100F2C0115B6000.zip", b"save".to_vec()).unwrap();
    }
    let before = h.runs_until();
    // A new profile would not open it: its certificate is gone.
    let error = renew::renew(&h.env, &h.udid(), Options::default()).await.expect_err("renewed without a certificate");
    assert_eq!(error.kind, Kind::CertificateGone, "{error}");

    let steps = Steps::default();
    let record = |step: &str, fraction: f64| steps.record(step, fraction);
    let done = reinstall::reinstall(&h.env, &h.udid(), &record).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(done.reinstalled);
    assert_eq!(done.bundle_id, h.bundle_id());
    assert_eq!(done.version, "0.17.0");
    assert_eq!(done.previous_version.as_deref(), Some("0.16.2"));
    assert_eq!(done.before, before);
    assert_eq!(done.due, Due::Now);
    assert_eq!(done.link, "usb");

    // The newest Cartouche, over the same identifier, runs seven days more.
    assert_eq!(h.cartouche_version().as_deref(), Some("0.17.0"));
    let after = h.runs_until();
    assert!(about(after, SystemTime::now() + 7 * DAY), "runs until {after:?}\n{}", h.report());
    assert_eq!(done.expires, after);
    // Its games and saves, kept by iOS with its container.
    let app = h.iphone.app(&h.bundle_id()).unwrap();
    assert_eq!(app.container.read("Documents/Saves/0100F2C0115B6000.zip").unwrap(), b"save");

    // Signed for the same team, with Increased Memory Limit, and the
    // certificate of this Mac in SideStore's framework, to renew with.
    assert_eq!(app.signature.team_id, h.team_id);
    assert_eq!(app.signature.entitlements.get("com.apple.developer.kernel.increased-memory-limit"), Some(&true.into()));
    let certificates = h.apple.with_account(EMAIL, |a| a.team.certificates.clone());
    assert_eq!(certificates.len(), 1, "{certificates:#?}");
    assert_eq!(certificates[0].machine_name, MACHINE_NAME);
    let sidestore = app
        .signature
        .bundles
        .iter()
        .find(|b| b.path == "Frameworks/SideStoreApp.framework")
        .expect("SideStore's framework");
    assert_eq!(sidestore.info.get("ALTCertificateID"), Some(&certificates[0].serial.clone().into()));
    assert!(app.files.contains_key("Frameworks/SideStoreApp.framework/ALTCertificate.p12"));

    // No certificate revoked, ever.
    assert!(!h.developer_requests().iter().any(|r| r.contains("revoke")), "{:#?}", h.developer_requests());
    // Downloaded from the releases the source lists, then signed, then
    // installed.
    assert!(
        h.github.state().requests.iter().any(|r| r.contains("/releases/download/v0.17.0/")),
        "{:#?}",
        h.github.state().requests
    );
    assert_eq!(steps.names(), ["download", "sign", "install"]);
    assert!(steps.0.lock().unwrap().iter().all(|(_, f)| (0.0..=1.0).contains(f)));
    // Nothing left of the IPA on the Mac.
    assert!(downloads(&h).is_empty(), "{:?}", downloads(&h));
    assert!(unpacked("0.17.0").is_empty(), "{:?}", unpacked("0.17.0"));
}

#[tokio::test(flavor = "multi_thread")]
async fn with_as_many_certificates_as_apple_allows_none_is_revoked_and_nothing_installed() {
    let h = revoked("0.16.3").await;
    // Two of other computers: as many as a free account holds.
    let mut serials =
        vec![h.apple.add_foreign_certificate(EMAIL, "AltServer"), h.apple.add_foreign_certificate(EMAIL, "iPad")];
    serials.sort();
    let iphone = iphone_now(&h);
    let log = h.iphone.log().len();

    let error = reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed without a certificate");
    assert_eq!(error.kind, Kind::NoCertificateLeft, "{error}");
    let mut left: Vec<String> =
        h.apple.with_account(EMAIL, |a| a.team.certificates.iter().map(|c| c.serial.clone()).collect());
    left.sort();
    assert_eq!(left, serials);
    assert!(!h.developer_requests().iter().any(|r| r.contains("revoke")), "{:#?}", h.developer_requests());
    assert_eq!(iphone_now(&h), iphone);
    assert!(installs_since(&h, log).is_empty());
    assert!(downloads(&h).is_empty(), "{:?}", downloads(&h));
}

#[tokio::test(flavor = "multi_thread")]
async fn cartouche_of_another_apple_account_is_left_alone() {
    let h = revoked("0.16.3").await;
    // The Mac signed in with another account.
    let other = AccountConfig::new("dominique@example.com", "Other-Horse-9");
    h.apple.add_account(other.clone());
    let code = other.code.clone();
    let codes: cartouche_signer::session::CodeAsker = std::sync::Arc::new(move |_| {
        use futures::FutureExt;
        let code = code.clone();
        async move { Ok(isideload::auth::apple_account::TwoFactorCallbackResponse::SubmitCode(code)) }.boxed()
    });
    cartouche_signer::session::sign_in(&h.env, &other.email, &other.password, codes).await.unwrap();
    let iphone = iphone_now(&h);
    let log = h.iphone.log().len();

    let error =
        reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed over another account's");
    assert_eq!(error.kind, Kind::OtherTeam, "{error}");
    assert!(h.github.state().requests.is_empty(), "downloaded: {:#?}", h.github.state().requests);
    assert_eq!(iphone_now(&h), iphone);
    assert!(installs_since(&h, log).is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn an_ipa_that_is_not_the_one_the_source_lists_is_never_installed() {
    let h = revoked("0.16.3").await;
    let iphone = iphone_now(&h);
    let log = h.iphone.log().len();
    let size = CartoucheIpa::new("0.16.3").build().len();

    // Other bytes, of the same size.
    h.github.state().asset_replace = Some(vec![0; size]);
    let error = reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed another IPA");
    assert_eq!(error.kind, Kind::Download, "{error}");
    assert!(error.message.contains("SHA-256"), "{error}");
    // Cut short.
    h.github.state().asset_replace = None;
    h.github.state().asset_truncate = Some(size / 2);
    let error = reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed half an IPA");
    assert!(matches!(error.kind, Kind::Download | Kind::Network), "{error}");
    // No source.
    h.github.state().asset_truncate = None;
    h.github.state().source_status = Some(503);
    let error = reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed without a source");
    assert_eq!(error.kind, Kind::Download, "{error}");

    assert_eq!(iphone_now(&h), iphone);
    assert!(installs_since(&h, log).is_empty());
    assert!(h.apple.with_account(EMAIL, |a| a.team.certificates.is_empty()), "a certificate was made");
    assert!(downloads(&h).is_empty(), "{:?}", downloads(&h));
}

#[tokio::test(flavor = "multi_thread")]
async fn without_a_session_nothing_is_downloaded_or_installed() {
    let h = Harness::new().await;
    h.publish_cartouche("0.16.3");
    let error = reinstall::reinstall(&h.env, &h.udid(), &|_, _| {}).await.expect_err("installed without a session");
    assert_eq!(error.kind, Kind::NoSession);
    assert!(h.iphone.log().is_empty(), "{:#?}", h.iphone.log());
    assert!(h.github.state().requests.is_empty());
}
