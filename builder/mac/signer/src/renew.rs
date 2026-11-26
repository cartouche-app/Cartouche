//! Renewing Cartouche from the Mac, as SideStore renews it on the iPhone: a
//! new provisioning profile for its App ID, which Apple makes for the
//! iPhone and the account's certificates, installed by misagent. Nothing is
//! signed or installed again, so Cartouche keeps its games, its saves and
//! its Increased Memory Limit, and no App ID is taken while Cartouche's
//! lives.
//!
//! The profile is installed only when it opens Cartouche: for its App ID,
//! this iPhone, a certificate of the profile Cartouche runs under now, and
//! every entitlement Cartouche was signed with. Without the certificate,
//! revoked since, a profile does not open Cartouche, and only an install
//! over it does (`Kind::CertificateGone`, reinstall.rs): the signer never
//! revokes one.

use std::time::{Instant, SystemTime};

use isideload::dev::{
    app_groups::AppGroupsApi,
    app_ids::{AppId, AppIdsApi},
    developer_session::DeveloperSession,
    devices::DevicesApi,
    teams::DeveloperTeam,
};
use serde::Serialize;

use crate::{
    APP_GROUP, Environment, Failure, Kind, Result, Stage,
    iphone::{self, Cartouche, RenewalRecord},
    profile::{self, Profile},
    protocol::time,
    rules::{self, Due},
    session::{self, Resumed},
};

#[derive(Clone, Copy, Debug)]
pub struct Options {
    /// Only in Cartouche's last two days, or once it has expired.
    pub only_if_due: bool,
    pub now: SystemTime,
}

impl Default for Options {
    fn default() -> Self {
        Options { only_if_due: false, now: SystemTime::now() }
    }
}

/// What a renewal did.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Renewal {
    pub renewed: bool,
    pub bundle_id: String,
    /// Until when Cartouche opened before, and after.
    #[serde(with = "time::option")]
    pub before: Option<SystemTime>,
    #[serde(with = "time::option")]
    pub expires: Option<SystemTime>,
    /// Whether it was due, before.
    #[serde(flatten)]
    pub due: Due,
    /// Whether Cartouche's App ID had to be registered again, which takes
    /// one of the ten of the week.
    pub registered_app_id: bool,
    /// Whether Apple gave the session a new Xcode token on the way.
    pub refreshed_session: bool,
    /// Whether Cartouche's Documents have the renewal's date.
    pub recorded: bool,
    /// "usb" or "network".
    pub link: &'static str,
    pub seconds: f64,
}

/// Renews Cartouche on the iPhone UDID, if it is due or OPTIONS say so.
pub async fn renew(env: &Environment, udid: &str, options: Options) -> Result<Renewal> {
    let started = Instant::now();
    // The session's team first, from this Mac alone: without one, nothing
    // reaches Apple.
    let saved = session::load(env)?
        .ok_or_else(|| Failure::new(Kind::NoSession, Stage::Session, "No Apple Account on this Mac"))?;
    let (device, provider) = iphone::connect(env, udid).await?;
    let link = iphone::link(&device);
    let (copies, held) = iphone::cartouches(&provider, &device.udid, options.now).await?;
    let copy = choose(&copies, &saved.team_id)?;
    let current = profile::latest_for(&held, &copy.bundle_id, &device.udid).cloned();
    let before = current.as_ref().map(|p| p.expires);
    let due = rules::due(before.unwrap_or(SystemTime::UNIX_EPOCH), options.now);
    let mut renewal = Renewal {
        renewed: false,
        bundle_id: copy.bundle_id.clone(),
        before,
        expires: before,
        due,
        registered_app_id: false,
        refreshed_session: false,
        recorded: false,
        link,
        seconds: 0.0,
    };
    if options.only_if_due && !due.is_due() {
        renewal.seconds = started.elapsed().as_secs_f64();
        return Ok(renewal);
    }

    let mut resumed = session::resume(env).await?;
    renewal.refreshed_session = resumed.refreshed;
    if resumed.team.team_id != copy.team_id.clone().unwrap_or_default() {
        return Err(other_team());
    }
    let (name, _) = iphone::describe(&provider).await.unwrap_or((None, None));
    let (fresh, registered) = new_profile(&mut resumed, copy, current.as_ref(), &device.udid, name.as_deref()).await?;
    renewal.registered_app_id = registered;

    iphone::install_profile(&provider, &fresh).await?;
    // What the iPhone holds now: the new profile counts once it lists it.
    let held = iphone::profiles(&provider).await?;
    let now_runs = profile::latest_for(&held, &copy.bundle_id, &device.udid).map(|p| p.expires);
    if now_runs < Some(fresh.expires) {
        return Err(Failure::new(
            Kind::ProfileRefused,
            Stage::Iphone,
            "The iPhone does not list Cartouche's new profile",
        ));
    }
    renewal.renewed = true;
    renewal.expires = now_runs;
    let record = RenewalRecord {
        bundle_identifier: copy.bundle_id.clone(),
        expiration_date: fresh.expires,
        refreshed_date: SystemTime::now(),
        by: "mac",
    };
    // Cartouche renewed opens anyway: its date on the iPhone is a nicety.
    match iphone::write_record(&provider, &record).await {
        Ok(()) => renewal.recorded = true,
        Err(e) => tracing::warn!("The renewal's date is not in Cartouche's Documents: {e}"),
    }
    renewal.seconds = started.elapsed().as_secs_f64();
    Ok(renewal)
}

pub(crate) fn other_team() -> Failure {
    Failure::new(
        Kind::OtherTeam,
        Stage::Session,
        "Cartouche on this iPhone was installed with another Apple Account than this Mac's",
    )
}

/// The copy of Cartouche the session's team signed.
pub(crate) fn choose<'a>(copies: &'a [Cartouche], team_id: &str) -> Result<&'a Cartouche> {
    if copies.is_empty() {
        return Err(Failure::new(Kind::NoCartouche, Stage::Iphone, "Cartouche is not on this iPhone"));
    }
    copies.iter().find(|c| c.team_id.as_deref() == Some(team_id)).ok_or_else(other_team)
}

/// A new profile for COPY that opens it where CURRENT does, and whether its
/// App ID had to be registered again.
async fn new_profile(
    resumed: &mut Resumed,
    copy: &Cartouche,
    current: Option<&Profile>,
    udid: &str,
    name: Option<&str>,
) -> Result<(Profile, bool)> {
    let apple = |r: rootcause::Report| Failure::from_apple(&r, Stage::Apple, false);
    let team = resumed.team.clone();
    let developer = &mut resumed.developer;
    let (mut app_id, registered) = app_id(developer, &team, &copy.bundle_id).await?;
    let mut fixed = registered;
    if registered {
        set_up(developer, &team, &mut app_id).await?;
    }
    let mut registered_device = false;
    loop {
        let downloaded = developer.download_team_provisioning_profile(&team, &app_id, None).await.map_err(apple)?;
        let fresh = Profile::parse(downloaded.encoded_profile.as_ref())
            .ok_or_else(|| Failure::new(Kind::Apple, Stage::Apple, "Apple's profile does not read"))?;
        if !fresh.is_for(&copy.bundle_id) {
            return Err(Failure::new(
                Kind::Apple,
                Stage::Apple,
                format!("Apple's profile is for {}", fresh.application_identifier),
            ));
        }
        if !fresh.lists_device(udid) {
            if registered_device {
                return Err(Failure::new(Kind::Apple, Stage::Apple, "Apple's profile does not list this iPhone"));
            }
            developer.ensure_device_registered(&team, name.unwrap_or("iPhone"), udid, None).await.map_err(apple)?;
            registered_device = true;
            continue;
        }
        let Some(current) = current else {
            return Ok((fresh, registered));
        };
        if !fresh.shares_a_certificate_with(current) {
            return Err(Failure::new(
                Kind::CertificateGone,
                Stage::Apple,
                "The certificate Cartouche was signed with is no longer on the Apple Account",
            ));
        }
        let lacking = fresh.lacks_entitlements_of(current);
        if lacking.is_empty() {
            return Ok((fresh, registered));
        }
        if fixed {
            return Err(Failure::new(
                Kind::Apple,
                Stage::Apple,
                format!("Apple's profile lacks what Cartouche was signed with: {}", lacking.join(", ")),
            ));
        }
        tracing::info!("Cartouche's App ID lacks {}: setting it up again", lacking.join(", "));
        set_up(developer, &team, &mut app_id).await?;
        fixed = true;
    }
}

/// Cartouche's App ID, registered again if it is gone (a free account's
/// expire), as the Installer registers it.
async fn app_id(developer: &mut DeveloperSession, team: &DeveloperTeam, bundle_id: &str) -> Result<(AppId, bool)> {
    let apple = |r: rootcause::Report| Failure::from_apple(&r, Stage::Apple, false);
    let listed = developer.list_app_ids(team, None).await.map_err(apple)?;
    if let Some(found) = listed.app_ids.into_iter().find(|a| a.identifier == bundle_id) {
        return Ok((found, false));
    }
    if listed.available_quantity.is_some_and(|n| n < 1) {
        return Err(Failure::new(Kind::NoAppIds, Stage::Apple, "No App ID left this week for Cartouche's"));
    }
    // Its name, as isideload gives it from Cartouche's bundle.
    let added = developer.add_app_id(team, "LiveContainer", bundle_id, None).await.map_err(apple)?;
    Ok((added, true))
}

/// What the Installer sets up on Cartouche's App ID: the app group it
/// shares with SideStore, and Increased Memory Limit.
async fn set_up(developer: &mut DeveloperSession, team: &DeveloperTeam, app_id: &mut AppId) -> Result<()> {
    let apple = |r: rootcause::Report| Failure::from_apple(&r, Stage::Apple, false);
    let group_id = format!("{APP_GROUP}.{}", team.team_id);
    let group = developer.ensure_app_group(team, "LiveContainer", &group_id, None).await.map_err(apple)?;
    app_id.ensure_group_feature(developer, team).await.map_err(apple)?;
    developer.assign_app_group(team, &group, app_id, None).await.map_err(apple)?;
    developer.add_increased_memory_limit(team, app_id).await.map_err(apple)?;
    Ok(())
}
