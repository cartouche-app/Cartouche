//
//  CartoucheBridgeCable.swift
//  Cartouche
//
//  The bridge through the cable: with the iPhone plugged into the Mac,
//  Cartouche Builder reaches Cartouche through usbmuxd, macOS's own way to
//  the iPhones on its USB ports, which the Finder and the Cartouche
//  Installer use too. Nothing to install, no Wi-Fi: the cable alone.
//
//  Only the Mac opens a connection that way, to a port of the iPhone's:
//  Cartouche listens on the iPhone's own loopback (CartoucheCableListener,
//  port 47921), where nothing from a network arrives. So the Mac keeps one
//  connection open with each iPhone plugged in where Cartouche listens, its
//  link: the Mac says first which Mac it is, in the clear, as its Bonjour
//  record does, then sends a frame with nothing in it every few seconds,
//  for Cartouche to know when it went. When Cartouche wants a session, it
//  asks the link for one with a ticket; the Mac opens another connection,
//  says which Mac it is with the ticket, and from there it is a connection
//  of the bridge as any other (CartoucheBridge.swift): the same handshake
//  with the paired key, or a pairing with its six digits, and the same
//  encryption. Nothing the cable carries is trusted more than the Wi-Fi.
//
//  This file is shared: Cartouche compiles it with the launcher, Cartouche
//  Builder through the CartoucheCore package. It needs only Foundation.
//

import Foundation

public enum CartoucheBridgeCable {
    /// The port Cartouche listens on, on the iPhone's own loopback.
    public static let port: UInt16 = 47921
    public static let version = 1
    /// How often the Mac says on a link that it is still there, in seconds.
    public static let beat: TimeInterval = 4
    /// How long Cartouche hears nothing on a link before it takes the Mac
    /// for gone, in seconds: three beats missed.
    public static let silence: TimeInterval = 13
    /// How long a connection the Mac opened has to say which Mac it comes
    /// from, in seconds.
    public static let helloPatience: TimeInterval = 5
    /// How long Cartouche waits for the connection a ticket asked for, in
    /// seconds, before it looks for the Mac on the network.
    public static let ticketPatience: TimeInterval = 3

    /// The first frame of each connection the Mac opens through the cable,
    /// in the clear: which Mac, with its ID in Cartouche Builder and its
    /// name, and, for a connection a ticket asked for, the ticket.
    public struct Hello: Codable, Equatable, Sendable {
        public var v: Int
        public var mac: String
        public var name: String
        public var ticket: String?

        public init(v: Int = CartoucheBridgeCable.version, mac: String, name: String, ticket: String? = nil) {
            self.v = v
            self.mac = mac
            self.name = name
            self.ticket = ticket
        }
    }

    /// What Cartouche asks on a link: another connection, for its ticket.
    public struct Ask: Codable, Equatable, Sendable {
        public var ticket: String

        public init(ticket: String) {
            self.ticket = ticket
        }
    }

    // MARK: The Mac's side

    /// The Mac's side of a link with an iPhone, on TRANSPORT: says which Mac
    /// it is, MAC and NAME, then says every BEAT seconds that it is still
    /// there, and has OPEN open a connection for each ticket the iPhone
    /// gives. Returns once the link is gone, closed.
    public static func serveLink(_ transport: CartoucheBridgeTransport, mac: String, name: String, beat: TimeInterval = beat,
                                 open: @escaping @Sendable (String) async -> Void) async {
        do {
            try await transport.sendFrame(JSONEncoder().encode(Hello(mac: mac, name: name)))
        } catch {
            transport.close()
            return
        }
        let beating = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(beat * 1_000_000_000))
                if Task.isCancelled { break }
                do {
                    try await transport.sendFrame(Data())
                } catch {
                    // Gone: closing it ends the reads below.
                    transport.close()
                    break
                }
            }
        }
        defer {
            beating.cancel()
            transport.close()
        }
        while true {
            let frame: Data
            do {
                frame = try await transport.receiveFrame()
            } catch {
                return
            }
            // Anything else is for a Cartouche newer than this Mac's app.
            guard let ask = try? JSONDecoder().decode(Ask.self, from: frame), !ask.ticket.isEmpty else { continue }
            Task { await open(ask.ticket) }
        }
    }

    /// The Mac's side of a connection it opened for TICKET, on TRANSPORT:
    /// says which Mac, with the ticket. The bridge's handshake follows on
    /// it, as on any other connection.
    public static func sayTicket(_ ticket: String, on transport: CartoucheBridgeTransport, mac: String, name: String) async throws {
        try await transport.sendFrame(JSONEncoder().encode(Hello(mac: mac, name: name, ticket: ticket)))
    }
}

/// A Mac linked through the cable now.
public struct CartoucheCableMac: Hashable, Identifiable, Sendable {
    /// The Mac's ID in Cartouche Builder.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The iPhone's side: the Macs linked through the cable, and the sessions
/// Cartouche asks of them. What the listener on the loopback accepts comes
/// here (CartoucheCableListener); the Mac's storage asks it first
/// (CartoucheStorageMac.swift). On the Mac's console, nothing comes, and
/// no Mac is linked.
public final class CartoucheCableLinks: @unchecked Sendable {
    public static let shared = CartoucheCableLinks()
    /// Posted, from any thread, each time a Mac is linked or goes.
    public static let changed = Notification.Name("CartoucheCableLinksChanged")

    private final class Link: @unchecked Sendable {
        let mac: String
        let name: String
        let transport: CartoucheBridgeTransport
        /// One ask at a time on the link.
        let gate = CartoucheBridgeGate()
        private let lock = NSLock()
        private var heard = Date()

        init(mac: String, name: String, transport: CartoucheBridgeTransport) {
            self.mac = mac
            self.name = name
            self.transport = transport
        }

        var lastHeard: Date {
            lock.lock()
            defer { lock.unlock() }
            return heard
        }

        func touch() {
            lock.lock()
            heard = Date()
            lock.unlock()
        }
    }

    private struct Waiting {
        let mac: String
        let continuation: CheckedContinuation<CartoucheBridgeTransport?, Never>
    }

    private let lock = NSLock()
    /// The links, oldest first: a Mac linked twice is asked on its newest.
    private var links: [Link] = []
    private var tickets: [String: Waiting] = [:]
    private let silence: TimeInterval
    private let helloPatience: TimeInterval

    public init(silence: TimeInterval = CartoucheBridgeCable.silence, helloPatience: TimeInterval = CartoucheBridgeCable.helloPatience) {
        self.silence = silence
        self.helloPatience = helloPatience
    }

    /// The Macs linked now, once each, by name.
    public var macs: [CartoucheCableMac] {
        lock.lock()
        let now = links
        lock.unlock()
        var seen = Set<String>()
        return now.reversed()
            .filter { seen.insert($0.mac).inserted }
            .map { CartoucheCableMac(id: $0.mac, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether the Mac MAC_ID is linked through the cable now.
    public func isLinked(_ macID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return links.contains { $0.mac == macID }
    }

    /// A connection the Mac opened through the cable, on TRANSPORT: its
    /// link, kept until it goes, or the connection a ticket asked for,
    /// handed to the session waiting for it. Returns once it is handed or
    /// gone. One that does not say which Mac it comes from in time, or says
    /// it in another version, is closed.
    public func take(_ transport: CartoucheBridgeTransport) async {
        let said = CartoucheBridgeOnce()
        let patience = helloPatience
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(patience * 1_000_000_000))
            if said.claim() { transport.close() }
        }
        let hello: CartoucheBridgeCable.Hello
        do {
            let frame = try await transport.receiveFrame()
            hello = try JSONDecoder().decode(CartoucheBridgeCable.Hello.self, from: frame)
        } catch {
            deadline.cancel()
            transport.close()
            return
        }
        deadline.cancel()
        guard said.claim(), hello.v == CartoucheBridgeCable.version, !hello.mac.isEmpty else {
            transport.close()
            return
        }
        if let ticket = hello.ticket {
            hand(transport, ticket: ticket, from: hello.mac)
        } else {
            await keep(Link(mac: hello.mac, name: hello.name.isEmpty ? "Mac" : hello.name, transport: transport))
        }
    }

    /// A connection to the Mac MAC_ID through the cable, to open a session
    /// or a pairing on: nil when it is not linked, or when it does not open
    /// the connection within PATIENCE, in seconds. Cancelling the task gives
    /// nil at once.
    public func session(with macID: String, patience: TimeInterval = CartoucheBridgeCable.ticketPatience) async -> CartoucheBridgeTransport? {
        lock.lock()
        let link = links.last { $0.mac == macID }
        lock.unlock()
        guard let link else { return nil }
        let ticket = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CartoucheBridgeTransport?, Never>) in
                lock.lock()
                tickets[ticket] = Waiting(mac: macID, continuation: continuation)
                lock.unlock()
                if Task.isCancelled {
                    resolve(ticket, with: nil)
                    return
                }
                Task {
                    await link.gate.enter()
                    do {
                        try await link.transport.sendFrame(JSONEncoder().encode(CartoucheBridgeCable.Ask(ticket: ticket)))
                    } catch {
                        // The link is gone: closing it ends its reads.
                        link.transport.close()
                        self.resolve(ticket, with: nil)
                    }
                    await link.gate.leave()
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(patience * 1_000_000_000))
                    self.resolve(ticket, with: nil)
                }
            }
        } onCancel: {
            resolve(ticket, with: nil)
        }
    }

    // MARK: Inside

    /// Keeps LINK until it goes: closed by the Mac, unplugged, or silent
    /// too long.
    private func keep(_ link: Link) async {
        lock.lock()
        links.append(link)
        lock.unlock()
        announce()
        let silence = self.silence
        let watch = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(silence / 4 * 1_000_000_000))
                if Task.isCancelled { break }
                if Date().timeIntervalSince(link.lastHeard) > silence {
                    link.transport.close()
                    break
                }
            }
        }
        while true {
            do {
                _ = try await link.transport.receiveFrame()
                link.touch()
            } catch {
                break
            }
        }
        watch.cancel()
        link.transport.close()
        lock.lock()
        links.removeAll { $0 === link }
        lock.unlock()
        announce()
    }

    /// The connection TRANSPORT, which the Mac MAC opened for TICKET, to the
    /// session waiting for it; closed when none waits, or another Mac than
    /// the one asked says it opened it.
    private func hand(_ transport: CartoucheBridgeTransport, ticket: String, from mac: String) {
        lock.lock()
        let waiting = tickets.removeValue(forKey: ticket)
        lock.unlock()
        guard let waiting else {
            transport.close()
            return
        }
        if waiting.mac == mac {
            waiting.continuation.resume(returning: transport)
        } else {
            transport.close()
            waiting.continuation.resume(returning: nil)
        }
    }

    /// Gives the session waiting for TICKET what it waits for, once.
    private func resolve(_ ticket: String, with transport: CartoucheBridgeTransport?) {
        lock.lock()
        let waiting = tickets.removeValue(forKey: ticket)
        lock.unlock()
        if let waiting {
            waiting.continuation.resume(returning: transport)
        } else {
            transport?.close()
        }
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
}
