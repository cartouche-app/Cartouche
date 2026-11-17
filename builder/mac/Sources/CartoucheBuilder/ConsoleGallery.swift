//
//  ConsoleGallery.swift
//  Cartouche Builder
//
//  Cartouche's console in the gallery (Gallery.swift): its home with the
//  sheet of the game in focus beside it, every game, a game's settings page
//  in place of its sheet, its info over the console, and the whole sheet of
//  a game played on this Mac, with the pages its saves open, as the console
//  shows the games built for this Mac, and one a NAS keeps that is not
//  installed here, in the window as the app shows it (MainView). The games
//  are real ones nxnative builds, with their covers from IGDB as the
//  console shows them; their apps are the gallery's own, empty but for
//  their Info.plist and the list of settings nxnative gives a game on the
//  Mac, in a temporary folder, their play time and their sizes made up, as
//  are the saves of the sheet's game and their copies; the NAS's file is
//  only a name, and nothing of the player's is read or kept: no data folder
//  of nxnative's, no saves folder, no game's preferences, no play time, no
//  question to Cartouche's server.
//  Like ConsoleWindow.swift, this file imports the console and not
//  CartoucheCore, whose names it shares.
//

import AppKit
import CartoucheConsole

@MainActor
enum ConsoleGallery {
    /// The games built for this Mac: the console sorts them by name.
    static let games: [(name: String, titleID: String)] = [
        ("Donkey Kong Bananza", "040074A01BF12000"),
        ("Mario Kart World", "0400C3F00006E000"),
        ("The Legend of Zelda: Link's Awakening", "01006BB00C6F0000"),
    ]

    /// A game the NAS keeps, not installed on this Mac: first by name, in
    /// focus, with Install.
    static let kept = [
        CartoucheMacKeptGame(titleID: "01006F8002326000", name: "Animal Crossing: New Horizons",
                             file: "/Volumes/Jeux/Animal Crossing New Horizons [01006F8002326000].app.zip",
                             size: 7_340_032_000, built: Date().addingTimeInterval(-26 * 3_600)),
    ]

    /// The game whose whole sheet the gallery shows: played on this Mac, and
    /// the one of them testers wrote a sheet for (catalog/games), which says
    /// how it fits this Mac.
    static let sheetGame = "0400C3F00006E000"

    /// The time two of them were played on this Mac, and the space each
    /// takes here, its app and its data.
    static let playTimes = [
        "040074A01BF12000": CartouchePlayTime(seconds: 45_240, sessions: 23, firstPlayed: Date().addingTimeInterval(-9 * 86_400),
                                              lastPlayed: Date().addingTimeInterval(-86_400)),
        "0400C3F00006E000": CartouchePlayTime(seconds: 2_820, sessions: 2, firstPlayed: Date().addingTimeInterval(-4 * 3_600),
                                              lastPlayed: Date().addingTimeInterval(-3 * 3_600)),
    ]
    static let sizes: [String: (app: UInt64, data: UInt64)] = [
        "040074A01BF12000": (14_173_392_076, 48_234_496),
        "0400C3F00006E000": (21_474_836_480, 327_155_712),
        "01006BB00C6F0000": (3_113_851_290, 6_291_456),
    ]

    /// The settings nxnative lists for a game built for the Mac
    /// (dm/games/settings.tsv, its rows for the Mac; the app's
    /// Contents/Resources/dm/launcher.json), with a game's defaults.
    static func settings(of titleID: String) -> String {
        """
        {"schema": 1, "game": "\(titleID)", "settings": [
          {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "", "default": "60",
           "level": "basic", "options": [["30", "30 fps"], ["60", "60 fps"]]},
          {"env": "DM_OPMODE", "kind": "choice", "section": "Game", "label": "Console mode", "note": "", "default": "1",
           "level": "basic", "options": [["1", "Docked"], ["0", "Handheld"]]},
          {"env": "DM_PRESENT_UPSCALE", "kind": "choice", "section": "Game", "label": "Upscaling",
           "note": "Uses more GPU time and can increase heat.", "default": "off", "options": [["off", "Standard"], ["metalfx", "MetalFX"]]},
          {"env": "DM_LANG", "kind": "choice", "section": "Game", "label": "Game language", "note": "", "default": "en-US", "level": "basic",
           "options": [["en-US", "American English"], ["en-GB", "British English"], ["ja", "Japanese"], ["fr", "French"], ["de", "German"],
                       ["es-419", "Latin American Spanish"], ["es", "Spanish"], ["it", "Italian"], ["nl", "Dutch"], ["fr-CA", "Canadian French"]]},
          {"env": "DM_FULLSCREEN", "kind": "choice", "section": "Game", "label": "Display mode", "note": "", "default": "0",
           "level": "basic", "options": [["0", "Window"], ["1", "Fullscreen"]]},
          {"env": "DM_RUMBLE", "kind": "toggle", "section": "Controls", "label": "Game rumble", "note": "", "default": "1",
           "level": "basic", "on": "1", "off": "0"},
          {"env": "DM_RUMBLE_GAIN", "kind": "range", "section": "Controls", "label": "Rumble strength", "note": "", "default": "1.0",
           "needs": "DM_RUMBLE=1", "min": 0.0, "max": 3.0, "step": 0.1},
          {"env": "DM_RUMBLE_MIN", "kind": "range", "section": "Controls", "label": "Rumble cutoff", "note": "", "default": "0",
           "min": 0.0, "max": 0.9, "step": 0.05},
          {"env": "DM_PAD_PRESS_TO_JOIN", "kind": "toggle", "section": "Controls", "label": "Press a button to join", "note": "",
           "default": "0", "on": "1", "off": "0"},
          {"env": "DM_SW2", "kind": "toggle", "section": "Controls", "label": "Switch 2 controllers",
           "note": "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. macOS asks once for Bluetooth access.",
           "default": "0", "on": "1", "off": "0"},
          {"env": "DM_PRESENT_SNAP", "kind": "toggle", "section": "Performance", "label": "Frame buffering",
           "note": "Up to one frame more display latency.", "default": "0", "on": "1", "off": "0"},
          {"env": "DM_PSO_MTL4", "kind": "toggle", "section": "Performance", "label": "Metal 4 pipelines",
           "note": "Keeps a pipeline archive; uses more memory.", "default": "1", "on": "1", "off": "0"},
          {"env": "DM_PSO_PREBUILD", "kind": "toggle", "section": "Performance", "label": "Pipeline prebuild",
           "note": "The first start waits a few minutes for it, once.", "default": "1", "needs": "DM_PSO_MTL4=1", "on": "1", "off": "0"},
          {"env": "DM_NVN_ENC_THREAD", "kind": "toggle", "section": "Performance", "label": "Encode thread", "note": "",
           "default": "1", "on": "1", "off": "0"},
          {"env": "DM_FPS_HOLD", "kind": "toggle", "section": "Performance", "label": "Hold frames when late", "note": "",
           "default": "on", "on": "on", "off": "off"},
          {"env": "DM_METAL_HUD", "kind": "toggle", "section": "Performance", "label": "Performance HUD", "note": "",
           "default": "0", "on": "1", "off": "0"}
        ]}
        """
    }

    private static var folder: URL?
    private static var apps: [URL] = []

    /// The copies of the sheet's game's saves in the saves folder, made up:
    /// the newest synced a few minutes ago, the others on the days before.
    static let copies: [CartoucheMacSaveCopy] = {
        let made: [(ago: TimeInterval, size: UInt64)] = [(12 * 60, 1_310_720), (21 * 3_600, 1_298_432), (46 * 3_600, 1_261_568),
                                                         (5 * 86_400, 1_179_648)]
        let now = (Date().timeIntervalSince1970 / 60).rounded(.down) * 60
        return made.map { copy in
            let date = Date(timeIntervalSince1970: now - copy.ago)
            return CartoucheMacSaveCopy(name: ConsoleGallery.copyName(date), date: date, size: copy.size)
        }
    }()

    /// A copy's name, as Cartouche names them: its date, in UTC.
    private static func copyName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date) + ".zip"
    }

    /// The console with the gallery's games, speaking LANGUAGE ("fr" or "en"),
    /// the saves of the sheet's game kept in step with a NAS's share: the
    /// newest copy came, or, NEWER, it waits for the game's update, version
    /// 1.2.0 of the game having written it and this Mac's app being 1.0.0.
    static func prepare(language: String, newer: Bool = false) {
        if let covers = makeGames() {
            let deadline = Date().addingTimeInterval(60)
            while !covers.loaded && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        show(language: language, newer: newer)
    }

    /// As prepare(language:newer:), from a task of the main actor: the
    /// layout check's. Spun inside such a task, prepare(language:newer:)'s
    /// run loop does not run the covers' task, also the main actor's, which
    /// waits for it to end: the layout check waited the whole minute (17
    /// November).
    static func prepareInTask(language: String, newer: Bool = false) async {
        if let covers = makeGames() {
            let deadline = Date().addingTimeInterval(60)
            while !covers.loaded && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        show(language: language, newer: newer)
    }

    /// The games and the NAS's in the console, speaking LANGUAGE, the
    /// newest copy of the sheet's game's saves waiting for its update when
    /// NEWER.
    private static func show(language: String, newer: Bool) {
        let console = CartoucheMacConsole.shared
        let nas = language == "fr" ? "le NAS" : "the NAS"
        console.show(games: apps, kept: kept, keptIn: nas)
        let saves = newer ? CartoucheMacGameSaves(lastSync: copies[0].date, newer: "1.2.0", game: "1.0.0")
                          : CartoucheMacGameSaves(lastSync: copies[0].date, fetched: copies[1].date)
        console.showSaves(folder: CartoucheMacSavesFolder(name: nas, path: "/Volumes/Partage/Cartouche/Saves"),
                          games: [sheetGame: saves])
        console.speak(language)
    }

    /// Whether the covers are loaded, as the task loading them says.
    private final class Covers {
        var loaded = false
    }

    /// The games' apps, made once, shown by the console, their covers
    /// loading: nil when they were made before.
    private static func makeGames() -> Covers? {
        guard folder == nil else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartouche-gallery-\(UUID().uuidString)", isDirectory: true)
        self.folder = folder
        var apps: [URL] = []
        for game in games {
            let app = folder.appendingPathComponent("Applications/\(game.name).app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            // As nxnative writes them: the game's title ID, the macOS its
            // apps need.
            let info: [String: Any] = ["CFBundleIdentifier": "org.nxnative." + game.titleID.lowercased(),
                                       "CFBundleName": game.name, "CFBundlePackageType": "APPL",
                                       "DMTitleID": game.titleID, "LSMinimumSystemVersion": "26.6"]
            let dm = contents.appendingPathComponent("Resources/dm", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: dm, withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: contents.appendingPathComponent("Info.plist"))
                try Data(settings(of: game.titleID).utf8).write(to: dm.appendingPathComponent("launcher.json"))
                apps.append(app)
            } catch {
                FileHandle.standardError.write(Data("gallery: the console's game \(game.name): \(error)\n".utf8))
            }
        }
        self.apps = apps
        let console = CartoucheMacConsole.shared
        console.asksServer = false
        console.keepsChoicesInMemory = true
        console.dataFolder = folder.appendingPathComponent("nxnative", isDirectory: true)
        // The sheet's game's saves, a file of made-up bytes, for its saves
        // section and its Switch saves; their copies, without a saves folder.
        let saves = console.dataFolder.appendingPathComponent(sheetGame + "/save", isDirectory: true)
        try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try? Data(repeating: 0x2A, count: 4_096).write(to: saves.appendingPathComponent("save.dat"))
        console.onSaveCopies = { _ in copies }
        console.showForGallery(playTimes: playTimes, sizes: sizes)
        console.show(games: apps, kept: kept)

        let covers = Covers()
        Task { @MainActor in
            await console.loadCovers(everyGame: true)
            covers.loaded = true
        }
        return covers
    }

    /// The games' apps go once the pictures are taken.
    static func cleanUp() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        self.folder = nil
        apps = []
    }
}
