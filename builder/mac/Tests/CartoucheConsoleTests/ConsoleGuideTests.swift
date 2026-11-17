//
//  ConsoleGuideTests.swift
//  CartoucheConsoleTests
//
//  The guide to a first game on this Mac (ConsoleGuide.swift): its three
//  steps, ticked from what the app sees in any order; its card on the
//  console's home until the first game is played, unless the player takes
//  it off, both kept from one start to the next; and the System page that
//  opens it, the iPhone's (CartoucheSystemView.swift).
//

import Foundation
import XCTest
@testable import CartoucheConsole

@MainActor
final class ConsoleGuideTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "console-guide-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheStepsTickFromWhatTheAppSees() {
        typealias Progress = CartoucheGuide.Progress
        let new = Progress()
        XCTAssertEqual(new.steps, [.setup, .build, .play])
        XCTAssertEqual(new.current, .setup)
        XCTAssertEqual(new.number(of: .play), 3)
        XCTAssertFalse(new.isFinished)

        XCTAssertEqual(Progress(isSetUp: true).current, .build)
        XCTAssertEqual(Progress(isSetUp: true, hasGame: true).current, .play)
        XCTAssertTrue(Progress(isSetUp: true, hasGame: true, hasPlayed: true).isFinished)
        // In any order: a game built here says this Mac was ready, even
        // with the assistant left before its end; one played, that a game
        // was built.
        let built = Progress(hasGame: true)
        XCTAssertTrue(built.isDone(.setup))
        XCTAssertEqual(built.current, .play)
        XCTAssertTrue(Progress(hasPlayed: true).isFinished)
    }

    func testTheCardStaysOnTheHomeUntilTheFirstGameIsPlayed() {
        let guide = CartoucheGuide(defaults: defaults)
        XCTAssertFalse(guide.hasPlayed)
        XCTAssertTrue(guide.showsCard(CartoucheGuide.Progress()))
        XCTAssertTrue(guide.showsCard(CartoucheGuide.Progress(isSetUp: true, hasGame: true)))
        XCTAssertFalse(guide.showsCard(CartoucheGuide.Progress(isSetUp: true, hasGame: true, hasPlayed: true)))

        // The console's Play: the last step, kept from one start to the next.
        guide.notePlayed()
        XCTAssertTrue(guide.hasPlayed)
        XCTAssertTrue(CartoucheGuide(defaults: defaults).hasPlayed)
        XCTAssertTrue(guide.progress().isDone(.play))
    }

    func testTheCardsCrossTakesItOffForGood() {
        let guide = CartoucheGuide(defaults: defaults)
        guide.hideCard()
        XCTAssertFalse(guide.showsCard(CartoucheGuide.Progress()))
        let again = CartoucheGuide(defaults: defaults)
        XCTAssertTrue(again.isCardHidden)
        XCTAssertFalse(again.showsCard(CartoucheGuide.Progress(isSetUp: true)))
        XCTAssertFalse(again.hasPlayed)
    }

    func testTheGuideReadsTheBuildersSetup() {
        let console = CartoucheMacConsole.shared
        let kept = console.isSetUp
        defer { console.isSetUp = kept }
        let guide = CartoucheGuide(defaults: defaults)
        guide.showForGallery(played: false)
        console.isSetUp = false
        // Unless another test left games in the console: one built here
        // says this Mac was ready.
        if console.apps.isEmpty {
            XCTAssertEqual(guide.progress().current, .setup)
        }
        console.isSetUp = true
        XCTAssertTrue(guide.progress().isDone(.setup))
        // The gallery's guide: a player who has played none of its games,
        // whatever play time its sheets show.
        XCTAssertFalse(guide.progress().hasPlayed)
        XCTAssertTrue(guide.showsCard(guide.progress()))
        guide.showForGallery(played: true)
        XCTAssertTrue(guide.progress().isFinished)
        XCTAssertFalse(guide.showsCard(guide.progress()))
    }

    func testTheStepsSayWhatToDoInTheirWords() {
        for step in CartoucheGuide.Step.allCases {
            XCTAssertFalse(CartoucheGuideView.title(step).isEmpty)
            XCTAssertFalse(CartoucheGuideView.detail(step).isEmpty)
            XCTAssertFalse(CartoucheGuideView.action(step).isEmpty)
            // The Mac's own words: never the iPhone's.
            XCTAssertFalse(CartoucheGuideView.detail(step).contains("iPhone"), CartoucheGuideView.detail(step))
        }
        XCTAssertEqual(Set(CartoucheGuide.Step.allCases.map(CartoucheGuideView.title)).count, 3)
    }
}
