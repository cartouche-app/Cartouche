//
//  BridgeConnectionsTests.swift
//  BuilderKitTests
//
//  The player's connections to their storage, as a paired iPhone gives
//  them to the Mac and takes the Mac's (BridgeServer's
//  BridgeConnectionsSource, CartoucheConnections.swift): a Mac that takes
//  none says so in its info and refuses them, the session going on; one
//  that does takes the iPhone's, with their secrets, and gives its own,
//  each side then keeping the same, and hears of the folders the player
//  chose on the iPhone. What Cartouche does with them is
//  tested with Cartouche's storage (launcher/StorageTests, MacBridgeTests).
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

/// The app, as it keeps the connections of the console's Storage page:
/// what the iPhones gave, in order, and the Mac's.
@MainActor
private final class Connections: BridgeConnectionsSource {
    var kept: [CartoucheConnection] = []
    var given: [[CartoucheConnection]] = []
    var told: [CartoucheChosenFolders?] = []

    func bridgeConnections(_ theirs: [CartoucheConnection], places: CartoucheChosenFolders?) -> [CartoucheConnection] {
        given.append(theirs)
        told.append(places)
        kept = CartoucheConnections.merged(kept, theirs)
        return kept
    }
}

final class BridgeConnectionsTests: XCTestCase {
    private var folder: URL!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        for name in ["Jeux", "Saves"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func server() -> BridgeServer {
        let server = BridgeServer(devices: BridgeDevices(url: folder.appendingPathComponent("bridge.json")), name: "Mac de test")
        server.roots = BridgeRoots(games: folder.appendingPathComponent("Jeux", isDirectory: true),
                                   saves: folder.appendingPathComponent("Saves", isDirectory: true))
        return server
    }

    /// A session of a paired iPhone with SERVER: its client, and the task
    /// that serves it until it closes.
    private func session(_ server: BridgeServer) async throws -> (CartoucheBridgeClient, Task<Void, Never>) {
        let key = Data(repeating: 7, count: 32)
        let device = UUID().uuidString
        server.devices.add(id: device, name: "iPhone de test", key: key)
        let (phoneSide, macSide) = MemoryPipe.pair()
        let serving = Task { await server.open(macSide) }
        let channel = try await CartoucheBridgeHandshake.client(phoneSide, device: device, key: key, mac: server.devices.macID)
        return (CartoucheBridgeClient(channel: channel, address: nil), serving)
    }

    func testAMacThatTakesNoConnectionsSaysSo() async throws {
        let server = server()
        let (client, serving) = try await session(server)
        let info = try await client.info()
        XCTAssertEqual(info.hasConnections, false)
        do {
            _ = try await client.connections([])
            XCTFail("connections to a Mac that takes none")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error.kind, .notFound)
        }
        // The session goes on.
        let top = try await client.list("")
        XCTAssertEqual(top.map(\.name), [CartoucheBridge.gamesFolder, CartoucheBridge.savesFolder])
        client.close()
        await serving.value
    }

    func testTheIPhonesConnectionsForTheMacs() async throws {
        let server = server()
        let bucket = CartoucheConnection(id: UUID(), kind: "s3", name: "Bucket", host: "s3.eu-west-3.amazonaws.com", username: "AKIA",
                                         share: "saves", secret: "secret key", changed: now)
        let connections = await MainActor.run { () -> Connections in
            let connections = Connections()
            connections.kept = [bucket]
            return connections
        }
        server.connections = connections
        let (client, serving) = try await session(server)
        let info = try await client.info()
        XCTAssertEqual(info.hasConnections, true)

        let nas = CartoucheConnection(id: UUID(), kind: "smb", name: "NAS", host: "192.168.1.2", username: "games", share: "Games",
                                      secret: "password", changed: now)
        var removed = CartoucheConnection(id: UUID(), kind: "ftp", name: "Old", changed: now)
        removed.removed = true
        let theirs = try await client.connections([nas, removed])
        // The Mac's, the iPhone's among them, with their secrets.
        XCTAssertEqual(Set(theirs.map(\.id)), [bucket.id, nas.id, removed.id])
        XCTAssertEqual(theirs.first { $0.id == bucket.id }?.secret, "secret key")
        XCTAssertEqual(theirs.first { $0.id == nas.id }?.secret, "password")
        XCTAssertEqual(theirs.first { $0.id == removed.id }?.removed, true)
        let given = await MainActor.run { connections.given }
        XCTAssertEqual(given, [[nas, removed]])
        // Told no folder: an iPhone older than that.
        let toldNone = await MainActor.run { connections.told }
        XCTAssertEqual(toldNone, [nil])
        // The iPhone keeps the same.
        XCTAssertEqual(Set(CartoucheConnections.merged([nas, removed], theirs, now: now).map(\.id)), Set(theirs.map(\.id)))

        // Without connections: refused, and the session goes on.
        do {
            _ = try await client.call(CartoucheBridgeRequest(.connections))
            XCTFail("connections without any")
        } catch let error as CartoucheBridgeError {
            XCTAssertEqual(error.kind, .protocolError)
        }
        let again = try await client.connections([])
        XCTAssertEqual(Set(again.map(\.id)), Set(theirs.map(\.id)))

        // The folders chosen on the iPhone, with the connections.
        let places = CartoucheChosenFolders(games: .init(connection: nil, path: "", chosen: now),
                                            saves: .init(connection: nas.id, path: "Cartouche/Saves", chosen: now))
        _ = try await client.connections([nas], places: places)
        let told = await MainActor.run { connections.told }
        XCTAssertEqual(told.last, places)
        client.close()
        await serving.value
    }
}
