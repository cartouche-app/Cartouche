//
//  CartoucheMods.swift
//  Cartouche
//
//  A game's mods: folders of files that the game reads in place of its own,
//  its textures, texts, music or levels. nxnative reads them itself
//  (DM_ROMFS_OVERLAY, docs/env_switches.tsv): the folders it names, in
//  their order, before the game's own files, the first that has a file
//  winning. Cartouche keeps them with the game, in its folder, where the
//  game reads its saves (its data folder's Documents on the iPhone, its
//  folder of nxnative's on the Mac): mods/<folder>/romfs, the files the mod
//  lays over the game's, and mods/mods.json, their names, their order and
//  which are on. Before each start, the line of the game's env.txt that
//  names the mods turned on, in their order, is written again
//  (prepareStart), with the paths the game itself sees: an iPhone's folders
//  may move when Cartouche is installed again.
//
//  A mod comes from what the player picks, a folder or a ZIP archive, as
//  mods are passed around: its romfs folder, at its root, under the mod's
//  own folder, or under atmosphere/contents/<title ID>/, as on a Switch's
//  microSD card. One that holds several romfs folders, as a pack of
//  variants does, gives several mods, turned off. A mod of another game, by
//  the title ID in its path, does not come; nor does a mod that changes the
//  game's code too, beside its romfs (exefs/): iOS runs only the code signed
//  with the game, and nxnative leaves such a plugin out there, so the game
//  waits for it on a black screen (nxnative's docs/reference/rewriter.md, A
//  mod's exefs plugin is left out); the Mac would need the plugin rewritten
//  first (scripts/prepare_mod.py), which Cartouche does not do yet. A
//  folder copied into mods/ by hand shows too, turned off.
//
//  Platform-independent: tested on its own by launcher/Package.swift; the
//  console on the Mac shows the same page, and Cartouche Builder writes the
//  line before it starts a game there (BuilderKit, MacGames.swift).
//

import Foundation

/// A game's mod, as Cartouche keeps it in the game's folder.
public struct CartoucheMod: Codable, Hashable, Identifiable, Sendable {
    /// Its folder in the game's mods folder.
    public var folder: String
    /// The name the player sees: that of the folder or the ZIP they picked,
    /// or of the mod's folder in it.
    public var name: String
    public var isOn: Bool
    /// Its files, and their size.
    public var files: Int
    public var size: UInt64
    /// The game's version when the mod came, when its build says it: a mod
    /// is often made for one.
    public var gameVersion: String?
    public var added: Date
    /// What stops it, read from its folder each time, never kept.
    public var problem: CartoucheModProblem?

    public var id: String { folder }

    public init(folder: String, name: String, isOn: Bool, files: Int, size: UInt64, gameVersion: String? = nil,
                added: Date, problem: CartoucheModProblem? = nil) {
        self.folder = folder
        self.name = name
        self.isOn = isOn
        self.files = files
        self.size = size
        self.gameVersion = gameVersion
        self.added = added
        self.problem = problem
    }

    private enum CodingKeys: String, CodingKey {
        case folder, name, isOn = "on", files, size, gameVersion, added
    }

    /// Whether the game takes it: on, with nothing that stops it.
    public var isTaken: Bool { isOn && problem == nil }
}

/// Why a mod cannot be added, or turned on.
public enum CartoucheModProblem: Error, Hashable, Sendable {
    /// No folder named romfs in it, where a mod's files go.
    case noRomfs
    /// Its romfs folder holds no file.
    case empty
    /// It changes the game's code too: a folder exefs with files, beside
    /// its romfs.
    case code
    /// A mod of another game, by the title ID in its path.
    case otherGame(String)
    /// A link, or a path that would land outside the mod.
    case unsafe(String)
}

/// A file or a folder of what the player picked, by its path in it.
public struct CartoucheModItem: Hashable, Sendable {
    public var path: String
    public var size: UInt64
    public var isFolder: Bool
    public var isLink: Bool

    public init(path: String, size: UInt64 = 0, isFolder: Bool = false, isLink: Bool = false) {
        self.path = path
        self.size = size
        self.isFolder = isFolder
        self.isLink = isLink
    }
}

/// A mod found in what the player picked.
public struct CartoucheModFound: Hashable, Sendable {
    public var name: String
    /// The path of its romfs folder in what was picked, "" for what was
    /// picked itself.
    public var romfs: String
    public var files: Int
    public var size: UInt64
}

/// A mod in what the player picked that does not come, and why.
public struct CartoucheModRefused: Hashable, Sendable {
    public var name: String
    public var problem: CartoucheModProblem
}

/// What the player picked, read.
public struct CartoucheModPick: Sendable {
    /// The folder or the archive picked.
    public var url: URL
    public var isArchive: Bool
    public var found: [CartoucheModFound]
    public var refused: [CartoucheModRefused]
}

public enum CartoucheMods {
    /// The game's folder of mods, in its Documents.
    public static let folderName = "mods"
    /// Their names, their order and which are on.
    static let listName = "mods.json"
    /// Where nxnative reads a mod's files, in its folder.
    static let romfsName = "romfs"
    /// The folder of a mod's code, which nxnative cannot run on an iPhone.
    static let exefsName = "exefs"
    /// The most mods on at once: nxnative keeps the line in 4,096 bytes
    /// (hle_fs.c), and each path takes a hundred or two on an iPhone.
    public static let mostOn = 16
    /// The most entries read in what was picked.
    static let itemLimit = 500_000

    public static func folder(in documents: URL) -> URL {
        documents.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: The list

    private struct ListFile: Codable {
        var schema = 1
        var mods: [CartoucheMod]
    }

    /// The game's mods, in their order: those its list names, whose folder
    /// is there, then the folders it does not name, turned off, as a player
    /// may copy one there; each with what stops it.
    public static func load(in documents: URL) -> [CartoucheMod] {
        let fileManager = FileManager.default
        let folder = folder(in: documents)
        let names = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { name in
            var isFolder: ObjCBool = false
            return !name.hasPrefix(".") && fileManager.fileExists(atPath: folder.appendingPathComponent(name).path, isDirectory: &isFolder)
                && isFolder.boolValue
        }
        let present = Set(names)
        var seen = Set<String>()
        let listed = ((try? Data(contentsOf: folder.appendingPathComponent(listName)))
            .flatMap { try? JSONDecoder.cartoucheMods.decode(ListFile.self, from: $0) }?.mods ?? [])
            .filter { present.contains($0.folder) && seen.insert($0.folder).inserted }
        var mods = listed
        for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) where !seen.contains(name) {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            let counted = count(romfs(of: url))
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            mods.append(CartoucheMod(folder: name, name: name, isOn: false, files: counted.files, size: counted.size,
                                     added: attributes?[.creationDate] as? Date ?? Date()))
        }
        for index in mods.indices {
            mods[index].problem = problem(of: folder.appendingPathComponent(mods[index].folder, isDirectory: true))
        }
        return mods
    }

    /// Keeps MODS, in their order, as the game's list.
    public static func save(_ mods: [CartoucheMod], in documents: URL) throws {
        let folder = folder(in: documents)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder.cartoucheMods.encode(ListFile(mods: mods))
        try data.write(to: folder.appendingPathComponent(listName), options: .atomic)
    }

    /// The romfs folder of the mod in FOLDER, in any letter case.
    static func romfs(of folder: URL) -> URL? {
        child(romfsName, of: folder)
    }

    private static func child(_ name: String, of folder: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let found = names.first(where: { $0 == name }) ?? names.first(where: { $0.lowercased() == name }) else { return nil }
        var isFolder: ObjCBool = false
        let url = folder.appendingPathComponent(found, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue ? url : nil
    }

    /// What stops the mod in FOLDER: no romfs folder, or code beside it.
    static func problem(of folder: URL) -> CartoucheModProblem? {
        guard romfs(of: folder) != nil else { return .noRomfs }
        if let exefs = child(exefsName, of: folder), count(exefs).files > 0 { return .code }
        return nil
    }

    /// The files under FOLDER, and their size.
    static func count(_ folder: URL?) -> (files: Int, size: UInt64) {
        guard let folder, let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return (0, 0) }
        var files = 0
        var size: UInt64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files += 1
            size += UInt64(max(values.fileSize ?? 0, 0))
        }
        return (files, size)
    }

    // MARK: Before a start

    /// The line's value for MODS, in DOCUMENTS: the romfs folders of those
    /// the game takes, in their order, under GAMEDOCUMENTS, the same
    /// Documents as the game sees them; nil when it takes none.
    public static func overlay(_ mods: [CartoucheMod], documents: URL, gameDocuments: URL) -> String? {
        let paths = mods.filter(\.isTaken).prefix(mostOn).map { mod -> String in
            // Its folder's own letters, read where Cartouche reaches it.
            let name = romfs(of: folder(in: documents).appendingPathComponent(mod.folder, isDirectory: true))?.lastPathComponent
                ?? romfsName
            return folder(in: gameDocuments).appendingPathComponent(mod.folder, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true).path
        }
        return paths.isEmpty ? nil : paths.joined(separator: ":")
    }

    /// Before the game starts: the line of its env.txt that names the mods
    /// it takes, written again, in DOCUMENTS, its Documents as Cartouche
    /// reaches them, with the paths of GAMEDOCUMENTS, the same as the game
    /// sees them. How many it takes.
    @discardableResult
    public static func prepareStart(documents: URL, gameDocuments: URL) throws -> Int {
        let mods = load(in: documents)
        try CartoucheModsLine.write(overlay(mods, documents: documents, gameDocuments: gameDocuments), documents: documents)
        return min(mods.filter(\.isTaken).count, mostOn)
    }

    // MARK: What the player picked

    /// The files and folders in FOLDER, by their paths in it.
    public static func items(inFolder folder: URL) throws -> [CartoucheModItem] {
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: folder.path])
        }
        var items: [CartoucheModItem] = []
        while let path = walker.nextObject() as? String {
            // The attributes the walk read, without reading them again.
            let attributes = walker.fileAttributes ?? [:]
            let type = attributes[.type] as? FileAttributeType
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            items.append(CartoucheModItem(path: path, size: size, isFolder: type == .typeDirectory,
                                          isLink: type == .typeSymbolicLink))
            guard items.count <= itemLimit else { throw CartoucheModProblem.unsafe(path) }
        }
        return items
    }

    /// What a Mac or a ZIP tool adds beside a mod's files, which no game
    /// reads: macOS's __MACOSX folder, ._ files and .DS_Store.
    static func isJunk(_ parts: [Substring]) -> Bool {
        parts.contains { $0 == "__MACOSX" || $0.hasPrefix("._") || $0 == ".DS_Store" }
    }

    /// The mods in ITEMS, what the player picked, named PICKNAME, in a
    /// folder named PARENTNAME: the romfs folders in it, each a mod, the
    /// outermost only, those of another game than TITLEIDS (the game's, its
    /// regions' too; none for a game Cartouche does not know) and those
    /// with code beside them refused. Picking a romfs folder itself takes
    /// it as the mod, named after its folder. Throws when no mod comes.
    public static func plan(_ items: [CartoucheModItem], pickName: String, parentName: String = "",
                            titleIds: [String]) throws -> (found: [CartoucheModFound], refused: [CartoucheModRefused]) {
        var files: [(parts: [Substring], size: UInt64)] = []
        var romfsFolders = Set<[Substring]>()
        for item in items {
            let parts = item.path.split(separator: "/", omittingEmptySubsequences: true)
            guard !item.path.hasPrefix("/"), !item.path.contains("\\"), !parts.isEmpty,
                  !parts.contains(where: { $0 == ".." || $0 == "." }) else { throw CartoucheModProblem.unsafe(item.path) }
            guard !isJunk(parts) else { continue }
            if let index = parts.firstIndex(where: { $0.lowercased() == romfsName }), index < parts.count - 1 || item.isFolder {
                romfsFolders.insert(Array(parts[...index]))
            }
            if item.isLink {
                // A mod's files are files: a link may point anywhere.
                throw CartoucheModProblem.unsafe(item.path)
            }
            if !item.isFolder { files.append((parts, item.size)) }
        }
        let picksRomfs = pickName.lowercased() == romfsName
        if picksRomfs {
            romfsFolders = [[]]
        }
        guard !romfsFolders.isEmpty else { throw CartoucheModProblem.noRomfs }
        let gameIds = Set(titleIds.compactMap(application))
        let ordered = romfsFolders.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
        var found: [CartoucheModFound] = []
        var refused: [CartoucheModRefused] = []
        for romfs in ordered {
            let parent = romfs.dropLast()
            let name: String
            if picksRomfs {
                name = parentName.isEmpty ? pickName : parentName
            } else if ordered.count == 1 {
                name = pickName
            } else {
                name = parent.last(where: { titleId(in: $0) == nil && !["contents", "atmosphere"].contains($0.lowercased()) })
                    .map(String.init) ?? pickName
            }
            let inside = files.filter { $0.parts.count > romfs.count && Array($0.parts.prefix(romfs.count)) == romfs }
            let code = files.contains { file in
                file.parts.count > parent.count + 1 && Array(file.parts.prefix(parent.count)) == Array(parent)
                    && file.parts[parent.count].lowercased() == exefsName
            }
            if let other = parent.compactMap(titleId(in:)).first, !gameIds.isEmpty,
               let id = application(other), !gameIds.contains(id) {
                refused.append(CartoucheModRefused(name: name, problem: .otherGame(other)))
            } else if code && !picksRomfs {
                refused.append(CartoucheModRefused(name: name, problem: .code))
            } else if inside.isEmpty {
                refused.append(CartoucheModRefused(name: name, problem: .empty))
            } else {
                found.append(CartoucheModFound(name: name, romfs: romfs.joined(separator: "/"), files: inside.count,
                                               size: inside.reduce(0) { $0 + $1.size }))
            }
        }
        if found.isEmpty, let first = refused.first { throw first.problem }
        return (found, refused)
    }

    /// The title ID a folder's name is, as Atmosphère names a game's folder
    /// in contents: 16 hexadecimal digits; in capitals.
    static func titleId(in name: Substring) -> String? {
        name.count == 16 && name.allSatisfy(\.isHexDigit) ? name.uppercased() : nil
    }

    /// The application a title ID belongs to: its program, its update and
    /// its other programs differ in the last three digits only.
    static func application(_ titleId: String) -> UInt64? {
        UInt64(titleId, radix: 16).map { $0 & ~0xFFF }
    }

    /// Reads URL, a folder or a ZIP archive the player picked, with access
    /// to it granted: the mods in it.
    public static func read(_ url: URL, titleIds: [String]) async throws -> CartoucheModPick {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let parentName = url.deletingLastPathComponent().lastPathComponent
        if isFolder.boolValue {
            let planned = try plan(try items(inFolder: url), pickName: url.lastPathComponent, parentName: parentName,
                                   titleIds: titleIds)
            return CartoucheModPick(url: url, isArchive: false, found: planned.found, refused: planned.refused)
        }
        let entries = try await CartoucheZip.entries(of: try CartoucheFileSource(url))
        let planned = try plan(entries.map(item), pickName: url.deletingPathExtension().lastPathComponent, parentName: parentName,
                               titleIds: titleIds)
        return CartoucheModPick(url: url, isArchive: true, found: planned.found, refused: planned.refused)
    }

    static func item(_ entry: CartoucheZipEntry) -> CartoucheModItem {
        CartoucheModItem(path: entry.name, size: entry.size, isFolder: entry.isDirectory, isLink: entry.isSymlink)
    }

    // MARK: Adding one

    /// A folder's name for a mod named NAME, in the game's mods folder,
    /// among TAKEN, the names there: without what a path or nxnative's line
    /// would cut it at, "/" and ":", nor a dot first, which hides it;
    /// " 2", " 3"… after it when the name is taken, in any letter case.
    static func folderName(for name: String, taken: [String]) -> String {
        var base = String(name.map { $0 == "/" || $0 == ":" || $0 == "\\" || $0.isNewline ? "-" : $0 })
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        base = String(base.prefix(64)).trimmingCharacters(in: .whitespaces)
        if base.isEmpty || base.lowercased() == listName { base = "Mod" }
        let used = Set(taken.map { $0.lowercased() })
        var candidate = base
        var number = 2
        while used.contains(candidate.lowercased()) {
            candidate = base + " " + String(number)
            number += 1
        }
        return candidate
    }

    /// Adds FOUND, of PICK, to the game's mods in DOCUMENTS, first in their
    /// order, turned on when it is the only one that came (ON), with the
    /// game's version, GAMEVERSION; access to the pick granted. Its files
    /// are copied, or unpacked, beside the game's mods first, then moved in
    /// at once: an add cut short leaves no half a mod.
    public static func add(_ found: [CartoucheModFound], of pick: CartoucheModPick, to documents: URL, on: Bool,
                           gameVersion: String?, now: Date = Date()) async throws -> [CartoucheMod] {
        let fileManager = FileManager.default
        let folder = folder(in: documents)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        // Gigabytes, which the player has elsewhere: out of iCloud, as the
        // games are (CartoucheBackup).
        CartoucheBackup.leaveOut([folder])
        #endif
        var mods = load(in: documents)
        var added: [CartoucheMod] = []
        let staging = folder.appendingPathComponent(".adding-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        var entries: [CartoucheZipEntry] = []
        let source: CartoucheFileSource? = pick.isArchive ? try CartoucheFileSource(pick.url) : nil
        if let source {
            entries = try await CartoucheZip.entries(of: source)
        }
        for (index, mod) in found.enumerated() {
            try Task.checkCancellation()
            let name = folderName(for: mod.name, taken: mods.map(\.folder) + added.map(\.folder))
            let made = staging.appendingPathComponent(String(index), isDirectory: true)
            let romfs = made.appendingPathComponent(romfsName, isDirectory: true)
            try fileManager.createDirectory(at: made, withIntermediateDirectories: true)
            if let source {
                let prefix = mod.romfs.split(separator: "/").map(String.init)
                let taken = entries.filter { entry in
                    let parts = entry.name.split(separator: "/", omittingEmptySubsequences: true)
                    return parts.count > prefix.count && parts.prefix(prefix.count).map(String.init) == prefix && !isJunk(parts)
                }
                let unpacked = made.appendingPathComponent("unpacked", isDirectory: true)
                try await CartoucheZip.extract(source, entries: taken, into: unpacked)
                let inside = prefix.isEmpty ? unpacked : unpacked.appendingPathComponent(prefix.joined(separator: "/"), isDirectory: true)
                try fileManager.moveItem(at: inside, to: romfs)
            } else {
                let inside = mod.romfs.isEmpty ? pick.url : pick.url.appendingPathComponent(mod.romfs, isDirectory: true)
                try fileManager.copyItem(at: inside, to: romfs)
                removeJunk(in: romfs)
            }
            try? fileManager.removeItem(at: made.appendingPathComponent("unpacked", isDirectory: true))
            try fileManager.moveItem(at: made, to: folder.appendingPathComponent(name, isDirectory: true))
            added.append(CartoucheMod(folder: name, name: mod.name, isOn: on, files: mod.files, size: mod.size,
                                      gameVersion: gameVersion, added: now))
        }
        // The newest first: it wins over the others.
        mods.insert(contentsOf: added, at: 0)
        try save(mods, in: documents)
        return added
    }

    /// Takes out of FOLDER what a Mac adds beside files: ._ files and
    /// .DS_Store, and __MACOSX folders.
    private static func removeJunk(in folder: URL) {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        var junk: [URL] = []
        for case let url as URL in walker where isJunk([Substring(url.lastPathComponent)]) {
            junk.append(url)
        }
        for url in junk {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Changing them

    /// Turns the mod in FOLDER on or off, in DOCUMENTS. Throws tooMany when
    /// mostOn are on already, or what stops it.
    @discardableResult
    public static func turn(_ folder: String, on: Bool, in documents: URL) throws -> [CartoucheMod] {
        var mods = load(in: documents)
        guard let index = mods.firstIndex(where: { $0.folder == folder }) else { return mods }
        if on {
            if let problem = mods[index].problem { throw problem }
            guard mods.filter(\.isTaken).count < mostOn else { throw CartoucheModsFull() }
        }
        mods[index].isOn = on
        try save(mods, in: documents)
        return mods
    }

    /// Moves the mod in FOLDER up the order (BY -1), where it wins over
    /// those under it, or down (+1).
    @discardableResult
    public static func move(_ folder: String, by offset: Int, in documents: URL) throws -> [CartoucheMod] {
        var mods = load(in: documents)
        guard let index = mods.firstIndex(where: { $0.folder == folder }) else { return mods }
        let target = min(max(index + offset, 0), mods.count - 1)
        guard target != index else { return mods }
        mods.insert(mods.remove(at: index), at: target)
        try save(mods, in: documents)
        return mods
    }

    /// Deletes the mod in FOLDER, its files with it.
    @discardableResult
    public static func delete(_ folder: String, in documents: URL) throws -> [CartoucheMod] {
        var mods = load(in: documents)
        guard let mod = mods.first(where: { $0.folder == folder }) else { return mods }
        try FileManager.default.removeItem(at: self.folder(in: documents).appendingPathComponent(mod.folder, isDirectory: true))
        mods.removeAll { $0.folder == folder }
        try save(mods, in: documents)
        return mods
    }
}

/// mostOn mods are on already.
public struct CartoucheModsFull: Error, Equatable {}

/// The line of a game's env.txt that names the mods it takes, which
/// nxnative reads before the game starts (dm/ios/Sources/main.m on the
/// iPhone, dm/mac/launcher.c on the Mac): Cartouche's, as the sheet's
/// mods set it. Every other line of the file stays.
public enum CartoucheModsLine {
    public static let key = "DM_ROMFS_OVERLAY"
    static let note = "# Cartouche: the mods turned on in the game's sheet, in their order."

    public static func write(_ value: String?, documents: URL) throws {
        let file = documents.appendingPathComponent("env.txt")
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var lines = old.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix(key + "=") && trimmed != note
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        if let value {
            lines += [note, key + "=" + value]
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        guard text != old else { return }
        if text.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// How many mods the game took, from the line nxnative writes in its log
    /// as it reads an env file: "boot: env DM_ROMFS_OVERLAY=<paths> (env.txt)"
    /// on the iPhone, "launcher: env DM_ROMFS_OVERLAY=<paths> (<file>)" on
    /// the Mac; nil for another line.
    static func count(inLogLine line: String) -> Int? {
        guard let start = line.range(of: " env " + key + "=") else { return nil }
        var value = line[start.upperBound...]
        if let source = value.range(of: " (", options: .backwards) { value = value[..<source.lowerBound] }
        let count = value.split(separator: ":", omittingEmptySubsequences: true).count
        return count > 0 ? count : nil
    }
}

private extension JSONEncoder {
    static var cartoucheMods: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var cartoucheMods: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
