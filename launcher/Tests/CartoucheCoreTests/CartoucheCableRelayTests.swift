//
//  CartoucheCableRelayTests.swift
//  CartoucheCoreTests
//
//  What the Mac reads for an iPhone plugged into it, and passes on through
//  the cable (CartoucheBridgeCable.swift's CartoucheCableRelay, decision
//  162): a NAS's file alone, of a games folder alone, on the Mac's
//  Ethernet alone; read a piece ahead (CartoucheReadingAhead), one piece at
//  a time on the server. The requests that carry it (relayStat, relayRead)
//  and the info that says the Mac does it (relays).
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheCableRelayTests: XCTestCase {
    // MARK: What the Mac reads

    func testOnlyAServerOfTheLocalNetworkIsRead() {
        XCTAssertEqual(CartoucheCableRelay.kinds, ["smb", "ftp", "sftp"])
        XCTAssertEqual(CartoucheCableRelay.port(of: "smb", given: nil), 445)
        XCTAssertEqual(CartoucheCableRelay.port(of: "ftp", given: nil), 21)
        XCTAssertEqual(CartoucheCableRelay.port(of: "sftp", given: nil), 22)
        XCTAssertEqual(CartoucheCableRelay.port(of: "smb", given: 1445), 1445, "the port the player gave")
        XCTAssertEqual(CartoucheCableRelay.port(of: "sftp", given: 0), 22, "none that a server could take")
        // The internet brings a bucket or a Drive as fast either way; the
        // Mac's own games folder already comes through the cable.
        for kind in ["s3", "drive", "mac", "folder", "webdav"] {
            XCTAssertNil(CartoucheCableRelay.port(of: kind, given: 443), kind)
        }
    }

    func testOnlyTheMacsEthernetPassesAGameOn() {
        XCTAssertTrue(CartoucheCableRelay.relays(over: CartoucheMacNetwork(medium: CartoucheMacNetwork.ethernet)))
        // On its Wi-Fi, even at 5 GHz, the game would cross the Wi-Fi all
        // the same, then the cable (Ad, 2026-11-25).
        XCTAssertFalse(CartoucheCableRelay.relays(over: CartoucheMacNetwork(medium: CartoucheMacNetwork.wifi, band: "5")))
        XCTAssertFalse(CartoucheCableRelay.relays(over: CartoucheMacNetwork(medium: CartoucheMacNetwork.wifi, band: "6")))
        XCTAssertFalse(CartoucheCableRelay.relays(over: CartoucheMacNetwork(medium: CartoucheMacNetwork.other)), "Tailscale or a VPN")
        XCTAssertFalse(CartoucheCableRelay.relays(over: CartoucheMacNetwork(medium: CartoucheMacNetwork.cable)))
        XCTAssertFalse(CartoucheCableRelay.relays(over: nil), "a server the Mac did not reach")
    }

    func testTheGamesFoldersOnTheConnectionAlone() {
        let nas = UUID(), other = UUID()
        let chosen = CartoucheChosenFolders(
            games: .init(connection: nas, path: "Jeux", chosen: Date()),
            saves: .init(connection: nas, path: "Sauvegardes", chosen: Date()),
            otherGames: [.init(connection: other, path: "Ailleurs", chosen: Date()),
                         .init(connection: nas, path: "Jeux/Anciens", chosen: Date())])
        XCTAssertEqual(CartoucheCableRelay.gamesFolders(on: nas, in: chosen), ["Jeux", "Jeux/Anciens"], "never the saves folder")
        XCTAssertEqual(CartoucheCableRelay.gamesFolders(on: other, in: chosen), ["Ailleurs"])
        XCTAssertEqual(CartoucheCableRelay.gamesFolders(on: UUID(), in: chosen), [])
        XCTAssertEqual(CartoucheCableRelay.gamesFolders(on: nas, in: nil), [], "a Mac that keeps no folder")
        // The games folder on the iPhone alone, which the Mac cannot see.
        let picked = CartoucheChosenFolders(games: .init(connection: nil, path: "Jeux", chosen: Date()))
        XCTAssertEqual(CartoucheCableRelay.gamesFolders(on: nas, in: picked), [])
    }

    func testOnlyAFileOfAGamesFolder() {
        let folders = ["Jeux"]
        XCTAssertTrue(CartoucheCableRelay.holds(folders, path: "Jeux/Mario Kart World [0400C3F00006E000].ipa"))
        XCTAssertTrue(CartoucheCableRelay.holds(folders, path: "Jeux/Switch/Jeu.ipa"), "in a folder of it")
        XCTAssertTrue(CartoucheCableRelay.holds(folders, path: "/Jeux//Jeu.ipa"), "as the paths are joined")
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "Jeux"), "the folder itself")
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "Sauvegardes/Jeu.zip"))
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "Jeux2/Jeu.ipa"), "a folder whose name starts the same")
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "jeux/Jeu.ipa"), "as the iPhone listed it")
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "Jeux/../prod.keys"))
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: "Jeux/./Jeu.ipa"))
        XCTAssertFalse(CartoucheCableRelay.holds(folders, path: ""))
        XCTAssertFalse(CartoucheCableRelay.holds([], path: "Jeux/Jeu.ipa"), "no games folder there")
        // A games folder at the root of the share holds all of it.
        XCTAssertTrue(CartoucheCableRelay.holds([""], path: "Jeu.ipa"))
        XCTAssertTrue(CartoucheCableRelay.holds(["Autre", "Jeux/Anciens"], path: "Jeux/Anciens/Jeu.ipa"))
        XCTAssertFalse(CartoucheCableRelay.holds(["Jeux/Anciens"], path: "Jeux/Jeu.ipa"))
    }

    // MARK: The requests

    func testTheRequestsSayTheConnectionAndTheInfoThatTheMacPassesOn() throws {
        let nas = UUID()
        let asked = CartoucheBridgeRequest(.relayRead, path: "Jeux/Jeu.ipa", offset: 8, count: 4, connection: nas)
        let (request, _) = try CartoucheBridgeMessage.decode(CartoucheBridgeRequest.self,
                                                              from: try CartoucheBridgeMessage.encode(asked, body: Data()))
        XCTAssertEqual(request, asked)
        XCTAssertEqual(request.connection, nas)
        XCTAssertTrue(request.op.isRelay)
        XCTAssertTrue(CartoucheBridgeRequest.Operation.relayStat.isRelay)
        XCTAssertFalse(CartoucheBridgeRequest.Operation.read.isRelay)
        XCTAssertFalse(CartoucheBridgeRequest.Operation.relayRead.isBuilds)
        // Nothing of it in another request.
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(CartoucheBridgeRequest(.read, path: "Games/x"))) as? [String: Any])
        XCTAssertNil(plain["connection"])

        var told = CartoucheBridgeResponse()
        told.relays = true
        let (info, _) = try CartoucheBridgeMessage.decode(CartoucheBridgeResponse.self,
                                                           from: try CartoucheBridgeMessage.encode(told, body: Data()))
        XCTAssertEqual(info.relays, true)
        // A Cartouche for Mac 0.8.0 says nothing: the iPhone never asks it.
        let (older, _) = try CartoucheBridgeMessage.decode(CartoucheBridgeResponse.self,
                                                            from: try CartoucheBridgeMessage.encode(CartoucheBridgeResponse(), body: Data()))
        XCTAssertNil(older.relays)
    }

    // MARK: Read a piece ahead

    func testThePieceAfterComesWhileThisOneGoes() async throws {
        let file = Data((0 ..< 100).map { UInt8($0) })
        let server = FakeServer(file)
        let reading = CartoucheReadingAhead(size: UInt64(file.count)) { try await server.read(at: $0, count: $1) }
        var read = Data()
        while read.count < file.count {
            read.append(try await reading.read(at: UInt64(read.count), count: 30))
        }
        XCTAssertEqual(read, file)
        let asked = await server.asked
        XCTAssertEqual(asked.map(\.offset), [0, 30, 60, 90], "each piece once, the next asked as one goes")
        XCTAssertEqual(asked.map(\.count), [30, 30, 30, 10], "nothing past the end")
        let hits = await reading.hits
        XCTAssertEqual(hits, 3, "the pieces after the first were read ahead")
        let most = await server.most
        XCTAssertEqual(most, 1, "one read at a time on the server")
        // Nothing read ahead past the end of the file.
        let beyond = try await reading.read(at: 100, count: 10)
        XCTAssertTrue(beyond.isEmpty)
    }

    func testAReadElsewhereLetsThePieceAheadEndFirst() async throws {
        let file = Data((0 ..< 200).map { UInt8($0 % 256) })
        let server = FakeServer(file, delay: 20_000_000)
        let reading = CartoucheReadingAhead(size: UInt64(file.count)) { try await server.read(at: $0, count: $1) }
        let first = try await reading.read(at: 0, count: 50)
        XCTAssertEqual(first, file.subdata(in: 0 ..< 50))
        // The zip's central directory, at the end, while 50 ... 100 comes.
        let end = try await reading.read(at: 180, count: 20)
        XCTAssertEqual(end, file.subdata(in: 180 ..< 200))
        let back = try await reading.read(at: 50, count: 50)
        XCTAssertEqual(back, file.subdata(in: 50 ..< 100))
        let most = await server.most
        XCTAssertEqual(most, 1, "the piece ahead ended before the next read began")
    }

    func testAShorterOrLongerReadTakesThePieceAheadToo() async throws {
        let file = Data((0 ..< 100).map { UInt8($0) })
        let server = FakeServer(file)
        let reading = CartoucheReadingAhead(size: UInt64(file.count)) { try await server.read(at: $0, count: $1) }
        _ = try await reading.read(at: 0, count: 20)
        let shorter = try await reading.read(at: 20, count: 5)
        XCTAssertEqual(shorter, file.subdata(in: 20 ..< 25))
        let longer = try await reading.read(at: 25, count: 30)
        XCTAssertEqual(longer, file.subdata(in: 25 ..< 55), "the piece ahead, and the rest of it asked")
        let hits = await reading.hits
        XCTAssertEqual(hits, 2)
    }

    func testAPieceAheadThatFailedFailsTheReadThatTakesIt() async throws {
        let file = Data(repeating: 7, count: 40)
        let server = FakeServer(file)
        let reading = CartoucheReadingAhead(size: UInt64(file.count)) { try await server.read(at: $0, count: $1) }
        _ = try await reading.read(at: 0, count: 10)
        await server.fail(from: 10)
        do {
            _ = try await reading.read(at: 10, count: 10)
            XCTFail("the server's failure was lost")
        } catch {
            XCTAssertEqual(error as? FakeServer.Failed, FakeServer.Failed())
        }
    }

    func testClosingEndsThePieceAhead() async throws {
        let file = Data(repeating: 1, count: 40)
        let server = FakeServer(file, delay: 50_000_000)
        let reading = CartoucheReadingAhead(size: UInt64(file.count)) { try await server.read(at: $0, count: $1) }
        _ = try await reading.read(at: 0, count: 10)
        await reading.close()
        let busy = await server.busy
        XCTAssertEqual(busy, 0, "nothing reads on the connection about to close")
    }
}

/// A file on a server, read one request after the other, as SMB's are.
private actor FakeServer {
    struct Failed: Error, Equatable {}

    private let file: Data
    private let delay: UInt64
    private(set) var asked: [(offset: UInt64, count: Int)] = []
    private(set) var busy = 0
    private(set) var most = 0
    private var failingFrom: UInt64?

    init(_ file: Data, delay: UInt64 = 1_000_000) {
        self.file = file
        self.delay = delay
    }

    func fail(from offset: UInt64) {
        failingFrom = offset
    }

    func read(at offset: UInt64, count: Int) async throws -> Data {
        asked.append((offset, count))
        busy += 1
        most = max(most, busy)
        defer { busy -= 1 }
        try? await Task.sleep(nanoseconds: delay)
        if let failingFrom, offset >= failingFrom { throw Failed() }
        let start = Int(offset)
        let end = min(start + count, file.count)
        return start < end ? file.subdata(in: start ..< end) : Data()
    }
}
