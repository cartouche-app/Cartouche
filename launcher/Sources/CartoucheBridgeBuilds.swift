//
//  CartoucheBridgeBuilds.swift
//  Cartouche
//
//  Cartouche Builder's builds, as the Mac shares them with a paired iPhone
//  over the bridge (CartoucheBridge.swift, its `builds` and `build`, and,
//  from a Mac whose info says hasBuildsControl, `buildDue`, `stop`,
//  `stopAll`, `follow` and `nightly`): whether a batch runs, each game the
//  Mac knows, building, waiting its turn, or as its library has it, whether
//  the Mac follows it, and the Mac's nightly build. And what Cartouche makes
//  of them: a game's line on its sheet, the button that asks the Mac to
//  build it, the one that stops its build, and the Mac's builds now,
//  waiting, done and failed (CartoucheMacBuildsPage.swift).
//
//  A Mac builds a game for the iPhone, its IPA, and for itself, its app
//  (decision 95), or for one of the two: each game says which, each build
//  what it makes and, building, which of the two it makes now, and the
//  game's app for the Mac its own build and failure
//  (CartoucheBuildTargets), as the Mac's window says them of its own
//  builds (decision 126).
//
//  This file is shared: Cartouche compiles it with the launcher, Cartouche
//  Builder through the CartoucheCore package (launcher/Package.swift).
//  Platform-independent: tested on its own by launcher/Package.swift.
//

import Foundation

/// What the Mac answers of its builds. A field a Mac a little older or
/// newer leaves out takes its default.
public struct CartoucheBridgeBuilds: Codable, Equatable, Sendable {
    /// A game the Mac knows: from the player's dumps, or only by its IPA in
    /// the games folder.
    public struct Game: Codable, Equatable, Sendable {
        /// Its title ID, as its dump says: its region's own.
        public var id: String
        /// Its name on the Mac.
        public var name: String
        /// "building" or "queued", in the batch running or starting; else
        /// its state in the Mac's library: "due", "up_to_date", "failed",
        /// "not_followed", "no_profile", "no_source".
        public var state: String
        /// Why it is due, as the Mac's library names it: "new" for a game
        /// never built.
        public var reasons: [String]
        /// Building: how far its build is, from 0 to 1, what it does now in
        /// the Mac's words, and the seconds it has left, when known.
        public var progress: Double?
        public var step: String?
        public var left: Double?
        /// Waiting: its turn, 1 for the next.
        public var turn: Int?
        /// When its IPA was last built, in seconds since 1970; its app's,
        /// for a game the Mac builds for itself alone.
        public var built: Double?
        /// When its last build failed, after the last one that worked, and
        /// why, in the Mac's words: its IPA's, or its app's for a game the
        /// Mac builds for itself alone.
        public var failed: Double?
        public var error: String?
        /// Whether the Mac has its dump: with its IPA alone, the Mac cannot
        /// build it again.
        public var buildable: Bool
        /// Whether the Mac follows it: builds it when nxnative improves it.
        /// Nil from a Mac that does not say.
        public var followed: Bool?
        /// Building or waiting its turn: whether the Mac can stop its build,
        /// or take it out of the queue, alone now; and whether its build is
        /// stopping. Nil from a Mac that does not say.
        public var stoppable: Bool?
        public var stopping: Bool?
        /// What the Mac builds the game for, in that order: "ios", its IPA,
        /// for the iPhone; "mac", its app, for the Mac. Nil from a Mac that
        /// does not say.
        public var platforms: [String]?
        /// Building or waiting its turn: what its build makes, of the two,
        /// in that order; building, the one it makes now. Nil from a Mac
        /// that does not say.
        public var makes: [String]?
        public var now: String?
        /// Its app for the Mac, for a game the Mac builds for the iPhone and
        /// for itself: its own build and failure. Nil from a Mac that does
        /// not say, and for a game it builds for one of the two alone, whose
        /// dates are of that one.
        public var mac: MacApp?

        public init(id: String, name: String, state: String, reasons: [String] = [], progress: Double? = nil, step: String? = nil,
                    left: Double? = nil, turn: Int? = nil, built: Date? = nil, failed: Date? = nil, error: String? = nil, buildable: Bool = true,
                    followed: Bool? = nil, stoppable: Bool? = nil, stopping: Bool? = nil, platforms: [String]? = nil, makes: [String]? = nil,
                    now: String? = nil, mac: MacApp? = nil) {
            self.id = id
            self.name = name
            self.state = state
            self.reasons = reasons
            self.progress = progress
            self.step = step
            self.left = left
            self.turn = turn
            self.built = built?.timeIntervalSince1970
            self.failed = failed?.timeIntervalSince1970
            self.error = error
            self.buildable = buildable
            self.followed = followed
            self.stoppable = stoppable
            self.stopping = stopping
            self.platforms = platforms
            self.makes = makes
            self.now = now
            self.mac = mac
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, state, reasons, progress, step, left, turn, built, failed, error, buildable, followed, stoppable, stopping
            case platforms, makes, now, mac
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
            state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
            reasons = (try? c.decodeIfPresent([String].self, forKey: .reasons)) ?? []
            progress = try? c.decodeIfPresent(Double.self, forKey: .progress)
            step = try? c.decodeIfPresent(String.self, forKey: .step)
            left = try? c.decodeIfPresent(Double.self, forKey: .left)
            turn = try? c.decodeIfPresent(Int.self, forKey: .turn)
            built = try? c.decodeIfPresent(Double.self, forKey: .built)
            failed = try? c.decodeIfPresent(Double.self, forKey: .failed)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            buildable = (try? c.decodeIfPresent(Bool.self, forKey: .buildable)) ?? true
            followed = try? c.decodeIfPresent(Bool.self, forKey: .followed)
            stoppable = try? c.decodeIfPresent(Bool.self, forKey: .stoppable)
            stopping = try? c.decodeIfPresent(Bool.self, forKey: .stopping)
            platforms = try? c.decodeIfPresent([String].self, forKey: .platforms)
            makes = try? c.decodeIfPresent([String].self, forKey: .makes)
            now = try? c.decodeIfPresent(String.self, forKey: .now)
            mac = try? c.decodeIfPresent(MacApp.self, forKey: .mac)
        }

        public var builtDate: Date? { built.map { Date(timeIntervalSince1970: $0) } }
        public var failedDate: Date? { failed.map { Date(timeIntervalSince1970: $0) } }

        /// What a build of it is for, as the Mac says: what its build makes,
        /// and which of the two it makes now, building or waiting its turn;
        /// else what the Mac builds the game for. Nil from a Mac that does
        /// not say.
        public var targets: CartoucheBuildTargets? {
            if state == "building" || state == "queued", let made = CartoucheBuildTargets(makes, now: state == "building" ? now : nil) {
                return made
            }
            return CartoucheBuildTargets(platforms)
        }

        /// The last failure of its app for the Mac, after the last build
        /// of it that worked: when, and why in the Mac's words.
        public var macFailure: (date: Date, error: String?)? {
            guard let mac, let failed = mac.failed, failed > (mac.built ?? -.infinity) else { return nil }
            return (Date(timeIntervalSince1970: failed), mac.error)
        }
    }

    /// A game's app for the Mac, which the Mac builds of the same files as
    /// its IPA, after it, or alone (decision 95).
    public struct MacApp: Codable, Equatable, Sendable {
        /// When it was last built, in seconds since 1970.
        public var built: Double?
        /// When its last build failed, after the last one that worked, and
        /// why, in the Mac's words.
        public var failed: Double?
        public var error: String?
        /// Whether a build of it alone is due, its IPA up to date: the
        /// game's state then says up to date, as its IPA is.
        public var due: Bool

        public init(built: Date? = nil, failed: Date? = nil, error: String? = nil, due: Bool = false) {
            self.built = built?.timeIntervalSince1970
            self.failed = failed?.timeIntervalSince1970
            self.error = error
            self.due = due
        }

        private enum CodingKeys: String, CodingKey { case built, failed, error, due }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            built = try? c.decodeIfPresent(Double.self, forKey: .built)
            failed = try? c.decodeIfPresent(Double.self, forKey: .failed)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            due = (try? c.decodeIfPresent(Bool.self, forKey: .due)) ?? false
        }

        public var builtDate: Date? { built.map { Date(timeIntervalSince1970: $0) } }
    }

    /// The Mac's nightly build: whether it builds what is due every night,
    /// even with its app closed, and at what time, in the Mac's own hours.
    public struct Nightly: Codable, Equatable, Sendable {
        public var on: Bool
        public var hour: Int
        public var minute: Int

        public init(on: Bool, hour: Int = 3, minute: Int = 30) {
            self.on = on
            self.hour = min(max(hour, 0), 23)
            self.minute = min(max(minute, 0), 59)
        }

        private enum CodingKeys: String, CodingKey { case on, hour, minute }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(on: (try? c.decodeIfPresent(Bool.self, forKey: .on)) ?? false,
                      hour: (try? c.decodeIfPresent(Int.self, forKey: .hour)) ?? 3,
                      minute: (try? c.decodeIfPresent(Int.self, forKey: .minute)) ?? 30)
        }
    }

    /// Whether a batch runs on the Mac, or starts: a build asked for waits
    /// its turn in it.
    public var running: Bool
    /// Whether the Mac takes a build now; when it does not, why, in its
    /// words: its tools not ready, an IPA being imported.
    public var ready: Bool
    public var why: String?
    public var games: [Game]
    /// How many games are due that the batch running does not have: what
    /// Build what is due builds. Nil from a Mac that does not say.
    public var due: Int?
    /// The Mac's nightly build; nil from a Mac that does not say.
    public var nightly: Nightly?

    public init(running: Bool = false, ready: Bool = true, why: String? = nil, games: [Game] = [], due: Int? = nil, nightly: Nightly? = nil) {
        self.running = running
        self.ready = ready
        self.why = why
        self.games = games
        self.due = due
        self.nightly = nightly
    }

    private enum CodingKeys: String, CodingKey { case running, ready, why, games, due, nightly }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? false
        ready = (try? c.decodeIfPresent(Bool.self, forKey: .ready)) ?? true
        why = try? c.decodeIfPresent(String.self, forKey: .why)
        games = (try? c.decodeIfPresent([Game].self, forKey: .games)) ?? []
        due = try? c.decodeIfPresent(Int.self, forKey: .due)
        nightly = try? c.decodeIfPresent(Nightly.self, forKey: .nightly)
    }

    /// The games building now.
    public var building: [Game] { games.filter { $0.state == "building" } }

    /// The games waiting their turn, the next first.
    public var waiting: [Game] {
        games.filter { $0.state == "queued" }.sorted { ($0.turn ?? .max) < ($1.turn ?? .max) }
    }

    /// Every game the Mac knows, by name.
    public var library: [Game] {
        games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// How many games Build what is due builds: as the Mac counts them, or,
    /// from a Mac that does not say, those due that the batch does not have.
    public var dueCount: Int {
        due ?? games.filter { $0.state == "due" }.count
    }

    /// A game's last build: built, or failed, and when; what it was for
    /// (PLATFORM: its IPA, for the iPhone, or its app, for the Mac; nil
    /// from a Mac that does not say), and why it failed, in the Mac's words.
    public struct Done: Equatable, Identifiable, Sendable {
        public let game: Game
        public let failed: Bool
        public let date: Date
        public let platform: CartoucheBuildTargets.Platform?
        public let error: String?
        /// The game's title ID; for its app for the Mac apart from its
        /// IPA, with " mac" after it.
        public let id: String

        public init(game: Game, failed: Bool, date: Date, platform: CartoucheBuildTargets.Platform? = nil, error: String? = nil,
                    app: Bool = false) {
            self.game = game
            self.failed = failed
            self.date = date
            self.platform = platform
            self.error = error
            id = app ? game.id + " mac" : game.id
        }
    }

    /// The builds done, the newest first: each game's last, built or
    /// failed, at most LIMIT; none of a game building or waiting now. A
    /// game's last is its IPA's, or its app's for one the Mac builds for
    /// itself alone.
    public func done(limit: Int = 8) -> [Done] {
        let ended = games.compactMap { game -> Done? in
            guard game.state != "building", game.state != "queued" else { return nil }
            let built = game.built ?? -.infinity, failed = game.failed ?? -.infinity
            let platform: CartoucheBuildTargets.Platform? = game.platforms.map { $0 == ["mac"] ? .mac : .iPhone }
            if let date = game.failedDate, failed > built { return Done(game: game, failed: true, date: date, platform: platform, error: game.error) }
            if let date = game.builtDate { return Done(game: game, failed: false, date: date, platform: platform) }
            return nil
        }
        return Array(ended.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// The builds whose last failed, the newest first: a game's IPA, and
    /// its app for the Mac apart; none of a game building or waiting now.
    public var failures: [Done] {
        let apps = games.compactMap { game -> Done? in
            guard game.state != "building", game.state != "queued", let failure = game.macFailure else { return nil }
            return Done(game: game, failed: true, date: failure.date, platform: .mac, error: failure.error, app: true)
        }
        return (done(limit: .max).filter(\.failed) + apps).sorted { $0.date > $1.date }
    }
}

// MARK: What a build is for

/// What a build on the Mac makes: a game's IPA, for the iPhone, then its
/// app, for the Mac, or one of the two (decision 95); building, the one it
/// makes now. Cartouche's words of it, and the Mac's window's, say which,
/// in a line (Line).
public struct CartoucheBuildTargets: Equatable, Sendable {
    public enum Platform: String, Equatable, Sendable {
        /// Its IPA, for the iPhone.
        case iPhone = "ios"
        /// Its app, for the Mac.
        case mac
    }

    /// In the order a build makes them: the iPhone's, then the Mac's.
    public let platforms: [Platform]
    /// Building: the one it makes now.
    public let now: Platform?

    /// PLATFORMS in the order a build makes them, NOW one of them, or nil
    /// when there are none.
    public init?(_ platforms: [Platform], now: Platform? = nil) {
        let ordered = [Platform.iPhone, .mac].filter(platforms.contains)
        guard !ordered.isEmpty else { return nil }
        self.platforms = ordered
        self.now = now.flatMap { ordered.contains($0) ? $0 : nil }
    }

    /// NAMES as the Mac says them, "ios" and "mac"; NOW, the one it makes
    /// now. Nil when the Mac says none it knows.
    public init?(_ names: [String]?, now: String? = nil) {
        self.init((names ?? []).compactMap(Platform.init(rawValue:)), now: now.flatMap(Platform.init(rawValue:)))
    }

    /// The names the Mac says them by, in their order.
    public var names: [String] { platforms.map(\.rawValue) }

    /// What a line says of it.
    public enum Line: Equatable, Sendable {
        /// Its IPA alone, for the iPhone.
        case iPhone
        /// Its app alone, for the Mac.
        case mac
        /// Both, neither being made now.
        case both
        /// Both: its IPA now, its app for the Mac after it.
        case iPhoneThenMac
        /// Both: its IPA made, its app for the Mac now.
        case macAfterIPhone
    }

    public var line: Line {
        guard platforms.count == 2 else { return platforms == [.mac] ? .mac : .iPhone }
        switch now {
        case .iPhone?: return .iPhoneThenMac
        case .mac?: return .macAfterIPhone
        case nil: return .both
        }
    }
}

// MARK: A game's sheet

/// A game's build on the player's Mac, as its sheet shows it: where the
/// build is, and the button that asks the Mac for one.
struct CartoucheMacBuild: Equatable {
    enum Status: Equatable {
        /// Building now: how far, what it does, the seconds it has left.
        case building(progress: Double?, step: String?, left: Double?)
        /// Waiting its turn in the batch: 1 for the next.
        case waiting(turn: Int?)
        /// Never built on the Mac.
        case new
        /// nxnative improved it since its last build: a build is due.
        case improved(built: Date?)
        /// Built, with nothing due since.
        case upToDate(built: Date?)
        /// Its last build failed, and why, in the Mac's words.
        case failed(at: Date?, error: String?)
        /// Not followed: the Mac builds it only when asked.
        case notFollowed(built: Date?)
        /// nxnative has no profile for it yet.
        case noProfile
        /// Only its IPA is on the Mac, without its dump.
        case ipaOnly(built: Date?)
        /// Its IPA up to date, its app for the Mac to build: never built,
        /// gone, or older than its IPA.
        case macDue(built: Date?)
        /// Its IPA up to date, the last build of its app for the Mac
        /// failed, and why, in the Mac's words.
        case macFailed(at: Date?, error: String?)
    }

    /// What the button of a game building or waiting asks of the Mac.
    enum Halt: Equatable {
        /// Building: stop its build; the batch goes on with the next game.
        case stop
        /// Waiting its turn: take it out of the queue.
        case remove
    }

    /// What the button asks of the Mac.
    enum Action: Equatable {
        /// A first build.
        case build
        /// A build nxnative's changes call for.
        case rebuild
        /// A build of a game up to date, or whose last one failed.
        case buildAgain
        /// A build after the games of the batch running.
        case addToQueue
        /// A build of its app for the Mac alone, its IPA up to date.
        case buildMac
    }

    /// The game's title ID on the Mac, and its name there.
    let id: String
    let name: String
    let status: Status
    /// The button; none while the game builds or waits its turn, nor for a
    /// game the Mac has only the IPA of.
    let action: Action?
    /// The button that stops its build, or takes it out of the queue: only
    /// when the Mac says it can, alone, now.
    let halt: Halt?
    /// Whether its build is stopping.
    let stopping: Bool
    /// Whether the Mac follows the game; nil when it does not say.
    let followed: Bool?
    /// Whether the Mac takes a build now; why not otherwise, in its words.
    let ready: Bool
    let why: String?
    /// What a build of it is for: what its build makes, building or
    /// waiting, which of the two it makes now, building; else what the Mac
    /// builds it for. Nil from a Mac that does not say.
    let targets: CartoucheBuildTargets?

    /// Whether the button asks the Mac for what is due of the game alone,
    /// its app for the Mac, as the Build button of its sheet on the Mac
    /// does, rather than for all of it again.
    var asksDue: Bool {
        if case .macDue = status { return true }
        return false
    }

    /// The game whose title IDs are TITLE_IDS in BUILDS, the first one the
    /// Mac knows: a game's IDs are those of its regions, and the Mac has
    /// the one of the player's dump.
    static func of(_ titleIds: [String], in builds: CartoucheBridgeBuilds) -> CartoucheMacBuild? {
        for titleId in titleIds {
            if let game = builds.games.first(where: { $0.id.caseInsensitiveCompare(titleId) == .orderedSame }) {
                return CartoucheMacBuild(game, running: builds.running, ready: builds.ready, why: builds.why)
            }
        }
        return nil
    }

    init(_ game: CartoucheBridgeBuilds.Game, running: Bool, ready: Bool, why: String?) {
        id = game.id
        name = game.name
        followed = game.followed
        self.ready = ready
        self.why = ready ? nil : why
        targets = game.targets
        let failedLast = (game.failed ?? -.infinity) > (game.built ?? -.infinity)
        switch game.state {
        case "building":
            status = .building(progress: game.progress.map { min(max($0, 0), 1) }, step: game.step, left: game.left)
        case "queued":
            status = .waiting(turn: game.turn)
        case "no_source":
            status = .ipaOnly(built: game.builtDate)
        case "no_profile":
            status = .noProfile
        case "failed":
            status = .failed(at: game.failedDate, error: game.error)
        case "not_followed":
            status = failedLast ? .failed(at: game.failedDate, error: game.error) : .notFollowed(built: game.builtDate)
        case "due":
            // As the Mac says it: never built, else improved.
            if game.reasons == ["new"] {
                status = failedLast ? .failed(at: game.failedDate, error: game.error) : .new
            } else {
                status = .improved(built: game.builtDate)
            }
        default:
            if failedLast {
                status = .failed(at: game.failedDate, error: game.error)
            } else if game.mac?.due == true {
                // Its IPA up to date, as the Mac says it, its app not.
                status = .macDue(built: game.builtDate)
            } else if let failure = game.macFailure {
                status = .macFailed(at: failure.date, error: failure.error)
            } else {
                status = .upToDate(built: game.builtDate)
            }
        }
        stopping = game.stopping == true
        switch status {
        case .building:
            halt = game.stoppable == true && !stopping ? .stop : nil
        case .waiting:
            halt = game.stoppable == true ? .remove : nil
        default:
            halt = nil
        }
        switch status {
        case .building, .waiting, .ipaOnly:
            action = nil
        default:
            if !game.buildable {
                action = nil
            } else if running {
                // A batch runs: the game waits its turn after the games in it.
                action = .addToQueue
            } else if case .macDue = status {
                action = .buildMac
            } else if case .improved = status {
                action = .rebuild
            } else if game.built == nil {
                action = .build
            } else {
                action = .buildAgain
            }
        }
    }
}
