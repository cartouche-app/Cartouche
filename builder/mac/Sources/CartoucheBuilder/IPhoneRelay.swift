//
//  IPhoneRelay.swift
//  Cartouche Builder
//
//  The player's connections, as the bridge reads a game of the iPhone's
//  games folders on a NAS for an iPhone plugged into this Mac and passes it
//  on through the cable (BuilderKit's BridgeRelay.swift, decision 162):
//  Cartouche's console reaches them by the iPhone's own code
//  (CartoucheMacRelayFile). The bridge decides whether it may.
//

import BuilderKit
import CartoucheConsole
import Foundation

final class IPhoneRelay: BridgeRelaySource, @unchecked Sendable {
    func relayServer(_ connection: UUID) async -> BridgeRelayServer? {
        guard let place = await CartoucheMacRelayFile.place(of: connection) else { return nil }
        return BridgeRelayServer(kind: place.kind, host: place.host, port: place.port)
    }

    func relayOpen(_ connection: UUID, path: String) async throws -> any BridgeRelayFile {
        IPhoneRelayFile(try await CartoucheMacRelayFile.open(connection, path: path))
    }
}

/// A file the console opened, as the bridge reads it.
private final class IPhoneRelayFile: BridgeRelayFile, @unchecked Sendable {
    private let file: CartoucheMacRelayFile

    init(_ file: CartoucheMacRelayFile) {
        self.file = file
    }

    var size: UInt64 { file.size }

    func read(at offset: UInt64, count: Int) async throws -> Data {
        try await file.read(at: offset, count: count)
    }

    func close() async {
        await file.close()
    }
}
