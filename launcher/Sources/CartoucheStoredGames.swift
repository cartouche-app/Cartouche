//
//  CartoucheStoredGames.swift
//  Cartouche
//
//  The games in the player's games folder (CartoucheStorage), installed on
//  this iPhone or not: each IPA there, and the folders one level down. An
//  IPA Cartouche wrote is known by its name, "<game> [<title ID>].ipa";
//  any other by its Info.plist, read from the IPA where it sits: its
//  central directory and one entry, a few reads, even for an IPA of
//  several gigabytes. The Info.plist also says which build of the game
//  the IPA is (CartoucheGameBuild), for the console to offer a newer one
//  over the installed game. What Cartouche found is kept on the iPhone,
//  so that each IPA is read once.
//
//  An IPA nxnative built without its game files (romfs.id, CartoucheRomfs)
//  takes the image of them, romfs.img, that sits beside it, in any letter
//  case, or elsewhere in the games folder: Cartouche installs the two
//  together. An image no IPA takes, and an IPA without its image, are
//  told on the Storage page, since neither installs a game by itself.
//
//  Away from the games folder's server, as from a NAS at home, the last
//  list stays: Cartouche finds the server offline within a few seconds
//  (CartoucheStorageReach), and reads the folder again once it answers.
//
//  The player may keep games in several folders, on several servers
//  (CartoucheStorageSettings.gamesFolders): Cartouche reads them all at
//  once, and a game in more than one shows once in the library, from the
//  copy it can reach (CartoucheGameCopies.swift): as the NAS goes offline
//  away from home, its games install from the Drive, the Mac or the bucket
//  that holds them too. Install tries the game's next copy when the server
//  of the one offered does not answer.
//

import Combine
import Foundation

/// An IPA in the player's games folder.
struct CartoucheStoredGame: Codable, Hashable, Identifiable {
    /// Its path in the games folder's server.
    let path: String
    let size: UInt64
    let modified: Date?
    /// From its Info.plist, when Cartouche read it.
    var bundleId: String?
    var displayName: String?
    var version: String?
    /// Which build of the game it is, from its Info.plist.
    var build: CartoucheGameBuild?
    /// The game's title ID, from its name or its bundle ID.
    var titleId: String?
    /// Whether it is an nxnative game, as far as Cartouche can tell.
    var isGame: Bool
    /// The image of its game files it needs, for an IPA nxnative built
    /// without them (CartoucheRomfs); nil for one that holds them.
    var gameFiles: CartoucheRomfsIdentity? = nil
    /// The image of the games folder that goes with it, by its path: of the
    /// size it needs, beside it or elsewhere in the folder.
    var gameFilesPath: String? = nil
    /// Whether Cartouche looked for romfs.id in it, as an older Cartouche
    /// did not.
    var checkedGameFiles: Bool? = nil
    /// The server of the games folder it is in, and that folder's path on
    /// it; none from an older Cartouche, which had one games folder.
    var server: UUID? = nil
    var folder: String? = nil
    /// Whether its server does not answer from here, and its folder's
    /// place among the games folders, as the list says them now: not kept
    /// (CodingKeys).
    var isOffline = false
    var folderRank = 0

    enum CodingKeys: String, CodingKey {
        case path, size, modified, bundleId, displayName, version, build, titleId, isGame, gameFiles, gameFilesPath,
             checkedGameFiles, server, folder
    }

    /// Its path, on its server: the same path in two games folders is two
    /// copies.
    var id: String { (server.map { $0.uuidString + "|" } ?? "") + path }
    /// Whether it needs an image of its game files the games folder lacks.
    var lacksGameFiles: Bool { gameFiles != nil && gameFilesPath == nil }
    /// What it takes in the games folder, with the image of its game files.
    var storedSize: UInt64 { size + (gameFilesPath == nil ? 0 : gameFiles?.size ?? 0) }
    var fileName: String { CartoucheStoragePath.name(path) }

    /// The name to show when the catalogue does not know the game.
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        var name = fileName
        if name.lowercased().hasSuffix(".ipa") { name.removeLast(4) }
        if let range = name.range(of: #"\s*\[[0-9A-Fa-f]{16}\]"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    /// The name Cartouche gives the IPA of a game it copies to the games
    /// folder.
    static func fileName(game: String, titleId: String?) -> String {
        var name = CartoucheStoragePath.fileName(game)
        if let titleId { name += " [\(titleId.uppercased())]" }
        return name + ".ipa"
    }

    /// The title ID in a name such as "Example Quest [0100F00D0BAD0000].ipa",
    /// as the Storage page says it (CartoucheNaming).
    static func titleId(inName name: String) -> String? {
        CartoucheNaming.titleId(inName: name)
    }

    /// The title ID in an nxnative bundle ID, org.nxnative.<title ID>.
    static func titleId(inBundleId bundleId: String) -> String? {
        let prefix = "org.nxnative."
        let lowered = bundleId.lowercased()
        guard lowered.hasPrefix(prefix) else { return nil }
        let candidate = lowered.dropFirst(prefix.count).prefix(16)
        guard candidate.count == 16, candidate.allSatisfy(\.isHexDigit) else { return nil }
        return candidate.uppercased()
    }

    /// Whether this IPA is a newer copy of the game than OTHER, of the same
    /// games folder: by the builds they are, else by when they were written
    /// there.
    func isNewerCopy(than other: CartoucheStoredGame) -> Bool {
        if let build, let otherBuild = other.build {
            if build.isNewerCopy(than: otherBuild) { return true }
            if otherBuild.isNewerCopy(than: build) { return false }
        }
        return (modified ?? .distantPast) > (other.modified ?? .distantPast)
    }

    /// What tells it from the game's other copies (CartoucheGameCopies).
    var rank: CartoucheCopyRank {
        CartoucheCopyRank(offline: isOffline, folder: folderRank, build: build, modified: modified)
    }

    /// Whether the console offers this IPA rather than OTHER, of the same
    /// game: one Cartouche can reach, then the newer copy, then the one of
    /// the folder listed first.
    func isPreferredCopy(over other: CartoucheStoredGame) -> Bool {
        CartoucheGameCopies.prefers(rank, over: other.rank)
    }

    /// Whether OTHER is a copy of the same game, by its title ID or its
    /// bundle ID.
    func isSameGame(as other: CartoucheStoredGame) -> Bool {
        if let titleId, titleId == other.titleId { return true }
        if let bundleId, bundleId == other.bundleId { return true }
        return false
    }
}

/// The build of each game Cartouche installed, as the IPA it came from
/// said: an installed game no longer says when it was built, since the
/// time of its Info.plist goes with the install.
final class CartoucheInstalledBuilds {
    static let shared = CartoucheInstalledBuilds()

    /// By the game's bundle ID.
    private var builds: [String: CartoucheGameBuild] = [:]
    private let file: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = support.appendingPathComponent("Cartouche/InstalledBuilds.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: CartoucheGameBuild].self, from: data) {
            builds = saved
        }
    }

    /// Notes the build of the IPA Cartouche just installed as BUNDLEID.
    func record(_ build: CartoucheGameBuild, bundleId: String) {
        builds[bundleId] = build
        guard let data = try? JSONEncoder().encode(builds) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The builds read from the games' Info.plist, by the game's bundle, with
    /// when the Info.plist last changed: the console asks for them often.
    private static var readBuilds: [String: (changed: Date?, build: CartoucheGameBuild)] = [:]
    private static let readLock = NSLock()

    /// The build of the installed game, as the Info.plist in its bundle says.
    /// LiveContainer's info() is not it: those are LiveContainer's own
    /// settings for the game (LCAppInfo.plist), which name no version.
    static func installedBuild(of app: LCAppModel) -> CartoucheGameBuild {
        guard let path = app.appInfo.bundlePath() else { return CartoucheGameBuild() }
        let bundle = URL(fileURLWithPath: path, isDirectory: true)
        let changed = (try? bundle.appendingPathComponent("Info.plist")
            .resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        readLock.lock()
        defer { readLock.unlock() }
        if let known = readBuilds[path], known.changed == changed { return known.build }
        let build = CartoucheGameBuild.installed(atBundle: bundle) ?? CartoucheGameBuild()
        readBuilds[path] = (changed, build)
        return build
    }

    /// Whether each installed game's executable converts its BC textures,
    /// by the game's bundle, with what its Info.plist names and when the
    /// executable last changed, and its size: Cartouche signing the game
    /// again writes it again.
    private static var readConversions: [String: Conversion] = [:]
    private static let conversionLock = NSLock()

    private struct Conversion {
        let infoChanged: Date?
        let executable: String
        let changed: Date?
        let size: Int?
        let converts: Bool
    }

    /// Whether the installed game was built with an nxnative that converts
    /// its BC-compressed textures for a GPU that reads none, as its
    /// executable says (CartoucheBCConversion): read once for each build,
    /// and only where the GPU reads none (CartoucheEntry.convertsBCTextures).
    /// The iPhone's bundle, whose Info.plist and executable are at its top.
    static func convertsBCTextures(of app: LCAppModel) -> Bool {
        guard let path = app.appInfo.bundlePath() else { return false }
        let bundle = URL(fileURLWithPath: path, isDirectory: true)
        let info = bundle.appendingPathComponent("Info.plist")
        let infoChanged = (try? info.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        conversionLock.lock()
        defer { conversionLock.unlock() }
        let executable: String
        if let known = readConversions[path], known.infoChanged == infoChanged {
            executable = known.executable
        } else {
            guard let data = try? Data(contentsOf: info),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let name = plist["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/") else {
                readConversions[path] = nil
                return false
            }
            executable = name
        }
        let file = bundle.appendingPathComponent(executable)
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        if let known = readConversions[path], known.infoChanged == infoChanged, known.executable == executable,
           known.changed == values?.contentModificationDate, known.size == values?.fileSize {
            return known.converts
        }
        let converts = CartoucheBCConversion.converts(executableAt: file)
        readConversions[path] = Conversion(infoChanged: infoChanged, executable: executable,
                                           changed: values?.contentModificationDate, size: values?.fileSize,
                                           converts: converts)
        return converts
    }

    /// The record of the game's install, when it is of the build installed
    /// (CartoucheGameBuild.record(_:of:)).
    func record(of app: LCAppModel) -> CartoucheGameBuild? {
        guard let bundleId = app.appInfo.bundleIdentifier(), let recorded = builds[bundleId] else { return nil }
        return CartoucheGameBuild.record(recorded, of: Self.installedBuild(of: app))
    }

    /// The installed game's build, to compare with a copy in the games
    /// folder: when it was built, from the record of its install, or, for
    /// a game Cartouche installed before it kept one, when it was
    /// installed, which it was built before.
    func build(of app: LCAppModel) -> CartoucheGameBuild {
        let installedAt: Date? = app.appInfo.installationDate
        var build = record(of: app) ?? Self.installedBuild(of: app)
        if build.builtAt == nil { build.builtAt = installedAt }
        return build
    }
}

@MainActor
final class CartoucheStoredGames: ObservableObject {
    static let shared = CartoucheStoredGames()

    /// The IPAs of every games folder, each copy of a game that is in
    /// several: the library shows one of them (CartoucheCatalog.entries),
    /// as isPreferredCopy(over:) chooses. Each says whether its server
    /// answers from here, as CartoucheStorageReach last found.
    @Published private(set) var games: [CartoucheStoredGame] = []
    @Published private(set) var isScanning = false
    /// Why the first games folder that could not be read, the last time,
    /// could not, and the report on it.
    var problemReport: CartoucheReport? {
        let folders = settings.gamesFolders.all
        return folders.lazy.compactMap { self.problems[$0] }.first ?? problems.values.first
    }
    var problem: String? { problemReport?.message }
    /// Why each games folder could not be read, the last time, and the
    /// report on it.
    @Published private(set) var problems: [CartoucheStoragePlace: CartoucheReport] = [:]
    /// The server the games are on, for the console to name: the games
    /// folder's, the first.
    @Published private(set) var serverName: String?
    /// The images of game files in the games folders that no IPA there
    /// takes, by their paths (CartoucheRomfs): a romfs.img without the IPA
    /// nxnative built with it.
    var looseGameFiles: [String] { settings.gamesFolders.all.flatMap { loose[$0] ?? [] } }
    /// The same, by games folder.
    @Published private(set) var loose: [CartoucheStoragePlace: [String]] = [:]

    private let settings: CartoucheStorageSettings
    /// What each folder holds, as last read, without whether their servers
    /// answer: games is made of it (publish).
    private var found: [CartoucheStoredGame] = []
    /// The servers that do not answer from here, as CartoucheStorageReach
    /// last said.
    private var offline: Set<UUID> = []
    private var known: [String: CartoucheStoredGame] = [:]
    private let cacheFile: URL
    private var scan: Task<Void, Never>?
    private var watching: AnyCancellable?
    #if CARTOUCHE_GALLERY
    private var shownForGallery = false
    #endif
    #if os(macOS)
    private var shownForMac = false
    #endif

    init(settings: CartoucheStorageSettings = .shared) {
        self.settings = settings
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFile = caches.appendingPathComponent("Cartouche/StoredGames.json")
        if let data = try? Data(contentsOf: cacheFile),
           let saved = try? JSONDecoder().decode([String: CartoucheStoredGame].self, from: data) {
            known = saved
        }
        let locations = settings.gamesLocations
        if let first = locations.first {
            serverName = first.server.name
            // The last list, until the folders have been read again.
            var lastList: [CartoucheStoredGame] = []
            for location in locations {
                let prefix = location.server.id.uuidString + "|"
                for (key, game) in known where key.hasPrefix(prefix) && Self.isIn(game.path, folder: location.path) {
                    var game = game
                    game.server = location.server.id
                    game.folder = location.path
                    lastList.append(game)
                }
            }
            found = Self.once(lastList)
        }
        // As each server goes offline, or answers again, the copy offered
        // of a game in several folders changes: from the list as it is now.
        watching = CartoucheStorageReach.shared.$absences
            .map { Set($0.keys) }
            .removeDuplicates()
            .sink { [weak self] offline in
                self?.offline = offline
                self?.publish()
            }
    }

    private static func byName(_ a: CartoucheStoredGame, _ b: CartoucheStoredGame) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Whether PATH is in the folder at FOLDER, or one of its folders.
    nonisolated static func isIn(_ path: String, folder: String) -> Bool {
        let base = CartoucheStoragePath.join(folder)
        let path = CartoucheStoragePath.join(path)
        return base.isEmpty || path.hasPrefix(base + "/")
    }

    /// GAMES without the same file twice, as two games folders of the same
    /// server, one in the other, both list it: the first folder's.
    private static func once(_ games: [CartoucheStoredGame]) -> [CartoucheStoredGame] {
        var seen = Set<String>()
        return games.filter { game in
            seen.insert((game.server?.uuidString ?? "") + "|" + CartoucheStoragePath.join(game.path)).inserted
        }
    }

    /// Makes games of what the folders hold: each copy saying whether its
    /// server answers, and its folder's place among the games folders.
    private func publish() {
        let folders = settings.gamesFolders.all
        let first = folders.first?.server
        let published = found.map { found -> CartoucheStoredGame in
            var game = found
            let server = game.server ?? first
            game.isOffline = server.map { offline.contains($0) } ?? false
            game.folderRank = folders.firstIndex { $0.server == server && $0.path == (game.folder ?? $0.path) } ?? 0
            return game
        }
        .filter(\.isGame)
        .sorted(by: Self.byName)
        if published != games { games = published }
    }

    /// The stored game of a title ID, or of an installed app's bundle ID:
    /// the copy offered, of a game in several folders.
    func game(titleId: String?, bundleId: String?) -> CartoucheStoredGame? {
        games.filter { stored in
            (titleId != nil && stored.titleId == titleId) || (bundleId != nil && stored.bundleId == bundleId)
        }
        .max { $1.isPreferredCopy(over: $0) }
    }

    /// GAME and its other copies, in the order to try them: GAME first,
    /// then those whose servers answer, the newer copies first.
    func copies(of game: CartoucheStoredGame) -> [CartoucheStoredGame] {
        let others = games.filter { $0 != game && $0.isSameGame(as: game) }
        return [game] + CartoucheGameCopies.ordered(others, by: \.rank)
    }

    /// The server of the games folder GAME is in.
    func server(of game: CartoucheStoredGame) -> CartoucheStorageServer? {
        if let server = game.server { return settings.server(server) }
        return settings.location(.games)?.server
    }

    /// The name of where GAME is, for the console to say: its server's.
    func place(of game: CartoucheStoredGame?) -> String {
        if let game, let server = server(of: game) { return server.name }
        return serverName ?? ""
    }

    /// Whether GAME's server is a Google Drive whose sign-in Google ended,
    /// as Cartouche found it offline: the player signs in again, rather
    /// than waits.
    func isSignedOut(_ game: CartoucheStoredGame) -> Bool {
        guard game.isOffline, let server = server(of: game) else { return false }
        return CartoucheStorageOffline(server).isSignedOut
    }

    /// The games found in the games folder at PLACE.
    func count(in place: CartoucheStoragePlace) -> Int {
        let first = settings.place(.games)
        return games.filter { game in
            let server = game.server ?? first?.server
            let folder = game.folder ?? first?.path
            return server == place.server && folder == place.path
        }.count
    }

    /// Reads the games folders again, unless they are being read. As
    /// Cartouche does by itself, it leaves a server it found offline a
    /// moment ago alone; EVEN IF OFFLINE, as the player asks, it tries it
    /// again.
    func refresh(evenIfOffline: Bool = false) {
        guard scan == nil else { return }
        scan = Task {
            await read(evenIfOffline: evenIfOffline)
            scan = nil
        }
    }

    /// Reads the games folders again and waits for the list.
    func reload() async {
        if let scan { await scan.value }
        await read(evenIfOffline: true)
    }

    #if CARTOUCHE_GALLERY
    /// A games folder with these IPAs, for the launcher's gallery
    /// (launcher/Gallery): those of several folders say which, by their
    /// servers and folders.
    func showForGallery(_ stored: [CartoucheStoredGame], server: String) {
        found = stored
        serverName = server
        shownForGallery = true
        publish()
    }
    #endif

    #if os(macOS)
    /// The games Cartouche Builder keeps for the Mac in its games folder
    /// and has not installed on it, and the words for where they are, for
    /// Cartouche's console on the Mac (builder/mac/Sources/CartoucheConsole):
    /// the Builder reads its games folder, never the console.
    func showForMac(_ stored: [CartoucheStoredGame], server: String) {
        found = stored
        serverName = server
        shownForMac = true
        publish()
    }
    #endif

    /// What the reading of one games folder found: its games and the
    /// images no IPA takes; none when the last list stays, as when its
    /// server is offline.
    private struct FolderRead {
        var place: CartoucheStoragePlace
        var games: [CartoucheStoredGame]?
        var loose: [String] = []
        var problem: CartoucheReport?
    }

    private func read(evenIfOffline: Bool) async {
        #if CARTOUCHE_GALLERY
        if shownForGallery { return }
        #endif
        #if os(macOS)
        if shownForMac { return }
        #endif
        let locations = settings.gamesLocations
        guard let first = locations.first else {
            found = []
            loose = [:]
            serverName = nil
            problems = [:]
            publish()
            return
        }
        serverName = first.server.name
        isScanning = true
        defer { isScanning = false }
        // All at once: a server that does not answer keeps the others
        // waiting no longer than itself.
        let reads = await withTaskGroup(of: FolderRead.self, returning: [FolderRead].self) { group in
            for location in locations {
                let server = location.server
                let path = location.path
                group.addTask {
                    await self.readFolder(server, path: path, evenIfOffline: evenIfOffline)
                }
            }
            var reads: [FolderRead] = []
            for await read in group { reads.append(read) }
            return reads
        }
        // The folders as they are now: one the player stopped using
        // meanwhile is left out.
        let folders = settings.gamesFolders.all
        var list: [CartoucheStoredGame] = []
        var problems: [CartoucheStoragePlace: CartoucheReport] = [:]
        var loose: [CartoucheStoragePlace: [String]] = [:]
        for place in folders {
            guard let read = reads.first(where: { $0.place == place }) else {
                list += found.filter { $0.server == place.server && $0.folder == place.path }
                continue
            }
            list += read.games ?? found.filter { $0.server == place.server && $0.folder == place.path }
            if read.games == nil { loose[place] = self.loose[place] } else { loose[place] = read.loose }
            problems[place] = read.problem
        }
        found = Self.once(list)
        self.problems = problems
        self.loose = loose
        publish()
        save()
    }

    /// Reads the games folder at PATH on SERVER.
    private func readFolder(_ server: CartoucheStorageServer, path: String, evenIfOffline: Bool) async -> FolderRead {
        let place = CartoucheStoragePlace(server: server.id, path: path)
        if !evenIfOffline && CartoucheStorageReach.shared.isSettledOffline(server.id) {
            return FolderRead(place: place)
        }
        let remote: CartoucheRemote
        do {
            remote = try await CartoucheStorage.connect(server, settings: settings)
        } catch is CartoucheStorageOffline {
            // No problem: the last list stays until the server answers again.
            return FolderRead(place: place)
        } catch {
            return FolderRead(place: place, problem: Self.readFailed(error, step: "Connecting to " + CartoucheReports.place(.games, on: server)))
        }
        var found: [CartoucheStoredGame] = []
        var images: [CartoucheRomfsImage] = []
        var problem: CartoucheReport?
        do {
            var folders = [path]
            let top = try await remote.list(path)
            // Whether Cartouche can copy a game there, for its Copy to.
            await settings.checkAccess(remote, server: server.id, path: path)
            folders += top.filter(\.isFolder).prefix(64).map { CartoucheStoragePath.join(path, $0.name) }
            for folder in folders {
                let items: [CartoucheRemoteItem]
                if folder == path {
                    items = top
                } else {
                    items = (try? await remote.list(folder)) ?? []
                }
                for item in items where !item.isFolder && CartoucheRomfs.isImageName(item.name) {
                    let itemPath = CartoucheStoragePath.join(folder, item.name)
                    images.append(CartoucheRomfsImage(path: itemPath, folder: CartoucheStoragePath.parent(itemPath), size: item.size))
                }
                for item in items where !item.isFolder && CartoucheNaming.isIPA(item.name) {
                    let itemPath = CartoucheStoragePath.join(folder, item.name)
                    let key = Self.key(server, path: itemPath, size: item.size, modified: item.modified)
                    // What a scan before 0.9.0 found says nothing of the
                    // build, and one by an older Cartouche nothing of the
                    // game files: read again.
                    if var game = known[key], game.build != nil, game.checkedGameFiles == true {
                        game.server = server.id
                        game.folder = path
                        found.append(game)
                        continue
                    }
                    let identified = await identify(path: itemPath, item: item, in: remote, server: server)
                    var game = identified.0
                    game.server = server.id
                    game.folder = path
                    if identified.settled { known[key] = game }
                    found.append(game)
                }
            }
        } catch {
            problem = Self.readFailed(error, step: "Listing " + CartoucheReports.place(.games, on: server),
                                      facts: [.init("Games found", String(found.count))])
        }
        await remote.disconnect()
        let paired = Self.pairGameFiles(found, images: images)
        for game in paired.games {
            let key = Self.key(server, path: game.path, size: game.size, modified: game.modified)
            known[key]?.gameFilesPath = game.gameFilesPath
        }
        return FolderRead(place: place, games: paired.games, loose: paired.loose, problem: problem)
    }

    /// GAMES, each IPA built without its game files with the image of the
    /// games folder it takes (CartoucheRomfs.pair), and the images no IPA
    /// takes. An IPA Cartouche could not read may be the one an image goes
    /// with: none is said to be alone then.
    nonisolated static func pairGameFiles(_ games: [CartoucheStoredGame], images: [CartoucheRomfsImage])
        -> (games: [CartoucheStoredGame], loose: [String]) {
        let needs = games.compactMap { game in
            game.gameFiles.map { CartoucheRomfsNeed(path: game.path, folder: CartoucheStoragePath.parent(game.path), size: $0.size) }
        }
        let (taken, loose) = CartoucheRomfs.pair(needs, with: images, allRead: games.allSatisfy { $0.checkedGameFiles == true })
        let paired = games.map { game -> CartoucheStoredGame in
            var game = game
            game.gameFilesPath = taken[game.path]?.path
            return game
        }
        return (paired, loose.map(\.path))
    }

    /// The report on the games folder, which ERROR kept Cartouche from
    /// reading at STEP. Cartouche reads it each time it comes back, away
    /// from home too: the report is not kept.
    private static func readFailed(_ error: Error, step: String, facts: [CartoucheReport.Fact] = []) -> CartoucheReport {
        CartoucheReports.make(.storage, CartoucheText.storageGamesFailed, message: error.localizedDescription, error: error,
                              step: step, stage: "gamesFolder", facts: facts, inBackground: true)
    }

    private static func key(_ server: CartoucheStorageServer, path: String, size: UInt64, modified: Date?) -> String {
        "\(server.id.uuidString)|\(path)|\(size)|\(Int(modified?.timeIntervalSince1970 ?? 0))"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(known) else { return }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
    }

    /// What the IPA at PATH is: by the title ID in its name, as Cartouche
    /// names the IPAs it writes, else by its Info.plist, else by its name
    /// (CartoucheCatalog.titleId(inFileName:)); and which build of the game,
    /// by its Info.plist. A file iCloud Drive has not downloaded is known by
    /// its name only, since reading it would download all of it. Also
    /// returns whether to remember what it found: an IPA whose Info.plist
    /// could not be read is read again at the next scan, once it is
    /// downloaded or once the place answers.
    private func identify(path: String, item: CartoucheRemoteItem, in remote: CartoucheRemote,
                          server: CartoucheStorageServer) async -> (CartoucheStoredGame, settled: Bool) {
        var game = CartoucheStoredGame(path: path, size: item.size, modified: item.modified,
                                       titleId: CartoucheStoredGame.titleId(inName: item.name), isGame: false)
        let named = game.titleId != nil
        if let folder = remote as? CartoucheFolder, !folder.isDownloaded(path) {
            if !named { game.titleId = CartoucheCatalog.shared.titleId(inFileName: item.name) }
            game.isGame = game.titleId != nil
            return (game, false)
        }
        do {
            let source = try await remote.open(path)
            let entries = try await CartoucheZip.entries(of: source)
            let (info, builtAt) = try await Self.infoPlist(of: source, entries: entries)
            game.bundleId = info["CFBundleIdentifier"] as? String
            game.displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            game.version = info["CFBundleShortVersionString"] as? String
            game.build = CartoucheGameBuild(info: info, builtAt: builtAt)
            if !named {
                game.titleId = game.bundleId.flatMap(CartoucheStoredGame.titleId(inBundleId:))
                    ?? CartoucheNxnativeApp.titleId(in: info)
                    ?? game.displayName.flatMap { CartoucheCatalog.shared.titleId(matchingName: $0) }
                    ?? CartoucheCatalog.shared.titleId(inFileName: item.name)
            }
            // Its romfs.id, for an IPA built without its game files: one
            // more entry read.
            game.gameFiles = try await CartoucheRomfs.neededIdentity(ofIPA: source, entries: entries)
            game.checkedGameFiles = true
            game.isGame = CartoucheNxnativeApp.isGame(info: info, titleId: game.titleId, needsGameFiles: game.gameFiles != nil)
            return (game, true)
        } catch {
            NSLog("[Cartouche] cannot read %@: %@", path, error.localizedDescription)
            if !named { game.titleId = CartoucheCatalog.shared.titleId(inFileName: item.name) }
            game.isGame = game.titleId != nil
            return (game, false)
        }
    }

    /// The entry of the app's Info.plist in an IPA: Payload/<name>.app/Info.plist.
    nonisolated static func infoPlistEntry(in entries: [CartoucheZipEntry]) -> CartoucheZipEntry? {
        entries.first { entry in
            let parts = entry.name.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
    }

    /// The Info.plist of the app in an IPA of these ENTRIES, and its time
    /// there, which says when the IPA was built.
    nonisolated static func infoPlist(of source: CartoucheByteSource,
                                      entries: [CartoucheZipEntry]) async throws -> (info: [String: Any], builtAt: Date?) {
        guard let entry = infoPlistEntry(in: entries) else {
            throw CartoucheStorageError(.notAnApp, CartoucheText.storageNotAnApp)
        }
        let data = try await CartoucheZip.data(of: entry, in: source, limit: 4 << 20)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CartoucheStorageError(.notAnApp, CartoucheText.storageNotAnApp)
        }
        return (plist, entry.modified)
    }
}
