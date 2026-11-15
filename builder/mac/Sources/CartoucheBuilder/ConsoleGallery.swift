//
//  ConsoleGallery.swift
//  Cartouche Builder
//
//  Cartouche's console in the gallery (Gallery.swift): its home with the
//  sheet of the game in focus beside it, and every game, as the console
//  shows the games built for this Mac, and one a NAS keeps that is not
//  installed here, in the window as the app shows it (MainView). The games
//  are real ones nxnative builds, with their covers from IGDB as the
//  console shows them; their apps are the gallery's own, empty, in a
//  temporary folder, the NAS's file is only a name, and nothing of the
//  player's is read: no data folder of nxnative's, no question to
//  Cartouche's server. Like ConsoleWindow.swift, this file imports the
//  console and not CartoucheCore, whose names it shares.
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

    private static var folder: URL?
    private static var apps: [URL] = []

    /// The console with the gallery's games, speaking LANGUAGE ("fr" or "en").
    static func prepare(language: String) {
        show()
        let console = CartoucheMacConsole.shared
        console.show(games: apps, kept: kept, keptIn: language == "fr" ? "le NAS" : "the NAS")
        console.speak(language)
    }

    /// The games' apps, made once, shown by the console, and their covers
    /// loaded, a minute at most.
    private static func show() {
        guard folder == nil else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartouche-gallery-\(UUID().uuidString)", isDirectory: true)
        self.folder = folder
        var apps: [URL] = []
        for game in games {
            let app = folder.appendingPathComponent("Applications/\(game.name).app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            let info: [String: Any] = ["CFBundleIdentifier": "org.nxnative." + game.titleID.lowercased(),
                                       "CFBundleName": game.name, "CFBundlePackageType": "APPL"]
            do {
                try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                    .write(to: contents.appendingPathComponent("Info.plist"))
                apps.append(app)
            } catch {
                FileHandle.standardError.write(Data("gallery: the console's game \(game.name): \(error)\n".utf8))
            }
        }
        self.apps = apps
        let console = CartoucheMacConsole.shared
        console.asksServer = false
        console.dataFolder = folder.appendingPathComponent("nxnative", isDirectory: true)
        console.show(games: apps, kept: kept)

        final class Done { var value = false }
        let done = Done()
        Task { @MainActor in
            await console.loadCovers(everyGame: true)
            done.value = true
        }
        let deadline = Date().addingTimeInterval(60)
        while !done.value && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// The games' apps go once the pictures are taken.
    static func cleanUp() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        self.folder = nil
        apps = []
    }
}
