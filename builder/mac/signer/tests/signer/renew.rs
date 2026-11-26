//! Renewing Cartouche from the Mac with a new profile: what the iPhone runs
//! after, what Apple was asked, and what was left alone.

use std::time::SystemTime;

use cartouche_signer::{
    Kind,
    renew::{self, Options},
    rules::Due,
};

use crate::harness::*;

fn due() -> Options {
    Options { only_if_due: true, now: SystemTime::now() }
}

fn now() -> Options {
    Options::default()
}

/// A player's iPhone with Cartouche installed by the Installer, and the
/// Mac signed in with the same Apple Account.
async fn installed() -> Harness {
    let h = Harness::new().await;
    h.sign_in().await;
    h.install_cartouche().await;
    h
}

#[tokio::test(flavor = "multi_thread")]
async fn renews_cartouche_with_a_new_profile_and_installs_nothing_again() {
    let h = installed().await;
    // A save in Cartouche's Documents, which an install over it would keep
    // too, and the app's files as installed.
    {
        let mut state = h.iphone.state();
        let container = &mut state.apps.get_mut(&h.bundle_id()).unwrap().container;
        container.mkdir_p("Documents/Saves").unwrap();
        container.write("Documents/Saves/0100F2C0115B6000.zip", b"save".to_vec()).unwrap();
    }
    let files = h.iphone.app(&h.bundle_id()).unwrap().files;
    h.age_cartouche(20 * HOUR, false);
    let before = h.runs_until();
    let (certificates, app_ids) = h.apple.with_account(EMAIL, |a| (a.team.certificates.len(), a.team.app_ids.len()));
    let log = h.iphone.log().len();
    let asked = h.developer_requests().len();

    let renewal = renew::renew(&h.env, &h.udid(), due()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(renewal.renewed);
    assert_eq!(renewal.due, Due::Now);
    assert_eq!(renewal.bundle_id, h.bundle_id());
    assert_eq!(renewal.before, before);
    assert!(!renewal.registered_app_id);
    assert_eq!(renewal.link, "usb");
    assert!(renewal.recorded);

    // iOS runs it for seven days more, under the new profile.
    let after = h.runs_until();
    assert!(about(after, SystemTime::now() + 7 * DAY), "runs until {after:?}");
    assert_eq!(renewal.expires, after);
    // Nothing installed again: the same app, its save, no install asked.
    let app = h.iphone.app(&h.bundle_id()).unwrap();
    assert_eq!(app.files, files);
    assert_eq!(app.container.read("Documents/Saves/0100F2C0115B6000.zip").unwrap(), b"save");
    let since: Vec<String> = h.iphone.log()[log..].to_vec();
    assert!(!since.iter().any(|l| l.starts_with("installation_proxy: install")), "{since:#?}");
    assert!(since.iter().any(|l| l.starts_with("misagent: installed")), "{since:#?}");
    // Three requests to Apple, no certificate made or revoked, no App ID
    // taken.
    assert_eq!(
        h.developer_requests()[asked..],
        ["developer listTeams", "developer listAppIds", "developer downloadTeamProvisioningProfile"]
    );
    assert_eq!(
        h.apple.with_account(EMAIL, |a| (a.team.certificates.len(), a.team.app_ids.len())),
        (certificates, app_ids)
    );

    // Cartouche reads the new date in its Documents.
    let record =
        h.iphone.container_file(&h.bundle_id(), "Documents/.cartouche/renewal.json").expect("no renewal record");
    let record: serde_json::Value = serde_json::from_slice(&record).unwrap();
    assert_eq!(record["bundleIdentifier"], h.bundle_id().as_str());
    assert_eq!(record["by"], "mac");
    let expires = cartouche_signer::protocol::time::parse(record["expirationDate"].as_str().unwrap());
    assert!(about(expires, after.unwrap()), "{expires:?}, {after:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn not_in_its_last_two_days_it_is_left_alone_and_apple_is_not_asked() {
    let h = installed().await;
    let before = h.runs_until();
    let asked = h.developer_requests().len();
    let profiles = h.iphone.state().profiles.len();

    let renewal = renew::renew(&h.env, &h.udid(), due()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(!renewal.renewed);
    assert!(matches!(renewal.due, Due::NotYet { .. }), "{:?}", renewal.due);
    assert_eq!(renewal.expires, before);
    assert_eq!(h.developer_requests().len(), asked, "Apple was asked: {:#?}", &h.developer_requests()[asked..]);
    assert_eq!(h.iphone.state().profiles.len(), profiles);
    assert_eq!(h.runs_until(), before);
}

#[tokio::test(flavor = "multi_thread")]
async fn an_expired_cartouche_opens_again() {
    let h = installed().await;
    h.age_cartouche(3 * DAY, true);
    assert!(h.runs_until().unwrap() < SystemTime::now());

    let renewal = renew::renew(&h.env, &h.udid(), due()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(renewal.renewed);
    assert_eq!(renewal.due, Due::Expired);
    assert!(about(h.runs_until(), SystemTime::now() + 7 * DAY));
}

#[tokio::test(flavor = "multi_thread")]
async fn asked_by_the_player_it_renews_whenever() {
    let h = installed().await;
    h.age_cartouche(4 * DAY, false);
    let renewal = renew::renew(&h.env, &h.udid(), now()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(renewal.renewed);
    assert!(matches!(renewal.due, Due::NotYet { .. }));
    assert!(about(h.runs_until(), SystemTime::now() + 7 * DAY));
}

#[tokio::test(flavor = "multi_thread")]
async fn with_its_certificate_revoked_nothing_is_installed_and_the_mac_says_so() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
    let before = h.runs_until();
    let profiles = h.iphone.state().profiles.len();
    // Revoked on another computer: the account's profiles no longer list it.
    h.apple.with_account(EMAIL, |a| a.team.certificates.clear());

    let error = renew::renew(&h.env, &h.udid(), due()).await.expect_err("renewed without its certificate");
    assert_eq!(error.kind, Kind::CertificateGone, "{error}");
    assert_eq!(h.iphone.state().profiles.len(), profiles);
    assert_eq!(h.runs_until(), before);
}

#[tokio::test(flavor = "multi_thread")]
async fn an_app_id_gone_is_registered_again_as_the_installer_set_it_up() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
    let bundle_id = h.bundle_id();
    h.apple.with_account(EMAIL, |a| a.team.app_ids.retain(|x| x.identifier != bundle_id));

    let renewal = renew::renew(&h.env, &h.udid(), due()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(renewal.renewed);
    assert!(renewal.registered_app_id);
    assert!(about(h.runs_until(), SystemTime::now() + 7 * DAY), "{}", h.report());
    // With the app group and Increased Memory Limit Cartouche was signed with.
    let app_id =
        h.apple.with_account(EMAIL, |a| a.team.app_ids.iter().find(|x| x.identifier == bundle_id).cloned()).unwrap();
    assert!(app_id.increased_memory_limit);
    assert_eq!(app_id.groups.len(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn cartouche_of_another_apple_account_is_left_alone() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
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
    let asked = h.developer_requests().len();

    let error = renew::renew(&h.env, &h.udid(), due()).await.expect_err("renewed another account's Cartouche");
    assert_eq!(error.kind, Kind::OtherTeam, "{error}");
    assert_eq!(h.developer_requests().len(), asked, "Apple was asked");
}

#[tokio::test(flavor = "multi_thread")]
async fn without_a_session_nothing_reaches_apple_or_the_iphone() {
    let h = Harness::new().await;
    let error = renew::renew(&h.env, &h.udid(), now()).await.expect_err("renewed without a session");
    assert_eq!(error.kind, Kind::NoSession);
    assert!(h.iphone.log().is_empty(), "{:#?}", h.iphone.log());
    assert!(h.developer_requests().is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn an_iphone_that_is_not_there_is_said_so() {
    let h = installed().await;
    let error = renew::renew(&h.env, "00008150-000000000000FFFF", now()).await.err().unwrap();
    assert_eq!(error.kind, Kind::NoIphone);
    h.usbmuxd.unplug(&h.iphone);
    let error = renew::renew(&h.env, &h.udid(), now()).await.err().unwrap();
    assert_eq!(error.kind, Kind::NoIphone);
}

#[tokio::test(flavor = "multi_thread")]
async fn an_iphone_without_cartouche_is_said_so() {
    let h = Harness::new().await;
    h.sign_in().await;
    let error = renew::renew(&h.env, &h.udid(), now()).await.err().unwrap();
    assert_eq!(error.kind, Kind::NoCartouche);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_profile_the_iphone_refuses_is_said_so() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
    let before = h.runs_until();
    h.iphone.state().fail_profile_install = Some(misagent::REFUSED);
    let error = renew::renew(&h.env, &h.udid(), due()).await.err().unwrap();
    assert_eq!(error.kind, Kind::ProfileRefused, "{error}");
    assert_eq!(h.runs_until(), before);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_session_apple_ended_asks_for_the_password_and_changes_nothing() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
    let before = h.runs_until();
    h.apple.end_session(EMAIL);
    let error = renew::renew(&h.env, &h.udid(), due()).await.err().unwrap();
    assert_eq!(error.kind, Kind::SessionEnded, "{error}");
    assert_eq!(h.runs_until(), before);
    // Signed in again, it renews.
    h.sign_in().await;
    assert!(renew::renew(&h.env, &h.udid(), due()).await.unwrap().renewed);
}

#[tokio::test(flavor = "multi_thread")]
async fn an_ended_xcode_token_is_no_reason_to_ask_for_the_password() {
    let h = installed().await;
    h.age_cartouche(HOUR, false);
    let sign_ins = h.sign_ins();
    h.apple.end_xcode_tokens(EMAIL);
    let renewal = renew::renew(&h.env, &h.udid(), due()).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(renewal.renewed);
    assert!(renewal.refreshed_session);
    assert_eq!(h.sign_ins(), sign_ins);
}
