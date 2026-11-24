//
//  CartoucheCableListener.swift
//  Cartouche
//
//  Cartouche's ear on the cable: it listens on the iPhone's own loopback,
//  where Cartouche Builder reaches it through usbmuxd once the iPhone is
//  plugged into the Mac, and nothing from a network arrives
//  (CartoucheBridgeCable.swift). Each connection the Mac opens goes to the
//  cable's links (CartoucheCableLinks). Listening needs no permission of
//  iOS: the loopback is not the local network.
//
//  It starts with Cartouche's screens and again each time Cartouche comes
//  to the front, as iOS may close a listener of an app it suspended. When a
//  Mac is linked, the servers in use that were found offline are tried
//  again: plugging the cable in changes nothing of the network the iPhone
//  watches.
//

import Foundation
import Network

final class CartoucheCableListener: @unchecked Sendable {
    static let shared = CartoucheCableListener()

    private let port: UInt16
    private let links: CartoucheCableLinks
    private let queue = DispatchQueue(label: "Cartouche cable")
    private let lock = NSLock()
    private var listener: NWListener?
    /// Whether it should listen: from start until stop.
    private var wanted = false
    private var watching: NSObjectProtocol?

    /// How long it waits before it listens again once its listener failed,
    /// in seconds.
    static let retry: TimeInterval = 2

    /// The tests listen on a port of their own, with links of their own.
    init(port: UInt16 = CartoucheBridgeCable.port, links: CartoucheCableLinks = .shared) {
        self.port = port
        self.links = links
    }

    /// Whether it listens now.
    var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil
    }

    /// Listens from now on, unless it does already; waits until it does,
    /// or could not.
    @discardableResult
    func start() async -> Bool {
        let running = locked {
            wanted = true
            return listener != nil
        }
        if running { return true }
        let parameters = CartoucheBridgeConnection.parameters()
        // The loopback alone: the Mac's connections come out of usbmuxd
        // there, and nothing of the Wi-Fi reaches it.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: port), let made = try? NWListener(using: parameters, on: port) else { return false }
        made.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            let transport = CartoucheBridgeConnection(connection, queue: self.queue)
            Task {
                do {
                    try await transport.start(timeout: CartoucheBridgeCable.helloPatience)
                } catch {
                    transport.close()
                    return
                }
                await self.links.take(transport)
            }
        }
        locked { listener = made }
        let once = CartoucheBridgeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            made.stateUpdateHandler = { [weak self, weak made] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: true) }
                case .failed, .cancelled:
                    // Taken by another app, or closed by iOS while Cartouche
                    // was away, even once it is back: listens again a moment
                    // later, until stopped.
                    let failed: Bool
                    if case .failed = state { failed = true } else { failed = false }
                    made?.cancel()
                    if let self {
                        self.lock.lock()
                        if self.listener === made { self.listener = nil }
                        let again = failed && self.wanted
                        self.lock.unlock()
                        if again {
                            Task { [weak self] in
                                try? await Task.sleep(nanoseconds: UInt64(CartoucheCableListener.retry * 1_000_000_000))
                                guard let self, self.isWanted else { return }
                                await self.start()
                            }
                        }
                    }
                    if once.claim() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            made.start(queue: queue)
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
        lock.lock()
        let current = listener
        listener = nil
        wanted = false
        lock.unlock()
        current?.cancel()
    }

    private var isWanted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wanted
    }
}

#if os(iOS)
extension CartoucheCableListener {
    /// Listens, and from the first call on, tries the servers in use found
    /// offline again each time a Mac is linked.
    @MainActor
    func startWithApp() {
        if watching == nil {
            let links = self.links
            watching = NotificationCenter.default.addObserver(forName: CartoucheCableLinks.changed, object: links, queue: .main) { _ in
                Task { @MainActor in
                    let linked = Set(links.macs.map(\.id))
                    let reach = CartoucheStorageReach.shared
                    for server in reach.offlineInUse where server.kind == .mac && linked.contains(server.macID ?? "") {
                        _ = await reach.tryAgain(server)
                    }
                }
            }
        }
        Task { await start() }
    }
}
#endif
