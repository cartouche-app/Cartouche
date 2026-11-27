//
//  CartoucheHomeFilterTests.swift
//  CartoucheCoreTests
//
//  The home's filter (Sources/CartoucheHomeFilter.swift): every game, those
//  installed or those not installed, offered while the player has games of
//  both kinds; no game taken away from under the player, nor the game
//  paused behind the console; the focus on its game as the shelf changes;
//  the player's choice kept; and its `home.filtered` event, which the
//  server takes and the telemetry's README tells.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheHomeFilterTests: XCTestCase {
    private func installed(_ key: String) -> CartoucheHomeShelfGame {
        CartoucheHomeShelfGame(key: key, isInstalled: true)
    }

    private func notInstalled(_ key: String) -> CartoucheHomeShelfGame {
        CartoucheHomeShelfGame(key: key, isInstalled: false)
    }

    /// Bananza and Link's Awakening installed, Mario Kart World and 13
    /// Sentinels on the player's Mac, the shelf ordering them by name.
    private var shelf: [CartoucheHomeShelfGame] {
        [notInstalled("01003FC01670C000"), installed("040074A01BF12000"), notInstalled("0400C3F00006E000"),
         installed("01006BB00C6F0000")]
    }

    // MARK: Which games

    func testEachFilterShowsItsGamesInTheShelfsOrder() {
        XCTAssertEqual(CartoucheHomeShelf.shown(shelf, filter: .all, kept: []), [0, 1, 2, 3])
        XCTAssertEqual(CartoucheHomeShelf.shown(shelf, filter: .installed, kept: []), [1, 3])
        XCTAssertEqual(CartoucheHomeShelf.shown(shelf, filter: .notInstalled, kept: []), [0, 2])
    }

    /// With games of one kind only, there is nothing to sort: no filter,
    /// and every game, whatever the player chose before, so that Not
    /// installed never leaves a shelf without games once the last one is
    /// installed.
    func testTheFilterIsOfferedOnlyWithGamesOfBothKinds() {
        XCTAssertTrue(CartoucheHomeShelf.offersFilter(shelf))
        let allInstalled = [installed("040074A01BF12000"), installed("01006BB00C6F0000")]
        let noneInstalled = [notInstalled("01003FC01670C000"), notInstalled("0400C3F00006E000")]
        for games in [allInstalled, noneInstalled, []] {
            XCTAssertFalse(CartoucheHomeShelf.offersFilter(games))
            for filter in CartoucheHomeFilter.allCases {
                XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: filter, kept: []), Array(games.indices), "\(filter)")
            }
        }
    }

    /// Mario Kart World installed from Not installed stays on the shelf,
    /// to play it, and Bananza uninstalled from Installed too, until the
    /// player chooses a filter again or the home opens again, which keeps
    /// nothing.
    func testAGameTheShelfShowedStaysThereOnceInstalledOrUninstalled() {
        var games = shelf
        games[2] = installed("0400C3F00006E000")
        let shownBefore: Set<String> = ["01003FC01670C000", "0400C3F00006E000"]
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .notInstalled, kept: shownBefore), [0, 2])
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .notInstalled, kept: []), [0])

        games = shelf
        games[1] = notInstalled("040074A01BF12000")
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .installed, kept: ["040074A01BF12000", "01006BB00C6F0000"]), [1, 3])
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .installed, kept: []), [3])
    }

    /// The game paused behind the console shows whatever the filter, with
    /// Resume.
    func testTheGamePausedBehindTheConsoleAlwaysShows() {
        var games = shelf
        games[3].isRunning = true
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .notInstalled, kept: []), [0, 2, 3])
        XCTAssertEqual(CartoucheHomeShelf.shown(games, filter: .installed, kept: []), [1, 3])
    }

    // MARK: The focus

    func testTheFocusStaysOnItsGameAsTheShelfChanges() {
        let every = ["01003FC01670C000", "040074A01BF12000", "0400C3F00006E000", "01006BB00C6F0000"]
        let installedOnly = ["040074A01BF12000", "01006BB00C6F0000"]
        // Link's Awakening, fourth, then second.
        XCTAssertEqual(CartoucheHomeShelf.column(3, from: every, to: installedOnly), 1)
        XCTAssertEqual(CartoucheHomeShelf.column(1, from: installedOnly, to: every), 3)
        // Mario Kart World filtered out: the game that took its place, else
        // the last.
        XCTAssertEqual(CartoucheHomeShelf.column(2, from: every, to: ["01003FC01670C000", "040074A01BF12000", "01006BB00C6F0000"]), 2)
        XCTAssertEqual(CartoucheHomeShelf.column(2, from: every, to: installedOnly), 1)
        XCTAssertEqual(CartoucheHomeShelf.column(0, from: ["01003FC01670C000"], to: []), 0)
        // Import a game and All games, after the games, stay in focus.
        XCTAssertEqual(CartoucheHomeShelf.column(4, from: every, to: installedOnly), 2)
        XCTAssertEqual(CartoucheHomeShelf.column(3, from: installedOnly, to: every), 5)
        // The player's first game, imported from Import a game: in focus,
        // with Play.
        XCTAssertEqual(CartoucheHomeShelf.column(0, from: [], to: ["040074A01BF12000"]), 0)
    }

    // MARK: The player's choice

    func testThePlayersChoiceIsKept() throws {
        let suite = "CartoucheHomeFilterTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CartoucheHomeFilter.saved(in: defaults), .all)
        CartoucheHomeFilter.notInstalled.save(in: defaults)
        XCTAssertEqual(CartoucheHomeFilter.saved(in: defaults), .notInstalled)
        CartoucheHomeFilter.installed.save(in: defaults)
        XCTAssertEqual(CartoucheHomeFilter.saved(in: defaults), .installed)
        CartoucheHomeFilter.all.save(in: defaults)
        XCTAssertNil(defaults.object(forKey: CartoucheHomeFilter.defaultsKey))
        defaults.set("someday", forKey: CartoucheHomeFilter.defaultsKey)
        XCTAssertEqual(CartoucheHomeFilter.saved(in: defaults), .all)
    }

    func testTheShoulderButtonsGoRoundTheFilters() {
        XCTAssertEqual(CartoucheHomeFilter.all.moved(forward: true), .installed)
        XCTAssertEqual(CartoucheHomeFilter.installed.moved(forward: true), .notInstalled)
        XCTAssertEqual(CartoucheHomeFilter.notInstalled.moved(forward: true), .all)
        XCTAssertEqual(CartoucheHomeFilter.all.moved(forward: false), .notInstalled)
        XCTAssertEqual(CartoucheHomeFilter.notInstalled.moved(forward: false), .installed)
    }

    // MARK: Its event

    func testItsEventSaysTheFilterAndHow() {
        let context = CartoucheTelemetryContext(install: "8c1f6c2e-7a2f-4e19-8c3d-2f6a9b0e1d7c", cartouche: "0.16.2",
                                                device: "iPhone19,4", ios: "27.2", language: "en")
        XCTAssertEqual(CartoucheHomeFilter.notInstalled.fields(byController: false),
                       ["filter": .text("notInstalled"), "controller": .flag(false)])
        for filter in CartoucheHomeFilter.allCases {
            for byController in [true, false] {
                let fields = filter.fields(byController: byController)
                for (key, value) in fields {
                    XCTAssertNotNil(key.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression), key)
                    if case .text(let text) = value {
                        XCTAssertNotNil(text.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression), text)
                    }
                }
                let made = CartoucheEventReport(id: "3d9b2f5e-0000-4000-8000-000000000002", seq: 1, context: context,
                                                name: CartoucheHomeFilter.event, fields: fields)
                XCTAssertEqual(made?.fields, fields, "\(filter)")
            }
        }
    }

    /// telemetry/README.md tells the event and each name it sends.
    func testTheTelemetrysReadmeTellsTheEvent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../telemetry/README.md").standardizedFileURL
        let readme = try String(contentsOf: url, encoding: .utf8)
        let row = try XCTUnwrap(readme.components(separatedBy: "\n").first { $0.hasPrefix("| `\(CartoucheHomeFilter.event)` |") },
                                "no row for \(CartoucheHomeFilter.event)")
        for name in CartoucheHomeFilter.allCases.map(\.rawValue) + ["filter", "controller"] {
            XCTAssertTrue(row.contains("`\(name)`"), "home.filtered's row should tell \(name)")
        }
    }
}
