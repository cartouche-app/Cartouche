//
//  ControllerTests.swift
//  CartoucheHarnessTests
//
//  A game behind the console gets its controllers' presses only while its
//  process has the keyboard: iOS hands them to the process that has it, as
//  it hands it a hardware keyboard's keys, and nothing in a game that Play
//  starts, without nxnative's settings screen, asked for it, so that the
//  controller drove nothing (issue #230, docs/decisions/123.md). The
//  game's process asks for it, without showing one, while the game's scene
//  is active (launcher/LiveProcessSupport/CartoucheGuestControllers.m).
//  The harness has no process of the game's: these tests run that part of
//  it in a window of their own, in the harness's scene, which stands in
//  for the game's, as the scene activates and resigns active. The game's
//  process also notes the last press that reached it, which the journal of
//  the reports says, once for each game, as the game pauses or ends.
//
//  Without the fix, the game's window has nothing that asks for the
//  keyboard, and the journal says nothing of the controller.
//

import UIKit
import XCTest
@testable import CartoucheHarness

@available(iOS 18.0, *)
final class ControllerTests: HarnessCase {
    /// The line that opens each test's steps in the journal of the reports.
    private static let journalMark = "Harness: a controller test starts"
    /// Whether the harness's process has used the keyboard yet.
    private static var keyboardLoaded = false

    /// The windows this test opened, which stand in for the game's.
    private var gameWindows: [UIWindow] = []
    /// The console's window, key before the test's.
    private weak var consoleWindow: UIWindow?

    override func setUp() async throws {
        // The keyboard's first use in a process loads what UIKit types
        // with, on the main thread: on the iPhone, in the game's process,
        // as its scene first activates, never in Cartouche's, whose main
        // thread the watchdog of HarnessCase looks after. Once, before it.
        if !Self.keyboardLoaded {
            Self.keyboardLoaded = true
            let (scene, _) = try openGameWindow()
            HarnessControllers.take(scene)
            HarnessControllers.leave(scene)
            closeGameWindows()
        }
        try await super.setUp()
        CartoucheReports.note(Self.journalMark)
    }

    override func tearDown() async throws {
        closeGameWindows()
        try await super.tearDown()
    }

    // MARK: The keyboard, and the controllers with it

    func testWhileItsSceneIsActiveTheGamesProcessAsksForTheKeyboardWithoutShowingOne() throws {
        let (scene, window) = try openGameWindow()
        XCTAssertFalse(HarnessControllers.holds(scene))
        HarnessControllers.take(scene)
        XCTAssertTrue(HarnessControllers.holds(scene))
        let view = try controllersView(in: window)
        XCTAssertTrue(view.isFirstResponder, "it has the keyboard of the game's window")
        // What iOS gives the keyboard to, and the controllers with it: a
        // responder that takes text, as a text field being typed in is.
        XCTAssertTrue(view.conforms(to: UIKeyInput.self))
        // No keyboard shows: an empty view of no height in its place, and
        // nothing over it.
        let noKeyboard = try XCTUnwrap(view.inputView, "a view in the keyboard's place")
        XCTAssertEqual(noKeyboard.bounds.height, 0)
        XCTAssertTrue(noKeyboard.subviews.isEmpty)
        XCTAssertNil(view.inputAccessoryView)
        // No bar of shortcuts over a hardware keyboard on an iPad.
        XCTAssertTrue(view.inputAssistantItem.leadingBarButtonGroups.isEmpty)
        XCTAssertTrue(view.inputAssistantItem.trailingBarButtonGroups.isEmpty)
        // Nothing on the game's screen, no touch taken from the game,
        // nothing for VoiceOver.
        XCTAssertEqual(view.alpha, 0)
        XCTAssertFalse(window.hitTest(view.center, with: nil) === view, "a touch on its place goes to the game")
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityElementsHidden)
        // What a hardware keyboard types goes nowhere.
        let input = try XCTUnwrap(view as? UIKeyInput)
        input.insertText("a")
        input.deleteBackward()
        XCTAssertFalse(input.hasText)
    }

    func testItLetsTheKeyboardGoAsTheSceneResignsActiveAndAsksAgainAsItComesBack() throws {
        let (scene, window) = try openGameWindow()
        HarnessControllers.take(scene)
        let view = try controllersView(in: window)

        // Paused behind the console: the keyboard, and the controllers with
        // it, go back to Cartouche, whose console then has them.
        HarnessControllers.leave(scene)
        XCTAssertFalse(HarnessControllers.holds(scene))
        XCTAssertFalse(view.isFirstResponder)

        // Back on screen: the same view asks again, once.
        HarnessControllers.take(scene)
        HarnessControllers.take(scene)
        XCTAssertTrue(HarnessControllers.holds(scene))
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertTrue(try controllersView(in: window) === view)
        XCTAssertEqual(window.subviews.filter { $0.accessibilityIdentifier == Self.controllersIdentifier }.count, 1)
    }

    func testATextFieldOfTheGamesKeepsTheKeyboardUntilItLetsItGo() throws {
        let (scene, window) = try openGameWindow()
        HarnessControllers.take(scene)
        // A text field of the game's, as nxnative shows one in an alert for
        // a game's software keyboard (front_ios.m): it takes the keyboard
        // as the player types in it. In the harness, nothing shows in the
        // keyboard's place.
        let field = UITextField(frame: CGRect(x: 20, y: 80, width: 200, height: 40))
        field.inputView = UIView()
        try XCTUnwrap(window.rootViewController?.view).addSubview(field)
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertFalse(HarnessControllers.holds(scene))

        // Asked again, every two seconds while the scene is active: the
        // text field keeps the keyboard.
        HarnessControllers.take(scene)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertFalse(HarnessControllers.holds(scene))

        // Once it lets it go, the game's process asks for it again.
        field.resignFirstResponder()
        HarnessControllers.take(scene)
        XCTAssertTrue(HarnessControllers.holds(scene))
    }

    func testItAsksInTheWindowTheGameShows() throws {
        let (scene, first) = try openGameWindow()
        HarnessControllers.take(scene)
        // The game shows another window, its key window from then on.
        let (_, second) = try openGameWindow()
        HarnessControllers.take(scene)
        XCTAssertTrue(HarnessControllers.holds(scene))
        let view = try controllersView(in: second)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertFalse(first.subviews.contains { $0 === view })
    }

    // MARK: The journal

    func testTheJournalSaysOnceForEachGameThatTheControllersPressesReachIt() async throws {
        let (app, scene) = try await started(.plain())
        let line = app.displayName + ": the controller's presses reach the game"

        // No press has reached the game: nothing said as the game pauses.
        scene.writeMemory(footprintMiB: 900, availableMiB: 5_000)
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the console shows") { actions.running?.isInFront == false }
        XCTAssertFalse(journal().contains(line))

        // One has: said as the game pauses, once.
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the game shows again") { actions.running?.isInFront == true }
        scene.writeMemory(footprintMiB: 900, availableMiB: 5_000, controllerPress: Date())
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the console shows") { actions.running?.isInFront == false }
        XCTAssertEqual(journal().filter { $0 == line }.count, 1)
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the game shows again") { actions.running?.isInFront == true }
        try await pause(0.7)
        scene.pressControllerHome()
        try await waitUntil("the console shows") { actions.running?.isInFront == false }
        actions.quitRunningGame()
        try await waitUntil("the game has ended") { actions.running == nil }
        XCTAssertEqual(journal().filter { $0 == line }.count, 1, "once for the game, which ended")

        // The game again, which the player quits without pausing it: said
        // as it ends.
        let shown = HarnessScenes.shownCount
        actions.play(app)
        try await waitUntil("the start is over") { actions.work == nil }
        try await waitUntil("its scene shows") { HarnessScenes.shownCount > shown }
        let again = try XCTUnwrap(HarnessScenes.running)
        again.writeMemory(footprintMiB: 900, availableMiB: 5_000, controllerPress: Date())
        actions.quitRunningGame()
        try await waitUntil("the game has ended") { actions.running == nil }
        XCTAssertEqual(journal().filter { $0 == line }.count, 2)
    }

    // MARK: Helpers

    /// What CartoucheGuestControllers.m names the view that asks for the
    /// keyboard.
    private static let controllersIdentifier = "cartouche.controllers"

    /// A window of the game's, key in the harness's scene, which stands in
    /// for the game's own scene: the game's process has its scene and its
    /// windows, the harness has none.
    private func openGameWindow(file: StaticString = #filePath, line: UInt = #line) throws -> (UIWindowScene, UIWindow) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }, file: file, line: line)
        if gameWindows.isEmpty {
            consoleWindow = scene.keyWindow
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        gameWindows.append(window)
        return (scene, window)
    }

    /// The game's scene resigns active, and its windows go: the console's
    /// window is key again.
    private func closeGameWindows() {
        guard let scene = gameWindows.first?.windowScene else { return }
        HarnessControllers.leave(scene)
        for window in gameWindows.reversed() {
            window.subviews.filter { $0.accessibilityIdentifier == Self.controllersIdentifier }.forEach { $0.removeFromSuperview() }
            window.isHidden = true
        }
        gameWindows = []
        consoleWindow?.makeKey()
    }

    /// The view that asks for the keyboard in WINDOW.
    private func controllersView(in window: UIWindow, file: StaticString = #filePath, line: UInt = #line) throws -> UIView {
        try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == Self.controllersIdentifier },
                      "a view asks for the keyboard in the game's window", file: file, line: line)
    }

    /// The steps Cartouche noted for its reports since this test started,
    /// without their time.
    private func journal() -> [String] {
        let lines = CartoucheReports.journal(last: CartoucheJournal.kept)
        guard let start = lines.lastIndex(where: { $0.hasSuffix(" " + Self.journalMark) }) else { return [] }
        // "11-17 10:41:07 Plain: the controller's presses reach the game"
        return lines[lines.index(after: start)...].map { line in
            line.split(separator: " ", maxSplits: 2).dropFirst(2).first.map(String.init) ?? ""
        }
    }
}
