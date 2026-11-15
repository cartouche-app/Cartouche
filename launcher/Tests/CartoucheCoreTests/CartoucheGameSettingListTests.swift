//
//  CartoucheGameSettingListTests.swift
//  CartoucheCoreTests
//
//  A game's settings list as nxnative writes it (CartoucheGameSettingList.swift):
//  its rows, the iPhone's and the Mac's, which only differ by the platform's
//  own; the env files that fix a setting, the first that sets it winning;
//  a row with another default, as the console on the Mac shows Display
//  mode; and where the game's language is kept among the choices.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheGameSettingListTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("setting-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A Mac app's list, as nxnative's settings.py writes it for the Mac
    /// (its settings.tsv, platform mac): Display mode and the Switch 2
    /// controllers are the Mac's alone.
    static let macList = """
    {"schema": 1, "game": "0100152000022000", "settings": [
      {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "", "default": "60",
       "options": [["30", "30 fps"], ["60", "60 fps"]], "level": "basic"},
      {"env": "DM_LANG", "kind": "choice", "section": "Game", "label": "Game language", "note": "", "default": "en-US",
       "options": [["en-US", "American English"], ["fr", "French"], ["de", "German"], ["ja", "Japanese"]], "level": "basic"},
      {"env": "DM_FULLSCREEN", "kind": "choice", "section": "Game", "label": "Display mode", "note": "", "default": "0",
       "options": [["0", "Window"], ["1", "Fullscreen"]], "level": "basic"},
      {"env": "DM_RUMBLE", "kind": "toggle", "section": "Controls", "label": "Game rumble", "note": "", "default": "1"},
      {"env": "DM_RUMBLE_GAIN", "kind": "range", "section": "Controls", "label": "Rumble strength", "note": "", "default": "1.0",
       "min": 0, "max": 3, "step": 0.1, "needs": "DM_RUMBLE=1"},
      {"env": "DM_SW2", "kind": "toggle", "section": "Controls", "label": "Switch 2 controllers",
       "note": "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. macOS asks once for Bluetooth access.",
       "default": "0"},
      {"env": "DM_FPS_HOLD", "kind": "toggle", "section": "Performance", "label": "Hold frames when late", "note": "",
       "default": "on", "on": "on", "off": "off"}
    ]}
    """

    func testAMacAppsListReadsAsTheIPhones() throws {
        let rows = try XCTUnwrap(CartoucheGameSetting.rows(in: Data(Self.macList.utf8)))
        XCTAssertEqual(rows.map(\.env), ["DM_FPS_TARGET", "DM_LANG", "DM_FULLSCREEN", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_SW2", "DM_FPS_HOLD"])
        let display = rows[2]
        XCTAssertEqual(display.kind, "choice")
        XCTAssertEqual(display.def, "0")
        XCTAssertEqual(display.optionValues, ["0", "1"])
        XCTAssertTrue(display.accepts("1"))
        XCTAssertFalse(display.accepts("2"))
        XCTAssertEqual(rows[1].optionValues, ["en-US", "fr", "de", "ja"])
        XCTAssertEqual(rows[5].label, "Switch 2 controllers")
        XCTAssertEqual(rows[5].sectionTitle, "Controls")
        XCTAssertEqual(rows[6].onValue, "on")
        XCTAssertTrue(rows[4].isDefault("1.00"), "a slider writes 1.00 for 1.0")
        // Not a list.
        XCTAssertNil(CartoucheGameSetting.rows(in: Data("{\"schema\": 1}".utf8)))
    }

    func testTheListIsInTheAppsResourcesOrItsFirstProgramsFolder() throws {
        // A Mac app keeps its dm folder in Contents/Resources, an iPhone's
        // at the root of its bundle: either is the bundle the list is in.
        let resources = root.appendingPathComponent("MK8.app/Contents/Resources", isDirectory: true)
        XCTAssertNil(CartoucheGameSetting.rows(inBundle: resources))
        let program = resources.appendingPathComponent("dm/p0", isDirectory: true)
        try FileManager.default.createDirectory(at: program, withIntermediateDirectories: true)
        try Data(Self.macList.utf8).write(to: program.appendingPathComponent("launcher.json"))
        XCTAssertEqual(CartoucheGameSetting.rows(inBundle: resources)?.count, 7)
        try Data("{\"settings\": []}".utf8).write(to: resources.appendingPathComponent("dm/launcher.json"))
        XCTAssertEqual(CartoucheGameSetting.rows(inBundle: resources)?.count, 0, "the game's own list first")
    }

    func testTheFirstEnvFileThatSetsAVariableWins() throws {
        let player = root.appendingPathComponent("env.txt")
        let app = root.appendingPathComponent("app-env.txt")
        try Data("# DM_LANG=ja\nDM_LANG=fr\nDM_FULLSCREEN=1\n".utf8).write(to: player)
        try Data("DM_LANG=de\nDM_FPS_TARGET=30\n=nothing\nnot a setting\n".utf8).write(to: app)
        let missing = root.appendingPathComponent("missing.txt")
        XCTAssertEqual(CartoucheGameSetting.fixedValues(files: [missing, player, app]),
                       ["DM_LANG": "fr", "DM_FULLSCREEN": "1", "DM_FPS_TARGET": "30"])
        XCTAssertEqual(CartoucheGameSetting.fixedValues(files: [app, player])["DM_LANG"], "de")
        XCTAssertEqual(CartoucheGameSetting.fixedValues(files: []), [:])
        // The iPhone's: the game's Documents/env.txt, then its bundle's dm/env.txt.
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bundle = root.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("dm"), withIntermediateDirectories: true)
        try Data("DM_LANG=ja\n".utf8).write(to: home.appendingPathComponent("Documents/env.txt"))
        try Data("DM_LANG=de\nDM_RUMBLE=0\n".utf8).write(to: bundle.appendingPathComponent("dm/env.txt"))
        XCTAssertEqual(CartoucheGameSetting.fixedValues(home: home, bundle: bundle), ["DM_LANG": "ja", "DM_RUMBLE": "0"])
        XCTAssertEqual(CartoucheGameSetting.fixedValues(home: nil, bundle: bundle), ["DM_LANG": "de", "DM_RUMBLE": "0"])
    }

    func testARowWithAnotherDefaultIsTheSameRowOtherwise() throws {
        let rows = try XCTUnwrap(CartoucheGameSetting.rows(in: Data(Self.macList.utf8)))
        let display = rows[2]
        let filling = CartoucheGameSetting(display, default: "1")
        XCTAssertEqual(filling.def, "1")
        XCTAssertTrue(filling.isDefault("1"))
        XCTAssertFalse(filling.isDefault("0"))
        XCTAssertEqual(filling.env, display.env)
        XCTAssertEqual(filling.label, display.label)
        XCTAssertEqual(filling.choices, display.choices)
        XCTAssertEqual(filling.sectionTitle, display.sectionTitle)
        let strength = CartoucheGameSetting(rows[4], default: "2.0")
        XCTAssertEqual(strength.needs, "DM_RUMBLE=1")
        XCTAssertEqual(strength.max, 3)
        XCTAssertTrue(strength.isDefault("2.00"))
    }

    /// Choices in memory, as a game's preferences hold them.
    private final class Choices: CartoucheGameChoices {
        var values: [String: String] = [:]
        var writes = 0
        func string(forKey key: String) -> String? { values[key] }
        func data(forKey key: String) -> Data? { nil }
        func set(_ value: Any?, forKey key: String) {
            writes += 1
            values[key] = value as? String
        }
    }

    func testTheGamesLanguageIsKeptWhereNxnativeAndCartoucheReadIt() {
        let choices = Choices()
        XCTAssertEqual(choices.languageRecord, CartoucheGameLanguage.Record())
        let record = CartoucheGameLanguage.Record(saved: "fr", source: .iPhone, iPhone: "fr")
        choices.keepLanguage(record)
        XCTAssertEqual(choices.values, ["launcher.DM_LANG": "fr", "cartouche.languageSource": "iPhone", "cartouche.iPhoneLanguage": "fr"])
        XCTAssertEqual(choices.languageRecord, record)
        // Only what changed is written.
        choices.writes = 0
        choices.keepLanguage(CartoucheGameLanguage.chosen("fr"))
        XCTAssertEqual(choices.writes, 2)
        XCTAssertEqual(choices.values, ["launcher.DM_LANG": "fr", "cartouche.languageSource": "player"])
    }
}
