//
//  CartoucheChosenFoldersTests.swift
//  CartoucheCoreTests
//
//  The folders for the games and the saves as the player changes them on
//  the Storage page of the Mac's console (Sources/CartoucheConnections.swift,
//  CartoucheChosenFolders.changing): chosen then, they win over what an
//  iPhone chose before, and lose to what one chooses later; Change folder
//  puts one of the other games folders first, Add another games folder
//  goes after the others, Stop reading this folder lets the next take the
//  games folder's place; the saves folder changes alone. The change goes
//  from the console to the app as JSON. How an iPhone takes them back is
//  tested with Cartouche's storage (launcher/StorageTests,
//  ConnectionsExchangeTests and GamesFoldersTests).
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheChosenFoldersTests: XCTestCase {
    typealias Folder = CartoucheChosenFolders.Folder

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let nas = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    let drive = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
    let bucket = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000003")!

    func testAFolderChangedOnTheMacWinsOverTheIPhonesUntilOneChoosesLater() {
        let saves = Folder(connection: nas, path: "Sauvegardes", chosen: now)
        let told = CartoucheChosenFolders(games: Folder(connection: nas, path: "Jeux", chosen: now), saves: saves,
                                          otherGames: [Folder(connection: drive, path: "Jeux", chosen: now)])
        // Change folder: the bucket's in the place of the NAS's, the
        // Drive's still read after it, all chosen now.
        let changed = told.changing(.games(connection: bucket, path: "jeux"), at: now + 60)
        XCTAssertEqual(changed.games, Folder(connection: bucket, path: "jeux", chosen: now + 60))
        XCTAssertEqual(changed.otherGames, [Folder(connection: drive, path: "Jeux", chosen: now + 60)])
        XCTAssertEqual(changed.saves, saves, "the saves folder stays as it was chosen")
        // The iPhone telling again what it chose before changes nothing.
        XCTAssertEqual(changed.taking(told), changed)
        // An iPhone choosing later still wins.
        let later = Folder(connection: nas, path: "Jeux", chosen: now + 120)
        XCTAssertEqual(changed.taking(CartoucheChosenFolders(games: later)).games, later)

        // One of the other games folders chosen as the games folder leaves
        // its place among them.
        let swapped = told.changing(.games(connection: drive, path: "Jeux"), at: now + 60)
        XCTAssertEqual(swapped.games, Folder(connection: drive, path: "Jeux", chosen: now + 60))
        XCTAssertNil(swapped.otherGames)

        // The saves folder changes alone.
        let moved = told.changing(.saves(connection: drive, path: "Saves"), at: now + 60)
        XCTAssertEqual(moved.saves, Folder(connection: drive, path: "Saves", chosen: now + 60))
        XCTAssertEqual(moved.games, told.games)
        XCTAssertEqual(moved.otherGames, told.otherGames)
        XCTAssertEqual(moved.taking(told), moved)
    }

    func testGamesFoldersAddedAndStoppedOnTheMac() {
        let told = CartoucheChosenFolders(games: Folder(connection: nas, path: "Jeux", chosen: now))
        let added = told.changing(.addGames(connection: drive, path: "Jeux"), at: now + 60)
        XCTAssertEqual(added.games, Folder(connection: nas, path: "Jeux", chosen: now + 60))
        XCTAssertEqual(added.otherGames, [Folder(connection: drive, path: "Jeux", chosen: now + 60)])
        // The same folder again, or the games folder: nothing more.
        XCTAssertEqual(added.changing(.addGames(connection: drive, path: "Jeux"), at: now + 90).otherGames?.map(\.connection), [drive])
        XCTAssertEqual(added.changing(.addGames(connection: nas, path: "Jeux"), at: now + 90).otherGames?.map(\.connection), [drive])

        // Stop reading the other one.
        let stopped = added.changing(.removeGames(connection: drive, path: "Jeux"), at: now + 120)
        XCTAssertEqual(stopped.games, Folder(connection: nas, path: "Jeux", chosen: now + 120))
        XCTAssertNil(stopped.otherGames)
        // Stop reading the games folder: the next one takes its place.
        let next = added.changing(.removeGames(connection: nas, path: "Jeux"), at: now + 120)
        XCTAssertEqual(next.games, Folder(connection: drive, path: "Jeux", chosen: now + 120))
        XCTAssertNil(next.otherGames)
        // The last one: none, chosen then.
        let none = next.changing(.removeGames(connection: drive, path: "Jeux"), at: now + 180)
        XCTAssertEqual(none.games, Folder(connection: nil, path: "", chosen: now + 180))
        XCTAssertNil(none.otherGames)

        // Told of none yet: the folder added is the games folder.
        let first = CartoucheChosenFolders().changing(.addGames(connection: nas, path: "Jeux"), at: now)
        XCTAssertEqual(first.games, Folder(connection: nas, path: "Jeux", chosen: now))
        XCTAssertNil(first.otherGames)
        XCTAssertNil(first.saves)
    }

    /// The iPhone's games folder on none of the connections, as the Mac
    /// itself through the bridge: one chosen on the Mac takes its place
    /// there, the iPhone keeping its own after it (take(folders:)).
    func testAGamesFolderOnNoConnectionGivesWayToOneChosenOnTheMac() {
        let ownMac = Folder(connection: nil, path: "", chosen: now)
        let told = CartoucheChosenFolders(games: ownMac, otherGames: [Folder(connection: drive, path: "Jeux", chosen: now)])
        let chosen = told.changing(.games(connection: nas, path: "Jeux"), at: now + 60)
        XCTAssertEqual(chosen.games, Folder(connection: nas, path: "Jeux", chosen: now + 60))
        XCTAssertEqual(chosen.otherGames, [Folder(connection: drive, path: "Jeux", chosen: now + 60)])

        let saves = CartoucheChosenFolders(games: ownMac).changing(.saves(connection: nas, path: "Sauvegardes"), at: now + 60)
        XCTAssertEqual(saves.saves, Folder(connection: nas, path: "Sauvegardes", chosen: now + 60))
        XCTAssertEqual(saves.games, ownMac)
    }

    /// The console's copy of the type and CartoucheCore's are the same
    /// source: what one writes, the other reads.
    func testAChangeGoesFromTheConsoleToTheAppAsJSON() throws {
        let changes: [CartoucheChosenFolders.Change] = [
            .games(connection: nas, path: "Jeux"), .addGames(connection: drive, path: "Jeux"),
            .removeGames(connection: drive, path: "Jeux"), .saves(connection: bucket, path: "Cartouche/Saves"),
        ]
        for change in changes {
            XCTAssertEqual(try JSONDecoder().decode(CartoucheChosenFolders.Change.self, from: JSONEncoder().encode(change)), change)
        }
        XCTAssertNotEqual(changes[0], .addGames(connection: nas, path: "Jeux"))
    }
}
