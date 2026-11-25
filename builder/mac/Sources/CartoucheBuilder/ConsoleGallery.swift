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
//  are the saves of the sheet's game and their copies, and the logs of its
//  last two sessions; the NAS's file is only a name, and nothing of the
//  player's is read or kept: no data folder or log of nxnative's, no saves
//  folder, no game's preferences, no play time, no journal or report, no
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

    /// The console with the gallery's games, speaking LANGUAGE (en, fr, es or de),
    /// the saves of the sheet's game kept in step with a NAS's share: the
    /// newest copy came, or, NEWER, it waits for the game's update, version
    /// 1.2.0 of the game having written it and this Mac's app being 1.0.0.
    /// The covers of the console's games are in memory before each page:
    /// every game's, which the French gallery's console library shows,
    /// leave the home's out of the cover store's memory, and the next
    /// language's home showed Cartouche's own drawings, or its covers half
    /// faded in, as its first page did (English, 25 November).
    static func prepare(language: String, newer: Bool = false, firstGame: Bool = false) {
        let covers = makeGames() ?? loadCovers()
        let deadline = Date().addingTimeInterval(60)
        while !covers.loaded && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        show(language: language, newer: newer, firstGame: firstGame)
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
        show(language: language, newer: newer, firstGame: false)
    }

    /// The games and the NAS's in the console, speaking LANGUAGE, the
    /// newest copy of the sheet's game's saves waiting for its update when
    /// NEWER; the guide to a first game for a player who has played none of
    /// them yet when FIRSTGAME, its card on the home, and done otherwise.
    private static func show(language: String, newer: Bool, firstGame: Bool) {
        let console = CartoucheMacConsole.shared
        let nas = named(language, "the NAS", "le NAS", "el NAS", "dem NAS")
        console.show(games: apps, kept: kept, keptIn: nas)
        let saves = newer ? CartoucheMacGameSaves(lastSync: copies[0].date, newer: "1.2.0", game: "1.0.0")
                          : CartoucheMacGameSaves(lastSync: copies[0].date, fetched: copies[1].date)
        console.showSaves(folder: CartoucheMacSavesFolder(name: nas, path: "/Volumes/Partage/Cartouche/Saves"),
                          games: [sheetGame: saves])
        // The Storage page: the NAS's folders under This Mac, and made-up
        // connections, kept in memory only.
        console.showFolders(games: URL(fileURLWithPath: "/Volumes/Jeux", isDirectory: true),
                            saves: URL(fileURLWithPath: "/Volumes/Partage/Cartouche/Saves", isDirectory: true))
        console.showStorageForGallery(language: language)
        // The games folder chosen on the iPhone, on the NAS: Mario Kart
        // World's Mac app going there, Animal Crossing's, another Mac's,
        // to install; and the other one the iPhone reads, on the Google
        // Drive, with another Mac's app too.
        console.showIPhoneGames(CartoucheMacGamesFolder(connection: CartoucheMacConsole.galleryNAS,
                                                        path: "Cartouche/" + named(language, "Games", "Jeux", "Juegos", "Spiele"),
                                                        state: .sending(game: "Mario Kart World", packing: false, done: 1_288_490_188,
                                                                        total: 2_915_000_000, index: 1, count: 2),
                                                        offers: 1,
                                                        others: [.init(connection: CartoucheMacConsole.galleryDrive,
                                                                       path: named(language, "Games", "Jeux", "Juegos", "Spiele"),
                                                                       offers: 1)]))
        // System › Game measurements: on, reports sent, the last one a
        // session of the sheet's game; a server, which the console never
        // reaches itself.
        CartoucheMacConsole.measuresServer = URL(string: "https://telemetry.example.invalid")
        console.showMeasures(CartoucheMacMeasures(isOn: true, sent: 48, waiting: 0, lastSent: copies[0].date, lastReport: lastReport))
        // System › Updates: this copy, up to date when its updater last
        // looked, an hour ago, as the app's would say; nothing asks GitHub.
        let updates = CartoucheMacUpdates.shared
        updates.version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        updates.enabled = true
        updates.checked = Date().addingTimeInterval(-3_600)
        updates.phase = .upToDate
        console.showGuideForGallery(played: !firstGame)
        console.speak(language)
    }

    /// The last report System › Game measurements opens: a made-up session
    /// of the sheet's game, as the console makes them.
    static let lastReport = #"{"schema":1,"kind":"session","id":"6a1d9e3c-0000-4000-8000-000000000048","seq":48,"#
        + #""install":"8c1f6c2e-7a2f-4e19-8c3d-2f6a9b0e1d7c","cartouche":"0.6.0","device":"Mac16,12","ios":"26.6","language":"fr","deviceLanguage":"fr","#
        + #""session":"c4d1b8e0-7a2f-4e19-8c3d-2f6a9b0e1d7c","game":"0400C3F00006E000","gameVersion":"1.0.0","#
        + #""nxnative":"6c3aeb3d70a1","nxnativeChanged":false,"settings":{"DM_FPS_TARGET":"60","DM_FULLSCREEN":"1"},"#
        + #""minutes":42,"reader":4,"frames":151200,"targetFps":60,"fps":{"median":60,"low5":58},"#
        + #""frameMs":{"p50":16.67,"p95":17.4,"p99":19.8},"gpuMs":{"p50":7.1,"p95":9.4},"droppedPercent":0.2,"#
        + #""stutters":{"count":3,"perMinute":0.07,"shaders":2,"textures":0,"other":1},"memory":{"peakMiB":5210,"exactPeak":false},"#
        + #""end":{"kind":"quit"}}"#

    /// WORDS in LANGUAGE: English, French, Spanish or German.
    private static func named(_ language: String, _ english: String, _ french: String, _ spanish: String,
                              _ german: String) -> String {
        ["fr": french, "es": spanish, "de": german][language] ?? english
    }

    /// Whether the covers are loaded, as the task loading them says.
    private final class Covers {
        var loaded = false
    }

    /// The covers and backdrops of the console's games, loading into the
    /// cover store's memory again, from its folder on disk.
    private static func loadCovers() -> Covers {
        let covers = Covers()
        Task { @MainActor in
            await CartoucheMacConsole.shared.loadCovers(everyGame: false)
            covers.loaded = true
        }
        return covers
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
        console.logsFolder = writeLogs(in: folder.appendingPathComponent("Logs/nxnative", isDirectory: true))
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

    /// The logs of the sheet's game's last two sessions in FOLDER, made up
    /// as nxnative's app for the Mac writes them, the one before ending in a
    /// crash; FOLDER, for the console to read them.
    private static func writeLogs(in folder: URL) -> URL {
        let start = [
            "launcher: Mario Kart World (\(sheetGame)), host /Applications/Mario Kart World.app/Contents/MacOS/dmhost",
            "launcher: env DM_FPS_TARGET=60 (saved choice)",
            "[dm] build: commit 6c3aeb3d70a1, shader chain 844bf1a5ea8f, profile mkw",
            "[dm] [nvn-mtl] pipeline prepare: 4210 lines (3000 shaders, 4000 render pipelines, 210 compute pipelines) in 6.20 s",
            "[dm] [nvn] timing up to frame 300: frame time p50 16.67 / p95 17.80 / max 40.00 ms (300 frames)",
        ].map { $0 + "\n" }.joined()
        let now = Date()
        let sessions: [(name: String, end: String, start: TimeInterval, minutes: Double)] = [
            (sheetGame + ".log", "launcher: the host exited with 0\n", -3 * 3_600 - 25 * 60, 25),
            (sheetGame + ".prev.log", "[dm] CRASH sig=11 (SIGSEGV) at main+0x1a2b3c\nlauncher: the host stopped on signal 11\n",
             -4 * 3_600, 22),
        ]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for session in sessions {
            let file = folder.appendingPathComponent(session.name)
            let started = now.addingTimeInterval(session.start)
            // A longer session writes more: lines of its frames.
            let frames = String(repeating: "[dm] [nvn] on-screen up to frame 600: 300 frames, dropped 0 (discarded 0), p99 17.50 ms\n",
                                count: Int(session.minutes * 40))
            try? Data((start + frames + session.end).utf8).write(to: file)
            try? FileManager.default.setAttributes([.creationDate: started,
                                                    .modificationDate: started.addingTimeInterval(session.minutes * 60)],
                                                   ofItemAtPath: file.path)
        }
        return folder
    }

    /// The made-up connections of the console's Storage page, named in
    /// LANGUAGE, kept in memory only: for the builder's iPhone page too,
    /// which names the NAS, the iPhone's games folder on it.
    static func showConnections(language: String) {
        CartoucheMacConsole.shared.showStorageForGallery(language: language)
    }

    /// The made-up NAS among them.
    static var nas: UUID { CartoucheMacConsole.galleryNAS }

    /// The games' apps go once the pictures are taken.
    static func cleanUp() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        self.folder = nil
        apps = []
    }
}
