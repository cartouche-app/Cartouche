//
//  ControllerPauseTests.swift
//  CartoucheHarnessTests
//
//  A game behind the console that loses its last controller while the
//  player plays (docs/decisions/166.md): 3 seconds later, the console shows
//  over it, the game paused, and says that the controller disconnected; a
//  controller that connects again brings the game back, as Resume does. A
//  game played on the screen alone never pauses for one, nor one the
//  player brought back with Resume and no controller, and System › While a
//  game runs turns it off. The game's process says whether it has
//  controllers, as CartoucheGuest.m posts it, and its word wins over
//  Cartouche's own. The Simulator has no controller: the tests connect and
//  disconnect them as CartoucheGamepad counts them.
//
//  Without the rule, nothing pauses a game whose controller goes: it plays
//  on under the controls on the screen.
//

import UIKit
import XCTest
@testable import CartoucheHarness

@available(iOS 18.0, *)
final class ControllerPauseTests: HarnessCase {
    /// The line that opens each test's steps in the journal of the reports.
    private static let journalMark = "Harness: a controller pause test starts"

    private var gamepad: CartoucheGamepad { CartoucheGamepad.shared }

    override func setUp() async throws {
        try await super.setUp()
        CartoucheReports.note(Self.journalMark)
        // The measurements on, nothing waiting, and no wait the server
        // asked for (TelemetryTests).
        CartoucheTelemetry.shared.setOn(false)
        CartoucheTelemetry.shared.setOn(true)
        HarnessNetwork.answer { request in
            request.url.host == "telemetry.harness.invalid" ? HarnessNetwork.Answer(status: 200, headers: [:]) : nil
        }
    }

    // MARK: The pause

    func testAGameThatLosesItsLastControllerPausesBehindTheConsoleThreeSecondsLater() async throws {
        gamepad.harnessControllers = 1
        let (app, scene) = try await started(.plain())
        try await pause(0.7)
        gamepad.harnessControllers = 0
        let gone = Date()
        try await waitUntil("the console shows", timeout: 8) { actions.running?.isInFront == false }
        XCTAssertGreaterThan(Date().timeIntervalSince(gone), 2.5, "3 seconds after the controller went")
        XCTAssertEqual(actions.running?.pausedForController, true, "the console says why")
        XCTAssertEqual(scene.presenter?.scene?.settings.foreground, false, "the game's scene goes to the background")
        XCTAssertTrue(scene.isAppRunning, "paused, not ended")
        XCTAssertTrue(journal().contains(app.displayName + ": no controller for 3 seconds, the game paused behind the console"))
        try await pause(4)
        XCTAssertEqual(actions.running?.isInFront, false, "it stays paused without a controller")
    }

    func testAControllerConnectedAgainBringsTheGameBack() async throws {
        gamepad.harnessControllers = 1
        let (app, scene) = try await started(.plain())
        try await pause(0.7)
        gamepad.harnessControllers = 0
        try await waitUntil("the console shows", timeout: 8) { actions.running?.isInFront == false }
        try await pause(0.7)
        gamepad.harnessControllers = 1
        try await waitUntil("the game shows again") { actions.running?.isInFront == true }
        XCTAssertEqual(actions.running?.pausedForController, false)
        XCTAssertEqual(scene.presenter?.scene?.settings.foreground, true)
        XCTAssertEqual(HarnessScenes.all.count, 1, "the same game, not another start")
        XCTAssertTrue(journal().contains(app.displayName + ": a controller connected, the game comes back"))
        // The measurements: a pause for the controller, which a controller
        // ended, and how long it lasted.
        try await waitUntil("the pause is reported") { self.report(named: "game.controllerPause") != nil }
        let fields = try XCTUnwrap(report(named: "game.controllerPause")?["fields"] as? [String: Any])
        XCTAssertEqual(fields["ended"] as? String, "controller")
        XCTAssertNotNil(fields["seconds"] as? Double)

        // It pauses again should the controller go again.
        gamepad.harnessControllers = 0
        try await waitUntil("the console shows again", timeout: 8) { actions.running?.isInFront == false }
        XCTAssertEqual(actions.running?.pausedForController, true)
    }

    func testAControllerBackWithinThreeSecondsKeepsTheGameOn() async throws {
        gamepad.harnessControllers = 1
        _ = try await started(.plain())
        try await pause(0.7)
        gamepad.harnessControllers = 0
        try await pause(1)
        gamepad.harnessControllers = 1
        try await pause(3.5)
        XCTAssertEqual(actions.running?.isInFront, true)
        XCTAssertEqual(actions.running?.pausedForController, false)
    }

    // MARK: No pause

    func testAGamePlayedOnTheScreenAloneNeverPauses() async throws {
        let (_, scene) = try await started(.plain())
        scene.sayControllers(false)
        try await pause(4)
        XCTAssertEqual(actions.running?.isInFront, true)
        XCTAssertEqual(actions.running?.pausedForController, false)
    }

    func testWithTheSwitchOffTheGamePlaysOn() async throws {
        UserDefaults.standard.set(false, forKey: CartoucheControllerLoss.settingKey)
        gamepad.harnessControllers = 1
        _ = try await started(.plain())
        try await pause(0.7)
        gamepad.harnessControllers = 0
        try await pause(4)
        XCTAssertEqual(actions.running?.isInFront, true)
    }

    func testResumeWithoutAControllerPlaysOnTheScreenFromThen() async throws {
        gamepad.harnessControllers = 1
        _ = try await started(.plain())
        try await pause(0.7)
        gamepad.harnessControllers = 0
        try await waitUntil("the console shows", timeout: 8) { actions.running?.isInFront == false }
        try await pause(0.7)
        actions.resumeRunningGame()
        try await waitUntil("the game shows again") { actions.running?.isInFront == true }
        XCTAssertEqual(actions.running?.pausedForController, false)
        try await pause(4)
        XCTAssertEqual(actions.running?.isInFront, true, "the player plays on the screen")
        try await waitUntil("the pause is reported") { self.report(named: "game.controllerPause") != nil }
        let fields = try XCTUnwrap(report(named: "game.controllerPause")?["fields"] as? [String: Any])
        XCTAssertEqual(fields["ended"] as? String, "resume")
    }

    func testAGamePausedFromTheHomeButtonStaysPausedAsAControllerConnects() async throws {
        gamepad.harnessControllers = 1
        let (_, scene) = try await started(.plain())
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the console shows") { actions.running?.isInFront == false }
        XCTAssertEqual(actions.running?.pausedForController, false, "the player paused it")
        gamepad.harnessControllers = 0
        try await pause(0.5)
        gamepad.harnessControllers = 1
        try await pause(1)
        XCTAssertEqual(actions.running?.isInFront, false, "it stays paused")
    }

    // MARK: The game's process

    func testTheGamesProcessSaysItsControllersGo() async throws {
        // Cartouche hears of no controller: the game's process has one.
        let (_, scene) = try await started(.plain())
        scene.sayControllers(true)
        try await pause(0.7)
        XCTAssertEqual(actions.running?.isInFront, true)
        scene.sayControllers(false)
        try await waitUntil("the console shows", timeout: 8) { actions.running?.isInFront == false }
        XCTAssertEqual(actions.running?.pausedForController, true)
    }

    func testWhileTheGamesProcessHasAControllerTheGameGoesOn() async throws {
        gamepad.harnessControllers = 1
        let (_, scene) = try await started(.plain())
        scene.sayControllers(true)
        try await pause(0.7)
        // Cartouche no longer hears of it: the game's process still has it.
        gamepad.harnessControllers = 0
        try await pause(4)
        XCTAssertEqual(actions.running?.isInFront, true)
    }

    // MARK: Helpers

    /// The steps Cartouche noted for its reports since this test started,
    /// without their time.
    private func journal() -> [String] {
        let lines = CartoucheReports.journal(last: CartoucheJournal.kept)
        guard let start = lines.lastIndex(where: { $0.hasSuffix(" " + Self.journalMark) }) else { return [] }
        // "11-26 18:02:07 Plain: a controller connected, the game comes back"
        return lines[lines.index(after: start)...].map { line in
            line.split(separator: " ", maxSplits: 2).dropFirst(2).first.map(String.init) ?? ""
        }
    }

    /// The last report named NAME the telemetry's server got, as JSON.
    private func report(named name: String) -> [String: Any]? {
        HarnessNetwork.requests.filter { $0.url.path == "/v1/reports" }
            .flatMap { request -> [[String: Any]] in
                let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
                return body?["reports"] as? [[String: Any]] ?? []
            }
            .last { $0["name"] as? String == name }
    }
}
