//
//  BridgeRelay.swift
//  Cartouche Builder
//
//  A game of the iPhone's games folders on a NAS, read here for an iPhone
//  plugged into this Mac and passed on through the cable (decision 162):
//  Cartouche on the iPhone asks for it as its install opens the file
//  (relayStat), then reads it a piece at a time (relayRead), as it reads
//  the Mac's own games folder. The Mac reads the NAS through the player's
//  connection, the one the iPhone gave it (CartoucheConnections.swift), by
//  the console's code, signed in to as the iPhone signs in
//  (BridgeRelaySource, the app's IPhoneRelay.swift), a piece ahead
//  (CartoucheReadingAhead): while one piece goes through the cable, the
//  next comes from the NAS.
//
//  Only through the cable: the Mac's info says so to a session that came
//  that way (relays), and refuses one of the network. Only a server of the
//  local network, a NAS's shared folder, an FTP or SFTP server
//  (CartoucheCableRelay.kinds), and only while this Mac reaches it on its
//  Ethernet, as a connection to it goes (BridgeNetwork.route): on the
//  Mac's Wi-Fi the game would cross the Wi-Fi all the same, and the iPhone
//  reads the NAS itself, as before. Only a file of the games folders the
//  Mac keeps on that connection (CartoucheChosenFolders), never anything
//  else there. The window shows how fast it goes, as for a game of the
//  Mac's own games folder.
//

import CartoucheCore
import Foundation

/// Where a connection's server is, for the way this Mac reaches it.
public struct BridgeRelayServer: Equatable, Sendable {
    /// The kind of place, as the connections name it: smb, ftp, sftp...
    public var kind: String
    public var host: String
    public var port: Int?

    public init(kind: String, host: String, port: Int?) {
        self.kind = kind
        self.host = host
        self.port = port
    }
}

/// A file of one of the player's connections, open on its server.
public protocol BridgeRelayFile: AnyObject, Sendable {
    var size: UInt64 { get }
    /// COUNT bytes at OFFSET, fewer only at the end of the file; one read
    /// at a time.
    func read(at offset: UInt64, count: Int) async throws -> Data
    /// Closes its connection.
    func close() async
}

/// The player's connections as Cartouche's console on this Mac reaches
/// them: the app's.
public protocol BridgeRelaySource: AnyObject, Sendable {
    /// Where the server of the connection CONNECTION is; nil for one this
    /// Mac does not have.
    func relayServer(_ connection: UUID) async -> BridgeRelayServer?
    /// Opens the file at PATH on CONNECTION, from its root.
    func relayOpen(_ connection: UUID, path: String) async throws -> any BridgeRelayFile
}

/// The files a session passes on, open until it ends: two at most, an IPA
/// and the image of its game files.
actor BridgeRelayFiles {
    struct Open: Sendable {
        let file: any BridgeRelayFile
        let reading: CartoucheReadingAhead
    }

    static let most = 2
    private var files: [(key: String, open: Open)] = []

    func open(_ key: String) -> Open? {
        files.first { $0.key == key }?.open
    }

    /// OPEN, as KEY's: the one it replaces, and the oldest beyond the most,
    /// are closed.
    func keep(_ open: Open, as key: String) async {
        var closing = files.filter { $0.key == key }.map(\.open)
        files.removeAll { $0.key == key }
        files.append((key, open))
        while files.count > Self.most {
            closing.append(files.removeFirst().open)
        }
        for old in closing { await Self.close(old) }
    }

    /// KEY's, closed: its server failed.
    func drop(_ key: String) async {
        let closing = files.filter { $0.key == key }.map(\.open)
        files.removeAll { $0.key == key }
        for old in closing { await Self.close(old) }
    }

    func closeAll() async {
        let closing = files.map(\.open)
        files.removeAll()
        for old in closing { await Self.close(old) }
    }

    /// How many are open, for the tests.
    var count: Int { files.count }

    private static func close(_ open: Open) async {
        await open.reading.close()
        await open.file.close()
    }
}

enum BridgeRelay {
    /// How long this Mac tries to reach a server to tell the way it goes
    /// there, in seconds.
    static let routePatience: TimeInterval = 3

    /// What the Mac answers REQUEST, a relayStat or a relayRead of a session
    /// that came through the CABLE or not: the file's size, opened anew for
    /// relayStat, or its bytes, read a piece ahead on the file kept open
    /// (FILES). SOURCE reaches the connections; FOLDERS gives the games
    /// folders the Mac keeps; ROUTE tells how the Mac reaches a server's
    /// host and port; READS counts what goes, for the window.
    static func answer(_ request: CartoucheBridgeRequest, cable: Bool, source: BridgeRelaySource?,
                       folders: () async -> CartoucheChosenFolders?,
                       route: (String, Int) async -> CartoucheMacNetwork?,
                       files: BridgeRelayFiles, reads: BridgeReads) async -> (CartoucheBridgeResponse, Data) {
        guard cable else { return (.failure(.denied, "only through the cable"), Data()) }
        guard let source else { return (.failure(.notFound, "relay"), Data()) }
        guard let connection = request.connection, let path = request.path else {
            return (.failure(.protocolError, "relay"), Data())
        }
        let key = connection.uuidString + "|" + path
        do {
            let open: BridgeRelayFiles.Open
            if request.op == .relayRead, let kept = await files.open(key) {
                open = kept
            } else {
                open = try await opened(path, on: connection, source: source, folders: await folders(), route: route)
                await files.keep(open, as: key)
            }
            var response = CartoucheBridgeResponse()
            response.size = open.file.size
            guard request.op == .relayRead else {
                response.folder = false
                return (response, Data())
            }
            let count = min(max(request.count ?? 0, 0), CartoucheBridge.maxRead)
            let data: Data
            do {
                data = try await open.reading.read(at: request.offset ?? 0, count: count)
            } catch {
                // Its connection is given up: the iPhone opens the file
                // again, here or on the NAS itself.
                await files.drop(key)
                throw error
            }
            reads.add(data.count)
            return (response, data)
        } catch let error as CartoucheBridgeError {
            return (.failure(error.kind, error.message), Data())
        } catch {
            return (.failure(.failed, error.localizedDescription), Data())
        }
    }

    /// The file at PATH on CONNECTION, opened through SOURCE, once the Mac
    /// may pass it on: a NAS's, in one of the games FOLDERS on it, which
    /// this Mac reaches on its Ethernet now (ROUTE).
    static func opened(_ path: String, on connection: UUID, source: BridgeRelaySource, folders: CartoucheChosenFolders?,
                       route: (String, Int) async -> CartoucheMacNetwork?) async throws -> BridgeRelayFiles.Open {
        guard let server = await source.relayServer(connection) else { throw CartoucheBridgeError(.notFound, "connection") }
        guard let port = CartoucheCableRelay.port(of: server.kind, given: server.port) else {
            throw CartoucheBridgeError(.refused, "not a server of the local network")
        }
        guard CartoucheCableRelay.holds(CartoucheCableRelay.gamesFolders(on: connection, in: folders), path: path) else {
            throw CartoucheBridgeError(.denied, "not in a games folder")
        }
        guard CartoucheCableRelay.relays(over: await route(server.host, port)) else {
            throw CartoucheBridgeError(.refused, "not on this Mac's Ethernet")
        }
        let file = try await source.relayOpen(connection, path: path)
        let reading = CartoucheReadingAhead(size: file.size) { [file] offset, count in
            try await file.read(at: offset, count: count)
        }
        return BridgeRelayFiles.Open(file: file, reading: reading)
    }
}
