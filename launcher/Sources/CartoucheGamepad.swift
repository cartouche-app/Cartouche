//
//  CartoucheGamepad.swift
//  Cartouche
//
//  A game controller drives the home screen as it would a console's: the
//  D-pad or the left stick moves between games, A plays, B goes back, X
//  opens the game's sheet, Y the list of every game, Menu the system page,
//  and the shoulder buttons change the list's filter. A held direction
//  repeats. Touch keeps working alongside.
//
//  A game takes over the controller once it starts. LiveContainer runs it
//  in place of the launcher, or behind the console (CartoucheGameHost):
//  there, while the game is on screen, the console takes none of the
//  controller's buttons, and the Home button, which comes to Cartouche
//  rather than to iOS, shows the console, then the game again.
//
//  A game that loses its last controller while the player plays pauses,
//  behind the console, and a controller that connects again brings it back
//  (CartoucheControllerPause, below; the rule is CartoucheControllerLoss's,
//  docs/decisions/166.md). On the Mac, Cartouche's console does the same
//  for a game's app (builder/mac).
//

import Combine
import GameController

@available(iOS 17.0, *)
@MainActor
final class CartoucheGamepad: ObservableObject {
    enum Input: Hashable {
        case up, down, left, right
        case a, b, x, y, menu
        case previous, next
    }

    static let shared = CartoucheGamepad()

    /// Whether a controller with a D-pad and face buttons is connected, so
    /// that the screen shows which button does what.
    @Published private(set) var isConnected = false

    /// How many controllers are connected, of any kind: a game that loses
    /// its last one pauses (CartoucheControllerPause).
    @Published private(set) var count = 0

    #if CARTOUCHE_HARNESS
    /// The controllers the harness's tests connect, in place of the real
    /// ones: the Simulator has none.
    var harnessControllers: Int? {
        didSet { update() }
    }
    #endif

    /// Each press once; a held direction repeats.
    let inputs = PassthroughSubject<Input, Never>()

    /// Each press of the Home button. iOS keeps them while no game runs
    /// behind the console (holdsHome).
    let homePresses = PassthroughSubject<Void, Never>()

    /// While a game runs behind the console, the Home button is Cartouche's.
    var holdsHome = false {
        didSet {
            for controller in GCController.controllers() {
                holdHome(of: controller)
            }
        }
    }

    /// While the game behind the console is on screen, the controller is
    /// the game's: the console takes none of its buttons but Home.
    var gameInFront = false {
        didSet {
            held = nil
            repeating?.cancel()
        }
    }

    private var held: Input?
    private var repeating: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.update(without: controller) }
        })
        for controller in GCController.controllers() {
            attach(controller)
        }
        update()
    }

    /// Shows the button hints without a controller (the launcher's
    /// screenshots).
    func showHints() {
        isConnected = true
    }

    /// The symbol of a button as the connected controller marks it (a
    /// letter on one, a shape on another), or a letter without one.
    func symbol(for input: Input) -> String {
        let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad
        switch input {
        case .a: return pad?.buttonA.sfSymbolsName ?? "a.circle.fill"
        case .b: return pad?.buttonB.sfSymbolsName ?? "b.circle.fill"
        case .x: return pad?.buttonX.sfSymbolsName ?? "x.circle.fill"
        case .y: return pad?.buttonY.sfSymbolsName ?? "y.circle.fill"
        case .menu: return pad?.buttonMenu.sfSymbolsName ?? "line.3.horizontal.circle.fill"
        case .previous: return pad?.leftShoulder.sfSymbolsName ?? "l1.rectangle.roundedbottom.fill"
        case .next: return pad?.rightShoulder.sfSymbolsName ?? "r1.rectangle.roundedbottom.fill"
        case .up, .down, .left, .right: return pad?.dpad.sfSymbolsName ?? "dpad.fill"
        }
    }

    /// The controllers connected now; GONE, one that has just
    /// disconnected, never among them.
    private func update(without gone: GCController? = nil) {
        let controllers = GCController.controllers().filter { $0 !== gone }
        isConnected = controllers.contains { $0.extendedGamepad != nil }
        var count = controllers.count
        #if CARTOUCHE_HARNESS
        if let harnessControllers {
            count = harnessControllers
        }
        #endif
        if count != self.count {
            self.count = count
        }
        if !isConnected {
            held = nil
            repeating?.cancel()
        }
    }

    private func attach(_ controller: GCController?) {
        defer { update() }
        guard let controller, let pad = controller.extendedGamepad else { return }
        // Handlers run on the controller's handler queue, the main queue
        // unless someone changes it.
        controller.handlerQueue = .main

        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.direction(x: x, y: y) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.direction(x: x, y: y) }
        }
        let buttons: [(GCControllerButtonInput?, Input)] = [
            (pad.buttonA, .a), (pad.buttonB, .b), (pad.buttonX, .x), (pad.buttonY, .y),
            (pad.buttonMenu, .menu), (pad.leftShoulder, .previous), (pad.rightShoulder, .next),
        ]
        for (button, input) in buttons {
            button?.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.send(input) }
            }
        }
        pad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.homePresses.send(()) }
        }
        holdHome(of: controller)
    }

    private func send(_ input: Input) {
        guard !gameInFront else { return }
        inputs.send(input)
    }

    /// The press comes to Cartouche rather than to iOS, as nxnative asks for
    /// a game that runs in Cartouche's place.
    private func holdHome(of controller: GCController) {
        controller.extendedGamepad?.buttonHome?.preferredSystemGestureState = holdsHome ? .disabled : .enabled
    }

    /// A direction from the D-pad or the stick, past half its travel.
    private func direction(x: Float, y: Float) {
        guard !gameInFront else { return }
        let input: Input?
        if abs(x) >= abs(y) {
            input = x > 0.5 ? .right : (x < -0.5 ? .left : nil)
        } else {
            input = y > 0.5 ? .up : (y < -0.5 ? .down : nil)
        }
        guard input != held else { return }
        held = input
        repeating?.cancel()
        guard let input else { return }
        inputs.send(input)
        repeating = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            while !Task.isCancelled {
                self?.send(input)
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }
}

/// A game that loses its last controller while the player plays pauses,
/// as CartoucheControllerLoss says (docs/decisions/166.md): this follows
/// the controllers and the game running, and does what the rule says,
/// through what the device gives it as the game starts: on the iPhone, the
/// game behind the console (CartoucheGameHost), on the Mac, Cartouche's
/// console and the game's app (builder/mac, ConsoleView.swift). One game
/// at a time.
@available(iOS 17.0, *)
@MainActor
final class CartoucheControllerPause {
    static let shared = CartoucheControllerPause()

    /// What the device does for the rule.
    struct Actions {
        /// The console over the game, which pauses.
        var pause: () -> Void
        /// The game again, where the player left it.
        var resume: () -> Void
        /// A pause for the controller ended, for the measurements.
        var ended: (CartoucheControllerLoss.Pause) -> Void
    }

    private(set) var rule = CartoucheControllerLoss()
    private var actions: Actions?
    private var inFront = false
    /// What the game's own process said last of its controllers, on the
    /// iPhone (CartoucheGuest.m): whether it has any; nil until it says
    /// it, from the game's last coming on screen. Its word wins over
    /// Cartouche's own: the game's controllers are those its process has.
    private var gameHasControllers: Bool?
    private var watching: AnyCancellable?
    private var looking: Task<Void, Never>?

    var isPausedForController: Bool { rule.isPausedForController }

    private init() {}

    /// A game starts, on screen: from now on, until it ends, the rule
    /// follows its controllers, and ACTIONS do what it says.
    func gameStarted(_ actions: Actions) {
        looking?.cancel()
        looking = nil
        self.actions = actions
        inFront = true
        gameHasControllers = nil
        let gamepad = CartoucheGamepad.shared
        rule.started(controllers: controllers(gamepad.count))
        // The value to come: a published value is sent before it is set.
        watching = gamepad.$count.dropFirst().removeDuplicates().sink { [weak self] count in
            self?.changed(count)
        }
        #if os(macOS)
        // The console is behind the game's app, which macOS hands the
        // controllers: the console still hears of them, and takes none of
        // their presses while the game is in front (gameInFront).
        GCController.shouldMonitorBackgroundEvents = true
        #endif
    }

    /// The game goes behind the console (INFRONT false), or comes on
    /// screen again.
    func gameMoved(inFront: Bool) {
        guard actions != nil, inFront != self.inFront else { return }
        self.inFront = inFront
        // Its process may have heard nothing while it was paused.
        gameHasControllers = nil
        looking?.cancel()
        looking = nil
        if inFront {
            if let pause = rule.cameToFront(controllers: controllers(CartoucheGamepad.shared.count), now: Date()) {
                actions?.ended(pause)
            }
        } else {
            rule.wentBehind()
        }
    }

    /// The game has ended, as the player quit it (QUIT) or not.
    func gameEnded(quit: Bool) {
        guard let actions else { return }
        if let pause = rule.ended(quit: quit, now: Date()) {
            actions.ended(pause)
        }
        self.actions = nil
        inFront = false
        gameHasControllers = nil
        watching = nil
        looking?.cancel()
        looking = nil
        #if os(macOS)
        GCController.shouldMonitorBackgroundEvents = false
        #endif
    }

    /// The game's own process says whether it has controllers now, on the
    /// iPhone: as one connects or goes, and as the game comes on screen.
    func gameSays(hasControllers: Bool) {
        guard actions != nil, inFront else { return }
        gameHasControllers = hasControllers
        changed(CartoucheGamepad.shared.count)
    }

    /// The controllers the rule counts, Cartouche's being COUNT: the game's
    /// process's word when it has said it, Cartouche's own otherwise.
    private func controllers(_ count: Int) -> Int {
        switch gameHasControllers {
        case true?: return max(count, 1)
        case false?: return 0
        case nil: return count
        }
    }

    private func changed(_ count: Int) {
        guard let actions else { return }
        switch rule.controllersChanged(controllers(count), inFront: inFront, now: Date()) {
        case .wait:
            look()
        case .resume:
            actions.resume()
        case .nothing, .pause:
            break
        }
    }

    /// Looks again once the delay has passed since the controller went.
    private func look() {
        looking?.cancel()
        let since = rule.lostSince ?? Date()
        let left = max(0.05, CartoucheControllerLoss.delay - Date().timeIntervalSince(since))
        looking = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(left * 1000)))
            guard !Task.isCancelled else { return }
            self?.lookAgain()
        }
    }

    private func lookAgain() {
        looking = nil
        guard let actions else { return }
        switch rule.check(controllers(CartoucheGamepad.shared.count), inFront: inFront,
                          isOn: CartoucheControllerLoss.isOn(), now: Date()) {
        case .pause:
            actions.pause()
        case .wait:
            look()
        case .nothing, .resume:
            break
        }
    }
}
