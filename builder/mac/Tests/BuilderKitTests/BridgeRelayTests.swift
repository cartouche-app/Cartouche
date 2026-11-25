//
//  BridgeRelayTests.swift
//  BuilderKitTests
//
//  A game of the iPhone's games folder on a NAS, read by this Mac for an
//  iPhone plugged into it and passed on through the cable (BridgeRelay.swift,
//  decision 162): only through the cable, only a NAS's, FTP's or SFTP's
//  file of a games folder the Mac keeps on that connection, only while the
//  Mac reaches the server on its Ethernet; the file read a piece ahead,
//  given up when its server fails, two at most open, all closed with the
//  session. Cartouche's side, against a Mac of its tests, is in
//  launcher/StorageTests (MacRelayTests); the console's connection to the
//  NAS is Cartouche's own code (CartoucheStorage.swift).
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

/// The player's NAS, as the console reaches it: its files, what was opened
/// and read, and closed.
private final class FakeNAS: BridgeRelaySource, @unchecked Sendable {
    let connection = UUID()
    private let lock = NSLock()
    private var place: BridgeRelayServer
    private var files: [String: Data]
    private var openedPaths: [String] = []
    private var readCount = 0
    private var closedCount = 0
    private var failing = false

    init(kind: String = "smb", port: Int? = nil, files: [String: Data]) {
        place = BridgeRelayServer(kind: kind, host: "192.168.1.2", port: port)
        self.files = files
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var opened: [String] { locked { openedPaths } }
    var reads: Int { locked { readCount } }
    var closed: Int { locked { closedCount } }
    /// The NAS goes away: every read fails from now on.
    func fail(_ on: Bool) { locked { failing = on } }

    func relayServer(_ connection: UUID) async -> BridgeRelayServer? {
        connection == self.connection ? locked { place } : nil
    }

    func relayOpen(_ connection: UUID, path: String) async throws -> any BridgeRelayFile {
        let bytes = try locked { () throws -> Data in
            openedPaths.append(path)
            guard let bytes = files[path] else { throw CartoucheBridgeError(.notFound, path) }
            return bytes
        }
        return File(nas: self, bytes: bytes)
    }

    fileprivate func read(_ bytes: Data, at offset: UInt64, count: Int) throws -> Data {
        try locked {
            readCount += 1
            if failing { throw CartoucheBridgeError(.failed, "the NAS went away") }
        }
        let start = Int(min(offset, UInt64(bytes.count)))
        return bytes.subdata(in: start ..< min(start + count, bytes.count))
    }

    fileprivate func closedOne() { locked { closedCount += 1 } }

    private final class File: BridgeRelayFile, @unchecked Sendable {
        let nas: FakeNAS
        let bytes: Data
        var size: UInt64 { UInt64(bytes.count) }

        init(nas: FakeNAS, bytes: Data) {
            self.nas = nas
            self.bytes = bytes
        }

        func read(at offset: UInt64, count: Int) async throws -> Data {
            try nas.read(bytes, at: offset, count: count)
        }

        func close() async { nas.closedOne() }
    }
}

/// How the Mac reaches a server, as the test says, and what it was asked.
private final class Route: @unchecked Sendable {
    private let lock = NSLock()
    private var network: CartoucheMacNetwork?
    private var askedPlaces: [String] = []

    init(_ medium: String?) {
        network = medium.map { CartoucheMacNetwork(medium: $0, band: "5") }
    }

    var asked: [String] {
        lock.lock()
        defer { lock.unlock() }
        return askedPlaces
    }

    /// The way to HOST and PORT, from synchronous code: an NSLock is not to
    /// be held across a suspension.
    func callAsFunction(_ host: String, _ port: Int) -> CartoucheMacNetwork? {
        lock.lock()
        defer { lock.unlock() }
        askedPlaces.append("\(host):\(port)")
        return network
    }
}

final class BridgeRelayTests: XCTestCase {
    private let path = "Jeux/Mario Kart World [0400C3F00006E000].ipa"
    private let bytes = Data((0 ..< 3_000_000).map { UInt8($0 % 251) })
    private var nas: FakeNAS!
    private var files: BridgeRelayFiles!
    private var reads: BridgeReads!

    override func setUp() {
        nas = FakeNAS(files: [path: bytes, "Saves/Mario Kart World.zip": Data("save".utf8),
                              "Jeux/Zelda [0100000000010000].ipa": Data("zelda".utf8),
                              "Jeux/Metroid [0100000000020000].ipa": Data("metroid".utf8)])
        files = BridgeRelayFiles()
        reads = BridgeReads()
    }

    /// The games folders the Mac keeps: Jeux on the NAS, and another
    /// connection's.
    private func folders() -> CartoucheChosenFolders {
        CartoucheChosenFolders(games: .init(connection: nas.connection, path: "Jeux", chosen: Date()),
                               saves: .init(connection: nas.connection, path: "Saves", chosen: Date()),
                               otherGames: [.init(connection: UUID(), path: "Autres", chosen: Date())])
    }

    private func ask(_ op: CartoucheBridgeRequest.Operation, _ path: String? = nil, at offset: UInt64 = 0, count: Int = 0,
                     connection: UUID? = nil, cable: Bool = true, route: Route = Route(CartoucheMacNetwork.ethernet),
                     source: BridgeRelaySource? = nil, folders: CartoucheChosenFolders? = nil) async -> (CartoucheBridgeResponse, Data) {
        let chosen = folders ?? self.folders()
        let request = CartoucheBridgeRequest(op, path: path ?? self.path, offset: offset, count: count, connection: connection ?? nas.connection)
        return await BridgeRelay.answer(request, cable: cable, source: source ?? nas, folders: { chosen },
                                        route: { route($0, $1) }, files: files, reads: reads)
    }

    func testAGameOfTheGamesFolderComesFromTheNASOnTheMacsEthernet() async throws {
        let route = Route(CartoucheMacNetwork.ethernet)
        let (stat, _) = await ask(.relayStat, route: route)
        XCTAssertNil(stat.error)
        XCTAssertEqual(stat.size, UInt64(bytes.count))
        XCTAssertEqual(stat.folder, false)
        XCTAssertEqual(route.asked, ["192.168.1.2:445"], "the way to the NAS's shared folders")

        var read = Data()
        while read.count < bytes.count {
            let (response, piece) = await ask(.relayRead, at: UInt64(read.count), count: CartoucheBridge.maxRead, route: route)
            XCTAssertNil(response.error)
            XCTAssertFalse(piece.isEmpty)
            read.append(piece)
        }
        XCTAssertEqual(read, bytes)
        XCTAssertEqual(nas.opened, [path], "opened once, kept for its reads")
        XCTAssertNotNil(reads.last, "the window shows how fast it goes")
        let kept = await files.count
        XCTAssertEqual(kept, 1)
        await files.closeAll()
        XCTAssertEqual(nas.closed, 1)
    }

    func testOnTheMacsWiFiItIsNotPassedOn() async {
        for medium in [CartoucheMacNetwork.wifi, CartoucheMacNetwork.other, nil] {
            let (response, data) = await ask(.relayStat, route: Route(medium))
            XCTAssertEqual(response.error, .refused, "\(String(describing: medium)): the game would cross the Wi-Fi all the same")
            XCTAssertTrue(data.isEmpty)
        }
        XCTAssertEqual(nas.opened, [], "nothing read on the NAS")
    }

    func testOnTheNetworkItIsDenied() async {
        let route = Route(CartoucheMacNetwork.ethernet)
        let (response, _) = await ask(.relayStat, cable: false, route: route)
        XCTAssertEqual(response.error, .denied, "through the cable alone")
        let (read, data) = await ask(.relayRead, count: 100, cable: false, route: route)
        XCTAssertEqual(read.error, .denied)
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(route.asked, [])
        XCTAssertEqual(nas.opened, [])
    }

    func testNothingOutsideTheGamesFoldersOnThatConnection() async {
        let route = Route(CartoucheMacNetwork.ethernet)
        for outside in ["Saves/Mario Kart World.zip", "Jeux", "Jeux/../Saves/Mario Kart World.zip", "", "Autres/Jeu.ipa"] {
            let (response, _) = await ask(.relayStat, outside, route: route)
            XCTAssertEqual(response.error, .denied, outside)
        }
        // The games folder on another connection of the Mac's.
        var elsewhere = folders()
        elsewhere.games?.connection = UUID()
        let (other, _) = await ask(.relayStat, folders: elsewhere)
        XCTAssertEqual(other.error, .denied)
        // A Mac that keeps no folder.
        let (none, _) = await ask(.relayStat, folders: CartoucheChosenFolders())
        XCTAssertEqual(none.error, .denied)
        XCTAssertEqual(nas.opened, [])
        XCTAssertEqual(route.asked, [], "never asked the way")
    }

    func testAGameOfAnotherGamesFolderOnTheNASIsPassedOn() async {
        var two = folders()
        two.otherGames = [.init(connection: nas.connection, path: "Saves", chosen: Date())]
        let (response, _) = await ask(.relayStat, "Saves/Mario Kart World.zip", folders: two)
        XCTAssertNil(response.error, "a games folder too")
        XCTAssertEqual(response.size, 4)
    }

    func testABucketOrADriveIsNotPassedOn() async {
        for kind in ["s3", "drive", "mac", "files"] {
            nas = FakeNAS(kind: kind, files: [path: bytes])
            let route = Route(CartoucheMacNetwork.ethernet)
            let (response, _) = await ask(.relayStat, route: route)
            XCTAssertEqual(response.error, .refused, "\(kind): the internet brings it as fast to the iPhone")
            XCTAssertEqual(route.asked, [])
            XCTAssertEqual(nas.opened, [])
        }
    }

    func testTheWayIsAskedToTheServersOwnPort() async {
        for (kind, given, port) in [("sftp", 2222, 2222), ("sftp", nil, 22), ("ftp", nil, 21), ("smb", 1445, 1445)] as [(String, Int?, Int)] {
            nas = FakeNAS(kind: kind, port: given, files: [path: bytes])
            let route = Route(CartoucheMacNetwork.ethernet)
            let (response, _) = await ask(.relayStat, route: route)
            XCTAssertNil(response.error, kind)
            XCTAssertEqual(route.asked, ["192.168.1.2:\(port)"], kind)
        }
    }

    func testAConnectionTheMacDoesNotHaveIsNotFound() async {
        let (unknown, _) = await ask(.relayStat, connection: UUID())
        XCTAssertEqual(unknown.error, .notFound)
        let (missing, _) = await ask(.relayStat, "Jeux/Absent.ipa")
        XCTAssertEqual(missing.error, .notFound, "what the NAS answers")
        let request = CartoucheBridgeRequest(.relayStat, path: path)
        let (noConnection, _) = await BridgeRelay.answer(request, cable: true, source: nas, folders: { self.folders() },
                                                         route: { _, _ in nil }, files: files, reads: reads)
        XCTAssertEqual(noConnection.error, .protocolError)
    }

    func testAMacWithoutTheConsoleReadsNoNAS() async {
        let request = CartoucheBridgeRequest(.relayStat, path: path, connection: nas.connection)
        let (response, _) = await BridgeRelay.answer(request, cable: true, source: nil, folders: { self.folders() },
                                                     route: { _, _ in nil }, files: files, reads: reads)
        XCTAssertEqual(response.error, .notFound)
    }

    func testAFailedReadGivesTheFileUpAndTheNextOpensItAgain() async {
        _ = await ask(.relayStat)
        nas.fail(true)
        let (failed, data) = await ask(.relayRead, count: 1000)
        XCTAssertEqual(failed.error, .failed)
        XCTAssertTrue(data.isEmpty)
        let open = await files.count
        XCTAssertEqual(open, 0, "its connection given up")
        XCTAssertEqual(nas.closed, 1)

        nas.fail(false)
        let (again, piece) = await ask(.relayRead, at: 1000, count: 1000)
        XCTAssertNil(again.error)
        XCTAssertEqual(piece, bytes.subdata(in: 1000 ..< 2000))
        XCTAssertEqual(nas.opened, [path, path], "opened again")
    }

    func testTheNextPieceIsReadWhileThisOneGoes() async throws {
        _ = await ask(.relayStat)
        let (first, _) = await ask(.relayRead, count: 1000)
        XCTAssertNil(first.error)
        let end = Date().addingTimeInterval(5)
        while nas.reads < 2, Date() < end {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(nas.reads, 2, "the piece after it, read ahead")
        let (second, piece) = await ask(.relayRead, at: 1000, count: 1000)
        XCTAssertNil(second.error)
        XCTAssertEqual(piece, bytes.subdata(in: 1000 ..< 2000))
    }

    func testTwoFilesAtMostStayOpenAndAllCloseWithTheSession() async {
        for game in [path, "Jeux/Zelda [0100000000010000].ipa", "Jeux/Metroid [0100000000020000].ipa"] {
            let (response, _) = await ask(.relayStat, game)
            XCTAssertNil(response.error, game)
        }
        let open = await files.count
        XCTAssertEqual(open, BridgeRelayFiles.most)
        XCTAssertEqual(nas.closed, 1, "the oldest closed")
        // The one given up opens again for its reads.
        let (read, data) = await ask(.relayRead, count: 10)
        XCTAssertNil(read.error)
        XCTAssertEqual(data, bytes.prefix(10))
        XCTAssertEqual(nas.opened.filter { $0 == path }.count, 2)
        // Its stat again: opened anew, the one before closed.
        _ = await ask(.relayStat)
        XCTAssertEqual(nas.opened.filter { $0 == path }.count, 3)
        await files.closeAll()
        XCTAssertEqual(nas.closed, nas.opened.count, "every one closed")
    }

    // MARK: The Mac's info

    func testInfoSaysSoOnlyToASessionOfTheCableOfAMacThatPassesOn() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = BridgeServer(devices: BridgeDevices(url: folder.appendingPathComponent("bridge.json")), name: "Mac de test")
        let info = CartoucheBridgeRequest(.info)
        XCTAssertNil(Session(server: server, peer: "iphone", cable: true).handle(info, body: Data()).0.relays, "no console")
        server.relay = nas
        XCTAssertEqual(Session(server: server, peer: "iphone", cable: true).handle(info, body: Data()).0.relays, true)
        XCTAssertNil(Session(server: server, peer: "iphone", cable: false).handle(info, body: Data()).0.relays, "on the network")
        // A relay asked of the session itself, as no server would.
        let (stat, _) = Session(server: server, peer: "iphone", cable: true).handle(CartoucheBridgeRequest(.relayStat, path: path,
                                                                                                           connection: nas.connection),
                                                                                    body: Data())
        XCTAssertEqual(stat.error, .notFound)
        XCTAssertEqual(nas.opened, [])
    }
}
