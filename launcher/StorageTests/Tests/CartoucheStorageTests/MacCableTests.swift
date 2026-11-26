//
//  MacCableTests.swift
//  CartoucheStorageTests
//
//  The player's Mac through the cable, as the app reaches it
//  (CartoucheStorageMac.swift, CartoucheCableListener.swift): Cartouche
//  listens on the loopback, and the fake Mac links to it there as
//  Cartouche Builder does through usbmuxd once the iPhone is plugged in
//  (the test's loopback stands in for usbmuxd). Pairing, signing in and
//  files through the cable alone, with no network to find the Mac on; the
//  cable first when both reach it; the network again once unplugged; an
//  install that says the way of its own connection, whatever another
//  sign-in goes through; and offline, saying to plug it in, when neither
//  does. The Mac's side of the cable is in builder/mac's tests
//  (BridgeCableTests).
//

import Foundation
import Network
import XCTest
@testable import CartoucheStorage

final class MacCableTests: XCTestCase {
    private var mac: FakeMac!
    private var listener: CartoucheCableListener!
    private var port: UInt16 = 0

    override func setUp() async throws {
        mac = FakeMac(name: "Mac par câble")
        // A port of the test's own, not Cartouche's.
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

    /// Settings of their own, which keep nothing.
    private func settings() -> CartoucheStorageSettings {
        CartoucheStorageSettings(defaults: UserDefaults(suiteName: "MacCableTests." + UUID().uuidString)!)
    }

    private func plugIn() async throws {
        try await mac.plug(into: port)
        let macID = mac.macID
        await eventually("linked through the cable") { CartoucheCableLinks.shared.isLinked(macID) }
    }

    /// The Mac as the Storage page lists it once the iPhone is plugged in.
    private var nearby: CartoucheNearbyMac {
        CartoucheMacBrowser.merged(bonjour: [], cable: CartoucheCableLinks.shared.macs).first { $0.macID == mac.macID }
            ?? CartoucheNearbyMac(name: mac.name, macID: mac.macID, endpoint: nil, cabled: true)
    }

    func testAnIPhonePluggedInPairsSignsInAndCopiesThroughTheCableAlone() async throws {
        // No network to find the Mac on: it does not even listen there.
        try await plugIn()
        XCTAssertTrue(nearby.cabled)
        XCTAssertNil(nearby.endpoint)
        XCTAssertEqual(nearby.name, "Mac par câble")

        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), with: nearby, deviceName: "iPhone de test") { _ in }
        XCTAssertEqual(paired.server.macID, mac.macID)
        XCTAssertEqual(paired.server.name, "Mac par câble")
        XCTAssertEqual(paired.server.host, "", "no address through the cable")
        XCTAssertEqual(mac.paired, [CartoucheMacStorage.deviceID(of: paired.server)])

        let started = Date()
        let remote = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings())
        XCTAssertLessThan(Date().timeIntervalSince(started), CartoucheMacStorage.lookupPatience,
                          "through the cable, without looking for the Mac on the network")
        let top = try await remote.list("")
        XCTAssertEqual(top.map(\.name), ["Games", "Saves"])
        let bytes = Data((0 ..< 300_000).map { UInt8($0 % 251) })
        let upload = try await remote.create("Games/Jeu [0100000000010000].ipa", size: UInt64(bytes.count))
        try await upload.write(bytes)
        try await upload.finish()
        let source = try await remote.open("Games/Jeu [0100000000010000].ipa")
        let read = try await source.read(at: 0, count: bytes.count)
        XCTAssertEqual(read, bytes)
        await remote.disconnect()
        XCTAssertGreaterThanOrEqual(mac.connectionsThroughCable, 2, "the pairing and the session went through the cable")

        let answers = await CartoucheStorageReach.answers(paired.server)
        XCTAssertTrue(answers, "it answers through the cable")
    }

    func testTheCableComesFirstWhenTheNetworkReachesTheMacToo() async throws {
        try await mac.start()
        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""),
                                                        at: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(mac.port))!),
                                                        name: "Mac par câble", deviceName: "iPhone de test") { _ in }
        XCTAssertEqual(paired.server.host, "127.0.0.1")
        try await plugIn()
        let remote = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings())
        _ = try await remote.list("")
        await remote.disconnect()
        XCTAssertEqual(mac.connectionsThroughCable, 1, "signed in through the cable, not at the last address")

        // Unplugged: the network again, at the last address.
        mac.unplug()
        let macID = mac.macID
        await eventually("unlinked") { !CartoucheCableLinks.shared.isLinked(macID) }
        let again = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings())
        _ = try await again.list("")
        await again.disconnect()
        XCTAssertEqual(mac.connectionsThroughCable, 1, "nothing more through the cable once unplugged")
    }

    /// An install reads its game on the network, and the iPhone is plugged
    /// in meanwhile: another sign-in to the Mac, such as the games folder's
    /// reading, goes through the cable, while the install's own connection
    /// stays on the network. The install's screen and game.installed's link
    /// say the network, as CartoucheGameActions.openStored notes the way of
    /// its own connection, not "cable" at the Wi-Fi's speed until Cartouche
    /// is opened again (issue #323).
    func testAnInstallOnTheNetworkSaysTheNetworkWhenAnotherSignInGoesThroughTheCable() async throws {
        try await mac.start()
        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""),
                                                        at: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(mac.port))!),
                                                        name: "Mac par câble", deviceName: "iPhone de test") { _ in }
        let id = paired.server.id
        let settings = settings()
        let bytes = Data((0 ..< 200_000).map { UInt8($0 % 251) })
        let upload = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings)
        let made = try await upload.create("Games/Jeu [0100000000010000].ipa", size: UInt64(bytes.count))
        try await made.write(bytes)
        try await made.finish()
        await upload.disconnect()

        // The install's connection, on the network: the cable is not in yet.
        let signedIn = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings)
        let install = try XCTUnwrap(signedIn as? CartoucheMacRemote)
        let link = install.link
        XCTAssertEqual(link, .network)
        // What CartoucheGameActions.openStored does with it.
        let network = await install.network()
        await MainActor.run { CartoucheMacStorage.note(link, network: network, of: id) }
        let game = try await install.open("Games/Jeu [0100000000010000].ipa")
        let first = try await game.read(at: 0, count: 100_000)
        XCTAssertEqual(first, Data(bytes.prefix(100_000)))
        let before = await MainActor.run { CartoucheMacStorage.links[id] }
        XCTAssertEqual(before, .network)

        // Plugged in meanwhile: another sign-in goes through the cable.
        try await plugIn()
        let other = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings)
        XCTAssertEqual((other as? CartoucheMacRemote)?.link, .cable)
        _ = try await other.list("Games")
        await other.disconnect()
        XCTAssertEqual(mac.connectionsThroughCable, 1, "the other sign-in went through the cable")

        // The game still comes on the network, and the install says so.
        let rest = try await game.read(at: 100_000, count: 100_000)
        XCTAssertEqual(rest, Data(bytes.suffix(100_000)))
        XCTAssertEqual(mac.connectionsThroughCable, 1, "the install's connection did not move to the cable")
        let shown = await MainActor.run { CartoucheMacStorage.links[id] }
        XCTAssertEqual(shown, .network, "the install's way, not the other sign-in's")
        XCTAssertEqual(CartoucheTransferWay.toMac(link: shown?.rawValue, network: network), .network(mac: network))
        await install.disconnect()

        // Opened again, now that the cable is in, the install's connection
        // goes through it, and the install says so.
        let reopened = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings)
        let again = try XCTUnwrap(reopened as? CartoucheMacRemote)
        let cable = again.link
        XCTAssertEqual(cable, .cable)
        await MainActor.run { CartoucheMacStorage.note(cable, network: nil, of: id) }
        let cabled = await MainActor.run { CartoucheMacStorage.links[id] }
        XCTAssertEqual(cabled, .cable)
        await again.disconnect()
    }

    func testUnpluggedAndOffTheNetworkTheMacIsOfflineAndSaysToPlugItIn() async throws {
        try await plugIn()
        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), with: nearby, deviceName: "iPhone de test") { _ in }
        mac.unplug()
        let macID = mac.macID
        await eventually("unlinked") { !CartoucheCableLinks.shared.isLinked(macID) }
        do {
            _ = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings(), tailscale: false)
            XCTFail("signed in to a Mac neither the cable nor the network reaches")
        } catch {
            XCTAssertTrue(error is CartoucheStorageOffline, String(describing: error))
            XCTAssertEqual(error.localizedDescription, CartoucheText.storageMacOffline("Mac par câble"))
            XCTAssertTrue(CartoucheText.storageMacOffline("Mac par câble").contains("cable"), "it says to plug the iPhone in")
        }
        let answers = await CartoucheStorageReach.answers(paired.server)
        XCTAssertFalse(answers)
    }

    func testAMacThatForgotThisIPhoneSaysSoThroughTheCable() async throws {
        try await plugIn()
        let paired = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), with: nearby, deviceName: "iPhone de test") { _ in }
        mac.forget(CartoucheMacStorage.deviceID(of: paired.server))
        do {
            _ = try await CartoucheMacStorage.connect(paired.server, secret: paired.secret, settings: settings())
            XCTFail("signed in to a Mac that forgot this iPhone")
        } catch {
            // Its own answer, not offline: the network would say the same.
            XCTAssertEqual((error as NSError).domain, "CartoucheBridge.notPaired")
        }
    }
}
