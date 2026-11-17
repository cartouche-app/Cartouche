//
//  ConnectionSaves.swift
//  Cartouche Builder
//
//  The saves folder the player chose on the iPhone, on one of their
//  connections, as the app's two halves keep the saves of the games played
//  on this Mac in step with it: BuilderKit drives them (MacConnectionSaves,
//  with the Mac's rules and records), Cartouche's console does the work by
//  the iPhone's code (CartoucheMacConnectionSaves). Each half has its own
//  copy of CartoucheCore's types: a base goes between them as JSON, and
//  what the console could not do becomes what BuilderKit tells apart.
//

import BuilderKit
import CartoucheConsole
import Foundation

final class ConsoleConnectionSaves: MacConnectionSavesDriver, @unchecked Sendable {
    let saves: CartoucheMacConnectionSaves

    init(connection: UUID, path: String, scratch: URL) {
        saves = CartoucheMacConnectionSaves(connection: connection, path: path, scratch: scratch)
    }

    var connection: UUID { saves.connection }
    var path: String { saves.path }
    var place: String { saves.place }

    func sync(_ game: MacSaveGame, documents: URL, base: Data?, fetching: Bool, leaving: @escaping @Sendable () -> Bool,
              quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome {
        do {
            let done = try await saves.sync(titleID: game.titleID, name: game.name, version: game.version, documents: documents,
                                            base: base, fetching: fetching, leaving: leaving, quiet: quiet)
            return Self.outcome(done)
        } catch let error as CartoucheMacSaveError {
            throw Self.builder(error)
        }
    }

    func putBack(_ name: String, of game: MacSaveGame, documents: URL, base: Data?,
                 quiet: @Sendable () -> Bool) async throws -> MacConnectionOutcome {
        do {
            let done = try await saves.putBack(name, titleID: game.titleID, name: game.name, version: game.version,
                                               documents: documents, base: base, quiet: quiet)
            return Self.outcome(done)
        } catch let error as CartoucheMacSaveError {
            throw Self.builder(error)
        }
    }

    func copies(of game: MacSaveGame, documents: URL) async throws -> [MacSaveCopyInfo] {
        do {
            return try await saves.copies(titleID: game.titleID, name: game.name, documents: documents)
                .map { MacSaveCopyInfo(name: $0.name, date: $0.date, size: $0.size) }
        } catch let error as CartoucheMacSaveError {
            throw Self.builder(error)
        }
    }

    private static func outcome(_ done: CartoucheMacConnectionOutcome) -> MacConnectionOutcome {
        MacConnectionOutcome(step: done.step, base: done.base, sent: done.sent, kept: done.kept, fetched: done.fetched,
                             newer: done.newer)
    }

    /// What BuilderKit tells apart: a copy that does not read stays the
    /// console's, which says so in the iPhone's words, without a name.
    private static func builder(_ error: CartoucheMacSaveError) -> Error {
        switch error {
        case .offline: return MacSavesError.offline
        case .busy: return MacSavesError.busy
        case .newerGame(let copy, let game): return MacSavesError.newerGame(copy: copy, game: game)
        case .unreadable: return error
        }
    }
}
