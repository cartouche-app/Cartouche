//
//  MacPlay.swift
//  BuilderKit
//
//  A game's app for this Mac, as nxnative packs it, and what the builder
//  needs to start it and to know how it ended (nxnative's docs/frontends.md,
//  "Starting a game"): its title ID and names in its Info.plist; the
//  environment of a start, which skips nxnative's settings window, fills the
//  screen with the game unless a display mode is saved for it,
//  turns nxnative's own cloud saves off while the builder keeps the saves,
//  and gives the Home button's prompt and the players' prompt the player's
//  language; the language the game starts in, chosen before each start as
//  Cartouche chooses it on the iPhone; the cloud saves folder the player
//  may have chosen in that window; and how the game ended, from the
//  launcher's last line in its log.
//  Platform-independent: Foundation only. Starting the app and following it
//  is MacGames.swift's.
//

import CartoucheCore
import Foundation

/// A game's app for this Mac.
public struct MacGameApp: Hashable, Sendable {
    public let url: URL
    public let titleID: String
    /// The name it shows: its copies' folder is named after it, as
    /// Cartouche names it after its IPA's.
    public let name: String
    /// Its preferences domain: its saved choices and nxnative's cloud saves
    /// folder are kept there.
    public let bundleID: String

    public init(url: URL, titleID: String, name: String, bundleID: String? = nil) {
        self.url = url.standardizedFileURL
        self.titleID = titleID.uppercased()
        self.name = name
        self.bundleID = bundleID ?? "org.nxnative." + titleID.uppercased()
    }

    /// The app at URL, as its Info.plist says it; nil for an app that is no
    /// game of nxnative's (no DMTitleID).
    public init?(url: URL) {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let id = info["DMTitleID"] as? String, MacSavesFolder.isTitleID(id) else { return nil }
        let names = [info["CFBundleDisplayName"], info["CFBundleName"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        let name = names.first ?? url.deletingPathExtension().lastPathComponent
        self.init(url: url, titleID: id, name: name, bundleID: (info["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    public var saveGame: MacSaveGame { MacSaveGame(titleID: titleID, name: name) }
}

/// How a game ended, as its launcher says it in the last line of the log
/// of its start: the launcher runs the game's host as a child and exits
/// with its exit code (0 for a quit, 70 after macOS revoked the game's GPU
/// work, 134 for an abort), or 128 + the signal that stopped it.
public enum MacGameEnding: String, Codable, Sendable {
    /// The player quit: ⌘Q, the Home prompt, its window closed.
    case quit
    /// macOS stopped running the game's GPU work.
    case gpu
    /// Another exit code, or a crash's signal.
    case crashed
    /// Stopped from outside: a logout, Activity Monitor, a terminal.
    case stopped
    /// No game ran (nxnative's window was closed without playing), or the
    /// log is another start's, or says it in words the builder does not
    /// know: nxnative treats its log as diagnostics, not as an interface,
    /// and a line it words otherwise makes the ending unknown, never wrong.
    case unknown

    static let exited = "launcher: the host exited with "
    static let signalled = "launcher: the host stopped on signal "

    /// The ending its launcher wrote in LOG, a start's log written since
    /// STARTED, and the launcher's exit code; unknown, with none, for a log
    /// of an earlier start or one that does not say.
    public static func read(log: URL, since started: Date? = nil) -> (ending: MacGameEnding, exit: Int?) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: log.path)
        if let started, let modified = attributes?[.modificationDate] as? Date, modified < started.addingTimeInterval(-2) {
            return (.unknown, nil)
        }
        guard let handle = try? FileHandle(forReadingFrom: log) else { return (.unknown, nil) }
        defer { try? handle.close() }
        // Its last lines: a game's log can be long, what ends it is short.
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 16384 ? end - 16384 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The ending the last launcher line of TEXT says.
    public static func parse(_ text: String) -> (ending: MacGameEnding, exit: Int?) {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(exited), let code = Int(line.dropFirst(exited.count).trimmingCharacters(in: .whitespaces)) {
                switch code {
                case 0: return (.quit, 0)
                case 70: return (.gpu, 70)
                default: return (.crashed, code)
                }
            }
            if line.hasPrefix(signalled), let signal = Int(line.dropFirst(signalled.count).trimmingCharacters(in: .whitespaces)) {
                // SIGHUP, SIGINT, SIGKILL, SIGTERM: someone stopped it.
                return ([1, 2, 9, 15].contains(signal) ? .stopped : .crashed, 128 + signal)
            }
        }
        return (.unknown, nil)
    }
}

/// The environment the builder starts a game with, over the player's own
/// (nxnative's docs/frontends.md, "Starting a game"). Only what is for this
/// start: what the player chose is in the app's saved choices, which a
/// start from the Finder or the Dock reads too.
public enum MacPlayEnvironment {
    /// The prompts' texts in the builder's LANGUAGE ("fr"), none for
    /// English, nxnative's own: the Home button's quit prompt for the game
    /// NAME, and the prompt that waits for more players, five lines each.
    public static func texts(game name: String, language: String) -> [String: String] {
        guard language == "fr" else { return [:] }
        return [
            "DM_HOME_QUIT_TEXT": [
                "Maintenez pour quitter",
                "Quitter \(name) ?",
                "La progression non sauvegardée sera perdue.",
                "Quitter",
                "Annuler",
            ].joined(separator: "\n"),
            "DM_CTRL_PROMPT_TEXT": [
                "{min} joueurs attendus",
                "Appuyez sur un bouton de chaque manette pour la faire rejoindre.",
                "Joueurs : {joined} sur {min}",
                "Terminé",
                "Annuler",
            ].joined(separator: "\n"),
        ]
    }

    /// The environment of a start of APP: KEEPS_SAVES, the builder keeps its
    /// saves in step with the iPhone's, so nxnative's own cloud saves stay
    /// off for this start, never two syncs on one save; FULLSCREEN, the
    /// game fills the screen from its start (fullscreen(settings:of:));
    /// DOCUMENTS, the game's folder when it is not nxnative's own, for the
    /// tests (its saves are DOCUMENTS/save and save_device: nxnative adds
    /// _device).
    public static func make(app: MacGameApp, keepsSaves: Bool, language: String, fullscreen: Bool = false,
                            documents: URL? = nil) -> [String: String] {
        var environment = texts(game: app.name, language: language)
        if keepsSaves {
            environment["DM_SAVE_SYNC"] = "0"
        }
        if fullscreen {
            environment[fullscreenKey] = "1"
        }
        if let documents {
            environment["DM_SAVE"] = documents.appendingPathComponent("save", isDirectory: true).path
        }
        return environment
    }

    /// nxnative's Display mode on the Mac (dm/games/settings.tsv): 0, a
    /// window, its default; 1, fullscreen.
    public static let fullscreenKey = "DM_FULLSCREEN"

    /// Whether a start of APP fills the screen, as a console's game does,
    /// Cartouche's console behind it until it ends: one straight into the
    /// game does, unless a Display mode is saved for the game
    /// (launcher.DM_FULLSCREEN in the app's preferences, read by PREFERENCE
    /// (key, domain)), which then holds. The console's settings page shows
    /// Fullscreen as the game's default, and saves a window as "0"
    /// (ConsoleSettings.swift); nxnative's settings window saves Fullscreen
    /// alone, a window, its default, as no choice, so a game put in a window
    /// there fills the screen again from here, ⌃⌘F putting it back in a
    /// window. A start with that window (SETTINGS) leaves it to the window:
    /// a variable the start sets, the window shows fixed.
    public static func fullscreen(settings: Bool, of app: MacGameApp, preference: (String, String) -> String?) -> Bool {
        guard !settings else { return false }
        return preference("launcher." + fullscreenKey, app.bundleID) == nil
    }

    /// The arguments of a start: none for one that shows nxnative's
    /// settings window (SETTINGS), --no-launcher to start the game at once.
    public static func arguments(settings: Bool) -> [String] {
        settings ? [] : ["--no-launcher"]
    }
}

/// The language a game starts in on this Mac, chosen before each start the
/// builder makes as Cartouche chooses it on the iPhone (CartoucheGameLanguage,
/// in CartoucheCore): the first of the Mac's languages that the game has,
/// unless the player chose one, in the console's settings page or in
/// nxnative's window. It is saved where nxnative keeps the player's choice,
/// the app's preferences, so that its window shows it, and a start from the
/// Finder or the Dock starts in it too. A game of one language has nothing
/// to choose, nor one whose env.txt, or the start's own environment, sets
/// it: nxnative keeps those over the player's choice.
public enum MacGameLanguage {
    /// Chooses APP's language before a start, from the Mac's languages,
    /// PREFERRED, in their order; DOCUMENTS is the game's folder of
    /// nxnative's, where the player's env.txt is, and ENVIRONMENT the
    /// start's own. READ (key, domain) reads the app's preferences, WRITE
    /// (key, value, domain) writes one, nil removing it. Returns the
    /// language the game starts in, nil when there was nothing to choose.
    @discardableResult
    public static func prepare(_ app: MacGameApp, documents: URL, environment: [String: String] = [:], preferred: [String],
                               read: @escaping (String, String) -> String?,
                               write: @escaping (String, String?, String) -> Void) -> String? {
        let resources = app.url.appendingPathComponent("Contents/Resources", isDirectory: true)
        let files = [documents.appendingPathComponent("env.txt"), resources.appendingPathComponent("dm/env.txt")]
        guard environment[CartoucheGameLanguage.variable] == nil,
              let row = CartoucheGameSetting.rows(inBundle: resources)?.first(where: { $0.env == CartoucheGameLanguage.variable }),
              row.kind == "choice", CartoucheGameSetting.fixedValues(files: files)[row.env] == nil else { return nil }
        let choices = MacGameChoices(domain: app.bundleID, read: read, write: write)
        let offered = row.optionValues
        let record = CartoucheGameLanguage.beforeStart(choices.languageRecord, preferred: preferred, offered: offered,
                                                      gameDefault: row.def)
        choices.keepLanguage(record)
        return CartoucheGameLanguage.language(of: record, offered: offered, gameDefault: row.def)
    }
}

/// A game's preferences, as the builder reads and writes them: through its
/// closures, cfprefsd's (MacGames.preference, MacGames.keep), or the
/// tests' own. A choice is a string, as nxnative keeps them.
final class MacGameChoices: CartoucheGameChoices {
    let domain: String
    private let read: (String, String) -> String?
    private let write: (String, String?, String) -> Void

    init(domain: String, read: @escaping (String, String) -> String?, write: @escaping (String, String?, String) -> Void) {
        self.domain = domain
        self.read = read
        self.write = write
    }

    func string(forKey key: String) -> String? { read(key, domain) }
    func data(forKey key: String) -> Data? { nil }
    func set(_ value: Any?, forKey key: String) { write(key, value as? String, domain) }
}

/// nxnative's own cloud saves: a folder the player chose in a game's
/// settings window (cloudSaves.folder in the app's preferences), or wrote
/// in its env.txt (DM_SAVE_SYNC), syncs its save at each start and quit.
/// The builder then leaves that game's saves to it.
public enum MacCloudSaves {
    /// The folder nxnative's cloud saves of APP go through, nil when they
    /// are off: from its preferences, read by PREFERENCE (key, domain), or
    /// the player's env.txt in DOCUMENTS, which wins over them.
    public static func folder(of app: MacGameApp, documents: URL, preference: (String, String) -> String?) -> String? {
        if let line = environmentFileValue(documents.appendingPathComponent("env.txt")) {
            // Set, even empty, it is the one nxnative reads: "" and "0" are off.
            return line.isEmpty || line == "0" ? nil : line
        }
        guard let folder = preference("cloudSaves.folder", app.bundleID)?.trimmingCharacters(in: .whitespaces),
              !folder.isEmpty, folder != "0" else { return nil }
        return folder
    }

    /// The value env.txt at URL gives DM_SAVE_SYNC, read as nxnative's
    /// launcher reads it (dm/mac/launcher.c env_file): the first line that
    /// sets it wins; nil when none does.
    static func environmentFileValue(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equal = line.firstIndex(of: "="), equal != line.startIndex,
                  line[..<equal].trimmingCharacters(in: .whitespaces) == "DM_SAVE_SYNC" else { continue }
            return String(line[line.index(after: equal)...])
        }
        return nil
    }
}
