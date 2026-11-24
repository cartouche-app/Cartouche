//
//  CartoucheSaveSync.swift
//  Cartouche
//
//  How a game's saves on this iPhone are kept in step with their copies in
//  the player's saves folder, the way nxnative keeps a game's save in step
//  with a cloud folder (dm/host/save_sync.c, ss_decide):
//
//  - The saves are the game's Documents/save and Documents/save_device, the
//    folders nxnative commits a game's saves to. A copy is a zip of them,
//    "<game> [<title ID>]/<date>.zip" in the saves folder, named by the time
//    its saves were last written, in UTC: the copies sort by when the game
//    saved, whichever iPhone made them, and the newest is the save played
//    last. A copy an older Cartouche made is named by the time it was made,
//    just after the game.
//  - Two saves are the same when their files are: the same paths, sizes and
//    CRC-32s, which a zip's central directory holds, so that a copy is
//    compared without being downloaded.
//  - For each game, Cartouche keeps the base: the copy last known to be the
//    same as the saves here, what it holds, and how the saves here looked
//    then, their files' count, size and newest date, which change whenever
//    the game saves.
//  - Which way, as ss_decide: nothing in the folder, the saves here go
//    there; nothing here, the newest copy comes; the same save on both
//    sides, nothing moves; only the folder's changed since the base, its
//    newest copy comes; only the saves here changed, they go; both changed,
//    or this iPhone never synced the game with this folder, the saves
//    written last win, and the others are kept as a copy of their own date.
//  - The newest copy comes when the game is installed and before it starts;
//    the saves here go a few seconds after the game saves, while it plays
//    and Cartouche runs beside it (CartoucheSaveWatch), and after the game.
//    A copy that goes as the newest is named after the newest one there,
//    so that it is the newest whatever the iPhones' clocks say.
//  - While the game plays, its saves go from a copy of them made at one
//    moment (snapshot): nxnative swaps a save's folder whole at each
//    commit, and a folder read while it swaps would mix two saves. Each
//    copy that goes while the game plays, and the one after it, takes the
//    place of the one that went before in the same game, so that the
//    copies kept are those of the last games, not of the last minutes of
//    one.
//  - Each copy names the version of the game that wrote its saves, in its
//    zip's comment, which older Cartouches leave aside. A game older than
//    the newest copy's never takes it, nor puts its own saves over it: they
//    go as a copy of their own date under it, and the newest copy waits for
//    the game to be updated (heldBack). A copy without a version, made by
//    an older Cartouche, or a version that does not read as numbers, holds
//    nothing back.
//
//  Platform-independent: tested on its own by launcher/Package.swift.
//  Public for Cartouche Builder, which keeps the saves of a game played on
//  the Mac in step with the same copies (builder/mac MacSaves.swift).
//

import CryptoKit
import Foundation

/// A game's saves on this iPhone.
public struct CartoucheLocalSaves: Hashable {
    /// How they look: their files' count, size and newest date, which
    /// change whenever the game saves.
    public let look: String
    /// When they were last written: the date of their newest file.
    public let written: Date
    /// What they hold (CartoucheSaveSync.content), once read.
    public var content: String?

    public init(look: String, written: Date, content: String? = nil) {
        self.look = look
        self.written = written
        self.content = content
    }
}

/// The newest copy of a game's saves in the saves folder.
public struct CartoucheSaveCopy: Hashable {
    public let name: String
    /// The date its name gives.
    public let date: Date
    /// What it holds, from its zip's central directory, once read.
    public var content: String?
    /// The version of the game that wrote its saves, from its zip's
    /// comment, once read; nil for a copy that names none.
    public var gameVersion: String?

    public init(name: String, date: Date, content: String? = nil, gameVersion: String? = nil) {
        self.name = name
        self.date = date
        self.content = content
        self.gameVersion = gameVersion
    }
}

/// What this iPhone last knew to be the same here and in the saves folder,
/// for one game.
public struct CartoucheSaveBase: Codable, Hashable {
    /// The saves folder: its server's ID and its path, "<ID>|<path>". A base
    /// holds for that folder only.
    public var place: String
    /// The copy, by name, in the game's folder there.
    public var copy: String
    /// What it holds (CartoucheSaveSync.content); nil for a base an older
    /// Cartouche left, which knew the copy by its name only.
    public var content: String?
    /// How the saves here looked then (CartoucheLocalSaves.look).
    public var look: String
    /// The version of the game the copy names, when it was known: the
    /// newest copy's, when it is the base's, needs no reading then. Nil for
    /// a base an older Cartouche left.
    public var gameVersion: String?

    public init(place: String, copy: String, content: String?, look: String, gameVersion: String? = nil) {
        self.place = place
        self.copy = copy
        self.content = content
        self.look = look
        self.gameVersion = gameVersion
    }
}

/// What to do with a game's saves.
public enum CartoucheSaveStep: String, Codable {
    /// Nothing moves: neither side changed since the base, or only the
    /// folder's, whose newest copy comes at the game's next start.
    case none
    /// Both sides hold the same save, which becomes the base.
    case same
    /// What both sides hold must be read first, to compare them.
    case compare
    /// The saves here go to the folder, as its newest copy.
    case send
    /// The saves here go to the folder as a copy of their own date, under
    /// the newest one there, which is newer and comes at the game's next
    /// start.
    case keep
    /// The newest copy comes here, in place of the saves here, which the
    /// folder has already.
    case fetch
    /// The saves here go to the folder as a copy of their own date, then the
    /// newest copy, which is newer, comes here in their place.
    case keepAndFetch
}

public enum CartoucheSaveSync {
    /// The folders of a game's Documents that nxnative keeps its saves in.
    public static let folders = ["save", "save_device"]
    /// nxnative's working copy of the saves, which the game makes again from
    /// them when it starts: it goes when other saves come in.
    public static let workFolder = "save.work"
    /// The copies kept for each game.
    public static let kept = 10

    // MARK: Which way

    /// Which way a game's saves go between HERE, the saves on this iPhone,
    /// nil when the game has none, and NEWEST, the newest copy in the game's
    /// folder, nil when there is none, from BASE, nil when this iPhone never
    /// synced the game with that folder. BASEISTHERE: whether the base's
    /// copy is still in the folder. FETCHING: whether the newest copy may
    /// come now, as it does when the game is installed and before it
    /// starts, rather than after a game. .compare asks for what both sides
    /// hold first: called again with it, the step is never .compare.
    public static func step(here: CartoucheLocalSaves?, newest: CartoucheSaveCopy?, base: CartoucheSaveBase?,
                     baseIsThere: Bool, fetching: Bool) -> CartoucheSaveStep {
        guard let here else {
            // Nothing here: the newest copy comes, unless it came already and
            // held no save.
            guard let newest, fetching else { return .none }
            if let base, base.copy == newest.name, base.look.isEmpty { return .none }
            return .fetch
        }
        // Nothing in the folder, or a copy that holds no save.
        guard let newest, newest.content != "" else { return .send }
        let hereIsBase = base.map { $0.look == here.look || ($0.content != nil && $0.content == here.content) } ?? false
        let copyIsBase = base.map { $0.copy == newest.name || ($0.content != nil && $0.content == newest.content) } ?? false
        if hereIsBase && copyIsBase { return .none }
        guard let mine = here.content, let theirs = newest.content else { return .compare }
        if mine == theirs { return .same }
        if hereIsBase {
            // Only the folder's changed: its newest copy comes, at the start.
            // The saves here go first if the base's copy is no longer there.
            guard fetching else { return .none }
            return baseIsThere ? .fetch : .keepAndFetch
        }
        // Only the saves here changed.
        if copyIsBase { return .send }
        // Both changed since the base, or this iPhone never synced the game
        // with this folder: the saves written last win, the others are kept.
        // The same second: this iPhone's, as nxnative keeps its own.
        if newest.date > here.written { return fetching ? .keepAndFetch : .keep }
        return .send
    }

    // MARK: Saves kept in step with another folder

    /// Whether SAVES are those BASE was made of: the same look, or the same
    /// content written again.
    public static func unchanged(_ saves: CartoucheLocalSaves, since base: CartoucheSaveBase) -> Bool {
        saves.look == base.look || (base.content != nil && saves.content == base.content)
    }

    /// STEP, as step() gave it with no base, for HERE, saves a device kept
    /// in step with another saves folder, as LEFT, its base there, says:
    /// on a Mac whose saves folder became its iPhone's (Cartouche Builder,
    /// MacSaves.swift). Saves it did not change since are no news for this
    /// folder, whatever their date: a game first played before the player
    /// chose the iPhone's folder made new ones, which would have gone as the
    /// newest copy, for the iPhone to take in place of its own. They stay
    /// in the folder they were in step with, and NEWEST, this folder's
    /// newest copy, comes in their place, as on a device without saves;
    /// were their copy no longer in the folder left (LEFTTHERE), they are
    /// kept here first, as a copy of their date under it. Not FETCHING,
    /// nothing moves. Saves changed since, which a game started since made,
    /// and a newest copy of no save, keep STEP: the saves written last win.
    public static func afterLeaving(_ step: CartoucheSaveStep, left: CartoucheSaveBase, here: CartoucheLocalSaves?,
                                    newest: CartoucheSaveCopy?, fetching: Bool, leftThere: () -> Bool) -> CartoucheSaveStep {
        guard let here, let newest, newest.content != "", [.send, .keep, .keepAndFetch].contains(step),
              unchanged(here, since: left) else { return step }
        return !fetching ? .none : leftThere() ? .fetch : .keepAndFetch
    }

    // MARK: The game's version

    /// Whether STEP would bring the newest copy here, or put the saves here
    /// over it, so that its game's version must be known first.
    public static func needsCopyVersion(_ step: CartoucheSaveStep) -> Bool {
        step == .fetch || step == .keepAndFetch || step == .send
    }

    /// STEP, as step() gave it, when the newest copy's saves were written by
    /// version COPY of the game and the game here is version GAME: a game
    /// older than the copy's never takes it, nor puts its saves over it, so
    /// that it never reads saves a newer version wrote, and the player keeps
    /// what they played there. The saves here go as a copy of their own date
    /// under the newest one instead, and it waits for the game's update.
    public static func heldBack(_ step: CartoucheSaveStep, copy: String?, game: String?) -> CartoucheSaveStep {
        guard isNewer(copy, than: game) else { return step }
        switch step {
        case .fetch: return .none
        case .keepAndFetch, .send: return .keep
        case .none, .same, .compare, .keep: return step
        }
    }

    /// Whether VERSION is newer than OTHER, both as a game's version shows
    /// it, "1.2.0": numbers, compared one by one, a missing one 0. False
    /// when either is missing or does not read as numbers.
    public static func isNewer(_ version: String?, than other: String?) -> Bool {
        guard let mine = numbers(of: version), let theirs = numbers(of: other) else { return false }
        for index in 0 ..< max(mine.count, theirs.count) {
            let a = index < mine.count ? mine[index] : 0
            let b = index < theirs.count ? theirs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(of version: String?) -> [Int]? {
        guard let version = version?.trimmingCharacters(in: .whitespaces), !version.isEmpty else { return nil }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    /// A copy's zip comment, which names the version of the game that wrote
    /// its saves: {"gameVersion":"1.2.0"}. Empty for no version.
    public static func comment(gameVersion: String?) -> Data {
        guard let version = gameVersion?.trimmingCharacters(in: .whitespaces), !version.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["gameVersion": String(version.prefix(64))],
                                                     options: [.sortedKeys])
        else { return Data() }
        return data
    }

    /// The version of the game a copy's zip COMMENT names; nil for none, as
    /// in a copy an older Cartouche made.
    public static func gameVersion(inComment comment: Data) -> String? {
        guard !comment.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: comment) as? [String: Any],
              let version = (object["gameVersion"] as? String)?.trimmingCharacters(in: .whitespaces),
              !version.isEmpty
        else { return nil }
        return version
    }

    // MARK: The copies' names

    /// Made for each use: a formatter is not for several threads at once.
    private static func nameFormat() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }

    /// A copy's name, its date in UTC: "2026-11-06T14-05-33Z.zip". The
    /// names sort by date.
    public static func fileName(_ date: Date) -> String {
        nameFormat().string(from: date) + ".zip"
    }

    public static func date(inName name: String) -> Date? {
        guard name.lowercased().hasSuffix(".zip") else { return nil }
        return nameFormat().date(from: String(name.dropLast(4)))
    }

    /// No save is older: a date before it is no date.
    private static let earliest = Date(timeIntervalSince1970: 946_684_800)

    /// The name of a copy that goes as the newest, of saves WRITTEN then:
    /// their date, but never later than NOW, and a second after AFTER, the
    /// newest copy there, when that is later.
    public static func sendName(written: Date, after newest: Date?, now: Date = Date()) -> String {
        var seconds = (written < earliest ? now : min(written, now)).timeIntervalSince1970.rounded(.down)
        if let newest {
            seconds = max(seconds, newest.timeIntervalSince1970.rounded(.down) + 1)
        }
        return fileName(Date(timeIntervalSince1970: seconds))
    }

    /// The name of a copy that keeps saves WRITTEN then, under NEWEST, the
    /// newer copy there: their own date, but never later than NOW, and a
    /// second before NEWEST at the latest.
    public static func keepName(written: Date, under newest: Date?, now: Date = Date()) -> String {
        var seconds = (written < earliest ? now : min(written, now)).timeIntervalSince1970.rounded(.down)
        if let newest {
            seconds = min(seconds, newest.timeIntervalSince1970.rounded(.down) - 1)
        }
        return fileName(Date(timeIntervalSince1970: seconds))
    }

    // MARK: The saves here

    /// The saves in DOCUMENTS, as they look now; nil when the game has none,
    /// no file in either folder.
    public static func saves(in documents: URL) -> CartoucheLocalSaves? {
        var count = 0
        var size: UInt64 = 0
        var newest: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for folder in folders {
            let root = documents.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path),
                  let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            while let url = walker.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                count += 1
                size += UInt64(values?.fileSize ?? 0)
                let date = Int64(((values?.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000).rounded())
                newest = max(newest, date)
            }
        }
        guard count > 0 else { return nil }
        // The form older versions kept their saves' fingerprint in.
        return CartoucheLocalSaves(look: "\(count)|\(size)|\(newest)",
                                   written: Date(timeIntervalSince1970: TimeInterval(newest) / 1000))
    }

    /// What the saves in DOCUMENTS hold: each file's path, size and CRC-32,
    /// and each link's target, as a zip of them lists them (writeZip, and
    /// content(of:) for a copy). "" when there is no file.
    public static func content(ofSavesIn documents: URL) throws -> String {
        var lines: [String] = []
        for folder in folders {
            let root = documents.appendingPathComponent(folder, isDirectory: true)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue,
                  let walker = FileManager.default.enumerator(atPath: root.path) else { continue }
            while let relative = walker.nextObject() as? String {
                let url = root.appendingPathComponent(relative)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let name = folder + "/" + relative
                if values.isSymbolicLink == true {
                    let target = Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8)
                    lines.append(line(name, size: UInt64(target.count), crc: CartoucheCRC32.of(target)))
                } else if values.isDirectory != true {
                    let (size, crc) = try checksum(of: url)
                    lines.append(line(name, size: size, crc: crc))
                }
            }
        }
        return digest(lines)
    }

    /// What a copy holds, from its zip's ENTRIES: what content(ofSavesIn:)
    /// gives for the saves it was made of.
    public static func content(of entries: [CartoucheZipEntry]) -> String {
        digest(entries.filter { !$0.isDirectory }.map { line($0.name, size: $0.size, crc: $0.crc) })
    }

    private static func line(_ name: String, size: UInt64, crc: UInt32) -> String {
        name + "\t" + String(size) + "\t" + String(format: "%08x", crc)
    }

    /// The first 16 bytes of the SHA-256 of LINES, in their bytes' order, in
    /// hex, as nxnative writes a save's hash; "" for none.
    private static func digest(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        let sorted = lines.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let hash = SHA256.hash(data: Data(sorted.joined(separator: "\n").utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func checksum(of url: URL) throws -> (size: UInt64, crc: UInt32) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var check = CartoucheCRC32()
        var size: UInt64 = 0
        while let chunk = try handle.cartoucheRead(upToCount: CartoucheSequentialReader.chunk) {
            check.update(chunk)
            size += UInt64(chunk.count)
        }
        return (size, check.value)
    }

    // MARK: Copies

    /// The saves' folders, files and links in DOCUMENTS, as a zip with paths
    /// from Documents: save/..., save_device/...; its comment names
    /// GAMEVERSION, the version of the game that wrote them, when known.
    public static func writeZip(ofSavesIn documents: URL, to sink: CartoucheByteSink,
                                gameVersion: String? = nil) async throws {
        let writer = CartoucheZipWriter(sink: sink)
        for folder in folders {
            let root = documents.appendingPathComponent(folder, isDirectory: true)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue,
                  let walker = FileManager.default.enumerator(atPath: root.path) else { continue }
            try await writer.addFolder(folder + "/")
            var relatives: [String] = []
            while let relative = walker.nextObject() as? String {
                relatives.append(relative)
            }
            for relative in relatives.sorted() {
                let url = root.appendingPathComponent(relative)
                let name = folder + "/" + relative
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                let date = values.contentModificationDate ?? Date()
                if values.isSymbolicLink == true {
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                    try await writer.addSymlink(name, target: target, date: date)
                } else if values.isDirectory == true {
                    try await writer.addFolder(name + "/", date: date)
                } else {
                    try await writer.addFile(name, from: url, date: date)
                }
            }
        }
        try await writer.finish(comment: comment(gameVersion: gameVersion))
    }

    /// Whether ENTRIES are those of a copy of saves: each in save/ or
    /// save_device/.
    public static func holdsSavesOnly(_ entries: [CartoucheZipEntry]) -> Bool {
        entries.allSatisfy { entry in
            folders.contains { entry.name == $0 + "/" || entry.name.hasPrefix($0 + "/") }
        }
    }

    /// Puts the saves unpacked in UNPACKED in place of those in DOCUMENTS,
    /// and removes nxnative's working copy, for the game to make it again
    /// from them. A folder the copy does not have goes, so that both sides
    /// hold the same. The folders replaced go to ASIDE, a folder of their
    /// own, first, and come back if a step fails.
    public static func replaceSaves(in documents: URL, with unpacked: URL, aside: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
        var moved: [String] = []
        var placed: [String] = []
        do {
            for folder in folders + [workFolder] {
                let here = documents.appendingPathComponent(folder, isDirectory: true)
                if fileManager.fileExists(atPath: here.path) {
                    try fileManager.moveItem(at: here, to: aside.appendingPathComponent(folder, isDirectory: true))
                    moved.append(folder)
                }
            }
            for folder in folders {
                let incoming = unpacked.appendingPathComponent(folder, isDirectory: true)
                if fileManager.fileExists(atPath: incoming.path) {
                    try fileManager.moveItem(at: incoming, to: documents.appendingPathComponent(folder, isDirectory: true))
                    placed.append(folder)
                }
            }
        } catch {
            // The saves as they were.
            for folder in placed {
                try? fileManager.removeItem(at: documents.appendingPathComponent(folder, isDirectory: true))
            }
            for folder in moved {
                try? fileManager.moveItem(at: aside.appendingPathComponent(folder, isDirectory: true),
                                          to: documents.appendingPathComponent(folder, isDirectory: true))
            }
            throw error
        }
    }
}

// MARK: The saves while the game plays

/// A game's saves copied as they were at one moment, while it plays: what
/// goes to the saves folder then (CartoucheSaveSync.snapshot).
public struct CartoucheSavesSnapshot: Hashable, Sendable {
    /// The folder they were copied into, laid out as a game's Documents:
    /// save/ and save_device/.
    public let documents: URL
    /// How the saves looked in the game's Documents as they were copied.
    public let look: String
    /// How they look in the copy: the same, but for dates a disk keeps less
    /// finely than another.
    public let copyLook: String

    public init(documents: URL, look: String, copyLook: String) {
        self.documents = documents
        self.look = look
        self.copyLook = copyLook
    }

    /// BASE, which holds for the saves in the game's Documents, as it holds
    /// for the copy: for a sync from it.
    public func forCopy(_ base: CartoucheSaveBase?) -> CartoucheSaveBase? {
        guard var base, base.look == look else { return base }
        base.look = copyLook
        return base
    }

    /// BASE, which a sync from the copy made, as it holds for the saves in
    /// the game's Documents.
    public func forGame(_ base: CartoucheSaveBase?) -> CartoucheSaveBase? {
        guard var base, base.look == copyLook else { return base }
        base.look = look
        return base
    }
}

extension CartoucheSaveSync {
    /// The saves in DOCUMENTS copied into FOLDER as they are at one moment,
    /// for them to go to the saves folder while the game plays. nxnative
    /// commits a game's saves by swapping each of their folders whole
    /// (Commit, renamex_np), so that a folder read while it swaps could
    /// hold files of two saves. The copy is made again, TRIES times at
    /// most, until the saves did not change while it was made; on an APFS
    /// disk it costs next to nothing (a clone). Nil when the game has no
    /// saves, or when they kept changing: they go once the game has
    /// stopped saving. COPIED runs once each copy is made, before the saves
    /// are looked at again: for the tests, a game that saves meanwhile.
    public static func snapshot(ofSavesIn documents: URL, into folder: URL, tries: Int = 3,
                                copied: () -> Void = {}) throws -> CartoucheSavesSnapshot? {
        let fileManager = FileManager.default
        var failure: Error?
        for _ in 0 ..< max(tries, 1) {
            guard let before = saves(in: documents) else { return nil }
            if fileManager.fileExists(atPath: folder.path) {
                try fileManager.removeItem(at: folder)
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            failure = nil
            for name in folders {
                let source = documents.appendingPathComponent(name, isDirectory: true)
                var isFolder: ObjCBool = false
                guard fileManager.fileExists(atPath: source.path, isDirectory: &isFolder), isFolder.boolValue else { continue }
                let copy = folder.appendingPathComponent(name, isDirectory: true)
                do {
                    try fileManager.copyItem(at: source, to: copy)
                    keepDates(from: source, in: copy)
                } catch {
                    // A file the game's commit took away under the copy.
                    failure = error
                    break
                }
            }
            copied()
            guard let after = saves(in: documents), after.look == before.look else { continue }
            // The saves did not change: a copy that failed all the same
            // will fail again.
            if let failure { throw failure }
            guard let inCopy = saves(in: folder) else { continue }
            return CartoucheSavesSnapshot(documents: folder, look: before.look, copyLook: inCopy.look)
        }
        try? fileManager.removeItem(at: folder)
        return nil
    }

    /// Gives each file in COPY the date of its own in SOURCE, which an APFS
    /// clone keeps already, and a copy on another disk may not.
    private static func keepDates(from source: URL, in copy: URL) {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(atPath: copy.path) else { return }
        while let relative = walker.nextObject() as? String {
            let copied = copy.appendingPathComponent(relative)
            guard let values = try? copied.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let date = try? source.appendingPathComponent(relative).resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate,
                  values.contentModificationDate != date else { continue }
            try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: copied.path)
        }
    }
}

/// When the saves a game makes while it plays go to the saves folder, the
/// game's saves looked at every few seconds (interval): once they have
/// stayed as they are for a few seconds since they last changed (quiet), as
/// a game often saves several times in a row, which nxnative's own sender
/// waits for too; and a minute at the latest after they first changed
/// (longest), for a game that never stops saving. Saves that did not go
/// are tried again a minute later (retry), or as soon as they change.
public struct CartoucheSaveWatch: Equatable, Sendable {
    /// How often the saves are looked at, in seconds.
    public static let interval: TimeInterval = 2
    public static let quiet: TimeInterval = 5
    public static let longest: TimeInterval = 60
    public static let retry: TimeInterval = 60

    /// How the saves looked when they were last in step with the saves
    /// folder: when they went, or when the game started.
    public private(set) var inStep: String?
    /// How they looked last, and since when.
    private var seen: String?
    private var seenSince: Date?
    /// When they first changed since they were last in step.
    private var changed: Date?
    /// Not tried again before then, unless they change.
    private var notBefore: Date?

    /// INSTEP: how the saves look when they are in step with the saves
    /// folder, as the game starts; nil when unknown, or never synced.
    public init(inStep: String?) {
        self.inStep = inStep
    }

    /// Whether the saves, which look as LOOK now (nil: the game has none),
    /// are to go now.
    public mutating func due(_ look: String?, now: Date = Date()) -> Bool {
        guard let look, look != inStep else {
            seen = look
            seenSince = nil
            changed = nil
            return false
        }
        if look != seen {
            seen = look
            seenSince = now
            notBefore = nil
        }
        let since = seenSince ?? now
        let first = changed ?? since
        changed = first
        if let notBefore, now < notBefore { return false }
        return now.timeIntervalSince(since) >= Self.quiet || now.timeIntervalSince(first) >= Self.longest
    }

    /// Whether saves that look as LOOK are yet to go: whatever is waiting
    /// goes at once when Cartouche leaves the screen.
    public func isPending(_ look: String?) -> Bool {
        look != nil && look != inStep
    }

    /// The saves that looked as LOOK went, or were found in step: what
    /// changed since goes in its turn.
    public mutating func sent(_ look: String) {
        inStep = look
        notBefore = nil
        if seen == look {
            changed = nil
        } else {
            // They changed again meanwhile: since they were seen so.
            changed = seenSince
        }
    }

    /// The saves did not go: they are tried again a minute later, or as
    /// soon as they change and the game stops saving, the longest wait
    /// counted anew from that change.
    public mutating func failed(now: Date = Date()) {
        notBefore = now.addingTimeInterval(Self.retry)
        changed = nil
    }

    /// The saves folder's server answers again: saves that did not go are
    /// tried again at once.
    public mutating func retryNow() {
        notBefore = nil
    }

    /// The saves changed while they were being copied: they go once they
    /// have stayed as they are for a few seconds.
    public mutating func moved() {
        seen = nil
    }
}
