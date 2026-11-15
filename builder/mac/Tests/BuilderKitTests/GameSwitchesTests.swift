//
//  GameSwitchesTests.swift
//  BuilderKitTests
//
//  The switches of a game's sheet, shown as soon as the player flips them,
//  over library reads that take tens of seconds on a NAS (GameSwitches).
//

import Foundation
import XCTest
@testable import BuilderKit

final class GameSwitchesTests: XCTestCase {
    private let mk8 = "0100152000022000"
    private let zelda = "01008CF01BAAC000"

    /// The library as the engine reads it: MK8 built for both, followed;
    /// Zelda for the iPhone alone, not followed.
    private func read(mk8 platforms: GamePlatforms = GamePlatforms(ios: true, mac: true), followed: Bool = true) -> Library {
        Library(games: [
            Game(titleID: mk8, name: "Mario Kart 8 Deluxe", kind: "dump", followed: followed, state: .upToDate, platforms: platforms),
            Game(titleID: zelda, name: "Zelda", kind: "dump", followed: false, state: .upToDate, platforms: GamePlatforms(ios: true, mac: false)),
        ])
    }

    func testAFlipShowsAtOnceAndUntilAReadThatBeganAfterTheAnswer() throws {
        var switches = GameSwitches()
        let before = read()
        // Ad's case: the switch for this Mac turned off showed off only once
        // the library was read again, 30 to 45 s later on a NAS.
        let flip = switches.flip(mk8, platforms: GamePlatforms(ios: true, mac: false))
        let shown = switches.applied(to: before)
        XCTAssertEqual(shown.game(mk8)?.onMac, false)
        XCTAssertEqual(shown.game(mk8)?.onIOS, true)
        XCTAssertEqual(shown.game(zelda), before.game(zelda))
        // A read that began before the engine answered says the game as it
        // was: the switch still shows.
        let early = switches.mark
        switches.answered(mk8, flip: flip, platforms: GamePlatforms(ios: true, mac: false), followed: true)
        let stale = switches.read(read(), since: early)
        XCTAssertEqual(stale.game(mk8)?.onMac, false)
        XCTAssertFalse(switches.isEmpty)
        // One that began after the answer says it: the switch is forgotten,
        // and what the read says shows, whatever it says.
        let late = switches.mark
        let fresh = switches.read(read(mk8: GamePlatforms(ios: true, mac: false)), since: late)
        XCTAssertEqual(fresh.game(mk8)?.onMac, false)
        XCTAssertTrue(switches.isEmpty)
        XCTAssertEqual(switches.read(read(), since: switches.mark).game(mk8)?.onMac, true)
    }

    func testAnEarlierFlipsAnswerDoesNotUndoALaterFlip() throws {
        var switches = GameSwitches()
        let off = switches.flip(mk8, platforms: GamePlatforms(ios: true, mac: false))
        let on = switches.flip(mk8, platforms: GamePlatforms(ios: true, mac: true))
        // The first answer comes after the second flip: the second shows.
        switches.answered(mk8, flip: off, platforms: GamePlatforms(ios: true, mac: false), followed: true)
        XCTAssertEqual(switches.applied(to: read()).game(mk8)?.onMac, true)
        // Nor does a read the first answer was in forget the second.
        XCTAssertEqual(switches.read(read(mk8: GamePlatforms(ios: true, mac: false)), since: switches.mark).game(mk8)?.onMac, true)
        XCTAssertFalse(switches.isEmpty)
        switches.answered(mk8, flip: on, platforms: GamePlatforms(ios: true, mac: true), followed: true)
        XCTAssertEqual(switches.applied(to: read(mk8: GamePlatforms(ios: true, mac: false))).game(mk8)?.onMac, true)
        _ = switches.read(read(), since: switches.mark)
        XCTAssertTrue(switches.isEmpty)
    }

    func testARefusedFlipShowsWhatTheEngineSaidLast() throws {
        var switches = GameSwitches()
        // Refused at once: the library as read shows again.
        let refused = switches.flip(mk8, platforms: GamePlatforms(ios: false, mac: true))
        XCTAssertEqual(switches.applied(to: read()).game(mk8)?.onIOS, false)
        switches.refused(mk8, flip: refused)
        XCTAssertTrue(switches.isEmpty)
        XCTAssertEqual(switches.applied(to: read()).game(mk8)?.onIOS, true)
        // Answered, then another flip refused before a read: the answer shows,
        // until a read that began after it.
        let off = switches.flip(mk8, platforms: GamePlatforms(ios: true, mac: false))
        switches.answered(mk8, flip: off, platforms: GamePlatforms(ios: true, mac: false), followed: true)
        let again = switches.flip(mk8, platforms: GamePlatforms(ios: false, mac: false))
        switches.refused(mk8, flip: again)
        let shown = switches.applied(to: read())
        XCTAssertEqual(shown.game(mk8)?.onMac, false)
        XCTAssertEqual(shown.game(mk8)?.onIOS, true)
        _ = switches.read(read(mk8: GamePlatforms(ios: true, mac: false)), since: switches.mark)
        XCTAssertTrue(switches.isEmpty)
        // A refusal of an earlier flip, answered meanwhile by a later one, changes nothing.
        let first = switches.flip(mk8, followed: false)
        let second = switches.flip(mk8, followed: true)
        switches.refused(mk8, flip: first)
        XCTAssertEqual(switches.applied(to: read(followed: false)).game(mk8)?.followed, true)
        switches.answered(mk8, flip: second, followed: true)
        XCTAssertEqual(switches.applied(to: read(followed: false)).game(mk8)?.followed, true)
    }

    func testFollowingAndPlatformsOfOneGameAddUp() throws {
        var switches = GameSwitches()
        // Turning this Mac on follows Zelda, as the engine does.
        let mac = switches.flip(zelda, platforms: GamePlatforms(ios: true, mac: true), followed: true)
        var shown = switches.applied(to: read())
        XCTAssertEqual(shown.game(zelda)?.onMac, true)
        XCTAssertEqual(shown.game(zelda)?.followed, true)
        switches.answered(zelda, flip: mac, platforms: GamePlatforms(ios: true, mac: true), followed: true)
        // Then no longer followed: the platforms stay as switched.
        let follow = switches.flip(zelda, followed: false)
        shown = switches.applied(to: read())
        XCTAssertEqual(shown.game(zelda)?.onMac, true)
        XCTAssertEqual(shown.game(zelda)?.followed, false)
        switches.answered(zelda, flip: follow, followed: false)
        XCTAssertEqual(switches.applied(to: read()).game(zelda)?.followed, false)
        // Title IDs in any letter case are the same game.
        let lower = switches.flip(zelda.lowercased(), followed: true)
        XCTAssertEqual(switches.applied(to: read()).game(zelda)?.followed, true)
        XCTAssertEqual(switches.applied(to: read()).game(zelda)?.onMac, true)
        switches.answered(zelda, flip: lower, followed: true)
        _ = switches.read(read(), since: switches.mark)
        XCTAssertTrue(switches.isEmpty)
    }
}
