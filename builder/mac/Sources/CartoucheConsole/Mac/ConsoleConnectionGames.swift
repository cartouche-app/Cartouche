//
//  ConsoleConnectionGames.swift
//  Cartouche on the Mac
//
//  The games folder the player chose on the iPhone, on one of their
//  connections (a NAS's shared folder, an S3 bucket, an FTP or SFTP server,
//  a Google Drive), as Cartouche Builder sends its games there and fetches
//  from there the Mac apps another Mac sent, which the console installs:
//  by the iPhone's own code (Shared/CartoucheStorage.swift), signed in to
//  as the iPhone signs in, with the connection the console keeps the same
//  as the iPhone's (CartoucheConnections.swift). The Builder decides what
//  goes and what comes (BuilderKit's ConnectionGames.swift); this reaches
//  the folder: its files, the room left there, whether the player's
//  account may write there, a file sent whole in the place of the one of
//  its name, or fetched, reading on where it stopped when the network
//  drops for a moment (CartoucheResumingSource).
//
//  A connection signed in to stays open a moment between two calls, as a
//  round goes through the games one after the other.
//

import Foundation

/// Why the folder could not be reached.
public enum CartoucheMacGamesError: Error, Equatable {
    /// Its server does not answer from here, or the connection is no longer
    /// there.
    case offline
}

/// A file at the top of the iPhone's games folder.
public struct CartoucheMacConnectionFile: Equatable, Sendable {
    public var name: String
    public var size: UInt64
    public var modified: Date?
}

/// The iPhone's games folder on one of the player's connections, as the
/// Builder sends its games there and fetches from there the Mac apps the
/// console installs. What it could not do throws
/// CartoucheMacGamesError.offline for a server that does not answer from
/// here; the rest throws as the iPhone's code does, in the player's words.
public actor CartoucheMacConnectionGames {
    public nonisolated let connection: UUID
    /// The folder's path on the connection.
    public nonisolated let path: String
    private let settings: CartoucheStorageSettings
    private var remote: CartoucheRemote?
    private var using = 0
    private var lastUse = Date.distantPast
    private var closing: Task<Void, Never>?
    /// How long a connection stays open after a call, in seconds.
    static let idle: TimeInterval = 30
    /// How much of a file goes or comes at a time.
    static let chunk = 8 << 20

    public init(connection: UUID, path: String) {
        self.init(connection: connection, path: path, settings: .shared)
    }

    init(connection: UUID, path: String, settings: CartoucheStorageSettings) {
        self.connection = connection
        self.path = path
        self.settings = settings
    }

    /// The files at the folder's top, without its folders.
    public func files() async throws -> [CartoucheMacConnectionFile] {
        let path = self.path
        return try await withRemote { remote in
            try await remote.list(path).filter { !$0.isFolder }
                .map { CartoucheMacConnectionFile(name: $0.name, size: $0.size, modified: $0.modified) }
        }
    }

    /// The room left there, when the server says.
    public func room() async throws -> UInt64? {
        try await withRemote { remote in try await remote.freeSpace() }
    }

    /// Whether the player's account may add a file there, as Cartouche
    /// found or finds now: a shared folder that lets it read only says no.
    public func canWrite() async throws -> Bool {
        let settings = self.settings
        let connection = self.connection
        let path = self.path
        return try await withRemote { remote in
            await settings.checkAccess(remote, server: connection, path: path) != false
        }
    }

    /// Sends FILE there as NAME, in the place of the file of that name only
    /// once whole; PROGRESS hears the bytes sent so far.
    public func send(_ file: URL, as name: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let target = CartoucheStoragePath.join(path, name)
        try await withRemote { remote in
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            let size = try reader.seekToEnd()
            try reader.seek(toOffset: 0)
            let upload = try await remote.create(target, size: size)
            do {
                var done: UInt64 = 0
                while done < size {
                    try Task.checkCancellation()
                    guard let data = try reader.read(upToCount: Self.chunk), !data.isEmpty else { break }
                    try await upload.write(data)
                    done += UInt64(data.count)
                    progress(done)
                }
                guard done == size else { throw CocoaError(.fileReadUnknown) }
                try await upload.finish()
            } catch {
                // Out of a stopped task, whose cancellation would leave what
                // it wrote there.
                await Task { await upload.cancel() }.value
                throw error
            }
        }
    }

    /// Fetches NAME from there into FILE, reading on where it stopped when
    /// the network drops for a moment; PROGRESS hears the bytes so far.
    public func fetch(_ name: String, to file: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        let source = CartoucheStoragePath.join(path, name)
        let settings = self.settings
        let connection = self.connection
        try await Self.mapped {
            let server = try await Self.server(connection, in: settings)
            let reading = try await CartoucheResumingSource.open {
                let remote = try await CartoucheStorage.connect(server, settings: settings)
                do {
                    return CartoucheResumingSource.Opened(source: try await remote.open(source), close: { await remote.disconnect() })
                } catch {
                    await remote.disconnect()
                    throw error
                }
            }
            do {
                FileManager.default.createFile(atPath: file.path, contents: nil)
                let writer = try FileHandle(forWritingTo: file)
                defer { try? writer.close() }
                var done: UInt64 = 0
                while done < reading.size {
                    try Task.checkCancellation()
                    let data = try await reading.read(at: done, count: Int(min(UInt64(Self.chunk), reading.size - done)))
                    guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                    try writer.write(contentsOf: data)
                    done += UInt64(data.count)
                    progress(done)
                }
                await reading.close()
            } catch {
                await reading.close()
                throw error
            }
        }
    }

    // MARK: The connection

    /// WORK on the connection kept open, or signed in to again: one that
    /// failed is closed, the next call signing in again.
    private func withRemote<T>(_ work: (CartoucheRemote) async throws -> T) async throws -> T {
        using += 1
        defer {
            using -= 1
            lastUse = Date()
            closeLater()
        }
        let remote: CartoucheRemote
        if let kept = self.remote {
            remote = kept
        } else {
            let settings = self.settings
            let connection = self.connection
            remote = try await Self.mapped {
                try await CartoucheStorage.connect(try await Self.server(connection, in: settings), settings: settings)
            }
            self.remote = remote
        }
        do {
            return try await Self.mapped { try await work(remote) }
        } catch {
            if self.remote === remote { self.remote = nil }
            await remote.disconnect()
            throw error
        }
    }

    /// The connection's server, as the iPhone has it: offline when it is no
    /// longer there.
    private static func server(_ connection: UUID, in settings: CartoucheStorageSettings) async throws -> CartoucheStorageServer {
        guard let server = await MainActor.run(body: { settings.server(connection) }), server.travels else {
            throw CartoucheMacGamesError.offline
        }
        return server
    }

    /// Closes the connection once no call used it for a moment.
    private func closeLater() {
        closing?.cancel()
        closing = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idle * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.closeIfIdle()
        }
    }

    private func closeIfIdle() async {
        guard using == 0, Date().timeIntervalSince(lastUse) >= Self.idle - 1, let remote else { return }
        self.remote = nil
        await remote.disconnect()
    }

    /// WORK, with a server that does not answer from here as
    /// CartoucheMacGamesError.offline.
    static func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch is CartoucheStorageOffline {
            throw CartoucheMacGamesError.offline
        } catch let lost as CartoucheResumingSource.Lost where lost.last is CartoucheStorageOffline {
            throw CartoucheMacGamesError.offline
        }
    }
}
