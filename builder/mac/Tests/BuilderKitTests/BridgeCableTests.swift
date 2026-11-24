//
//  BridgeCableTests.swift
//  BuilderKitTests
//
//  The bridge through the cable, the Mac's side (BridgeCable.swift,
//  Usbmux.swift), against a usbmuxd of the test's on a Unix socket, with
//  one iPhone plugged in, where Cartouche's side of the cable
//  (CartoucheCableLinks) takes what the Mac opens: usbmuxd's messages as it
//  reads them, the iPhone's games read and its pairing through the cable
//  alone, with no network, Cartouche tried again until it listens, and its
//  link gone once the iPhone is unplugged.
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// usbmuxd, as the test plays it: one iPhone plugged in, number 7, on
/// whose loopback Cartouche listens, or not yet.
private final class FakeUsbmuxd: @unchecked Sendable {
    static let device = 7
    let path: String
    /// Cartouche on the iPhone: what the Mac opens to its port reaches it.
    let iphone: CartoucheCableLinks
    let port: UInt16
    private let listening: Int32
    private let lock = NSLock()
    private var cartoucheListens: Bool
    private var plugged = true
    private var listens: [UsbmuxSocket] = []
    private var toIPhone: [UsbmuxSocket] = []
    private var connects = 0
    private var ports: [Int] = []
    private var devices: Set<Int> = []

    init(iphone: CartoucheCableLinks, port: UInt16, cartoucheListens: Bool = true) throws {
        path = "/tmp/cartouche-usbmuxd-\(UUID().uuidString.prefix(8)).sock"
        self.iphone = iphone
        self.port = port
        self.cartoucheListens = cartoucheListens
        #if canImport(Darwin)
        listening = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        listening = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let server = listening
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(server, 16) == 0 else { throw CartoucheBridgeError(.closed, String(cString: strerror(errno))) }
        Thread.detachNewThread { [weak self] in
            while true {
                let accepted = accept(server, nil, nil)
                guard accepted >= 0 else { return }
                guard let self else { return }
                let socket = UsbmuxSocket(descriptor: accepted)
                Task { await self.serve(socket) }
            }
        }
    }

    /// BODY under the lock, from synchronous code: an NSLock is not to be
    /// held across a suspension.
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func stop() {
        shutdown(listening, Int32(SHUT_RDWR))
        unlink(path)
        lock.lock()
        let all = listens + toIPhone
        lock.unlock()
        all.forEach { $0.close() }
    }

    func setCartoucheListens(_ on: Bool) {
        lock.lock()
        cartoucheListens = on
        lock.unlock()
    }

    /// How many times the Mac asked to connect to an iPhone, the port
    /// numbers it gave, as it sent them, and the iPhones it asked for.
    var asked: (connects: Int, ports: [Int], devices: Set<Int>) {
        lock.lock()
        defer { lock.unlock() }
        return (connects, ports, devices)
    }

    /// The iPhone unplugged: usbmuxd says so, and its connections end.
    func unplug() async {
        let (listens, connections) = locked {
            plugged = false
            defer { toIPhone = [] }
            return (self.listens, toIPhone)
        }
        for socket in listens {
            try? await socket.sendMessage(["MessageType": "Detached", "DeviceID": Self.device], tag: 0)
        }
        connections.forEach { $0.close() }
    }

    private func serve(_ socket: UsbmuxSocket) async {
        while true {
            guard let message = try? await socket.receiveMessage() else { return socket.close() }
            switch message["MessageType"] as? String {
            case "Listen":
                locked { listens.append(socket) }
                try? await socket.sendMessage(["MessageType": "Result", "Number": 0], tag: 1)
                // An iPhone syncing over Wi-Fi, which the Mac leaves to Bonjour, then the one plugged in.
                try? await socket.sendMessage(["MessageType": "Attached", "DeviceID": 9,
                                               "Properties": ["ConnectionType": "Network", "DeviceID": 9, "SerialNumber": "00008150-WIFI"]], tag: 0)
                try? await socket.sendMessage(["MessageType": "Attached", "DeviceID": Self.device,
                                               "Properties": ["ConnectionType": "USB", "DeviceID": Self.device, "SerialNumber": "00008150-USB"]], tag: 0)
            case "Connect":
                let device = (message["DeviceID"] as? NSNumber)?.intValue
                let number = (message["PortNumber"] as? NSNumber)?.intValue ?? 0
                // In network order, as libimobiledevice and macOS read it.
                let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: number))
                let (listens, plugged) = locked {
                    connects += 1
                    ports.append(number)
                    if let device { devices.insert(device) }
                    return (cartoucheListens, self.plugged)
                }
                guard device == Self.device, plugged else {
                    try? await socket.sendMessage(["MessageType": "Result", "Number": 2], tag: 2)
                    continue
                }
                guard port == self.port, listens else {
                    try? await socket.sendMessage(["MessageType": "Result", "Number": 3], tag: 2)
                    continue
                }
                try? await socket.sendMessage(["MessageType": "Result", "Number": 0], tag: 2)
                locked { toIPhone.append(socket) }
                // From here on, the iPhone's connection: Cartouche takes it.
                await iphone.take(UsbmuxStream(socket))
                return
            default:
                try? await socket.sendMessage(["MessageType": "Result", "Number": 1], tag: 0)
            }
        }
    }
}

/// The player at the Mac, who allows every iPhone.
@MainActor
private final class AllowingPlayer: BridgeServerDelegate {
    var asked: [String] = []

    func bridgeServer(_ server: BridgeServer, allowPairing name: String, code: String) async -> Bool {
        asked.append(name)
        return true
    }

    func bridgeServerChanged(_ server: BridgeServer) {}
}

final class BridgeCableTests: XCTestCase {
    private var folder: URL!
    private var games: URL!
    private var muxd: FakeUsbmuxd?
    private var server: BridgeServer?
    private let port: UInt16 = 47921
    private let device = UUID().uuidString
    private let key = Data((0 ..< 32).map { UInt8(255 - $0) })

    override func setUpWithError() throws {
        let manager = FileManager.default
        folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        games = folder.appendingPathComponent("Jeux", isDirectory: true)
        try manager.createDirectory(at: games, withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appendingPathComponent("Saves", isDirectory: true), withIntermediateDirectories: true)
        try Data("IPA bytes through the cable".utf8).write(to: games.appendingPathComponent("Mario Kart World [0400C3F00006E000].ipa"))
    }

    override func tearDownWithError() throws {
        server?.stop()
        muxd?.stop()
        try? FileManager.default.removeItem(at: folder)
    }

    /// The Mac, with the test's usbmuxd and an iPhone paired already
    /// (PAIRED), and Cartouche on the iPhone plugged in.
    private func plugged(paired: Bool = true, cartoucheListens: Bool = true) throws -> (server: BridgeServer, iphone: CartoucheCableLinks, muxd: FakeUsbmuxd) {
        let iphone = CartoucheCableLinks()
        let muxd = try FakeUsbmuxd(iphone: iphone, port: port, cartoucheListens: cartoucheListens)
        let devices = BridgeDevices(url: folder.appendingPathComponent("bridge.json"))
        if paired { devices.add(id: device, name: "iPhone de test", key: key) }
        let server = BridgeServer(devices: devices, name: "Mac de test", tailnetAddresses: { [] },
                                  usbmuxd: muxd.path, cablePort: port, cableRetry: 0.1)
        server.roots = BridgeRoots(games: games, saves: folder.appendingPathComponent("Saves", isDirectory: true))
        self.muxd = muxd
        self.server = server
        return (server, iphone, muxd)
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

    // MARK: usbmuxd's messages

    func testMessagesAreAsUsbmuxdReadsThem() throws {
        let packet = try Usbmux.packet(Usbmux.connect(device: 7, port: 62078), tag: 5)
        let header = [UInt8](packet.prefix(16))
        // Length with the header, version 1, a property list (8), the tag: little-endian.
        XCTAssertEqual(Usbmux.length(of: packet), packet.count)
        XCTAssertEqual(Array(header[4 ..< 16]), [1, 0, 0, 0, 8, 0, 0, 0, 5, 0, 0, 0])
        let message = try Usbmux.message(packet.subdata(in: 16 ..< packet.count))
        XCTAssertEqual(message["MessageType"] as? String, "Connect")
        XCTAssertEqual((message["DeviceID"] as? NSNumber)?.intValue, 7)
        // Lockdown's port, 62078 (0xF27E), as libimobiledevice sends it from a little-endian Mac: 0x7EF2.
        let number = try XCTUnwrap((message["PortNumber"] as? NSNumber)?.intValue)
        XCTAssertEqual(UInt16(bigEndian: UInt16(truncatingIfNeeded: number)), 62078)
        if 1.littleEndian == 1 { XCTAssertEqual(number, 32498) }
    }

    func testEventsSayWhichIPhoneCameByUSBAndWhichWent() {
        XCTAssertEqual(Usbmux.event(["MessageType": "Attached", "DeviceID": 3,
                                     "Properties": ["ConnectionType": "USB", "SerialNumber": "00008150-A"]]),
                       .attached(Usbmux.Device(id: 3, serial: "00008150-A", usb: true)))
        XCTAssertEqual(Usbmux.event(["MessageType": "Attached", "DeviceID": 4,
                                     "Properties": ["ConnectionType": "Network", "SerialNumber": "00008150-B"]]),
                       .attached(Usbmux.Device(id: 4, serial: "00008150-B", usb: false)))
        XCTAssertEqual(Usbmux.event(["MessageType": "Detached", "DeviceID": 3]), .detached(3))
        XCTAssertNil(Usbmux.event(["MessageType": "Paired", "DeviceID": 3]))
        XCTAssertEqual(Usbmux.result(["MessageType": "Result", "Number": 3]), 3)
    }

    // MARK: Through the cable

    func testAnIPhonePluggedInReadsTheMacsGamesThroughTheCableAlone() async throws {
        let (server, iphone, muxd) = try plugged()
        // As Share with Cartouche on the iPhone starts it: the network and
        // the cable both.
        server.start()
        let mac = server.devices.macID
        await eventually("linked") { iphone.isLinked(mac) }
        XCTAssertEqual(iphone.macs, [CartoucheCableMac(id: mac, name: "Mac de test")])
        XCTAssertTrue(muxd.asked.ports.allSatisfy { UInt16(bigEndian: UInt16(truncatingIfNeeded: $0)) == port })

        let opened = await iphone.session(with: mac)
        let transport = try XCTUnwrap(opened, "the Mac opened no connection for the ticket")
        let channel = try await CartoucheBridgeHandshake.client(transport, device: device, key: key, mac: mac)
        let client = CartoucheBridgeClient(channel: channel, address: nil)
        let listed = try await client.list("Games")
        XCTAssertEqual(listed.map(\.name), ["Mario Kart World [0400C3F00006E000].ipa"])
        XCTAssertEqual(muxd.asked.devices, [FakeUsbmuxd.device], "the iPhone on the Wi-Fi is left to Bonjour")
        let read = try await client.read("Games/Mario Kart World [0400C3F00006E000].ipa", at: 0, count: 1 << 20)
        XCTAssertEqual(read, Data("IPA bytes through the cable".utf8))
        XCTAssertEqual(server.connectedByCable, [device])
        XCTAssertEqual(server.connected, [device])

        client.close()
        await eventually("session ended") { server.connected.isEmpty }
        XCTAssertEqual(server.connectedByCable, [])
    }

    @MainActor
    func testAnIPhonePairsThroughTheCable() async throws {
        let (server, iphone, _) = try plugged(paired: false)
        let player = AllowingPlayer()
        server.delegate = player
        server.cable?.start()
        let mac = server.devices.macID
        await eventually("linked") { iphone.isLinked(mac) }
        let opened = await iphone.session(with: mac)
        let transport = try XCTUnwrap(opened)
        let paired = try await CartoucheBridgeHandshake.pair(transport, device: device, name: "iPhone de test") { _ in }
        XCTAssertEqual(paired.mac, mac)
        XCTAssertEqual(paired.name, "Mac de test")
        XCTAssertEqual(server.devices.key(of: device), paired.key)
        XCTAssertEqual(player.asked, ["iPhone de test"])
    }

    func testCartoucheIsTriedAgainUntilItListens() async throws {
        let (server, iphone, muxd) = try plugged(cartoucheListens: false)
        server.cable?.start()
        let mac = server.devices.macID
        await eventually("tried twice") { muxd.asked.connects >= 2 }
        XCTAssertFalse(iphone.isLinked(mac))
        XCTAssertEqual(server.cable?.linkedDevices, [])
        // Cartouche opened on the iPhone.
        muxd.setCartoucheListens(true)
        await eventually("linked once Cartouche listens") { iphone.isLinked(mac) }
        XCTAssertEqual(server.cable?.linkedDevices, [FakeUsbmuxd.device])
    }

    func testTheLinkGoesOnceTheIPhoneIsUnplugged() async throws {
        let (server, iphone, muxd) = try plugged()
        server.cable?.start()
        let mac = server.devices.macID
        await eventually("linked") { iphone.isLinked(mac) }
        await muxd.unplug()
        await eventually("gone from the iPhone") { !iphone.isLinked(mac) }
        await eventually("gone from the Mac") { server.cable?.linkedDevices.isEmpty == true }
        let opened = await iphone.session(with: mac)
        XCTAssertNil(opened)
        // Nor tried again: the Mac follows it once it is plugged in again.
        let asked = muxd.asked.connects
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(muxd.asked.connects, asked, "the Mac still asks usbmuxd for an iPhone unplugged")
    }

    func testNoUsbmuxdLeavesTheNetworkAlone() async throws {
        // A Mac whose usbmuxd does not answer: nothing breaks, nothing is linked.
        let devices = BridgeDevices(url: folder.appendingPathComponent("alone.json"))
        let server = BridgeServer(devices: devices, name: "Mac de test", tailnetAddresses: { [] },
                                  usbmuxd: "/tmp/cartouche-no-usbmuxd-\(UUID().uuidString.prefix(8)).sock", cablePort: port)
        self.server = server
        server.cable?.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(server.cable?.linkedDevices, [])
        XCTAssertNil(BridgeServer(devices: devices, name: "Mac de test", usbmuxd: nil).cable)
    }
}
