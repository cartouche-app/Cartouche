//
//  CartoucheBridgeCableTests.swift
//  CartoucheCoreTests
//
//  The bridge through the cable (Sources/CartoucheBridgeCable.swift), over
//  connections in memory: a Mac linked once it says which it is, listed
//  until it goes, closed or silent; a session asked with a ticket on the
//  link, the Mac opening another connection for it, and the bridge's own
//  handshake with the paired key on that one; and what gives none: no
//  link, a Mac that does not open it in time, another Mac answering the
//  ticket, a task cancelled, a connection that never says which Mac it is.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheBridgeCableTests: XCTestCase {
    let mac = UUID().uuidString
    let device = UUID().uuidString
    let key = Data((0 ..< 32).map { UInt8($0) })

    /// Waits until CONDITION holds, or fails after SECONDS.
    func eventually(_ what: String, within seconds: TimeInterval = 3, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return XCTFail("never: \(what)") }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// The Mac's side of a link to LINKS, as Cartouche Builder serves it,
    /// each ticket answered by ANSWER with a new connection of its own,
    /// whose iPhone end LINKS takes as the listener would.
    func link(_ links: CartoucheCableLinks, name: String = "MacBook Air", beat: TimeInterval = CartoucheBridgeCable.beat,
              answer: @escaping @Sendable (String, MemoryTransport) async -> Void) -> (mac: MemoryTransport, served: Task<Void, Never>) {
        let (phone, macSide) = MemoryTransport.pair()
        Task { await links.take(phone) }
        let mac = self.mac
        let served = Task {
            await CartoucheBridgeCable.serveLink(macSide, mac: mac, name: name, beat: beat) { ticket in
                let (phone, macSide) = MemoryTransport.pair()
                Task { await links.take(phone) }
                await answer(ticket, macSide)
            }
        }
        return (macSide, served)
    }

    func testAMacIsLinkedOnceItSaysWhichItIsThenGoesWhenItCloses() async {
        let links = CartoucheCableLinks()
        XCTAssertFalse(links.isLinked(mac))
        let (macSide, served) = link(links) { _, connection in connection.close() }
        await eventually("linked") { links.isLinked(mac) }
        XCTAssertEqual(links.macs, [CartoucheCableMac(id: mac, name: "MacBook Air")])
        macSide.close()
        await served.value
        await eventually("gone") { !links.isLinked(mac) }
        XCTAssertEqual(links.macs, [])
    }

    func testASessionThroughTheCableOpensTheBridgeWithThePairedKey() async throws {
        let links = CartoucheCableLinks()
        let mac = self.mac, key = self.key, device = self.device
        let (macSide, _) = link(links) { ticket, connection in
            // As the Builder does: the ticket, then the bridge's handshake.
            do {
                try await CartoucheBridgeCable.sayTicket(ticket, on: connection, mac: mac, name: "MacBook Air")
                let opening = try await CartoucheBridgeHandshake.server(connection, mac: mac, name: "MacBook Air",
                                                                         keyOf: { $0 == device ? key : nil }, allow: nil,
                                                                         keep: { _, _, _ in })
                guard case let .session(channel) = opening else { return connection.close() }
                let (request, _) = try await channel.receive(CartoucheBridgeRequest.self)
                var response = CartoucheBridgeResponse()
                response.name = "answered \(request.op.rawValue)"
                try await channel.send(response)
            } catch {
                connection.close()
            }
        }
        defer { macSide.close() }
        await eventually("linked") { links.isLinked(mac) }
        let opened = await links.session(with: mac)
        let transport = try XCTUnwrap(opened)
        let channel = try await CartoucheBridgeHandshake.client(transport, device: device, key: key, mac: mac)
        XCTAssertEqual(channel.peer, mac)
        let client = CartoucheBridgeClient(channel: channel, address: nil)
        let info = try await client.info()
        XCTAssertEqual(info.name, "answered info")
    }

    func testEachSessionHasItsOwnConnection() async throws {
        let links = CartoucheCableLinks()
        let opened = CableCounter()
        let mac = self.mac
        let (macSide, _) = link(links) { ticket, connection in
            opened.add()
            try? await CartoucheBridgeCable.sayTicket(ticket, on: connection, mac: mac, name: "MacBook Air")
        }
        defer { macSide.close() }
        await eventually("linked") { links.isLinked(mac) }
        async let first = links.session(with: mac)
        async let second = links.session(with: mac)
        let (a, b) = await (first, second)
        let one = try XCTUnwrap(a), two = try XCTUnwrap(b)
        XCTAssertFalse(one === two)
        XCTAssertEqual(opened.value, 2)
    }

    func testNoSessionWithoutALink() async {
        let links = CartoucheCableLinks()
        let started = Date()
        let transport = await links.session(with: mac)
        XCTAssertNil(transport)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "waited for a Mac that is not linked")
    }

    func testAMacThatDoesNotOpenTheConnectionInTimeGivesNone() async {
        let links = CartoucheCableLinks()
        let (macSide, _) = link(links) { _, _ in }
        defer { macSide.close() }
        await eventually("linked") { links.isLinked(mac) }
        let started = Date()
        let transport = await links.session(with: mac, patience: 0.3)
        XCTAssertNil(transport)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testAnotherMacAnsweringTheTicketGivesNone() async {
        let links = CartoucheCableLinks()
        let (macSide, _) = link(links) { ticket, connection in
            try? await CartoucheBridgeCable.sayTicket(ticket, on: connection, mac: UUID().uuidString, name: "Another Mac")
        }
        defer { macSide.close() }
        await eventually("linked") { links.isLinked(mac) }
        let transport = await links.session(with: mac, patience: 2)
        XCTAssertNil(transport)
    }

    func testCancellingTheSessionGivesNoneAtOnce() async {
        let links = CartoucheCableLinks()
        let (macSide, _) = link(links) { _, _ in }
        defer { macSide.close() }
        let mac = self.mac
        await eventually("linked") { links.isLinked(mac) }
        let asked = Task { await links.session(with: mac, patience: 30) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let started = Date()
        asked.cancel()
        let transport = await asked.value
        XCTAssertNil(transport)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testTheMacBeatsOnTheLinkAndASilentLinkGoes() async throws {
        // Beats: frames with nothing in them, after the Mac said which it is.
        let (phone, macSide) = MemoryTransport.pair()
        let served = Task { await CartoucheBridgeCable.serveLink(macSide, mac: mac, name: "MacBook Air", beat: 0.05) { _ in } }
        let hello = try JSONDecoder().decode(CartoucheBridgeCable.Hello.self, from: try await phone.receiveFrame())
        XCTAssertEqual(hello, CartoucheBridgeCable.Hello(mac: mac, name: "MacBook Air"))
        // A Mac that does not beat leaves the read waiting: closed after a
        // while, it fails rather than waits.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            phone.close()
        }
        let beat = try await phone.receiveFrame()
        watchdog.cancel()
        XCTAssertEqual(beat, Data())
        phone.close()
        await served.value

        // A Mac that says which it is, then nothing: gone after the silence.
        let links = CartoucheCableLinks(silence: 0.3)
        let (silentPhone, silentMac) = MemoryTransport.pair()
        Task { await links.take(silentPhone) }
        try await silentMac.sendFrame(JSONEncoder().encode(CartoucheBridgeCable.Hello(mac: mac, name: "MacBook Air")))
        await eventually("linked") { links.isLinked(mac) }
        await eventually("gone, silent", within: 3) { !links.isLinked(mac) }
    }

    func testAConnectionThatNeverSaysWhichMacItIsIsClosed() async {
        let links = CartoucheCableLinks(helloPatience: 0.2)
        let (phone, macSide) = MemoryTransport.pair()
        let taken = Task { await links.take(phone) }
        do {
            _ = try await macSide.receiveFrame()
            XCTFail("the iPhone sent something")
        } catch {
            // Closed by the iPhone.
        }
        await taken.value
        XCTAssertEqual(links.macs, [])
    }

    func testAConnectionInAnotherVersionIsLeftOut() async throws {
        let links = CartoucheCableLinks()
        let (phone, macSide) = MemoryTransport.pair()
        let left = CableCounter()
        Task {
            await links.take(phone)
            left.add()
        }
        try await macSide.sendFrame(JSONEncoder().encode(CartoucheBridgeCable.Hello(v: 99, mac: mac, name: "MacBook Air")))
        // Closed at once, not kept until it falls silent.
        await eventually("left out", within: 2) { left.value == 1 }
        XCTAssertFalse(links.isLinked(mac))
        macSide.close()
    }
}

/// A count shared with the Mac's side.
final class CableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
