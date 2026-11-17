//
//  ConsoleSaves.swift
//  Cartouche on the Mac
//
//  A game's saves on its sheet in Cartouche's console, the iPhone's screens
//  (CartoucheSavesView.swift, CartoucheSwitchSaveView.swift): when they were
//  last in step with the saves folder, what came and what was kept, Sync
//  now, the copies of the saves, one of which can be put back, and the
//  game's saves between the player's Switch and this Mac. The Builder keeps
//  them in step (MacSaves.swift and MacGames.swift in BuilderKit), before a
//  game, after it and every minute while it does not run, with the saves
//  folder of its iPhone page: the bridge's, or a NAS's share mounted on
//  this Mac; or with the one the player chose on the iPhone, on one of
//  their connections, by the iPhone's code (ConsoleConnectionSaves.swift),
//  which the Storage page then shows as the iPhone shows it. This stand-in
//  of the iPhone's CartoucheSaveBackups shows what
//  the app tells it (CartoucheMacConsole.showSaves), and asks the app for
//  the rest: a sync now, the copies, a copy put back, a save from the
//  Switch put in place or the one it replaced put back, each in the
//  Builder's turn, never at once with a sync of the game.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: What the app tells

/// A game's saves on this Mac, as the Builder keeps them in step with the
/// saves folder.
public struct CartoucheMacGameSaves: Equatable, Sendable {
    /// When they were last in step with the saves folder.
    public var lastSync: Date?
    /// When the saves that came last were written, and those of this Mac
    /// kept as a copy under newer ones, when the last sync did that.
    public var fetched: Date?
    public var kept: Date?
    /// Whether they wait for the saves folder, which was not there, as a
    /// NAS's share not mounted.
    public var waiting: Bool
    /// What went wrong with the last sync, in the Builder's words.
    public var failure: String?
    /// Whether nxnative's own cloud saves keep them, chosen in the game's
    /// settings: the Builder leaves them alone.
    public var inCloud: Bool
    /// The version of the game the newest copy names, newer than this Mac's
    /// app, GAME: the copy waits for the game's update, and the saves played
    /// here go to the saves folder as a copy of their own meanwhile.
    public var newer: String?
    public var game: String?

    public init(lastSync: Date? = nil, fetched: Date? = nil, kept: Date? = nil, waiting: Bool = false,
                failure: String? = nil, inCloud: Bool = false, newer: String? = nil, game: String? = nil) {
        self.lastSync = lastSync
        self.fetched = fetched
        self.kept = kept
        self.waiting = waiting
        self.failure = failure
        self.inCloud = inCloud
        self.newer = newer
        self.game = game
    }
}

/// The saves folder, as a game's sheet names it.
public struct CartoucheMacSavesFolder: Equatable, Sendable {
    /// Its name in a sentence: "the NAS", "the saves folder".
    public var name: String
    public var path: String
    /// Whether it was not there when the Builder last tried it.
    public var isAway: Bool
    /// The connection it is on, the iPhone's saves folder: nil for a folder
    /// of this Mac's.
    public var connection: UUID?

    public init(name: String, path: String, isAway: Bool = false, connection: UUID? = nil) {
        self.name = name
        self.path = path
        self.isAway = isAway
        self.connection = connection
    }
}

/// A copy of a game's saves in the saves folder.
public struct CartoucheMacSaveCopy: Equatable, Sendable {
    /// Its name there, which says when its saves were written.
    public let name: String
    public let date: Date
    public let size: UInt64

    public init(name: String, date: Date, size: UInt64) {
        self.name = name
        self.date = date
        self.size = size
    }
}

/// Why the Builder did not do what the console asked of a game's saves.
public enum CartoucheMacSaveError: Error, Equatable {
    /// The game plays, or starts: its saves are its own meanwhile.
    case busy
    /// The saves folder is not there.
    case offline
    /// The copy does not read whole, or holds more than a game's saves.
    case unreadable
    /// A newer version of the game wrote the copy, COPY, than this Mac's
    /// app, GAME: it stays where it is.
    case newerGame(copy: String, game: String)
}

extension CartoucheMacSaveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .busy: return CartoucheText.savesRunning
        case .offline: return CartoucheText.savesWaitingHere
        case .unreadable: return CartoucheText.savesCopyUnreadable
        case .newerGame(let copy, let game): return CartoucheText.savesPutBackNewer(copy, game)
        }
    }
}

/// A page a game's sheet opens beside the console, for the app's gallery.
public enum CartoucheMacSavesPage: Sendable {
    /// The copies of its saves, one of which can be put back.
    case copies
    /// Its saves between the player's Switch and this Mac.
    case switchSaves
    /// What the game wrote of its last sessions, to share
    /// (CartoucheGameLogView).
    case log
}

extension CartoucheMacConsole {
    /// Keeps the saves of the game of that title ID in step now, as the
    /// player asks on its sheet: it throws CartoucheMacSaveError for what
    /// kept them from it.
    public var onSyncSaves: (_ titleID: String) async throws -> Void {
        get { CartoucheSaveBackups.shared.onSync }
        set { CartoucheSaveBackups.shared.onSync = newValue }
    }

    /// The copies of the game's saves in the saves folder.
    public var onSaveCopies: (_ titleID: String) async throws -> [CartoucheMacSaveCopy] {
        get { CartoucheSaveBackups.shared.onCopies }
        set { CartoucheSaveBackups.shared.onCopies = newValue }
    }

    /// Puts the copy of that name back as the game's saves on this Mac:
    /// this Mac's go to the saves folder first, and the copy put back
    /// becomes the newest one there.
    public var onPutBackSave: (_ name: String, _ titleID: String) async throws -> Void {
        get { CartoucheSaveBackups.shared.onPutBack }
        set { CartoucheSaveBackups.shared.onPutBack = newValue }
    }

    /// Runs CHANGE on the game's saves on this Mac, once no sync of them is
    /// under way, none starting meanwhile, then has them go to the saves
    /// folder: a save from the Switch put in place, or the one it replaced
    /// put back. What CHANGE gives, or throws.
    public var onChangeSaves: (_ titleID: String, _ change: @escaping @Sendable () throws -> URL?) async throws -> URL? {
        get { CartoucheSaveBackups.shared.onChange }
        set { CartoucheSaveBackups.shared.onChange = newValue }
    }

    /// The saves folder, nil while the Builder keeps no saves in step, and
    /// the saves of the games, by title ID, as their sheets show them.
    public func showSaves(folder: CartoucheMacSavesFolder?, games: [String: CartoucheMacGameSaves]) {
        CartoucheSaveBackups.shared.show(folder: folder, games: games)
    }
}

// MARK: The stand-in

/// What a sync did to a game's saves that the player should know.
struct CartoucheSaveNews: Codable, Hashable {
    /// The date of the copy that came here.
    var fetched: Date?
    /// The date of the copy the saves here were kept as, under a newer one.
    var kept: Date?
}

/// The games' saves on this Mac, under the names of the iPhone's
/// (CartoucheSaveBackups.swift), by target key: the game's title ID
/// (CartoucheGameActions.saves(of:)).
@MainActor
final class CartoucheSaveBackups: ObservableObject {
    static let shared = CartoucheSaveBackups()
    /// The copies kept for each game.
    nonisolated static let kept = CartoucheSaveSync.kept

    /// Whether the player's sync or copy put back is under way.
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: [String: Date] = [:]
    @Published private(set) var news: [String: CartoucheSaveNews] = [:]
    /// The games whose newest copy waits for the game's update, a newer
    /// version of it having written it.
    @Published private(set) var newer: [String: CartoucheSaveNewer] = [:]
    @Published private(set) var waiting: Set<String> = []
    /// The games whose saves nxnative's own cloud saves keep.
    @Published private(set) var inCloud: Set<String> = []
    /// What went wrong with each game's last sync, and the report on it.
    @Published private(set) var problems: [String: CartoucheReport] = [:]
    private var failures: [String: String] = [:]

    var onSync: (String) async throws -> Void = { _ in throw CartoucheMacSaveError.offline }
    var onCopies: (String) async throws -> [CartoucheMacSaveCopy] = { _ in [] }
    var onPutBack: (String, String) async throws -> Void = { _, _ in throw CartoucheMacSaveError.offline }
    var onChange: (String, @escaping @Sendable () throws -> URL?) async throws -> URL? = { _, change in try change() }

    private let settings = CartoucheStorageSettings.shared

    /// Whether the Builder keeps the saves in step with a saves folder.
    var isOn: Bool { settings.location(.saves) != nil }

    /// The target key of the saves of the game of TITLEID.
    nonisolated static func key(_ titleID: String) -> String {
        titleID.uppercased()
    }

    func problem(of target: CartoucheSaveTarget) -> CartoucheReport? {
        problems[target.key]
    }

    /// Why the last sync failed, and the report on it, as the Storage page
    /// says it under the saves folder: on the Mac, where each game's saves
    /// go on their own, the newest of the games' failures.
    var problemReport: CartoucheReport? {
        problems.values.max { $0.date < $1.date }
    }

    /// Whether nxnative's own cloud saves keep TARGET's saves, chosen in
    /// the game's settings: the Builder leaves them alone.
    func isLeftToCloud(_ target: CartoucheSaveTarget) -> Bool {
        inCloud.contains(target.key)
    }

    func show(folder: CartoucheMacSavesFolder?, games: [String: CartoucheMacGameSaves]) {
        settings.showMacSaves(name: folder?.name, path: folder?.path ?? "", connection: folder?.connection)
        if let folder, let server = settings.location(.saves)?.server {
            if folder.isAway {
                CartoucheStorageReach.shared.noteOffline(server)
            } else {
                CartoucheStorageReach.shared.noteAnswered(server)
            }
        }
        var lastSync: [String: Date] = [:]
        var news: [String: CartoucheSaveNews] = [:]
        var newer: [String: CartoucheSaveNewer] = [:]
        var waiting: Set<String> = []
        var inCloud: Set<String> = []
        var failures: [String: String] = [:]
        for (titleID, saves) in games {
            let key = Self.key(titleID)
            if let date = saves.lastSync { lastSync[key] = date }
            if saves.fetched != nil || saves.kept != nil {
                news[key] = CartoucheSaveNews(fetched: saves.fetched, kept: saves.kept)
            }
            if let copy = saves.newer { newer[key] = CartoucheSaveNewer(copy: copy, game: saves.game ?? "") }
            if saves.waiting { waiting.insert(key) }
            if saves.inCloud { inCloud.insert(key) }
            if let failure = saves.failure { failures[key] = failure }
        }
        if lastSync != self.lastSync { self.lastSync = lastSync }
        if news != self.news { self.news = news }
        if newer != self.newer { self.newer = newer }
        if waiting != self.waiting { self.waiting = waiting }
        if inCloud != self.inCloud { self.inCloud = inCloud }
        guard failures != self.failures else { return }
        // A report of each failure, made once: its journal line too.
        var problems: [String: CartoucheReport] = [:]
        for (key, failure) in failures {
            if self.failures[key] == failure, let known = self.problems[key] {
                problems[key] = known
            } else {
                problems[key] = CartoucheReports.make(.saves, CartoucheText.savesCopyFailed, message: failure,
                                                      step: "Keeping a game's saves in step, in " + CartoucheReports.place(.saves),
                                                      stage: "savesSync")
            }
        }
        self.failures = failures
        self.problems = problems
    }

    /// Keeps TARGET's saves in step now, as the player asked: whether it
    /// went through. What it did, the app tells (show).
    func syncNow(_ target: CartoucheSaveTarget) async -> Bool {
        guard let titleID = target.titleId, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await onSync(titleID)
            return true
        } catch {
            if error as? CartoucheMacSaveError == .offline { _ = away() }
            CartoucheReports.note("Saves of " + target.name + " not synced now: " + String(describing: error))
            return false
        }
    }

    /// TARGET's copies in the saves folder, the newest first.
    func copies(of target: CartoucheSaveTarget) async throws -> [CartoucheSaveBackup] {
        guard let titleID = target.titleId, isOn else { return [] }
        do {
            let copies = try await onCopies(titleID)
            there()
            return copies.map { CartoucheSaveBackup(path: $0.name, date: $0.date, size: $0.size) }
        } catch CartoucheMacSaveError.offline {
            throw away()
        }
    }

    /// Puts BACKUP back as TARGET's saves, as the player chose it: the
    /// Builder sends this Mac's to the saves folder first, and the copy
    /// put back becomes the newest one there, which the player's other
    /// devices take.
    func restore(_ backup: CartoucheSaveBackup, of target: CartoucheSaveTarget) async throws {
        guard let titleID = target.titleId else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await onPutBack(backup.path, titleID)
        } catch CartoucheMacSaveError.offline {
            throw away()
        } catch CartoucheMacSaveError.newerGame(let copy, let game) {
            // As the iPhone says it.
            throw CartoucheSaveNewerGame(copy: copy, game: game)
        }
        there()
        // The player put it back: no news to tell of it.
        news[target.key] = nil
    }

    // MARK: A save from the Switch

    /// Puts the save from the player's Switch that STAGED holds in place of
    /// TARGET's, in the Builder's turn, as the iPhone's does: the saves it
    /// replaces are kept on this Mac first, and it goes to the saves folder
    /// as the newest copy. The backup of the saves it replaced, nil when
    /// there were none.
    func bringIn(_ staged: URL, of target: CartoucheSaveTarget, running: @escaping @MainActor () -> Bool) async throws -> URL? {
        if running() { throw CartoucheSwitchSaveProblem.running }
        let documents = target.documents
        let backup = try await changing(target) { try CartoucheSwitchSave.place(staged, in: documents) }
        news[target.key] = nil
        return backup
    }

    /// Puts BACKUP, the saves an import replaced, back in place of TARGET's,
    /// the same way.
    func putBack(beforeImport backup: CartoucheSwitchSaveBackup, of target: CartoucheSaveTarget,
                 running: @escaping @MainActor () -> Bool) async throws {
        if running() { throw CartoucheSwitchSaveProblem.running }
        let documents = target.documents
        let folder = backup.folder
        _ = try await changing(target) {
            try CartoucheSwitchSave.putBack(folder, in: documents)
            return nil
        }
    }

    private func changing(_ target: CartoucheSaveTarget, _ change: @escaping @Sendable () throws -> URL?) async throws -> URL? {
        guard let titleID = target.titleId else { throw CartoucheSwitchSaveProblem.notAGame }
        do {
            return try await onChange(titleID, change)
        } catch CartoucheMacSaveError.busy {
            throw CartoucheSwitchSaveProblem.running
        }
    }

    // MARK: The saves folder away

    /// The saves folder is not there: what the player reads of it.
    private func away() -> Error {
        guard let server = settings.location(.saves)?.server else { return CartoucheMacSaveError.offline }
        CartoucheStorageReach.shared.noteOffline(server)
        return CartoucheStorageOffline(server)
    }

    /// The saves folder is there again.
    private func there() {
        guard let server = settings.location(.saves)?.server else { return }
        CartoucheStorageReach.shared.noteAnswered(server)
    }
}

// MARK: The pages a game's sheet opens

extension View {
    /// A page a game's sheet opens beside the console, the copies of its
    /// saves or its Switch saves: its title, and the way back to the sheet
    /// above it, which Escape takes too, as the settings page has them
    /// (ConsoleView.swift), rather than in the window's toolbar, which the
    /// console's two stacks share. A page the console's home opens, as
    /// System, says where its way back goes: BACK.
    func cartoucheConsolePage(_ title: String, back: String = CartoucheText.backToSheet) -> some View {
        modifier(CartoucheConsolePage(title: title, backTitle: back))
    }
}

private struct CartoucheConsolePage: ViewModifier {
    let title: String
    let backTitle: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                CartoucheConsoleBar(title: title, back: { dismiss() }, backTitle: backTitle)
            }
    }
}

/// The bar above a page beside the console: its title, and the way back to
/// the game's sheet, or BACKTITLE's page, which Escape takes too.
struct CartoucheConsoleBar: View {
    let title: String
    let back: () -> Void
    var backTitle = CartoucheText.backToSheet

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Button(action: back) {
                    Label(backTitle, systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
    }
}

/// Saves FILE where the player chooses, as on the microSD card in the
/// Mac's card reader, where the iPhone shares it: the ZIP JKSV restores on
/// the Switch. A file of that name there goes to the Trash first, once the
/// save panel has asked.
struct CartoucheSaveFileButton: View {
    let file: URL
    /// The folder it was saved in last.
    @State private var savedIn: String?
    @State private var failure: String?

    var body: some View {
        Button(action: save) {
            Label(CartoucheText.macSaveFile(file.lastPathComponent), systemImage: "square.and.arrow.down")
        }
        if let savedIn {
            Label(CartoucheText.macFileSaved(savedIn), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.green)
        }
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.orange)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        failure = nil
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: file, to: url)
            savedIn = fileManager.displayName(atPath: url.deletingLastPathComponent().path)
            CartoucheReports.note("A save's ZIP for JKSV saved by the player")
        } catch {
            savedIn = nil
            failure = error.localizedDescription
        }
    }
}

// MARK: The Mac's own words

extension CartoucheText {
    /// A game whose saves nxnative's own cloud saves keep, which the
    /// Builder leaves to it, as its page in the Builder says.
    static var savesInCloud: String {
        s("mac.saves.cloud", "Its saves go through nxnative’s own cloud saves, chosen in its settings: Cartouche Builder leaves them to it.")
    }

    static func macSaveFile(_ name: String) -> String { f("mac.file.save", "Save %@…", name) }
    static func macFileSaved(_ folder: String) -> String { f("mac.file.saved", "Saved in %@.", folder) }
}
