//
//  MacBridgeTests.swift
//  CartoucheStorageTests
//
//  The player's Mac through Cartouche Builder's bridge, as the app reaches
//  it (CartoucheStorageMac.swift): the test plays the Mac on 127.0.0.1,
//  with the bridge's own handshake (CartoucheBridge.swift) and its two
//  folders, Games and Saves, in memory. Pairing and its six digits, a
//  pairing refused, signing in at the last address, and at once after
//  pairing with a Mac slow to write the pairing down, a Mac that forgot
//  this iPhone, another Mac at its address, a Mac gone, then files listed,
//  read, written, given up and removed. Through Tailscale: a Mac away from
//  home reached at its address in the tailnet (the test's loopback stands
//  in for it), not tried there while Tailscale is off, and its addresses
//  there kept as its Cartouche Builder tells them. It needs no server, so
//  it always runs.
//  Bonjour needs a real network: the Mac's side of it is in builder/mac's
//  tests (BridgeSessionTests), its words in Cartouche's.
//

import Foundation
import Network
import XCTest
@testable import CartoucheStorage

/// A Mac with Cartouche Builder, played by the test.
final class FakeMac: @unchecked Sendable {
    enum Entry: Equatable {
        case folder
        case file(Data)
    }

    let macID: String
    let name: String
    private let lock = NSLock()
    private var allowing = true
    private var writing: TimeInterval = 0
    private var keys: [String: Data] = [:]
    private var codes: [String] = []
    private var entries: [String: Entry] = ["Games": .folder, "Saves": .folder]
    private var uploads: [String: (path: String, data: Data)] = [:]
    /// The player's connections it keeps, as Cartouche Builder's console
    /// does; nil for a Mac too old to take them, whose info says nothing
    /// of them.
    private var connections: [CartoucheConnection]?
    private var given: [[CartoucheConnection]] = []
    /// The folders each iPhone told it with its connections, in order.
    private var told: [CartoucheChosenFolders?] = []
    /// The folders it keeps, the ones chosen last, which it answers with;
    /// nil for a Mac older than that, which answers with none.
    private var folders: CartoucheChosenFolders?
    private var tailnet: [String]?
    /// The NAS it reads for an iPhone plugged in, as Cartouche Builder
    /// does (BridgeRelay.swift): the files of each connection, and whether
    /// it reaches them on its Ethernet; nil for a Mac older than that,
    /// whose info says nothing of it.
    private var nas: (ethernet: Bool, files: [UUID: [String: Data]])?
    private var relayAsked = 0
    private var relayReadCount = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "Fake Mac")
    private(set) var port = 0
    /// Its link through the cable, while the iPhone is plugged into it.
    private var cableLink: CartoucheBridgeConnection?
    private var throughCable = 0

    init(name: String = "Mac de test") {
        macID = UUID().uuidString
        self.name = name
    }

    /// Listens on 127.0.0.1, on a port of its own.
    func start() async throws {
        let parameters = CartoucheBridgeConnection.parameters()
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            let transport = CartoucheBridgeConnection(connection, queue: self.queue)
            Task { await self.serve(transport) }
        }
        let once = CartoucheBridgeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { continuation.resume() }
                case let .failed(error): if once.claim() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        port = Int(listener.port?.rawValue ?? 0)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The iPhone plugged into it: as Cartouche Builder does through
    /// usbmuxd, it links to Cartouche listening on the iPhone's loopback at
    /// PORT (CartoucheCableListener), and opens a connection there for each
    /// ticket Cartouche gives. The test's loopback stands in for usbmuxd.
    func plug(into port: UInt16) async throws {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let link = try await CartoucheBridgeConnection.open(endpoint, timeout: 5)
        locked { cableLink = link }
        let macID = self.macID, name = self.name
        Task {
            await CartoucheBridgeCable.serveLink(link, mac: macID, name: name) { [weak self] ticket in
                guard let connection = try? await CartoucheBridgeConnection.open(endpoint, timeout: 5) else { return }
                do {
                    try await CartoucheBridgeCable.sayTicket(ticket, on: connection, mac: macID, name: name)
                } catch {
                    return connection.close()
                }
                guard let self else { return connection.close() }
                self.countThroughCable()
                await self.handshake(connection, cable: true)
            }
        }
    }

    /// The iPhone unplugged: its link ends.
    func unplug() {
        lock.lock()
        let link = cableLink
        cableLink = nil
        lock.unlock()
        link?.close()
    }

    private func countThroughCable() {
        lock.lock()
        throughCable += 1
        lock.unlock()
    }

    private func locked(_ body: () -> Void) {
        lock.lock()
        body()
        lock.unlock()
    }

    /// How many connections it opened through the cable.
    var connectionsThroughCable: Int {
        lock.lock()
        defer { lock.unlock() }
        return throughCable
    }

    // MARK: What the test sets and reads

    func allow(_ allowing: Bool) {
        lock.lock()
        self.allowing = allowing
        lock.unlock()
    }

    /// Takes SECONDS to write a pairing down, as Cartouche Builder writing
    /// bridge.json on a busy disk.
    func slowToWrite(_ seconds: TimeInterval) {
        lock.lock()
        writing = seconds
        lock.unlock()
    }

    /// Tells TAILNET in its info, its addresses in the player's tailnet,
    /// as Cartouche Builder does with Tailscale on the Mac.
    func tell(tailnet: [String]?) {
        lock.lock()
        self.tailnet = tailnet
        lock.unlock()
    }

    /// Reads FILES for an iPhone plugged in from now on, each connection's
    /// by its path, as a Cartouche Builder that does, on its ETHERNET or
    /// its Wi-Fi.
    func passOn(_ files: [UUID: [String: Data]], ethernet: Bool) {
        lock.lock()
        nas = (ethernet, files)
        lock.unlock()
    }

    /// How many relayStat and relayRead it was asked.
    var relayRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return relayAsked
    }

    /// How many pieces of a NAS's file it passed on.
    var relayReads: Int {
        lock.lock()
        defer { lock.unlock() }
        return relayReadCount
    }

    /// The iPhones paired with it.
    var paired: [String] {
        lock.lock()
        defer { lock.unlock() }
        return keys.keys.sorted()
    }

    /// The codes it showed, in order.
    var shownCodes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return codes
    }

    /// Forgets DEVICE, as the player removing the iPhone on the Mac.
    func forget(_ device: String) {
        lock.lock()
        keys[device] = nil
        lock.unlock()
    }

    /// Takes the player's connections from now on, with KEPT, those it
    /// has, as a Cartouche Builder that does.
    func takeConnections(_ kept: [CartoucheConnection] = []) {
        lock.lock()
        connections = kept
        lock.unlock()
    }

    /// Keeps FOLDERS from now on, as chosen on its console, and answers
    /// with the ones chosen last, as a Cartouche Builder that does.
    func keepFolders(_ folders: CartoucheChosenFolders) {
        lock.lock()
        self.folders = folders
        lock.unlock()
    }

    /// The folders it keeps; nil while it keeps none.
    var keptFolders: CartoucheChosenFolders? {
        lock.lock()
        defer { lock.unlock() }
        return folders
    }

    /// The connections it keeps; nil while it takes none.
    var keptConnections: [CartoucheConnection]? {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }

    /// The connections each iPhone gave it, in order.
    var givenConnections: [[CartoucheConnection]] {
        lock.lock()
        defer { lock.unlock() }
        return given
    }

    /// The folders each iPhone told it with them, in order.
    var toldFolders: [CartoucheChosenFolders?] {
        lock.lock()
        defer { lock.unlock() }
        return told
    }

    func entry(_ path: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[path]
    }

    // MARK: The bridge

    private func key(of device: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keys[device]
    }

    private func asked(code: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        codes.append(code)
        return allowing
    }

    private var writingTime: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return writing
    }

    private func keep(_ key: Data, of device: String) {
        lock.lock()
        keys[device] = key
        lock.unlock()
    }

    /// Writes the pairing down, in the time it takes.
    private func write(_ key: Data, of device: String) async {
        let wait = writingTime
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        keep(key, of: device)
    }

    private func serve(_ transport: CartoucheBridgeConnection) async {
        do {
            try await transport.start(timeout: 5)
        } catch {
            return transport.close()
        }
        await handshake(transport)
    }

    /// A connection once open, the network's or the cable's (CABLE): a
    /// session, or a pairing.
    private func handshake(_ transport: CartoucheBridgeTransport, cable: Bool = false) async {
        do {
            let opening = try await CartoucheBridgeHandshake.server(transport, mac: macID, name: name,
                                                                     keyOf: { [weak self] in self?.key(of: $0) },
                                                                     allow: { [weak self] _, code in self?.asked(code: code) ?? false },
                                                                     keep: { [weak self] device, _, key in await self?.write(key, of: device) })
            switch opening {
            case let .session(channel):
                while let (request, body) = try? await channel.receive(CartoucheBridgeRequest.self) {
                    let (response, data) = answer(request, body: body, cable: cable)
                    guard (try? await channel.send(response, body: data)) != nil else { break }
                }
                channel.close()
            case .paired, .refused:
                transport.close()
            }
        } catch {
            transport.close()
        }
    }

    private static func parent(_ path: String) -> String {
        CartoucheStoragePath.parent(path)
    }

    /// What Cartouche Builder answers, from the folders in memory, on a
    /// session of the network or the CABLE.
    func answer(_ request: CartoucheBridgeRequest, body: Data, cable: Bool = false) -> (CartoucheBridgeResponse, Data) {
        lock.lock()
        defer { lock.unlock() }
        let path = request.path ?? ""
        var response = CartoucheBridgeResponse()
        switch request.op {
        case .info:
            response.name = name
            response.readOnly = false
            if connections != nil { response.hasConnections = true }
            response.tailscale = tailnet
            if cable, nas != nil { response.relays = true }
        case .list:
            guard path.isEmpty || entries[path] == .folder else { return (.failure(.notFound, path), Data()) }
            response.items = entries.filter { Self.parent($0.key) == path }
                .map { item -> CartoucheBridgeItem in
                    if case let .file(data) = item.value {
                        return CartoucheBridgeItem(name: CartoucheStoragePath.name(item.key), folder: false, size: UInt64(data.count), modified: nil)
                    }
                    return CartoucheBridgeItem(name: CartoucheStoragePath.name(item.key), folder: true, size: 0, modified: nil)
                }
                .sorted { $0.name < $1.name }
        case .stat:
            switch entries[path] {
            case .folder?: response.folder = true
            case let .file(data)?:
                response.folder = false
                response.size = UInt64(data.count)
            case nil: return (.failure(.notFound, path), Data())
            }
        case .read:
            guard case let .file(data)? = entries[path] else { return (.failure(.notFound, path), Data()) }
            let start = Int(min(request.offset ?? 0, UInt64(data.count)))
            let end = min(start + min(request.count ?? 0, CartoucheBridge.maxRead), data.count)
            response.size = UInt64(data.count)
            return (response, data.subdata(in: start ..< end))
        case .create:
            guard !Self.parent(path).isEmpty, entries[Self.parent(path)] == .folder else { return (.failure(.denied, path), Data()) }
            let upload = UUID().uuidString
            uploads[upload] = (path, Data())
            response.upload = upload
        case .write:
            guard let upload = request.upload, uploads[upload] != nil else { return (.failure(.notFound, "upload"), Data()) }
            uploads[upload]?.data.append(body)
        case .finish:
            guard let upload = request.upload, let done = uploads.removeValue(forKey: upload) else { return (.failure(.notFound, "upload"), Data()) }
            entries[done.path] = .file(done.data)
            response.size = UInt64(done.data.count)
        case .cancel:
            if let upload = request.upload { uploads[upload] = nil }
        case .makeFolder:
            guard entries[Self.parent(path)] == .folder || Self.parent(path).isEmpty, !path.isEmpty else { return (.failure(.denied, path), Data()) }
            guard entries[path] == nil else { return (.failure(.exists, path), Data()) }
            entries[path] = .folder
        case .delete:
            guard Self.parent(path) != "", entries[path] != nil else { return (.failure(.denied, path), Data()) }
            entries = entries.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        case .free:
            response.free = 1 << 40
        case .canWrite:
            response.writable = !path.isEmpty && entries[path] == .folder
        case .builds, .build, .buildDue, .stop, .stopAll, .follow, .nightly:
            // A Mac without builds to show, whose info does not say it has some.
            return (.failure(.notFound, "builds"), Data())
        case .relayStat, .relayRead:
            relayAsked += 1
            // An older Mac would end the session on it.
            guard let nas else { return (.failure(.protocolError, "unknown request"), Data()) }
            guard cable else { return (.failure(.denied, "only through the cable"), Data()) }
            guard nas.ethernet else { return (.failure(.refused, "not on this Mac's Ethernet"), Data()) }
            guard let connection = request.connection, let data = nas.files[connection]?[path] else {
                return (.failure(.notFound, path), Data())
            }
            response.size = UInt64(data.count)
            guard request.op == .relayRead else {
                response.folder = false
                break
            }
            relayReadCount += 1
            let start = Int(min(request.offset ?? 0, UInt64(data.count)))
            let end = min(start + min(request.count ?? 0, CartoucheBridge.maxRead), data.count)
            return (response, data.subdata(in: start ..< end))
        case .connections:
            // Those it keeps, the iPhone's among them, as Cartouche
            // Builder's console takes them.
            guard let kept = connections else { return (.failure(.notFound, "connections"), Data()) }
            guard let theirs = request.connections else { return (.failure(.protocolError, "connections"), Data()) }
            given.append(theirs)
            told.append(request.places)
            let merged = CartoucheConnections.merged(kept, theirs)
            connections = merged
            response.connections = merged
            // The folders chosen last, here or on the iPhone, as Cartouche
            // Builder keeps them (BridgeController).
            if let kept = folders {
                folders = request.places.map { kept.taking($0) } ?? kept
                response.places = folders
            }
        }
        return (response, Data())
    }
}

/// The digits the iPhone showed, from the pairing's task.
private final class ShownCodes: @unchecked Sendable {
    private let lock = NSLock()
    private var codes: [String] = []

    func add(_ code: String) {
        lock.lock()
        codes.append(code)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return codes
    }
}

final class MacBridgeTests: XCTestCase {
    private var mac: FakeMac!

    override func setUp() async throws {
        mac = FakeMac()
        try await mac.start()
    }

    override func tearDown() async throws {
        mac.stop()
    }

    private func endpoint(_ port: Int) -> NWEndpoint {
        .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
    }

    /// Settings of their own, which keep nothing: the servers here are
    /// never saved, so the keychain is left alone.
    private func settings() -> CartoucheStorageSettings {
        CartoucheStorageSettings(defaults: UserDefaults(suiteName: "MacBridgeTests." + UUID().uuidString)!)
    }

    /// Pairs as the Storage page does once the player chose the Mac, and
    /// checks that both screens showed the same digits.
    private func pair() async throws -> (server: CartoucheStorageServer, secret: String) {
        let shown = ShownCodes()
        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), at: endpoint(mac.port),
                                                        name: "Mac de test", deviceName: "iPhone de test") { shown.add($0) }
        XCTAssertEqual(shown.all.count, 1)
        XCTAssertEqual(shown.all.first?.count, 6)
        XCTAssertEqual(shown.all, mac.shownCodes, "both screens show the same digits")
        return paired
    }

    private func signIn() async throws -> CartoucheRemote {
        let (server, secret) = try await pair()
        return try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
    }

    func testPairsOnceThenSignsInAtTheLastAddress() async throws {
        let (server, secret) = try await pair()
        XCTAssertEqual(server.kind, .mac)
        XCTAssertEqual(server.macID, mac.macID)
        XCTAssertEqual(server.name, "Mac de test")
        XCTAssertEqual(server.host, "127.0.0.1")
        XCTAssertEqual(server.port, mac.port)
        XCTAssertNotNil(CartoucheMacStorage.pairedKey(secret))
        XCTAssertEqual(mac.paired, [CartoucheMacStorage.deviceID(of: server)])

        let started = Date()
        let remote = try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
        XCTAssertLessThan(Date().timeIntervalSince(started), CartoucheMacStorage.lastAddressPatience,
                          "at the last address, without looking for the Mac")
        let top = try await remote.list("")
        XCTAssertEqual(top.map(\.name), ["Games", "Saves"])
        XCTAssertTrue(top.allSatisfy(\.isFolder))
        XCTAssertFalse(remote.isReadOnly)
        await remote.disconnect()
        let answers = await CartoucheStorageReach.answers(server)
        XCTAssertTrue(answers, "it takes a connection at its last address")
    }

    func testAPairingTheMacRefusesSaysSo() async throws {
        mac.allow(false)
        let shown = ShownCodes()
        do {
            _ = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), at: endpoint(mac.port),
                                                   name: "Mac de test", deviceName: "iPhone de test") { shown.add($0) }
            XCTFail("paired anyway")
        } catch {
            XCTAssertEqual((error as NSError).domain, "CartoucheBridge.refused")
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacRefused("Mac de test"))
        }
        XCTAssertEqual(shown.all.count, 1, "the digits showed while the Mac asked")
        XCTAssertEqual(mac.paired, [])
    }

    func testSignsInAtOnceAfterPairingWithAMacSlowToWriteItDown() async throws {
        // Cartouche signs in as soon as the Mac says the iPhone is paired,
        // to take its folders for the games and the saves: the Mac has
        // written the pairing down by then, however long that takes it.
        mac.slowToWrite(0.5)
        let (server, secret) = try await pair()
        XCTAssertEqual(mac.paired, [CartoucheMacStorage.deviceID(of: server)])
        let remote = try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
        let top = try await remote.list("")
        XCTAssertEqual(top.map(\.name), ["Games", "Saves"])
        await remote.disconnect()
    }

    func testAMacThatForgotThisIPhoneAsksToPairAgain() async throws {
        let (server, secret) = try await pair()
        mac.forget(CartoucheMacStorage.deviceID(of: server))
        do {
            _ = try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
            XCTFail("signed in to a Mac that forgot this iPhone")
        } catch {
            XCTAssertEqual((error as NSError).domain, "CartoucheBridge.notPaired")
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacNotPaired(server.name))
        }
    }

    func testAnotherMacAtTheLastAddressIsNotSignedInTo() async throws {
        let (server, secret) = try await pair()
        let other = FakeMac(name: "Autre Mac")
        try await other.start()
        defer { other.stop() }
        var moved = server
        moved.port = other.port
        // Nor does Bonjour find this one: it is offline, not unpaired.
        do {
            _ = try await CartoucheMacStorage.connect(moved, secret: secret, settings: settings())
            XCTFail("signed in to another Mac")
        } catch {
            XCTAssertTrue(error is CartoucheStorageOffline, String(describing: error))
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacOffline(server.name))
        }
        XCTAssertEqual(other.paired, [])
    }

    func testAMacGoneIsOfflineWithinItsPatience() async throws {
        let (server, secret) = try await pair()
        mac.stop()
        let started = Date()
        do {
            _ = try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
            XCTFail("signed in to a Mac that is gone")
        } catch {
            // Offline, as a NAS away from home: no report, tried again.
            XCTAssertTrue(error is CartoucheStorageOffline, String(describing: error))
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacOffline(server.name))
        }
        // Nothing listens there: the last address fails at once, then
        // Bonjour has its few seconds.
        XCTAssertLessThan(Date().timeIntervalSince(started), CartoucheMacStorage.lookupPatience + 2)
        let answers = await CartoucheStorageReach.answers(server)
        XCTAssertFalse(answers)
    }

    func testAMacAwayFromHomeIsOfflineWithinItsPatience() async throws {
        // Its last address never answers (TEST-NET-1, RFC 5737), as the
        // player's home seen from anywhere else.
        var server = CartoucheStorageServer(kind: .mac, name: "Mac de test", host: "192.0.2.1", port: Int(CartoucheBridge.port))
        server.macID = UUID().uuidString
        let secret = Data(repeating: 9, count: 32).base64EncodedString()
        let started = Date()
        do {
            _ = try await CartoucheMacStorage.connect(server, secret: secret, settings: settings())
            XCTFail("signed in to an address that never answers")
        } catch {
            XCTAssertTrue(error is CartoucheStorageOffline, String(describing: error))
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacOffline("Mac de test"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started),
                          CartoucheMacStorage.lastAddressPatience + CartoucheMacStorage.lookupPatience + 2)
    }

    // MARK: Through Tailscale

    /// SERVER away from home: its last address never answers (TEST-NET-1,
    /// RFC 5737), and the test's loopback stands for its address in the
    /// tailnet, where the fake Mac listens.
    private func awayFromHome(_ server: CartoucheStorageServer) -> CartoucheStorageServer {
        var away = server
        away.host = "192.0.2.1"
        away.tailnet = ["127.0.0.1"]
        return away
    }

    func testAMacAwayFromHomeIsReachedThroughTailscale() async throws {
        let (server, secret) = try await pair()
        let away = awayFromHome(server)
        let started = Date()
        let remote = try await CartoucheMacStorage.connect(away, secret: secret, settings: settings(), tailscale: true)
        XCTAssertLessThan(Date().timeIntervalSince(started), CartoucheMacStorage.lastAddressPatience,
                          "through Tailscale, without waiting for the last address to give up, nor for Bonjour")
        let top = try await remote.list("")
        XCTAssertEqual(top.map(\.name), ["Games", "Saves"])
        await remote.disconnect()
        let answers = await CartoucheMacStorage.answers(away, tailscale: true)
        XCTAssertTrue(answers, "it takes a connection through Tailscale")
    }

    func testWithTailscaleOffTheMacAwayFromHomeIsOfflineAndSaysToTurnItOn() async throws {
        let (server, secret) = try await pair()
        let away = awayFromHome(server)
        let started = Date()
        do {
            _ = try await CartoucheMacStorage.connect(away, secret: secret, settings: settings(), tailscale: false)
            XCTFail("tried the Mac's address in the tailnet with Tailscale off")
        } catch {
            // As LocalDevVPN leaves it: offline, no report, and how to
            // reach the Mac again.
            XCTAssertTrue(error is CartoucheStorageOffline, String(describing: error))
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacOfflineTailscaleOff(server.name))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started),
                          CartoucheMacStorage.lastAddressPatience + CartoucheMacStorage.lookupPatience + 2)
    }

    func testTheMacsAddressesInTheTailnetAreKeptAsItTellsThem() async throws {
        // Cartouche Builder tells them with Tailscale on the Mac; the iPhone
        // keeps them beside the Mac's last address, for away from home.
        let (server, secret) = try await pair()
        mac.tell(tailnet: ["100.101.102.103", "fd7a:115c:a1e0::1"])
        let kept = settings()
        kept.save(server, secret: nil)
        let remote = try await CartoucheMacStorage.connect(server, secret: secret, settings: kept, tailscale: false)
        await remote.disconnect()
        let now = try XCTUnwrap(kept.server(server.id))
        XCTAssertEqual(now.host, "127.0.0.1", "its last address stays")
        XCTAssertEqual(now.port, mac.port)
        XCTAssertEqual(now.tailnet, ["100.101.102.103", "fd7a:115c:a1e0::1"])
    }

    func testAnIPAAndSavesGoBothWays() async throws {
        let remote = try await signIn()
        // More than a read ahead (4 MiB), and not a whole number of them.
        var ipa = Data(count: (9 << 20) + 12345)
        for index in stride(from: 0, to: ipa.count, by: 4093) {
            ipa[index] = UInt8(truncatingIfNeeded: index / 4093)
        }
        let path = "Games/Test [0100000000010000].ipa"
        try await remote.write(ipa, to: path)
        XCTAssertEqual(mac.entry(path), .file(ipa))
        let listed = try await remote.list("Games")
        XCTAssertEqual(listed.map(\.name), ["Test [0100000000010000].ipa"])
        XCTAssertEqual(listed.first?.size, UInt64(ipa.count))
        XCTAssertEqual(listed.first?.isFolder, false)

        let source = try await remote.open(path)
        XCTAssertEqual(source.size, UInt64(ipa.count))
        let middle = try await source.read(at: 5 << 20, count: 1000)
        XCTAssertEqual(middle, ipa.subdata(in: (5 << 20) ..< (5 << 20) + 1000))
        let end = try await source.read(at: UInt64(ipa.count - 10), count: 100)
        XCTAssertEqual(end, ipa.suffix(10))
        let whole = try await source.read(at: 0, count: ipa.count)
        XCTAssertEqual(whole, ipa)

        try await remote.makeFolders("Saves/0100000000010000")
        try await remote.write(Data("save".utf8), to: "Saves/0100000000010000/1.zip")
        let save = try await remote.read("Saves/0100000000010000/1.zip")
        XCTAssertEqual(save, Data("save".utf8))
        // A copy given up leaves nothing.
        let upload = try await remote.create("Saves/0100000000010000/2.zip", size: 3)
        try await upload.write(Data("abc".utf8))
        await upload.cancel()
        let copies = try await remote.list("Saves/0100000000010000")
        XCTAssertEqual(copies.map(\.name), ["1.zip"])
        try await remote.delete("Saves/0100000000010000/1.zip")
        let left = try await remote.list("Saves/0100000000010000")
        XCTAssertEqual(left, [])

        let canWriteSaves = try await remote.canWrite("Saves")
        XCTAssertTrue(canWriteSaves)
        let canWriteTop = try await remote.canWrite("")
        XCTAssertFalse(canWriteTop)
        let free = try await remote.freeSpace()
        XCTAssertEqual(free, 1 << 40)
        await remote.disconnect()
    }

    func testWhatTheMacSaysIsInThePlayersWords() async throws {
        let remote = try await signIn()
        do {
            _ = try await remote.open("Games/Nothing.ipa")
            XCTFail("a file that is not there")
        } catch {
            // Its kind stays for the report.
            XCTAssertEqual((error as NSError).domain, "CartoucheBridge.notFound")
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacNotFound("Nothing.ipa"))
        }
        do {
            try await remote.makeFolder("Games")
            XCTFail("a folder made twice")
        } catch {
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacExists("Games"))
        }
        do {
            _ = try await remote.open("Games")
            XCTFail("a folder opened as a file")
        } catch {
            XCTAssertEqual((error as NSError).domain, "CartoucheBridge.notFound")
        }
        await remote.disconnect()
    }
}
