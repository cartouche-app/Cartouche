//
//  BridgeBuilds.swift
//  Cartouche Builder
//
//  What the Mac shows a paired iPhone of its builds over the bridge
//  (CartoucheBridgeBuilds, launcher/Sources/CartoucheBridgeBuilds.swift):
//  each game of the library, building now or waiting its turn in the batch
//  running, or as the library has it, due, up to date, failed; when its IPA
//  was last built, and when its last build failed and why, in the words
//  the Mac's window shows, cut; whether the Mac follows it, and whether its
//  build can be stopped, or it be taken out of the queue, alone; how many
//  games Build what is due builds, and the nightly build. Over the bridge
//  alone, to the player's own iPhones: no file of the Mac's, nothing to any
//  server.
//

import CartoucheCore
import Foundation

public enum BridgeBuilds {
    /// The most of a failure's words an iPhone gets.
    static let errorLength = 500

    /// What the window can do to the games of the batch, and to the rest.
    public struct Control {
        /// Whether a game building, or waiting its turn, can be stopped, or
        /// taken out of the queue, alone now; and whether its build is
        /// stopping.
        public var stoppable: (String) -> Bool
        public var stopping: (String) -> Bool
        /// How many games Build what is due builds.
        public var due: Int
        /// The nightly build, once the settings are read.
        public var nightly: CartoucheBridgeBuilds.Nightly?

        public init(stoppable: @escaping (String) -> Bool, stopping: @escaping (String) -> Bool, due: Int,
                    nightly: CartoucheBridgeBuilds.Nightly?) {
            self.stoppable = stoppable
            self.stopping = stopping
            self.due = due
            self.nightly = nightly
        }
    }

    /// GAMES, the library's, with those BUILDING now and those WAITING
    /// their turn, in their order, in the batch running or starting
    /// (RUNNING). READY: whether the Mac takes a build now; WHY not, in the
    /// player's words. STAGE names a build's step in the player's words.
    /// TARGETS: what the build of a game building or waiting makes, and the
    /// part it makes now (AppModel.targets: as the batch planned it, else
    /// as the game's settings say). CONTROL: what the window can do to
    /// them, which the iPhone does too.
    public static func shared(games: [Game], building: [GameProgress], waiting: [GameProgress], running: Bool,
                              ready: Bool, why: String?, stage: (String?) -> String,
                              targets: (GameProgress) -> CartoucheBuildTargets? = { $0.targets },
                              control: Control? = nil) -> CartoucheBridgeBuilds {
        var now: [String: GameProgress] = [:]
        for progress in building where now[progress.titleID] == nil {
            now[progress.titleID] = progress
        }
        var turns: [String: Int] = [:]
        var queue: [String: GameProgress] = [:]
        var order: [GameProgress] = []
        for progress in waiting where now[progress.titleID] == nil && turns[progress.titleID] == nil {
            order.append(progress)
            queue[progress.titleID] = progress
            turns[progress.titleID] = order.count
        }
        var shared = games.map { game in
            Self.game(game, building: now[game.titleID], turn: turns[game.titleID], waiting: queue[game.titleID], stage: stage,
                      targets: targets)
        }
        // A game of the batch the library does not show yet: by the batch's
        // own words.
        var known = Set(games.map(\.titleID))
        for progress in building + order where known.insert(progress.titleID).inserted {
            shared.append(Self.game(progress, turn: turns[progress.titleID], stage: stage, targets: targets))
        }
        guard let control else {
            return CartoucheBridgeBuilds(running: running, ready: ready, why: ready ? nil : why, games: shared)
        }
        for index in shared.indices where shared[index].state == "building" || shared[index].state == "queued" {
            let titleID = shared[index].id
            let stopping = shared[index].state == "building" && control.stopping(titleID)
            shared[index].stoppable = !stopping && control.stoppable(titleID)
            shared[index].stopping = stopping
        }
        return CartoucheBridgeBuilds(running: running, ready: ready, why: ready ? nil : why, games: shared, due: control.due,
                                     nightly: control.nightly)
    }

    /// GAME of the library, building now (BUILDING), waiting its turn
    /// (TURN, WAITING), or as the library has it. What it is built for,
    /// and, built for this Mac too, its app's own build and failure; built
    /// for this Mac alone, its dates are its app's.
    static func game(_ game: Game, building: GameProgress?, turn: Int?, waiting: GameProgress? = nil, stage: (String?) -> String,
                     targets: (GameProgress) -> CartoucheBuildTargets? = { $0.targets }) -> CartoucheBridgeBuilds.Game {
        let alone = game.onMac && !game.onIOS
        let last = Self.last(alone ? game.mac?.build : game.build, alone ? game.mac?.attempt : game.attempt)
        var shared = CartoucheBridgeBuilds.Game(id: game.titleID, name: game.name, state: game.state.rawValue, reasons: game.reasons,
                                                built: last.built, failed: last.failed, error: last.error, buildable: game.canBuild,
                                                followed: game.canBuild ? game.followed : nil, platforms: game.builtFor?.names ?? [])
        if game.onIOS, game.onMac {
            let app = Self.last(game.mac?.build, game.mac?.attempt)
            shared.mac = CartoucheBridgeBuilds.MacApp(built: app.built, failed: app.failed, error: app.error, due: game.dueForMacAppAlone)
        }
        if game.dueForMacAppAlone {
            // Its IPA up to date: so it is to an iPhone, which reads that its
            // app for the Mac is due when it knows (mac.due).
            shared.state = GameState.upToDate.rawValue
            shared.reasons = []
        }
        if let building {
            shared.state = "building"
            shared.progress = building.overall ?? building.frac
            shared.step = stage(building.stage)
            shared.left = building.eta.flatMap { $0 > 0 ? $0 : nil }
            let made = targets(building)
            shared.makes = made?.names
            shared.now = made?.now?.rawValue
        } else if let turn {
            shared.state = "queued"
            shared.turn = turn
            shared.makes = (waiting.flatMap(targets) ?? game.plannedTargets(forced: game.state != .due))?.names
        } else if game.state == .building || game.state == .queued {
            // The library read while the batch had it, which no longer does:
            // as it was before.
            shared.state = last.built == nil ? GameState.due.rawValue : GameState.upToDate.rawValue
        }
        return shared
    }

    /// A game of the batch alone, building or waiting its turn (TURN).
    static func game(_ progress: GameProgress, turn: Int?, stage: (String?) -> String,
                     targets: (GameProgress) -> CartoucheBuildTargets? = { $0.targets }) -> CartoucheBridgeBuilds.Game {
        var shared = CartoucheBridgeBuilds.Game(id: progress.titleID, name: progress.name, state: progress.state, reasons: progress.reasons ?? [])
        let made = targets(progress)
        shared.makes = made?.names
        if progress.state == "building" {
            shared.progress = progress.overall ?? progress.frac
            shared.step = stage(progress.stage)
            shared.left = progress.eta.flatMap { $0 > 0 ? $0 : nil }
            shared.now = made?.now?.rawValue
        } else {
            shared.state = "queued"
            shared.turn = turn
        }
        return shared
    }

    /// When BUILD was made, and when ATTEMPT, its last that did not build,
    /// failed after it, and why, cut: a stop is no failure.
    private static func last(_ build: GameBuild?, _ attempt: GameAttempt?) -> (built: Date?, failed: Date?, error: String?) {
        let built = build?.date
        guard let attempt, attempt.result == "failed", let at = attempt.date, built.map({ at > $0 }) ?? true else {
            return (built, nil, nil)
        }
        return (built, at, attempt.error.map(cut))
    }

    /// Whether GAME is due for its app for this Mac alone, by reasons of
    /// that app (mac_…), its IPA up to date (Game.dueForMacAppAlone): an
    /// iPhone that says what is due asks for that app alone, as the Build
    /// button of its sheet; one that does not, for its IPA again too, as
    /// for a game up to date (forced).
    public static func dueForMacAppAlone(_ game: Game) -> Bool {
        game.dueForMacAppAlone
    }

    /// Whether the build of GAME an iPhone asks for is forced, built again
    /// even up to date, as its Build button on the Mac: unless due. Due
    /// for its app for this Mac alone, which an iPhone that does not ask
    /// for what is due (DUE) shows as up to date: forced, its IPA built
    /// again too.
    public static func forced(_ game: Game, due: Bool) -> Bool {
        game.state != .due || (game.dueForMacAppAlone && !due)
    }

    /// What the Mac builds of the games an iPhone asks for, ASKED, what is
    /// due when empty (DUE). NEVER: those no Mac built that this Mac did not
    /// build either (Unbuilt.swift), which the Mac's window asks about first
    /// and an iPhone cannot: left aside, as the nightly run leaves them.
    /// Empty: what is due, as asked; nil: nothing left, which the iPhone is
    /// told why.
    public static func toBuild(_ asked: [String], due: [String], never: Set<String>) -> [String]? {
        guard !never.isEmpty else { return asked }
        let others = (asked.isEmpty ? due : asked).filter { !never.contains($0) }
        return others.isEmpty ? nil : others
    }

    private static func cut(_ text: String) -> String {
        text.count <= errorLength ? text : String(text.prefix(errorLength - 1)) + "…"
    }
}
