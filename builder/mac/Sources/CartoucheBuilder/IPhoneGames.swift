//
//  IPhoneGames.swift
//  Cartouche Builder
//
//  The games folder the player chose on the iPhone, on one of their
//  connections, as the iPhone told this Mac (CartoucheChosenFolders): the
//  Builder sends its games there, the IPAs and the Mac apps of its games
//  folder, and Cartouche's console installs from there the Mac apps another
//  Mac sent (BuilderKit's ConnectionGames.swift). The console reaches the
//  folder by the iPhone's code (CartoucheMacConnectionGames). A round goes
//  after a reading of the library that changed it, or five minutes after
//  the last, and every half hour, never during a batch, the newest builds
//  first, one file at a time; a batch that starts lets the file going end
//  and stops the round. A round also makes this Mac's copy of an app
//  installed from there again of a newer file there, unless the game runs.
//

import BuilderKit
import CartoucheConsole
import Foundation

/// The console's games folder on a connection, as BuilderKit drives it.
final class ConsoleConnectionGames: ConnectionGamesDriver, @unchecked Sendable {
    let folder: CartoucheMacConnectionGames

    init(connection: UUID, path: String) {
        folder = CartoucheMacConnectionGames(connection: connection, path: path)
    }

    var connection: UUID { folder.connection }
    var path: String { folder.path }

    func files() async throws -> [ConnectionFile] {
        try await Self.mapped {
            try await self.folder.files().map { ConnectionFile(name: $0.name, size: $0.size, modified: $0.modified) }
        }
    }

    func room() async throws -> UInt64? {
        try await Self.mapped { try await self.folder.room() }
    }

    func canWrite() async throws -> Bool {
        try await Self.mapped { try await self.folder.canWrite() }
    }

    func send(_ file: URL, as name: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        try await Self.mapped { try await self.folder.send(file, as: name, progress: progress) }
    }

    func fetch(_ name: String, to file: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        try await Self.mapped { try await self.folder.fetch(name, to: file, progress: progress) }
    }

    /// What the console could not reach is the Builder's to tell apart.
    private static func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch CartoucheMacGamesError.offline {
            throw ConnectionGamesError.offline
        }
    }
}

/// The Builder's games in the iPhone's games folder, on a connection.
@MainActor
final class IPhoneGames: ObservableObject {
    /// The folder as the iPhone told it, on the connection it is on now.
    struct Folder: Equatable {
        var connection: UUID
        var path: String
    }

    @Published private(set) var folder: Folder?
    /// The file going, or coming, now.
    @Published private(set) var progress: ConnectionGamesProgress?
    /// Why the last round stopped before its end, if it did.
    @Published private(set) var stopped: ConnectionGamesError?
    @Published private(set) var failure: String?
    @Published private(set) var lastRound: Date?
    /// How many of the Builder's files went, as the last round found, of
    /// how many it has.
    @Published private(set) var sentCount = 0
    @Published private(set) var total = 0
    /// What is due still.
    @Published private(set) var left = 0
    /// The Mac apps another Mac sent there, of games this Mac has no app of.
    @Published private(set) var offers: [ConnectionMacApp] = []

    let store: ConnectionGamesStore
    private let scratch: URL
    private var sender: ConnectionGamesSender?
    private var running: Task<Void, Never>?
    /// Which round runs, so that one stopped says nothing once it ends.
    private var runningID = UUID()
    private var again = false
    private var timer: Task<Void, Never>?
    /// What the app gives a round: the library's games, whether a batch
    /// runs, the engine, and what to say of what went or came.
    private weak var model: AppModel?
    /// The library's games as the last reading gave them.
    private var readGames: [Game]?
    /// How long between two rounds, in seconds.
    static let interval: TimeInterval = 30 * 60
    /// How long a reading of the library that changed nothing waits for a
    /// round since the last one, in seconds: the player coming back to the
    /// app reads it again.
    static let quiet: TimeInterval = 5 * 60

    init(store: ConnectionGamesStore, scratch: URL) {
        self.store = store
        self.scratch = scratch
    }

    /// From now on, for MODEL: a round every half hour.
    func start(for model: AppModel) {
        self.model = model
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
                guard let self else { return }
                self.round()
            }
        }
    }

    /// The iPhone's games folder, FOLDER, or none: a round in it at once
    /// when it is another.
    func use(_ folder: Folder?) {
        guard folder != self.folder || (folder != nil && sender == nil) else { return }
        running?.cancel()
        running = nil
        self.folder = folder
        progress = nil
        stopped = nil
        failure = nil
        offers = []
        sentCount = 0
        total = 0
        left = 0
        lastRound = nil
        guard let folder, model != nil else {
            sender = nil
            return
        }
        sender = ConnectionGamesSender(driver: ConsoleConnectionGames(connection: folder.connection, path: folder.path), store: store) { [weak self] game in
            guard let self else { throw CancellationError() }
            return try await self.pack(game)
        }
        round()
    }

    /// GAME's Mac app, as the games folder keeps it, packed by the engine
    /// in one file of the Builder's scratch folder.
    private func pack(_ game: GameToSend) async throws -> URL {
        guard let engine = model?.engine else { throw CocoaError(.featureUnsupported) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return URL(fileURLWithPath: try await engine.packMac(game.titleID, into: scratch).file.path)
    }

    /// The Mac app another Mac sent there of TITLE_ID's game, if any.
    func offer(_ titleID: String) -> ConnectionMacApp? {
        offers.first { $0.titleID == titleID.uppercased() }
    }

    /// The Mac apps installed from the folder in use, still on this Mac.
    var fetchedApps: [FetchedApp] {
        guard let sender else { return [] }
        let place = sender.driver.place
        return store.fetched.values.filter { $0.place == place && FileManager.default.fileExists(atPath: $0.app) }
            .sorted { $0.titleID < $1.titleID }
    }

    // MARK: Rounds

    /// After each reading of the library: a round when its GAMES changed,
    /// or the last round is a while ago.
    func libraryRead(_ games: [Game]) {
        if games == readGames, let lastRound, Date().timeIntervalSince(lastRound) < Self.quiet { return }
        readGames = games
        round()
    }

    /// A round, now unless one runs, or once it ends; none during a batch.
    func round() {
        guard sender != nil, let model, !model.sample else { return }
        guard running == nil else {
            again = true
            return
        }
        guard !model.isBuilding else { return }
        let id = UUID()
        runningID = id
        running = Task { [weak self] in
            repeat {
                self?.again = false
                await self?.roundOnce()
            } while self?.again == true && !Task.isCancelled
            if self?.runningID == id { self?.running = nil }
        }
    }

    private func roundOnce() async {
        guard let sender, let model else { return }
        let local = await Self.files(of: model.library?.games ?? [])
        let report = await sender.send(local, progress: { [weak self] progress in
            Task { @MainActor in
                // None from a round stopped since.
                guard let self, sender === self.sender else { return }
                self.progress = progress
            }
        }, stop: { [weak self] in await self?.stops() ?? true })
        guard !Task.isCancelled, sender === self.sender else { return }
        progress = nil
        lastRound = Date()
        stopped = report.stopped
        failure = report.failure
        left = report.left
        let server = folder.flatMap { ConsoleLink.connectionKind($0.connection) }
        for went in report.sent {
            model.telemetry.event("builder.sent", game: went.game.titleID,
                                  fields: BuilderTelemetry.sentFields(kind: went.game.kind == .ipa ? "ipa" : "mac", bytes: went.bytes,
                                                                      seconds: went.seconds, packed: went.game.kind == .macApp,
                                                                      server: server))
        }
        total = local.count
        if let files = report.files {
            sentCount = local.filter { game in
                files.contains { $0.name == (game.fileName ?? "") } || store.sent(to: sender.driver.place)[game.sentKey]?.build == game.build
            }.count
            offers = ConnectionGames.macApps(in: files, known: model.macTitleIDs())
            await makeAgain(from: files)
        }
        model.showConsoleGames()
    }

    /// The apps installed from the folder, made again of a newer file
    /// there, but while their game runs, or once this Mac builds the game
    /// itself, and none during a batch.
    private func makeAgain(from files: [ConnectionFile]) async {
        guard let model else { return }
        let own = Set((model.library?.games ?? []).filter { $0.mac?.kept == true || $0.mac?.build != nil }.map { $0.titleID.uppercased() })
        for fetched in fetchedApps where !own.contains(fetched.titleID) {
            guard !Task.isCancelled, !model.isBuilding else { return }
            guard let newer = ConnectionGames.newer(for: fetched, in: files), !model.macGames.isPlaying(fetched.titleID) else { continue }
            do {
                try await install(newer, again: true)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Installs APP on this Mac: its file fetched into the Builder's folder,
    /// then installed by the engine, how far each is said on the console.
    func install(_ app: ConnectionMacApp, again: Bool = false) async throws {
        guard let sender, let model, let engine = model.engine else { return }
        let place = folder.flatMap { ConsoleLink.connectionName($0.connection) } ?? tr("the iPhone’s games folder", "le dossier des jeux de l’iPhone")
        let server = folder.flatMap { ConsoleLink.connectionKind($0.connection) }
        let total = app.file.size
        let began = Date()
        try await model.runInstall(of: app.titleID, name: app.game) { say in
            say(tr("Fetching from \(place)…", "Téléchargement depuis \(place)…"))
            let file = try await sender.fetch(app, into: self.scratch) { done in
                say(tr("Fetching from \(place): \(Format.size(done)) of \(Format.size(total))",
                       "Téléchargement depuis \(place) : \(Format.size(done)) sur \(Format.size(total))"))
            }
            defer { try? FileManager.default.removeItem(at: file) }
            let answer = try await engine.installMac(app.titleID, from: file) { line in say(line) }
            sender.installed(app, at: answer.app.path)
            model.telemetry.event("builder.macInstalled", game: answer.titleID,
                                  fields: BuilderTelemetry.installedFields(bytes: answer.bytes, seconds: Date().timeIntervalSince(began), again: again,
                                                                           server: server ?? "other"))
        }
        offers.removeAll { $0.titleID == app.titleID }
        model.useMacApps()
        model.showConsoleGames()
    }

    /// The gallery's: the iPhone's games folder FOLDER, the file going,
    /// how many went, of TOTAL, and the Mac apps another Mac sent there, as
    /// a round CHECKED them; nothing looked at.
    func preview(folder: Folder, progress: ConnectionGamesProgress?, sent: Int, total: Int, offers: [ConnectionMacApp], checked: Date) {
        guard model == nil else { return }
        self.folder = folder
        self.progress = progress
        sentCount = sent
        self.total = total
        self.offers = offers
        lastRound = checked
    }

    /// The files of the library's GAMES that go, read aside: a games
    /// folder on a NAS answers slowly.
    private nonisolated static func files(of games: [Game]) async -> [GameToSend] {
        ConnectionGames.toSend(games)
    }

    /// The round stops before its next file: it was stopped, or a batch
    /// started.
    private func stops() -> Bool {
        Task.isCancelled || model?.isBuilding != false
    }
}
