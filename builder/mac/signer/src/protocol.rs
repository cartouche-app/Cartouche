//! How the Mac app and the signer talk: the signer writes one JSON object a
//! line on its output, events as they come (`{"event": "code", …}`) and,
//! last, its answer (`{"result": …}`) or what stopped it
//! (`{"error": {"kind": …, "stage": …, "message": …}}`). It reads what the
//! player types, one JSON object a line on its input: the password
//! (`{"password": …}`), then a code when it asks for one (`{"code": …}`,
//! `{"sms": <number's id>}`, `{"devices": true}` or `{"cancel": true}`).
//! The password goes no further than Apple: it is never written, nor kept
//! once the sign-in is over.

use std::io::Write;

use serde::Serialize;
use serde_json::{Value, json};

use crate::error::Failure;

/// Writes one line on the output, and flushes it: the app reads each as it
/// comes.
pub fn line(value: &Value) {
    let mut out = std::io::stdout().lock();
    let _ = serde_json::to_writer(&mut out, value);
    let _ = out.write_all(b"\n");
    let _ = out.flush();
}

pub fn event(name: &str, fields: Value) {
    let mut value = json!({ "event": name });
    if let (Some(object), Value::Object(fields)) = (value.as_object_mut(), fields) {
        object.extend(fields);
    }
    line(&value);
}

pub fn result(value: &impl Serialize) {
    line(&json!({ "result": value }));
}

pub fn failure(failure: &Failure) {
    line(&json!({ "error": failure }));
}

/// Dates as RFC 3339, in UTC, to the second: "2026-12-03T09:41:00Z".
pub mod time {
    use std::time::SystemTime;

    use chrono::{DateTime, SecondsFormat, Utc};
    use serde::{Deserialize, Deserializer, Serializer, de::Error};

    pub fn text(time: SystemTime) -> String {
        DateTime::<Utc>::from(time).to_rfc3339_opts(SecondsFormat::Secs, true)
    }

    pub fn parse(text: &str) -> Option<SystemTime> {
        DateTime::parse_from_rfc3339(text).ok().map(|d| SystemTime::from(d.with_timezone(&Utc)))
    }

    pub fn serialize<S: Serializer>(time: &SystemTime, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&text(*time))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<SystemTime, D::Error> {
        let text = String::deserialize(d)?;
        parse(&text).ok_or_else(|| D::Error::custom(format!("not a date: {text}")))
    }

    pub mod option {
        use super::*;

        pub fn serialize<S: Serializer>(time: &Option<SystemTime>, s: S) -> Result<S::Ok, S::Error> {
            match time {
                Some(t) => s.serialize_some(&text(*t)),
                None => s.serialize_none(),
            }
        }

        pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<SystemTime>, D::Error> {
            let text = Option::<String>::deserialize(d)?;
            match text {
                None => Ok(None),
                Some(text) => parse(&text).map(Some).ok_or_else(|| D::Error::custom(format!("not a date: {text}"))),
            }
        }
    }
}
