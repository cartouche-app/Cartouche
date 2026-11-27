//
//  HomeFilterUITests.swift
//  CartoucheGalleryUITests
//
//  The home's filter (launcher/Sources/CartoucheHomeFilter.swift): with the
//  player's games installed and a game Cartouche Cloud built for them, not
//  installed, the menu beside the shelf's title shows every game, those
//  installed or those not installed; a player whose games are all
//  installed has no filter.
//

import XCTest

extension Words {
    static let filter = "Filter"                            // hint.filter
    static let filterAll = "All"                            // library.filter.all
    static let installed = "Installed"                      // home.filter.installed
    static let notInstalled = "Not installed"               // home.filter.notInstalled
}

final class HomeFilterUITests: ConsoleTestCase {
    /// The game Cartouche Cloud built for the player, not installed
    /// (GalleryCloud): the first of the shelf by name.
    private let builtGame = "13 Sentinels: Aegis Rim"

    /// The filter leaves out the games not installed, then those
    /// installed, and shows them all again.
    @MainActor
    func testTheFilterShowsTheGamesInstalledOrNot() {
        let app = openConsole(Launch(work: "cloud-games"))
        let filter = app.buttons[Words.filter]
        expect(filter.waitForExistence(timeout: 15), "No filter beside the shelf's title", in: app)
        expect((filter.value as? String) == Words.filterAll, "The filter is \(filter.value as? String ?? "nothing"), not All",
               in: app)
        expectShelf(shows: [builtGame, Games.inFocus], hides: [], in: app)

        choose(Words.installed, with: filter, in: app)
        expectShelf(shows: [Games.inFocus], hides: [builtGame], in: app)
        expect(app.buttons[Games.inFocus].isSelected, "\(Games.inFocus), first of the games installed, is not in focus",
               in: app)

        choose(Words.notInstalled, with: filter, in: app)
        expectShelf(shows: [builtGame], hides: Games.names, in: app)
        expect(app.buttons[builtGame].isSelected, "\(builtGame), alone on the shelf, is not in focus", in: app)

        choose(Words.filterAll, with: filter, in: app)
        expectShelf(shows: [builtGame, Games.inFocus], hides: [], in: app)
        expectMainThreadAnswered(app)
    }

    /// Every game installed: nothing to sort, no filter.
    @MainActor
    func testNoFilterWhenEveryGameIsInstalled() {
        let app = openConsole()
        expect(app.buttons[Games.inFocus].waitForExistence(timeout: 15), "No cover of \(Games.inFocus) on the shelf", in: app)
        expect(!app.buttons[Words.filter].exists, "The home offers a filter with every game installed", in: app)
        expectMainThreadAnswered(app)
    }

    /// Opens the filter's menu and picks FILTER in it.
    @MainActor
    private func choose(_ filter: String, with menu: XCUIElement, in app: XCUIApplication) {
        tap(menu, "the filter beside the shelf's title", in: app)
        tap(app.buttons[filter], "\(filter) in the filter's menu", in: app)
        expect(waitUntil(10) { (menu.value as? String) == filter },
               "The filter is \(menu.value as? String ?? "nothing") once \(filter) was picked", in: app)
    }

    /// The covers of SHOWS on the shelf, the first ones, which a shelf that
    /// scrolls has on screen, and none of HIDES.
    @MainActor
    private func expectShelf(shows: [String], hides: [String], in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        for name in shows {
            expect(app.buttons[name].waitForExistence(timeout: 10), "No cover of \(name) on the shelf", in: app,
                   file: file, line: line)
        }
        for name in hides {
            expect(waitUntil(10) { !app.buttons[name].exists }, "The cover of \(name) is still on the shelf", in: app,
                   file: file, line: line)
        }
    }
}
