//
//  BridgeDevices.swift
//  Cartouche Builder
//
//  The iPhones paired with this Mac, and the Mac's own ID for them, in
//  bridge.json of the builder's folder: readable only by the player
//  (0600), never in a report. Each paired key opens sessions of its iPhone
//  only; removing it here ends them.
//

import CartoucheCore
import Foundation

public struct PairedDevice: Codable, Identifiable, Equatable, Sendable {
    /// The iPhone's ID for this Mac: the ID of its storage server in Cartouche.
    public var id: String
    public var name: String
    public var key: Data
    public var paired: Date
    public var seen: Date?
    /// Its model ("iPhone15,4") and whether its GPU reads BC textures, as
    /// Cartouche tells them with its info requests (CartoucheBridgeDevice):
    /// nil until it does, from an older Cartouche. The engine reads these
    /// two, never the key, to build the games of an iPhone without BC from
    /// nxnative's no-bc variant (cartouche_builder/build_for.py).
    public var model: String?
    public var readsBC: Bool?

    public init(id: String, name: String, key: Data, paired: Date = Date(), seen: Date? = nil, model: String? = nil, readsBC: Bool? = nil) {
        self.id = id
        self.name = name
        self.key = key
        self.paired = paired
        self.seen = seen
        self.model = model
        self.readsBC = readsBC
    }
}

public final class BridgeDevices: @unchecked Sendable {
    struct File: Codable {
        var mac: String
        var devices: [PairedDevice]
    }

    public let url: URL
    private let lock = NSLock()
    private var file: File

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let file = try? decoder.decode(File.self, from: data), !file.mac.isEmpty {
            self.file = file
        } else {
            file = File(mac: UUID().uuidString, devices: [])
            save()
        }
    }

    public var macID: String {
        lock.lock()
        defer { lock.unlock() }
        return file.mac
    }

    public var all: [PairedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return file.devices.sorted { $0.paired < $1.paired }
    }

    public func key(of device: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return file.devices.first { $0.id == device }?.key
    }

    public func add(id: String, name: String, key: Data) {
        lock.lock()
        file.devices.removeAll { $0.id == id }
        file.devices.append(PairedDevice(id: id, name: name, key: key, paired: Date(), seen: Date()))
        lock.unlock()
        save()
    }

    /// Keeps what the paired device ID tells of itself: whether it changed.
    @discardableResult
    public func describe(_ id: String, as device: CartoucheBridgeDevice) -> Bool {
        lock.lock()
        guard let index = file.devices.firstIndex(where: { $0.id == id }),
              file.devices[index].model != device.model || file.devices[index].readsBC != device.readsBC else {
            lock.unlock()
            return false
        }
        file.devices[index].model = device.model
        file.devices[index].readsBC = device.readsBC
        lock.unlock()
        save()
        return true
    }

    public func remove(_ id: String) {
        lock.lock()
        file.devices.removeAll { $0.id == id }
        lock.unlock()
        save()
    }

    public func seen(_ id: String) {
        lock.lock()
        guard let index = file.devices.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        file.devices[index].seen = Date()
        lock.unlock()
        save()
    }

    /// Writes the file whole, readable by the player only.
    private func save() {
        lock.lock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(file)
        lock.unlock()
        guard let data else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8))")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temporary.path, url.path) != 0 {
            try? manager.removeItem(at: temporary)
        }
    }
}
