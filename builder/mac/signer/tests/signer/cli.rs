//! The signer's command line, as the Mac app runs it (Signer.swift): its
//! lines of JSON, the password and the code it reads, how it ends.

use std::{
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    time::SystemTime,
};

use serde_json::{Value, json};

use crate::harness::*;

fn signer(h: &Harness, args: &[&str]) -> Command {
    // The authority the fake GitHub's certificates come from, for the
    // signer to trust it alone.
    let ca = h.dir.path().join("github-ca.der");
    std::fs::write(&ca, h.github.ca_der()).expect("GitHub's authority");
    let mut command = Command::new(env!("CARGO_BIN_EXE_cartouche-signer"));
    command
        .arg("--folder")
        .arg(&h.env.folder)
        .arg("--anisette")
        .arg(&h.env.anisette_url)
        .args(args)
        .env("USBMUXD_SOCKET_ADDRESS", h.usbmuxd.addr().to_string())
        .env("CARTOUCHE_SIGNER_TEST_APPLE_PROXY", h.apple.proxy_url())
        .env("CARTOUCHE_SIGNER_TEST_GITHUB_PROXY", h.github.proxy_url())
        .env("CARTOUCHE_SIGNER_TEST_GITHUB_CA", &ca)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    command
}

/// Runs the signer to its end: its lines, its last line's answer, its exit.
async fn run(h: &Harness, args: &[&str]) -> (Vec<Value>, i32) {
    let output = tokio::task::spawn_blocking({
        let mut command = signer(h, args);
        move || command.stdin(Stdio::null()).output().expect("the signer")
    })
    .await
    .unwrap();
    let lines: Vec<Value> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("not JSON: {l}: {e}")))
        .collect();
    assert!(!lines.is_empty(), "the signer said nothing: {}", String::from_utf8_lossy(&output.stderr));
    (lines, output.status.code().unwrap_or(-1))
}

#[tokio::test(flavor = "multi_thread")]
async fn signs_in_with_the_password_and_the_code_it_asks_for() {
    let h = Harness::new().await;
    let code = h.account.code.clone();
    let mut command = signer(&h, &["sign-in", "--email", EMAIL]);
    let (lines, status) = tokio::task::spawn_blocking(move || {
        let mut child = command.stdin(Stdio::piped()).spawn().expect("the signer");
        let mut input = child.stdin.take().unwrap();
        let mut lines = Vec::new();
        for line in BufReader::new(child.stdout.take().unwrap()).lines() {
            let line: Value = serde_json::from_str(&line.unwrap()).unwrap();
            match line["event"].as_str() {
                Some("password") => writeln!(input, "{}", json!({ "password": PASSWORD })).unwrap(),
                Some("code") => writeln!(input, "{}", json!({ "code": code })).unwrap(),
                _ => {}
            }
            lines.push(line);
        }
        (lines, child.wait().unwrap().code())
    })
    .await
    .unwrap();
    let events: Vec<&str> = lines.iter().filter_map(|l| l["event"].as_str()).collect();
    assert_eq!(events, ["password", "code"], "{lines:#?}\n{}", h.report());
    let result = &lines.last().unwrap()["result"];
    assert_eq!(result["signedIn"], true, "{lines:#?}");
    assert_eq!(result["teamId"], h.team_id.as_str());
    assert_eq!(status, Some(0));
    // Nothing it wrote or keeps holds the password.
    for line in &lines {
        assert!(!line.to_string().contains(PASSWORD));
    }
    for (path, data) in h.signer_files() {
        assert!(!String::from_utf8_lossy(&data).contains(PASSWORD), "{}", path.display());
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn without_a_password_it_signs_nothing_in() {
    let h = Harness::new().await;
    let (lines, status) = run(&h, &["sign-in", "--email", EMAIL]).await;
    assert_eq!(lines.last().unwrap()["error"]["kind"], "cancelled", "{lines:#?}");
    assert_eq!(status, 1);
    assert!(!h.env.session_file().exists());
}

#[tokio::test(flavor = "multi_thread")]
async fn lists_the_iphone_and_until_when_cartouche_opens() {
    let h = Harness::new().await;
    h.sign_in().await;
    h.install_cartouche().await;
    let (lines, status) = run(&h, &["devices"]).await;
    assert_eq!(status, 0, "{lines:#?}");
    let iphones = lines.last().unwrap()["result"]["iphones"].as_array().unwrap().clone();
    assert_eq!(iphones.len(), 1, "{iphones:#?}");
    let iphone = &iphones[0];
    assert_eq!(iphone["udid"], h.udid().as_str());
    assert_eq!(iphone["name"], h.iphone.config().name.as_str());
    assert_eq!(iphone["link"], "usb");
    let copy = &iphone["cartouche"][0];
    assert_eq!(copy["bundleId"], h.bundle_id().as_str());
    assert_eq!(copy["version"], "0.16.2");
    assert_eq!(copy["teamId"], h.team_id.as_str());
    assert_eq!(copy["due"], "not-yet");
    let expires = cartouche_signer::protocol::time::parse(copy["expires"].as_str().unwrap());
    assert!(about(expires, h.runs_until().unwrap()), "{expires:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn renews_and_answers_as_the_app_reads_it() {
    let h = Harness::new().await;
    h.sign_in().await;
    h.install_cartouche().await;
    h.age_cartouche(HOUR, false);
    let udid = h.udid();
    let (lines, status) = run(&h, &["renew", "--udid", &udid, "--if-due"]).await;
    assert_eq!(status, 0, "{lines:#?}\n{}", h.report());
    let result = &lines.last().unwrap()["result"];
    assert_eq!(result["renewed"], true);
    assert_eq!(result["due"], "now");
    assert_eq!(result["link"], "usb");
    assert!(about(h.runs_until(), SystemTime::now() + 7 * DAY));

    let (lines, status) = run(&h, &["session"]).await;
    assert_eq!(status, 0);
    let session = &lines.last().unwrap()["result"];
    assert_eq!(session["signedIn"], true);
    assert_eq!(session["email"], EMAIL);
    // What the app shows of the session: never its tokens.
    let text = session.to_string();
    assert!(!text.contains("token") && !text.contains("idms") && !text.contains("adsid"), "{text}");
}

#[tokio::test(flavor = "multi_thread")]
async fn installs_over_cartouche_with_its_progress_as_the_app_reads_it() {
    let h = Harness::new().await;
    h.sign_in().await;
    h.install_cartouche().await;
    h.apple.with_account(EMAIL, |a| a.team.certificates.clear());
    h.publish_cartouche("0.17.1");
    let udid = h.udid();
    let (lines, status) = run(&h, &["reinstall", "--udid", &udid]).await;
    assert_eq!(status, 0, "{lines:#?}\n{}", h.report());
    let result = &lines.last().unwrap()["result"];
    assert_eq!(result["reinstalled"], true);
    assert_eq!(result["version"], "0.17.1");
    assert_eq!(result["previousVersion"], "0.16.2");
    assert_eq!(result["bundleId"], h.bundle_id().as_str());
    assert!(result["expires"].is_string(), "{result}");
    assert_eq!(h.cartouche_version().as_deref(), Some("0.17.1"));
    // Each step as it goes, a hundredth at most each time.
    let progress: Vec<&Value> = lines.iter().filter(|l| l["event"] == "progress").collect();
    for step in ["download", "sign", "install"] {
        let fractions: Vec<f64> =
            progress.iter().filter(|l| l["step"] == step).map(|l| l["fraction"].as_f64().unwrap()).collect();
        assert!(!fractions.is_empty(), "no {step} in {progress:#?}");
        assert!(fractions.windows(2).all(|w| w[0] < w[1]), "{step}: {fractions:?}");
        assert!(fractions.len() <= 101, "{step}: {} lines", fractions.len());
    }

    // Without a certificate left, it says so and installs nothing.
    h.apple.with_account(EMAIL, |a| a.team.certificates.clear());
    h.apple.add_foreign_certificate(EMAIL, "AltServer");
    h.apple.add_foreign_certificate(EMAIL, "iPad");
    let (lines, status) = run(&h, &["reinstall", "--udid", &udid]).await;
    assert_eq!(status, 1);
    assert_eq!(lines.last().unwrap()["error"]["kind"], "no-certificate-left", "{lines:#?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn each_failure_ends_with_its_kind() {
    let h = Harness::new().await;
    let (lines, status) = run(&h, &["renew", "--udid", "00008150-000000000000FFFF"]).await;
    assert_eq!(lines.last().unwrap()["error"]["kind"], "no-session");
    assert_eq!(status, 1);
    h.sign_in().await;
    let (lines, _) = run(&h, &["renew", "--udid", "00008150-000000000000FFFF"]).await;
    assert_eq!(lines.last().unwrap()["error"]["kind"], "no-iphone");
    assert_eq!(lines.last().unwrap()["error"]["stage"], "iphone");
    let (lines, status) = run(&h, &["renew"]).await;
    assert_eq!(lines.last().unwrap()["error"]["kind"], "usage");
    assert_eq!(status, 2);
    let (lines, status) = run(&h, &["sign-out"]).await;
    assert_eq!(lines.last().unwrap()["result"]["signedIn"], false);
    assert_eq!(status, 0);
    let (lines, status) = run(&h, &["version"]).await;
    assert_eq!(lines.last().unwrap()["result"]["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(status, 0);
}
