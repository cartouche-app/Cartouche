//
//  CartoucheGameTexts.swift
//  Cartouche
//
//  The texts of nxnative's own prompts and menu over a game, in the
//  language Cartouche speaks: nxnative writes them in English, and takes
//  them in another language from its front end, in the game's environment
//  (its docs/frontends.md, "Starting a game", and docs/env_switches.tsv).
//
//  - DM_HOME_QUIT_TEXT: the prompt that quits a game held on a controller's
//    Home button, the Mac's alone (on the iPhone, Home shows Cartouche's
//    console). Five lines: the hold indicator, the title with the game's
//    name, the note, the quit and the cancel button.
//  - DM_CTRL_PROMPT_TEXT: the prompt that waits when a game asks for more
//    players than have joined, on the Mac and the iPhone. Five lines: the
//    title, the hint, the count, the done and the cancel button; nxnative
//    puts the numbers in place of {min}, {max} and {joined}.
//  - DM_GAME_MENU_TEXT: the gear menu over a game on the iPhone (nxnative's
//    commit 90edd532 of 23 November 2026; an older build shows it in
//    English). Four lines: the menu's title, Controller layout, the Tap
//    layout, and the note of a setting an env.txt file sets. Its title
//    says where the other settings are, which nxnative calls its start
//    screen: Play skips that screen, so Cartouche names its own Game
//    settings, in English too. The settings in the menu keep nxnative's
//    English names, which it takes from no front end.
//
//  An empty or missing line keeps nxnative's English text. One table for
//  the Mac and the iPhone, so that both say the same words: the Mac starts
//  its games with them in their environment (builder/mac, MacPlay.swift,
//  MacPlayEnvironment); the iPhone writes them in the game's data folder
//  as Play starts it, behind the console or in Cartouche's place, and
//  Cartouche's code in the game's process puts them in its environment
//  (launcher/Guest/CartoucheGameTexts.m), unless the game's env.txt sets
//  them (docs/decisions/179.md).
//

import Foundation

public enum CartoucheGameTexts {
    /// Where a game is played: the Mac has the Home button's prompt, the
    /// iPhone the gear menu.
    public enum Platform: Sendable {
        case mac, iPhone
    }

    public static let quitVariable = "DM_HOME_QUIT_TEXT"
    public static let playersVariable = "DM_CTRL_PROMPT_TEXT"
    public static let menuVariable = "DM_GAME_MENU_TEXT"

    /// The variables each platform's nxnative reads, in this order.
    public static func variables(on platform: Platform) -> [String] {
        switch platform {
        case .mac: return [quitVariable, playersVariable]
        case .iPhone: return [playersVariable, menuVariable]
        }
    }

    /// The languages the texts are in besides English, nxnative's own.
    public static let languages = ["fr", "es", "de"]

    /// The texts' language for TAG, as a bundle or a system writes a
    /// language ("fr", "fr-CA", "de_CH"): "en" for one they are not in.
    public static func language(of tag: String?) -> String {
        let base = String((tag ?? "en").lowercased().prefix { $0.isLetter })
        return languages.contains(base) ? base : "en"
    }

    /// The lines of VARIABLE for the game NAME in LANGUAGE, in nxnative's
    /// order; an empty one keeps nxnative's English. Nil when all of them
    /// would be English.
    public static func lines(_ variable: String, game name: String, language: String) -> [String]? {
        switch (variable, language) {
        case (quitVariable, "fr"):
            return ["Maintenez pour quitter", "Quitter \(name) ?", "La progression non sauvegardée sera perdue.", "Quitter", "Annuler"]
        case (quitVariable, "es"):
            return ["Mantén pulsado para salir", "¿Salir de \(name)?", "Se perderá el progreso no guardado.", "Salir", "Cancelar"]
        case (quitVariable, "de"):
            return ["Zum Beenden gedrückt halten", "\(name) beenden?", "Nicht gespeicherter Fortschritt geht verloren.", "Beenden",
                    "Abbrechen"]
        case (playersVariable, "fr"):
            return ["{min} joueurs attendus", "Appuyez sur un bouton de chaque manette pour la faire rejoindre.",
                    "Joueurs : {joined} sur {min}", "Terminé", "Annuler"]
        case (playersVariable, "es"):
            return ["Se esperan {min} jugadores", "Pulsa un botón de cada mando para que se una.",
                    "Jugadores: {joined} de {min}", "Hecho", "Cancelar"]
        case (playersVariable, "de"):
            return ["{min} Spieler erwartet", "Drücke eine Taste auf jedem Controller, um ihn hinzuzufügen.",
                    "Spieler: {joined} von {min}", "Fertig", "Abbrechen"]
        // The game's settings in the words of Cartouche's own button
        // (action.gameSettings), its Controls section (setting.section.controls)
        // and its note of a setting an env.txt file sets (settings.fixed).
        case (menuVariable, "fr"):
            return ["Plus de réglages dans Cartouche\u{00A0}: Réglages du jeu", "Disposition des commandes", "Toucher",
                    "Fixé par un fichier env.txt"]
        case (menuVariable, "es"):
            return ["Más ajustes en Cartouche: Ajustes del juego", "Disposición de los controles", "Tocar",
                    "Fijado por un archivo env.txt"]
        case (menuVariable, "de"):
            return ["Weitere Einstellungen in Cartouche: Spieleinstellungen", "Steuerungslayout", "Tippen",
                    "Durch eine env.txt-Datei festgelegt"]
        case (menuVariable, _):
            // nxnative's says "More settings on the start screen", which Play
            // skips; the rest stays its own.
            return ["More settings in Cartouche: Game settings"]
        default:
            return nil
        }
    }

    /// The environment a game NAME starts with on PLATFORM, for the
    /// prompts and the menu in LANGUAGE (one of `languages`, or English):
    /// nothing for those that stay in nxnative's English.
    public static func environment(game name: String, language: String, on platform: Platform) -> [String: String] {
        var environment: [String: String] = [:]
        for variable in variables(on: platform) {
            if let lines = lines(variable, game: name, language: language) {
                environment[variable] = lines.joined(separator: "\n")
            }
        }
        return environment
    }

    // MARK: The iPhone's file

    /// In the game's data folder; CartoucheGameTextsEnvironment.m reads it
    /// in the game's process (CartoucheGameTextsFile).
    public static let file = "Library/Cartouche/GameTexts.plist"
    static let version = 1

    /// Writes the iPhone's texts in LANGUAGE in HOME, the data folder of
    /// the game NAME about to start, in place of what an earlier start
    /// wrote there: the language Cartouche speaks may have changed since.
    /// Returns the variables written.
    @discardableResult
    public static func write(game name: String, language: String, home: URL) throws -> [String] {
        let url = home.appendingPathComponent(file)
        let environment = environment(game: name, language: language, on: .iPhone)
        guard !environment.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return []
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["version": version, "language": language, "environment": environment]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
        return variables(on: .iPhone).filter { environment[$0] != nil }
    }

    /// The texts the game whose data folder is HOME starts with, as its
    /// file says: none without it.
    public static func written(home: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(file)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let environment = plist["environment"] as? [String: String] else {
            return [:]
        }
        return environment
    }
}
