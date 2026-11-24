//! The window's texts: every text it names exists in English, and French,
//! Spanish and German have the same texts, with the same {{values}},
//! links and platforms. A missing one shows as its key in the window
//! (en.json, fr.json, es.json, de.json).

use std::{collections::BTreeMap, path::Path};

use serde_json::Value;

fn locale(language: &str) -> BTreeMap<String, Value> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../src/locales/{language}.json"));
    let value: Value = serde_json::from_str(&std::fs::read_to_string(&path).expect("locale")).expect("JSON");
    let mut flat = BTreeMap::new();
    flatten("", &value, &mut flat);
    flat
}

fn flatten(prefix: &str, value: &Value, out: &mut BTreeMap<String, Value>) {
    match value {
        Value::Object(map) => {
            for (key, value) in map {
                let key = if prefix.is_empty() { key.clone() } else { format!("{prefix}.{key}") };
                flatten(&key, value, out);
            }
        }
        other => {
            out.insert(prefix.to_string(), other.clone());
        }
    }
}

/// The {{values}} of a text, sorted.
fn values(text: &str) -> Vec<&str> {
    let mut found: Vec<&str> = text.split("{{").skip(1).filter_map(|rest| rest.split("}}").next()).collect();
    found.sort();
    found
}

/// What must stay the same between languages in a text.
fn shape(text: &str) -> (Vec<&str>, usize, Option<&str>) {
    let platform = text.strip_prefix("[platform::").and_then(|rest| rest.split(']').next());
    (values(text), text.matches("((link:").count(), platform)
}

/// The languages the window speaks besides English, with their names
/// for the messages (src/i18next.ts).
const LANGUAGES: [(&str, &str); 3] = [("fr", "French"), ("es", "Spanish"), ("de", "German")];

#[test]
fn every_language_has_every_english_text_with_the_same_values() {
    let en = locale("en");
    for (code, name) in LANGUAGES {
        let other = locale(code);
        let missing: Vec<&String> = en.keys().filter(|k| !other.contains_key(*k)).collect();
        let extra: Vec<&String> = other.keys().filter(|k| !en.contains_key(*k)).collect();
        assert!(missing.is_empty(), "{name} lacks {missing:?}");
        assert!(extra.is_empty(), "{name} has texts English has not: {extra:?}");
        for (key, english) in &en {
            match (english, &other[key]) {
                (Value::String(e), Value::String(o)) => {
                    assert_eq!(shape(e), shape(o), "{name}, {key}: {e:?} / {o:?}");
                    assert!(!o.trim().is_empty(), "{key} is empty in {name}");
                }
                (Value::Array(e), Value::Array(o)) => {
                    assert_eq!(e.len(), o.len(), "{name}, {key}: not as many suggestions");
                    for (e, o) in e.iter().zip(o) {
                        let (e, o) = (e.as_str().unwrap(), o.as_str().unwrap());
                        assert_eq!(shape(e), shape(o), "{name}, {key}: {e:?} / {o:?}");
                    }
                }
                _ => panic!("{name}, {key}: not the same kind of text in both"),
            }
        }
    }
}

#[test]
fn the_window_offers_every_language() {
    let i18next = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/i18next.ts")).expect("i18next.ts");
    for code in ["en"].into_iter().chain(LANGUAGES.iter().map(|(code, _)| *code)) {
        assert!(i18next.contains(&format!("[\"{code}\", ")), "src/i18next.ts does not offer {code}");
    }
    let locales: Vec<String> = std::fs::read_dir(Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/locales"))
        .expect("locales")
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().trim_end_matches(".json").to_string())
        .collect();
    assert_eq!(locales.len(), LANGUAGES.len() + 1, "a locale the test does not check: {locales:?}");
}

/// Every key the frontend names literally: t("…"), the operations' keys,
/// and the errors' suggestions.
fn keys_used() -> Vec<(String, String)> {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src");
    let mut found = Vec::new();
    let mut stack = vec![src];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).expect("src").flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            if !(name.ends_with(".ts") || name.ends_with(".tsx")) {
                continue;
            }
            let text = std::fs::read_to_string(&path).expect("source");
            for (opening, after) in [
                ("t(\"", ""),
                ("Key: \"", ""),
                ("\"error.suggestions.", "error.suggestions."),
            ] {
                for (at, _) in text.match_indices(opening) {
                    // t( alone, not split( or emit(.
                    if opening.starts_with('t')
                        && text[..at].chars().last().is_some_and(|c| c.is_alphanumeric() || c == '_' || c == '.')
                    {
                        continue;
                    }
                    let rest = &text[at + opening.len()..];
                    let key: String = rest.chars().take_while(|c| *c != '"').collect();
                    if key.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '.') {
                        found.push((format!("{after}{key}"), name.clone()));
                    }
                }
            }
        }
    }
    found
}

#[test]
fn every_text_the_window_names_exists() {
    let en = locale("en");
    let used = keys_used();
    assert!(used.len() > 100, "found only {} keys: the scan is broken", used.len());
    let missing: Vec<&(String, String)> = used
        .iter()
        .filter(|(key, _)| !en.contains_key(key) && !en.keys().any(|k| k.starts_with(&format!("{key}."))))
        .collect();
    assert!(missing.is_empty(), "named in the window, missing from en.json: {missing:?}");
}
