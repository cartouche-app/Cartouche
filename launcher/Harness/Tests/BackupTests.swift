//
//  BackupTests.swift
//  CartoucheHarnessTests
//
//  The games Cartouche installs, out of the iPhone's backups, iCloud's
//  among them, and their saves in them (decision 153, #302): a game
//  installed from its IPA, another build of it, and the games a Cartouche
//  installed before it marked them, as Cartouche starts, in its own folder
//  of games and in the app group's.
//

import XCTest
@testable import CartoucheHarness

final class BackupTests: HarnessCase {
    func testAnInstalledGameIsLeftOutOfTheBackupsAndItsSavesAreNot() async throws {
        let app = try await installed(HarnessGame.plain())
        let bundle = try bundle(of: app)

        XCTAssertTrue(CartoucheBackup.isLeftOut(LCPath.bundlePath), "Cartouche's folder of games, and all it holds")
        XCTAssertTrue(CartoucheBackup.isLeftOut(bundle), "the game's app, wherever it goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("romfs.img").path),
                      "with the game's files, in its app")

        // Its first start made its data folder, where it saves: in the backups.
        _ = actions.settings(for: app, tileKey: "")
        let folder = try dataFolder(of: app)
        try write("level 12", in: folder, at: "Documents/save/slot1.bin")
        XCTAssertFalse(CartoucheBackup.isLeftOut(folder), "the game's saves stay in the backups")
        XCTAssertFalse(CartoucheBackup.isLeftOut(LCPath.dataPath))
        XCTAssertFalse(CartoucheBackup.isLeftOut(LCPath.docPath), "the rest of Cartouche's stays in them")
    }

    func testAnotherBuildOfTheGameIsLeftOutToo() async throws {
        var game = HarnessGame.plain()
        let first = try await installed(game)
        game.version = "1.1.0"
        game.commit = "0d9b6358aa11bb22cc33dd44ee55ff6677889900"
        let second = try await installed(game)

        XCTAssertEqual(second.appInfo.relativeBundlePath, first.appInfo.relativeBundlePath, "in the place of the first")
        XCTAssertTrue(CartoucheBackup.isLeftOut(try bundle(of: second)), "the new app, which came without the mark")
        XCTAssertTrue(CartoucheBackup.isLeftOut(LCPath.bundlePath))
    }

    func testTheGamesFolderMadeAgainIsMarkedAtTheNextInstall() async throws {
        _ = try await installed(HarnessGame.plain())
        // Emptied and made again, as LiveContainer makes it when it is gone.
        try FileManager.default.removeItem(at: LCPath.bundlePath)
        try FileManager.default.createDirectory(at: LCPath.bundlePath, withIntermediateDirectories: true)
        XCTAssertFalse(CartoucheBackup.isLeftOut(LCPath.bundlePath))
        HarnessLC.loadApps()

        let other = try await installed(HarnessGame.plain(1))
        XCTAssertTrue(CartoucheBackup.isLeftOut(LCPath.bundlePath))
        XCTAssertTrue(CartoucheBackup.isLeftOut(try bundle(of: other)))
    }

    /// Games a Cartouche installed before it marked them, one in its own
    /// folder of games and one LiveContainer shares through the app group:
    /// marked as Cartouche starts, the app group's folder itself left as it
    /// is, which another LiveContainer of the player's may use.
    func testTheGamesInstalledBeforeAreLeftOutAsCartoucheStarts() async throws {
        let own = try await installed(HarnessGame.plain())
        let moved = try await installed(HarnessGame.plain(1))
        let ownBundle = try bundle(of: own)
        try FileManager.default.createDirectory(at: LCPath.lcGroupBundlePath, withIntermediateDirectories: true)
        let sharedBundle = LCPath.lcGroupBundlePath.appendingPathComponent(try XCTUnwrap(moved.appInfo.relativeBundlePath))
        try FileManager.default.moveItem(at: try bundle(of: moved), to: sharedBundle)
        // Without the mark, as an older Cartouche left them.
        for url in [LCPath.bundlePath, ownBundle, sharedBundle] {
            try unmark(url)
        }
        HarnessLC.loadApps()
        let shared = try XCTUnwrap(app(HarnessGame.plain(1).bundleIdentifier))
        XCTAssertTrue(shared.uiIsShared, "LiveContainer lists it from the app group")

        let failed = await CartoucheGameActions.leaveGamesOutOfBackups(of: model)

        XCTAssertEqual(failed, [])
        XCTAssertTrue(CartoucheBackup.isLeftOut(LCPath.bundlePath))
        XCTAssertTrue(CartoucheBackup.isLeftOut(ownBundle))
        XCTAssertTrue(CartoucheBackup.isLeftOut(sharedBundle), "Cartouche's game in the app group")
        XCTAssertFalse(CartoucheBackup.isLeftOut(LCPath.lcGroupBundlePath), "the app group's folder is not Cartouche's alone")
        XCTAssertEqual(model.apps.count, 2, "nothing else changes")
    }

    private func unmark(_ url: URL) throws {
        var marked = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try marked.setResourceValues(values)
        XCTAssertFalse(CartoucheBackup.isLeftOut(url))
    }
}
