//
//  MacSaves.swift
//  Cartouche Builder
//
//  A game's saves on this Mac, where its app keeps them (nxnative's Mac
//  launcher: ~/Library/Application Support/nxnative/<title ID>/save and
//  save_device, and save_user2 to save_user8 with save.users for a game
//  with other profiles), kept in step with their copies in the player's saves
//  folder as Cartouche keeps an iPhone's: the same decisions and the same
//  copies (launcher/Sources/CartoucheSaveSync.swift), a folder of the game's
//  "<game> [<title ID>]" holding zips "<date>.zip" of save/ and save_device/,
//  the ten newest kept. The saves folder is the one the bridge shares with
//  Cartouche as Saves: on this Mac, or the folder Cartouche keeps on a NAS,
//  mounted on this Mac; or the one the player chose on the iPhone, on one
//  of their connections, which the console reaches by the iPhone's code
//  (MacConnectionSaves.swift), each a MacSavesPlace.
//
//  - The game's folder is the one whose name ends with "[<title ID>]":
//    Cartouche names it after the game as the iPhone shows it, nxnative's
//    name, which the Mac app has too. A game with none gets the name
//    Cartouche would give it.
//  - Which way is CartoucheSaveSync.step's: nothing moves while neither
//    side changed since the base, the side that changed goes to the other,
//    and when both did, or this Mac never synced the game with this folder,
//    the saves written last win, the others kept as a copy of their date.
//  - The newest copy comes when the game is about to start, and while it
//    does not run; the saves of the Mac go a few seconds after the game
//    saves, while it plays (CartoucheSaveWatch), from a copy of them made
//    at one moment, never half written (CartoucheSaveSync.snapshot), and
//    after each game. Each copy that goes while a game plays, and the one
//    after it, takes the place of the one before, so that each game leaves
//    one copy, as on the iPhone.
//  - A copy can be put back from the game's sheet in Cartouche's console,
//    as on the iPhone: the saves of the Mac go to the folder first, and the
//    copy put back becomes the newest one there, which the iPhones take.
//  - Saves the Mac kept in step with another saves folder, and did not
//    change since, are no news for the one the player chose since: they
//    stay in the other, and this one's newest copy comes in their place
//    (kept here first, as a copy of their date, were they no longer there).
//  - A saves folder that is not there, a share not mounted, is offline:
//    nothing moves; the game plays with the saves of the Mac, which go once
//    the folder is back.
//  - Until the player chooses one, the Mac takes Cartouche's saves folder
//    it finds on a share mounted here (adopted), the iPhone's on a NAS.
//  - What was the same on both sides last, the base, is kept for each game
//    and one saves folder (MacSaveStore): another folder starts from none.
//  - The other profiles of a game, save_user2/ to save_user8/, and their
//    registry, save.users, go and come with its saves, as on the iPhone;
//    the list of pipelines the game prepared, pso_user.tsv, beside save/,
//    goes into the one beside the copies, which every device adds its lines
//    to, and its lines this Mac lacks come before the game starts
//    (CartoucheSaveSync.keepPipelines).
//
//  Platform-independent: Foundation and CartoucheCore only.
//

import CartoucheCore
import Foundation

/// A game whose saves this Mac keeps in step: its title ID, and its name,
/// for the folder of its copies when it has none yet.
public struct MacSaveGame: Hashable, Sendable {
    public let titleID: String
    public let name: String
    /// The version of its app on this Mac, CFBundleShortVersionString, which
    /// each copy of its saves names: a copy of a newer one never comes
    /// (CartoucheSaveSync.heldBack). Nil when unknown, which holds nothing
    /// back.
    public let version: String?

    public init(titleID: String, name: String, version: String? = nil) {
        self.titleID = titleID.uppercased()
        self.name = name
        self.version = version
    }
}

/// What a sync did with a game's saves.
public struct MacSaveOutcome: Equatable {
    public var step: CartoucheSaveStep
    /// What is the same on this Mac and in the folder now.
    public var base: CartoucheSaveBase?
    /// The copy the saves of the Mac went to, as the newest one.
    public var sent: String?
    /// The copy the saves of the Mac went to under a newer one, kept.
    public var kept: String?
    /// The copy that came to the Mac, in place of its saves.
    public var fetched: String?
    /// The version of the game the newest copy names, newer than the app's
    /// on this Mac, when it held the copy back (CartoucheSaveSync.heldBack).
    public var newer: String?
    /// What moved of the list of pipelines the game prepared, beside the
    /// copies (CartoucheSaveSync.keepPipelines).
    public var pipelines: CartouchePipelinesMoved

    public init(step: CartoucheSaveStep, base: CartoucheSaveBase? = nil, sent: String? = nil, kept: String? = nil, fetched: String? = nil,
                newer: String? = nil, pipelines: CartouchePipelinesMoved = CartouchePipelinesMoved()) {
        self.step = step
        self.base = base
        self.sent = sent
        self.kept = kept
        self.fetched = fetched
        self.newer = newer
        self.pipelines = pipelines
    }

    /// Whether a copy went or came.
    public var moved: Bool { sent != nil || kept != nil || fetched != nil }
}

/// Why a game's saves did not move.
public enum MacSavesError: Error, Equatable {
    /// The saves folder is not there: a share not mounted.
    case offline
    /// A copy that does not read whole, or holds more than saves.
    case unreadable(String)
    /// The game started meanwhile: the saves it found stay.
    case busy
    /// A copy to put back that a newer version of the game wrote than the
    /// app's on this Mac: the versions.
    case newerGame(copy: String, game: String)
}

/// A copy of a game's saves in the saves folder.
public struct MacSaveCopyInfo: Hashable, Identifiable, Sendable {
    public let name: String
    public let date: Date
    public let size: UInt64

    public init(name: String, date: Date, size: UInt64) {
        self.name = name
        self.date = date
        self.size = size
    }

    public var id: String { name }
}

/// Where this Mac keeps its games' saves in step: a folder of this Mac's,
/// or a share mounted here (MacSavesFolder), or the iPhone's saves folder
/// on one of the player's connections (MacConnectionSaves).
public protocol MacSavesPlace: AnyObject, Sendable {
    /// What a base holds for: "mac|<path>", or the connection's ID and the
    /// path on it, as the iPhone's bases say it.
    var place: String { get }
    /// Its path: on this Mac, or on its connection.
    var path: String { get }
    /// The connection it is on; nil for a folder of this Mac's.
    var connection: UUID? { get }
    /// Whether it is away from this Mac's disks: on a share or a server.
    var onShare: Bool { get }
    /// Keeps GAME's saves on this Mac in step with its copies there, from
    /// BASE (MacSavesFolder.sync); REPLACING: the copy they went to earlier
    /// in the same game, which the one that goes now takes the place of
    /// when it is still the newest.
    func sync(_ game: MacSaveGame, base given: CartoucheSaveBase?, fetching: Bool,
              quiet: @Sendable () -> Bool, replacing: String?) async throws -> MacSaveOutcome
    /// The same saves folder, the saves of the games read from GAMES rather
    /// than from nxnative's folder: a copy of a game's saves made while it
    /// plays (CartoucheSaveSync.snapshot), <GAMES>/<title ID>.
    func reading(games: URL) -> any MacSavesPlace
    /// Puts the copy NAME back as GAME's saves on this Mac
    /// (MacSavesFolder.putBack).
    func putBack(_ name: String, of game: MacSaveGame, base given: CartoucheSaveBase?,
                 quiet: @Sendable () -> Bool) async throws -> MacSaveOutcome
    /// GAME's copies, the newest first; offline when the folder is not
    /// there.
    func listCopies(of game: MacSaveGame) async throws -> [MacSaveCopyInfo]
}

/// The player's saves folder, as this Mac keeps its games' saves in step
/// with it.
public final class MacSavesFolder: MacSavesPlace {
    /// nxnative's folder of each game's own on this Mac.
    public static var nxnativeFolder: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/nxnative", isDirectory: true)
    }

    /// The saves folder.
    public let root: URL
    /// nxnative's folder of each game's own: the saves of a game are in
    /// save/ and save_device/ of its folder there.
    public let games: URL
    /// "mac|<path>": the saves folder a base holds for.
    public let place: String
    /// A folder of the Mac's for the copies that come, unpacked there first.
    private let scratch: URL

    public init(root: URL, games: URL = MacSavesFolder.nxnativeFolder, scratch: URL) {
        self.root = root.standardizedFileURL
        self.games = games
        place = "mac|" + self.root.path
        self.scratch = scratch
    }

    /// Whether the saves folder is there: a share not mounted is not, nor
    /// a folder of the Mac's own made where it mounts, under /Volumes.
    public var reachable: Bool {
        guard Self.isFolder(root) else { return false }
        let parts = root.pathComponents
        guard parts.count > 2, parts[0] == "/", parts[1] == "Volumes" else { return true }
        let volume = (try? root.resourceValues(forKeys: [.volumeURLKey]))?.volume
        return volume?.standardizedFileURL.path == "/Volumes/" + parts[2]
    }

    /// Whether the saves folder is on a share, not on a disk of this Mac's.
    public var onShare: Bool {
        (try? root.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
    }

    public var path: String { root.path }
    public var connection: UUID? { nil }

    public func listCopies(of game: MacSaveGame) async throws -> [MacSaveCopyInfo] {
        guard reachable else { throw MacSavesError.offline }
        return copies(of: game)
    }

    public func reading(games: URL) -> any MacSavesPlace {
        MacSavesFolder(root: root, games: games, scratch: scratch)
    }

    /// The game's folder on this Mac, nxnative's, holding its saves.
    public func documents(of titleID: String) -> URL {
        games.appendingPathComponent(titleID.uppercased(), isDirectory: true)
    }

    /// The name Cartouche gives a game's folder of copies (its
    /// CartoucheSavesFolder.folderName): "<game> [<title ID>]", the game's
    /// name without what a file's name cannot hold, as
    /// CartoucheStoragePath.fileName writes it.
    public static func folderName(_ game: MacSaveGame) -> String {
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = String(game.name.unicodeScalars.map { refused.contains($0) ? " " : Character($0) })
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let name = cleaned.isEmpty ? "Game" : String(cleaned.prefix(120))
        return name + " [\(game.titleID)]"
    }

    /// The folder of the game's copies: the one whose name ends with the
    /// game's "[<title ID>]", whatever the name before it, which Cartouche
    /// gives after the game's app on the iPhone; of two made before either
    /// was seen, the one holding the newest copy, which Cartouche takes too
    /// (its CartoucheSavesFolder.gameFolder); else the one to make.
    public func gameFolder(of game: MacSaveGame) -> URL {
        let made = Self.folderName(game)
        let suffix = "[\(game.titleID)]"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let found = names.filter { $0.uppercased().hasSuffix(suffix) && Self.isFolder(root.appendingPathComponent($0)) }.sorted()
        guard found.count > 1 else { return root.appendingPathComponent(found.first ?? made, isDirectory: true) }
        var chosen = found[0]
        var newest: Date?
        for name in found {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            guard let last = copyNames(in: folder).last.flatMap(CartoucheSaveSync.date(inName:)) else { continue }
            if newest.map({ last > $0 }) ?? true {
                chosen = name
                newest = last
            }
        }
        return root.appendingPathComponent(chosen, isDirectory: true)
    }

    /// The game's copies, the newest first.
    public func copies(of game: MacSaveGame) -> [MacSaveCopyInfo] {
        let folder = gameFolder(of: game)
        return copyNames(in: folder).compactMap { name in
            guard let date = CartoucheSaveSync.date(inName: name) else { return nil }
            let size = (try? folder.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return MacSaveCopyInfo(name: name, date: date, size: UInt64(max(size, 0)))
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Syncing

    /// Keeps GAME's saves on this Mac in step with its copies, from BASE,
    /// the last time both were the same (CartoucheSaveSync.step). FETCHING
    /// lets the newest copy come, when the game is about to start or does
    /// not run; while a game plays and after it, only the saves of the Mac
    /// go. QUIET says, just before a copy takes the place of the Mac's
    /// saves, that the game still does not run: one started meanwhile, from
    /// the Dock, keeps the saves it found (busy). REPLACING: the copy the
    /// saves of the Mac went to earlier in the same game, while it played,
    /// which the one that goes now takes the place of when it is still the
    /// newest there: one copy for each game.
    public func sync(_ game: MacSaveGame, base given: CartoucheSaveBase?, fetching: Bool,
                     quiet: @Sendable () -> Bool = { true }, replacing: String? = nil) async throws -> MacSaveOutcome {
        guard reachable else { throw MacSavesError.offline }
        let base = given?.place == place ? given : nil
        // The saves folder this Mac kept the game in step with before the
        // player chose this one, by its base there.
        let left = given?.place == place ? nil : given
        let documents = self.documents(of: game.titleID)
        let folder = gameFolder(of: game)
        let names = copyNames(in: folder)
        var here = CartoucheSaveSync.saves(in: documents)
        var newest = names.last.flatMap { name in
            CartoucheSaveSync.date(inName: name).map { CartoucheSaveCopy(name: name, date: $0) }
        }
        // What the base says of either side, read already.
        if let base, let content = base.content {
            if here?.look == base.look { here?.content = content }
            if newest?.name == base.copy { newest?.content = content }
        }
        let baseIsThere = base.map { names.contains($0.copy) } ?? false
        var step = CartoucheSaveSync.step(here: here, newest: newest, base: base, baseIsThere: baseIsThere, fetching: fetching)
        if step == .compare {
            if here != nil, here?.content == nil {
                here?.content = try CartoucheSaveSync.content(ofSavesIn: documents)
            }
            if let copy = newest, copy.content == nil {
                newest?.content = CartoucheSaveSync.content(of: try await entries(of: folder.appendingPathComponent(copy.name)))
            }
            step = CartoucheSaveSync.step(here: here, newest: newest, base: base, baseIsThere: baseIsThere, fetching: fetching)
        }
        // Saves this Mac has not changed since it kept them in step with the
        // folder it left are no news here, whatever their date: this
        // folder's newest copy comes in their place (CartoucheSaveSync's
        // afterLeaving, which a folder on one of the player's connections
        // takes too). Only a game started since, which changed them, makes
        // them news, the saves written last winning then.
        if base == nil, let left {
            step = CartoucheSaveSync.afterLeaving(step, left: left, here: here, newest: newest, fetching: fetching) {
                Self.copyIsThere(left, of: game, games: games, scratch: scratch)
            }
        }
        // A game older than the newest copy's never takes it, nor puts its
        // saves over it: they go as a copy under it instead, as on the
        // iPhone. The copy's version is the base's when it is the base's
        // copy, else its zip's comment, read from its end.
        var held: String?
        if CartoucheSaveSync.needsCopyVersion(step), game.version != nil, let copy = newest, copy.content != "" {
            if let base, base.copy == copy.name {
                newest?.gameVersion = base.gameVersion
            } else {
                let archive = try await archive(of: folder.appendingPathComponent(copy.name))
                newest?.gameVersion = CartoucheSaveSync.gameVersion(inComment: archive.comment)
                if newest?.content == nil { newest?.content = CartoucheSaveSync.content(of: archive.entries) }
            }
            let checked = CartoucheSaveSync.heldBack(step, copy: newest?.gameVersion, game: game.version)
            if checked != step {
                held = newest?.gameVersion
                step = checked
            }
        }

        // A sync that moves nothing keeps what the Mac knew of the folder it
        // left, for the next one.
        var outcome = MacSaveOutcome(step: step, base: base ?? left, newer: held)
        switch step {
        case .none, .compare:
            // Saves written again as they were: the base takes their look,
            // not to read them again next time.
            if let here, var same = base, here.look != same.look, here.content != nil, here.content == same.content {
                same.look = here.look
                outcome.base = same
            }
        case .same:
            if let here, let newest {
                outcome.base = CartoucheSaveBase(place: place, copy: newest.name, content: here.content ?? newest.content, look: here.look,
                                                 gameVersion: newest.gameVersion)
            }
        case .send:
            if let here {
                let name = CartoucheSaveSync.sendName(written: here.written, after: newest?.date)
                outcome.base = try await send(documents, here, as: name, to: folder, version: game.version,
                                              replacing: replacing != nil && replacing == newest?.name ? replacing : nil)
                outcome.sent = name
            }
        case .keep:
            if let here {
                let (name, kept) = try await keep(documents, here, under: newest, in: folder, names: names, version: game.version)
                outcome.base = kept
                outcome.kept = name
            }
        case .fetch, .keepAndFetch:
            guard let newest else { break }
            if step == .keepAndFetch, let here {
                outcome.kept = try await keep(documents, here, under: newest, in: folder, names: names, version: game.version).name
            }
            outcome.base = try await fetch(newest, into: documents, from: folder, quiet: quiet)
            outcome.fetched = newest.name
        }
        // The list of pipelines the game prepared, beside its copies, once
        // the game has a folder there: not from the copy of the saves made
        // while it plays, which holds none.
        if Self.isFolder(folder) {
            let list = folder.appendingPathComponent(CartoucheSaveSync.pipelinesFile)
            let there = (try? list.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])).flatMap { values in
                values.isRegularFile == true ? UInt64(max(values.fileSize ?? 0, 0)) : nil
            }
            outcome.pipelines = await CartoucheSaveSync.keepPipelines(
                in: documents, there: there, fetching: fetching, quiet: quiet,
                read: {
                    let data = try Data(contentsOf: list)
                    guard data.count <= CartoucheSaveSync.pipelinesLimit else { throw MacSavesError.unreadable(list.lastPathComponent) }
                    return data
                },
                write: { try $0.write(to: list, options: .atomic) })
        }
        return outcome
    }

    /// Puts the copy NAME back as GAME's saves on this Mac, as the player
    /// chose it in Cartouche's console, as Cartouche puts one back on the
    /// iPhone (its CartoucheSavesFolder.putBack): the saves of the Mac go to
    /// the folder first, unless it has them already, and the copy put back
    /// then goes there as the newest one, which the player's iPhones take at
    /// their next start, rather than the one that was the newest. QUIET, as
    /// for a sync: the game still does not run, just before the copy takes
    /// the place of its saves.
    public func putBack(_ name: String, of game: MacSaveGame, base given: CartoucheSaveBase?,
                        quiet: @Sendable () -> Bool = { true }) async throws -> MacSaveOutcome {
        guard reachable else { throw MacSavesError.offline }
        let base = given?.place == place ? given : nil
        let documents = self.documents(of: game.titleID)
        let folder = gameFolder(of: game)
        var names = copyNames(in: folder)
        guard names.contains(name), let date = CartoucheSaveSync.date(inName: name) else {
            throw MacSavesError.unreadable(name)
        }
        // A copy a newer version of the game wrote stays where it is, and so
        // do the saves of this Mac.
        if let version = game.version {
            let copy = try await archive(of: folder.appendingPathComponent(name))
            if let written = CartoucheSaveSync.gameVersion(inComment: copy.comment), CartoucheSaveSync.isNewer(written, than: version) {
                throw MacSavesError.newerGame(copy: written, game: version)
            }
        }
        var outcome = MacSaveOutcome(step: .fetch, base: base)
        if let here = CartoucheSaveSync.saves(in: documents),
           !(base.map { $0.look == here.look && names.contains($0.copy) } ?? false) {
            let sent = CartoucheSaveSync.sendName(written: here.written, after: names.last.flatMap(CartoucheSaveSync.date(inName:)))
            // The copy to put back stays, even the oldest one.
            _ = try await send(documents, here, as: sent, to: folder, version: game.version, sparing: name)
            names = copyNames(in: folder)
            outcome.kept = sent
        }
        let fetched = try await fetch(CartoucheSaveCopy(name: name, date: date), into: documents, from: folder, quiet: quiet)
        outcome.fetched = name
        outcome.base = fetched
        // The newest one already, or a copy of no save.
        guard name != names.last, let here = CartoucheSaveSync.saves(in: documents) else { return outcome }
        var put = here
        put.content = fetched.content
        let newest = CartoucheSaveSync.sendName(written: here.written, after: names.last.flatMap(CartoucheSaveSync.date(inName:)))
        outcome.base = try await send(documents, put, as: newest, to: folder, version: game.version)
        outcome.sent = newest
        return outcome
    }

    // MARK: Steps

    /// Whether the copy BASE names is still in the saves folder of this
    /// Mac's it was made in, there now: false for one on a connection, which
    /// is not looked at, so that the saves of the Mac are kept as a copy
    /// first.
    public static func copyIsThere(_ base: CartoucheSaveBase, of game: MacSaveGame, games: URL = MacSavesFolder.nxnativeFolder,
                                   scratch: URL) -> Bool {
        guard base.place.hasPrefix("mac|"), !base.copy.isEmpty else { return false }
        let other = MacSavesFolder(root: URL(fileURLWithPath: String(base.place.dropFirst(4)), isDirectory: true),
                                   games: games, scratch: scratch)
        guard other.reachable else { return false }
        let copy = other.gameFolder(of: game).appendingPathComponent(base.copy)
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: copy.path, isDirectory: &folder) && !folder.boolValue
    }

    /// The names of the copies in FOLDER, the oldest first; none when the
    /// game has no folder yet.
    private func copyNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { CartoucheSaveSync.date(inName: $0) != nil && !Self.isFolder(folder.appendingPathComponent($0)) }.sorted()
    }

    /// The zip's entries of the copy at URL, from its end.
    private func entries(of url: URL) async throws -> [CartoucheZipEntry] {
        try await archive(of: url).entries
    }

    /// The zip's entries and comment of the copy at URL, from its end.
    private func archive(of url: URL) async throws -> CartoucheZipArchive {
        do {
            return try await CartoucheZip.archive(of: CartoucheFileSource(url))
        } catch {
            throw MacSavesError.unreadable(url.lastPathComponent)
        }
    }

    /// Writes the saves HERE in DOCUMENTS to NAME in FOLDER, whole before it
    /// takes its name, naming VERSION, the game's, then removes REPLACING,
    /// the copy it takes the place of, and the copies past the newest ones,
    /// but for this one and SPARING; the base it makes.
    private func send(_ documents: URL, _ here: CartoucheLocalSaves, as name: String, to folder: URL, version: String?,
                      sparing: String? = nil, replacing: String? = nil) async throws -> CartoucheSaveBase {
        let fileManager = FileManager.default
        let content = try here.content ?? CartoucheSaveSync.content(ofSavesIn: documents)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name)
        let partial = folder.appendingPathComponent(name + ".partial")
        let sink = try CartoucheFileSink(partial)
        do {
            try await CartoucheSaveSync.writeZip(ofSavesIn: documents, to: sink, gameVersion: version)
            try sink.close()
        } catch {
            try? sink.close()
            try? fileManager.removeItem(at: partial)
            throw error
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: partial, to: target)
        if let replacing, replacing != name, replacing != sparing {
            try? fileManager.removeItem(at: folder.appendingPathComponent(replacing))
        }
        prune(folder, made: name, sparing: sparing)
        return CartoucheSaveBase(place: place, copy: name, content: content, look: here.look, gameVersion: version)
    }

    /// Keeps the saves HERE in FOLDER as a copy of their own date, under
    /// NEWEST, the newer one there: the name it has, and the base it makes.
    /// A copy of that name there already is left as it is when it holds the
    /// same saves; else the copy takes the second before.
    private func keep(_ documents: URL, _ here: CartoucheLocalSaves, under newest: CartoucheSaveCopy?, in folder: URL,
                      names: [String], version: String?) async throws -> (name: String, base: CartoucheSaveBase) {
        var saves = here
        let content = try here.content ?? CartoucheSaveSync.content(ofSavesIn: documents)
        saves.content = content
        var name = CartoucheSaveSync.keepName(written: here.written, under: newest?.date)
        var date = CartoucheSaveSync.date(inName: name) ?? here.written
        while names.contains(name) {
            let there = try await archive(of: folder.appendingPathComponent(name))
            if CartoucheSaveSync.content(of: there.entries) == content {
                return (name, CartoucheSaveBase(place: place, copy: name, content: content, look: here.look,
                                                gameVersion: CartoucheSaveSync.gameVersion(inComment: there.comment)))
            }
            date = date.addingTimeInterval(-1)
            name = CartoucheSaveSync.fileName(date)
        }
        let base = try await send(documents, saves, as: name, to: folder, version: version)
        return (name, base)
    }

    /// Brings COPY to DOCUMENTS in place of the saves there, once it was
    /// copied whole to the Mac and reads as a copy of saves, and while the
    /// game is QUIET; the base it makes.
    private func fetch(_ copy: CartoucheSaveCopy, into documents: URL, from folder: URL,
                       quiet: @Sendable () -> Bool) async throws -> CartoucheSaveBase {
        let fileManager = FileManager.default
        let work = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        // The folder may be a share, and another device may replace the
        // copy meanwhile: what is unpacked is what was checked.
        let local = work.appendingPathComponent("copy.zip")
        try fileManager.copyItem(at: folder.appendingPathComponent(copy.name), to: local)
        let file = try CartoucheFileSource(local)
        let archive: CartoucheZipArchive
        do {
            archive = try await CartoucheZip.archive(of: file)
        } catch {
            throw MacSavesError.unreadable(copy.name)
        }
        let entries = archive.entries
        guard CartoucheSaveSync.holdsSavesOnly(entries) else { throw MacSavesError.unreadable(copy.name) }
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        do {
            try await CartoucheZip.extract(file, entries: entries, into: unpacked)
        } catch {
            throw MacSavesError.unreadable(copy.name)
        }
        // The copy took its time on a share: the game may have started.
        guard quiet() else { throw MacSavesError.busy }
        try CartoucheSaveSync.replaceSaves(in: documents, with: unpacked, aside: work.appendingPathComponent("replaced", isDirectory: true))
        return CartoucheSaveBase(place: place, copy: copy.name, content: CartoucheSaveSync.content(of: entries),
                                 look: CartoucheSaveSync.saves(in: documents)?.look ?? "",
                                 gameVersion: CartoucheSaveSync.gameVersion(inComment: archive.comment))
    }

    /// Keeps the newest copies in FOLDER, MADE among them whatever its date,
    /// and SPARING too, and removes what a copy given up left over an hour
    /// ago, as Cartouche does.
    private func prune(_ folder: URL, made: String, sparing: String?) {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let stale = Date().addingTimeInterval(-3600)
        for name in names where name.hasSuffix(".partial") && name != made + ".partial" {
            let url = folder.appendingPathComponent(name)
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if (modified ?? .distantPast) < stale { try? fileManager.removeItem(at: url) }
        }
        let others = names.filter { $0 != made && CartoucheSaveSync.date(inName: $0) != nil }.sorted(by: >)
        for name in others.dropFirst(CartoucheSaveSync.kept - 1) where name != sparing {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Finding the folder

    /// Whether FOLDER looks like a saves folder of Cartouche's: a folder of
    /// games' folders "… [<title ID>]" holding copies "<date>.zip".
    public static func looksLikeSaves(_ folder: URL) -> Bool {
        looksLikeSaves(folder, names: (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    private static func looksLikeSaves(_ folder: URL, names: [String]) -> Bool {
        for name in names.prefix(500) where hasTitleID(name) {
            let game = folder.appendingPathComponent(name, isDirectory: true)
            guard isFolder(game), let copies = try? FileManager.default.contentsOfDirectory(atPath: game.path) else { continue }
            if copies.contains(where: { CartoucheSaveSync.date(inName: $0) != nil }) { return true }
        }
        return false
    }

    /// Saves folders of Cartouche's on the disks and shares mounted on this
    /// Mac (VOLUMES), down to DEPTH folders inside each: the folder Cartouche
    /// keeps on a NAS, as the NAS is mounted here. The Mac's own disk is not
    /// looked through, and BUDGET folders at most are, a share being slow
    /// to list.
    public static func found(in volumes: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true), depth: Int = 3, budget: Int = 300) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var visited = 0
        var level: [URL] = ((try? fileManager.contentsOfDirectory(atPath: volumes.path)) ?? []).sorted()
            .map { volumes.appendingPathComponent($0, isDirectory: true) }
            .filter { isFolder($0) && !isLink($0) }
        for _ in 0 ... depth {
            var next: [URL] = []
            for folder in level {
                guard visited < budget else { return found }
                visited += 1
                let names = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
                if looksLikeSaves(folder, names: names) {
                    found.append(folder)
                    continue
                }
                next += names.prefix(100).map { folder.appendingPathComponent($0, isDirectory: true) }.filter { isFolder($0) && !isLink($0) }
            }
            level = next
            if level.isEmpty { break }
        }
        return found
    }

    /// The saves folder this Mac takes by itself, as the player would with
    /// Use it on the iPhone page, when they chose none: Cartouche's saves
    /// folder on a share mounted here, when one was FOUND, and only one. The
    /// builder's own folder (OWN) is the one the bridge shares as Saves: an
    /// iPhone PAIRED with this Mac may keep its saves there, and would find
    /// another folder in their place; with one, the builder's folder is left
    /// only when each game folder with a copy in it is one of a game this
    /// Mac kept in step there (SYNCED, title IDs).
    public static func adopted(found: [URL], own: URL, paired: Bool, synced: Set<String>) -> URL? {
        guard found.count == 1, found[0].standardizedFileURL.path != own.standardizedFileURL.path else { return nil }
        if paired {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: own.path)) ?? []
            for name in names {
                guard let titleID = titleID(in: name) else { continue }
                let folder = own.appendingPathComponent(name, isDirectory: true)
                guard isFolder(folder), let copies = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
                      copies.contains(where: { CartoucheSaveSync.date(inName: $0) != nil }) else { continue }
                if !synced.contains(titleID) { return nil }
            }
        }
        return found[0]
    }

    /// Whether NAME ends with a title ID in brackets: "Game [0100152000022000]".
    static func hasTitleID(_ name: String) -> Bool {
        titleID(in: name) != nil
    }

    /// The title ID NAME ends with, in brackets, in capitals.
    static func titleID(in name: String) -> String? {
        guard name.hasSuffix("]"), let open = name.lastIndex(of: "[") else { return nil }
        let id = String(name[name.index(after: open) ..< name.index(before: name.endIndex)])
        return isTitleID(id) ? id.uppercased() : nil
    }

    /// Whether TEXT is a title ID: 16 hexadecimal digits.
    public static func isTitleID(_ text: String) -> Bool {
        text.count == 16 && text.allSatisfy(\.isHexDigit)
    }

    static func isFolder(_ url: URL) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) && folder.boolValue
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

// MARK: What the Mac knows of each game's saves

/// What moved last with a game's saves, or why nothing did: what the game's
/// sheet says.
public struct MacSaveEvent: Codable, Equatable, Sendable {
    /// When.
    public var at: Date
    /// Before the game started, after it, or while it did not run.
    public var when: MacSaveMoment
    /// What was done (CartoucheSaveStep), "putBack" for a copy the player
    /// put back, "heldBack" for a newest copy that waits for the game's
    /// update, or "offline", "failed".
    public var step: String
    /// The copy that came, by name: its date is when its saves were written.
    public var fetched: String?
    /// The copy the saves of the Mac were kept as, under a newer one.
    public var kept: String?
    /// The copy the saves of the Mac went to.
    public var sent: String?
    /// For "failed": what went wrong, in the player's words.
    public var failure: String?
    /// For "heldBack": the version of the game the newest copy names, and
    /// that of the app on this Mac, older.
    public var newer: String?
    public var game: String?

    public init(at: Date, when: MacSaveMoment, step: String, fetched: String? = nil, kept: String? = nil, sent: String? = nil, failure: String? = nil,
                newer: String? = nil, game: String? = nil) {
        self.at = at
        self.when = when
        self.step = step
        self.fetched = fetched
        self.kept = kept
        self.sent = sent
        self.failure = failure
        self.newer = newer
        self.game = game
    }

    public var offline: Bool { step == "offline" }
    public var failed: Bool { step == "failed" }

    /// The step of a copy the player put back from Cartouche's console.
    public static let putBack = "putBack"
    /// The step of a newest copy a newer version of the game wrote, which
    /// waits for the game's update: this Mac's saves went under it as a
    /// copy (kept), or stayed as they were.
    public static let heldBack = "heldBack"

    /// The date the saves that came were written, and those of the Mac
    /// kept as a copy under a newer one, as their copies' names say: what
    /// the game's sheet in Cartouche's console tells, as the iPhone's.
    public var fetchedDate: Date? { fetched.flatMap(CartoucheSaveSync.date(inName:)) }
    public var keptDate: Date? { kept.flatMap(CartoucheSaveSync.date(inName:)) }
}

/// When a game's saves are kept in step.
public enum MacSaveMoment: String, Codable, Sendable {
    /// Before the game starts, from the Builder: the newest copy comes.
    case before
    /// While the game plays, a few seconds after it saved: the saves of the
    /// Mac go, from a copy of them made at one moment.
    case during
    /// After a game, wherever it was started: the saves of the Mac go.
    case after
    /// While the game does not run: a copy that arrived comes, saves the
    /// Mac made while the Builder was closed go.
    case round
}

/// What a sync of a game's saves while it plays did, for its watch
/// (CartoucheSaveWatch).
public struct MacSavePlayed: Equatable, Sendable {
    /// The event it records, nil when nothing new is to be said.
    public var event: MacSaveEvent?
    /// How the saves looked, in nxnative's folder, when they went or were
    /// found in step.
    public var inStep: String?
    /// They kept changing while they were copied: they go once they stop.
    public var moved: Bool
    /// They did not go: the saves folder away, or failing.
    public var failed: Bool

    public init(event: MacSaveEvent? = nil, inStep: String? = nil, moved: Bool = false, failed: Bool = false) {
        self.event = event
        self.inStep = inStep
        self.moved = moved
        self.failed = failed
    }
}

/// What this Mac knows of a game's saves.
public struct MacSaveRecord: Codable, Equatable {
    /// What was the same on both sides last.
    public var base: CartoucheSaveBase?
    /// The last time a copy went or came, or could not.
    public var last: MacSaveEvent?

    public init(base: CartoucheSaveBase? = nil, last: MacSaveEvent? = nil) {
        self.base = base
        self.last = last
    }
}

/// The records of every game, in a file of the builder's (mac-saves.json).
public final class MacSaveStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var records: [String: MacSaveRecord]

    public init(url: URL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([String: MacSaveRecord].self, from: $0) } ?? [:]
    }

    public func record(_ titleID: String) -> MacSaveRecord {
        lock.lock()
        defer { lock.unlock() }
        return records[titleID.uppercased()] ?? MacSaveRecord()
    }

    /// The games whose saves this Mac kept in step with the saves folder
    /// ROOT last, by title ID.
    public func games(syncedIn root: URL) -> Set<String> {
        let place = "mac|" + root.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        return Set(records.filter { $0.value.base?.place == place }.map(\.key))
    }

    public func set(_ titleID: String, _ record: MacSaveRecord) {
        lock.lock()
        records[titleID.uppercased()] = record
        let all = records
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Keeps the games' saves in step one sync at a time, and records what
/// each did.
public actor MacSaveKeeper {
    public let store: MacSaveStore
    /// The last sync asked for, which the next one waits for: an actor lets
    /// another call in while one waits on the disk, and two syncs of a game
    /// at once would both move its saves.
    private var queue: Task<Void, Never>?
    /// When each game's saves were last kept in step, whether a copy moved
    /// or not, by title ID: since the builder opened.
    private var checked: [String: Date] = [:]
    /// The copy each game's saves went to while it played, by title ID,
    /// which the next one takes the place of, until the one after the game.
    private var playCopies: [String: String] = [:]

    public init(store: MacSaveStore) {
        self.store = store
    }

    /// Sends GAME's saves, which changed while it plays, from DOCUMENTS,
    /// nxnative's folder of the game's own, to FOLDER, once the syncs asked
    /// for before ended: from a copy of them made at one moment, in SCRATCH
    /// (CartoucheSaveSync.snapshot), so that a save the game is writing
    /// never goes half written, taking the place of the copy they went to
    /// before in the same game. What its watch learns of it.
    public func sendPlaying(_ game: MacSaveGame, from documents: URL, in folder: any MacSavesPlace, scratch: URL,
                            now: Date = Date()) async -> MacSavePlayed {
        let previous = queue
        let this = Task { () -> MacSavePlayed in
            _ = await previous?.value
            return await self.runPlaying(game, from: documents, in: folder, scratch: scratch, now: now)
        }
        queue = Task { _ = await this.value }
        return await this.value
    }

    /// Keeps GAME's saves in step with FOLDER, at WHEN: before the game (the
    /// newest copy comes), after it (the saves of the Mac go), or while it
    /// does not run, once the syncs asked for before ended. QUIET: whether
    /// the game still does not run, just before a copy takes the place of
    /// its saves. The event it records: nil when nothing moved and nothing
    /// went wrong, or the game started meanwhile, the last event staying as
    /// it was.
    @discardableResult
    public func sync(_ game: MacSaveGame, in folder: any MacSavesPlace, when: MacSaveMoment, now: Date = Date(),
                     quiet: @escaping @Sendable () -> Bool = { true }) async -> MacSaveEvent? {
        let previous = queue
        let this = Task { () -> MacSaveEvent? in
            _ = await previous?.value
            return await self.run(game, in: folder, when: when, now: now, quiet: quiet).event
        }
        queue = Task { _ = await this.value }
        return await this.value
    }

    /// Puts the copy NAME back as GAME's saves on this Mac, from FOLDER, as
    /// the player chose it in Cartouche's console (MacSavesFolder.putBack),
    /// once the syncs asked for before ended: the event it records, a put
    /// back ("putBack"). It throws what kept it from going (MacSavesError):
    /// the last event stays as it was then.
    @discardableResult
    public func putBack(_ name: String, of game: MacSaveGame, in folder: any MacSavesPlace, now: Date = Date(),
                        quiet: @escaping @Sendable () -> Bool = { true }) async throws -> MacSaveEvent {
        let previous = queue
        let this = Task { () -> Result<MacSaveEvent, Error> in
            _ = await previous?.value
            return await self.runPutBack(name, of: game, in: folder, now: now, quiet: quiet)
        }
        queue = Task { _ = await this.value }
        return try await this.value.get()
    }

    /// Runs CHANGE on a game's saves on this Mac, as the player asked in
    /// Cartouche's console (a save from their Switch put in place of the
    /// game's, or the one it replaced put back), once the syncs asked for
    /// before ended, and none starts meanwhile: what it gives, or throws.
    public func change<T: Sendable>(_ change: @escaping @Sendable () throws -> T) async throws -> T {
        let previous = queue
        let this = Task { () -> Result<T, Error> in
            _ = await previous?.value
            return Result { try change() }
        }
        queue = Task { _ = await this.value }
        return try await this.value.get()
    }

    private func runPutBack(_ name: String, of game: MacSaveGame, in folder: any MacSavesPlace, now: Date,
                            quiet: @Sendable () -> Bool) async -> Result<MacSaveEvent, Error> {
        var record = store.record(game.titleID)
        do {
            let outcome = try await folder.putBack(name, of: game, base: record.base, quiet: quiet)
            checked[game.titleID] = now
            record.base = outcome.base
            let event = MacSaveEvent(at: now, when: .round, step: MacSaveEvent.putBack, fetched: outcome.fetched,
                                     kept: outcome.kept, sent: outcome.sent)
            record.last = event
            store.set(game.titleID, record)
            return .success(event)
        } catch {
            return .failure(error)
        }
    }

    /// When GAME's saves were last kept in step, a copy moving or not; nil
    /// when they were not since the builder opened.
    public func lastChecked(_ titleID: String) -> Date? {
        checked[titleID.uppercased()]
    }

    private func runPlaying(_ game: MacSaveGame, from documents: URL, in folder: any MacSavesPlace, scratch: URL,
                            now: Date) async -> MacSavePlayed {
        let root = scratch.appendingPathComponent("playing", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot: CartoucheSavesSnapshot
        do {
            guard let made = try CartoucheSaveSync.snapshot(ofSavesIn: documents,
                                                            into: root.appendingPathComponent(game.titleID, isDirectory: true)) else {
                return MacSavePlayed(moved: true)
            }
            snapshot = made
        } catch {
            return MacSavePlayed(event: record(failure: error, of: game, when: .during, now: now), failed: true)
        }
        // Nothing changed since they last went.
        let base = store.record(game.titleID).base
        if base?.place == folder.place, base?.look == snapshot.look {
            return MacSavePlayed(inStep: snapshot.look)
        }
        let (event, through) = await run(game, in: folder.reading(games: root), when: .during, now: now, quiet: { true },
                                         snapshot: snapshot)
        return through ? MacSavePlayed(event: event, inStep: snapshot.look) : MacSavePlayed(event: event, failed: true)
    }

    /// What a failure to keep GAME's saves in step at WHEN records: the
    /// event, nil when the last one said so already.
    private func record(failure error: Error, of game: MacSaveGame, when: MacSaveMoment, now: Date) -> MacSaveEvent? {
        var record = store.record(game.titleID)
        let event = MacSaveEvent(at: now, when: when, step: "failed", failure: error.localizedDescription)
        if let last = record.last, last.step == event.step, last.failure == event.failure { return nil }
        record.last = event
        store.set(game.titleID, record)
        return event
    }

    /// The sync: the event it records, and whether it went through.
    private func run(_ game: MacSaveGame, in folder: any MacSavesPlace, when: MacSaveMoment, now: Date,
                     quiet: @Sendable () -> Bool,
                     snapshot: CartoucheSavesSnapshot? = nil) async -> (event: MacSaveEvent?, through: Bool) {
        var record = store.record(game.titleID)
        let event: MacSaveEvent?
        var through = false
        // A game starting, or not playing, begins anew: its next copy takes
        // no other's place.
        if when == .before || when == .round { playCopies[game.titleID] = nil }
        do {
            var outcome = try await folder.sync(game, base: snapshot.map { $0.forCopy(record.base) } ?? record.base,
                                                fetching: when == .before || when == .round, quiet: quiet,
                                                replacing: when == .during || when == .after ? playCopies[game.titleID] : nil)
            if let snapshot { outcome.base = snapshot.forGame(outcome.base) }
            if when == .during, let sent = outcome.sent {
                playCopies[game.titleID] = sent
            } else if when == .after {
                playCopies[game.titleID] = nil
            }
            checked[game.titleID] = now
            through = true
            record.base = outcome.base
            if let newer = outcome.newer {
                event = MacSaveEvent(at: now, when: when, step: MacSaveEvent.heldBack, kept: outcome.kept, newer: newer, game: game.version)
            } else {
                event = outcome.moved
                    ? MacSaveEvent(at: now, when: when, step: outcome.step.rawValue, fetched: outcome.fetched, kept: outcome.kept, sent: outcome.sent)
                    : nil
            }
        } catch MacSavesError.busy {
            // It comes at the game's next quiet moment.
            return (nil, false)
        } catch MacSavesError.offline {
            event = MacSaveEvent(at: now, when: when, step: "offline")
        } catch MacSavesError.unreadable(let name) {
            event = MacSaveEvent(at: now, when: when, step: "failed",
                                 failure: tr("The copy \(name) does not read as a copy of saves: the saves of this Mac stay as they are.",
                                             "La copie \(name) ne se lit pas comme une copie de sauvegardes : celles de ce Mac restent telles quelles.",
                                             "La copia \(name) no se puede leer como copia de partidas guardadas: las de este Mac se quedan como están.",
                                             "Die Kopie \(name) lässt sich nicht als Kopie von Spielständen lesen: Die Spielstände dieses Mac bleiben, wie sie sind."))
        } catch {
            event = MacSaveEvent(at: now, when: when, step: "failed", failure: error.localizedDescription)
        }
        if let event {
            // A folder still offline, or still failing, keeps the time it
            // started to, and a copy still waiting for the game's update,
            // when nothing went.
            if let last = record.last, last.step == event.step, last.failure == event.failure, event.offline || event.failed {
                return (nil, through)
            }
            if let last = record.last, last.step == MacSaveEvent.heldBack, event.step == MacSaveEvent.heldBack,
               last.newer == event.newer, last.game == event.game, event.kept == nil {
                if record != store.record(game.titleID) { store.set(game.titleID, record) }
                return (nil, through)
            }
            record.last = event
        }
        if record != store.record(game.titleID) {
            store.set(game.titleID, record)
        }
        return (event, through)
    }
}
