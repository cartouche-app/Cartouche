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
//  The other games folders the iPhone reads, a round looks at too, for the
//  Mac apps another Mac sent there: a game in several is offered once, from
//  one that answers (ConnectionGames.macApps), and installs from the next
//  when that one does not.
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
    /// The other games folders the iPhone reads, in their order: whether
    /// each answered the last look, and the Mac apps offered from it.
    struct Other: Equatable {
        var folder: Folder
        var offline = false
        var offers = 0
    }
    @Published private(set) var others: [Other] = []
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
    /// The other games folders, which nothing goes to.
    private var readers: [ConnectionGamesSender] = []
    /// What each folder held at its last look, by its place.
    private var looked: [String: [ConnectionFile]] = [:]
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

    /// The iPhone's games folder, FOLDER, or none, and the OTHERS it reads:
    /// a round in them at once when they are others.
    func use(_ folder: Folder?, others: [Folder] = []) {
        let others = others.filter { $0 != folder }
        guard folder != self.folder || others != self.others.map(\.folder)
            || (folder != nil && sender == nil) || readers.count != others.count else { return }
        running?.cancel()
        running = nil
        self.folder = folder
        self.others = others.map { Other(folder: $0) }
        progress = nil
        stopped = nil
        failure = nil
        offers = []
        looked = [:]
        sentCount = 0
        total = 0
        left = 0
        lastRound = nil
        guard model != nil else {
            sender = nil
            readers = []
            return
        }
        sender = folder.map { folder in
            ConnectionGamesSender(driver: ConsoleConnectionGames(connection: folder.connection, path: folder.path), store: store) { [weak self] game in
                guard let self else { throw CancellationError() }
                return try await self.pack(game)
            }
        }
        // Nothing is packed for them: nothing goes there.
        readers = others.map { other in
            ConnectionGamesSender(driver: ConsoleConnectionGames(connection: other.connection, path: other.path), store: store) { _ in
                throw CancellationError()
            }
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

    /// The Mac apps installed from the folders in use, still on this Mac.
    var fetchedApps: [FetchedApp] {
        let places = Set(folders.map(\.driver.place))
        return store.fetched.values.filter { places.contains($0.place) && FileManager.default.fileExists(atPath: $0.app) }
            .sorted { $0.titleID < $1.titleID }
    }

    /// The folders in use, the iPhone's games folder first.
    private var folders: [ConnectionGamesSender] {
        (sender.map { [$0] } ?? []) + readers
    }

    /// The folders as their last looks found them, in their order.
    private var looks: [ConnectionGamesLook] {
        var looks: [ConnectionGamesLook] = []
        if let sender {
            looks.append(ConnectionGamesLook(place: sender.driver.place, files: looked[sender.driver.place] ?? [],
                                             answered: stopped != .offline))
        }
        for (reader, other) in zip(readers, others) {
            looks.append(ConnectionGamesLook(place: reader.driver.place, files: looked[reader.driver.place] ?? [],
                                             answered: !other.offline))
        }
        return looks
    }

    /// Where OFFERS are, in the player's words: their folder's connection,
    /// or the iPhone's games folders, of offers in several.
    func placeName(of offers: [ConnectionMacApp]) -> String {
        let folders = self.folders
        var connections: [UUID] = []
        for offer in offers {
            guard let connection = folders.first(where: { $0.driver.place == offer.place })?.driver.connection,
                  !connections.contains(connection) else { continue }
            connections.append(connection)
        }
        if connections.count > 1 { return tr("your games folders", "vos dossiers de jeux", "tus carpetas de juegos", "deine Spieleordner") }
        return (connections.first ?? folder?.connection).flatMap { ConsoleLink.connectionName($0) }
            ?? tr("the iPhone’s games folder", "le dossier des jeux de l’iPhone", "la carpeta de juegos del iPhone", "der Spieleordner des iPhones")
    }

    /// The Mac apps offered from the iPhone's games folder, the first.
    var offersInFirst: Int {
        offers.count - others.reduce(0) { $0 + $1.offers }
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
        guard !folders.isEmpty, let model, !model.sample else { return }
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
        guard let model else { return }
        let sender = self.sender
        let readers = self.readers
        if let sender {
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
                looked[sender.driver.place] = files
            }
        }
        // The other folders, for the Mac apps another Mac sent there.
        for (index, reader) in readers.enumerated() {
            let files = try? await reader.driver.files()
            guard !Task.isCancelled, readers.map(\.driver.place) == self.readers.map(\.driver.place), index < others.count else { return }
            others[index].offline = files == nil
            if let files { looked[reader.driver.place] = files }
        }
        // None from folders changed since.
        guard !Task.isCancelled, sender === self.sender, readers.map(\.driver.place) == self.readers.map(\.driver.place),
              readers.count == others.count else { return }
        lastRound = Date()
        let looks = self.looks
        offers = ConnectionGames.macApps(in: looks, known: model.macTitleIDs())
        for index in others.indices {
            let place = readers[index].driver.place
            others[index].offers = offers.filter { $0.place == place }.count
        }
        await makeAgain(from: looks.filter(\.answered))
        model.showConsoleGames()
    }

    /// The apps installed from the folders, made again of a newer file
    /// there, in the folder each came from, but while their game runs, or
    /// once this Mac builds the game itself, and none during a batch.
    private func makeAgain(from looks: [ConnectionGamesLook]) async {
        guard let model else { return }
        let own = Set((model.library?.games ?? []).filter { $0.mac?.kept == true || $0.mac?.build != nil }.map { $0.titleID.uppercased() })
        for fetched in fetchedApps where !own.contains(fetched.titleID) {
            guard !Task.isCancelled, !model.isBuilding else { return }
            guard let look = looks.first(where: { $0.place == fetched.place }),
                  var newer = ConnectionGames.newer(for: fetched, in: look.files),
                  !model.macGames.isPlaying(fetched.titleID) else { continue }
            newer.place = look.place
            do {
                try await install(newer, again: true)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Where APP's copies are to fetch, APP's first, then the others in
    /// the order to try them: each with the folder it is in.
    private func copies(of app: ConnectionMacApp) -> [(app: ConnectionMacApp, folder: ConnectionGamesSender)] {
        let folders = self.folders
        let others = ConnectionGames.copies(of: app.titleID, in: looks).filter { $0.place != app.place }
        return ([app] + others).compactMap { copy in
            let folder = copy.place.isEmpty ? folders.first : folders.first(where: { $0.driver.place == copy.place })
            return folder.map { (copy, $0) }
        }
    }

    /// Installs APP on this Mac: its file fetched into the Builder's folder,
    /// from the folder it is in, or the next one with the game when that
    /// one does not answer, then installed by the engine, how far each is
    /// said on the console.
    func install(_ app: ConnectionMacApp, again: Bool = false) async throws {
        guard let model, let engine = model.engine else { return }
        let copies = self.copies(of: app)
        guard !copies.isEmpty else { return }
        let began = Date()
        let scratch = self.scratch
        try await model.runInstall(of: app.titleID, name: app.game) { say in
            var fetched: URL?
            var installed: (app: ConnectionMacApp, folder: ConnectionGamesSender)?
            for (index, copy) in copies.enumerated() {
                let connection = copy.folder.driver.connection
                let place = ConsoleLink.connectionName(connection) ?? tr("the iPhone’s games folder", "le dossier des jeux de l’iPhone", "la carpeta de juegos del iPhone", "der Spieleordner des iPhones")
                let total = copy.app.file.size
                say(tr("Fetching from \(place)…", "Téléchargement depuis \(place)…", "Descargando desde \(place)…", "Wird von \(place) geladen …"))
                do {
                    fetched = try await copy.folder.fetch(copy.app, into: scratch) { done in
                        say(tr("Fetching from \(place): \(Format.size(done)) of \(Format.size(total))",
                               "Téléchargement depuis \(place) : \(Format.size(done)) sur \(Format.size(total))",
                               "Descargando desde \(place): \(Format.size(done)) de \(Format.size(total))",
                               "Wird von \(place) geladen: \(Format.size(done)) von \(Format.size(total))"))
                    }
                } catch ConnectionGamesError.offline where index < copies.count - 1 {
                    // Its server does not answer from here: the next
                    // folder with the game may.
                    continue
                }
                installed = copy
                break
            }
            guard let file = fetched, let copy = installed else { throw ConnectionGamesError.offline }
            defer { try? FileManager.default.removeItem(at: file) }
            let answer = try await engine.installMac(copy.app.titleID, from: file) { line in say(line) }
            copy.folder.installed(copy.app, at: answer.app.path)
            let server = ConsoleLink.connectionKind(copy.folder.driver.connection)
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
