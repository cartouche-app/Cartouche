//
//  ConnectionGames.swift
//  Cartouche Builder
//
//  The iPhone's games folder, on one of the player's connections (a NAS's
//  shared folder, an S3 bucket, an FTP or SFTP server, a Google Drive), as
//  the player chose it on the iPhone and the iPhone told this Mac
//  (CartoucheChosenFolders, CartoucheConnections.swift): the Builder sends
//  its games there, each IPA and each Mac app of its games folder, so that
//  the player's iPhones and Macs find them in the same place; and
//  Cartouche's console on this Mac installs from there the Mac apps
//  another Mac sent. The console reaches the folder as the iPhone does
//  (CartoucheMacConnectionGames, by the iPhone's code), the app driving it
//  (ConnectionGamesDriver).
//
//  What goes: a file the folder lacks, or holds older under the same name.
//  The same name and size there is the same file: the Builder's own games
//  folder on the same share sends nothing. A newer file there, another
//  Mac's, stays. Nothing there is ever removed, and nothing goes to a
//  folder without the room for it. A Mac app the games folder keeps as it
//  is, on this Mac's own disk, is packed in one file first (mac-pack), as a
//  NAS keeps it, and the Builder remembers which build went.
//
//  A Mac app another Mac sent, of a game this Mac has no app of, the
//  console offers to install, from its sheet; once installed, it is made
//  again of each newer file there, as this Mac's copy of an app a NAS
//  keeps is of each new build (macapps.py).
//
//  The iPhone may read other games folders besides (CartoucheChosenFolders'
//  otherGames): the Builder sends its games to the first only, and offers
//  the Mac apps of all, a game in several once, from a folder that answers,
//  as the iPhone offers a game (CartoucheGameCopies.swift): then the newest
//  file, then the folder listed first. Its install goes on from the next
//  folder when that one does not answer.
//
//  Platform-independent: Foundation and the library's models only.
//

import Foundation

/// A file in the iPhone's games folder.
public struct ConnectionFile: Codable, Hashable, Sendable {
    public var name: String
    public var size: UInt64
    /// When it was written there, when the server says.
    public var modified: Date?

    public init(name: String, size: UInt64, modified: Date? = nil) {
        self.name = name
        self.size = size
        self.modified = modified
    }
}

/// A game's file of the Builder's games folder, for the iPhone's.
public struct GameToSend: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Its IPA.
        case ipa
        /// Its Mac app, kept in one file already (a NAS's games folder).
        case macFile
        /// Its Mac app as the games folder keeps it, packed in one file
        /// first.
        case macApp
    }

    public var titleID: String
    /// The game's name, as the player knows it.
    public var game: String
    public var kind: Kind
    /// The file, or the app to pack.
    public var url: URL
    /// The file's size; the app's, unpacked, for one to pack.
    public var size: UInt64
    /// When it was built.
    public var modified: Date?
    /// The build it is, as the library says it, which says whether the file
    /// that went is of it: by its size and date when not given.
    public var build: String

    public init(titleID: String, game: String, kind: Kind, url: URL, size: UInt64, modified: Date?, build: String? = nil) {
        self.titleID = titleID.uppercased()
        self.game = game
        self.kind = kind
        self.url = url
        self.size = size
        self.modified = modified
        self.build = build ?? "\(size)|\(modified.map { String(Int64($0.timeIntervalSince1970)) } ?? "")"
    }

    /// Its name there: the file's own; none for an app to pack, which the
    /// engine names.
    public var fileName: String? { kind == .macApp ? nil : url.lastPathComponent }

    /// What the Builder records it went as: the game's IPA, or its Mac app,
    /// whichever way it was kept.
    public var sentKey: String { titleID + (kind == .ipa ? "|ipa" : "|mac") }
}

/// A game's file that went there: of which build, as which file.
public struct SentApp: Codable, Equatable, Sendable {
    public var build: String
    public var file: ConnectionFile

    public init(build: String, file: ConnectionFile) {
        self.build = build
        self.file = file
    }
}

/// A Mac app in the iPhone's games folder.
public struct ConnectionMacApp: Equatable, Sendable {
    public var titleID: String
    /// The game's name, as the file's says it.
    public var game: String
    public var file: ConnectionFile
    /// The games folder it is in, of the iPhone's (ConnectionGamesDriver's
    /// place); "" when the folder is the only one.
    public var place: String

    public init(titleID: String, game: String, file: ConnectionFile, place: String = "") {
        self.titleID = titleID.uppercased()
        self.game = game
        self.file = file
        self.place = place
    }
}

/// One of the iPhone's games folders as the Builder last looked at it: its
/// files, and whether its server answered then (its files those of the
/// look before, else none).
public struct ConnectionGamesLook: Equatable, Sendable {
    public var place: String
    public var files: [ConnectionFile]
    public var answered: Bool

    public init(place: String, files: [ConnectionFile], answered: Bool) {
        self.place = place
        self.files = files
        self.answered = answered
    }
}

/// A Mac app installed on this Mac from the iPhone's games folder.
public struct FetchedApp: Codable, Equatable, Sendable {
    public var titleID: String
    /// The folder it came from (ConnectionGamesDriver.place).
    public var place: String
    /// The file it was installed from.
    public var file: ConnectionFile
    /// Where it is installed.
    public var app: String
    public var installed: Date

    public init(titleID: String, place: String, file: ConnectionFile, app: String, installed: Date) {
        self.titleID = titleID.uppercased()
        self.place = place
        self.file = file
        self.app = app
        self.installed = installed
    }
}

/// Why the Builder sends nothing more there for now.
public enum ConnectionGamesError: Error, Equatable {
    /// The folder's server does not answer from here, or the connection is
    /// no longer there.
    case offline
    /// The player's account may not add a file there.
    case readOnly
    /// NEEDED bytes for the next file, and FREE there.
    case noRoom(needed: UInt64, free: UInt64)
}

extension ConnectionGamesError: LocalizedError {
    /// In the player's words, for an install from there that stopped.
    public var errorDescription: String? {
        switch self {
        case .offline:
            return tr("The iPhone’s games folder does not answer from this Mac.", "Le dossier des jeux de l’iPhone ne répond pas depuis ce Mac.", "La carpeta de juegos del iPhone no responde desde este Mac.", "Der Spieleordner des iPhones antwortet nicht von diesem Mac aus.")
        case .readOnly:
            return tr("Your account may only read the iPhone’s games folder.", "Votre compte ne peut que lire le dossier des jeux de l’iPhone.", "Tu cuenta solo puede leer la carpeta de juegos del iPhone.", "Dein Account darf den Spieleordner des iPhones nur lesen.")
        case let .noRoom(needed, free):
            return tr("Not enough room: \(Format.size(needed)) needed, \(Format.size(free)) free.",
                      "Pas assez de place : \(Format.size(needed)) nécessaires, \(Format.size(free)) libres.",
                      "No hay espacio suficiente: se necesitan \(Format.size(needed)), quedan \(Format.size(free)) libres.",
                      "Nicht genug Platz: \(Format.size(needed)) benötigt, \(Format.size(free)) frei.")
        }
    }
}

public enum ConnectionGames {
    /// What a Mac app kept in one file ends with: "<game> [<title ID>].app.zip".
    public static let packedSuffix = ".app.zip"
    /// The room a file leaves there, at least, in bytes: as the iPhone
    /// leaves when it copies a game (CartoucheGameActions.export).
    public static let margin: UInt64 = 64 << 20

    /// Of LOCAL, what goes to the folder that holds THERE, the newest build
    /// first: a build that did not go yet (SENT, by GameToSend.sentKey),
    /// which the folder lacks, or holds older: never in the place of the
    /// same file, or of a newer one, another Mac's. A build that went and
    /// is no longer there was removed there: it stays removed.
    public static func due(_ local: [GameToSend], there: [ConnectionFile], sent: [String: SentApp]) -> [GameToSend] {
        var byName: [String: ConnectionFile] = [:]
        for file in there where byName[file.name] == nil { byName[file.name] = file }
        let due = local.filter { game in
            let went = sent[game.sentKey]
            if let went, went.build == game.build { return false }
            let file: ConnectionFile?
            if let name = game.fileName {
                file = byName[name]
                // The same file: the Builder's own games folder on the same
                // share, or one that went before this Builder recorded it.
                if let file, file.size == game.size { return false }
            } else {
                file = went.flatMap { byName[$0.file.name] } ?? macFile(of: game.titleID, in: there)
            }
            guard let file else { return true }
            // The one that went, of an older build.
            if let went, file.name == went.file.name, file.size == went.file.size { return true }
            return isOlder(file, than: game)
        }
        let order: [GameToSend.Kind: Int] = [.ipa: 0, .macFile: 1, .macApp: 1]
        return due.sorted { a, b in
            let (x, y) = (a.modified ?? .distantPast, b.modified ?? .distantPast)
            if x != y { return x > y }
            if a.kind != b.kind { return order[a.kind, default: 1] < order[b.kind, default: 1] }
            return a.game.localizedStandardCompare(b.game) == .orderedAscending
        }
    }

    /// Of LOCAL, the builds that did not go but are there already, the
    /// same file, as the Builder records them, by GameToSend.sentKey: once
    /// removed there, they stay removed.
    public static func there(_ local: [GameToSend], in there: [ConnectionFile], sent: [String: SentApp]) -> [String: SentApp] {
        var byName: [String: ConnectionFile] = [:]
        for file in there where byName[file.name] == nil { byName[file.name] = file }
        var found: [String: SentApp] = [:]
        for game in local where sent[game.sentKey]?.build != game.build {
            guard let name = game.fileName, let file = byName[name], file.size == game.size else { continue }
            found[game.sentKey] = SentApp(build: game.build, file: file)
        }
        return found
    }

    /// Whether FILE there is older than GAME: by when each was written,
    /// unless the server does not say.
    static func isOlder(_ file: ConnectionFile, than game: GameToSend) -> Bool {
        guard let theirs = file.modified, let mine = game.modified else { return true }
        return theirs < mine
    }

    /// The title ID a Mac app's file names: "<game> [<title ID>].app.zip".
    public static func titleID(inName name: String) -> String? {
        guard name.lowercased().hasSuffix(packedSuffix) else { return nil }
        let stem = String(name.dropLast(packedSuffix.count))
        guard stem.hasSuffix("]"), let open = stem.lastIndex(of: "[") else { return nil }
        let inside = stem[stem.index(after: open)..<stem.index(before: stem.endIndex)]
        guard inside.count == 16, inside.allSatisfy(\.isHexDigit) else { return nil }
        return inside.uppercased()
    }

    /// The game's name in a Mac app's file name, without its title ID.
    public static func gameName(of name: String) -> String {
        var stem = name.lowercased().hasSuffix(packedSuffix) ? String(name.dropLast(packedSuffix.count)) : name
        if Self.titleID(inName: name) != nil, let open = stem.lastIndex(of: "[") {
            stem = String(stem[..<open])
        }
        let trimmed = stem.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    /// The newest of TITLE_ID's Mac app files in THERE.
    static func macFile(of titleID: String, in there: [ConnectionFile]) -> ConnectionFile? {
        there.filter { Self.titleID(inName: $0.name) == titleID.uppercased() }.max(by: isOlderFile)
    }

    private static func isOlderFile(_ a: ConnectionFile, _ b: ConnectionFile) -> Bool {
        let (x, y) = (a.modified ?? .distantPast, b.modified ?? .distantPast)
        return x != y ? x < y : a.name > b.name
    }

    /// The Mac apps of THERE, the newest file of each game, but for the
    /// games of KNOWN, which this Mac has an app of: by name.
    public static func macApps(in there: [ConnectionFile], known: Set<String>) -> [ConnectionMacApp] {
        var newest: [String: ConnectionFile] = [:]
        for file in there {
            guard let titleID = Self.titleID(inName: file.name), !known.contains(titleID) else { continue }
            if let kept = newest[titleID], !isOlderFile(kept, file) { continue }
            newest[titleID] = file
        }
        return newest.map { ConnectionMacApp(titleID: $0.key, game: gameName(of: $0.value.name), file: $0.value) }
            .sorted { $0.game.localizedStandardCompare($1.game) == .orderedAscending }
    }

    /// The Mac apps of the iPhone's games folders, LOOKS in their order,
    /// but for the games of KNOWN, which this Mac has an app of: a game in
    /// several once, the copy to offer first (copies(of:in:)), by name.
    public static func macApps(in looks: [ConnectionGamesLook], known: Set<String>) -> [ConnectionMacApp] {
        var titleIDs: [String] = []
        for look in looks {
            for file in look.files {
                guard let titleID = Self.titleID(inName: file.name), !known.contains(titleID), !titleIDs.contains(titleID) else { continue }
                titleIDs.append(titleID)
            }
        }
        return titleIDs.compactMap { copies(of: $0, in: looks).first }
            .sorted { $0.game.localizedStandardCompare($1.game) == .orderedAscending }
    }

    /// TITLE_ID's Mac app in each of LOOKS that holds one, the newest file
    /// there, in the order to try them: one in a folder whose server
    /// answered first, then the newest file, then the folder listed first.
    public static func copies(of titleID: String, in looks: [ConnectionGamesLook]) -> [ConnectionMacApp] {
        let found = looks.enumerated().compactMap { index, look -> (index: Int, answered: Bool, app: ConnectionMacApp)? in
            guard let file = macFile(of: titleID, in: look.files) else { return nil }
            return (index, look.answered, ConnectionMacApp(titleID: titleID, game: gameName(of: file.name), file: file, place: look.place))
        }
        return found.sorted { a, b in
            if a.answered != b.answered { return a.answered }
            let (x, y) = (a.app.file.modified ?? .distantPast, b.app.file.modified ?? .distantPast)
            if x != y { return x > y }
            return a.index < b.index
        }
        .map(\.app)
    }

    /// The file there that FETCHED, an app installed from the folder, is
    /// made again of: the newest of its game, when it is another file than
    /// the one it was installed from, and not older.
    public static func newer(for fetched: FetchedApp, in there: [ConnectionFile]) -> ConnectionMacApp? {
        guard let file = macFile(of: fetched.titleID, in: there),
              file.name != fetched.file.name || file.size != fetched.file.size else { return nil }
        if let theirs = file.modified, let mine = fetched.file.modified, theirs <= mine { return nil }
        return ConnectionMacApp(titleID: fetched.titleID, game: gameName(of: file.name), file: file)
    }
}

// MARK: The library's games

extension ConnectionGames {
    /// The files of the library's GAMES that go to the iPhone's games
    /// folder: each IPA there, and each Mac app, in one file already (a
    /// NAS's games folder) or as it is, by its build; MODIFIED says when a
    /// file was written.
    public static func toSend(_ games: [Game], modified: (URL) -> Date? = ConnectionGames.modified(_:)) -> [GameToSend] {
        var files: [GameToSend] = []
        for game in games {
            if let ipa = game.ipa, ipa.present, !ipa.path.isEmpty {
                let url = URL(fileURLWithPath: ipa.path)
                files.append(GameToSend(titleID: game.titleID, game: game.name, kind: .ipa, url: url, size: ipa.size,
                                        modified: modified(url), build: game.build.map(Self.build(of:))))
            }
            guard let mac = game.mac, let kept = mac.library, kept.present, !kept.path.isEmpty else { continue }
            let url = URL(fileURLWithPath: kept.path)
            let built = mac.build.map(Self.build(of:))
            if mac.packed {
                files.append(GameToSend(titleID: game.titleID, game: game.name, kind: .macFile, url: url, size: kept.size,
                                        modified: modified(url), build: built))
            } else {
                // An app's folder says nothing of when it was built: its
                // build does.
                files.append(GameToSend(titleID: game.titleID, game: game.name, kind: .macApp, url: url, size: kept.size,
                                        modified: mac.build?.date ?? modified(url), build: built ?? String(kept.size)))
            }
        }
        return files
    }

    /// The build BUILD, as the Builder records the file that went of it.
    static func build(of build: GameBuild) -> String { build.commit + "|" + build.builtAt }

    /// When the file at URL was written.
    public static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Where the console says the games to install are: KEPT, the place of
    /// those the games folder keeps in one file (a NAS's), OFFERS, the
    /// connection's of the Mac apps another Mac sent to the iPhone's games
    /// folder, or both.
    public static func shownPlace(kept: String?, offers: String?) -> String {
        switch (kept, offers) {
        case let (kept?, offers?): return kept == offers ? kept : tr("your games folders", "vos dossiers de jeux", "tus carpetas de juegos", "deine Spieleordner")
        case let (kept?, nil): return kept
        case let (nil, offers?): return offers
        case (nil, nil): return tr("the games folder", "le dossier des jeux", "la carpeta de juegos", "der Spieleordner")
        }
    }
}

/// The folder an app reaches the iPhone's games folder through: Cartouche's
/// console, signed in to the connection as the iPhone signs in. What it does
/// throws ConnectionGamesError.offline for a server that does not answer.
public protocol ConnectionGamesDriver: AnyObject, Sendable {
    /// The connection, by its ID, and the folder's path on it.
    var connection: UUID { get }
    var path: String { get }
    /// The files at the folder's top.
    func files() async throws -> [ConnectionFile]
    /// The room left there, when the server says.
    func room() async throws -> UInt64?
    /// Whether the player's account may add a file there.
    func canWrite() async throws -> Bool
    /// Sends FILE there as NAME, in the place of the file of that name only
    /// once whole; PROGRESS hears the bytes sent so far.
    func send(_ file: URL, as name: String, progress: @escaping @Sendable (UInt64) -> Void) async throws
    /// Fetches NAME from there into FILE; PROGRESS hears the bytes so far.
    func fetch(_ name: String, to file: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws
}

extension ConnectionGamesDriver {
    /// What the folder's records hold for: the connection and the path.
    public var place: String { connection.uuidString + "|" + path }
}

/// How far the file going or coming is.
public struct ConnectionGamesProgress: Equatable, Sendable {
    public var game: String
    public var kind: GameToSend.Kind
    /// Packing it first.
    public var packing: Bool
    public var done: UInt64
    public var total: UInt64
    /// Which of how many in the round, from 1.
    public var index: Int
    public var count: Int

    public init(game: String, kind: GameToSend.Kind, packing: Bool = false, done: UInt64, total: UInt64, index: Int, count: Int) {
        self.game = game
        self.kind = kind
        self.packing = packing
        self.done = done
        self.total = total
        self.index = index
        self.count = count
    }
}

/// What a round did.
public struct ConnectionGamesReport: Sendable {
    /// What went, with how many bytes and seconds.
    public var sent: [(game: GameToSend, bytes: UInt64, seconds: Double)] = []
    /// What is due still.
    public var left = 0
    /// The folder's files, as the round found them, for the console's.
    public var files: [ConnectionFile]?
    /// Why it stopped before the end, if it did.
    public var stopped: ConnectionGamesError?
    /// What failed, in the player's words: the next round tries again.
    public var failure: String?

    public init() {}
}

/// What the Builder keeps of the iPhone's games folder: the games' files
/// that went there, by folder, and the Mac apps installed from there.
public final class ConnectionGamesStore: @unchecked Sendable {
    private struct Kept: Codable {
        var sent: [String: [String: SentApp]] = [:]
        var fetched: [String: FetchedApp] = [:]
    }

    private let url: URL
    private let lock = NSLock()
    private var kept: Kept

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        kept = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Kept.self, from: $0) } ?? Kept()
    }

    /// The games' files that went to the folder PLACE, by
    /// GameToSend.sentKey.
    public func sent(to place: String) -> [String: SentApp] {
        lock.lock()
        defer { lock.unlock() }
        return kept.sent[place] ?? [:]
    }

    public func setSent(_ app: SentApp, as key: String, to place: String) {
        change { $0.sent[place, default: [:]][key] = app }
    }

    /// The Mac apps installed from the iPhone's games folder, by title ID.
    public var fetched: [String: FetchedApp] {
        lock.lock()
        defer { lock.unlock() }
        return kept.fetched
    }

    public func setFetched(_ app: FetchedApp?, of titleID: String) {
        change { $0.fetched[titleID.uppercased()] = app }
    }

    private func change(_ edit: (inout Kept) -> Void) {
        lock.lock()
        edit(&kept)
        let all = kept
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Sends the Builder's games to the iPhone's games folder, one file at a
/// time, and fetches from there the Mac apps the console installs.
public final class ConnectionGamesSender: @unchecked Sendable {
    public let driver: any ConnectionGamesDriver
    private let store: ConnectionGamesStore
    /// Packs a Mac app the games folder keeps as it is in one file, in a
    /// folder of the Builder's, and gives that file (Engine.packMac).
    private let pack: @Sendable (GameToSend) async throws -> URL

    public init(driver: any ConnectionGamesDriver, store: ConnectionGamesStore,
                pack: @escaping @Sendable (GameToSend) async throws -> URL) {
        self.driver = driver
        self.store = store
        self.pack = pack
    }

    /// Sends what of LOCAL is due there, the newest first, PROGRESS hearing
    /// how far each file is: stops for a server that does not answer, a
    /// folder this account may not write to or without room, a failure, or
    /// STOP, asked before each file (a batch started: the file going goes
    /// on to its end).
    public func send(_ local: [GameToSend], progress: @escaping @Sendable (ConnectionGamesProgress) -> Void = { _ in },
                     stop: @escaping @Sendable () async -> Bool = { false }) async -> ConnectionGamesReport {
        var report = ConnectionGamesReport()
        let place = driver.place
        do {
            let files = try await driver.files()
            report.files = files
            let sent = store.sent(to: place)
            for (key, app) in ConnectionGames.there(local, in: files, sent: sent) {
                store.setSent(app, as: key, to: place)
            }
            let due = ConnectionGames.due(local, there: files, sent: sent)
            report.left = due.count
            guard !due.isEmpty else { return report }
            guard try await driver.canWrite() else {
                report.stopped = .readOnly
                return report
            }
            for (index, game) in due.enumerated() {
                guard !(await stop()) else { break }
                let began = Date()
                var file = game.url
                var packed: URL?
                if game.kind == .macApp {
                    progress(ConnectionGamesProgress(game: game.game, kind: game.kind, packing: true, done: 0, total: game.size,
                                                     index: index + 1, count: due.count))
                    let made = try await pack(game)
                    packed = made
                    file = made
                }
                defer {
                    if let packed { try? FileManager.default.removeItem(at: packed) }
                }
                let size = Self.size(of: file) ?? game.size
                if let free = try await driver.room(), free < size + ConnectionGames.margin {
                    report.stopped = .noRoom(needed: size + ConnectionGames.margin, free: free)
                    break
                }
                let name = file.lastPathComponent
                let total = size
                let count = due.count
                progress(ConnectionGamesProgress(game: game.game, kind: game.kind, done: 0, total: total, index: index + 1, count: count))
                try await driver.send(file, as: name) { done in
                    progress(ConnectionGamesProgress(game: game.game, kind: game.kind, done: done, total: total, index: index + 1, count: count))
                }
                store.setSent(SentApp(build: game.build, file: ConnectionFile(name: name, size: size, modified: Date())),
                              as: game.sentKey, to: place)
                report.sent.append((game, size, Date().timeIntervalSince(began)))
                report.left -= 1
            }
        } catch let error as ConnectionGamesError {
            report.stopped = error
        } catch {
            report.failure = error.localizedDescription
        }
        return report
    }

    /// Fetches APP's file from there into FOLDER, PROGRESS hearing how far
    /// it is, for the engine to install it: the file, once whole; nothing
    /// is left of it otherwise.
    public func fetch(_ app: ConnectionMacApp, into folder: URL,
                      progress: @escaping @Sendable (UInt64) -> Void = { _ in }) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let free = Self.room(at: folder), free < app.file.size + ConnectionGames.margin {
            throw ConnectionGamesError.noRoom(needed: app.file.size + ConnectionGames.margin, free: free)
        }
        let file = folder.appendingPathComponent(app.file.name)
        try? FileManager.default.removeItem(at: file)
        do {
            try await driver.fetch(app.file.name, to: file, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }

    /// Records APP, installed from FILE there at PATH, which is made again
    /// of each newer file there from then on.
    public func installed(_ app: ConnectionMacApp, at path: String, now: Date = Date()) {
        store.setFetched(FetchedApp(titleID: app.titleID, place: driver.place, file: app.file, app: path, installed: now), of: app.titleID)
    }

    static func size(of file: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value
    }

    static func room(at folder: URL) -> UInt64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: folder.path)[.systemFreeSize] as? NSNumber)?.uint64Value
    }
}
