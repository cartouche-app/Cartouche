//! The player's Apple session on this Mac: signed in once with the
//! password and a code, then kept as Apple's tokens alone, in session.json,
//! readable by the player's account only. Never the password, which goes
//! no further than Apple, and never the keychain: the Mac app is signed ad
//! hoc, and macOS would ask for it again after each update.
//!
//! Apple's developer services take an Xcode token, which ends after some
//! days; a new one comes from the session it was given in, without the
//! password, as long as Apple keeps that session. Once Apple ends it, only
//! the password signs in again (`Kind::SessionEnded`).

use std::{
    io::Write,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use base64::{Engine, prelude::BASE64_STANDARD};
use futures::future::BoxFuture;
use isideload::{
    anisette::{AnisetteClientInfo, remote_v3::RemoteV3AnisetteProvider},
    auth::apple_account::{AppToken, AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse},
    dev::{
        developer_session::DeveloperSession,
        teams::{DeveloperTeam, TeamsApi},
    },
    util::fs_storage::FsStorage,
};
use rootcause::Report;
use serde::{Deserialize, Serialize};

use crate::{Environment, Failure, Kind, Result, Stage, internal, private, protocol::time};

/// Asks the player for the two-factor code, as the app shows it.
pub type CodeAsker = Arc<
    dyn Fn(TwoFactorCallbackParams) -> BoxFuture<'static, std::result::Result<TwoFactorCallbackResponse, Report>>
        + Send
        + Sync,
>;

/// How long before its end an Xcode token is taken as ended: a renewal
/// that starts with it does not see it end on the way.
const TOKEN_MARGIN: Duration = Duration::from_secs(10 * 60);

/// session.json.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedSession {
    pub version: u32,
    pub email: String,
    pub adsid: String,
    pub team_id: String,
    pub team_name: Option<String>,
    #[serde(with = "time")]
    pub signed_in: SystemTime,
    /// When Apple last gave this Mac a new Xcode token without the password.
    #[serde(with = "time::option", default)]
    pub refreshed: Option<SystemTime>,
    pub xcode: SavedToken,
    /// What gives a new Xcode token without the password: the session's
    /// token and keys, as Apple sent them at the sign-in.
    pub idms: SavedIdms,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedToken {
    pub token: String,
    pub duration: u64,
    /// Its end, in milliseconds since 1970, as Apple gives it.
    pub expiry: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SavedIdms {
    pub token: String,
    pub sk: String,
    pub c: String,
}

impl SavedToken {
    fn token(&self) -> AppToken {
        AppToken { token: self.token.clone(), duration: self.duration, expiry: self.expiry }
    }

    fn ends_soon(&self, now: SystemTime) -> bool {
        let now_ms = now.duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
        self.expiry <= now_ms + TOKEN_MARGIN.as_millis() as u64
    }
}

impl From<AppToken> for SavedToken {
    fn from(t: AppToken) -> Self {
        SavedToken { token: t.token, duration: t.duration, expiry: t.expiry }
    }
}

/// What the app shows of the session: never its tokens.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionInfo {
    pub signed_in: bool,
    pub email: Option<String>,
    pub team_id: Option<String>,
    pub team_name: Option<String>,
    #[serde(with = "time::option")]
    pub since: Option<SystemTime>,
    #[serde(with = "time::option")]
    pub refreshed: Option<SystemTime>,
}

impl SessionInfo {
    fn of(saved: Option<&SavedSession>) -> Self {
        SessionInfo {
            signed_in: saved.is_some(),
            email: saved.map(|s| s.email.clone()),
            team_id: saved.map(|s| s.team_id.clone()),
            team_name: saved.and_then(|s| s.team_name.clone()),
            since: saved.map(|s| s.signed_in),
            refreshed: saved.and_then(|s| s.refreshed),
        }
    }
}

/// A session ready for Apple's developer services.
pub struct Resumed {
    pub developer: DeveloperSession,
    pub team: DeveloperTeam,
    pub saved: SavedSession,
    /// Whether Apple gave a new Xcode token on the way.
    pub refreshed: bool,
}

/// The anisette machine of this Mac, kept in the signer's folder so that
/// Apple knows it again, as the Installer does with its own.
fn anisette(env: &Environment) -> Result<RemoteV3AnisetteProvider> {
    crate::init();
    let url = if env.anisette_url.starts_with("http") {
        env.anisette_url.clone()
    } else {
        format!("https://{}", env.anisette_url)
    };
    let provider =
        RemoteV3AnisetteProvider::new(&url, Box::new(FsStorage::new(env.isideload_folder())), "0".to_string())
            .map_err(|r| Failure::new(Kind::Anisette, Stage::Session, r.to_string()))?;
    // As the Installer: GrandSlam expects the "Mac OS X" label.
    Ok(provider.set_client_info_override(Some(AnisetteClientInfo {
        client_info: "<Mac15,7> <Mac OS X;27.0;26A5378j> <com.apple.AuthKit/1 (com.apple.akd/1.0)>".to_string(),
        user_agent: "akd/1.0 CFNetwork/811.5.4".to_string(),
    })))
}

/// Signs in with the password and, when Apple asks, a code, and keeps the
/// session. The password is not kept.
pub async fn sign_in(env: &Environment, email: &str, password: &str, ask: CodeAsker) -> Result<SessionInfo> {
    env.ensure_folder()?;
    let email = email.trim().to_lowercase();
    let at_sign_in = |r: Report| Failure::from_apple(&r, Stage::Session, true);
    let two_factor = move |params: TwoFactorCallbackParams| ask(params);
    let mut account = AppleAccount::builder(&email)
        .proxy_url(env.apple_proxy.clone())
        .anisette_provider(anisette(env)?)
        .login(password, two_factor)
        .await
        .map_err(at_sign_in)?;
    let token = account.get_app_token("xcode.auth").await.map_err(at_sign_in)?;
    let spd = account.spd.clone().ok_or_else(|| internal("Apple sent no session"))?;
    let text = |key: &str| spd.get(key).and_then(|v| v.as_string()).map(str::to_string);
    let data = |key: &str| spd.get(key).and_then(|v| v.as_data()).map(|d| BASE64_STANDARD.encode(d));
    let (Some(adsid), Some(idms), Some(sk), Some(c)) = (text("adsid"), text("GsIdmsToken"), data("sk"), data("c"))
    else {
        return Err(internal("Apple's session lacks its tokens"));
    };
    let mut developer = DeveloperSession::new(
        token.clone(),
        adsid.clone(),
        account.grandslam_client.clone(),
        account.anisette_generator.clone(),
    );
    let team = first_team(&mut developer, None).await?;
    let saved = SavedSession {
        version: 1,
        email,
        adsid,
        team_id: team.team_id.clone(),
        team_name: team.name.clone(),
        signed_in: SystemTime::now(),
        refreshed: None,
        xcode: token.into(),
        idms: SavedIdms { token: idms, sk, c },
    };
    save(env, &saved)?;
    Ok(SessionInfo::of(Some(&saved)))
}

/// The session, ready for Apple's developer services, without the
/// password: a new Xcode token from the session when the last one ended.
pub async fn resume(env: &Environment) -> Result<Resumed> {
    let mut saved =
        load(env)?.ok_or_else(|| Failure::new(Kind::NoSession, Stage::Session, "No Apple Account on this Mac"))?;
    let mut account = AppleAccount::builder(&saved.email)
        .proxy_url(env.apple_proxy.clone())
        .anisette_provider(anisette(env)?)
        .build()
        .await
        .map_err(|r| Failure::from_apple(&r, Stage::Session, false))?;
    let mut refreshed = false;
    if saved.xcode.ends_soon(SystemTime::now()) {
        refresh(&mut account, &mut saved).await?;
        refreshed = true;
    }
    let developer_session = |saved: &SavedSession, account: &AppleAccount| {
        DeveloperSession::new(
            saved.xcode.token(),
            saved.adsid.clone(),
            account.grandslam_client.clone(),
            account.anisette_generator.clone(),
        )
    };
    let mut developer = developer_session(&saved, &account);
    let team = match first_team(&mut developer, Some(&saved.team_id)).await {
        Ok(team) => team,
        Err(f) if f.kind == Kind::SessionEnded && !refreshed => {
            refresh(&mut account, &mut saved).await?;
            refreshed = true;
            developer = developer_session(&saved, &account);
            first_team(&mut developer, Some(&saved.team_id)).await?
        }
        Err(f) => return Err(f),
    };
    if team.team_id != saved.team_id || team.name != saved.team_name {
        saved.team_id = team.team_id.clone();
        saved.team_name = team.name.clone();
        save(env, &saved)?;
    }
    if refreshed {
        saved.refreshed = Some(SystemTime::now());
        save(env, &saved)?;
    }
    Ok(Resumed { developer, team, saved, refreshed })
}

/// A new Xcode token, from the session alone.
async fn refresh(account: &mut AppleAccount, saved: &mut SavedSession) -> Result<()> {
    let decode = |b64: &str| BASE64_STANDARD.decode(b64).map_err(|e| internal(format!("session.json: {e}")));
    let mut spd = plist::Dictionary::new();
    spd.insert("adsid".into(), saved.adsid.clone().into());
    spd.insert("GsIdmsToken".into(), saved.idms.token.clone().into());
    spd.insert("sk".into(), plist::Value::Data(decode(&saved.idms.sk)?));
    spd.insert("c".into(), plist::Value::Data(decode(&saved.idms.c)?));
    account.spd = Some(spd);
    let token =
        account.get_app_token("xcode.auth").await.map_err(|r| Failure::from_apple(&r, Stage::Session, false))?;
    saved.xcode = token.into();
    Ok(())
}

/// The account's team: the one it had, or the first, as the Installer
/// takes it.
async fn first_team(developer: &mut DeveloperSession, had: Option<&str>) -> Result<DeveloperTeam> {
    let teams = developer.list_teams().await.map_err(|r| Failure::from_apple(&r, Stage::Apple, false))?;
    let found = had.and_then(|id| teams.iter().find(|t| t.team_id == id).cloned());
    found
        .or_else(|| teams.into_iter().next())
        .ok_or_else(|| Failure::new(Kind::Apple, Stage::Apple, "The Apple Account has no developer team"))
}

/// The session, as the app shows it, without reaching Apple.
pub fn info(env: &Environment) -> Result<SessionInfo> {
    Ok(SessionInfo::of(load(env)?.as_ref()))
}

/// Forgets the session. The anisette machine stays: Apple knows this Mac
/// at the next sign-in.
pub fn sign_out(env: &Environment) -> Result<()> {
    match std::fs::remove_file(env.session_file()) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(internal(format!("session.json: {e}"))),
    }
}

pub fn load(env: &Environment) -> Result<Option<SavedSession>> {
    match std::fs::read(env.session_file()) {
        Ok(data) => {
            serde_json::from_slice(&data).map(Some).map_err(|e| internal(format!("session.json does not read: {e}")))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(internal(format!("session.json: {e}"))),
    }
}

/// Writes session.json whole, readable by the player's account alone.
fn save(env: &Environment, saved: &SavedSession) -> Result<()> {
    env.ensure_folder()?;
    let path = env.session_file();
    let incoming = env.folder.join("session.json.incoming");
    let data = serde_json::to_vec_pretty(saved).map_err(|e| internal(e.to_string()))?;
    {
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
        let mut file = options.open(&incoming).map_err(|e| internal(format!("session.json: {e}")))?;
        file.write_all(&data).map_err(|e| internal(format!("session.json: {e}")))?;
        file.sync_all().map_err(|e| internal(format!("session.json: {e}")))?;
    }
    private(&incoming, 0o600)?;
    std::fs::rename(&incoming, &path).map_err(|e| internal(format!("session.json: {e}")))
}
