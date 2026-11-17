//
//  ConsoleConnectionSaves.swift
//  Cartouche on the Mac
//
//  The saves folder the player chose on the iPhone, on one of their
//  connections (a NAS's shared folder, an S3 bucket, an FTP or SFTP server,
//  a Google Drive), as Cartouche Builder keeps the saves of the games played
//  on this Mac in step with it: by the iPhone's own code
//  (Shared/CartoucheStorageSaves.swift, CartoucheSavesFolder), signed in to
//  as the iPhone signs in, with the connection the console keeps the same
//  as the iPhone's (CartoucheConnections.swift). What the Mac adds, the
//  iPhone's code takes too: a game started from the Dock meanwhile keeps the
//  saves it found (quiet), and saves the Mac kept in step with another
//  saves folder, unchanged since, are no news here (leaving). The Builder
//  drives it, one game at a time (BuilderKit's MacConnectionSaves.swift),
//  and keeps each game's base, which goes between the two as JSON.
//
//  A connection signed in to stays open a moment between two syncs, as a
//  round of them goes through the games one after the other; the copies
//  of a game, which the player lists from its sheet, take one of their own.
//

import Foundation

/// What a sync did, as the Builder takes it (MacConnectionOutcome).
public struct CartoucheMacConnectionOutcome: Equatable, Sendable {
    /// The step, as CartoucheSaveStep names it.
    public var step: String
    /// The base it leaves, as JSON (CartoucheSaveBase).
    public var base: Data?
    public var sent: String?
    public var kept: String?
    public var fetched: String?
    /// The version of the game the newest copy names, when it held the copy
    /// back.
    public var newer: String?
}

/// The iPhone's saves folder on one of the player's connections, as the
/// Builder keeps the saves of this Mac's games in step with it. What it
/// could not do throws CartoucheMacSaveError: offline for a server that
/// does not answer from here or a connection no longer there, busy for a
/// game started meanwhile, unreadable for a copy that does not read as a
/// copy of saves, newerGame for one a newer version of the game wrote; the
/// rest throws as the iPhone's code does, in the player's words.
public actor CartoucheMacConnectionSaves {
    public nonisolated let connection: UUID
    /// The folder's path on the connection.
    public nonisolated let path: String
    /// What its bases hold for, as the iPhone names its own.
    public nonisolated var place: String { connection.uuidString + "|" + path }
    /// A folder of the Builder's, where the copies that come are unpacked.
    private let scratch: URL
    private let settings: CartoucheStorageSettings
    private var remote: CartoucheRemote?
    private var using = 0
    private var lastUse = Date.distantPast
    private var closing: Task<Void, Never>?
    /// How long a connection stays open after a sync, in seconds.
    static let idle: TimeInterval = 30

    public init(connection: UUID, path: String, scratch: URL) {
        self.init(connection: connection, path: path, scratch: scratch, settings: .shared)
    }

    init(connection: UUID, path: String, scratch: URL, settings: CartoucheStorageSettings) {
        self.connection = connection
        self.path = path
        self.scratch = scratch
        self.settings = settings
    }

    /// Keeps the saves in DOCUMENTS, those of the game of TITLEID, NAME and
    /// VERSION, in step with its copies in the folder, from BASE, the last
    /// time both were the same (as JSON): FETCHING lets the newest copy
    /// come; LEAVING says whether the copy of a base of another saves
    /// folder is still there; QUIET, just before a copy takes the place of
    /// the saves, that the game still does not run.
    public func sync(titleID: String, name: String, version: String?, documents: URL, base: Data?, fetching: Bool,
                     leaving: @escaping @Sendable () -> Bool, quiet: @Sendable () -> Bool) async throws -> CartoucheMacConnectionOutcome {
        let target = Self.target(titleID: titleID, name: name, version: version, documents: documents)
        let given = base.flatMap(Self.decode)
        return try await withFolder { folder in
            Self.outcome(try await folder.sync(target, base: given, fetching: fetching, leaving: leaving, quiet: quiet))
        }
    }

    /// Puts the copy NAME back as the game's saves in DOCUMENTS, as the
    /// player chose it on its sheet: this Mac's go to the folder first,
    /// unless it has them already, and the copy put back becomes the newest
    /// one there, which the iPhones take.
    public func putBack(_ copy: String, titleID: String, name: String, version: String?, documents: URL, base: Data?,
                        quiet: @Sendable () -> Bool) async throws -> CartoucheMacConnectionOutcome {
        let target = Self.target(titleID: titleID, name: name, version: version, documents: documents)
        let given = base.flatMap(Self.decode)
        return try await withFolder { folder in
            Self.outcome(try await folder.putBack(copy, of: target, base: given, quiet: quiet))
        }
    }

    /// The game's copies in the folder, the newest first, on a connection
    /// of their own.
    public func copies(titleID: String, name: String, documents: URL) async throws -> [CartoucheMacSaveCopy] {
        let target = Self.target(titleID: titleID, name: name, version: nil, documents: documents)
        let remote = try await Self.mapped { try await self.signIn() }
        let folder = CartoucheSavesFolder(remote: remote, path: path, place: place, scratch: scratch)
        do {
            let copies = try await Self.mapped { try await folder.copies(of: target) }
            await remote.disconnect()
            return copies.map { CartoucheMacSaveCopy(name: CartoucheStoragePath.name($0.path), date: $0.date, size: $0.size) }
        } catch {
            await remote.disconnect()
            throw error
        }
    }

    // MARK: The connection

    /// WORK on the folder, on the connection kept open, or signed in to
    /// again: one that failed is closed, the next sync signing in again.
    private func withFolder<T>(_ work: (CartoucheSavesFolder) async throws -> T) async throws -> T {
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
            remote = try await Self.mapped { try await self.signIn() }
            self.remote = remote
        }
        let folder = CartoucheSavesFolder(remote: remote, path: path, place: place, scratch: scratch)
        do {
            return try await Self.mapped { try await work(folder) }
        } catch let error as CartoucheMacSaveError where error != .offline {
            // The folder answered: the connection stays.
            throw error
        } catch {
            if self.remote === remote { self.remote = nil }
            await remote.disconnect()
            throw error
        }
    }

    /// Signs in to the connection, as the iPhone does: offline when it is
    /// no longer there.
    private func signIn() async throws -> CartoucheRemote {
        let settings = self.settings
        let connection = self.connection
        guard let server = await MainActor.run(body: { settings.server(connection) }), server.travels else {
            throw CartoucheMacSaveError.offline
        }
        return try await CartoucheStorage.connect(server, settings: settings)
    }

    /// Closes the connection once no sync used it for a moment.
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

    // MARK: Between the console and the Builder

    private static func target(titleID: String, name: String, version: String?, documents: URL) -> CartoucheSaveTarget {
        CartoucheSaveTarget(key: titleID.uppercased(), name: name, titleId: titleID.uppercased(), documents: documents,
                            gameVersion: version)
    }

    private static func decode(_ data: Data) -> CartoucheSaveBase? {
        try? JSONDecoder().decode(CartoucheSaveBase.self, from: data)
    }

    private static func outcome(_ outcome: CartoucheSaveOutcome) -> CartoucheMacConnectionOutcome {
        CartoucheMacConnectionOutcome(step: outcome.step.rawValue, base: outcome.base.flatMap { try? JSONEncoder().encode($0) },
                                      sent: outcome.sent, kept: outcome.kept, fetched: outcome.fetched, newer: outcome.newer)
    }

    /// WORK, with what the iPhone's code throws that the Builder tells
    /// apart as CartoucheMacSaveError.
    static func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch is CartoucheStorageOffline {
            throw CartoucheMacSaveError.offline
        } catch is CartoucheSavesBusy {
            throw CartoucheMacSaveError.busy
        } catch let newer as CartoucheSaveNewerGame {
            throw CartoucheMacSaveError.newerGame(copy: newer.copy, game: newer.game)
        } catch let error as CartoucheStorageError where error.kind == .copyUnreadable {
            throw CartoucheMacSaveError.unreadable
        }
    }
}

extension CartoucheMacConsole {
    /// The connection the folders chosen on an iPhone on the connection ID
    /// are on now: itself, or the one it was replaced by, the same place
    /// added on both sides; nil when it was removed, or is not there.
    public func currentConnection(_ id: UUID) -> UUID? {
        Self.currentConnection(id, in: .shared)
    }

    static func currentConnection(_ id: UUID, in settings: CartoucheStorageSettings) -> UUID? {
        guard let current = CartoucheConnections.current(id, in: settings.connections()),
              settings.server(current)?.travels == true else { return nil }
        return current
    }

    /// The name the player gave the connection ID.
    public func connectionName(_ id: UUID) -> String? {
        CartoucheStorageSettings.shared.server(id)?.name
    }

    /// The connection ID's kind, as the measurements say it: smb, s3, ftp,
    /// sftp or drive.
    public func connectionKind(_ id: UUID) -> String? {
        CartoucheStorageSettings.shared.server(id)?.kind.rawValue
    }
}
