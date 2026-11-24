//
//  BridgeCable.swift
//  Cartouche Builder
//
//  The bridge through the cable, the Mac's side: each iPhone plugged into
//  this Mac by USB, as usbmuxd tells (Usbmux.swift), is tried every few
//  seconds on the port where Cartouche listens on it, its loopback
//  (CartoucheBridgeCable.swift). Once Cartouche answers, the Mac keeps that
//  connection, its link, says which Mac it is there and that it is still
//  there, and opens another connection for each ticket Cartouche gives on
//  it. Those go to the bridge's server as the network's do (BridgeServer's
//  open): the same handshake with the paired key, the same pairing with
//  its six digits, the same two folders. No Wi-Fi needed, nothing to
//  install: usbmuxd is macOS's.
//
//  An iPhone the Mac reaches by the network only (Wi-Fi sync) is left to
//  Bonjour. The iPhone must trust this Mac, as the Finder asks once.
//

import CartoucheCore
import Foundation

public final class BridgeCable: @unchecked Sendable {
    /// How long the Mac waits before it tries an iPhone plugged in again,
    /// once Cartouche did not answer there or the link went, in seconds.
    public static let retry: TimeInterval = 2
    /// How long it waits before it asks usbmuxd again, once it went or
    /// could not be reached, in seconds.
    public static let usbmuxdRetry: TimeInterval = 5

    let client: UsbmuxClient
    let port: UInt16
    private let retry: TimeInterval
    private let beat: TimeInterval
    /// This Mac's ID in Cartouche Builder and its name, as it says them.
    private let identity: @Sendable () -> (mac: String, name: String)
    /// What takes each connection a ticket opened: the bridge's server.
    private let open: @Sendable (any CartoucheBridgeTransport & Sendable) async -> Void

    private let lock = NSLock()
    private var watching: Task<Void, Never>?
    private var followed: [Int: Task<Void, Never>] = [:]
    private var linked: Set<Int> = []

    public init(client: UsbmuxClient = UsbmuxClient(), port: UInt16 = CartoucheBridgeCable.port,
                retry: TimeInterval = BridgeCable.retry, beat: TimeInterval = CartoucheBridgeCable.beat,
                identity: @escaping @Sendable () -> (mac: String, name: String),
                open: @escaping @Sendable (any CartoucheBridgeTransport & Sendable) async -> Void) {
        self.client = client
        self.port = port
        self.retry = retry
        self.beat = beat
        self.identity = identity
        self.open = open
    }

    /// The iPhones plugged in whose Cartouche is linked now, by usbmuxd's
    /// number.
    public var linkedDevices: Set<Int> {
        lock.lock()
        defer { lock.unlock() }
        return linked
    }

    /// Follows the iPhones plugged in from now on, until stop.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await event in self.client.events() {
                        self.handle(event)
                    }
                } catch {
                    // usbmuxd went, or is not there: asked again below.
                }
                self.leaveAll()
                try? await Task.sleep(nanoseconds: UInt64(BridgeCable.usbmuxdRetry * 1_000_000_000))
            }
        }
    }

    public func stop() {
        lock.lock()
        let current = watching
        watching = nil
        lock.unlock()
        current?.cancel()
        leaveAll()
    }

    // MARK: Inside

    private func handle(_ event: Usbmux.Event) {
        switch event {
        case let .attached(device):
            guard device.usb else { return }
            lock.lock()
            defer { lock.unlock() }
            guard followed[device.id] == nil else { return }
            followed[device.id] = Task { [weak self] in await self?.follow(device.id) }
        case let .detached(id):
            lock.lock()
            let task = followed.removeValue(forKey: id)
            lock.unlock()
            task?.cancel()
        }
    }

    private func leaveAll() {
        lock.lock()
        let tasks = Array(followed.values)
        followed.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    /// The iPhone DEVICE, while it stays plugged in: its link with
    /// Cartouche, kept while Cartouche listens, tried again a moment after
    /// it went or did not answer.
    private func follow(_ device: Int) async {
        while !Task.isCancelled {
            if let stream = try? await client.connect(device: device, port: port) {
                let me = identity()
                setLinked(device, true)
                await withTaskCancellationHandler {
                    await CartoucheBridgeCable.serveLink(stream, mac: me.mac, name: me.name, beat: beat) { [weak self] ticket in
                        await self?.session(device, ticket: ticket)
                    }
                } onCancel: {
                    stream.close()
                }
                setLinked(device, false)
            }
            try? await Task.sleep(nanoseconds: UInt64(retry * 1_000_000_000))
        }
    }

    /// A connection to the iPhone DEVICE for TICKET, which Cartouche gave on
    /// the link, handed to the bridge's server once it says the ticket.
    private func session(_ device: Int, ticket: String) async {
        guard let stream = try? await client.connect(device: device, port: port) else { return }
        let me = identity()
        do {
            try await CartoucheBridgeCable.sayTicket(ticket, on: stream, mac: me.mac, name: me.name)
        } catch {
            stream.close()
            return
        }
        await open(stream)
    }

    private func setLinked(_ device: Int, _ on: Bool) {
        lock.lock()
        if on { linked.insert(device) } else { linked.remove(device) }
        lock.unlock()
    }
}
