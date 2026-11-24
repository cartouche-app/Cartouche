//
//  CartoucheNightlyRenewalTests.swift
//  CartoucheCoreTests
//
//  Where the automation of Shortcuts that renews Cartouche every night
//  stands, from the last run of Refresh All Apps that the built-in
//  SideStore's support noted and from when the player said they made it
//  (Sources/CartoucheRenewalRules.swift, CartoucheNightlyRenewal).
//

import XCTest
@testable import CartoucheCore

final class CartoucheNightlyRenewalTests: XCTestCase {
    private typealias Nightly = CartoucheNightlyRenewal
    private typealias Run = CartoucheNightlyRenewal.Run

    /// Nine in the morning; the night's run at four.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var night: Date { now.addingTimeInterval(-5 * 3_600) }
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private func state(_ run: Run?, made: Date? = nil, expiration: Date? = nil) -> Nightly.State {
        Nightly.state(run: run, made: made, expiration: expiration, at: now)
    }

    // MARK: Never made, or made by the player's word

    /// A new player: no run, and they have not said they made it.
    func testWithNoRunNorWordItIsToMake() {
        XCTAssertEqual(state(nil), .toMake)
        XCTAssertFalse(Nightly.State.toMake.isDone)
    }

    /// Made in the afternoon: done for the setup until its first night.
    func testMadeItWaitsForItsFirstNight() {
        let made = now.addingTimeInterval(-20 * hour)
        XCTAssertEqual(state(nil, made: made), .waiting(since: made))
        XCTAssertTrue(Nightly.State.waiting(since: made).isDone)
    }

    /// No run a night and a half after the player made it: its time, or Run
    /// Immediately, to check.
    func testMadeWithNoRunAfterANightAndAHalfDoesNotRun() {
        let made = now.addingTimeInterval(-37 * hour)
        XCTAssertEqual(state(nil, made: made), .notRunning(since: made))
        XCTAssertFalse(Nightly.State.notRunning(since: made).isDone)
    }

    /// Made again after a run that failed: its next night tells, whatever
    /// the run before said.
    func testMadeAgainAfterItsLastRunWaitsAgain() {
        let run = Run(started: night, tunnel: false, ended: night.addingTimeInterval(20), message: "No device found.")
        let made = now.addingTimeInterval(-hour)
        XCTAssertEqual(state(run, made: made), .waiting(since: made))
    }

    /// Made before its last run: the run tells.
    func testARunAfterThePlayersWordTells() {
        let run = Run(started: night, tunnel: true, ended: night.addingTimeInterval(40))
        XCTAssertEqual(state(run, made: night.addingTimeInterval(-10 * hour)), .renewed(at: night.addingTimeInterval(40)))
    }

    // MARK: Its last run

    /// The run went through, LocalDevVPN connected.
    func testARunThatEndedWithoutAnErrorRenewedCartouche() {
        let ended = night.addingTimeInterval(38)
        XCTAssertEqual(state(Run(started: night, tunnel: true, ended: ended)), .renewed(at: ended))
        XCTAssertTrue(Nightly.State.renewed(at: ended).isDone)
    }

    /// No Enable LocalDevVPN before Refresh All Apps: SideStore cannot reach
    /// the iPhone, whatever it said, even with a signature renewed since by
    /// Renew now.
    func testARunWithoutLocalDevVPNsTunnelFailedOnIt() {
        let run = Run(started: night, tunnel: false, ended: night.addingTimeInterval(19), message: "No device found.")
        XCTAssertEqual(state(run), .failed(at: night, .vpn))
        XCTAssertEqual(state(run, expiration: now.addingTimeInterval(7 * day)), .failed(at: night, .vpn))
        XCTAssertFalse(Nightly.State.failed(at: night, .vpn).isDone)
    }

    /// SideStore went through though no tunnel was read: it renewed
    /// Cartouche, which it could not do without one.
    func testARunThatEndedWithoutAnErrorRenewedWhateverTheTunnelRead() {
        let ended = night.addingTimeInterval(41)
        XCTAssertEqual(state(Run(started: night, tunnel: false, ended: ended)), .renewed(at: ended))
    }

    /// SideStore failed with its words, the signature being the one an
    /// update gave the day before: it expires less than seven days after
    /// the run.
    func testARunSideStoreFailedSaysItsWords() {
        let run = Run(started: night, tunnel: true, ended: night.addingTimeInterval(9), message: "Invalid parameters")
        let updatedTheDayBefore = night.addingTimeInterval(-17 * hour + 7 * day)
        XCTAssertEqual(state(run, expiration: updatedTheDayBefore), .failed(at: night, .sideStore("Invalid parameters")))
        XCTAssertEqual(state(run), .failed(at: night, .sideStore("Invalid parameters")))
    }

    /// SideStore quit on its way back, once Cartouche was renewed: the
    /// signature, seven days from the run, says it renewed.
    func testARunThatFailedOnItsWayBackRenewedAsTheSignatureSays() {
        let ended = night.addingTimeInterval(70)
        let run = Run(started: night, tunnel: true, ended: ended, message: "Built-in SideStore quit unexpectedly")
        XCTAssertEqual(state(run, expiration: night.addingTimeInterval(7 * day + 50)), .renewed(at: ended))
    }

    /// A run under way as the player opens Cartouche.
    func testARunUnderWayIsRunning() {
        let started = now.addingTimeInterval(-90)
        XCTAssertEqual(state(Run(started: started, tunnel: true)), .running(since: started))
        XCTAssertTrue(Nightly.State.running(since: started).isDone)
    }

    /// A run that never ended, ten minutes on: iOS ended Cartouche first.
    func testARunThatNeverEndedWasInterrupted() {
        XCTAssertEqual(state(Run(started: night, tunnel: true)), .failed(at: night, .interrupted))
        XCTAssertEqual(state(Run(started: night)), .failed(at: night, .interrupted))
    }

    /// Interrupted once Apple had made the profiles: renewed all the same.
    func testARunInterruptedOnceRenewedRenewed() {
        XCTAssertEqual(state(Run(started: night, tunnel: true), expiration: night.addingTimeInterval(7 * day)),
                       .renewed(at: night))
    }

    /// Its last run three nights ago and more: the automation no longer
    /// runs, whatever that run said.
    func testALastRunOlderThanThreeNightsStopped() {
        let started = now.addingTimeInterval(-3 * day - hour)
        let run = Run(started: started, tunnel: true, ended: started.addingTimeInterval(40))
        XCTAssertEqual(state(run), .stopped(since: started))
        XCTAssertFalse(Nightly.State.stopped(since: started).isDone)
        // Two nights without a run, the iPhone off: still renewing.
        let twoNights = now.addingTimeInterval(-2 * day - 5 * hour)
        XCTAssertEqual(state(Run(started: twoNights, tunnel: true, ended: twoNights.addingTimeInterval(40))),
                       .renewed(at: twoNights.addingTimeInterval(40)))
    }

    // MARK: The run as CartoucheShortcutRun writes it

    func testReadsTheRunCartoucheShortcutRunWrites() {
        let ended = night.addingTimeInterval(19)
        let record: [String: Any] = ["started": night, "tunnel": false, "ended": ended, "message": "No device found."]
        XCTAssertEqual(Run(record: record), Run(started: night, tunnel: false, ended: ended, message: "No device found."))
        XCTAssertEqual(Run(record: ["started": night]), Run(started: night))
    }

    func testReadsNothingElse() {
        XCTAssertNil(Run(record: nil))
        XCTAssertNil(Run(record: "4:00"))
        XCTAssertNil(Run(record: ["tunnel": true]))
        XCTAssertNil(Run(record: ["started": "2026-11-24T04:00:00Z"]))
    }

    // MARK: The measurements

    func testSendsShortNames() {
        XCTAssertEqual(Nightly.State.toMake.name, "toMake")
        XCTAssertEqual(Nightly.State.waiting(since: now).name, "waiting")
        XCTAssertEqual(Nightly.State.notRunning(since: now).name, "notRunning")
        XCTAssertEqual(Nightly.State.running(since: now).name, "running")
        XCTAssertEqual(Nightly.State.renewed(at: now).name, "renewed")
        XCTAssertEqual(Nightly.State.failed(at: now, .vpn).name, "failed")
        XCTAssertEqual(Nightly.State.stopped(since: now).name, "stopped")
        XCTAssertEqual(Nightly.Problem.vpn.name, "vpn")
        XCTAssertEqual(Nightly.Problem.interrupted.name, "interrupted")
        XCTAssertEqual(Nightly.Problem.sideStore("Invalid parameters").name, "sideStore")
    }

    /// What its last run failed on, alone: never SideStore's words.
    func testSendsWhatItFailedOn() {
        XCTAssertEqual(Nightly.State.failed(at: now, .vpn).problem?.name, "vpn")
        XCTAssertEqual(Nightly.State.failed(at: now, .sideStore("Invalid parameters")).problem?.name, "sideStore")
        XCTAssertNil(Nightly.State.renewed(at: now).problem)
        XCTAssertNil(Nightly.State.stopped(since: now).problem)
    }
}
