//
//  CartoucheBackupTests.swift
//  CartoucheCoreTests
//
//  The mark that leaves a game out of the iPhone's backups
//  (Sources/CartoucheBackup.swift): on 24 November 2026, a player's next
//  iCloud backup was to take 43.74 GB more, the games Cartouche had
//  installed, which nothing marked, and iOS showed no switch for Cartouche
//  to leave it out (#302).
//

import XCTest
@testable import CartoucheCore

final class CartoucheBackupTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartoucheBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The games' folder and a game's app, marked, as an install marks
    /// them; the data folder beside them, where the saves are, is not.
    func testMarksTheFoldersItIsGivenAndNothingElse() throws {
        let games = try made("Applications")
        let app = try made("Applications/com.example.game.app")
        let data = try made("Data/Application/1234")

        XCTAssertFalse(CartoucheBackup.isLeftOut(games), "nothing marked yet")
        XCTAssertEqual(CartoucheBackup.leaveOut([games, app]), [])

        XCTAssertTrue(CartoucheBackup.isLeftOut(games))
        XCTAssertTrue(CartoucheBackup.isLeftOut(app))
        XCTAssertFalse(CartoucheBackup.isLeftOut(data), "the saves stay in the backups")
        XCTAssertFalse(CartoucheBackup.isLeftOut(folder))
    }

    /// Marked again, as each start of Cartouche marks the games: nothing
    /// changes, and nothing fails.
    func testMarkingAgainChangesNothing() throws {
        let app = try made("Applications/com.example.game.app")
        XCTAssertEqual(CartoucheBackup.leaveOut([app]), [])
        XCTAssertEqual(CartoucheBackup.leaveOut([app]), [])
        XCTAssertTrue(CartoucheBackup.isLeftOut(app))
    }

    /// The mark goes with the app it was set on, but a folder made again
    /// comes without one: why Cartouche marks the games' folder and each
    /// game's app, and again as it starts.
    func testTheMarkGoesWithTheItemNotThePlace() throws {
        let unpacked = try made("Install/Payload/com.example.game.app")
        CartoucheBackup.leaveOut([unpacked])
        let games = try made("Applications")
        let installed = games.appendingPathComponent("com.example.game.app", isDirectory: true)
        try FileManager.default.moveItem(at: unpacked, to: installed)
        XCTAssertTrue(CartoucheBackup.isLeftOut(installed), "moved with its mark")
        XCTAssertFalse(CartoucheBackup.isLeftOut(games), "its new folder has none of its own")

        CartoucheBackup.leaveOut([games])
        try FileManager.default.removeItem(at: games)
        let again = try made("Applications")
        XCTAssertFalse(CartoucheBackup.isLeftOut(again), "a folder made again comes without the mark")
    }

    /// An app gone since Cartouche listed it: said, never thrown, and the
    /// others marked all the same.
    func testWhatIsGoneIsSaidAndTheRestMarked() throws {
        let gone = folder.appendingPathComponent("Applications/com.example.gone.app", isDirectory: true)
        let app = try made("Applications/com.example.game.app")
        XCTAssertEqual(CartoucheBackup.leaveOut([gone, app]), [gone])
        XCTAssertTrue(CartoucheBackup.isLeftOut(app))
        XCTAssertFalse(CartoucheBackup.isLeftOut(gone))
    }

    private func made(_ path: String) throws -> URL {
        let url = folder.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
