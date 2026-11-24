//
//  L10n.swift
//  Cartouche Builder
//
//  The app speaks English, French, Spanish or German: the Mac's language,
//  or the one chosen in its settings; English when the Mac speaks another.
//  Each text is written in all four, where it is used:
//  tr("Library", "Bibliothèque", "Biblioteca", "Bibliothek").
//

import Foundation

public enum L10n {
    /// The languages the app speaks, English first, which it speaks when
    /// the Mac speaks none of them.
    public static let languages = ["en", "fr", "es", "de"]

    /// The language chosen in the settings: one of `languages`, or "" for
    /// the Mac's.
    public private(set) static var chosen = ""
    /// The language in use, one of `languages`: for the engine and the
    /// formatters.
    public private(set) static var code = systemLanguage

    /// The Mac's language, as the app speaks it: its first preferred
    /// language, or CARTOUCHE_BUILDER_LANG, the tests'.
    public static var systemLanguage: String {
        if let forced = ProcessInfo.processInfo.environment["CARTOUCHE_BUILDER_LANG"], !forced.isEmpty {
            return language(of: forced)
        }
        return language(of: Locale.preferredLanguages.first ?? "en")
    }

    /// The app's language for TAG, a language as macOS writes it: "fr-CA"
    /// is French, "es-419" Spanish, "de-CH" German, "it" English.
    public static func language(of tag: String) -> String {
        let base = String(tag.lowercased().prefix { $0.isLetter })
        return languages.contains(base) ? base : "en"
    }

    public static func use(_ language: String) {
        chosen = languages.contains(language) ? language : ""
        code = chosen.isEmpty ? systemLanguage : chosen
    }

    public static var french: Bool { code == "fr" }
    /// Whether numbers take a decimal comma, as in "4,7": every language
    /// but English.
    public static var decimalComma: Bool { code != "en" }
    public static var locale: Locale {
        Locale(identifier: ["fr": "fr_FR", "es": "es_ES", "de": "de_DE"][code] ?? "en_US")
    }
}

/// ENGLISH, FRENCH, SPANISH or GERMAN, in the app's language.
public func tr(_ english: String, _ french: String, _ spanish: String, _ german: String) -> String {
    switch L10n.code {
    case "fr": french
    case "es": spanish
    case "de": german
    default: english
    }
}
