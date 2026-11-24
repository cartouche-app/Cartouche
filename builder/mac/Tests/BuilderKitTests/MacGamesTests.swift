//
//  MacGamesTests.swift
//  BuilderKitTests
//
//  The games played on this Mac, on what needs no game: the processes the
//  builder follows, the saves folder it uses (MacGames.swift). A game
//  played from end to end is in EndToEndTests.swift.
//

import Foundation
import XCTest
@testable import BuilderKit

/// A saves folder on a connection, as the console reaches it: none of it
/// is asked here.
private final class Connection: MacConnectionSavesDriver, @unchecked Sendable {
    let connection = UUID()
    let path = "Cartouche/Saves"
    var place: String { connection.uuidString + "|" + path }

    func sync(_ game: MacSaveGame, documents: URL, base: Data?, fetching: Bool, leaving: @escaping @Sendable () -> Bool,
              quiet: @Sendable () -> Bool, replacing: String?) async throws -> MacConnectionOutcome {
        throw MacSavesError.offline
    }

    func putBack(_ name: String, of game: MacSaveGame, documents: URL, base: Data?,
                 quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome {
        throw MacSavesError.offline
    }

    func copies(of game: MacSaveGame, documents: URL) async throws -> [MacSaveCopyInfo] { [] }
}

final class MacGamesTests: XCTestCase {
    /// LaunchServices says -1 of a game that ended as soon as it started,
    /// which kill() takes for every process the builder may signal, and 0
    /// for its own group: neither is a game running.
    func testOnlyAProcessOfItsOwnIsAlive() {
        XCTAssertFalse(MacGames.alive(-1))
        XCTAssertFalse(MacGames.alive(0))
        XCTAssertTrue(MacGames.alive(getpid()))
    }

    /// The saves folder: the Mac's own, or the iPhone's on a connection,
    /// the one in use staying when it is the same.
    @MainActor
    func testTheSavesFolderIsTheMacsOrTheIPhonesOnAConnection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-games-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let games = MacGames(store: root.appendingPathComponent("mac-saves.json"), scratch: root.appendingPathComponent("scratch"),
                             games: root.appendingPathComponent("nxnative", isDirectory: true), sample: true)
        XCTAssertNil(games.folder)
        let own = root.appendingPathComponent("Saves", isDirectory: true)
        games.use(saves: own)
        XCTAssertEqual(games.folder?.place, "mac|" + own.standardizedFileURL.path)
        XCTAssertNil(games.folder?.connection)

        let connection = Connection()
        games.use(connection: connection)
        let used = try XCTUnwrap(games.folder as? MacConnectionSaves)
        XCTAssertEqual(used.place, connection.place)
        XCTAssertEqual(used.connection, connection.connection)
        XCTAssertEqual(used.path, "Cartouche/Saves")
        // Told again: the same one stays, with what it holds.
        games.use(connection: connection)
        XCTAssertTrue(games.folder === used)
        // Turned off.
        games.use(saves: nil)
        XCTAssertNil(games.folder)
    }
}
