//
//  CartoucheControllerLossTests.swift
//  CartoucheCoreTests
//
//  When a game playing with a controller pauses for losing it, and when it
//  comes back (Sources/CartoucheControllerLoss.swift, decision 166): 3
//  seconds without any controller pause a game on screen that had one; a
//  controller that connects again brings back a game paused for it; a game
//  played on the screen alone never pauses for one.
//
//  Without the rule, nothing pauses a game whose controller goes: it plays
//  on under the controls on the screen.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheControllerLossTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// A game started with one controller, on screen.
    private func playing() -> CartoucheControllerLoss {
        var loss = CartoucheControllerLoss()
        loss.started(controllers: 1)
        return loss
    }

    func testTheLastControllerGoingPausesTheGameThreeSecondsLater() {
        var loss = playing()
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(10)), .wait)
        XCTAssertEqual(loss.lostSince, at(10))
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(11)), .wait, "not before 3 seconds")
        XCTAssertFalse(loss.isPausedForController)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(13)), .pause)
        XCTAssertTrue(loss.isPausedForController)
        XCTAssertNil(loss.lostSince)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(16)), .nothing, "paused once")
    }

    func testAControllerBackWithinThreeSecondsKeepsTheGameGoing() {
        var loss = playing()
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(10)), .wait)
        XCTAssertEqual(loss.controllersChanged(1, inFront: true, now: at(11.5)), .nothing)
        XCTAssertEqual(loss.check(1, inFront: true, isOn: true, now: at(13)), .nothing)
        XCTAssertFalse(loss.isPausedForController)
        // It goes again: three seconds counted from then.
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(20)), .wait)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(22)), .wait)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(23)), .pause)
    }

    func testOneControllerOfTwoGoingPausesNothing() {
        var loss = CartoucheControllerLoss()
        loss.started(controllers: 2)
        XCTAssertEqual(loss.controllersChanged(1, inFront: true, now: at(10)), .nothing)
        XCTAssertEqual(loss.check(1, inFront: true, isOn: true, now: at(13)), .nothing)
        XCTAssertFalse(loss.isPausedForController)
    }

    func testAGamePlayedOnTheScreenAloneNeverPauses() {
        var loss = CartoucheControllerLoss()
        loss.started(controllers: 0)
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(10)), .nothing)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(20)), .nothing)
        XCTAssertFalse(loss.isPausedForController)
    }

    func testAControllerConnectedDuringTheGameCountsFromThen() {
        var loss = CartoucheControllerLoss()
        loss.started(controllers: 0)
        XCTAssertEqual(loss.controllersChanged(1, inFront: true, now: at(30)), .nothing)
        XCTAssertTrue(loss.hadController)
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(60)), .wait)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(63)), .pause)
    }

    func testAControllerBackBringsTheGamePausedForItBack() throws {
        var loss = playing()
        _ = loss.controllersChanged(0, inFront: true, now: at(10))
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(13)), .pause)
        loss.wentBehind()
        XCTAssertEqual(loss.controllersChanged(1, inFront: false, now: at(40)), .resume)
        let pause = try XCTUnwrap(loss.cameToFront(controllers: 1, now: at(41)))
        XCTAssertEqual(pause, CartoucheControllerLoss.Pause(ending: .controller, seconds: 28))
        XCTAssertFalse(loss.isPausedForController)
        XCTAssertTrue(loss.hadController)
        // And it pauses again should the controller go again.
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(50)), .wait)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(53)), .pause)
    }

    func testResumeWithoutAControllerPlaysOnTheScreenFromThen() throws {
        var loss = playing()
        _ = loss.controllersChanged(0, inFront: true, now: at(10))
        _ = loss.check(0, inFront: true, isOn: true, now: at(13))
        loss.wentBehind()
        let pause = try XCTUnwrap(loss.cameToFront(controllers: 0, now: at(20)))
        XCTAssertEqual(pause, CartoucheControllerLoss.Pause(ending: .resume, seconds: 7))
        XCTAssertFalse(loss.hadController)
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(21)), .nothing)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(30)), .nothing, "no pause on the screen's controls")
    }

    func testAGamePausedFromTheHomeButtonDoesNotComeBackForAController() {
        var loss = playing()
        // The player opens the console while the controller has just gone.
        _ = loss.controllersChanged(0, inFront: true, now: at(10))
        loss.wentBehind()
        XCTAssertNil(loss.lostSince)
        XCTAssertEqual(loss.check(0, inFront: false, isOn: true, now: at(13)), .nothing)
        XCTAssertFalse(loss.isPausedForController)
        XCTAssertEqual(loss.controllersChanged(1, inFront: false, now: at(20)), .nothing, "the player paused it: it stays")
        XCTAssertNil(loss.cameToFront(controllers: 1, now: at(30)), "no pause for the controller ended")
    }

    func testAGameBroughtBackWithoutTheControllerItLostMeanwhileDoesNotPause() {
        var loss = playing()
        loss.wentBehind()
        // The controller goes while the console shows.
        XCTAssertEqual(loss.controllersChanged(0, inFront: false, now: at(10)), .nothing)
        XCTAssertNil(loss.cameToFront(controllers: 0, now: at(20)))
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(21)), .nothing)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: true, now: at(25)), .nothing)
    }

    func testTheSwitchOffPausesNothing() {
        var loss = playing()
        XCTAssertEqual(loss.controllersChanged(0, inFront: true, now: at(10)), .wait)
        XCTAssertEqual(loss.check(0, inFront: true, isOn: false, now: at(13)), .nothing)
        XCTAssertFalse(loss.isPausedForController)
        XCTAssertNil(loss.lostSince)
    }

    func testTheSwitchIsOnUnlessThePlayerTurnedItOff() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CartoucheControllerLossTests-\(UUID().uuidString)"))
        XCTAssertTrue(CartoucheControllerLoss.isOn(in: defaults))
        defaults.set(false, forKey: CartoucheControllerLoss.settingKey)
        XCTAssertFalse(CartoucheControllerLoss.isOn(in: defaults))
        defaults.set(true, forKey: CartoucheControllerLoss.settingKey)
        XCTAssertTrue(CartoucheControllerLoss.isOn(in: defaults))
    }

    func testAGameEndedWhilePausedForItsControllerSaysHow() throws {
        var quitting = playing()
        _ = quitting.controllersChanged(0, inFront: true, now: at(10))
        _ = quitting.check(0, inFront: true, isOn: true, now: at(13))
        quitting.wentBehind()
        XCTAssertEqual(try XCTUnwrap(quitting.ended(quit: true, now: at(73))),
                       CartoucheControllerLoss.Pause(ending: .quit, seconds: 60))
        XCTAssertFalse(quitting.isPausedForController)
        XCTAssertFalse(quitting.hadController)

        var stopped = playing()
        _ = stopped.controllersChanged(0, inFront: true, now: at(10))
        _ = stopped.check(0, inFront: true, isOn: true, now: at(13))
        XCTAssertEqual(stopped.ended(quit: false, now: at(20))?.ending, .ended)

        var never = playing()
        XCTAssertNil(never.ended(quit: true, now: at(20)), "no pause for the controller, nothing to say")
    }

    func testTheMeasurementSaysHowItEndedAndHowLongItLasted() {
        let fields = CartoucheControllerLoss.fields(of: CartoucheControllerLoss.Pause(ending: .controller, seconds: 27.6))
        XCTAssertEqual(fields, ["ended": .text("controller"), "seconds": .number(28)])
    }
}
