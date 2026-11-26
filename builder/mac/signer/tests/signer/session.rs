//! Signing in once on the Mac, then never again with the password while
//! Apple keeps the session (the player, 26 November: "sans garder le mot de
//! passe, mais faut pas que ca lui demande son mot de passe a chaque fois").

use cartouche_signer::{Kind, session};

use crate::harness::*;

#[tokio::test(flavor = "multi_thread")]
async fn signs_in_with_a_code_and_keeps_no_password() {
    let h = Harness::new().await;
    let info = h.sign_in().await;
    assert!(info.signed_in);
    assert_eq!(info.email.as_deref(), Some(EMAIL));
    assert_eq!(info.team_id.as_deref(), Some(h.team_id.as_str()));

    let files = h.signer_files();
    assert!(files.iter().any(|(p, _)| p.ends_with("session.json")), "no session.json: {files:?}");
    for (path, data) in &files {
        let text = String::from_utf8_lossy(data);
        assert!(!text.contains(PASSWORD), "{} holds the password", path.display());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = |p: &std::path::Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&h.env.session_file()), 0o600);
        assert_eq!(mode(&h.env.folder), 0o700);
        assert_eq!(mode(&h.env.isideload_folder()), 0o700);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_wrong_password_is_said_so_and_keeps_nothing() {
    let h = Harness::new().await;
    let error = session::sign_in(&h.env, EMAIL, "Wrong-Horse-8", h.codes()).await.unwrap_err();
    assert_eq!(error.kind, Kind::WrongPassword, "{error}");
    assert!(!h.env.session_file().exists());
    assert!(!session::info(&h.env).unwrap().signed_in);
}

#[tokio::test(flavor = "multi_thread")]
async fn no_code_closes_the_sign_in() {
    let h = Harness::new().await;
    let cancel: session::CodeAsker = std::sync::Arc::new(|_| {
        use futures::FutureExt;
        async { Ok(isideload::auth::apple_account::TwoFactorCallbackResponse::Abort) }.boxed()
    });
    let error = session::sign_in(&h.env, EMAIL, PASSWORD, cancel).await.unwrap_err();
    assert_eq!(error.kind, Kind::Cancelled, "{error}");
    assert!(!h.env.session_file().exists());
}

#[tokio::test(flavor = "multi_thread")]
async fn the_session_comes_back_without_the_password() {
    let h = Harness::new().await;
    h.sign_in().await;
    let sign_ins = h.sign_ins();
    let resumed = session::resume(&h.env).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert_eq!(resumed.team.team_id, h.team_id);
    assert!(!resumed.refreshed);
    assert_eq!(h.sign_ins(), sign_ins, "signed in again");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_new_xcode_token_comes_from_the_session_without_the_password() {
    let h = Harness::new().await;
    h.sign_in().await;
    let before = session::load(&h.env).unwrap().unwrap();
    let sign_ins = h.sign_ins();
    h.apple.end_xcode_tokens(EMAIL);

    let resumed = session::resume(&h.env).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
    assert!(resumed.refreshed);
    assert_eq!(h.sign_ins(), sign_ins, "signed in again");
    let after = session::load(&h.env).unwrap().unwrap();
    assert_ne!(after.xcode.token, before.xcode.token, "the new token is not kept");
    assert!(after.refreshed.is_some());
    // And the next time, that one serves.
    assert!(!session::resume(&h.env).await.unwrap().refreshed);
}

#[tokio::test(flavor = "multi_thread")]
async fn once_apple_ends_the_session_only_the_password_signs_in_again() {
    let h = Harness::new().await;
    h.sign_in().await;
    h.apple.end_session(EMAIL);
    let error = session::resume(&h.env).await.err().expect("resumed an ended session");
    assert_eq!(error.kind, Kind::SessionEnded, "{error}");
    // The session stays until the player signs in again: the app says
    // what to do, the signer forgets nothing on its own.
    assert!(session::info(&h.env).unwrap().signed_in);
    h.sign_in().await;
    session::resume(&h.env).await.unwrap_or_else(|e| panic!("{e}\n{}", h.report()));
}

#[tokio::test(flavor = "multi_thread")]
async fn signing_out_forgets_the_session() {
    let h = Harness::new().await;
    h.sign_in().await;
    session::sign_out(&h.env).unwrap();
    assert!(!session::info(&h.env).unwrap().signed_in);
    let error = session::resume(&h.env).await.err().expect("resumed without a session");
    assert_eq!(error.kind, Kind::NoSession);
    // Twice is no error.
    session::sign_out(&h.env).unwrap();
}
