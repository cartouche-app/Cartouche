//
//  MacPlayTests.swift
//  BuilderKitTests
//
//  What the builder needs to start a game's Mac app and to know how it
//  ended (MacPlay.swift), as nxnative's docs/frontends.md and its launcher
//  (dm/mac/launcher.c) say it: the app's Info.plist, the launcher's last
//  line in its log, the environment of a start, the language a game starts
//  in, chosen as Cartouche chooses it on the iPhone, and nxnative's own
//  cloud saves, which the builder leaves a game's saves to.
//

import Foundation
import XCTest
@testable import BuilderKit

final class MacPlayTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-play-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// An app named NAME.app whose Info.plist holds INFO.
    private func app(_ name: String, _ info: [String: Any]) throws -> URL {
        let url = root.appendingPathComponent(name + ".app", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    // MARK: The app

    func testAGamesAppIsWhatItsInfoPlistSays() throws {
        let url = try app("MK8", ["DMTitleID": "0100152000022000", "CFBundleDisplayName": "Mario Kart 8 Deluxe", "CFBundleName": "MK8",
                                  "CFBundleIdentifier": "org.nxnative.0100152000022000"])
        let found = try XCTUnwrap(MacGameApp(url: url))
        XCTAssertEqual(found.titleID, "0100152000022000")
        // Its copies' folder is named after the name it shows, as Cartouche
        // names it after its IPA's.
        XCTAssertEqual(found.name, "Mario Kart 8 Deluxe")
        XCTAssertEqual(found.bundleID, "org.nxnative.0100152000022000")
        XCTAssertEqual(found.saveGame, MacSaveGame(titleID: "0100152000022000", name: "Mario Kart 8 Deluxe"))
        XCTAssertNil(found.version)
        // The version of the game it was built from, as nxnative's packer
        // writes it, which each copy of its saves names.
        let built = try XCTUnwrap(MacGameApp(url: try app("MK8 1.2", ["DMTitleID": "0100152000022000", "CFBundleName": "MK8",
                                                                       "CFBundleShortVersionString": "1.2.0"])))
        XCTAssertEqual(built.version, "1.2.0")
        XCTAssertEqual(built.saveGame, MacSaveGame(titleID: "0100152000022000", name: "MK8", version: "1.2.0"))
        XCTAssertNil(MacGameApp(url: try app("MK8 none", ["DMTitleID": "0100152000022000", "CFBundleShortVersionString": ""]))?.version)
        // Packed with another bundle ID, a lower-case ID, no display name.
        let other = try XCTUnwrap(MacGameApp(url: try app("Kirby", ["DMTitleID": "01004d300c5ae000", "CFBundleName": "Kirby",
                                                                     "CFBundleIdentifier": "com.example.kirby"])))
        XCTAssertEqual(other.titleID, "01004D300C5AE000")
        XCTAssertEqual(other.name, "Kirby")
        XCTAssertEqual(other.bundleID, "com.example.kirby")
        // No bundle ID: nxnative's own.
        XCTAssertEqual(MacGameApp(url: try app("Dread", ["DMTitleID": "010093801237C000"]))?.bundleID, "org.nxnative.010093801237C000")
        XCTAssertEqual(MacGameApp(url: try app("Dread", ["DMTitleID": "010093801237C000"]))?.name, "Dread")
        // Any other app, or none.
        XCTAssertNil(MacGameApp(url: try app("Safari", ["CFBundleName": "Safari"])))
        XCTAssertNil(MacGameApp(url: try app("Odd", ["DMTitleID": "../0100152000022000"])))
        XCTAssertNil(MacGameApp(url: root.appendingPathComponent("Missing.app")))
    }

    // MARK: How it ended

    func testTheEndingIsTheLaunchersLastLine() {
        let start = "launcher: Mario Kart 8 Deluxe (0100152000022000), host /Applications/MK8.app/Contents/MacOS/dmhost\n"
            + "launcher: no settings window (DM_LAUNCHER=0 or --no-launcher)\n[host] a game's own line\n"
        let cases: [(String, MacGameEnding, Int?)] = [
            ("launcher: the host exited with 0", .quit, 0),
            ("launcher: the host exited with 70", .gpu, 70),
            ("launcher: the host exited with 134", .crashed, 134),
            ("launcher: the host exited with 1", .crashed, 1),
            ("launcher: the host stopped on signal 15", .stopped, 143),
            ("launcher: the host stopped on signal 9", .stopped, 137),
            ("launcher: the host stopped on signal 11", .crashed, 139),
            // The window closed without playing: no host line.
            ("", .unknown, nil),
            // Words the builder does not know: unknown, never wrong.
            ("launcher: the game ended (code 0)", .unknown, nil),
        ]
        for (last, ending, exit) in cases {
            let result = MacGameEnding.parse(start + last + "\n")
            XCTAssertEqual(result.ending, ending, last)
            XCTAssertEqual(result.exit, exit, last)
        }
        // After the host's line, the launcher may still say the cloud's save did not go.
        let after = MacGameEnding.parse(start + "launcher: the host exited with 0\nlauncher: the save did not reach the cloud; it goes at the next start\n")
        XCTAssertEqual(after.ending, .quit)
    }

    func testTheEndingIsReadFromTheEndOfThisStartsLog() throws {
        let log = root.appendingPathComponent("0100152000022000.log")
        // A long log: what ends it is at its end.
        var text = "launcher: Mario Kart 8 Deluxe (0100152000022000)\n"
        text += String(repeating: "[host] frame 1234 took 16.6 ms, nothing to say\n", count: 4000)
        text += "launcher: the host stopped on signal 6\n"
        try Data(text.utf8).write(to: log)
        let read = MacGameEnding.read(log: log, since: Date().addingTimeInterval(-60))
        XCTAssertEqual(read.ending, .crashed)
        XCTAssertEqual(read.exit, 134)
        // The log of an earlier start: this one wrote none (it never ran).
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: log.path)
        XCTAssertEqual(MacGameEnding.read(log: log, since: Date()).ending, .unknown)
        XCTAssertEqual(MacGameEnding.read(log: root.appendingPathComponent("none.log")).ending, .unknown)
    }

    // MARK: A start

    func testAStartSkipsTheWindowAndSpeaksThePlayersLanguage() throws {
        let app = MacGameApp(url: URL(fileURLWithPath: "/Applications/MK8.app"), titleID: "0100152000022000", name: "Mario Kart 8 Deluxe")
        XCTAssertEqual(MacPlayEnvironment.arguments(settings: false), ["--no-launcher"])
        XCTAssertEqual(MacPlayEnvironment.arguments(settings: true), [])
        let french = MacPlayEnvironment.make(app: app, keepsSaves: true, language: "fr")
        // Never two syncs on one save: nxnative's own cloud saves stay off.
        XCTAssertEqual(french["DM_SAVE_SYNC"], "0")
        XCTAssertNil(french["DM_SAVE"])
        // Five lines each, in nxnative's order; its placeholders kept.
        let quit = try XCTUnwrap(french["DM_HOME_QUIT_TEXT"]).components(separatedBy: "\n")
        XCTAssertEqual(quit.count, 5)
        XCTAssertEqual(quit[1], "Quitter Mario Kart 8 Deluxe ?")
        XCTAssertFalse(quit.contains(""))
        let players = try XCTUnwrap(french["DM_CTRL_PROMPT_TEXT"]).components(separatedBy: "\n")
        XCTAssertEqual(players.count, 5)
        XCTAssertTrue(players[0].contains("{min}"))
        XCTAssertTrue(players[2].contains("{joined}") && players[2].contains("{min}"))
        XCTAssertFalse(players.contains(""))
        // In Spanish and German too, five lines each with their placeholders.
        for (language, title) in [("es", "¿Salir de Mario Kart 8 Deluxe?"), ("de", "Mario Kart 8 Deluxe beenden?")] {
            let made = MacPlayEnvironment.make(app: app, keepsSaves: true, language: language)
            let quit = try XCTUnwrap(made["DM_HOME_QUIT_TEXT"]).components(separatedBy: "\n")
            XCTAssertEqual(quit.count, 5, language)
            XCTAssertEqual(quit[1], title)
            let players = try XCTUnwrap(made["DM_CTRL_PROMPT_TEXT"]).components(separatedBy: "\n")
            XCTAssertEqual(players.count, 5, language)
            XCTAssertTrue(players[0].contains("{min}"), language)
            XCTAssertTrue(players[2].contains("{joined}") && players[2].contains("{min}"), language)
        }
        // In English, nxnative's own texts; its saves left to its cloud saves.
        let english = MacPlayEnvironment.make(app: app, keepsSaves: false, language: "en")
        XCTAssertEqual(english, [:])
        // The tests' own folder for the game's saves.
        let documents = root.appendingPathComponent("nxnative/0100152000022000", isDirectory: true)
        XCTAssertEqual(MacPlayEnvironment.make(app: app, keepsSaves: true, language: "en", documents: documents)["DM_SAVE"],
                       documents.appendingPathComponent("save").path)
    }

    /// Ad's choice (15 November): a game started from Cartouche fills the
    /// screen, as a console's does, Cartouche behind it until it ends; it
    /// opened in a window of its own beside Cartouche's.
    func testAGameStartedStraightAwayFillsTheScreenUnlessThePlayerChoseOtherwise() {
        let app = MacGameApp(url: URL(fileURLWithPath: "/Applications/MK8.app"), titleID: "0100152000022000", name: "Mario Kart 8 Deluxe",
                             bundleID: "com.example.mk8")
        var asked: [String] = []
        var saved: String?
        let preference: (String, String) -> String? = { key, domain in
            asked.append(domain + " " + key)
            return saved
        }
        XCTAssertTrue(MacPlayEnvironment.fullscreen(settings: false, of: app, preference: preference))
        // nxnative's saved choice of Display mode, in the app's own domain.
        XCTAssertEqual(asked, ["com.example.mk8 launcher.DM_FULLSCREEN"])
        XCTAssertEqual(MacPlayEnvironment.make(app: app, keepsSaves: true, language: "en", fullscreen: true)["DM_FULLSCREEN"], "1")
        XCTAssertNil(MacPlayEnvironment.make(app: app, keepsSaves: true, language: "en")["DM_FULLSCREEN"])
        // A Display mode saved for the game holds (nxnative's settings window
        // saves Fullscreen; a front end may save either): the start leaves it
        // to the launcher, which applies it.
        for choice in ["1", "0"] {
            saved = choice
            XCTAssertFalse(MacPlayEnvironment.fullscreen(settings: false, of: app, preference: preference), choice)
        }
        // With that window first, the window shows the player's choice: a
        // variable the start set, it would show fixed.
        saved = nil
        asked.removeAll()
        XCTAssertFalse(MacPlayEnvironment.fullscreen(settings: true, of: app, preference: preference))
        XCTAssertEqual(asked, [])
    }

    // MARK: The game's language

    /// An app whose settings list offers LANGUAGES, the first its own.
    private func appWithLanguages(_ languages: [String], bundleID: String = "com.example.mk8") throws -> MacGameApp {
        let url = try app("MK8", ["DMTitleID": "0100152000022000", "CFBundleIdentifier": bundleID])
        let dm = url.appendingPathComponent("Contents/Resources/dm", isDirectory: true)
        try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
        let options = languages.map { "[\"\($0)\", \"\($0)\"]" }.joined(separator: ", ")
        let list = """
        {"schema": 1, "settings": [
          {"env": "DM_FULLSCREEN", "kind": "choice", "section": "Game", "label": "Display mode", "note": "", "default": "0",
           "options": [["0", "Window"], ["1", "Fullscreen"]]},
          {"env": "DM_LANG", "kind": "choice", "section": "Game", "label": "Game language", "note": "",
           "default": "\(languages[0])", "options": [\(options)]}
        ]}
        """
        try Data(list.utf8).write(to: dm.appendingPathComponent("launcher.json"))
        return try XCTUnwrap(MacGameApp(url: url))
    }

    func testAGameStartsInTheMacsLanguageUnlessThePlayerChoseOne() throws {
        let game = try appWithLanguages(["en-US", "en-GB", "fr", "de", "ja"])
        let documents = root.appendingPathComponent("0100152000022000", isDirectory: true)
        var saved: [String: String] = [:]
        let read: (String, String) -> String? = { key, domain in saved[domain + " " + key] }
        let write: (String, String?, String) -> Void = { key, value, domain in saved[domain + " " + key] = value }
        func prepare(_ preferred: [String]) -> String? {
            MacGameLanguage.prepare(game, documents: documents, preferred: preferred, read: read, write: write)
        }

        // The first of the Mac's languages the game has, saved where nxnative
        // reads the player's choice, in the app's own domain.
        XCTAssertEqual(prepare(["fr-FR", "en-FR"]), "fr")
        XCTAssertEqual(saved, ["com.example.mk8 launcher.DM_LANG": "fr", "com.example.mk8 cartouche.languageSource": "iPhone",
                               "com.example.mk8 cartouche.iPhoneLanguage": "fr"])
        // The Mac's languages change: the game follows at its next start.
        XCTAssertEqual(prepare(["de-CH", "fr-FR"]), "de")
        XCTAssertEqual(saved["com.example.mk8 launcher.DM_LANG"], "de")
        // None of them: the game's own.
        XCTAssertEqual(prepare(["pl-PL"]), "en-US")
        // The player chose Japanese in nxnative's window: it stays.
        saved["com.example.mk8 launcher.DM_LANG"] = "ja"
        XCTAssertEqual(prepare(["fr-FR"]), "ja")
        XCTAssertEqual(saved["com.example.mk8 cartouche.languageSource"], "player")
        XCTAssertNil(saved["com.example.mk8 cartouche.iPhoneLanguage"])
        XCTAssertEqual(prepare(["de-DE"]), "ja")
    }

    /// Up to Mac 0.8.2, a Mac in Polish or Thai started a game that has its
    /// language in the game's own, as the iPhone did.
    func testAGameStartsInPolishOrThaiOnAMacInIt() throws {
        let game = try appWithLanguages(["en-US", "fr", "pl", "th"])
        let documents = root.appendingPathComponent("0100152000022000", isDirectory: true)
        var saved: [String: String] = [:]
        let read: (String, String) -> String? = { key, domain in saved[domain + " " + key] }
        let write: (String, String?, String) -> Void = { key, value, domain in saved[domain + " " + key] = value }
        XCTAssertEqual(MacGameLanguage.prepare(game, documents: documents, preferred: ["pl-PL", "en-PL"], read: read, write: write), "pl")
        XCTAssertEqual(saved["com.example.mk8 launcher.DM_LANG"], "pl")
        XCTAssertEqual(MacGameLanguage.prepare(game, documents: documents, preferred: ["th-TH"], read: read, write: write), "th")
        XCTAssertEqual(saved["com.example.mk8 launcher.DM_LANG"], "th")
    }

    func testALanguageAnEnvFileOrTheStartSetsIsLeftAlone() throws {
        let game = try appWithLanguages(["en-US", "fr"])
        let documents = root.appendingPathComponent("0100152000022000", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        var writes = 0
        let read: (String, String) -> String? = { _, _ in nil }
        let write: (String, String?, String) -> Void = { _, _, _ in writes += 1 }
        // The start's own environment.
        XCTAssertNil(MacGameLanguage.prepare(game, documents: documents, environment: ["DM_LANG": "en-US"], preferred: ["fr-FR"],
                                             read: read, write: write))
        // The player's env.txt in nxnative's folder of the game, which
        // nxnative keeps over the choice, as the app's own.
        try Data("DM_LANG=en-US\n".utf8).write(to: documents.appendingPathComponent("env.txt"))
        XCTAssertNil(MacGameLanguage.prepare(game, documents: documents, preferred: ["fr-FR"], read: read, write: write))
        try FileManager.default.removeItem(at: documents.appendingPathComponent("env.txt"))
        try Data("DM_LANG=en-US\n".utf8).write(to: game.url.appendingPathComponent("Contents/Resources/dm/env.txt"))
        XCTAssertNil(MacGameLanguage.prepare(game, documents: documents, preferred: ["fr-FR"], read: read, write: write))
        XCTAssertEqual(writes, 0)
        // A game without the row, of one language: nothing to choose.
        let one = try XCTUnwrap(MacGameApp(url: try app("Dread", ["DMTitleID": "010093801237C000"])))
        XCTAssertNil(MacGameLanguage.prepare(one, documents: documents, preferred: ["fr-FR"], read: read, write: write))
        XCTAssertEqual(writes, 0)
    }

    // MARK: nxnative's own cloud saves

    func testAGameWhoseSavesNxnativesCloudSyncsIsLeftToIt() throws {
        let app = MacGameApp(url: URL(fileURLWithPath: "/Applications/MK8.app"), titleID: "0100152000022000", name: "Mario Kart 8 Deluxe",
                             bundleID: "com.example.mk8")
        let documents = root.appendingPathComponent("0100152000022000", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        var asked: [String] = []
        var chosen: String?
        let preference: (String, String) -> String? = { key, domain in
            asked.append(domain + " " + key)
            return chosen
        }
        XCTAssertNil(MacCloudSaves.folder(of: app, documents: documents, preference: preference))
        // The app's own domain, its cloudSaves.folder key.
        XCTAssertEqual(asked, ["com.example.mk8 cloudSaves.folder"])
        chosen = "/Users/player/Library/Mobile Documents/com~apple~CloudDocs/Saves"
        XCTAssertEqual(MacCloudSaves.folder(of: app, documents: documents, preference: preference), chosen)
        chosen = ""
        XCTAssertNil(MacCloudSaves.folder(of: app, documents: documents, preference: preference))
        // The player's env.txt wins over the window's choice, as nxnative reads it: the first line that sets it.
        chosen = "/Users/player/Saves"
        let env = documents.appendingPathComponent("env.txt")
        try Data("# DM_SAVE_SYNC=icloud\nDM_FPS_TARGET=30\nDM_SAVE_SYNC=0\nDM_SAVE_SYNC=icloud\n".utf8).write(to: env)
        XCTAssertNil(MacCloudSaves.folder(of: app, documents: documents, preference: preference))
        try Data("DM_SAVE_SYNC=icloud\n".utf8).write(to: env)
        XCTAssertEqual(MacCloudSaves.folder(of: app, documents: documents, preference: preference), "icloud")
        // Set empty, it is off all the same: nxnative then reads no folder.
        try Data("DM_SAVE_SYNC=\n".utf8).write(to: env)
        XCTAssertNil(MacCloudSaves.folder(of: app, documents: documents, preference: preference))
    }
}
