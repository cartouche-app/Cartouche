//! When the Mac renews Cartouche: in its last two days, as Cartouche on the
//! iPhone renews itself then when Tailscale is on (CartoucheTailscale), or
//! once it has expired. Never earlier: each renewal asks Apple for a new
//! profile, and a profile made a day after the last one gains a day.

use std::time::{Duration, SystemTime};

use serde::Serialize;

/// How long before Cartouche expires the Mac renews it.
pub const RENEW_BEFORE: Duration = Duration::from_secs(2 * 86_400);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case", tag = "due")]
pub enum Due {
    /// Not yet: its last two days start then.
    NotYet {
        #[serde(with = "crate::protocol::time")]
        from: SystemTime,
    },
    /// In its last two days.
    Now,
    /// It has expired: Cartouche does not open until it is renewed.
    Expired,
}

impl Due {
    pub fn is_due(self) -> bool {
        !matches!(self, Due::NotYet { .. })
    }
}

/// Whether Cartouche, signed until EXPIRES, is to be renewed at NOW.
pub fn due(expires: SystemTime, now: SystemTime) -> Due {
    if expires <= now {
        return Due::Expired;
    }
    let from = expires.checked_sub(RENEW_BEFORE).unwrap_or(SystemTime::UNIX_EPOCH);
    if now >= from { Due::Now } else { Due::NotYet { from } }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: Duration = Duration::from_secs(3600);

    #[test]
    fn its_last_two_days_and_after() {
        let now = SystemTime::now();
        assert_eq!(due(now + 7 * 24 * HOUR, now), Due::NotYet { from: now + 5 * 24 * HOUR });
        assert_eq!(
            due(now + 48 * HOUR + Duration::from_secs(1), now),
            Due::NotYet { from: now + Duration::from_secs(1) }
        );
        assert_eq!(due(now + 48 * HOUR, now), Due::Now);
        assert_eq!(due(now + HOUR, now), Due::Now);
        assert_eq!(due(now, now), Due::Expired);
        assert_eq!(due(now - 30 * 24 * HOUR, now), Due::Expired);
        assert!(!due(now + 3 * 24 * HOUR, now).is_due());
        assert!(due(now - HOUR, now).is_due());
    }
}
