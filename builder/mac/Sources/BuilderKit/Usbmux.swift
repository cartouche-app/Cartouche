//
//  Usbmux.swift
//  Cartouche Builder
//
//  usbmuxd, macOS's own way to the iPhones plugged into the Mac, which the
//  Finder and the Cartouche Installer use too: a Unix socket any app of the
//  player's may open, /var/run/usbmuxd, nothing to install. Each message is
//  a 16-byte header, little-endian (the message's length with the header,
//  the protocol's version, 1, its kind, 8 for a property list, and a tag
//  the answer repeats), then an XML property list. Listen gives the
//  iPhones plugged in, then each one that comes or goes (Attached,
//  Detached); Connect opens a connection to a port of one, given in network
//  order, and from its Result on the socket carries that connection's bytes
//  alone. An iPhone reaches no port of the Mac this way: only the Mac
//  opens, and only to a port where an app of the iPhone listens.
//
//  The bridge's frames go over such a connection as over the network's
//  (UsbmuxStream), for the bridge through the cable (BridgeCable.swift).
//

import CartoucheCore
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum Usbmux {
    /// Where macOS's usbmuxd listens.
    public static let socketPath = "/var/run/usbmuxd"
    /// The name the Mac's app gives usbmuxd.
    static let clientName = "Cartouche Builder"

    /// An iPhone usbmuxd knows: by USB, or by the network for an iPhone
    /// that syncs with the Mac over Wi-Fi.
    public struct Device: Equatable, Sendable {
        /// usbmuxd's number for it while it stays plugged in.
        public let id: Int
        public let serial: String
        public let usb: Bool

        public init(id: Int, serial: String, usb: Bool) {
            self.id = id
            self.serial = serial
            self.usb = usb
        }
    }

    public enum Event: Equatable, Sendable {
        case attached(Device)
        case detached(Int)
    }

    /// What usbmuxd refused: its Result's number (2, no such device; 3,
    /// nothing listens on that port of the iPhone), or nothing it reads.
    public struct Refusal: Error, Equatable {
        public let number: Int?
    }

    // MARK: Messages

    /// MESSAGE, a property list, as usbmuxd reads it, with TAG.
    static func packet(_ message: [String: Any], tag: UInt32) throws -> Data {
        let body = try PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
        var data = Data()
        for value in [UInt32(16 + body.count), 1, 8, tag] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(body)
        return data
    }

    /// The length a header gives its message, header with it.
    static func length(of header: Data) -> Int {
        let bytes = [UInt8](header.prefix(4))
        guard bytes.count == 4 else { return 0 }
        return Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
    }

    /// The property list of a message's body.
    static func message(_ body: Data) throws -> [String: Any] {
        guard let message = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw Refusal(number: nil)
        }
        return message
    }

    static func listen() -> [String: Any] {
        ["MessageType": "Listen", "ClientVersionString": clientName, "ProgName": clientName, "kLibUSBMuxVersion": 3]
    }

    static func connect(device: Int, port: UInt16) -> [String: Any] {
        ["MessageType": "Connect", "DeviceID": device, "PortNumber": portNumber(port),
         "ClientVersionString": clientName, "ProgName": clientName, "kLibUSBMuxVersion": 3]
    }

    /// PORT as usbmuxd reads it: its two bytes in network order, read as a
    /// number of this Mac's.
    static func portNumber(_ port: UInt16) -> Int {
        Int(port.bigEndian)
    }

    /// A Result's number; nil for another message.
    static func result(_ message: [String: Any]) -> Int? {
        guard message["MessageType"] as? String == "Result" else { return nil }
        return (message["Number"] as? NSNumber)?.intValue
    }

    /// The device that came or went, from an event of Listen.
    static func event(_ message: [String: Any]) -> Event? {
        let id = (message["DeviceID"] as? NSNumber)?.intValue
        switch message["MessageType"] as? String {
        case "Attached":
            let properties = message["Properties"] as? [String: Any] ?? [:]
            guard let id = id ?? (properties["DeviceID"] as? NSNumber)?.intValue else { return nil }
            return .attached(Device(id: id, serial: properties["SerialNumber"] as? String ?? "",
                                    usb: (properties["ConnectionType"] as? String ?? "USB") == "USB"))
        case "Detached":
            return id.map { .detached($0) }
        default:
            return nil
        }
    }
}

// MARK: The socket

/// A stream socket, read and written on its own two queues, a blocking call
/// at a time each: what usbmuxd gives, and, once Connect answered, an
/// iPhone's port. Closing it ends the calls waiting; its descriptor goes
/// with it.
public final class UsbmuxSocket: @unchecked Sendable {
    let descriptor: Int32
    private let reads = DispatchQueue(label: "io.github.clabeuhtegrite.cartouche-builder.usbmux.read")
    private let writes = DispatchQueue(label: "io.github.clabeuhtegrite.cartouche-builder.usbmux.write")
    private let lock = NSLock()
    private var closed = false

    init(descriptor: Int32) {
        self.descriptor = descriptor
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    deinit {
        closeDescriptor(descriptor)
    }

    /// Connects to the Unix socket at PATH.
    static func open(_ path: String) throws -> UsbmuxSocket {
        #if canImport(Darwin)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw CartoucheBridgeError(.closed, String(cString: strerror(errno))) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            closeDescriptor(descriptor)
            throw CartoucheBridgeError(.closed, "path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let error = String(cString: strerror(errno))
            closeDescriptor(descriptor)
            throw CartoucheBridgeError(.closed, error)
        }
        return UsbmuxSocket(descriptor: descriptor)
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Ends the reads and writes waiting, at once, and those to come.
    public func close() {
        lock.lock()
        let first = !closed
        closed = true
        lock.unlock()
        if first { shutdown(descriptor, Int32(SHUT_RDWR)) }
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writes.async { [self] in
                do {
                    try writeNow(data)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func read(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            reads.async { [self] in
                do {
                    continuation.resume(returning: try readNow(exactly: count))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func writeNow(_ data: Data) throws {
        guard !isClosed else { throw CartoucheBridgeError(.closed) }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                #if canImport(Darwin)
                let wrote = send(descriptor, base + sent, raw.count - sent, 0)
                #else
                let wrote = send(descriptor, base + sent, raw.count - sent, Int32(MSG_NOSIGNAL))
                #endif
                if wrote < 0 && errno == EINTR { continue }
                guard wrote > 0 else { throw CartoucheBridgeError(.closed, wrote < 0 ? String(cString: strerror(errno)) : "") }
                sent += wrote
            }
        }
    }

    private func readNow(exactly count: Int) throws -> Data {
        var data = Data(count: count)
        guard count > 0 else { return data }
        try data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var got = 0
            while got < count {
                guard !isClosed else { throw CartoucheBridgeError(.closed) }
                let read = recv(descriptor, base + got, count - got, 0)
                if read < 0 && errno == EINTR { continue }
                // Nothing more: the other side went.
                guard read > 0 else { throw CartoucheBridgeError(.closed, read < 0 ? String(cString: strerror(errno)) : "") }
                got += read
            }
        }
        return data
    }

    // MARK: usbmuxd's messages

    /// Sends MESSAGE with TAG.
    func sendMessage(_ message: [String: Any], tag: UInt32) async throws {
        try await write(try Usbmux.packet(message, tag: tag))
    }

    /// The next message, and no byte after it.
    func receiveMessage() async throws -> [String: Any] {
        let header = try await read(exactly: 16)
        let length = Usbmux.length(of: header)
        guard length >= 16, length <= 1 << 20 else { throw Usbmux.Refusal(number: nil) }
        return try Usbmux.message(try await read(exactly: length - 16))
    }
}

/// close(2), which UsbmuxSocket's own close hides.
private func closeDescriptor(_ descriptor: Int32) {
    #if canImport(Darwin)
    _ = Darwin.close(descriptor)
    #else
    _ = Glibc.close(descriptor)
    #endif
}

/// The bridge's frames over a connection usbmuxd opened to an iPhone: a
/// 4-byte big-endian length and its bytes, as over the network
/// (CartoucheBridge.swift).
public final class UsbmuxStream: CartoucheBridgeTransport, @unchecked Sendable {
    let socket: UsbmuxSocket

    init(_ socket: UsbmuxSocket) {
        self.socket = socket
    }

    public func sendFrame(_ data: Data) async throws {
        guard data.count <= CartoucheBridge.maxFrame else { throw CartoucheBridgeError(.protocolError, "frame too large") }
        var frame = Data()
        let length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
        frame.append(data)
        try await socket.write(frame)
    }

    public func receiveFrame() async throws -> Data {
        let header = try await socket.read(exactly: 4)
        let bytes = [UInt8](header)
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard length <= CartoucheBridge.maxFrame else { throw CartoucheBridgeError(.protocolError, "frame too large") }
        return try await socket.read(exactly: length)
    }

    public func close() {
        socket.close()
    }
}

// MARK: The client

/// usbmuxd at PATH: the iPhones plugged in, and connections to them.
public struct UsbmuxClient: Sendable {
    public let path: String

    public init(path: String = Usbmux.socketPath) {
        self.path = path
    }

    /// The iPhones plugged in now, then each one that comes or goes, until
    /// usbmuxd goes or the stream is left.
    public func events() -> AsyncThrowingStream<Usbmux.Event, Error> {
        let path = self.path
        return AsyncThrowingStream { continuation in
            let socket: UsbmuxSocket
            do {
                socket = try UsbmuxSocket.open(path)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.onTermination = { _ in socket.close() }
            Task {
                do {
                    try await socket.sendMessage(Usbmux.listen(), tag: 1)
                    let answer = try await socket.receiveMessage()
                    guard let number = Usbmux.result(answer), number == 0 else {
                        throw Usbmux.Refusal(number: Usbmux.result(answer))
                    }
                    while true {
                        if let event = Usbmux.event(try await socket.receiveMessage()) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    socket.close()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// A connection to PORT of the iPhone DEVICE: refused when nothing
    /// listens there (Refusal 3), as when Cartouche is not open on it.
    /// Cancelling the task closes it.
    public func connect(device: Int, port: UInt16) async throws -> UsbmuxStream {
        try Task.checkCancellation()
        let socket = try UsbmuxSocket.open(path)
        return try await withTaskCancellationHandler {
            do {
                try await socket.sendMessage(Usbmux.connect(device: device, port: port), tag: 2)
                let answer = try await socket.receiveMessage()
                guard let number = Usbmux.result(answer), number == 0 else {
                    throw Usbmux.Refusal(number: Usbmux.result(answer))
                }
                try Task.checkCancellation()
                return UsbmuxStream(socket)
            } catch {
                socket.close()
                throw error
            }
        } onCancel: {
            socket.close()
        }
    }
}
