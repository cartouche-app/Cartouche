//
//  MacGames.swift
//  BuilderKit
//
//  The games played on this Mac: started from the builder (Play, or Game
//  settings, nxnative's own window first) or from anywhere else (the
//  Finder, the Dock, Launchpad), followed until they end, and their saves
//  kept in step with the iPhone's copies in the saves folder (MacSaves.swift):
//  the newest copy comes before a game the builder starts, the Mac's saves
//  go a few seconds after the game saves, while it plays, and after every
//  game, and while a game does not run, a round every minute brings a copy
//  that arrived, so that a start from the Dock finds it too. A game whose saves nxnative's own cloud saves sync (a folder
//  the player chose in its settings window) is left to them: never two
//  syncs on one save.
//
//  A game is started through LaunchServices, as the Finder starts it: it
//  keeps its own permissions (Bluetooth, for its controllers) and its own
//  place in the Dock, in the language the Mac's languages choose for it
//  unless the player chose one (MacGameLanguage). Its launcher's process is
//  followed until it ends; how it ended is the last line its launcher
//  wrote in its log (MacPlay.swift). While it runs, its play time counts
//  each time its app is the Mac's active one (MacPlayTime.swift).
//

import AppKit
import CartoucheCore
import Foundation

/// A game playing on this Mac.
public struct MacGameRun: Equatable, Sendable {
    public let app: MacGameApp
    /// The process followed: its launcher's, or another of the app's.
    public let pid: pid_t
    public let started: Date
    /// Started by the builder, else from the Finder, the Dock, Launchpad.
    public let fromBuilder: Bool
    /// Started with nxnative's settings window first.
    public let settings: Bool

    public init(app: MacGameApp, pid: pid_t, started: Date, fromBuilder: Bool, settings: Bool = false) {
        self.app = app
        self.pid = pid
        self.started = started
        self.fromBuilder = fromBuilder
        self.settings = settings
    }
}

/// What happened to the games of this Mac, for the app's words and its
/// measures.
public enum MacGamesNews {
    case started(MacGameRun)
    /// A game ended, after SECONDS, as its launcher said.
    case ended(MacGameRun, ending: MacGameEnding, exit: Int?, seconds: TimeInterval)
    /// A game's saves went or came, or could not: ON_SHARE, the saves
    /// folder is on a share.
    case saves(titleID: String, event: MacSaveEvent, onShare: Bool)
}

public enum MacPlayError: Error, Equatable {
    /// The game has no app on this Mac, or no longer.
    case noApp(String)
}

extension MacPlayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noApp:
            return tr("This game’s app is no longer on this Mac: build it for this Mac again.",
                      "L’app de ce jeu n’est plus sur ce Mac : construisez-le à nouveau pour ce Mac.",
                      "La app de este juego ya no está en este Mac: vuelve a compilarlo para este Mac.",
                      "Die App dieses Spiels ist nicht mehr auf diesem Mac: Erstelle es erneut für diesen Mac.")
        }
    }
}

@MainActor
public final class MacGames: ObservableObject {
    /// How often the saves of the games not playing are kept in step.
    public static let roundInterval: UInt64 = 60

    /// nxnative's folder of the games' logs, <title ID>.log.
    public nonisolated static var nxnativeLogs: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Logs/nxnative", isDirectory: true)
    }

    /// The games playing now, by title ID.
    @Published public private(set) var playing: [String: MacGameRun] = [:]
    /// The games whose saves come before the builder starts them.
    @Published public private(set) var preparing: Set<String> = []
    /// What each game's saves did last, by title ID.
    @Published public private(set) var last: [String: MacSaveEvent] = [:]
    /// When each game's saves were last kept in step, a copy moving or not,
    /// by title ID: since the builder opened.
    @Published public private(set) var checked: [String: Date] = [:]
    /// The folder nxnative's own cloud saves go through, for each game
    /// whose player chose one, by title ID.
    @Published public private(set) var cloud: [String: String] = [:]
    /// The saves folder the Mac's saves are kept in step with, nil when
    /// they are not: a folder of this Mac's or a share mounted here, or the
    /// iPhone's on one of the player's connections.
    @Published public private(set) var folder: (any MacSavesPlace)?

    /// The games' apps on this Mac, by title ID.
    public private(set) var apps: [String: MacGameApp] = [:]
    public var news: ((MacGamesNews) -> Void)?
    /// The language of the prompts the games show: "fr", "es", "de", or
    /// English.
    public var language = "en"
    /// More environment for each start: the tests' own.
    public var environment: [String: String] = [:]
    public let store: MacSaveStore
    public let keeper: MacSaveKeeper
    /// nxnative's folder of the games' own (their saves) and of their logs.
    public let games: URL
    public let logs: URL
    private let scratch: URL
    private let preference: (String, String) -> String?
    private let keep: (String, String?, String) -> Void
    private let sample: Bool
    private var watchers: [pid_t: any DispatchSourceProcess] = [:]
    private var observers: [any NSObjectProtocol] = []
    private var rounds: Task<Void, Never>?
    private var rounding = false
    /// The games playing whose saves go as they change, by title ID
    /// (CartoucheSaveWatch), and the loop that looks at them.
    private var watches: [String: CartoucheSaveWatch] = [:]
    private var looking: Task<Void, Never>?
    /// The games playing whose sync while they play the app heard of, by
    /// title ID: it counts one for each game, but for those that failed.
    private var heardPlaying: Set<String> = []
    /// The play time of each game playing, by title ID.
    private var counters: [String: MacPlayTime] = [:]
    private var ticks: Task<Void, Never>?
    /// The Mac asleep, its screens off or locked, or another user's session
    /// in front: no game is played.
    private var away = false

    /// STORE, the file of what the Mac knows of each game's saves; SCRATCH,
    /// a folder of the builder's for the copies that come. PREFERENCE and
    /// KEEP read and write the games' preferences.
    public init(store: URL, scratch: URL, games: URL = MacSavesFolder.nxnativeFolder, logs: URL = MacGames.nxnativeLogs,
                sample: Bool = false, preference: @escaping (String, String) -> String? = MacGames.preference,
                keep: @escaping (String, String?, String) -> Void = MacGames.keep) {
        self.store = MacSaveStore(url: store)
        keeper = MacSaveKeeper(store: self.store)
        self.scratch = scratch
        self.games = games
        self.logs = logs
        self.sample = sample
        self.preference = preference
        self.keep = keep
    }

    /// A string of another app's preferences: KEY in DOMAIN, as the app
    /// last saved it.
    public nonisolated static func preference(_ key: String, _ domain: String) -> String? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }

    /// Keeps VALUE as KEY in another app's preferences, DOMAIN, at once:
    /// nil removes it. The app reads it at its next start.
    public nonisolated static func keep(_ key: String, _ value: String?, _ domain: String) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFString }, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    // MARK: What the builder tells

    /// The library's games that have an app on this Mac.
    public func use(apps list: [MacGameApp]) {
        var apps: [String: MacGameApp] = [:]
        for app in list { apps[app.titleID] = app }
        self.apps = apps
        var last: [String: MacSaveEvent] = [:]
        for titleID in apps.keys {
            if let event = store.record(titleID).last { last[titleID] = event }
        }
        if last != self.last { self.last = last }
        readCloud()
        noticeRunning()
    }

    /// The saves folder, ROOT, or none: the saves stay as they are.
    public func use(saves root: URL?) {
        use(place: root.map { MacSavesFolder(root: $0, games: games, scratch: scratch) })
    }

    /// The iPhone's saves folder on one of the player's connections, as
    /// DRIVER reaches it, the console's (MacConnectionSaves).
    public func use(connection driver: any MacConnectionSavesDriver) {
        use(place: MacConnectionSaves(driver: driver, games: games, scratch: scratch))
    }

    /// The saves folder PLACE, or none: the one in use stays when it is
    /// the same folder.
    public func use(place: (any MacSavesPlace)?) {
        guard let place else {
            if folder != nil { folder = nil }
            return
        }
        guard folder?.place != place.place else { return }
        folder = place
    }

    /// Whether the builder keeps TITLE_ID's saves in step: a saves folder
    /// is chosen, and nxnative's own cloud saves do not sync them.
    public func keepsSaves(_ titleID: String) -> Bool {
        folder != nil && cloud[titleID.uppercased()] == nil
    }

    public func isPlaying(_ titleID: String) -> Bool {
        playing[titleID.uppercased()] != nil
    }

    // MARK: Following the games

    /// Follows the games started from anywhere, and keeps the saves of
    /// those that do not run in step, now and every minute; counts the
    /// play time of those playing.
    public func start() {
        guard !sample, observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.noticeRunning() }
        })
        // The app in front changed, or the Mac went away or came back.
        let front: [(NotificationCenter, Notification.Name, Bool?)] = [
            (center, NSWorkspace.didActivateApplicationNotification, nil),
            (center, NSWorkspace.didDeactivateApplicationNotification, nil),
            (center, NSWorkspace.willSleepNotification, true),
            (center, NSWorkspace.screensDidSleepNotification, true),
            (center, NSWorkspace.sessionDidResignActiveNotification, true),
            (center, NSWorkspace.didWakeNotification, false),
            (center, NSWorkspace.screensDidWakeNotification, false),
            (center, NSWorkspace.sessionDidBecomeActiveNotification, false),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), true),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"), false),
            // The builder quits: the time so far is written.
            (NotificationCenter.default, NSApplication.willTerminateNotification, true),
        ]
        for (place, name, away) in front {
            observers.append(place.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if let away { self?.away = away }
                    self?.noticeFront()
                }
            })
        }
        noticeRunning()
        rounds = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                await self?.round()
                try? await Task.sleep(nanoseconds: MacGames.roundInterval * 1_000_000_000)
            }
        }
        ticks = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                try? await Task.sleep(nanoseconds: UInt64(MacPlayTime.interval * 1_000_000_000))
                self?.tickPlayTime()
            }
        }
        looking = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                try? await Task.sleep(nanoseconds: UInt64(CartoucheSaveWatch.interval * 1_000_000_000))
                await self?.lookAtPlaying()
            }
        }
    }

    public func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        rounds?.cancel()
        rounds = nil
        ticks?.cancel()
        ticks = nil
        looking?.cancel()
        looking = nil
        watchers.values.forEach { $0.cancel() }
        watchers = [:]
        counters.values.forEach { $0.leftFront() }
        counters = [:]
    }

    // MARK: Play time

    /// Whether RUN's game is the Mac's active app: its launcher, its host,
    /// or another program of its app.
    private func isInFront(_ run: MacGameRun) -> Bool {
        guard !away, let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.processIdentifier == run.pid { return true }
        let app = Self.realPath(run.app.url)
        if front.bundleURL.map(Self.realPath) == app { return true }
        return front.executableURL.map(Self.realPath)?.hasPrefix(app + "/Contents/MacOS/") ?? false
    }

    /// The app in front changed: the games playing count, or stop counting.
    private func noticeFront() {
        for (titleID, counter) in counters {
            guard let run = playing[titleID] else { continue }
            if isInFront(run) {
                counter.cameToFront()
            } else {
                counter.leftFront()
            }
        }
    }

    /// Every 30 seconds, each game playing writes its time so far.
    private func tickPlayTime() {
        for (titleID, counter) in counters {
            guard let run = playing[titleID] else { continue }
            counter.tick(inFront: isInFront(run))
        }
    }

    /// A program running: its process, and its path as the kernel names it.
    typealias Program = (pid: pid_t, path: String)

    /// The processes of APP running now, by process number: those
    /// LaunchServices started from it, and those whose program is in it,
    /// its launcher and the game's host, which nxnative's launcher starts
    /// without LaunchServices. PROGRAMS: the programs running, listed once
    /// for every game of a round.
    private func pids(of app: MacGameApp, programs: [Program]? = nil) -> [pid_t] {
        let path = Self.realPath(app.url)
        let name = app.url.lastPathComponent
        var found = Set(NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL?.lastPathComponent == name && $0.bundleURL.map(Self.realPath) == path
        }.map(\.processIdentifier))
        found.formUnion(Self.pids(inside: app, programs: programs ?? Self.runningPrograms()))
        // LaunchServices may not know yet that one ended.
        return found.filter { $0 > 0 && Self.alive($0) }.sorted()
    }

    /// Whether process PID runs; never for -1, which kill() takes for every
    /// process the builder may signal, nor 0, its own group.
    nonisolated static func alive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// The path of URL as the kernel names a program's: its links
    /// resolved, /private/var and not /var.
    nonisolated static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The programs running now.
    nonisolated static func runningPrograms() -> [Program] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let listed = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard listed > 0 else { return [] }
        var path = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var programs: [Program] = []
        for pid in pids.prefix(Int(listed)) where pid > 0 {
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { continue }
            programs.append((pid, String(decoding: path.prefix(Int(length)), as: UTF8.self)))
        }
        return programs
    }

    /// The processes whose program is in APP, among PROGRAMS: its
    /// launcher's and its host's, however they were started.
    nonisolated static func pids(inside app: MacGameApp, programs: [Program]) -> [pid_t] {
        let folder = realPath(app.url) + "/Contents/MacOS/"
        return programs.filter { $0.path.hasPrefix(folder) }.map(\.pid)
    }

    /// Follows the games started from elsewhere: those running that the
    /// builder does not follow yet, but for one it is starting.
    private func noticeRunning() {
        guard !sample else { return }
        let waiting = apps.values.filter { playing[$0.titleID] == nil && !preparing.contains($0.titleID) }
        guard !waiting.isEmpty else { return }
        let programs = Self.runningPrograms()
        for app in waiting {
            followRunning(app, programs: programs)
        }
    }

    /// Follows APP's game when it runs already, started from elsewhere: the
    /// run followed, nil when it does not run.
    @discardableResult
    private func followRunning(_ app: MacGameApp, programs: [Program]? = nil) -> MacGameRun? {
        guard let pid = pids(of: app, programs: programs).first else { return nil }
        let started = NSRunningApplication(processIdentifier: pid)?.launchDate ?? Date()
        let run = MacGameRun(app: app, pid: pid, started: started, fromBuilder: false)
        follow(run)
        return run
    }

    private func follow(_ run: MacGameRun) {
        playing[run.app.titleID] = run
        if watches[run.app.titleID] == nil {
            // How its saves look when they are in step with the saves folder.
            let base = store.record(run.app.titleID).base
            watches[run.app.titleID] = CartoucheSaveWatch(inStep: base?.place == folder?.place ? base?.look : nil)
            heardPlaying.remove(run.app.titleID)
        }
        if !sample, counters[run.app.titleID] == nil {
            counters[run.app.titleID] = MacPlayTime(folder: games.appendingPathComponent(run.app.titleID, isDirectory: true))
        }
        news?(.started(run))
        watch(run)
        noticeFront()
    }

    /// Follows RUN's process until it ends. A game that ended as soon as it
    /// started has none to follow: LaunchServices says -1 of it.
    private func watch(_ run: MacGameRun) {
        let pid = run.pid
        guard pid > 0 else {
            ended(run)
            return
        }
        watchers.removeValue(forKey: pid)?.cancel()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.exited(pid) }
        }
        watchers[pid] = source
        source.resume()
        // Gone before the watch began: nothing would say so.
        if !Self.alive(pid) {
            exited(pid)
        }
    }

    /// The process PID ended.
    private func exited(_ pid: pid_t) {
        watchers.removeValue(forKey: pid)?.cancel()
        guard let run = playing.values.first(where: { $0.pid == pid }) else { return }
        ended(run)
    }

    /// RUN's process ended: the game ended, unless another process of its
    /// app still runs.
    private func ended(_ run: MacGameRun) {
        let titleID = run.app.titleID
        if let other = pids(of: run.app).first(where: { $0 != run.pid }) {
            let next = MacGameRun(app: run.app, pid: other, started: run.started, fromBuilder: run.fromBuilder, settings: run.settings)
            playing[titleID] = next
            watch(next)
            return
        }
        playing.removeValue(forKey: titleID)
        watches.removeValue(forKey: titleID)
        counters.removeValue(forKey: titleID)?.leftFront()
        let (ending, code) = MacGameEnding.read(log: logs.appendingPathComponent(titleID + ".log"), since: run.started)
        news?(.ended(run, ending: ending, exit: code, seconds: Date().timeIntervalSince(run.started)))
        // The saves it made go.
        if let folder, keepsSaves(titleID) {
            Task { await self.sync(run.app, in: folder, when: .after) }
        }
    }

    // MARK: Playing

    /// Starts TITLE_ID's game: its newest copy of saves first, when the
    /// builder keeps them; with nxnative's settings window first
    /// (SETTINGS), else straight into the game. A game playing already
    /// comes to the front.
    @discardableResult
    public func play(_ titleID: String, settings: Bool = false) async throws -> MacGameRun? {
        let titleID = titleID.uppercased()
        guard let app = apps[titleID] else { throw MacPlayError.noApp(titleID) }
        if let run = playing[titleID] {
            if let process = NSRunningApplication(processIdentifier: run.pid) {
                _ = process.activate(options: [])
            }
            return run
        }
        guard !sample, !preparing.contains(titleID) else { return nil }
        guard FileManager.default.fileExists(atPath: app.url.appendingPathComponent("Contents/Info.plist").path) else {
            throw MacPlayError.noApp(titleID)
        }
        // Started from the Dock a moment ago, not followed yet: that one plays.
        if let run = followRunning(app) { return run }
        preparing.insert(titleID)
        defer { preparing.remove(titleID) }
        readCloud()
        let keeps = keepsSaves(titleID)
        if let folder, keeps {
            await sync(app, in: folder, when: .before)
        }
        // Started meanwhile, from the Dock: that one plays.
        if let run = followRunning(app) { return run }
        // In the Mac's language, unless the player chose one.
        let documents = games.appendingPathComponent(titleID, isDirectory: true)
        MacGameLanguage.prepare(app, documents: documents, environment: self.environment, preferred: Locale.preferredLanguages,
                                read: preference, write: keep)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = MacPlayEnvironment.arguments(settings: settings)
        let own = games.standardizedFileURL.path == MacSavesFolder.nxnativeFolder.standardizedFileURL.path
        var environment = MacPlayEnvironment.make(app: app, keepsSaves: keeps, language: language,
                                                  fullscreen: MacPlayEnvironment.fullscreen(settings: settings, of: app, preference: preference),
                                                  documents: own ? nil : games.appendingPathComponent(titleID, isDirectory: true))
        environment.merge(self.environment) { _, extra in extra }
        configuration.environment = environment
        configuration.activates = true
        configuration.addsToRecentItems = false
        let started = Date()
        let pid: pid_t
        do {
            pid = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration).processIdentifier
        } catch {
            // Started all the same, its launcher not saying to LaunchServices
            // that it finished launching: it plays.
            guard let running = pids(of: app).first else { throw error }
            pid = running
        }
        let run = MacGameRun(app: app, pid: pid, started: started, fromBuilder: true, settings: settings)
        follow(run)
        return run
    }

    /// Asks TITLE_ID's game to quit, as Cartouche's console does once the
    /// player said so: its app as macOS asks an app to quit, then, should
    /// it still run GRACE seconds later, its processes, the game's host
    /// first, so that its launcher can say how it ended.
    public func quit(_ titleID: String, grace: TimeInterval = 5) {
        guard !sample, let run = playing[titleID.uppercased()] else { return }
        for pid in pids(of: run.app) {
            _ = NSRunningApplication(processIdentifier: pid)?.terminate()
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(grace, 0) * 1_000_000_000))
            guard let self, let still = self.playing[run.app.titleID] else { return }
            let pids = self.pids(of: still.app)
            let launchers = Set(pids.filter { NSRunningApplication(processIdentifier: $0) != nil })
            for pid in pids where !launchers.contains(pid) {
                kill(pid, SIGTERM)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for pid in self.pids(of: still.app) {
                kill(pid, SIGTERM)
            }
        }
    }

    // MARK: Saves

    /// Keeps the saves of the games not playing in step: a copy that
    /// arrived comes, saves made while the builder was closed go.
    public func round() async {
        guard !sample, !rounding else { return }
        // A game whose end nothing said, if any; one started from elsewhere.
        for run in Array(playing.values) where !Self.alive(run.pid) {
            exited(run.pid)
        }
        readCloud()
        noticeRunning()
        guard let folder else { return }
        rounding = true
        defer { rounding = false }
        let programs = Self.runningPrograms()
        for app in apps.values.sorted(by: { $0.titleID < $1.titleID }) where keepsSaves(app.titleID) {
            // Never under a game playing, or starting.
            guard playing[app.titleID] == nil, !preparing.contains(app.titleID), pids(of: app, programs: programs).isEmpty else { continue }
            await sync(app, in: folder, when: .round)
        }
    }

    @discardableResult
    private func sync(_ app: MacGameApp, in folder: any MacSavesPlace, when: MacSaveMoment) async -> MacSaveEvent? {
        // A copy takes the place of the saves only while no program of the
        // game runs, looked at again just before: one started from the Dock
        // meanwhile keeps the saves it found.
        let event = await keeper.sync(app.saveGame, in: folder, when: when, quiet: Self.quiet(app))
        await noteChecked(app)
        guard let event else { return nil }
        last[app.titleID] = event
        news?(.saves(titleID: app.titleID, event: event, onShare: folder.onShare))
        return event
    }

    /// Looks at the saves of the games playing: those a game made go to the
    /// saves folder once they have stayed as they are for a few seconds
    /// (CartoucheSaveWatch), from a copy of them made at one moment, in
    /// their turn with the other syncs (MacSaveKeeper.sendPlaying).
    public func lookAtPlaying() async {
        guard !sample, let folder else { return }
        for titleID in watches.keys.sorted() {
            guard let run = playing[titleID], keepsSaves(titleID) else { continue }
            let documents = games.appendingPathComponent(titleID, isDirectory: true)
            let look = await Task.detached(priority: .utility) { CartoucheSaveSync.saves(in: documents)?.look }.value
            guard watches[titleID]?.due(look) == true else { continue }
            let played = await keeper.sendPlaying(run.app.saveGame, from: documents, in: folder, scratch: scratch)
            if let look = played.inStep {
                watches[titleID]?.sent(look)
            } else if played.moved {
                watches[titleID]?.moved()
            } else if played.failed {
                watches[titleID]?.failed()
            }
            await noteChecked(run.app)
            guard let event = played.event else { continue }
            last[titleID] = event
            if event.offline || event.failed || heardPlaying.insert(titleID).inserted {
                news?(.saves(titleID: titleID, event: event, onShare: folder.onShare))
            }
        }
    }

    /// Whether no program of APP runs, looked at again each time it is asked.
    private nonisolated static func quiet(_ app: MacGameApp) -> @Sendable () -> Bool {
        { MacGames.pids(inside: app, programs: MacGames.runningPrograms()).isEmpty }
    }

    /// When APP's saves were last kept in step, as the keeper says.
    private func noteChecked(_ app: MacGameApp) async {
        guard let date = await keeper.lastChecked(app.titleID), checked[app.titleID] != date else { return }
        checked[app.titleID] = date
    }

    // MARK: What Cartouche's console asks

    /// Whether TITLE_ID's game plays, starts, or runs a program of its app:
    /// its saves stay as they are meanwhile.
    public func isBusy(_ titleID: String) -> Bool {
        let titleID = titleID.uppercased()
        guard let app = apps[titleID] else { return false }
        return playing[titleID] != nil || preparing.contains(titleID) || !pids(of: app).isEmpty
    }

    /// Keeps TITLE_ID's saves in step now, as the player asked from its
    /// sheet in Cartouche's console: the newest copy comes when it is the
    /// one to keep, the saves of this Mac go when they changed. What moved,
    /// nil when nothing did, or the event that says why nothing could, the
    /// saves folder away (offline) or failing (failed). It throws busy while
    /// the game plays or starts, offline when the builder keeps no saves of
    /// the game's.
    public func syncNow(_ titleID: String) async throws -> MacSaveEvent? {
        let titleID = titleID.uppercased()
        guard let app = apps[titleID], let folder, keepsSaves(titleID) else { throw MacSavesError.offline }
        guard !sample else { return nil }
        guard !isBusy(titleID) else { throw MacSavesError.busy }
        let asked = Date()
        let event = await sync(app, in: folder, when: .round)
        if let date = checked[titleID], date >= asked { return event }
        // Nothing went through: the folder away or failing as it was before,
        // which the last event says, or the game started meanwhile.
        if let last = last[titleID], last.offline || last.failed { return last }
        throw MacSavesError.busy
    }

    /// TITLE_ID's copies in the saves folder, the newest first, read off the
    /// main thread: none when the builder keeps no saves of the game's. It
    /// throws offline when the saves folder is not there, a share not
    /// mounted or a server that does not answer.
    public func copies(_ titleID: String) async throws -> [MacSaveCopyInfo] {
        let titleID = titleID.uppercased()
        guard let app = apps[titleID], let folder, keepsSaves(titleID) else { return [] }
        let game = app.saveGame
        return try await Task.detached(priority: .userInitiated) {
            try await folder.listCopies(of: game)
        }.value
    }

    /// Puts the copy NAME back as TITLE_ID's saves on this Mac, as the
    /// player chose it on its sheet in Cartouche's console: this Mac's saves
    /// go to the saves folder first, and the copy put back becomes the
    /// newest one there (MacSavesFolder.putBack). It throws busy while the
    /// game plays or starts, offline when the saves folder is not there,
    /// unreadable for a copy that does not read whole.
    public func putBack(_ name: String, of titleID: String) async throws {
        let titleID = titleID.uppercased()
        guard let app = apps[titleID], let folder, keepsSaves(titleID) else { throw MacSavesError.offline }
        guard !sample else { return }
        guard !isBusy(titleID) else { throw MacSavesError.busy }
        preparing.insert(titleID)
        defer { preparing.remove(titleID) }
        let event = try await keeper.putBack(name, of: app.saveGame, in: folder, quiet: Self.quiet(app))
        await noteChecked(app)
        last[titleID] = event
        news?(.saves(titleID: titleID, event: event, onShare: folder.onShare))
    }

    /// Runs CHANGE on TITLE_ID's saves on this Mac, in DOCUMENTS, nxnative's
    /// folder of the game's own, as the player asked from its sheet in
    /// Cartouche's console (a save from their Switch put in place, or the
    /// one it replaced put back), once the syncs under way ended, none
    /// starting meanwhile; then the saves go to the saves folder, when the
    /// builder keeps them. It throws busy while the game plays or starts.
    public func change<T: Sendable>(_ titleID: String, _ change: @escaping @Sendable (_ documents: URL) throws -> T) async throws -> T {
        let titleID = titleID.uppercased()
        guard !isBusy(titleID) else { throw MacSavesError.busy }
        let documents = games.appendingPathComponent(titleID, isDirectory: true)
        let quiet = apps[titleID].map(Self.quiet) ?? { true }
        preparing.insert(titleID)
        let result: T
        do {
            result = try await keeper.change {
                // A game started from the Dock while a sync ended keeps the
                // saves it found, as under a sync.
                guard quiet() else { throw MacSavesError.busy }
                return try change(documents)
            }
        } catch {
            preparing.remove(titleID)
            throw error
        }
        preparing.remove(titleID)
        if let app = apps[titleID], let folder, keepsSaves(titleID), !sample {
            Task { await self.sync(app, in: folder, when: .after) }
        }
        return result
    }

    /// The folders nxnative's own cloud saves go through, read again.
    private func readCloud() {
        var cloud: [String: String] = [:]
        for app in apps.values {
            if let found = MacCloudSaves.folder(of: app, documents: games.appendingPathComponent(app.titleID, isDirectory: true),
                                                preference: preference) {
                cloud[app.titleID] = found
            }
        }
        if cloud != self.cloud { self.cloud = cloud }
    }

    // MARK: The gallery

    /// Games playing, and what their saves did last, for the gallery's
    /// pictures.
    public func preview(folder root: URL?, playing: [MacGameRun] = [], last: [String: MacSaveEvent] = [:], cloud: [String: String] = [:]) {
        guard sample else { return }
        folder = root.map { MacSavesFolder(root: $0, games: games, scratch: scratch) }
        self.playing = Dictionary(uniqueKeysWithValues: playing.map { ($0.app.titleID, $0) })
        self.last = last
        self.cloud = cloud
    }

    /// The gallery's apps, without a look at the disk.
    public func preview(apps list: [MacGameApp]) {
        guard sample else { return }
        apps = Dictionary(uniqueKeysWithValues: list.map { ($0.titleID, $0) })
    }
}
