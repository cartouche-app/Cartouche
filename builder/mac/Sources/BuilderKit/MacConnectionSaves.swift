//
//  MacConnectionSaves.swift
//  Cartouche Builder
//
//  The iPhone's saves folder on one of the player's connections, a NAS's
//  shared folder, an S3 bucket, an FTP or SFTP server or a Google Drive,
//  as this Mac keeps the saves of its games in step with it once the player
//  chose it on the iPhone (CartoucheChosenFolders, CartoucheConnections.swift):
//  by the iPhone's own code, which Cartouche's console runs on the Mac
//  (CartoucheMacConnectionSaves, over CartoucheSavesFolder), the app
//  driving it (MacConnectionSavesDriver). The Mac's rules hold as for a
//  folder of its own (MacSaves.swift): a game started from the Dock
//  meanwhile keeps the saves it found, and saves kept in step with another
//  saves folder, unchanged since, are no news here, the newest copy coming
//  in their place, after they were kept as a copy here when their own is
//  no longer in the folder left, which is looked at on this Mac only.
//
//  The console has its own copy of CartoucheCore's types: a base goes
//  between them as JSON, which both read as their own.
//
//  Platform-independent: Foundation and CartoucheCore only.
//

import CartoucheCore
import Foundation

/// What a sync on a connection did, as the console says it.
public struct MacConnectionOutcome: Equatable, Sendable {
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

    public init(step: String, base: Data?, sent: String? = nil, kept: String? = nil, fetched: String? = nil, newer: String? = nil) {
        self.step = step
        self.base = base
        self.sent = sent
        self.kept = kept
        self.fetched = fetched
        self.newer = newer
    }
}

/// The console's saves folder on one of the player's connections, as the
/// app gives it: what it does throws MacSavesError, offline for a server
/// that does not answer.
public protocol MacConnectionSavesDriver: AnyObject, Sendable {
    /// The connection, by its ID, and the folder's path on it.
    var connection: UUID { get }
    var path: String { get }
    /// What its bases hold for, as the console names it.
    var place: String { get }
    /// Keeps the saves in DOCUMENTS, GAME's on this Mac, in step with its
    /// copies, from BASE, as JSON: a base of another saves folder makes the
    /// saves unchanged since no news (LEAVING says whether their copy is
    /// still in the folder left). QUIET, just before a copy takes the place
    /// of the saves.
    func sync(_ game: MacSaveGame, documents: URL, base: Data?, fetching: Bool, leaving: @escaping @Sendable () -> Bool,
              quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome
    /// Puts the copy NAME back as GAME's saves in DOCUMENTS.
    func putBack(_ name: String, of game: MacSaveGame, documents: URL, base: Data?,
                 quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome
    /// GAME's copies, the newest first.
    func copies(of game: MacSaveGame, documents: URL) async throws -> [MacSaveCopyInfo]
}

/// The iPhone's saves folder on one of the player's connections, as this
/// Mac keeps its games' saves in step with it.
public final class MacConnectionSaves: MacSavesPlace {
    public let driver: any MacConnectionSavesDriver
    /// nxnative's folder of each game's own, as for MacSavesFolder.
    public let games: URL
    /// A folder of the Mac's, where a folder of its own left is looked at.
    private let scratch: URL

    public init(driver: any MacConnectionSavesDriver, games: URL = MacSavesFolder.nxnativeFolder, scratch: URL) {
        self.driver = driver
        self.games = games
        self.scratch = scratch
    }

    public var place: String { driver.place }
    public var path: String { driver.path }
    public var connection: UUID? { driver.connection }
    public var onShare: Bool { true }

    /// The game's folder on this Mac, nxnative's, holding its saves.
    public func documents(of titleID: String) -> URL {
        games.appendingPathComponent(titleID.uppercased(), isDirectory: true)
    }

    public func sync(_ game: MacSaveGame, base given: CartoucheSaveBase?, fetching: Bool,
                     quiet: @Sendable () -> Bool) async throws -> MacSaveOutcome {
        let games = self.games
        let scratch = self.scratch
        let left = given.flatMap { $0.place == place ? nil : Self.encode($0) }
        // The copy of the saves kept in step with a folder of this Mac's,
        // in that folder: looked at there, as MacSavesFolder does.
        let leaving: @Sendable () -> Bool = {
            guard let left, let base = Self.decode(left) else { return false }
            return MacSavesFolder.copyIsThere(base, of: game, games: games, scratch: scratch)
        }
        let outcome = try await driver.sync(game, documents: documents(of: game.titleID), base: given.flatMap(Self.encode),
                                            fetching: fetching, leaving: leaving, quiet: quiet)
        return try Self.outcome(outcome)
    }

    public func putBack(_ name: String, of game: MacSaveGame, base given: CartoucheSaveBase?,
                        quiet: @Sendable () -> Bool) async throws -> MacSaveOutcome {
        let outcome = try await driver.putBack(name, of: game, documents: documents(of: game.titleID), base: given.flatMap(Self.encode),
                                               quiet: quiet)
        return try Self.outcome(outcome)
    }

    public func listCopies(of game: MacSaveGame) async throws -> [MacSaveCopyInfo] {
        try await driver.copies(of: game, documents: documents(of: game.titleID))
    }

    // MARK: Between the two copies of CartoucheCore's types

    static func encode(_ base: CartoucheSaveBase) -> Data? {
        try? JSONEncoder().encode(base)
    }

    static func decode(_ data: Data) -> CartoucheSaveBase? {
        try? JSONDecoder().decode(CartoucheSaveBase.self, from: data)
    }

    /// OUTCOME, as MacSavesFolder gives one: a step this side does not
    /// know is a failure.
    static func outcome(_ outcome: MacConnectionOutcome) throws -> MacSaveOutcome {
        guard let step = CartoucheSaveStep(rawValue: outcome.step) else {
            throw CocoaError(.coderInvalidValue)
        }
        return MacSaveOutcome(step: step, base: outcome.base.flatMap(decode), sent: outcome.sent, kept: outcome.kept,
                              fetched: outcome.fetched, newer: outcome.newer)
    }
}
