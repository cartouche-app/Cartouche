//
//  CartoucheSaveBackups.swift
//  Cartouche
//
//  The games' saves kept in step with the player's saves folder, where each
//  game has a folder of its copies, the way nxnative keeps a game's save in
//  step with a cloud folder (CartoucheSaveSync, CartoucheStorageSaves):
//
//  - When a game is installed, and before it starts, the newest copy comes,
//    when the game has no saves on this iPhone, as after Cartouche was
//    installed again, or when the copy is newer than theirs, as when
//    another iPhone played the game since. A server offline from here is
//    left alone: the game plays with the saves it has.
//  - While a game plays behind the console, Cartouche beside it, the saves
//    it makes go a few seconds after it made them (CartoucheSaveWatch),
//    from a copy of them made at one moment, never half written
//    (CartoucheSaveSync.snapshot); each copy that goes then takes the place
//    of the one before, so that each game leaves one copy. Cartouche
//    leaving the screen sends at once what waits.
//  - After a game, the saves that changed go: when a game behind the
//    console ends and, since a game in Cartouche's place is Cartouche
//    itself while it plays, when Cartouche opens again after a game and
//    whenever it comes back to the front, but for the game that runs. Play
//    waits for the syncs under way.
//  - When both changed, the saves written last win, and the others are kept
//    as a copy of their own date: the game's sheet says what came and what
//    was kept. The ten newest copies stay.
//  - A copy can be put back from the game's sheet: the saves it replaces go
//    to the saves folder first, and the copy put back becomes the newest
//    one there, which the player's other iPhones take at their next start.
//  - A copy a newer version of the game wrote, on a Mac or an iPhone that
//    has the game's update, never comes to an older one: the saves here go
//    as a copy under it, and the game's sheet says the copy waits for the
//    game's update (CartoucheSaveSync.heldBack).
//
//  Away from the saves folder's server, as from a NAS at home, the saves
//  wait: Cartouche finds the server offline within a few seconds
//  (CartoucheStorageReach), leaves it alone while it stays so, and sends the
//  saves waiting as soon as it answers again. Being offline is not a
//  problem: no report is made of it.
//

import Combine
import Foundation
import UIKit

/// What a sync did to a game's saves that the player should know.
struct CartoucheSaveNews: Codable, Hashable {
    /// The date of the copy that came here.
    var fetched: Date?
    /// The date of the copy the saves here were kept as, under a newer one.
    var kept: Date?
}

@MainActor
final class CartoucheSaveBackups: ObservableObject {
    static let shared = CartoucheSaveBackups()
    /// The copies kept for each game.
    nonisolated static let kept = CartoucheSaveSync.kept

    /// Whether the saves are being synced.
    @Published private(set) var isSyncing = false
    /// When each game's saves were last synced, by target key.
    @Published private(set) var lastSync: [String: Date]
    /// What the last syncs did that the player should know, by target key.
    @Published private(set) var news: [String: CartoucheSaveNews]
    /// Why the last sync failed, if it did, and the report on it.
    @Published private(set) var problemReport: CartoucheReport?
    /// The games whose saves wait for the saves folder's server, offline
    /// from here, by target key: they go once it answers again.
    @Published private(set) var waiting: Set<String> = []
    /// The games whose newest copy a newer version of the game wrote, which
    /// waits for the game's update, by target key.
    @Published private(set) var newer: [String: CartoucheSaveNewer]

    private let settings: CartoucheStorageSettings
    private let defaults: UserDefaults
    /// What was last the same here and in the saves folder, for each game
    /// (CartoucheSaveSync), by target key.
    private var bases: [String: CartoucheSaveBase]
    private var run: Task<Void, Never>?
    private var background = UIBackgroundTaskIdentifier.invalid
    /// The games playing behind the console whose saves go as they change,
    /// by target key: each one's target, watch, and the loop that looks at
    /// its saves.
    private var playingGames: [String: CartoucheSaveTarget] = [:]
    private var watches: [String: CartoucheSaveWatch] = [:]
    private var looking: [String: Task<Void, Never>] = [:]
    /// The copy each game's saves went to while it played, by target key,
    /// which the next one takes the place of, until the one after the game.
    private var playCopies: [String: String] = [:]
    /// The games whose sync while they played failed already, by target
    /// key: the next failures make no report of their own.
    private var playFailed: Set<String> = []
    /// How often each game's saves went while it played, and how often
    /// they failed to, by target key, which the telemetry hears of at the
    /// game's end (CartoucheSavesSynced).
    private var playTold: [String: (sent: Int, failed: Int)] = [:]
    /// The syncs after the games that ended, which a start waits for.
    private var ending: [String: Task<Void, Never>] = [:]
    private static let basesKey = "Cartouche.saves.bases"
    private static let syncedKey = "Cartouche.saves.synced"
    private static let newsKey = "Cartouche.saves.news"
    private static let newerKey = "Cartouche.saves.newer"
    /// What Cartouche kept before it synced the saves: how each game's saves
    /// looked at their last copy, "<server ID>|<path>|<look>", and the date
    /// that named the copy.
    private static let fingerprintsKey = "Cartouche.saves.fingerprints"
    private static let lastKey = "Cartouche.saves.last"

    init(settings: CartoucheStorageSettings = .shared, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        let decoder = JSONDecoder()
        bases = defaults.data(forKey: Self.basesKey).flatMap { try? decoder.decode([String: CartoucheSaveBase].self, from: $0) } ?? [:]
        news = defaults.data(forKey: Self.newsKey).flatMap { try? decoder.decode([String: CartoucheSaveNews].self, from: $0) } ?? [:]
        newer = defaults.data(forKey: Self.newerKey).flatMap { try? decoder.decode([String: CartoucheSaveNewer].self, from: $0) } ?? [:]
        let synced = (defaults.dictionary(forKey: Self.syncedKey) as? [String: Date]) ?? [:]
        let copied = (defaults.dictionary(forKey: Self.lastKey) as? [String: Date]) ?? [:]
        lastSync = synced.merging(copied) { synced, _ in synced }
    }

    /// Whether the player chose a saves folder.
    var isOn: Bool { settings.location(.saves) != nil }

    /// Why the last sync failed, and the report on it, as TARGET's sheet
    /// shows it: on the iPhone, whose syncs go in rounds, the last round's
    /// for every game; on the Mac, each game's own (Mac/ConsoleSaves.swift).
    func problem(of target: CartoucheSaveTarget) -> CartoucheReport? {
        problemReport
    }

    /// After a game: sends the saves of the TARGETS that changed since they
    /// were last in step with the saves folder, unless syncs are under way.
    /// What the folder has new for the others comes at their next start.
    func copyChanged(_ targets: [CartoucheSaveTarget]) {
        guard run == nil, isOn, !targets.isEmpty else { return }
        run = Task {
            _ = await syncRound(targets, fetching: false, onlyChanged: true, byPlayer: false, telling: .after)
            run = nil
        }
    }

    /// Syncs TARGET's saves with the saves folder, the newest copy coming
    /// here when it is the one to keep: when the game is installed and
    /// before it starts. A server known to be offline from here is left
    /// alone. What the sync did, unless it did not go through.
    @discardableResult
    func sync(_ target: CartoucheSaveTarget) async -> CartoucheSaveOutcome? {
        await turn {
            await self.syncRound([target], fetching: true, onlyChanged: false, byPlayer: false, telling: .before).outcomes[target.key]
        }
    }

    /// Syncs TARGET's saves now, as the player asked: whether it went
    /// through.
    func syncNow(_ target: CartoucheSaveTarget) async -> Bool {
        await turn { await self.syncRound([target], fetching: true, onlyChanged: false, byPlayer: true, telling: .player).failure == nil }
    }

    #if CARTOUCHE_GALLERY
    /// COUNT games whose saves wait for the server, for the launcher's
    /// gallery (launcher/Gallery).
    func showWaitingForGallery(_ count: Int) {
        waiting = Set((0 ..< count).map { "gallery-\($0)" })
    }

    /// The newest copy of the saves of the game of KEY waiting for its
    /// update, for the launcher's gallery.
    func showNewerForGallery(_ key: String, _ held: CartoucheSaveNewer) {
        newer[key] = held
    }
    #endif

    /// Whether TARGET's saves are in the saves folder as they are here, as
    /// far as Cartouche knows: before a reset of Cartouche, which erases
    /// them here (CartoucheReset). A game without saves has nothing to
    /// lose.
    func isInStep(_ target: CartoucheSaveTarget) async -> Bool {
        guard let look = await Self.look(of: target.documents) else { return true }
        guard let location = settings.location(.saves) else { return false }
        return savedBase(of: target, place: Self.place(location))?.look == look
    }

    /// Waits for the syncs under way: before a game starts, which closes
    /// Cartouche.
    func finish() async {
        for task in Array(ending.values) {
            await task.value
        }
        while let run {
            await run.value
            if self.run == run { break }
        }
    }

    /// Runs WORK once the syncs under way have ended, as the one under way:
    /// one round at a time, as each signs in to the server and may write a
    /// game's folder.
    private func turn<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        // The one under way, then any that began while it ended.
        while let current = run {
            await current.value
            if run == current { run = nil }
        }
        let task = Task { @MainActor in await work() }
        let marker = Task { @MainActor in _ = await task.value }
        run = marker
        let value = await task.value
        if run == marker { run = nil }
        return value
    }

    // MARK: Syncing

    /// What a round of syncs did, game by game, and why it stopped, if it
    /// did.
    private struct Round {
        var outcomes: [String: CartoucheSaveOutcome] = [:]
        var failure: Error?
        /// How the saves of each game looked, in its Documents, when the
        /// round found them in step or sent them, by target key.
        var inStep: [String: String] = [:]
        /// The games whose saves kept changing while they were copied, to
        /// go once they stop (PLAYING).
        var moved: Set<String> = []
    }

    /// Syncs the TARGETS with the saves folder, one game after another: all
    /// of them, or, ONLYCHANGED, after a game, those whose saves changed
    /// since they were last in step. FETCHING lets the newest copy come
    /// here. BYPLAYER: the player asked, and a server found offline is tried
    /// again. PLAYING: the games play, and their saves go from a copy of
    /// them made at one moment, never while a server is known to be offline;
    /// REPORTING: a failure makes a report. TELLING: when the round happens,
    /// for the telemetry, which hears of what it did game by game; PLAYED,
    /// at the end of a game that played behind the console, how often its
    /// saves went while it did.
    private func syncRound(_ targets: [CartoucheSaveTarget], fetching: Bool, onlyChanged: Bool, byPlayer: Bool,
                           playing: Bool = false, reporting: Bool = true, telling moment: CartoucheSavesSynced.Moment? = nil,
                           played: (sent: Int, failed: Int)? = nil) async -> Round {
        var result = Round()
        guard let location = settings.location(.saves) else {
            result.failure = CartoucheStorageError(.noSavesFolder, CartoucheText.savesNoFolder)
            return result
        }
        let place = Self.place(location)
        var due: [(target: CartoucheSaveTarget, base: CartoucheSaveBase?)] = []
        for target in targets {
            let base = savedBase(of: target, place: place)
            if onlyChanged {
                // A game that never saved, or whose saves did not change
                // since they were last in step, has nothing to send.
                guard let look = await Self.look(of: target.documents), look != base?.look else {
                    waiting.remove(target.key)
                    if let look = base?.look { result.inStep[target.key] = look }
                    continue
                }
            }
            due.append((target, base))
        }
        defer {
            if let moment { tell(result, of: played == nil ? due.map { $0.target } : targets, at: moment, played: played) }
        }
        guard !due.isEmpty else { return result }
        // The server was found offline from here: the saves to send wait for
        // it, rather than for the patience each time Cartouche comes back,
        // and a game starts with the saves it has.
        let reach = CartoucheStorageReach.shared
        let offline = onlyChanged && !playing ? reach.isSettledOffline(location.server.id) : reach.isOffline(location.server.id)
        if !byPlayer && offline {
            if onlyChanged { wait(for: due.map { $0.target }) }
            result.failure = CartoucheStorageOffline(location.server)
            return result
        }

        isSyncing = true
        beginBackground()
        defer {
            isSyncing = false
            endBackground()
        }
        var remote: CartoucheRemote?
        do {
            let connected = try await CartoucheStorage.connect(location.server, settings: settings)
            remote = connected
            if await settings.checkAccess(connected, server: location.server.id, path: location.path) == false {
                throw CartoucheStorageError(.readOnly, CartoucheText.savesReadOnly)
            }
            let folder = CartoucheSavesFolder(remote: connected, path: location.path, place: place, scratch: Self.scratch)
            // One game that fails leaves the others to go.
            var failed: Error?
            for (target, base) in due {
                do {
                    var source = target
                    var snapshot: CartoucheSavesSnapshot?
                    if playing {
                        // The saves as they are now, whole: the game may save
                        // again while they go.
                        let copy = Self.scratch.appendingPathComponent("playing", isDirectory: true)
                            .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        let documents = target.documents
                        snapshot = try await Task.detached(priority: .utility) {
                            try CartoucheSaveSync.snapshot(ofSavesIn: documents, into: copy)
                        }.value
                        guard let snapshot else {
                            result.moved.insert(target.key)
                            continue
                        }
                        source = CartoucheSaveTarget(key: target.key, name: target.name, titleId: target.titleId,
                                                     documents: snapshot.documents, gameVersion: target.gameVersion)
                    }
                    defer {
                        if let snapshot { try? FileManager.default.removeItem(at: snapshot.documents) }
                    }
                    var outcome = try await folder.sync(source, base: snapshot.map { $0.forCopy(base) } ?? base,
                                                        fetching: fetching, replacing: playCopies[target.key])
                    if let snapshot { outcome.base = snapshot.forGame(outcome.base) }
                    record(outcome, of: target)
                    result.outcomes[target.key] = outcome
                    if playing, outcome.sent != nil, playingGames[target.key] != nil {
                        playTold[target.key, default: (0, 0)].sent += 1
                    }
                    if let look = snapshot?.look ?? outcome.base?.look { result.inStep[target.key] = look }
                    // The next copy of the same game takes this one's place.
                    if let sent = outcome.sent, playingGames[target.key] != nil || ending[target.key] != nil {
                        playCopies[target.key] = sent
                    }
                } catch let offline as CartoucheStorageOffline {
                    throw offline
                } catch {
                    NSLog("[Cartouche] saves of %@ not synced: %@", target.name, error.localizedDescription)
                    failed = failed ?? error
                }
            }
            if let failed { throw failed }
            problemReport = nil
        } catch let offline as CartoucheStorageOffline {
            // No problem: the saves wait for the server to answer again.
            if onlyChanged { wait(for: due.map { $0.target }.filter { result.outcomes[$0.key] == nil }) }
            result.failure = offline
        } catch {
            // The syncs Cartouche makes by itself, each time it comes back,
            // can fail on the way too: their report is not kept.
            if reporting || problemReport == nil {
                problemReport = CartoucheReports.make(.saves, CartoucheText.savesCopyFailed, message: error.localizedDescription,
                                                      error: error, step: "Syncing the saves with " + CartoucheReports.place(.saves),
                                                      stage: "savesSync",
                                                      facts: [.init("Games", String(due.count))]
                                                          + (playing ? [.init("While the game plays", "yes", own: true)] : []),
                                                      inBackground: !byPlayer)
            }
            NSLog("[Cartouche] saves not synced: %@", error.localizedDescription)
            result.failure = error
        }
        note(result.outcomes, of: due.map { $0.target })
        await remote?.disconnect()
        return result
    }

    /// Tells the telemetry what RESULT, a round at MOMENT, did with the
    /// saves of each of the TARGETS (saves.synced): those that moved, that
    /// a newer version of the game holds back, that wait for an offline
    /// server or that failed; nothing of a sync that moved nothing. At the
    /// end of a game that played behind the console, how often its saves
    /// went while it did (PLAYED), whatever the round did.
    private func tell(_ result: Round, of targets: [CartoucheSaveTarget], at moment: CartoucheSavesSynced.Moment,
                      played: (sent: Int, failed: Int)?) {
        // The telemetry, as the console, needs iOS 17.
        guard #available(iOS 17.0, *) else { return }
        for target in targets {
            var step: String?
            if let outcome = result.outcomes[target.key] {
                step = CartoucheSavesSynced.step(outcome.step.rawValue,
                                                 moved: outcome.sent != nil || outcome.fetched != nil || outcome.kept != nil,
                                                 heldBack: outcome.newer != nil)
            } else if result.failure is CartoucheStorageOffline {
                step = "offline"
            } else if result.failure != nil {
                step = "failed"
            }
            if let played {
                CartoucheTelemetry.shared.event("saves.synced", game: target.titleId,
                                                fields: CartoucheSavesSynced.fields(step: step ?? "same", when: moment,
                                                                                    during: played.sent, duringFailed: played.failed))
            } else if let step {
                CartoucheTelemetry.shared.event("saves.synced", game: target.titleId,
                                                fields: CartoucheSavesSynced.fields(step: step, when: moment))
            }
        }
    }

    /// The base of TARGET's saves for the saves folder at PLACE: the one
    /// Cartouche keeps, or, for saves an older Cartouche copied, the copy it
    /// made last, by its date, and how the saves looked then. None for
    /// another folder than the one the base was for: the saves go to the
    /// new one.
    private func savedBase(of target: CartoucheSaveTarget, place: String) -> CartoucheSaveBase? {
        if let base = bases[target.key] { return base.place == place ? base : nil }
        let fingerprints = (defaults.dictionary(forKey: Self.fingerprintsKey) as? [String: String]) ?? [:]
        let copied = (defaults.dictionary(forKey: Self.lastKey) as? [String: Date]) ?? [:]
        guard let stamp = fingerprints[target.key], stamp.hasPrefix(place + "|"), let date = copied[target.key] else { return nil }
        return CartoucheSaveBase(place: place, copy: CartoucheSaveSync.fileName(date), content: nil,
                                 look: String(stamp.dropFirst(place.count + 1)))
    }

    /// Keeps what a sync of TARGET's saves did.
    private func record(_ outcome: CartoucheSaveOutcome, of target: CartoucheSaveTarget) {
        waiting.remove(target.key)
        if let base = outcome.base, base != bases[target.key] {
            bases[target.key] = base
            defaults.set(try? JSONEncoder().encode(bases), forKey: Self.basesKey)
        }
        lastSync[target.key] = Date()
        defaults.set(lastSync, forKey: Self.syncedKey)
        // The newest copy waits for the game's update, until it comes or
        // the saves here go over it.
        if let held = outcome.newer {
            note(newer: CartoucheSaveNewer(copy: held, game: target.gameVersion ?? ""), of: target)
        } else if outcome.fetched != nil || outcome.sent != nil || outcome.step == .same {
            note(newer: nil, of: target)
        }
        let fetched = outcome.fetched.flatMap(CartoucheSaveSync.date(inName:))
        let kept = outcome.kept.flatMap(CartoucheSaveSync.date(inName:))
        if outcome.newer != nil {
            // What the sheet says of the newest copy, which waits, takes the
            // place of the news, the copy kept under it with them.
            guard news[target.key] != nil else { return }
            news[target.key] = nil
        } else if fetched != nil || kept != nil {
            news[target.key] = CartoucheSaveNews(fetched: fetched, kept: kept)
        } else if outcome.sent != nil {
            // Played since: what came before is old news.
            news[target.key] = nil
        } else {
            return
        }
        defaults.set(try? JSONEncoder().encode(news), forKey: Self.newsKey)
    }

    /// Keeps whether TARGET's newest copy waits for the game's update.
    private func note(newer held: CartoucheSaveNewer?, of target: CartoucheSaveTarget) {
        guard newer[target.key] != held else { return }
        newer[target.key] = held
        defaults.set(try? JSONEncoder().encode(newer), forKey: Self.newerKey)
        if let held {
            CartoucheReports.note("Saves of \(target.name): the newest copy is of version \(held.copy) of the game, "
                                  + "newer than this iPhone's \(held.game); it waits for the game's update")
        }
    }

    /// The journal's lines on a round: the saves sent, those that came, and
    /// those kept under newer ones.
    private func note(_ outcomes: [String: CartoucheSaveOutcome], of targets: [CartoucheSaveTarget]) {
        let sent = targets.filter { outcomes[$0.key]?.sent != nil }.count
        if sent > 0 {
            CartoucheReports.note("Saves sent to the saves folder: \(sent) " + (sent == 1 ? "game" : "games"), own: true)
        }
        for target in targets {
            guard let outcome = outcomes[target.key] else { continue }
            var line: String
            if let fetched = outcome.fetched {
                line = "Saves of \(target.name) came from the saves folder, the copy \(fetched)"
                if let kept = outcome.kept {
                    line += "; this iPhone's kept there as \(kept)"
                }
            } else if let kept = outcome.kept {
                line = "Saves of \(target.name): newer ones in the saves folder, "
                line += outcome.newer == nil ? "for the next start; " : "for the game's update; "
                line += "this iPhone's kept there as \(kept)"
            } else {
                continue
            }
            CartoucheReports.note(line)
        }
    }

    /// The saves of TARGETS wait for the saves folder's server, offline
    /// from here.
    private func wait(for targets: [CartoucheSaveTarget]) {
        problemReport = nil
        let added = Set(targets.map { $0.key }).subtracting(waiting)
        guard !added.isEmpty else { return }
        waiting.formUnion(added)
        CartoucheReports.note("Saves waiting for the saves folder: \(waiting.count) " + (waiting.count == 1 ? "game" : "games"),
                              own: true)
    }

    /// The saves folder, as a base names it: "<server ID>|<path>".
    private static func place(_ location: (server: CartoucheStorageServer, path: String)) -> String {
        location.server.id.uuidString + "|" + location.path
    }

    /// Where the copies that come are unpacked, before they replace a
    /// game's saves.
    private static var scratch: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CartoucheSaves", isDirectory: true)
    }

    /// How the saves in DOCUMENTS look, read off the main thread.
    nonisolated private static func look(of documents: URL) async -> String? {
        CartoucheSaveSync.saves(in: documents)?.look
    }

    /// A few seconds more to finish, if the player leaves Cartouche.
    private func beginBackground() {
        guard background == .invalid else { return }
        background = UIApplication.shared.beginBackgroundTask(withName: "Cartouche saves") { [weak self] in
            // iOS calls this on the main thread, as the time runs out.
            Task { @MainActor in self?.endBackground() }
        }
    }

    private func endBackground() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background)
        background = .invalid
    }

    // MARK: While a game plays

    /// While TARGET's game plays behind the console, Cartouche beside it:
    /// the saves it makes go to the saves folder a few seconds after it
    /// made them (CartoucheSaveWatch), from a copy made at one moment
    /// (CartoucheSaveSync.snapshot), in their turn with the other syncs.
    /// Away from the saves folder's server, they wait for it, as after a
    /// game.
    func watch(_ target: CartoucheSaveTarget) {
        guard isOn, let location = settings.location(.saves), looking[target.key] == nil else { return }
        playingGames[target.key] = target
        watches[target.key] = CartoucheSaveWatch(inStep: savedBase(of: target, place: Self.place(location))?.look)
        playCopies[target.key] = nil
        playFailed.remove(target.key)
        playTold[target.key] = (0, 0)
        looking[target.key] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(CartoucheSaveWatch.interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.lookAgain(at: target)
            }
        }
    }

    /// TARGET's game ended: its saves are no longer watched, and those it
    /// made since they last went go now, after the syncs under way, in place
    /// of the copy they went to while it played. A game started next waits
    /// for them (finish).
    func gameEnded(_ target: CartoucheSaveTarget) {
        looking.removeValue(forKey: target.key)?.cancel()
        watches[target.key] = nil
        playingGames[target.key] = nil
        guard isOn else {
            playCopies[target.key] = nil
            return
        }
        let played = playTold.removeValue(forKey: target.key)
        let previous = ending[target.key]
        let task = Task {
            await previous?.value
            _ = await turn {
                await self.syncRound([target], fetching: false, onlyChanged: true, byPlayer: false, telling: .after, played: played)
            }
        }
        ending[target.key] = task
        Task {
            await task.value
            guard ending[target.key] == task else { return }
            ending[target.key] = nil
            if playingGames[target.key] == nil { playCopies[target.key] = nil }
        }
    }

    /// Cartouche leaves the screen while a game plays beside it: its saves
    /// that have not gone yet go now, without the few seconds' wait, before
    /// iOS stops Cartouche.
    func sendWaitingNow() {
        guard !playingGames.isEmpty else { return }
        beginBackground()
        Task {
            for target in Array(playingGames.values) {
                let look = await Self.look(of: target.documents)
                if watches[target.key]?.isPending(look) == true {
                    await sendPlaying(target)
                }
            }
            if run == nil { endBackground() }
        }
    }

    /// The saves folder's server answers again, or Cartouche came back: the
    /// saves of the game playing that did not go are tried again at once.
    func retryPlaying() {
        for key in watches.keys {
            watches[key]?.retryNow()
        }
    }

    /// Looks at TARGET's saves again: they go once they have stayed as they
    /// are for a few seconds.
    private func lookAgain(at target: CartoucheSaveTarget) async {
        guard watches[target.key] != nil else { return }
        let look = await Self.look(of: target.documents)
        guard watches[target.key]?.due(look) == true else { return }
        await sendPlaying(target)
    }

    /// Sends TARGET's saves, which changed while its game plays, in their
    /// turn: what its watch learns of it.
    private func sendPlaying(_ target: CartoucheSaveTarget) async {
        let reporting = !playFailed.contains(target.key)
        let round = await turn { () -> PlayRound in
            let round = await self.syncRound([target], fetching: false, onlyChanged: true, byPlayer: false, playing: true,
                                             reporting: reporting)
            return PlayRound(inStep: round.inStep[target.key], moved: round.moved.contains(target.key),
                             failed: round.failure != nil, offline: round.failure is CartoucheStorageOffline)
        }
        guard watches[target.key] != nil else { return }
        if let look = round.inStep {
            watches[target.key]?.sent(look)
        } else if round.moved {
            watches[target.key]?.moved()
        } else if round.failed {
            watches[target.key]?.failed()
            if !round.offline {
                playFailed.insert(target.key)
                playTold[target.key]?.failed += 1
            }
        }
    }

    /// What a sync of a game's saves while it plays did, for its watch.
    private struct PlayRound: Sendable {
        /// How its saves looked when they went, or were found in step.
        var inStep: String?
        /// They kept changing while they were copied.
        var moved: Bool
        var failed: Bool
        var offline: Bool
    }

    // MARK: Listing and putting back

    /// TARGET's copies in the saves folder, the newest first.
    func copies(of target: CartoucheSaveTarget) async throws -> [CartoucheSaveBackup] {
        guard let location = settings.location(.saves) else { return [] }
        let remote = try await CartoucheStorage.connect(location.server, settings: settings)
        let folder = CartoucheSavesFolder(remote: remote, path: location.path, place: Self.place(location), scratch: Self.scratch)
        do {
            let copies = try await folder.copies(of: target)
            await remote.disconnect()
            return copies
        } catch {
            await remote.disconnect()
            throw error
        }
    }

    /// Puts BACKUP back as TARGET's saves, as the player chose it. The saves
    /// it replaces go to the saves folder first; nothing changes on the
    /// iPhone unless the backup reads whole. The copy put back then becomes
    /// the newest one, which the player's other iPhones take at their next
    /// start.
    func restore(_ backup: CartoucheSaveBackup, of target: CartoucheSaveTarget) async throws {
        let failure: Error? = await turn {
            do {
                try await self.putBack(backup, of: target)
                return nil
            } catch {
                return error
            }
        }
        if let failure { throw failure }
    }

    // MARK: A save from the Switch

    /// Puts the save from the player's Switch that STAGED holds
    /// (CartoucheSwitchSave.stage) in place of TARGET's, once the syncs under
    /// way have ended, none starting meanwhile: the saves it replaces are
    /// kept on this iPhone first. It then goes to the saves folder as the
    /// newest copy, if the player chose one: now, or once its server answers
    /// again. RUNNING: whether the game runs now, which its turn asks
    /// first, as the player may have started it since the question; nothing
    /// changes then. The backup of the saves it replaced, nil when there
    /// were none.
    func bringIn(_ staged: URL, of target: CartoucheSaveTarget, running: @escaping @MainActor () -> Bool) async throws -> URL? {
        let documents = target.documents
        let result: Result<URL?, Error> = await turn {
            if running() { return .failure(CartoucheSwitchSaveProblem.running) }
            return await Task.detached(priority: .userInitiated) {
                Result { try CartoucheSwitchSave.place(staged, in: documents) }
            }.value
        }
        let backup = try result.get()
        news[target.key] = nil
        defaults.set(try? JSONEncoder().encode(news), forKey: Self.newsKey)
        sendChanged(target)
        return backup
    }

    /// Puts BACKUP, the saves an import replaced, back in place of TARGET's,
    /// as the player asked, the same way: what it replaces is kept on this
    /// iPhone, and it goes to the saves folder; nothing changes while the
    /// game runs (RUNNING).
    func putBack(beforeImport backup: CartoucheSwitchSaveBackup, of target: CartoucheSaveTarget,
                 running: @escaping @MainActor () -> Bool) async throws {
        let documents = target.documents
        let folder = backup.folder
        let result: Result<Void, Error> = await turn {
            if running() { return .failure(CartoucheSwitchSaveProblem.running) }
            return await Task.detached(priority: .userInitiated) {
                Result { try CartoucheSwitchSave.putBack(folder, in: documents) }
            }.value
        }
        try result.get()
        sendChanged(target)
    }

    /// Sends TARGET's saves, which the player changed on this iPhone, to the
    /// saves folder, after the syncs under way: now, or once its server
    /// answers again.
    private func sendChanged(_ target: CartoucheSaveTarget) {
        guard isOn else { return }
        Task {
            _ = await turn { await self.syncRound([target], fetching: false, onlyChanged: true, byPlayer: false).failure == nil }
        }
    }

    private func putBack(_ backup: CartoucheSaveBackup, of target: CartoucheSaveTarget) async throws {
        guard let location = settings.location(.saves) else { return }
        let place = Self.place(location)
        isSyncing = true
        beginBackground()
        defer {
            isSyncing = false
            endBackground()
        }
        let remote = try await CartoucheStorage.connect(location.server, settings: settings)
        do {
            if await settings.checkAccess(remote, server: location.server.id, path: location.path) == false {
                throw CartoucheStorageError(.readOnly, CartoucheText.savesReadOnly)
            }
            let folder = CartoucheSavesFolder(remote: remote, path: location.path, place: place, scratch: Self.scratch)
            let outcome = try await folder.putBack(CartoucheStoragePath.name(backup.path), of: target,
                                                   base: savedBase(of: target, place: place))
            record(outcome, of: target)
            // The player put it back: no news to tell of it.
            news[target.key] = nil
            defaults.set(try? JSONEncoder().encode(news), forKey: Self.newsKey)
            problemReport = nil
        } catch {
            await remote.disconnect()
            throw error
        }
        await remote.disconnect()
    }
}
