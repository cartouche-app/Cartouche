//
//  CartoucheTransferSpeedTests.swift
//  CartoucheCoreTests
//
//  How fast a game comes as it installs, and what the install's screen
//  tells the player of it (CartoucheTransferSpeed.swift): the speed over
//  the last seconds, its pauses left out, slow below 8 MB/s and no longer
//  above 12, and the advice for each way, the Mac's 2.4 GHz Wi-Fi at once.
//

import XCTest
@testable import CartoucheCore

final class CartoucheTransferSpeedTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// 4 MB every SPACING seconds from FROM to TO, as the Mac's reads of
    /// 4 MB come (CartoucheReadAhead).
    private func feed(_ meter: CartoucheTransferMeter, every spacing: TimeInterval, from: TimeInterval, to: TimeInterval) {
        var time = from
        while time <= to + 0.000_1 {
            meter.add(4_000_000, at: at(time))
            time += spacing
        }
    }

    func testTheSpeedIsTheBytesOfTheLastSecondsAfterTheFirstRead() {
        let meter = CartoucheTransferMeter()
        XCTAssertNil(meter.speed(at: at(0)), "nothing read yet")
        // A 2.4 GHz Wi-Fi: 4 MB a second.
        feed(meter, every: 1, from: 0, to: 2)
        XCTAssertNil(meter.speed(at: at(2)), "not for the first seconds")
        meter.add(4_000_000, at: at(3))
        // Three reads in the three seconds since the first one ended: its
        // own bytes came before, and the window is not full yet.
        XCTAssertEqual(meter.speed(at: at(3)) ?? 0, 4_000_000, accuracy: 1)
        feed(meter, every: 1, from: 4, to: 20)
        let speed = try? XCTUnwrap(meter.speed(at: at(20)))
        XCTAssertEqual(speed ?? 0, 4_000_000, accuracy: 1, "the first read's bytes came before it ended")
        // Then 5 GHz: 4 MB every 0.1 s, 40 MB/s, which the window sees whole
        // 8 seconds later.
        feed(meter, every: 0.1, from: 20.1, to: 28)
        XCTAssertEqual(meter.speed(at: at(28)) ?? 0, 40_000_000, accuracy: 600_000)
    }

    func testAStalledTransferComesDownToNothing() {
        let meter = CartoucheTransferMeter()
        feed(meter, every: 0.1, from: 0, to: 10)
        XCTAssertGreaterThan(meter.speed(at: at(10)) ?? 0, 30_000_000)
        // Nothing for 9 seconds: the window holds no read.
        XCTAssertEqual(meter.speed(at: at(19)), 0)
        XCTAssertTrue(CartoucheTransferMeter.isSlow(meter.speed(at: at(19)), wasSlow: false))
    }

    func testAPauseCountsNeitherInTheSpeedNorInTheAverage() {
        let meter = CartoucheTransferMeter()
        feed(meter, every: 0.5, from: 0, to: 10)
        XCTAssertEqual(meter.average() ?? 0, 8_000_000, accuracy: 1)
        // The connection drops, and comes back after 60 seconds.
        meter.pause()
        XCTAssertNil(meter.speed(at: at(30)), "no speed while the connection is made again")
        feed(meter, every: 0.5, from: 70, to: 72)
        XCTAssertNil(meter.speed(at: at(72)), "the run after the pause settles first")
        feed(meter, every: 0.5, from: 72.5, to: 80)
        XCTAssertEqual(meter.speed(at: at(80)) ?? 0, 8_000_000, accuracy: 1, "not the pause's minute")
        XCTAssertEqual(meter.average() ?? 0, 8_000_000, accuracy: 1, "the pause is left out")
    }

    func testTheAverageWaitsForAFewSeconds() {
        let meter = CartoucheTransferMeter()
        meter.add(4_000_000, at: at(0))
        meter.add(4_000_000, at: at(1))
        XCTAssertNil(meter.average())
        meter.add(4_000_000, at: at(4))
        XCTAssertEqual(meter.average() ?? 0, 2_000_000, accuracy: 1)
    }

    func testSlowBelowEightAndNoLongerAboveTwelve() {
        XCTAssertTrue(CartoucheTransferMeter.isSlow(3_000_000, wasSlow: false))
        XCTAssertFalse(CartoucheTransferMeter.isSlow(9_000_000, wasSlow: false))
        // Once slow, about the limit keeps it so: the advice does not come
        // and go.
        XCTAssertTrue(CartoucheTransferMeter.isSlow(9_000_000, wasSlow: true))
        XCTAssertTrue(CartoucheTransferMeter.isSlow(12_000_000, wasSlow: true))
        XCTAssertFalse(CartoucheTransferMeter.isSlow(12_500_000, wasSlow: true))
        // No speed yet: as before.
        XCTAssertTrue(CartoucheTransferMeter.isSlow(nil, wasSlow: true))
        XCTAssertFalse(CartoucheTransferMeter.isSlow(nil, wasSlow: false))
    }

    func testMegabytesWithOneDecimalBelowTen() {
        XCTAssertEqual(CartoucheTransferMeter.megabytes(3_140_000).value, 3.1)
        XCTAssertEqual(CartoucheTransferMeter.megabytes(3_140_000).decimals, 1)
        XCTAssertEqual(CartoucheTransferMeter.megabytes(9_960_000).value, 10)
        XCTAssertEqual(CartoucheTransferMeter.megabytes(9_960_000).decimals, 0)
        XCTAssertEqual(CartoucheTransferMeter.megabytes(31_400_000).value, 31)
        XCTAssertEqual(CartoucheTransferMeter.megabytes(-5).value, 0)
    }

    func testTheWayToTheMac() {
        let slowBand = CartoucheMacNetwork(medium: "wifi", band: "2.4")
        XCTAssertEqual(CartoucheTransferWay.toMac(link: "cable", network: slowBand), .cable, "the cable, whatever the Mac's Wi-Fi")
        XCTAssertEqual(CartoucheTransferWay.toMac(link: "tailnet", network: slowBand), .tailnet)
        XCTAssertEqual(CartoucheTransferWay.toMac(link: "network", network: slowBand), .network(mac: slowBand))
        XCTAssertEqual(CartoucheTransferWay.toMac(link: "network", network: nil), .network(mac: nil), "an older Cartouche Builder")
        XCTAssertNil(CartoucheTransferWay.toMac(link: nil, network: nil))
    }

    func testTheMacsBand() {
        XCTAssertEqual(CartoucheMacNetwork.band(ofChannelBand: 1), "2.4")
        XCTAssertEqual(CartoucheMacNetwork.band(ofChannelBand: 2), "5")
        XCTAssertEqual(CartoucheMacNetwork.band(ofChannelBand: 3), "6")
        XCTAssertNil(CartoucheMacNetwork.band(ofChannelBand: 0), "unknown")
        XCTAssertTrue(CartoucheMacNetwork(medium: "wifi", band: "2.4").isSlowBand)
        XCTAssertFalse(CartoucheMacNetwork(medium: "wifi", band: "5").isSlowBand)
        XCTAssertNil(CartoucheMacNetwork(medium: "ethernet", band: "2.4").band, "a band only on Wi-Fi")
        XCTAssertFalse(CartoucheMacNetwork(medium: "ethernet", band: "2.4").isSlowBand)
    }

    func testANewerMacsWordsStayReadable() throws {
        let decoded = try JSONDecoder().decode(CartoucheMacNetwork.self, from: Data(#"{"medium":"thread","band":"60"}"#.utf8))
        XCTAssertEqual(decoded.medium, "thread")
        XCTAssertFalse(decoded.isSlowBand)
    }

    func testTheAdvice() {
        let slowBand = CartoucheMacNetwork(medium: "wifi", band: "2.4")
        let fastBand = CartoucheMacNetwork(medium: "wifi", band: "5")
        // The cable is the fastest: nothing to say, even slow.
        XCTAssertNil(CartoucheTransferAdvice.of(way: .cable, local: true, slow: true))
        // The Mac on 2.4 GHz: at once, before any speed.
        XCTAssertEqual(CartoucheTransferAdvice.of(way: .network(mac: slowBand), local: true, slow: false), .macOnSlowBand)
        XCTAssertEqual(CartoucheTransferAdvice.of(way: .network(mac: slowBand), local: true, slow: true), .macOnSlowBand)
        // Elsewhere, only once slow.
        XCTAssertNil(CartoucheTransferAdvice.of(way: .network(mac: fastBand), local: true, slow: false))
        XCTAssertEqual(CartoucheTransferAdvice.of(way: .network(mac: fastBand), local: true, slow: true), .slowToMac,
                       "the iPhone's own Wi-Fi may be the slow one")
        XCTAssertEqual(CartoucheTransferAdvice.of(way: .network(mac: nil), local: true, slow: true), .slowToMac)
        XCTAssertNil(CartoucheTransferAdvice.of(way: .tailnet, local: true, slow: false))
        XCTAssertEqual(CartoucheTransferAdvice.of(way: .tailnet, local: true, slow: true), .slowTailnet)
        // A NAS of the local network, slow: its Wi-Fi; a bucket or the
        // cloud, through the internet: nothing Cartouche can tell.
        XCTAssertEqual(CartoucheTransferAdvice.of(way: nil, local: true, slow: true), .slowNetwork)
        XCTAssertNil(CartoucheTransferAdvice.of(way: nil, local: false, slow: true))
        XCTAssertNil(CartoucheTransferAdvice.of(way: nil, local: true, slow: false))
    }
}
