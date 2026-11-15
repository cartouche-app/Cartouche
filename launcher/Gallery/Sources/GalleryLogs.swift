//
//  GalleryLogs.swift
//  CartoucheGallery
//
//  A game's logs for the gallery's screens of the log a game wrote
//  (CartoucheGameLogView, decision 101): -GalleryWork log, with
//  -GalleryScreen gamelog and gamelog-sent, and the sheet opened on the
//  game's management (-GalleryCategory manage), where its row shows.
//

import Foundation

/// The logs nxnative wrote of a game of the player's last two sessions, in
/// the gallery's Application Support (work: log), as a game's data folder
/// holds them: the last session, a quarter of an hour that ended in a
/// crash, and the one before. Their paths, folders, data folder and
/// nickname are made up, for the page of what Send to Cartouche sends to
/// show them cleaned.
enum GalleryLogs {
    /// The game whose logs these are, once the scenario has them.
    @MainActor private static var titleId: String?

    /// The game's Documents, where nxnative writes its logs.
    private static var documents: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GalleryLogs/Game/Documents", isDirectory: true)
    }

    @MainActor
    static func prepare(titleId: String) {
        let manager = FileManager.default
        try? manager.removeItem(at: documents)
        do {
            try manager.createDirectory(at: documents, withIntermediateDirectories: true)
            let now = Date()
            let before = documents.appendingPathComponent("log.prev.txt")
            try Data(session(frames: 54_000, crashed: false).utf8).write(to: before)
            try manager.setAttributes([.creationDate: now.addingTimeInterval(-3 * 3_600),
                                       .modificationDate: now.addingTimeInterval(-3 * 3_600 + 31 * 60)], ofItemAtPath: before.path)
            let last = documents.appendingPathComponent("log.txt")
            try Data(session(frames: 27_000, crashed: true).utf8).write(to: last)
            try manager.setAttributes([.creationDate: now.addingTimeInterval(-40 * 60),
                                       .modificationDate: now.addingTimeInterval(-25 * 60)], ofItemAtPath: last.path)
            self.titleId = titleId
        } catch {
            NSLog("[Gallery] cannot write the logs: %@", String(describing: error))
        }
    }

    /// The logs of APP, if it is the scenario's game.
    @MainActor
    static func folder(of app: LCAppModel) -> CartoucheGameLogFolder? {
        guard let titleId, app.appInfo.relativeBundlePath == titleId + ".app" else { return nil }
        return CartoucheGameLogFolder(game: app.displayName, titleId: titleId,
                                      build: CartoucheGameBuild(version: "1.0.0", commit: "7bddb8c1e2f3", chain: "adec7d81d970"),
                                      documents: documents)
    }

    /// The logs of FOLDER, read, as Send to Cartouche sends them.
    @MainActor
    static func share(of folder: CartoucheGameLogFolder) -> CartoucheGameLogShare {
        let logs = folder.files.compactMap { CartoucheGameLogDigest.read($0, name: $0.lastPathComponent) }
        var share = CartoucheGameLogView.share(of: folder, logs: logs)
        share.what = "Crashes at the start of the second race."
        return share
    }

    /// A session of FRAMES frames, as nxnative logs one.
    private static func session(frames: Int, crashed: Bool) -> String {
        let app = "/private/var/mobile/Containers/Data/Application/0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
        var lines = [
            "boot: game files \(app)/Documents/Data/Application/5A3C1B2D-0E4F-4A6B-8C7D-9E0F1A2B3C4D/Documents/romfs.img",
            "boot: env DM_NICK=Lou (env.txt)",
            "boot: cloud saves through /private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Saves d'Élodie",
            "[dm] build: commit 7bddb8c1e2f3, shader chain adec7d81d970, profile mkw, title 0400C3F00006E000",
            "[RED] [nvn] texture format 0x2b not supported: drawn black",
        ]
        for frame in stride(from: 300, through: frames, by: 300) {
            let slow = (frame / 300) % 7
            lines.append("[dm] [nvn] frame interval up to frame \(frame): >16.7ms \(slow) / 300 frames, p99 \(30 + slow).40 ms")
        }
        if crashed {
            lines += [
                "[dm] CRASH sig=11 addr=0x10 pc=main+0x1a2b3c lr=main+0x1a2b00 sp=0x16fdff000",
                "x0=0x0 x1=0x16fdff120 x2=0x2 x3=0x3 x4=0x4 x5=0x5",
                "[dm] *x1: 0x16fdff200 main+0x40 0 0x6c6c6548206f6c6c 0x1 0x16fdff300",
                "[dm] bt: main+0x1a2b00 main+0x1a0000 nnSdk+0x1234",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
