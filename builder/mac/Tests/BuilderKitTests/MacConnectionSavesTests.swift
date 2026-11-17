//
//  MacConnectionSavesTests.swift
//  BuilderKitTests
//
//  The iPhone's saves folder on one of the player's connections, as this
//  Mac keeps its games' saves in step with it through Cartouche's console
//  (MacConnectionSaves.swift): the base the console gives is the one the
//  Mac keeps and gives back, from one copy of CartoucheCore's types to the
//  other; saves kept in step with a folder of this Mac's say whether their
//  copy is still there; what the console could not do is the Mac's to say.
//  The console's side, the iPhone's code, is tested with Cartouche's
//  storage (launcher/StorageTests, StorageServerTests).
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

/// The console, as the app drives it: what it was asked, and what it
/// answers, in turn.
private final class Console: MacConnectionSavesDriver, @unchecked Sendable {
    struct Asked: Equatable {
        var base: CartoucheSaveBase?
        var fetching: Bool
        /// What LEAVING said.
        var leftThere: Bool
        var documents: URL
    }

    let connection = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    let path = "Cartouche/Saves"
    var place: String { connection.uuidString + "|" + path }
    var answers: [Result<MacConnectionOutcome, Error>] = []
    var asked: [Asked] = []
    var copies: [MacSaveCopyInfo] = []
    var putBack: [String] = []

    private func answer() throws -> MacConnectionOutcome {
        guard !answers.isEmpty else { return MacConnectionOutcome(step: "none", base: nil) }
        return try answers.removeFirst().get()
    }

    func sync(_ game: MacSaveGame, documents: URL, base: Data?, fetching: Bool, leaving: @escaping @Sendable () -> Bool,
              quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome {
        asked.append(Asked(base: base.flatMap { try? JSONDecoder().decode(CartoucheSaveBase.self, from: $0) }, fetching: fetching,
                           leftThere: leaving(), documents: documents))
        return try answer()
    }

    func putBack(_ name: String, of game: MacSaveGame, documents: URL, base: Data?,
                 quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome {
        putBack.append(name)
        return try answer()
    }

    func copies(of game: MacSaveGame, documents: URL) async throws -> [MacSaveCopyInfo] {
        copies
    }
}

final class MacConnectionSavesTests: XCTestCase {
    private var root: URL!
    private let game = MacSaveGame(titleID: "0100152000022000", name: "Mario Kart 8 Deluxe", version: "3.0.1")
    private let t0 = Date(timeIntervalSince1970: 1_794_506_520)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-connection-saves-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var games: URL { root.appendingPathComponent("nxnative", isDirectory: true) }
    private var scratch: URL { root.appendingPathComponent("scratch", isDirectory: true) }

    private var store: MacSaveStore!

    private func keeper() -> MacSaveKeeper {
        store = MacSaveStore(url: root.appendingPathComponent("mac-saves.json"))
        return MacSaveKeeper(store: store)
    }

    private func json(_ base: CartoucheSaveBase) throws -> Data {
        try JSONEncoder().encode(base)
    }

    func testTheMacKeepsTheBaseTheConsoleGivesAndGivesItBack() async throws {
        let console = Console()
        let place = MacConnectionSaves(driver: console, games: games, scratch: scratch)
        XCTAssertEqual(place.place, console.place)
        XCTAssertEqual(place.connection, console.connection)
        XCTAssertEqual(place.path, "Cartouche/Saves")
        XCTAssertTrue(place.onShare)
        let sent = CartoucheSaveSync.fileName(t0)
        let base = CartoucheSaveBase(place: console.place, copy: sent, content: "a1b2", look: "2|300|1794506520000", gameVersion: "3.0.1")
        console.answers = [.success(MacConnectionOutcome(step: "send", base: try json(base), sent: sent))]
        let keeper = keeper()

        // After a game: the saves of this Mac go, as the console says.
        let synced = await keeper.sync(game, in: place, when: .after, now: t0)
        let event = try XCTUnwrap(synced)
        XCTAssertEqual(event.step, "send")
        XCTAssertEqual(event.sent, sent)
        XCTAssertEqual(store.record(game.titleID).base, base)
        XCTAssertEqual(console.asked.last?.fetching, false)
        XCTAssertEqual(console.asked.last?.documents, games.appendingPathComponent(game.titleID, isDirectory: true))

        // The next sync gives it back, as the console's own type reads it;
        // nothing moving, it stays.
        console.answers = [.success(MacConnectionOutcome(step: "none", base: try json(base)))]
        let quiet = await keeper.sync(game, in: place, when: .round, now: t0 + 60)
        XCTAssertNil(quiet)
        XCTAssertEqual(console.asked.last?.base, base)
        XCTAssertEqual(console.asked.last?.fetching, true)
        XCTAssertEqual(console.asked.last?.leftThere, false, "the base is this folder's")
        XCTAssertEqual(store.record(game.titleID).base, base)

        // A copy put back, through the console too.
        let fetched = CartoucheSaveSync.fileName(t0 - 3_600)
        let after = CartoucheSaveBase(place: console.place, copy: CartoucheSaveSync.fileName(t0 + 120), content: "c3", look: "2|310|1")
        console.answers = [.success(MacConnectionOutcome(step: "fetch", base: try json(after), sent: after.copy, fetched: fetched))]
        let putBack = try await keeper.putBack(fetched, of: game, in: place, now: t0 + 120)
        XCTAssertEqual(console.putBack, [fetched])
        XCTAssertEqual(putBack.step, MacSaveEvent.putBack)
        XCTAssertEqual(putBack.fetched, fetched)
        XCTAssertEqual(store.record(game.titleID).base, after)
    }

    func testSavesKeptInStepWithAFolderOfThisMacSayWhetherTheirCopyIsStillThere() async throws {
        // The Mac kept the game's saves in step with its own saves folder.
        let own = root.appendingPathComponent("Saves", isDirectory: true)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let documents = games.appendingPathComponent(game.titleID, isDirectory: true)
        let save = documents.appendingPathComponent("save/save0.bin")
        try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partie du Mac".utf8).write(to: save)
        try FileManager.default.setAttributes([.modificationDate: t0], ofItemAtPath: save.path)
        let keeper = keeper()
        let folder = MacSavesFolder(root: own, games: games, scratch: scratch)
        let first = await keeper.sync(game, in: folder, when: .after, now: t0)
        let sent = try XCTUnwrap(first)
        XCTAssertEqual(sent.step, "send")
        let left = try XCTUnwrap(store.record(game.titleID).base)
        XCTAssertTrue(left.place.hasPrefix("mac|"))

        // The player chose the iPhone's on a connection since: the console
        // hears of the base left, and that its copy is still there.
        let console = Console()
        let place = MacConnectionSaves(driver: console, games: games, scratch: scratch)
        console.answers = [.success(MacConnectionOutcome(step: "none", base: try json(left)))]
        _ = await keeper.sync(game, in: place, when: .after, now: t0 + 60)
        XCTAssertEqual(console.asked.last?.base, left)
        XCTAssertEqual(console.asked.last?.leftThere, true)
        // Its copy gone from there: they are kept in the new one first.
        try FileManager.default.removeItem(at: own.appendingPathComponent(MacSavesFolder.folderName(game)).appendingPathComponent(left.copy))
        _ = await keeper.sync(game, in: place, when: .after, now: t0 + 120)
        XCTAssertEqual(console.asked.last?.leftThere, false)
        // A base of another connection is never looked at here.
        var other = left
        other.place = UUID().uuidString + "|Saves"
        store.set(game.titleID, MacSaveRecord(base: other))
        _ = await keeper.sync(game, in: place, when: .after, now: t0 + 180)
        XCTAssertEqual(console.asked.last?.base, other)
        XCTAssertEqual(console.asked.last?.leftThere, false)
    }

    func testWhatTheConsoleCouldNotDoIsTheMacsToSay() async throws {
        let console = Console()
        let place = MacConnectionSaves(driver: console, games: games, scratch: scratch)
        let keeper = keeper()
        // A server that does not answer: offline, once.
        console.answers = [.failure(MacSavesError.offline), .failure(MacSavesError.offline)]
        let away = await keeper.sync(game, in: place, when: .round, now: t0)
        let offline = try XCTUnwrap(away)
        XCTAssertTrue(offline.offline)
        let still = await keeper.sync(game, in: place, when: .round, now: t0 + 60)
        XCTAssertNil(still, "still offline: the time it started to stays")
        // The game started meanwhile: nothing to say, and nothing recorded.
        console.answers = [.failure(MacSavesError.busy)]
        let busy = await keeper.sync(game, in: place, when: .round, now: t0 + 120)
        XCTAssertNil(busy)
        XCTAssertEqual(store.record(game.titleID).last, offline)
        // A step this Mac does not know is a failure, which changes nothing.
        console.answers = [.success(MacConnectionOutcome(step: "teleport", base: nil))]
        let unknown = await keeper.sync(game, in: place, when: .round, now: t0 + 180)
        let failed = try XCTUnwrap(unknown)
        XCTAssertTrue(failed.failed)
        // The copies, as the console lists them.
        console.copies = [MacSaveCopyInfo(name: CartoucheSaveSync.fileName(t0), date: t0, size: 512)]
        let copies = try await place.listCopies(of: game)
        XCTAssertEqual(copies, console.copies)
    }
}
