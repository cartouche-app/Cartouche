//
//  CartoucheTailscaleTests.swift
//  CartoucheCoreTests
//
//  Tailscale, which the player installs apart (Sources/CartoucheTailscale.swift):
//  the addresses and names of a tailnet, how Cartouche tells that Tailscale
//  is on from the device's interfaces, the addresses it tries for the
//  player's Mac with Tailscale on and off, those it keeps of the Mac once
//  it reached it and the Mac told its own, and an address the player types
//  for their Mac.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheTailscaleTests: XCTestCase {
    // MARK: Addresses and names of a tailnet

    func testTheTailnetsAddressesAreKnown() {
        for address in ["100.64.0.1", "100.101.102.103", "100.127.255.254", "fd7a:115c:a1e0::1",
                        "FD7A:115C:A1E0:AB12:4843:CD96:6258:B240", "[fd7a:115c:a1e0::1]", "fd7a:115c:a1e0::1%utun4",
                        " 100.100.100.100 "] {
            XCTAssertTrue(CartoucheTailscale.isTailnetAddress(address), address)
        }
    }

    func testOtherAddressesAreNot() {
        // The player's network, the Internet, the edges of 100.64.0.0/10,
        // another network of fd00::/8, and what is no address at all.
        for address in ["192.168.1.20", "10.7.0.10", "100.63.255.255", "100.128.0.1", "100.1.2.3", "8.8.8.8",
                        "fd7a:115c:a1e1::1", "fe80::1", "fd00::1", "::1", "100.64.0", "100.64.0.1.2",
                        "100.64.0.256", "100.064.0.1x", "", "nas.local", "100.64.0.1:47920"] {
            XCTAssertFalse(CartoucheTailscale.isTailnetAddress(address), address)
        }
    }

    func testMagicDNSNamesAreKnown() {
        for name in ["nas.tail1234.ts.net", "macbook-air.tail-scale.ts.net", "NAS.TAIL1234.TS.NET",
                     "nas.tail1234.ts.net.", "mac.example.com.beta.tailscale.net"] {
            XCTAssertTrue(CartoucheTailscale.isMagicDNSName(name), name)
        }
        for name in ["ts.net", ".ts.net", "nas..ts.net", "nas.local", "nas", "tailscale.net", "nas.ts.network",
                     "nas.ts.net.example.com", "beta.tailscale.net", "192.168.1.2"] {
            XCTAssertFalse(CartoucheTailscale.isMagicDNSName(name), name)
        }
    }

    func testATailnetHostIsAnAddressOrAName() {
        XCTAssertTrue(CartoucheTailscale.isTailnetHost("100.101.102.103"))
        XCTAssertTrue(CartoucheTailscale.isTailnetHost("nas.tail1234.ts.net"))
        XCTAssertFalse(CartoucheTailscale.isTailnetHost("192.168.1.2"))
        XCTAssertFalse(CartoucheTailscale.isTailnetHost("nas.local"))
    }

    // MARK: Whether Tailscale is on

    func testTailscalesTunnelIsSeen() {
        let interfaces: [CartoucheNetworkInterface] = [
            .init(name: "lo0", address: "127.0.0.1"),
            .init(name: "en0", address: "192.168.1.30"),
            .init(name: "utun3", address: "fd7a:115c:a1e0::5%utun3"),
            .init(name: "utun3", address: "100.101.102.104"),
            .init(name: "utun3", address: "fe80::1%utun3"),
        ]
        XCTAssertTrue(CartoucheTailscale.isConnected(interfaces))
        // IPv4 first, without the interface after the address.
        XCTAssertEqual(CartoucheTailscale.addresses(in: interfaces), ["100.101.102.104", "fd7a:115c:a1e0::5"])
    }

    func testACarriersAddressOrLocalDevVPNIsNotTailscale() {
        // A carrier may give the iPhone an address of 100.64.0.0/10 on its
        // own interface; LocalDevVPN's tunnel has one of 10.7.0.0/16.
        let interfaces: [CartoucheNetworkInterface] = [
            .init(name: "pdp_ip0", address: "100.70.1.2"),
            .init(name: "utun4", address: "10.7.0.10"),
            .init(name: "en0", address: "100.64.5.6"),
        ]
        XCTAssertFalse(CartoucheTailscale.isConnected(interfaces))
        XCTAssertEqual(CartoucheTailscale.addresses(in: interfaces), [])
        XCTAssertFalse(CartoucheTailscale.isConnected([]))
    }

    func testTheSameAddressTwiceIsOnce() {
        let interfaces: [CartoucheNetworkInterface] = [
            .init(name: "utun3", address: "100.101.102.104"),
            .init(name: "utun3", address: "100.101.102.104"),
        ]
        XCTAssertEqual(CartoucheTailscale.addresses(in: interfaces), ["100.101.102.104"])
    }

    #if canImport(Darwin)
    func testThisMachinesInterfacesAreRead() {
        // Every Mac has its loopback up, with its IPv4 and IPv6 addresses.
        let interfaces = CartoucheTailscale.interfaces()
        XCTAssertTrue(interfaces.contains { $0.name == "lo0" && $0.address == "127.0.0.1" })
        XCTAssertTrue(interfaces.contains { $0.name == "lo0" && $0.address == "::1" })
    }
    #endif

    // MARK: The player's Mac in the tailnet

    func testTheLastAddressGoesFirstThenTheTailnetsWithTailscaleOn() {
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "192.168.1.20", tailnet: ["100.101.102.103", "fd7a:115c:a1e0::3"],
                                                         tailscaleOn: true),
                       ["192.168.1.20", "100.101.102.103", "fd7a:115c:a1e0::3"])
    }

    func testWithoutTailscaleNoAddressOfTheTailnetIsTried() {
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "192.168.1.20", tailnet: ["100.101.102.103"], tailscaleOn: false),
                       ["192.168.1.20"])
        // A Mac paired through Tailscale, its last address in the tailnet.
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "100.101.102.103", tailnet: ["100.101.102.103"], tailscaleOn: false), [])
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "mac.tail1234.ts.net", tailnet: [], tailscaleOn: false), [])
    }

    func testEachAddressIsTriedOnce() {
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "100.101.102.103", tailnet: ["100.101.102.103", " ", "fd7a:115c:a1e0::3"],
                                                         tailscaleOn: true),
                       ["100.101.102.103", "fd7a:115c:a1e0::3"])
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: "", tailnet: [], tailscaleOn: true), [])
        XCTAssertEqual(CartoucheTailscale.addressesToTry(host: " ", tailnet: ["100.101.102.103"], tailscaleOn: true), ["100.101.102.103"])
    }

    // MARK: What Cartouche keeps of the Mac

    private let home = CartoucheMacAddresses(host: "192.168.1.20", port: 47920, tailnet: [])

    func testReachedAtHomeTheAddressIsKept() {
        let reached = home.reached("192.168.1.21", port: 47921, told: nil)
        XCTAssertEqual(reached, CartoucheMacAddresses(host: "192.168.1.21", port: 47921, tailnet: []))
    }

    func testTheMacsAddressesInTheTailnetAreKeptBesideTheHomeOne() {
        // A Cartouche Builder that knows Tailscale tells them, its IPv4 first.
        let told = home.reached("192.168.1.20", port: 47920, told: ["100.101.102.103", "fd7a:115c:a1e0::3"])
        XCTAssertEqual(told, CartoucheMacAddresses(host: "192.168.1.20", port: 47920, tailnet: ["100.101.102.103", "fd7a:115c:a1e0::3"]))
        // Reached through Tailscale, away from home: the home address stays
        // first, for the Wi-Fi at home.
        let away = told.reached("100.101.102.103", port: 47920, told: ["100.101.102.103"])
        XCTAssertEqual(away, CartoucheMacAddresses(host: "192.168.1.20", port: 47920, tailnet: ["100.101.102.103"]))
    }

    func testAMacPairedThroughTailscaleGetsItsHomeAddressOnceReachedThere() {
        let paired = CartoucheMacAddresses(host: "", port: nil, tailnet: []).reached("100.101.102.103", port: 47920, told: nil)
        XCTAssertEqual(paired, CartoucheMacAddresses(host: "100.101.102.103", port: 47920, tailnet: ["100.101.102.103"]))
        let atHome = paired.reached("192.168.1.20", port: 47920, told: nil)
        XCTAssertEqual(atHome, CartoucheMacAddresses(host: "192.168.1.20", port: 47920, tailnet: ["100.101.102.103"]))
    }

    func testAMacThatSaysNothingOrNoneKeepsWhatItHad() {
        let known = CartoucheMacAddresses(host: "192.168.1.20", port: 47920, tailnet: ["100.101.102.103"])
        // An older Cartouche Builder says nothing; one whose Tailscale is
        // off a moment says it has none.
        XCTAssertEqual(known.reached("192.168.1.20", port: 47920, told: nil), known)
        XCTAssertEqual(known.reached("192.168.1.20", port: 47920, told: []), known)
        // Nor does what is no address of a tailnet replace them.
        XCTAssertEqual(known.reached("192.168.1.20", port: 47920, told: ["192.168.1.20", "fe80::1"]), known)
        // Nothing reached changes nothing.
        XCTAssertEqual(known.reached(nil, port: nil, told: nil), known)
        XCTAssertEqual(known.reached("", port: 47920, told: nil), known)
    }

    func testTheMacsOwnListIsKeptOnceEach() {
        let told = home.reached("192.168.1.20", port: 47920, told: [" 100.101.102.103", "100.101.102.103", "fd7a:115c:a1e0::3"])
        XCTAssertEqual(told.tailnet, ["100.101.102.103", "fd7a:115c:a1e0::3"])
    }

    // MARK: An address the player types

    func testAnAddressOrANameIsTakenWithTheBridgesPort() {
        XCTAssertEqual(CartoucheTypedAddress.parse("macbook-air", port: 47920), CartoucheTypedAddress(host: "macbook-air", port: 47920))
        XCTAssertEqual(CartoucheTypedAddress.parse(" macbook-air.tail1234.ts.net \n", port: 47920),
                       CartoucheTypedAddress(host: "macbook-air.tail1234.ts.net", port: 47920))
        XCTAssertEqual(CartoucheTypedAddress.parse("100.101.102.103", port: 47920), CartoucheTypedAddress(host: "100.101.102.103", port: 47920))
        XCTAssertEqual(CartoucheTypedAddress.parse("fd7a:115c:a1e0::3", port: 47920), CartoucheTypedAddress(host: "fd7a:115c:a1e0::3", port: 47920))
    }

    func testAPortTypedAfterItIsTaken() {
        XCTAssertEqual(CartoucheTypedAddress.parse("100.101.102.103:47921", port: 47920),
                       CartoucheTypedAddress(host: "100.101.102.103", port: 47921))
        XCTAssertEqual(CartoucheTypedAddress.parse("mac.tail1234.ts.net:50000", port: 47920),
                       CartoucheTypedAddress(host: "mac.tail1234.ts.net", port: 50000))
        XCTAssertEqual(CartoucheTypedAddress.parse("[fd7a:115c:a1e0::3]:47921", port: 47920),
                       CartoucheTypedAddress(host: "fd7a:115c:a1e0::3", port: 47921))
        XCTAssertEqual(CartoucheTypedAddress.parse("[fd7a:115c:a1e0::3]", port: 47920),
                       CartoucheTypedAddress(host: "fd7a:115c:a1e0::3", port: 47920))
    }

    func testWhatIsNoAddressIsRefused() {
        for text in ["", "  ", "mac book", "http://mac.local", "mac.local/games", "ad@mac", "mac:", "mac:0", "mac:70000",
                     "mac:port", "[fd7a::1", "[fd7a::1]x", "[fd7a::1]:", ".mac", "-mac", "mac%en0", "mac_air", "maçon"] {
            XCTAssertNil(CartoucheTypedAddress.parse(text, port: 47920), text)
        }
    }

    // MARK: Turning Tailscale on again

    func testSaysToTurnTailscaleOnAgainOnceLocalDevVPNIsNoLongerNeeded() {
        let off = Date(timeIntervalSince1970: 1_800_000_000)
        // Off since LocalDevVPN connected, the renewal done.
        XCTAssertTrue(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: false, busy: false, at: off.addingTimeInterval(60)))
        // Not while the renewal goes on: turning Tailscale on would stop it.
        XCTAssertFalse(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: false, busy: true, at: off.addingTimeInterval(60)))
        // On again, or never turned off by LocalDevVPN.
        XCTAssertFalse(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: true, busy: false, at: off.addingTimeInterval(60)))
        XCTAssertFalse(CartoucheTailscaleReminder.shows(turnedOff: nil, tailscaleOn: false, busy: false, at: off))
        // Twelve hours at most: the player may keep it off.
        XCTAssertTrue(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: false, busy: false,
                                                       at: off.addingTimeInterval(CartoucheTailscaleReminder.lasts - 1)))
        XCTAssertFalse(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: false, busy: false,
                                                        at: off.addingTimeInterval(CartoucheTailscaleReminder.lasts)))
        // A clock set back.
        XCTAssertFalse(CartoucheTailscaleReminder.shows(turnedOff: off, tailscaleOn: false, busy: false, at: off.addingTimeInterval(-60)))
    }

    /// LocalDevVPN, which Cartouche opened with Tailscale on, connects and
    /// brings Cartouche back within seconds: Tailscale seen off then went
    /// off for it, and long after, by the player's hand.
    func testTailscaleOffSoonAfterCartoucheOpenedLocalDevVPNWentOffForIt() {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(CartoucheTailscaleReminder.turnedOff(byOpeningAt: opened, seenOffAt: opened.addingTimeInterval(2)))
        XCTAssertTrue(CartoucheTailscaleReminder.turnedOff(byOpeningAt: opened, seenOffAt: opened.addingTimeInterval(5 * 60)))
        XCTAssertFalse(CartoucheTailscaleReminder.turnedOff(byOpeningAt: opened,
                                                            seenOffAt: opened.addingTimeInterval(CartoucheTailscaleReminder.opening)))
        XCTAssertFalse(CartoucheTailscaleReminder.turnedOff(byOpeningAt: opened, seenOffAt: opened.addingTimeInterval(3_600)))
        // A clock set back.
        XCTAssertFalse(CartoucheTailscaleReminder.turnedOff(byOpeningAt: opened, seenOffAt: opened.addingTimeInterval(-60)))
    }
}
