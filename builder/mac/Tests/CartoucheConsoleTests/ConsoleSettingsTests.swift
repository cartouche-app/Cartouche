//
//  ConsoleSettingsTests.swift
//  CartoucheConsoleTests
//
//  A game's settings page in the console on the Mac (ConsoleSettings.swift),
//  the iPhone's own page on the rows of the game's app: Display mode
//  Fullscreen unless the player chose a window, what an env.txt sets shown
//  fixed, the game's language following the Mac's; how a game fits this
//  Mac, by the iPhone's rule; and what the console reads of a game's app
//  and of its folder of nxnative's: its title ID whatever its bundle ID,
//  the macOS it needs, and the play time the Builder counts there, which
//  the app's gallery shows its own of; the games' languages named, and
//  numbers and days written, in the language the console speaks. The
//  choices are kept in memory, as the gallery keeps them: no test writes a
//  game's preferences.
//

import Foundation
import XCTest
@testable import CartoucheConsole

/// A Mac app's list, as nxnative's settings.py writes it for the Mac.
private let macList = """
{"schema": 1, "game": "0100152000022000", "settings": [
  {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "", "default": "60",
   "options": [["30", "30 fps"], ["60", "60 fps"]], "level": "basic"},
  {"env": "DM_LANG", "kind": "choice", "section": "Game", "label": "Game language", "note": "", "default": "en-US",
   "options": [["en-US", "American English"], ["en-GB", "British English"], ["fr", "French"], ["de", "German"],
               ["es", "Spanish"], ["it", "Italian"], ["ja", "Japanese"]], "level": "basic"},
  {"env": "DM_FULLSCREEN", "kind": "choice", "section": "Game", "label": "Display mode", "note": "", "default": "0",
   "options": [["0", "Window"], ["1", "Fullscreen"]], "level": "basic"},
  {"env": "DM_RUMBLE", "kind": "toggle", "section": "Controls", "label": "Game rumble", "note": "", "default": "1"},
  {"env": "DM_SW2", "kind": "toggle", "section": "Controls", "label": "Switch 2 controllers", "note": "", "default": "0"},
  {"env": "DM_METAL_HUD", "kind": "toggle", "section": "Performance", "label": "Performance HUD", "note": "", "default": "0"}
]}
"""

@MainActor
final class ConsoleSettingsTests: XCTestCase {
    private var root: URL!
    private var keptRoot: URL!
    private var keptMemory = false

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("console-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let actions = CartoucheGameActions.shared
        keptRoot = actions.dataRoot
        keptMemory = actions.keepsChoicesInMemory
        actions.dataRoot = root.appendingPathComponent("nxnative", isDirectory: true)
        actions.keepsChoicesInMemory = true
    }

    override func tearDown() async throws {
        CartoucheGameActions.shared.dataRoot = keptRoot
        CartoucheGameActions.shared.keepsChoicesInMemory = keptMemory
        try? FileManager.default.removeItem(at: root)
    }

    /// A game's app as nxnative builds one for the Mac, its settings list
    /// in its resources, under a bundle ID of the test's own: the choices
    /// in memory are kept by domain.
    private func makeApp(titleID: String = "0100152000022000", bundleID: String? = nil, info extra: [String: Any] = [:],
                         list: String? = macList) throws -> LCAppModel {
        let app = root.appendingPathComponent("Applications/MK8-\(UUID().uuidString).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources/dm"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID ?? "com.example.mk8.\(UUID().uuidString.lowercased())",
                                   "CFBundleName": "Mario Kart 8 Deluxe", "DMTitleID": titleID, "DMLanguage": "en-US"]
        info.merge(extra) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let list {
            try Data(list.utf8).write(to: contents.appendingPathComponent("Resources/dm/launcher.json"))
        }
        return LCAppModel(appInfo: LCAppInfo(url: app))
    }

    private func row(_ env: String, of model: CartoucheGameSettingsModel) throws -> CartoucheGameSetting {
        try XCTUnwrap(model.settings.first { $0.env == env })
    }

    func testDisplayModeIsFullscreenUnlessThePlayerChoseAWindow() throws {
        let app = try makeApp()
        let model = CartoucheGameActions.shared.settings(for: app, tileKey: "mk8")
        XCTAssertTrue(model.canChange)
        XCTAssertEqual(model.settings.map(\.env), ["DM_FPS_TARGET", "DM_LANG", "DM_FULLSCREEN", "DM_RUMBLE", "DM_SW2", "DM_METAL_HUD"])
        let display = try row("DM_FULLSCREEN", of: model)
        XCTAssertEqual(display.def, "1", "Cartouche starts its games filling the screen")
        XCTAssertEqual(model.value(display), "1")
        XCTAssertFalse(model.changed)
        // A window is a choice, kept where nxnative's launcher reads it.
        model.choose(display, "0")
        let domain = try XCTUnwrap(app.appInfo.bundleIdentifier())
        let kept = CartoucheMemoryGamePreferences(domain: domain)
        XCTAssertEqual(kept.string(forKey: "launcher.DM_FULLSCREEN"), "0")
        XCTAssertTrue(model.changed)
        // Fullscreen again is the default: no choice left.
        model.choose(display, "1")
        XCTAssertNil(kept.string(forKey: "launcher.DM_FULLSCREEN"))
        // The page opens again on what was kept.
        model.choose(display, "0")
        let again = CartoucheGameActions.shared.settings(for: app, tileKey: "mk8")
        XCTAssertEqual(again.value(try row("DM_FULLSCREEN", of: again)), "0")
        again.reset()
        XCTAssertNil(kept.string(forKey: "launcher.DM_FULLSCREEN"))
        // The other rows as nxnative lists them.
        XCTAssertEqual(try row("DM_RUMBLE", of: model).def, "1")
        XCTAssertEqual(model.categories, ["Game", "Controls", "Performance"], "no cloud saves category on the Mac")
    }

    func testWhatAnEnvFileSetsShowsFixed() throws {
        let app = try makeApp()
        let folder = CartoucheGameActions.shared.dataRoot.appendingPathComponent("0100152000022000", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("DM_LANG=ja\n".utf8).write(to: folder.appendingPathComponent("env.txt"))
        try Data("DM_LANG=de\nDM_SW2=1\n".utf8).write(to: app.appInfo.url.appendingPathComponent("Contents/Resources/dm/env.txt"))
        let model = CartoucheGameActions.shared.settings(for: app, tileKey: "mk8")
        let language = try row("DM_LANG", of: model)
        XCTAssertTrue(model.isFixed(language))
        XCTAssertEqual(model.value(language), "ja", "the player's env.txt first")
        XCTAssertEqual(model.value(try row("DM_SW2", of: model)), "1")
        XCTAssertNil(model.languageRow, "a language an env.txt sets does not follow the Mac's")
        model.choose(try row("DM_SW2", of: model), "0")
        XCTAssertEqual(model.value(try row("DM_SW2", of: model)), "1")
    }

    func testTheGamesLanguageFollowsTheMacsUntilThePlayerChoosesOne() throws {
        let app = try makeApp()
        let model = CartoucheGameActions.shared.settings(for: app, tileKey: "mk8")
        let language = try XCTUnwrap(model.languageRow)
        // As the Builder will start it, from the Mac's languages; nothing
        // is kept before the player chooses.
        XCTAssertNotNil(model.iPhoneLanguage)
        let kept = CartoucheMemoryGamePreferences(domain: try XCTUnwrap(app.appInfo.bundleIdentifier()))
        XCTAssertNil(kept.string(forKey: "launcher.DM_LANG"))
        model.choose(language, "ja")
        XCTAssertNil(model.iPhoneLanguage)
        XCTAssertEqual(kept.string(forKey: "launcher.DM_LANG"), "ja")
        XCTAssertEqual(kept.string(forKey: "cartouche.languageSource"), "player")
        model.followIPhoneLanguage()
        XCTAssertEqual(kept.string(forKey: "cartouche.languageSource"), "iPhone")
    }

    func testTheConsoleNamesLanguagesAndWritesNumbersInTheLanguageItSpeaks() {
        let console = CartoucheMacConsole.shared
        let spoken = console.language
        defer { console.speak(spoken, from: nil) }
        let yesterday = Date().addingTimeInterval(-26 * 3_600)
        // In French, whatever the Mac's language: the words of the tests'
        // bundle are English, the numbers and the names French.
        console.speak("fr", from: nil)
        XCTAssertEqual(CartoucheText.languageNameInText("en-US", english: "American English"), "anglais (États-Unis)")
        XCTAssertEqual(CartoucheText.languageName("ja", english: "Japanese"), "Japonais")
        XCTAssertEqual(CartoucheText.size(bytes: 7_340_032_000), "7,3\u{00A0}GB")
        XCTAssertEqual(CartoucheText.lastPlayed(yesterday), "hier")
        console.speak("en", from: nil)
        XCTAssertEqual(CartoucheText.languageNameInText("fr", english: "French"), "French")
        XCTAssertEqual(CartoucheText.size(bytes: 7_340_032_000), "7.3\u{00A0}GB")
        XCTAssertEqual(CartoucheText.lastPlayed(yesterday), "yesterday")
        // The Mac's language: its own names and numbers.
        console.speak(nil, from: nil)
        XCTAssertEqual(CartoucheText.locale.identifier, Locale.current.identifier)
    }

    func testAnAppWithoutAListHasNoSettings() throws {
        let app = try makeApp(list: nil)
        let model = CartoucheGameActions.shared.settings(for: app, tileKey: "mk8")
        XCTAssertTrue(model.settings.isEmpty)
        XCTAssertTrue(model.categories.isEmpty)
    }

    // MARK: How a game fits this Mac

    private func sheet(peakMiB: Int?, results: [(device: String, status: String)]) throws -> CartoucheGameSheet {
        let list = results.map { result in
            "{\"device\": \"\(result.device)\", \"iOS\": \"26.6\", \"date\": \"2026-11-10\", \"engine\": \"nxnative\", \"status\": \"\(result.status)\"}"
        }.joined(separator: ", ")
        let json = """
        {"titleId": "0100152000022000", "name": "Mario Kart 8 Deluxe", "platform": "switch",
         "requirements": {"minimumIOS": "26.0", "bcTextureCompression": true, "increasedMemoryLimit": true\(peakMiB.map { ", \"peakMemoryMiB\": \($0)" } ?? "")},
         "results": [\(list)]}
        """
        return try JSONDecoder().decode(CartoucheGameSheet.self, from: Data(json.utf8))
    }

    func testAGameFitsThisMacByTheIPhonesRule() throws {
        // What this Mac cannot change: an Apple chip reads BC textures, and
        // nxnative's apps need macOS 26.6.
        let runs = CartoucheDevice.supportsBCTextureCompression && CartoucheDevice.runsAtLeast(CartoucheDevice.macMinimum)
        let here = CartoucheDevice.modelIdentifier
        // Testers ran it on this Mac's model: recommended. Increased Memory
        // Limit, which the sheet names, is iOS's alone.
        let tested = try sheet(peakMiB: 4_000, results: [(here, "playable"), ("iPhone18,1", "does-not-run")])
        if runs {
            XCTAssertEqual(CartoucheFit.of(tested, limitMiB: 12_000), .recommended)
            // Only an iPhone's result: not tried on this Mac yet.
            XCTAssertEqual(CartoucheFit.of(try sheet(peakMiB: nil, results: [("iPhone18,1", "playable")]), limitMiB: 12_000), .untested)
            // More than the memory a game may use here.
            let fit = CartoucheFit.of(tested, limitMiB: 3_000)
            guard case .notRecommended(let reasons) = fit else { return XCTFail("\(fit)") }
            XCTAssertEqual(reasons.count, 1)
            // The testers' last result on this model.
            XCTAssertFalse(CartoucheFit.of(try sheet(peakMiB: nil, results: [(here, "does-not-run")]), limitMiB: nil).isPlayable)
        } else {
            XCTAssertFalse(CartoucheFit.of(tested, limitMiB: 12_000).isPlayable)
        }
        XCTAssertEqual(CartoucheFit.withoutSheet() == nil, CartoucheDevice.supportsBCTextureCompression)
        // The memory a game may use on this Mac, as Metal says it.
        XCTAssertEqual(CartoucheGameKeeping.shared.gameLimitMiB(ownLimitMiB: nil), CartoucheDevice.gameMemoryMiB)
        XCTAssertGreaterThan(CartoucheDevice.gameMemoryMiB ?? 1, 0)
        XCTAssertFalse(CartoucheDevice.chip.isEmpty)
        XCTAssertEqual(CartoucheDevice.symbol, "laptopcomputer")
    }

    // MARK: The game's app and its folder

    func testTheConsoleReadsTheAppsTitleIDAndTheMacOSItNeeds() throws {
        // Built under another bundle ID: its title ID all the same.
        let app = try makeApp(titleID: "01004d300c5ae000", bundleID: "com.example.kirby", info: ["LSMinimumSystemVersion": "26.6"])
        XCTAssertEqual(app.appInfo.titleId, "01004D300C5AE000")
        XCTAssertEqual(app.appInfo.minimumSystemVersion, "26.6")
        XCTAssertEqual(CartoucheGameActions.shared.titleId(of: app), "01004D300C5AE000")
        XCTAssertNil(try makeApp(titleID: "not an ID").appInfo.titleId)
        XCTAssertNil(try makeApp(info: ["LSMinimumSystemVersion": ""]).appInfo.minimumSystemVersion)
        XCTAssertTrue(CartoucheDevice.runsAtLeast("13.0"))
        XCTAssertFalse(CartoucheDevice.runsAtLeast("99.0"))
    }

    func testThePlayTimeTheBuilderCountsShowsOnTheSheet() throws {
        // A game built under another bundle ID, its folder found by its title ID.
        let app = try makeApp(titleID: "01004D300C5AE000", bundleID: "com.example.kirby")
        let folder = CartoucheGameActions.shared.dataRoot.appendingPathComponent("01004D300C5AE000", isDirectory: true)
        let file = folder.appendingPathComponent(CartouchePlayTime.file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let played = Date(timeIntervalSince1970: 1_763_200_000)
        let plist: [String: Any] = ["seconds": 5_400.0, "sessions": 3, "firstPlayed": played, "lastPlayed": played, "version": 1,
                                    "lastSession": ["start": played, "seconds": 1_800.0]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: file)
        let folders = try XCTUnwrap(CartoucheGameActions.shared.folders(of: app))
        XCTAssertEqual(folders.titleId, "01004D300C5AE000")
        XCTAssertEqual(folders.playTimes(), ["01004D300C5AE000": CartouchePlayTime(seconds: 5_400, sessions: 3, firstPlayed: played,
                                                                                  lastPlayed: played)])
    }

    func testTheGallerysPlayTimeAndSizesAreItsOwn() throws {
        // A game of the app's gallery, under nxnative's bundle ID.
        let app = try makeApp(titleID: "040074A01BF12000", bundleID: "org.nxnative.040074a01bf12000")
        let entry = try XCTUnwrap(CartoucheCatalog.shared.entries(for: [app], stored: []).owned.first)
        let played = Date(timeIntervalSince1970: 1_763_200_000)
        let shown = CartouchePlayTime(seconds: 45_240, sessions: 23, firstPlayed: played, lastPlayed: played)
        CartoucheMacConsole.shared.showForGallery(playTimes: ["040074A01BF12000": shown],
                                                  sizes: ["040074A01BF12000": (app: 14_173_392_076, data: 48_234_496)])
        let stats = CartoucheGameStats.shared
        XCTAssertEqual(stats.playTime(of: entry)?.seconds, 45_240)
        XCTAssertEqual(stats.playTime(of: entry)?.sessions, 23)
        XCTAssertEqual(stats.size(of: app), CartoucheGameSize(bundle: 14_173_392_076, data: 48_234_496))
        // What the folder of nxnative's says since is neither read nor kept.
        let file = CartoucheGameActions.shared.dataRoot.appendingPathComponent("040074A01BF12000/" + CartouchePlayTime.file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["seconds": 60.0, "sessions": 1, "firstPlayed": played, "lastPlayed": played, "version": 1]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: file)
        stats.refresh([app])
        stats.cameBack([app])
        XCTAssertEqual(stats.playTime(of: entry)?.seconds, 45_240)
        XCTAssertEqual(stats.size(of: app)?.total, 14_173_392_076 + 48_234_496)
    }
}
