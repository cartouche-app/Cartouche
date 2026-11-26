//! Cartouche's IPA, for an install over the copy on the iPhone: the newest
//! release its source lists, the one Cartouche's built-in SideStore updates
//! from (CARTOUCHE_SIDESTORE_SOURCE_URL in app/config.env), downloaded from
//! the repository's releases on GitHub alone and checked against the
//! source's size and SHA-256, as the Cartouche Installer does
//! (installer/src-tauri/src/cartouche.rs).

use std::path::Path;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;

use crate::{BUNDLE_ID, Environment, Failure, Kind, Result, Stage};

/// The source Cartouche's built-in SideStore reads for its updates.
pub const SOURCE_URL: &str =
    "https://raw.githubusercontent.com/clabeuhtegrite/Cartouche/main/app/sidestore-source.json";

/// Only GitHub serves Cartouche's IPA, from the repository's releases.
pub const DOWNLOAD_PREFIX: &str = "https://github.com/clabeuhtegrite/Cartouche/releases/download/";

/// A release of Cartouche, as its source lists it.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Release {
    pub version: String,
    #[serde(rename(deserialize = "downloadURL"))]
    pub download_url: String,
    pub size: u64,
    pub sha256: String,
}

#[derive(Deserialize)]
struct Source {
    apps: Vec<SourceApp>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SourceApp {
    bundle_identifier: String,
    versions: Vec<Release>,
}

fn download_failure(message: impl Into<String>) -> Failure {
    Failure::new(Kind::Download, Stage::Download, message)
}

/// "0.16.2" as numbers, for the newest: a part's digits alone.
pub fn version_key(version: &str) -> Vec<u64> {
    version
        .split('.')
        .map(|part| part.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().unwrap_or(0))
        .collect()
}

/// The highest version SOURCE lists for Cartouche, from GitHub's releases.
pub fn latest_in(source: &str) -> Result<Release> {
    let source: Source =
        serde_json::from_str(source).map_err(|e| download_failure(format!("Cartouche's source does not read: {e}")))?;
    let release = source
        .apps
        .into_iter()
        .filter(|app| app.bundle_identifier == BUNDLE_ID)
        .flat_map(|app| app.versions)
        .max_by_key(|release| version_key(&release.version))
        .ok_or_else(|| download_failure("Cartouche's source lists no release"))?;
    if !release.download_url.starts_with(DOWNLOAD_PREFIX) {
        return Err(download_failure(format!(
            "Cartouche's source gives an IPA outside its GitHub releases: {}",
            release.download_url
        )));
    }
    Ok(release)
}

fn network(e: reqwest::Error) -> Failure {
    if e.is_connect() || e.is_timeout() {
        Failure::new(Kind::Network, Stage::Download, e.to_string())
    } else {
        download_failure(e.to_string())
    }
}

/// The newest Cartouche its source lists.
pub async fn latest(env: &Environment) -> Result<Release> {
    let response = env.http.get(SOURCE_URL).send().await.map_err(network)?;
    if !response.status().is_success() {
        return Err(download_failure(format!("Cartouche's source answered HTTP {}", response.status())));
    }
    let text = response.text().await.map_err(network)?;
    latest_in(&text)
}

/// Downloads RELEASE's IPA to DEST, checked against its size and SHA-256;
/// PROGRESS gets the fraction received. Nothing is left at DEST when it
/// fails.
pub async fn download<F: FnMut(f64)>(env: &Environment, release: &Release, dest: &Path, progress: F) -> Result<()> {
    let outcome = fetch(env, release, dest, progress).await;
    if outcome.is_err() {
        let _ = tokio::fs::remove_file(dest).await;
    }
    outcome
}

async fn fetch<F: FnMut(f64)>(env: &Environment, release: &Release, dest: &Path, mut progress: F) -> Result<()> {
    let mut response = env.http.get(&release.download_url).send().await.map_err(network)?;
    if !response.status().is_success() {
        return Err(download_failure(format!(
            "The download of Cartouche {} answered HTTP {}",
            release.version,
            response.status()
        )));
    }
    let written = |e: std::io::Error| crate::internal(format!("{}: {e}", dest.display()));
    let mut file = tokio::fs::File::create(dest).await.map_err(written)?;
    let mut hasher = Sha256::new();
    let mut received: u64 = 0;
    while let Some(chunk) = response.chunk().await.map_err(network)? {
        received += chunk.len() as u64;
        if received > release.size {
            return Err(download_failure(format!(
                "Cartouche {} is larger than its source says ({} bytes)",
                release.version, release.size
            )));
        }
        hasher.update(&chunk);
        file.write_all(&chunk).await.map_err(written)?;
        progress(received as f64 / release.size.max(1) as f64);
    }
    file.flush().await.map_err(written)?;
    if received != release.size {
        return Err(download_failure(format!(
            "Cartouche {} came short: {received} bytes of {}",
            release.version, release.size
        )));
    }
    let digest = hex::encode(hasher.finalize());
    if !digest.eq_ignore_ascii_case(&release.sha256) {
        return Err(download_failure(format!(
            "Cartouche {} is not the file its source lists: SHA-256 {digest}, expected {}",
            release.version, release.sha256
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(versions: &[(&str, &str)]) -> String {
        let versions: Vec<serde_json::Value> = versions
            .iter()
            .map(|(version, url)| {
                serde_json::json!({ "version": version, "downloadURL": url, "size": 10, "sha256": "00" })
            })
            .collect();
        serde_json::json!({ "apps": [
            { "bundleIdentifier": "io.github.clabeuhtegrite.cartouche.other", "versions": [
                { "version": "9.0.0", "downloadURL": format!("{DOWNLOAD_PREFIX}v9.0.0/Other.ipa"), "size": 1, "sha256": "00" }
            ] },
            { "bundleIdentifier": BUNDLE_ID, "versions": versions },
        ] })
        .to_string()
    }

    #[test]
    fn the_newest_of_cartouches_releases() {
        let url = |v: &str| format!("{DOWNLOAD_PREFIX}v{v}/Cartouche-{v}.ipa");
        let listed = source(&[("0.9.0", &url("0.9.0")), ("0.16.2", &url("0.16.2")), ("0.16.10", &url("0.16.10"))]);
        let release = latest_in(&listed).expect("a release");
        assert_eq!(release.version, "0.16.10");
        assert_eq!(release.download_url, url("0.16.10"));
    }

    #[test]
    fn never_an_ipa_from_elsewhere() {
        let listed = source(&[("0.16.2", "https://example.com/Cartouche-0.16.2.ipa")]);
        let failure = latest_in(&listed).expect_err("an IPA outside GitHub's releases");
        assert_eq!(failure.kind, Kind::Download);
        assert_eq!(latest_in(&source(&[])).expect_err("no release").kind, Kind::Download);
        assert_eq!(latest_in("not json").expect_err("no source").kind, Kind::Download);
    }

    #[test]
    fn versions_by_their_numbers() {
        assert!(version_key("0.16.10") > version_key("0.16.2"));
        assert!(version_key("1.0") > version_key("0.99.99"));
        assert_eq!(version_key("0.16.2-beta"), vec![0, 16, 2]);
    }
}
