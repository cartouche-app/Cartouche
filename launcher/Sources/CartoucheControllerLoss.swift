//
//  CartoucheControllerLoss.swift
//  Cartouche
//
//  A game that loses its last controller while the player plays pauses
//  (docs/decisions/166.md): its controller's battery ran out, or its
//  Bluetooth link dropped, and the game went on under the controls on the
//  screen, the race or the fight lost meanwhile. A game played with a
//  controller that has none for 3 seconds goes behind the console, paused,
//  as the Home button takes it there; the console says that the controller
//  disconnected. A controller that connects again brings the game back, as
//  Resume does. A game played on the screen alone, which never had a
//  controller, never pauses for one; nor one the player brought back with
//  Resume and no controller: they play on the screen from then on, until a
//  controller connects again. System › While a game runs turns it off.
//
//  This is the rule alone, apart from the controllers and the screens, so
//  that it is the same on the iPhone (CartoucheGameHost.swift) and on the
//  Mac (Cartouche's console there, builder/mac), and tested on its own.
//  CartoucheControllerPause (CartoucheGamepad.swift) follows the
//  controllers and the game, and asks this what to do.
//
//  Foundation only, so that it is tested on a Mac (swift test
//  --package-path launcher).
//

import Foundation

/// When a game playing with a controller pauses for losing it, and when it
/// comes back.
struct CartoucheControllerLoss: Equatable {
    /// How long a game on screen goes without a controller before it
    /// pauses: a link that drops for a moment, a controller that wakes as a
    /// button is pressed, does not pause it.
    static let delay: TimeInterval = 3

    /// The player's switch, in System › While a game runs: on unless they
    /// turned it off.
    static let settingKey = "pausesWhenTheControllerGoes"

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: settingKey) as? Bool ?? true
    }

    /// What to do now.
    enum Step: Equatable {
        case nothing
        /// The game has no controller since `lostSince`: look again once
        /// `delay` has passed.
        case wait
        /// The console over the game, which pauses.
        case pause
        /// The game again: it paused for its controller, and has one again.
        case resume
    }

    /// How a pause for the controller ended, for the measurements
    /// (game.controllerPause in telemetry/README.md).
    enum Ending: String, Equatable {
        /// A controller connected again, and the game came back.
        case controller
        /// The player brought the game back: Resume, Play, the Home button
        /// over the game.
        case resume
        /// The player quit the game.
        case quit
        /// The game ended otherwise: iOS stopped it, or it ended itself.
        case ended
    }

    /// A pause for the controller that ended: how, and how long it lasted.
    struct Pause: Equatable {
        let ending: Ending
        let seconds: TimeInterval
    }

    /// Whether the game on screen had a controller since it last came on
    /// screen without one.
    private(set) var hadController = false
    /// Since when the game on screen has had no controller, after it had
    /// one; nil while it has one, or while it is not on screen.
    private(set) var lostSince: Date?
    /// When the game paused for its controller, while it stays paused.
    private(set) var pausedAt: Date?
    /// A controller connected while the game was paused for it: the game
    /// comes back for it.
    private(set) var comingBack = false

    var isPausedForController: Bool { pausedAt != nil }

    /// A game starts, on screen, with CONTROLLERS connected.
    mutating func started(controllers: Int) {
        self = CartoucheControllerLoss()
        hadController = controllers > 0
    }

    /// The controllers connected now are CONTROLLERS, the game on screen or
    /// not (INFRONT), at NOW.
    mutating func controllersChanged(_ controllers: Int, inFront: Bool, now: Date) -> Step {
        if inFront {
            if controllers > 0 {
                hadController = true
                lostSince = nil
                return .nothing
            }
            guard hadController else { return .nothing }
            if lostSince == nil { lostSince = now }
            return .wait
        }
        lostSince = nil
        // Each time, should the console not bring the game back at once,
        // as while an install shows over it.
        guard isPausedForController, controllers > 0 else { return .nothing }
        comingBack = true
        return .resume
    }

    /// Once the delay has passed since the controller went: the game pauses
    /// if it is still on screen without one, and the player's switch ISON
    /// is on.
    mutating func check(_ controllers: Int, inFront: Bool, isOn: Bool, now: Date) -> Step {
        guard inFront, controllers == 0, hadController, let lostSince else { return .nothing }
        // A timer may fire a few milliseconds early.
        guard now.timeIntervalSince(lostSince) >= Self.delay - 0.05 else { return .wait }
        self.lostSince = nil
        guard isOn else { return .nothing }
        pausedAt = now
        comingBack = false
        return .pause
    }

    /// The game goes behind the console: the player opened it, or the game
    /// paused for its controller. No pause for the controller is to come.
    mutating func wentBehind() {
        lostSince = nil
    }

    /// The game comes on screen again, with CONTROLLERS connected: the
    /// pause for its controller, if it was one, ends.
    mutating func cameToFront(controllers: Int, now: Date) -> Pause? {
        lostSince = nil
        // Brought back without a controller, the player plays on the
        // screen: no pause until one connects.
        hadController = controllers > 0
        return endPause(comingBack ? .controller : .resume, now: now)
    }

    /// The game ended, as the player quit it (QUIT) or not.
    mutating func ended(quit: Bool, now: Date) -> Pause? {
        let pause = endPause(quit ? .quit : .ended, now: now)
        self = CartoucheControllerLoss()
        return pause
    }

    private mutating func endPause(_ ending: Ending, now: Date) -> Pause? {
        guard let pausedAt else { return nil }
        self.pausedAt = nil
        comingBack = false
        return Pause(ending: ending, seconds: max(0, now.timeIntervalSince(pausedAt)))
    }

    /// The fields of game.controllerPause for PAUSE: how it ended, and how
    /// long it lasted, in whole seconds.
    static func fields(of pause: Pause) -> [String: CartoucheTelemetryValue] {
        ["ended": .text(pause.ending.rawValue), "seconds": .number(pause.seconds.rounded())]
    }
}
