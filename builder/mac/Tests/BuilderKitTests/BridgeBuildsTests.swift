//
//  BridgeBuildsTests.swift
//  BuilderKitTests
//
//  The builds a paired iPhone sees, and the build it asks for
//  (BridgeBuilds.swift, BridgeServer's BridgeBuildsSource): the library's
//  games, those building and those waiting their turn in their order, when
//  each was built and its last failure, cut, whether the Mac follows each
//  and which can be stopped alone, what is due and the nightly build; then
//  over a session, the Mac's info, its builds, a build asked for and the
//  Mac's refusal in its own words, and the rest of what the window does,
//  asked from the iPhone. What each build is for, the iPhone, the Mac or
//  both, and the part it makes now, and a game's app for the Mac apart
//  (decision 127). What Cartouche makes of them is tested with Cartouche's
//  (launcher/Tests/CartoucheCoreTests/CartoucheBridgeBuildsTests.swift).
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

/// One end of a connection in memory; frames go to the other end.
private final class Pipe: CartoucheBridgeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Data] = []
    private var waiting: CheckedContinuation<Data, Error>?
    private var closed = false
    weak var other: Pipe?

    static func pair() -> (Pipe, Pipe) {
        let a = Pipe(), b = Pipe()
        a.other = b
        b.other = a
        return (a, b)
    }

    func sendFrame(_ data: Data) async throws {
        guard let other else { throw CartoucheBridgeError(.closed) }
        other.deliver(data)
    }

    private func deliver(_ data: Data) {
        lock.lock()
        if let waiting {
            self.waiting = nil
            lock.unlock()
            waiting.resume(returning: data)
        } else {
            frames.append(data)
            lock.unlock()
        }
    }

    func receiveFrame() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !frames.isEmpty {
                let frame = frames.removeFirst()
                lock.unlock()
                continuation.resume(returning: frame)
            } else if closed {
                lock.unlock()
                continuation.resume(throwing: CartoucheBridgeError(.closed))
            } else {
                waiting = continuation
                lock.unlock()
            }
        }
    }

    func close() {
        shut()
        other?.shut()
    }

    private func shut() {
        lock.lock()
        closed = true
        let waiting = self.waiting
        self.waiting = nil
        lock.unlock()
        waiting?.resume(throwing: CartoucheBridgeError(.closed))
    }
}

/// The app, as a paired iPhone sees its builds: the games it was asked to
/// build, what else it was asked, and the Mac's refusal, if it refuses.
@MainActor
private final class Builds: BridgeBuildsSource {
    var shared = CartoucheBridgeBuilds()
    var asked: [String] = []
    /// The rest, in the order asked: "due", "stop A", "stop all",
    /// "follow A on", "nightly on 4:15".
    var done: [String] = []
    var refusal: CartoucheBridgeError?

    func bridgeBuilds() -> CartoucheBridgeBuilds { shared }

    func bridgeBuild(_ titleID: String, due: Bool) throws {
        if let refusal { throw refusal }
        asked.append(titleID + (due ? " due" : ""))
        shared.running = true
        if let index = shared.games.firstIndex(where: { $0.id == titleID }) {
            shared.games[index].state = "building"
        }
    }

    func bridgeBuildDue() throws {
        if let refusal { throw refusal }
        done.append("due")
    }

    func bridgeStop(_ titleID: String?) throws {
        done.append(titleID.map { "stop " + $0 } ?? "stop all")
        shared.running = titleID != nil
    }

    func bridgeFollow(_ titleID: String, _ followed: Bool) async throws {
        // As the app, which reads its library again before it answers.
        await Task.yield()
        done.append("follow \(titleID) \(followed ? "on" : "off")")
        if let index = shared.games.firstIndex(where: { $0.id == titleID }) {
            shared.games[index].followed = followed
        }
    }

    func bridgeNightly(_ nightly: CartoucheBridgeBuilds.Nightly) throws {
        done.append("nightly \(nightly.on ? "on" : "off") \(nightly.hour):\(nightly.minute)")
        shared.nightly = nightly
    }
}

final class BridgeBuildsTests: XCTestCase {
    static let stage: (String?) -> String = { "Stage " + ($0 ?? "none") }

    func game(_ titleID: String, _ state: GameState, reasons: [String] = [], built: String? = nil, attempt: GameAttempt? = nil,
              kind: String = "nsp") -> Game {
        Game(titleID: titleID, name: "Game \(titleID)", kind: kind, state: state, reasons: reasons,
             build: built.map { GameBuild(commit: "7bddb8c1e2f3", builtAt: $0) }, attempt: attempt)
    }

    func testTheLibraryWithTheGamesBuildingAndWaiting() throws {
        var building = GameProgress(titleID: "A", name: "Game A", state: "building", stage: "shaders", frac: 0.2, overall: 0.4, eta: 300)
        building.reasons = ["changes"]
        let library = [
            game("A", .due, reasons: ["changes"], built: "2026-11-10T07:00:00+00:00"),
            game("B", .upToDate, built: "2026-11-12T07:00:00+00:00"),
            game("C", .due, reasons: ["new"]),
            game("D", .noSource, built: "2026-11-01T07:00:00+00:00", kind: "ipa"),
        ]
        let waiting = [
            GameProgress(titleID: "C", name: "Game C", state: "queued"),
            // Twice in the queue, and the game building: once, in its first place.
            GameProgress(titleID: "C", name: "Game C", state: "queued"),
            GameProgress(titleID: "A", name: "Game A", state: "queued"),
            GameProgress(titleID: "B", name: "Game B", state: "queued"),
            // Not in the library yet.
            GameProgress(titleID: "E", name: "Game E", state: "queued"),
        ]
        let shared = BridgeBuilds.shared(games: library, building: [building], waiting: waiting, running: true, ready: false,
                                         why: "Importing", stage: Self.stage)
        XCTAssertTrue(shared.running)
        XCTAssertFalse(shared.ready)
        XCTAssertEqual(shared.why, "Importing")
        XCTAssertEqual(shared.games.map(\.id), ["A", "B", "C", "D", "E"])
        let a = shared.games[0]
        XCTAssertEqual(a.state, "building")
        XCTAssertEqual(a.progress, 0.4)
        XCTAssertEqual(a.step, "Stage shaders")
        XCTAssertEqual(a.left, 300)
        XCTAssertEqual(a.reasons, ["changes"])
        XCTAssertEqual(a.builtDate, ISODate.parse("2026-11-10T07:00:00+00:00"))
        XCTAssertEqual(shared.games.map(\.turn), [nil, 2, 1, nil, 3])
        XCTAssertEqual(shared.waiting.map(\.id), ["C", "B", "E"])
        XCTAssertEqual(shared.games[3].state, "no_source")
        XCTAssertFalse(shared.games[3].buildable)
        XCTAssertTrue(shared.games[0].buildable)
        XCTAssertEqual(shared.games[4].name, "Game E")
        XCTAssertEqual(shared.games[4].state, "queued")

        // Ready: no reason why not.
        XCTAssertNil(BridgeBuilds.shared(games: library, building: [], waiting: [], running: false, ready: true, why: "stale",
                                         stage: Self.stage).why)
    }

    func testTheLastFailureAndItsWordsCut() throws {
        let long = String(repeating: "x", count: BridgeBuilds.errorLength + 50)
        let failedSince = game("A", .failed, built: "2026-11-10T07:00:00+00:00",
                               attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "failed", error: long))
        let shared = BridgeBuilds.game(failedSince, building: nil, turn: nil, stage: Self.stage)
        XCTAssertEqual(shared.failedDate, ISODate.parse("2026-11-11T07:00:00+00:00"))
        XCTAssertEqual(shared.error?.count, BridgeBuilds.errorLength)
        XCTAssertEqual(shared.error?.last, "…")

        // A failure before the last build is over; a stop is no failure.
        let builtSince = game("A", .upToDate, built: "2026-11-12T07:00:00+00:00",
                              attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "failed", error: "old"))
        XCTAssertNil(BridgeBuilds.game(builtSince, building: nil, turn: nil, stage: Self.stage).failed)
        let stopped = game("A", .upToDate, built: "2026-11-10T07:00:00+00:00",
                           attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "stopped"))
        XCTAssertNil(BridgeBuilds.game(stopped, building: nil, turn: nil, stage: Self.stage).error)
        // Never built, failed.
        let never = game("A", .failed, attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "failed"))
        XCTAssertNotNil(BridgeBuilds.game(never, building: nil, turn: nil, stage: Self.stage).failed)
    }

    func testTheLibraryReadWhileTheBatchHadTheGame() {
        // The batch no longer has it: as it was before.
        XCTAssertEqual(BridgeBuilds.game(game("A", .building), building: nil, turn: nil, stage: Self.stage).state, "due")
        XCTAssertEqual(BridgeBuilds.game(game("A", .queued, built: "2026-11-10T07:00:00+00:00"), building: nil, turn: nil,
                                         stage: Self.stage).state, "up_to_date")
    }

    func testWhatTheWindowCanDoIsShared() {
        var followed = game("A", .upToDate, built: "2026-11-10T07:00:00+00:00")
        followed.followed = true
        var notFollowed = game("B", .notFollowed, built: "2026-11-10T07:00:00+00:00")
        notFollowed.followed = false
        let library = [followed, notFollowed, game("C", .due, reasons: ["new"]), game("D", .noSource, kind: "ipa"), game("E", .due, reasons: ["changes"])]
        let building = [GameProgress(titleID: "C", name: "Game C", state: "building")]
        let waiting = [GameProgress(titleID: "E", name: "Game E", state: "queued"), GameProgress(titleID: "F", name: "Game F", state: "queued")]
        // C stops; E can be taken out of the queue, F not yet.
        let control = BridgeBuilds.Control(stoppable: { $0 != "F" }, stopping: { $0 == "C" }, due: 2,
                                           nightly: CartoucheBridgeBuilds.Nightly(on: true, hour: 4, minute: 15))
        let shared = BridgeBuilds.shared(games: library, building: building, waiting: waiting, running: true, ready: true, why: nil,
                                         stage: Self.stage, control: control)
        XCTAssertEqual(shared.games.map(\.id), ["A", "B", "C", "D", "E", "F"])
        XCTAssertEqual(shared.games.map(\.followed), [true, false, true, nil, true, nil])
        XCTAssertEqual(shared.games.map(\.stoppable), [nil, nil, false, nil, true, false])
        XCTAssertEqual(shared.games.map(\.stopping), [nil, nil, true, nil, false, false])
        XCTAssertEqual(shared.due, 2)
        XCTAssertEqual(shared.nightly, CartoucheBridgeBuilds.Nightly(on: true, hour: 4, minute: 15))

        // A Mac that does not say: nothing of it.
        let without = BridgeBuilds.shared(games: library, building: building, waiting: waiting, running: true, ready: true, why: nil,
                                          stage: Self.stage)
        XCTAssertEqual(without.games.compactMap(\.stoppable), [])
        XCTAssertNil(without.due)
        XCTAssertNil(without.nightly)
    }

    func testAGameDueForItsMacAppAloneIsUpToDateToTheIPhone() {
        var macAlone = game("A", .due, reasons: ["mac_new"], built: "2026-11-10T07:00:00+00:00")
        macAlone.platforms = GamePlatforms(ios: true, mac: true)
        XCTAssertTrue(BridgeBuilds.dueForMacAppAlone(macAlone))
        let shared = BridgeBuilds.game(macAlone, building: nil, turn: nil, stage: Self.stage)
        XCTAssertEqual(shared.state, "up_to_date")
        XCTAssertEqual(shared.reasons, [])
        // Its app for the Mac, which an iPhone that knows reads as due.
        XCTAssertEqual(shared.mac?.due, true)
        XCTAssertNil(shared.mac?.built)
        XCTAssertFalse(BridgeBuilds.dueForMacAppAlone(game("A", .due, reasons: ["mac_new", "changes"])))
        XCTAssertFalse(BridgeBuilds.dueForMacAppAlone(game("A", .due)))
        XCTAssertFalse(BridgeBuilds.dueForMacAppAlone(game("A", .upToDate, reasons: ["mac_new"])))
    }

    func testABuildAskedFromTheIPhoneIsForcedAsTheWindowsButton() {
        // Up to date: built again; due: what is due.
        XCTAssertTrue(BridgeBuilds.forced(game("A", .upToDate, built: "2026-11-10T07:00:00+00:00"), due: false))
        XCTAssertTrue(BridgeBuilds.forced(game("A", .upToDate, built: "2026-11-10T07:00:00+00:00"), due: true))
        XCTAssertFalse(BridgeBuilds.forced(game("A", .due, reasons: ["changes"]), due: false))
        // Due for its app for this Mac alone: that app alone when the iPhone
        // asks for what is due; all of it again when it does not say, as
        // an iPhone that showed it up to date asks.
        let macAlone = game("A", .due, reasons: ["mac_behind"], built: "2026-11-10T07:00:00+00:00")
        XCTAssertFalse(BridgeBuilds.forced(macAlone, due: true))
        XCTAssertTrue(BridgeBuilds.forced(macAlone, due: false))
    }

    func testWhatEachBuildIsForIsShared() throws {
        let both = GamePlatforms(ios: true, mac: true)
        let built = "2026-11-10T07:00:00+00:00", appBuilt = "2026-11-10T08:00:00+00:00"
        // Building its IPA, its app for this Mac after it.
        var a = game("A", .due, reasons: ["changes"], built: built)
        a.platforms = both
        a.mac = GameMac(build: GameBuild(commit: "7bddb8c1e2f3", builtAt: appBuilt))
        var building = GameProgress(titleID: "A", name: "Game A", state: "building", stage: "shaders")
        building.makes = ["ios", "mac"]
        building.mac = "waiting"
        // Built for this Mac alone: its dates are its app's.
        var b = game("B", .upToDate, built: built)
        b.platforms = GamePlatforms(ios: false, mac: true)
        b.mac = GameMac(build: GameBuild(commit: "7bddb8c1e2f3", builtAt: appBuilt),
                        attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "failed", error: "No Metal"))
        // Its IPA up to date, its app's last build failed since.
        var c = game("C", .upToDate, built: built)
        c.platforms = both
        c.mac = GameMac(build: GameBuild(commit: "7bddb8c1e2f3", builtAt: "2026-11-09T07:00:00+00:00"),
                        attempt: GameAttempt(commit: "7bddb8c1e2f3", at: "2026-11-11T07:00:00+00:00", result: "failed", error: "No Metal"))
        // Waiting its turn: for the iPhone alone, and for both, its app
        // alone being due.
        let d = game("D", .due, reasons: ["changes"], built: built)
        var e = game("E", .due, reasons: ["mac_new"], built: built)
        e.platforms = both
        let waiting = [GameProgress(titleID: "D", name: "Game D", state: "queued"), GameProgress(titleID: "E", name: "Game E", state: "queued")]
        let shared = BridgeBuilds.shared(games: [a, b, c, d, e], building: [building], waiting: waiting, running: true, ready: true,
                                         why: nil, stage: Self.stage)
        XCTAssertEqual(shared.games.map(\.platforms), [["ios", "mac"], ["mac"], ["ios", "mac"], ["ios"], ["ios", "mac"]])
        XCTAssertEqual(shared.games.map(\.makes), [["ios", "mac"], nil, nil, ["ios"], ["mac"]])
        XCTAssertEqual(shared.games.map(\.now), ["ios", nil, nil, nil, nil])
        XCTAssertEqual(shared.games[0].mac?.builtDate, ISODate.parse(appBuilt))
        XCTAssertEqual(shared.games[0].builtDate, ISODate.parse(built))
        // Built for this Mac alone: its app's dates, and no app apart.
        XCTAssertEqual(shared.games[1].builtDate, ISODate.parse(appBuilt))
        XCTAssertEqual(shared.games[1].failedDate, ISODate.parse("2026-11-11T07:00:00+00:00"))
        XCTAssertEqual(shared.games[1].error, "No Metal")
        XCTAssertNil(shared.games[1].mac)
        // Its app's failure apart from its IPA, which is up to date.
        XCTAssertNil(shared.games[2].failed)
        XCTAssertEqual(shared.games[2].mac?.failed, ISODate.parse("2026-11-11T07:00:00+00:00")?.timeIntervalSince1970)
        XCTAssertEqual(shared.games[2].mac?.error, "No Metal")
        XCTAssertEqual(shared.games[2].mac?.due, false)
        // Built for the iPhone alone: no app for the Mac.
        XCTAssertNil(shared.games[3].mac)

        // As the app says what a build makes (AppModel.targets): the batch's
        // plan, or the settings of a game it has not planned yet.
        let told = BridgeBuilds.shared(games: [a, d], building: [building], waiting: [waiting[0]], running: true, ready: true, why: nil,
                                       stage: Self.stage, targets: { _ in CartoucheBuildTargets([.mac], now: .mac) })
        XCTAssertEqual(told.games.map(\.makes), [["mac"], ["mac"]])
        XCTAssertEqual(told.games.map(\.now), ["mac", nil])
        // A game of the batch the library does not show yet.
        var alone = GameProgress(titleID: "F", name: "Game F", state: "building")
        alone.makes = ["ios"]
        let batchOnly = BridgeBuilds.shared(games: [], building: [alone], waiting: [], running: true, ready: true, why: nil, stage: Self.stage)
        XCTAssertEqual(batchOnly.games.map(\.makes), [["ios"]])
        XCTAssertEqual(batchOnly.games.map(\.now), ["ios"])
    }

    func testAGameNoMacBuiltIsLeftAsideFromTheIPhone() {
        // None: as asked, what is due included.
        XCTAssertEqual(BridgeBuilds.toBuild([], due: ["A", "B"], never: []), [])
        XCTAssertEqual(BridgeBuilds.toBuild(["B"], due: ["A", "B"], never: []), ["B"])
        // What is due: the others, as the nightly run builds them, and
        // nothing when it is all there is.
        XCTAssertEqual(BridgeBuilds.toBuild([], due: ["A", "B", "C"], never: ["B"]), ["A", "C"])
        XCTAssertNil(BridgeBuilds.toBuild([], due: ["B"], never: ["B"]))
        // The game itself: refused, never asked about on the Mac.
        XCTAssertNil(BridgeBuilds.toBuild(["B"], due: ["A", "B"], never: ["B"]))
    }

    // MARK: Over a session

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        for name in ["Jeux", "Saves"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A session of a paired iPhone with SERVER: its client, and the task
    /// that serves it until it closes.
    private func session(_ server: BridgeServer) async throws -> (CartoucheBridgeClient, Task<Void, Never>) {
        let key = Data(repeating: 5, count: 32)
        let device = UUID().uuidString
        server.devices.add(id: device, name: "iPhone de test", key: key)
        let (phoneSide, macSide) = Pipe.pair()
        let serving = Task { await server.open(macSide) }
        let channel = try await CartoucheBridgeHandshake.client(phoneSide, device: device, key: key, mac: server.devices.macID)
        return (CartoucheBridgeClient(channel: channel, address: nil), serving)
    }

    private func server() -> BridgeServer {
        let server = BridgeServer(devices: BridgeDevices(url: folder.appendingPathComponent("bridge.json")), name: "Mac de test")
        server.roots = BridgeRoots(games: folder.appendingPathComponent("Jeux", isDirectory: true),
                                   saves: folder.appendingPathComponent("Saves", isDirectory: true))
        return server
    }

    func testAMacWithoutBuildsSaysSo() async throws {
        let server = server()
        let (client, serving) = try await session(server)
        let info = try await client.info()
        XCTAssertEqual(info.hasBuilds, false)
        XCTAssertEqual(info.hasBuildsControl, false)
        do {
            _ = try await client.builds()
            XCTFail("builds from a Mac without any")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error.kind, .notFound)
        }
        // The session goes on.
        let top = try await client.list("")
        XCTAssertEqual(top.map(\.name), [CartoucheBridge.gamesFolder, CartoucheBridge.savesFolder])
        client.close()
        await serving.value
    }

    func testTheBuildsAndABuildAskedFor() async throws {
        let server = server()
        let builds = await MainActor.run { () -> Builds in
            let builds = Builds()
            builds.shared = CartoucheBridgeBuilds(games: [CartoucheBridgeBuilds.Game(id: "A", name: "Game A", state: "up_to_date")])
            return builds
        }
        server.builds = builds
        let (client, serving) = try await session(server)
        let hasBuilds = try await client.info().hasBuilds
        XCTAssertEqual(hasBuilds, true)
        let before = try await client.builds()
        XCTAssertFalse(before.running)
        XCTAssertEqual(before.games.map(\.state), ["up_to_date"])
        let after = try await client.build("A")
        XCTAssertTrue(after.running)
        XCTAssertEqual(after.games.map(\.state), ["building"])
        let asked = await MainActor.run { builds.asked }
        XCTAssertEqual(asked, ["A"])
        // What is due of it, as the Build button of its sheet: its app for
        // the Mac alone, when that alone is due.
        _ = try await client.build("A", due: true)
        let askedDue = await MainActor.run { builds.asked }
        XCTAssertEqual(askedDue, ["A", "A due"])

        // Without a game, and refused by the Mac, in its words.
        do {
            _ = try await client.call(CartoucheBridgeRequest(.build))
            XCTFail("a build of no game")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error.kind, .notFound)
        }
        await MainActor.run { builds.refusal = CartoucheBridgeError(.failed, "The Mac is importing an IPA") }
        do {
            _ = try await client.build("A")
            XCTFail("a build the Mac refused")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error, CartoucheBridgeError(.failed, "The Mac is importing an IPA"))
        }
        let stillAsked = await MainActor.run { builds.asked }
        XCTAssertEqual(stillAsked, ["A", "A due"])
        client.close()
        await serving.value
    }

    func testTheRestOfTheWindowAskedFromTheIPhone() async throws {
        let server = server()
        let builds = await MainActor.run { () -> Builds in
            let builds = Builds()
            builds.shared = CartoucheBridgeBuilds(running: true, games: [CartoucheBridgeBuilds.Game(id: "A", name: "Game A", state: "queued",
                                                                                                   turn: 1, followed: true, stoppable: true)])
            return builds
        }
        server.builds = builds
        let (client, serving) = try await session(server)
        let info = try await client.info()
        XCTAssertEqual(info.hasBuildsControl, true)

        _ = try await client.buildDue()
        _ = try await client.stop("A")
        let stopped = try await client.stopAll()
        XCTAssertFalse(stopped.running)
        let unfollowed = try await client.follow("A", false)
        XCTAssertEqual(unfollowed.games.first?.followed, false)
        let nightly = try await client.setNightly(CartoucheBridgeBuilds.Nightly(on: true, hour: 4, minute: 15))
        XCTAssertEqual(nightly.nightly, CartoucheBridgeBuilds.Nightly(on: true, hour: 4, minute: 15))
        let done = await MainActor.run { builds.done }
        XCTAssertEqual(done, ["due", "stop A", "stop all", "follow A off", "nightly on 4:15"])

        // Without what each needs: refused, and the session goes on.
        let incomplete: [(CartoucheBridgeRequest, CartoucheBridgeError.Kind)] = [
            (CartoucheBridgeRequest(.stop), .notFound),
            (CartoucheBridgeRequest(.follow, game: "A"), .protocolError),
            (CartoucheBridgeRequest(.nightly), .protocolError),
        ]
        for (request, kind) in incomplete {
            do {
                _ = try await client.call(request)
                XCTFail("\(request.op) without what it needs")
            } catch let error as CartoucheBridgeError {
                XCTAssertEqual(error.kind, kind, "\(request.op)")
            }
        }
        // Refused by the Mac, in its words.
        await MainActor.run { builds.refusal = CartoucheBridgeError(.failed, "The Mac is importing an IPA") }
        do {
            _ = try await client.buildDue()
            XCTFail("Build what is due, which the Mac refused")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error, CartoucheBridgeError(.failed, "The Mac is importing an IPA"))
        }
        let after = await MainActor.run { builds.done.count }
        XCTAssertEqual(after, 5)
        client.close()
        await serving.value
    }
}
