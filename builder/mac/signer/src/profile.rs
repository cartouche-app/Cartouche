//! A provisioning profile, as the signer reads it: the plist Apple signs
//! inside it, found as Cartouche on the iPhone finds it
//! (CartoucheSignature, launcher/Sources/CartoucheDevice.swift).

use std::time::SystemTime;

/// What a profile says.
#[derive(Clone, Debug)]
pub struct Profile {
    pub uuid: String,
    /// "TEAM.bundle", the App ID it is for.
    pub application_identifier: String,
    pub team_id: String,
    pub expires: SystemTime,
    pub created: Option<SystemTime>,
    pub devices: Vec<String>,
    pub all_devices: bool,
    /// The certificates an app signed with may run under it, in DER.
    pub certificates: Vec<Vec<u8>>,
    /// Whether a free Apple Account's.
    pub free: bool,
    /// What an app may be signed with under it.
    pub entitlements: plist::Dictionary,
    pub bytes: Vec<u8>,
}

impl Profile {
    pub fn parse(bytes: &[u8]) -> Option<Profile> {
        let start = find(bytes, b"<?xml")?;
        let end = find(&bytes[start..], b"</plist>")? + start + b"</plist>".len();
        let plist: plist::Dictionary = plist::from_bytes(&bytes[start..end]).ok()?;
        let date = |key: &str| plist.get(key).and_then(|v| v.as_date()).map(SystemTime::from);
        let strings = |key: &str| -> Vec<String> {
            plist
                .get(key)
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|v| v.as_string().map(str::to_string)).collect())
                .unwrap_or_default()
        };
        let entitlements = plist.get("Entitlements").and_then(|v| v.as_dictionary());
        Some(Profile {
            uuid: plist.get("UUID")?.as_string()?.to_string(),
            application_identifier: entitlements?.get("application-identifier")?.as_string()?.to_string(),
            team_id: strings("TeamIdentifier").into_iter().next().unwrap_or_default(),
            expires: date("ExpirationDate")?,
            created: date("CreationDate"),
            devices: strings("ProvisionedDevices"),
            all_devices: plist.get("ProvisionsAllDevices").and_then(|v| v.as_boolean()) == Some(true),
            certificates: plist
                .get("DeveloperCertificates")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|v| v.as_data().map(<[u8]>::to_vec)).collect())
                .unwrap_or_default(),
            free: plist.get("LocalProvision").and_then(|v| v.as_boolean()) == Some(true),
            entitlements: entitlements.cloned().unwrap_or_default(),
            bytes: bytes.to_vec(),
        })
    }

    /// Whether it is for BUNDLE_ID, an identifier as the iPhone lists it.
    pub fn is_for(&self, bundle_id: &str) -> bool {
        self.application_identifier
            .split_once('.')
            .is_some_and(|(team, bundle)| team == self.team_id && bundle == bundle_id)
    }

    pub fn lists_device(&self, udid: &str) -> bool {
        self.all_devices || self.devices.iter().any(|d| d.eq_ignore_ascii_case(udid))
    }

    /// The entitlements OLDER grants that this one does not: an app signed
    /// with them under OLDER would not open under this one.
    pub fn lacks_entitlements_of(&self, older: &Profile) -> Vec<String> {
        older
            .entitlements
            .iter()
            .filter(|(key, value)| match self.entitlements.get(key) {
                None => true,
                Some(have) => !granted(value, have),
            })
            .map(|(key, _)| key.clone())
            .collect()
    }

    /// Whether it lists at least one certificate of OTHER: an app signed
    /// under OTHER may run under it.
    pub fn shares_a_certificate_with(&self, other: &Profile) -> bool {
        self.certificates.iter().any(|c| other.certificates.contains(c))
    }
}

/// The profile of the iPhone's PROFILES that runs BUNDLE_ID on UDID the
/// longest, as iOS takes the best of them.
pub fn latest_for<'a>(profiles: &'a [Profile], bundle_id: &str, udid: &str) -> Option<&'a Profile> {
    profiles.iter().filter(|p| p.is_for(bundle_id) && p.lists_device(udid)).max_by_key(|p| p.expires)
}

/// Whether HAVE grants what WANT asks: the same value, the same list or
/// more, or a wildcard ("TEAM.*") that covers it.
fn granted(want: &plist::Value, have: &plist::Value) -> bool {
    fn string_ok(want: &str, have: &plist::Value) -> bool {
        match have {
            plist::Value::String(h) => h == want || h.strip_suffix('*').is_some_and(|prefix| want.starts_with(prefix)),
            plist::Value::Array(items) => items.iter().any(|h| string_ok(want, h)),
            _ => false,
        }
    }
    match want {
        plist::Value::String(w) => string_ok(w, have),
        plist::Value::Array(items) => items.iter().all(|w| granted(w, have)),
        plist::Value::Boolean(false) => true,
        _ => want == have,
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile_bytes(app_id: &str, team: &str, expires: SystemTime, devices: &[&str]) -> Vec<u8> {
        let mut d = plist::Dictionary::new();
        d.insert("UUID".into(), "A-B-C".into());
        let mut e = plist::Dictionary::new();
        e.insert("application-identifier".into(), app_id.into());
        d.insert("Entitlements".into(), plist::Value::Dictionary(e));
        d.insert("TeamIdentifier".into(), vec![plist::Value::from(team)].into());
        d.insert("ExpirationDate".into(), plist::Value::Date(expires.into()));
        d.insert(
            "ProvisionedDevices".into(),
            devices.iter().map(|x| plist::Value::from(*x)).collect::<Vec<_>>().into(),
        );
        d.insert("DeveloperCertificates".into(), vec![plist::Value::Data(vec![1, 2, 3])].into());
        let mut xml = Vec::new();
        plist::Value::Dictionary(d).to_writer_xml(&mut xml).unwrap();
        // As in a real profile: the plist within Apple's signature.
        let mut bytes = vec![0x30, 0x80, 0x06, 0x09];
        bytes.extend(xml);
        bytes.extend([0xa0, 0x82, 0x00, 0x00]);
        bytes
    }

    #[test]
    fn reads_the_plist_inside_the_signature() {
        let expires = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(2_000_000_000);
        let bytes =
            profile_bytes("TEAM123.io.github.clabeuhtegrite.cartouche.TEAM123", "TEAM123", expires, &["UDID-1"]);
        let p = Profile::parse(&bytes).expect("profile");
        assert_eq!(p.uuid, "A-B-C");
        assert_eq!(p.team_id, "TEAM123");
        assert_eq!(p.expires, expires);
        assert!(p.is_for("io.github.clabeuhtegrite.cartouche.TEAM123"));
        assert!(!p.is_for("io.github.clabeuhtegrite.cartouche"));
        assert!(p.lists_device("udid-1"));
        assert!(!p.lists_device("UDID-2"));
        assert_eq!(p.certificates, vec![vec![1, 2, 3]]);
    }

    #[test]
    fn a_profile_without_its_plist_is_none() {
        assert!(Profile::parse(b"not a profile").is_none());
        assert!(Profile::parse(b"<?xml version=\"1.0\"?><plist><dict></dict></plist>").is_none());
    }

    #[test]
    fn the_latest_is_the_one_that_runs_longest_on_this_iphone() {
        // Whole seconds, as a plist keeps dates.
        let now = SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(2_000_000_000);
        let day = std::time::Duration::from_secs(86_400);
        let id = "io.github.clabeuhtegrite.cartouche.TEAM123";
        let profiles: Vec<Profile> = [
            profile_bytes(&format!("TEAM123.{id}"), "TEAM123", now + day, &["U"]),
            profile_bytes(&format!("TEAM123.{id}"), "TEAM123", now + 6 * day, &["U"]),
            // Longer, but for another iPhone, then another app.
            profile_bytes(&format!("TEAM123.{id}"), "TEAM123", now + 9 * day, &["V"]),
            profile_bytes("TEAM123.other.app", "TEAM123", now + 9 * day, &["U"]),
        ]
        .iter()
        .map(|b| Profile::parse(b).unwrap())
        .collect();
        assert_eq!(latest_for(&profiles, id, "U").unwrap().expires, now + 6 * day);
        assert!(latest_for(&profiles, "nothing", "U").is_none());
    }
}
