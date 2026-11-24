//
//  BridgeNetworkTests.swift
//  BuilderKitTests
//
//  How an iPhone's connection reaches this Mac, which the bridge's info
//  tells it (BridgeNetwork.swift), the games it reads and how fast
//  (BridgeServer.sending), and what the iPhone page says of them, with the
//  advice when it is slow or the Mac on its 2.4\u{00A0}GHz Wi-Fi (decision 151).
//

import CartoucheCore
import Foundation
import Network
import XCTest
@testable import BuilderKit

final class BridgeNetworkTests: XCTestCase {
    private var folder: URL!
    private var games: URL!
    private var saves: URL!
    private var server: BridgeServer!

    override func setUpWithError() throws {
        let manager = FileManager.default
        folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        games = folder.appendingPathComponent("Jeux", isDirectory: true)
        saves = folder.appendingPathComponent("Saves", isDirectory: true)
        try manager.createDirectory(at: games, withIntermediateDirectories: true)
        try manager.createDirectory(at: saves.appendingPathComponent("0400C3F00006E000"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 3_000_000).write(to: games.appendingPathComponent("Mario Kart World [0400C3F00006E000].ipa"))
        try Data(repeating: 2, count: 3_000_000).write(to: saves.appendingPathComponent("0400C3F00006E000/save.zip"))
        server = BridgeServer(devices: BridgeDevices(url: folder.appendingPathComponent("bridge.json")), name: "Mac de test", usbmuxd: nil)
        server.roots = BridgeRoots(games: games, saves: saves)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: The connection's network

    func testTheInterfaceSaysTheNetwork() {
        let band: (String) -> String? = { $0 == "en0" ? "2.4" : nil }
        XCTAssertEqual(BridgeNetwork.network(type: .wifi, name: "en0", band: band), CartoucheMacNetwork(medium: "wifi", band: "2.4"))
        XCTAssertEqual(BridgeNetwork.network(type: .wifi, name: "en1", band: band), CartoucheMacNetwork(medium: "wifi"),
                       "a band CoreWLAN does not say")
        XCTAssertEqual(BridgeNetwork.network(type: .wiredEthernet, name: "en0", band: band), CartoucheMacNetwork(medium: "ethernet"),
                       "no band on Ethernet")
        // Tailscale's tunnel, whatever it rides on.
        XCTAssertEqual(BridgeNetwork.network(type: .other, name: "utun4", band: band), CartoucheMacNetwork(medium: "other"))
        XCTAssertEqual(BridgeNetwork.network(type: nil, name: nil, band: band), CartoucheMacNetwork(medium: "other"))
    }

    func testInfoTellsTheSessionsNetwork() {
        let onWiFi = Session(server: server, peer: "iphone",
                             reads: BridgeReads(network: { CartoucheMacNetwork(medium: "wifi", band: "2.4") }))
        let (info, _) = onWiFi.handle(CartoucheBridgeRequest(.info), body: Data())
        XCTAssertNil(info.error)
        XCTAssertEqual(info.network, CartoucheMacNetwork(medium: "wifi", band: "2.4"))
        // Through the cable.
        let cabled = Session(server: server, peer: "iphone", reads: BridgeReads(network: { CartoucheMacNetwork(medium: "cable") }))
        XCTAssertEqual(cabled.handle(CartoucheBridgeRequest(.info), body: Data()).0.network?.medium, "cable")
        // In memory, as the tests open them: nothing to say.
        XCTAssertNil(Session(server: server, peer: "iphone").handle(CartoucheBridgeRequest(.info), body: Data()).0.network)
    }

    func testTheNetworkSurvivesTheBridgesMessage() throws {
        var response = CartoucheBridgeResponse()
        response.network = CartoucheMacNetwork(medium: "wifi", band: "5")
        let (decoded, _) = try CartoucheBridgeMessage.decode(CartoucheBridgeResponse.self, from: CartoucheBridgeMessage.encode(response))
        XCTAssertEqual(decoded.network, CartoucheMacNetwork(medium: "wifi", band: "5"))
        // An older Mac's info says nothing of it.
        let older = try CartoucheBridgeMessage.decode(CartoucheBridgeResponse.self, from: CartoucheBridgeMessage.encode(CartoucheBridgeResponse()))
        XCTAssertNil(older.0.network)
    }

    // MARK: What the iPhones read

    func testOnlyTheGamesFolderCountsAsAGameSent() {
        let reads = BridgeReads()
        let session = Session(server: server, peer: "iphone", reads: reads)
        _ = session.handle(CartoucheBridgeRequest(.read, path: "Saves/0400C3F00006E000/save.zip", offset: 0, count: 1_000_000), body: Data())
        XCTAssertNil(reads.last, "a save is not a game")
        _ = session.handle(CartoucheBridgeRequest(.read, path: "Games/Mario Kart World [0400C3F00006E000].ipa", offset: 0, count: 1_000_000),
                           body: Data())
        XCTAssertNotNil(reads.last)
    }

    func testTheSpeedOfAGameOnItsWayAndHowItComes() {
        let reads = BridgeReads(network: { CartoucheMacNetwork(medium: "wifi", band: "2.4") })
        let start = Date()
        // 1 MB every quarter of a second: 4 MB/s, as a 2.4\u{00A0}GHz Wi-Fi gives.
        for step in 0 ... 40 { reads.add(1_000_000, at: start.addingTimeInterval(Double(step) * 0.25)) }
        let now = start.addingTimeInterval(10)
        XCTAssertEqual(reads.meter.speed(at: now) ?? 0, 4_000_000, accuracy: 1)
        XCTAssertEqual(reads.network(), CartoucheMacNetwork(medium: "wifi", band: "2.4"))
    }

    func testAnIPhoneSendsWhileItReadsAndNoLongerOnceItStopped() {
        // No session open: nothing on its way.
        XCTAssertEqual(server.sending(), [:])
        let start = Date()
        let installing = BridgeReads(network: { CartoucheMacNetwork(medium: "cable") })
        for step in 0 ... 40 { installing.add(4_000_000, at: start.addingTimeInterval(Double(step) * 0.25)) }
        // The same iPhone's other sessions: one that read nothing of the
        // games folder, its saves synced, and one that read a little of it,
        // its library looked at.
        let saving = BridgeReads(network: { CartoucheMacNetwork(medium: "cable") })
        let looking = BridgeReads(network: { CartoucheMacNetwork(medium: "cable") })
        for step in 0 ... 10 { looking.add(100_000, at: start.addingTimeInterval(Double(step))) }
        let now = start.addingTimeInterval(10)
        let sending = BridgeServer.sending(of: [("iphone", saving), ("iphone", installing), ("iphone", looking)], at: now)
        XCTAssertEqual(sending.count, 1)
        XCTAssertEqual(sending["iphone"]?.speed ?? 0, 16_000_000, accuracy: 1, "the session that installs, the fastest")
        XCTAssertEqual(sending["iphone"]?.network?.medium, "cable")
        // A read of 4 MB at 0.5 MB/s takes 8 seconds: still sending.
        XCTAssertEqual(BridgeServer.sending(of: [("iphone", installing)], at: now.addingTimeInterval(9)).count, 1)
        // Nothing read for longer: done, and the next read starts again.
        let later = now.addingTimeInterval(BridgeServer.sendingPatience + 1)
        XCTAssertEqual(BridgeServer.sending(of: [("iphone", installing)], at: later), [:])
        installing.add(4_000_000, at: later)
        installing.add(4_000_000, at: later.addingTimeInterval(1))
        XCTAssertNil(BridgeServer.sending(of: [("iphone", installing)], at: later.addingTimeInterval(1))["iphone"]?.speed,
                     "a new measure, not the minutes without a read")
    }

    // MARK: What the iPhone page says

    func testTheLineSaysHowFastAndHow() {
        let chosen = L10n.chosen
        L10n.use("fr")
        defer { L10n.use(chosen) }
        let slowBand = BridgeSendingWords(BridgeSending(speed: 3_140_000, network: CartoucheMacNetwork(medium: "wifi", band: "2.4")), slow: true)
        XCTAssertEqual(slowBand.line, "Envoie un jeu\u{00A0}: 3,1\u{00A0}Mo/s, par le Wi-Fi 2,4\u{00A0}GHz de ce Mac")
        XCTAssertEqual(slowBand.advice, "Ce Mac est sur le Wi-Fi 2,4\u{00A0}GHz, le plus lent\u{00A0}: un câble entre l’iPhone et ce Mac, ou le Wi-Fi 5\u{00A0}GHz, irait bien plus vite.")
        // The 2.4\u{00A0}GHz band, at once: before a speed is measured.
        let starting = BridgeSendingWords(BridgeSending(speed: nil, network: CartoucheMacNetwork(medium: "wifi", band: "2.4")), slow: false)
        XCTAssertEqual(starting.line, "Envoie un jeu, par le Wi-Fi 2,4\u{00A0}GHz de ce Mac")
        XCTAssertNotNil(starting.advice)
        // 5\u{00A0}GHz and fast: nothing to say.
        let fast = BridgeSendingWords(BridgeSending(speed: 41_000_000, network: CartoucheMacNetwork(medium: "wifi", band: "5")), slow: false)
        XCTAssertEqual(fast.line, "Envoie un jeu\u{00A0}: 41\u{00A0}Mo/s, par le Wi-Fi 5\u{00A0}GHz de ce Mac")
        XCTAssertNil(fast.advice)
        // The cable: never.
        let cable = BridgeSendingWords(BridgeSending(speed: 2_000_000, network: CartoucheMacNetwork(medium: "cable")), slow: true)
        XCTAssertEqual(cable.line, "Envoie un jeu\u{00A0}: 2,0\u{00A0}Mo/s, par câble")
        XCTAssertNil(cable.advice)
        // Slow through Tailscale: it goes over the internet.
        let tailnet = BridgeSendingWords(BridgeSending(speed: 2_000_000, network: CartoucheMacNetwork(medium: "other")), slow: true)
        XCTAssertEqual(tailnet.line, "Envoie un jeu\u{00A0}: 2,0\u{00A0}Mo/s, par Tailscale ou un VPN")
        XCTAssertEqual(tailnet.advice, "C’est lent\u{00A0}: par Tailscale, le jeu passe par internet. À la maison, sur le même Wi-Fi ou par câble, il irait bien plus vite.")
        // Slow on the Ethernet: the iPhone's own Wi-Fi.
        let wired = BridgeSendingWords(BridgeSending(speed: 2_000_000, network: CartoucheMacNetwork(medium: "ethernet")), slow: true)
        XCTAssertEqual(wired.advice, "C’est lent\u{00A0}: un câble entre l’iPhone et ce Mac, ou un Wi-Fi 5\u{00A0}GHz pour les deux, irait bien plus vite.")
    }

    func testTheLineInEnglish() {
        let chosen = L10n.chosen
        L10n.use("en")
        defer { L10n.use(chosen) }
        let words = BridgeSendingWords(BridgeSending(speed: 3_140_000, network: CartoucheMacNetwork(medium: "wifi", band: "2.4")), slow: false)
        XCTAssertEqual(words.line, "Sending a game: 3.1\u{00A0}MB/s, on this Mac’s 2.4\u{00A0}GHz Wi-Fi")
        XCTAssertEqual(Format.speed(31_400_000), "31\u{00A0}MB/s")
    }

    /// In Spanish and German, a decimal comma, and MB/s.
    func testTheLineInSpanishAndGerman() {
        let chosen = L10n.chosen
        defer { L10n.use(chosen) }
        let sending = BridgeSending(speed: 3_140_000, network: CartoucheMacNetwork(medium: "wifi", band: "2.4"))
        L10n.use("es")
        XCTAssertEqual(BridgeSendingWords(sending, slow: false).line, "Enviando un juego: 3,1\u{00A0}MB/s, por la Wi-Fi de 2,4\u{00A0}GHz de este Mac")
        L10n.use("de")
        let words = BridgeSendingWords(sending, slow: false)
        XCTAssertEqual(words.line, "Sendet ein Spiel: 3,1\u{00A0}MB/s, über das 2,4-GHz-WLAN dieses Mac")
        XCTAssertEqual(words.advice, "Dieser Mac ist in seinem 2,4-GHz-WLAN, dem langsamsten: Ein Kabel zwischen dem iPhone und diesem Mac oder das 5-GHz-WLAN wäre viel schneller.")
    }
}
