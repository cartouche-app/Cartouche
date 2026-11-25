//
//  MacRelayTests.swift
//  CartoucheStorageTests
//
//  A game of the games folder on a NAS, read through the player's Mac this
//  iPhone is plugged into (CartoucheStorageMac.swift, relayed; decision
//  162): the fake Mac links to Cartouche on the loopback as Cartouche
//  Builder does through usbmuxd, and reads the NAS's files from memory,
//  on its Ethernet or on its Wi-Fi. Through the cable only, a Mac on its
//  Ethernet only, a NAS only; never asked of a Mac too old to know it. The
//  Mac's side is in builder/mac's tests (BridgeRelayTests).
//

import Foundation
import Network
import XCTest
@testable import CartoucheStorage

final class MacRelayTests: XCTestCase {
    private var mac: FakeMac!
    private var listener: CartoucheCableListener!
    private var port: UInt16 = 0
    /// The player's NAS, as the iPhone's settings have it.
    private let nas = CartoucheStorageServer(kind: .smb, name: "NAS")
    private let path = "Jeux/Jeu [0100000000010000].ipa"
    private let bytes = Data((0 ..< 3_000_000).map { UInt8($0 % 253) })

    override func setUp() async throws {
        mac = FakeMac(name: "Mac mini")
        for _ in 0 ..< 20 {
            port = UInt16.random(in: 49_152 ... 65_000)
            listener = CartoucheCableListener(port: port)
            if await listener.start() { return }
        }
        XCTFail("no port to listen on")
    }

    override func tearDown() async throws {
        mac.unplug()
        mac.stop()
        listener.stop()
        let macID = mac.macID
        await eventually("unlinked") { !CartoucheCableLinks.shared.isLinked(macID) }
    }

    private func eventually(_ what: String, within seconds: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end {
                XCTFail("never: \(what)")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func settings() -> CartoucheStorageSettings {
        CartoucheStorageSettings(defaults: UserDefaults(suiteName: "MacRelayTests." + UUID().uuidString)!)
    }

    /// The iPhone plugged in, and paired through the cable.
    private func pluggedAndPaired() async throws -> (server: CartoucheStorageServer, secret: String) {
        try await mac.plug(into: port)
        let macID = mac.macID
        await eventually("linked through the cable") { CartoucheCableLinks.shared.isLinked(macID) }
        let nearby = CartoucheMacBrowser.merged(bonjour: [], cable: CartoucheCableLinks.shared.macs).first { $0.macID == macID }
            ?? CartoucheNearbyMac(name: mac.name, macID: macID, endpoint: nil, cabled: true)
        return try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), with: nearby, deviceName: "iPhone de test") { _ in }
    }

    private func relayed(_ server: CartoucheStorageServer, through paired: (server: CartoucheStorageServer, secret: String)) async
        -> CartoucheMacStorage.Relayed? {
        await CartoucheMacStorage.relayed(path, on: server, through: [paired], settings: settings(), cable: .shared)
    }

    func testAGameOfTheNASComesThroughTheMacOnItsEthernet() async throws {
        let paired = try await pluggedAndPaired()
        mac.passOn([nas.id: [path: bytes]], ethernet: true)
        guard let relayed = await relayed(nas, through: paired) else {
            return XCTFail("the Mac did not pass the game on")
        }
        XCTAssertEqual(relayed.mac, "Mac mini")
        XCTAssertEqual(relayed.source.size, UInt64(bytes.count))
        var read = Data()
        while read.count < bytes.count {
            let piece = try await relayed.source.read(at: UInt64(read.count), count: 700_000)
            XCTAssertFalse(piece.isEmpty)
            read.append(piece)
        }
        XCTAssertEqual(read, bytes, "the NAS's bytes, as they are")
        XCTAssertGreaterThan(mac.relayReads, 0, "read through the Mac")
        await relayed.close()
    }

    func testAMacOnItsWiFiPassesNothingOnAndTheIPhoneReadsTheNASItself() async throws {
        let paired = try await pluggedAndPaired()
        mac.passOn([nas.id: [path: bytes]], ethernet: false)
        let relayed = await relayed(nas, through: paired)
        XCTAssertNil(relayed, "a Mac on its Wi-Fi: the game would cross the Wi-Fi all the same")
        XCTAssertEqual(mac.relayRequests, 1, "asked once, and it refused")
        XCTAssertEqual(mac.relayReads, 0)
    }

    func testUnpluggedNothingGoesThroughTheMac() async throws {
        let paired = try await pluggedAndPaired()
        mac.passOn([nas.id: [path: bytes]], ethernet: true)
        try await mac.start()
        mac.unplug()
        let macID = mac.macID
        await eventually("unlinked") { !CartoucheCableLinks.shared.isLinked(macID) }
        let before = mac.connectionsThroughCable
        let relayed = await relayed(nas, through: paired)
        XCTAssertNil(relayed, "through the cable alone")
        XCTAssertEqual(mac.relayRequests, 0)
        XCTAssertEqual(mac.connectionsThroughCable, before)
    }

    func testAMacTooOldIsNeverAsked() async throws {
        // Its info says nothing of it: a Cartouche for Mac 0.8.0 ends the
        // session on a request it does not know.
        let paired = try await pluggedAndPaired()
        let relayed = await relayed(nas, through: paired)
        XCTAssertNil(relayed)
        XCTAssertEqual(mac.relayRequests, 0, "never asked")
    }

    func testABucketOrADriveIsReadByTheIPhoneItself() async throws {
        let paired = try await pluggedAndPaired()
        let bucket = CartoucheStorageServer(kind: .s3, name: "Bucket")
        let drive = CartoucheStorageServer(kind: .drive, name: "Drive")
        mac.passOn([bucket.id: [path: bytes], drive.id: [path: bytes]], ethernet: true)
        let fromBucket = await relayed(bucket, through: paired)
        let fromDrive = await relayed(drive, through: paired)
        XCTAssertNil(fromBucket)
        XCTAssertNil(fromDrive)
        XCTAssertEqual(mac.relayRequests, 0, "the internet brings them as fast either way")
    }

    func testAFileTheMacDoesNotFindIsReadOnTheNAS() async throws {
        let paired = try await pluggedAndPaired()
        mac.passOn([nas.id: [:]], ethernet: true)
        let relayed = await relayed(nas, through: paired)
        XCTAssertNil(relayed)
        XCTAssertEqual(mac.relayRequests, 1)
    }
}
