//
//  ConsoleRelay.swift
//  Cartouche on the Mac
//
//  A file of the iPhone's games folders on one of the player's connections,
//  a NAS's, which Cartouche Builder reads for an iPhone plugged into this
//  Mac and passes on through the cable (BuilderKit's BridgeRelay.swift,
//  decision 162): by the iPhone's own code (Shared/CartoucheStorage.swift),
//  signed in to as the iPhone signs in, with the connection the console
//  keeps the same as the iPhone's (CartoucheConnections.swift). Builder
//  decides whether it may; this reaches the file, one read at a time on its
//  connection, which closes with it.
//

import Foundation

/// Where one of the player's connections' server is, as the console has
/// it.
public struct CartoucheMacRelayPlace: Equatable, Sendable {
    /// The kind of place: smb, ftp, sftp, s3 or drive.
    public var kind: String
    public var host: String
    public var port: Int?
}

/// A file of one of the player's connections, open on its server.
public final class CartoucheMacRelayFile: @unchecked Sendable {
    public let size: UInt64
    private let source: CartoucheByteSource
    private let remote: CartoucheRemote

    private init(source: CartoucheByteSource, remote: CartoucheRemote) {
        size = source.size
        self.source = source
        self.remote = remote
    }

    /// Where the server of the connection CONNECTION is: nil for one the
    /// console does not have, or that stays on the iPhone.
    public static func place(of connection: UUID) async -> CartoucheMacRelayPlace? {
        await MainActor.run {
            guard let server = CartoucheStorageSettings.shared.server(connection), server.travels else { return nil }
            return CartoucheMacRelayPlace(kind: server.kind.rawValue, host: server.host, port: server.port)
        }
    }

    /// The file at PATH on CONNECTION, from its root, opened: offline for a
    /// server that does not answer from here, and what the server answers.
    public static func open(_ connection: UUID, path: String) async throws -> CartoucheMacRelayFile {
        let settings = CartoucheStorageSettings.shared
        guard let server = await MainActor.run(body: { settings.server(connection) }), server.travels else {
            throw CartoucheMacGamesError.offline
        }
        let remote = try await CartoucheMacConnectionGames.mapped { try await CartoucheStorage.connect(server, settings: settings) }
        do {
            return CartoucheMacRelayFile(source: try await remote.open(path), remote: remote)
        } catch {
            await remote.disconnect()
            throw error
        }
    }

    /// COUNT bytes at OFFSET, fewer only at the end of the file.
    public func read(at offset: UInt64, count: Int) async throws -> Data {
        try await source.read(at: offset, count: count)
    }

    public func close() async {
        await remote.disconnect()
    }
}
