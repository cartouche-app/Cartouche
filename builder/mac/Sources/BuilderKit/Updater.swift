//
//  Updater.swift
//  Cartouche Builder
//
//  The app's own updates, without the player, like Cartouche's on the
//  iPhone. It reads the project's releases on GitHub (builder-v<version>,
//  which the Builder workflow publishes) when it opens and every six
//  hours, a page at a time until one has the builder's: Cartouche's own
//  releases and its Installer's come between. A higher version than its
//  own is downloaded and checked against the SHA-256 published beside it,
//  then put in place of the app when the app quits, at once when the
//  player asks, or when nothing runs and no window is open (the app then
//  opens again, in the menu bar only). The new app is checked before it
//  replaces this one: the same bundle identifier, the version the release
//  names, a macOS it runs on, an intact signature. A disk image the app
//  downloads itself is not quarantined, so macOS opens the new version
//  without asking again.
//
//  A copy already installed finds only what it was built to find: the
//  tag, the disk image's name and the bundle identifier below, and the
//  repository, or the one GitHub answers for once it moved. Every release
//  keeps them (builder/tests/test_updates.py): 0.5.0 and older took their
//  disk images from github.com/clabeuhtegrite/Cartouche alone, and find
//  none since the repository moved to its organization.
//  UpdaterEndToEndTests.swift updates an installed copy as a player's Mac
//  does, and the Builder workflow does it with the disk image it made.
//

import CryptoKit
import Foundation

/// A version of Cartouche Builder that GitHub has.
public struct BuilderRelease: Codable, Equatable, Sendable {
    public var version: String
    public var tag: String
    public var notes: String
    public var page: URL
    /// The disk image, and its SHA-256.
    public var image: URL
    public var checksum: URL
    public var size: UInt64

    public init(version: String, tag: String, notes: String, page: URL, image: URL, checksum: URL, size: UInt64) {
        self.version = version
        self.tag = tag
        self.notes = notes
        self.page = page
        self.image = image
        self.checksum = checksum
        self.size = size
    }
}

public enum BuilderVersion {
    /// "0.2.0" as [0, 2, 0]; nil when it is not a version.
    public static func parts(_ text: String) -> [Int]? {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    public static func isHigher(_ version: String, than other: String) -> Bool {
        guard let mine = parts(version), let theirs = parts(other) else { return false }
        for index in 0..<max(mine.count, theirs.count) {
            let a = index < mine.count ? mine[index] : 0
            let b = index < theirs.count ? theirs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

public enum BuilderReleases {
    public static let repository = "cartouche-app/Cartouche"
    public static let tagPrefix = "builder-v"
    /// The releases in one answer of GitHub's, its most.
    public static let perPage = 100
    /// The answers one check reads at most. GitHub gives the newest
    /// releases first, so the builder's newest is on the first answer that
    /// has one of the builder's; Cartouche's and its Installer's, two at
    /// each version of Cartouche, can fill the answers before it.
    public static let pages = 10

    public static var api: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=\(perPage)")!
    }

    /// The newest release of Cartouche Builder that GitHub has: its
    /// releases read from `api` an answer at a time, FETCH giving each as
    /// URLSession does (redirects followed, the answer's own address in the
    /// response), until one has a release of the builder's, at most `pages`
    /// of them. The repository GitHub answered for is the first answer's
    /// (`answeringRepository(_:releases:)`). Nil when there is none.
    public static func newest(fetch: (URL) async throws -> (Data, URLResponse)) async throws -> BuilderRelease? {
        var address: URL? = api
        var answering: String?
        for page in 1...pages {
            guard let asked = address else { break }
            let (data, response) = try await fetch(asked)
            if page == 1 {
                answering = answeringRepository(response.url, releases: data)
            }
            if let found = try newest(in: data, answering: answering) {
                return found
            }
            address = nextPage((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Link"))
        }
        return nil
    }

    /// The address of the answer after this one, from GitHub's Link header
    /// (`<https://api.github.com/…&page=2>; rel="next", <…>; rel="last"`):
    /// an address of GitHub's API alone. Nil on the last answer.
    public static func nextPage(_ link: String?) -> URL? {
        guard let link else { return nil }
        for part in link.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            let isNext = pieces.dropFirst().contains { $0.replacingOccurrences(of: " ", with: "").lowercased() == "rel=\"next\"" }
            guard isNext, let first = pieces.first, first.hasPrefix("<"), first.hasSuffix(">") else { continue }
            guard let next = URL(string: String(first.dropFirst().dropLast())), next.scheme == "https",
                  next.host?.lowercased() == "api.github.com" else { return nil }
            return next
        }
        return nil
    }

    public static func imageName(_ version: String) -> String {
        "Cartouche-Builder-\(version).dmg"
    }

    /// The repository whose releases GitHub answered with, from the address
    /// the answer came from once URLSession followed GitHub's redirects:
    /// another than `repository` once the repository has moved, as GitHub
    /// redirects the API of a repository that moved, whose answer then gives
    /// the new place's addresses.
    /// - https://api.github.com/repos/OWNER/NAME/releases names it.
    /// - https://api.github.com/repositories/ID/releases, where GitHub may
    ///   send a repository that moved, names it by its number alone: the
    ///   answer, RELEASES, is that repository's releases, whose pages,
    ///   https://github.com/OWNER/NAME/releases/tag/TAG, all name it.
    /// Nil for any other address, or releases that name none or several.
    public static func answeringRepository(_ address: URL?, releases: Data? = nil) -> String? {
        guard let address, address.scheme == "https", address.host?.lowercased() == "api.github.com" else { return nil }
        let path = address.pathComponents.filter { $0 != "/" }
        if path.count == 4, path[0] == "repos", path[3] == "releases" {
            return path[1] + "/" + path[2]
        }
        guard path.count == 3, path[0] == "repositories", path[2] == "releases",
              !path[1].isEmpty, path[1].allSatisfy({ $0.isASCII && $0.isNumber }), let releases else { return nil }
        struct Release: Decodable {
            var html_url: String
        }
        guard let pages = try? JSONDecoder().decode([Release].self, from: releases) else { return nil }
        let named = pages.map { release -> String? in
            guard let page = URL(string: release.html_url), page.scheme == "https",
                  page.host?.lowercased() == "github.com" else { return nil }
            let parts = page.pathComponents.filter { $0 != "/" }
            guard parts.count >= 4, parts[2] == "releases" else { return nil }
            return parts[0] + "/" + parts[1]
        }
        guard let first = named.first ?? nil,
              named.allSatisfy({ $0?.caseInsensitiveCompare(first) == .orderedSame }) else { return nil }
        return first
    }

    /// The newest release of Cartouche Builder in an answer of GitHub's
    /// releases API: not a draft nor a pre-release, with its disk image and
    /// its SHA-256 downloaded from the project's releases, those of
    /// `repository` or of the repository GitHub answered for (ANSWERING,
    /// `answeringRepository(_:)`). Nil when there is none.
    public static func newest(in data: Data, answering: String? = nil) throws -> BuilderRelease? {
        struct Release: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: String
                var size: UInt64?
            }

            var tag_name: String
            var draft: Bool?
            var prerelease: Bool?
            var body: String?
            var html_url: String
            var assets: [Asset]
        }
        let repositories: [String] = [repository, answering ?? repository]
        let downloads = repositories.map { "https://github.com/\($0)/releases/download/".lowercased() }
        var best: BuilderRelease?
        for release in try JSONDecoder().decode([Release].self, from: data)
        where release.draft != true && release.prerelease != true && release.tag_name.hasPrefix(tagPrefix) {
            let version = String(release.tag_name.dropFirst(tagPrefix.count))
            guard isVersion(version) else { continue }
            func asset(_ name: String) -> (url: URL, size: UInt64)? {
                guard let found = release.assets.first(where: { $0.name == name }),
                      downloads.contains(where: { found.browser_download_url.lowercased().hasPrefix($0) }),
                      let url = URL(string: found.browser_download_url) else { return nil }
                return (url, found.size ?? 0)
            }
            guard let image = asset(imageName(version)), let checksum = asset(imageName(version) + ".sha256"),
                  let page = URL(string: release.html_url) else { continue }
            let found = BuilderRelease(version: version, tag: release.tag_name, notes: release.body ?? "", page: page,
                                       image: image.url, checksum: checksum.url, size: image.size)
            if best.map({ BuilderVersion.isHigher(version, than: $0.version) }) ?? true {
                best = found
            }
        }
        return best
    }

    private static func isVersion(_ text: String) -> Bool {
        BuilderVersion.parts(text) != nil
    }

    /// The SHA-256 in a .sha256 file: its first word, 64 hexadecimal digits.
    public static func checksum(in text: String) -> String? {
        guard let word = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).first else { return nil }
        let hex = word.lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }
}

public struct UpdateError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

@MainActor
public final class Updater: ObservableObject {
    public enum State: Equatable {
        case idle
        case upToDate
        case checking
        case available(BuilderRelease)
        case downloading(BuilderRelease)
        /// Downloaded and checked: it installs when the app quits.
        case ready(BuilderRelease)
        case installing
        case failed(String)
    }

    public static let identifier = "io.github.clabeuhtegrite.cartouche-builder"
    public static let checkInterval: TimeInterval = 6 * 3600
    static let automaticKey = "updates.automatic"

    @Published public private(set) var state: State = .idle
    @Published public private(set) var checked: Date?
    /// Whether updates download and install by themselves (on unless the
    /// player turns it off).
    @Published public var automatic: Bool {
        didSet {
            UserDefaults.standard.set(automatic, forKey: Self.automaticKey)
            if automatic, case let .available(release) = state {
                Task { await download(release) }
            }
        }
    }

    /// This app's version.
    public let current: String
    /// Whether this copy is the app, not the engine run from a Terminal.
    public let enabled: Bool

    /// Whether a build runs: the update waits for it, as a build runs the
    /// engine inside the app.
    public var isBuilding: () -> Bool = { false }
    /// Whether the app may quit and open again by itself: no window open,
    /// no iPhone connected.
    public var isIdle: () -> Bool = { false }
    /// Quits the app, for the new version to open.
    public var quit: () -> Void = {}
    /// What went wrong, for the telemetry.
    public var failed: ((Error) -> Void)?

    private let app: URL
    private let identifier: String
    private let folder: URL
    /// How it reaches GitHub: the system's session, or the tests' own.
    private let session: URLSession
    private var loop: Task<Void, Never>?

    public init(app: URL, version: String, identifier: String, folder: URL, enabled: Bool, session: URLSession = .shared) {
        self.app = app
        current = version
        self.identifier = identifier
        self.folder = folder
        self.enabled = enabled
        self.session = session
        automatic = UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    /// The updater of the app that runs.
    public static func forThisApp() -> Updater {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let identifier = bundle.bundleIdentifier ?? ""
        return Updater(app: bundle.bundleURL, version: version, identifier: identifier,
                       folder: CoverSource.cache.appendingPathComponent("Updates", isDirectory: true),
                       enabled: bundle.bundleURL.pathExtension == "app" && identifier == Self.identifier)
    }

    public var busy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    public var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// Shows STATE without checking: for the gallery's pictures.
    public func preview(_ state: State) {
        self.state = state
    }

    /// The app opened from its disk image, or from where macOS put it aside
    /// (App Translocation): it cannot replace itself there.
    public var runsFromDiskImage: Bool {
        guard enabled else { return false }
        if app.path.contains("/AppTranslocation/") || app.path.hasPrefix("/Volumes/") { return true }
        return (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    /// Whether the update can go in place without the player's password.
    public var installsWithoutPassword: Bool {
        FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Whether the update installs as the app quits: downloaded, by itself
    /// or because the player asked, nothing built, no password to ask.
    public var installsAtQuit: Bool {
        isReady && !isBuilding() && !runsFromDiskImage && installsWithoutPassword
    }

    // MARK: Checking

    /// Checks in a moment and then every six hours; meanwhile, an update
    /// downloaded installs at the first quiet moment.
    public func start() {
        guard enabled, loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            while !Task.isCancelled {
                await self?.check(force: false)
                var waited: TimeInterval = 0
                while waited < Updater.checkInterval, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 900_000_000_000)
                    waited += 900
                    await self?.installIfIdle()
                }
            }
        }
    }

    /// Reads GitHub's releases, unless it did less than an hour ago (FORCE
    /// reads them now). A newer version downloads when updates are
    /// automatic, or when FORCE asked.
    public func check(force: Bool) async {
        guard enabled, !busy else { return }
        if !force, let checked, Date().timeIntervalSince(checked) < 3600 { return }
        if !force, isReady { return }
        let before = state
        state = .checking
        do {
            let newest = try await Self.newestRelease(session: session)
            checked = Date()
            guard let newest, BuilderVersion.isHigher(newest.version, than: current) else {
                state = .upToDate
                clean(keeping: nil)
                return
            }
            if (try? Self.verify(image(newest))) == true {
                state = .ready(newest)
                return
            }
            state = .available(newest)
            if automatic || force { await download(newest) }
        } catch {
            if force {
                state = .failed(tr("GitHub did not answer: ", "GitHub n’a pas répondu : ", "GitHub no respondió: ", "GitHub hat nicht geantwortet: ") + error.localizedDescription)
            } else {
                // A check the app makes by itself fails whenever the Mac is
                // offline: nothing to say.
                state = before == .checking ? .idle : before
            }
        }
    }

    nonisolated private static func newestRelease(session: URLSession) async throws -> BuilderRelease? {
        try await BuilderReleases.newest { address in
            var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try answered(response)
            return (data, response)
        }
    }

    // MARK: Downloading

    /// Downloads RELEASE and checks it: it is then ready to install.
    public func download(_ release: BuilderRelease) async {
        switch state {
        case .downloading, .installing: return
        default: break
        }
        guard !runsFromDiskImage else {
            state = .failed(Self.moveFirst)
            return
        }
        state = .downloading(release)
        do {
            try await Self.fetch(release, to: image(release), session: session)
            state = .ready(release)
            clean(keeping: release)
            await installIfIdle()
        } catch {
            state = .failed(error.localizedDescription)
            failed?(error)
        }
    }

    private func image(_ release: BuilderRelease) -> URL {
        folder.appendingPathComponent(BuilderReleases.imageName(release.version))
    }

    nonisolated private static func fetch(_ release: BuilderRelease, to destination: URL, session: URLSession) async throws {
        guard release.size <= 800_000_000 else {
            throw UpdateError(tr("This update is too big to be right: it was not downloaded.", "Cette mise à jour est trop grosse pour être la bonne : elle n’a pas été téléchargée.", "Esta actualización es demasiado grande para ser correcta: no se ha descargado.", "Dieses Update ist zu groß, um das richtige zu sein: Es wurde nicht geladen."))
        }
        let (text, sumResponse) = try await session.data(from: release.checksum)
        try answered(sumResponse)
        guard let expected = BuilderReleases.checksum(in: String(decoding: text, as: UTF8.self)) else {
            throw UpdateError(tr("The update has no valid checksum.", "La mise à jour n’a pas de somme de contrôle valide.", "La actualización no tiene una suma de comprobación válida.", "Das Update hat keine gültige Prüfsumme."))
        }
        let (temporary, response) = try await session.download(from: release.image)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try answered(response)
        guard try sha256(of: temporary) == expected else {
            throw UpdateError(tr("The update arrived damaged: it downloads again at the next check.", "La mise à jour est arrivée abîmée : elle se télécharge à nouveau à la prochaine vérification.", "La actualización llegó dañada: se vuelve a descargar en la próxima comprobación.", "Das Update kam beschädigt an: Es wird bei der nächsten Prüfung erneut geladen."))
        }
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: temporary, to: destination)
        try Data((expected + "\n").utf8).write(to: destination.appendingPathExtension("sha256"), options: .atomic)
    }

    /// Whether the disk image at IMAGE is the one that was downloaded: its
    /// SHA-256 is the one saved beside it.
    nonisolated static func verify(_ image: URL) throws -> Bool {
        let saved = try String(contentsOf: image.appendingPathExtension("sha256"), encoding: .utf8)
        guard let expected = BuilderReleases.checksum(in: saved) else { return false }
        return try sha256(of: image) == expected
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func answered(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError(tr("GitHub answered \(http.statusCode).", "GitHub a répondu \(http.statusCode).", "GitHub respondió \(http.statusCode).", "GitHub hat \(http.statusCode) geantwortet."))
        }
    }

    /// Removes the disk images of other versions.
    private func clean(keeping release: BuilderRelease?) {
        let keep = release.map { BuilderReleases.imageName($0.version) }
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            if let keep, name == keep || name == keep + ".sha256" { continue }
            try? manager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Installing

    public static var moveFirst: String {
        tr("Drag Cartouche to Applications and open it from there: it can then update itself.",
           "Glissez Cartouche dans Applications et ouvrez-le de là : il pourra alors se mettre à jour.",
           "Arrastra Cartouche a Aplicaciones y ábrelo desde allí: así podrá actualizarse solo.",
           "Zieh Cartouche in „Programme“ und öffne es von dort: Dann kann es sich selbst aktualisieren.")
    }

    /// Installs the update when nothing runs and no window is open, and
    /// opens the new version in the menu bar.
    func installIfIdle() async {
        guard automatic, isReady, !runsFromDiskImage, installsWithoutPassword, !isBuilding(), isIdle() else { return }
        _ = await install(relaunch: true, quietly: true)
    }

    /// Puts the downloaded update in place of the app. With RELAUNCH, the
    /// app quits and the new version opens (QUIETLY, in the menu bar only);
    /// without, the app is quitting. False when it could not.
    @discardableResult
    public func install(relaunch: Bool, quietly: Bool = false) async -> Bool {
        guard case let .ready(release) = state else { return false }
        guard !isBuilding() else {
            state = .failed(tr("A build is running: the update installs once it has ended.", "Une construction est en cours : la mise à jour s’installe une fois qu’elle est finie.", "Hay una compilación en curso: la actualización se instala cuando termine.", "Ein Build läuft: Das Update wird installiert, sobald er beendet ist."))
            return false
        }
        guard !runsFromDiskImage else {
            state = .failed(Self.moveFirst)
            return false
        }
        state = .installing
        do {
            let image = image(release)
            guard try Self.verify(image) else {
                clean(keeping: nil)
                throw UpdateError(tr("The downloaded update changed: it downloads again at the next check.", "La mise à jour téléchargée a changé : elle se télécharge à nouveau à la prochaine vérification.", "La actualización descargada ha cambiado: se vuelve a descargar en la próxima comprobación.", "Das geladene Update hat sich verändert: Es wird bei der nächsten Prüfung erneut geladen."))
            }
            try await Self.put(image, over: app, version: release.version, identifier: identifier)
        } catch {
            state = .failed(error.localizedDescription)
            failed?(error)
            return false
        }
        clean(keeping: nil)
        if relaunch {
            Self.openAgain(app, quietly: quietly)
            quit()
        }
        return true
    }

    /// Mounts IMAGE out of sight, checks the app in it and puts it in place
    /// of APP.
    nonisolated private static func put(_ image: URL, over app: URL, version: String, identifier: String) async throws {
        let attached = try await Run.program("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-plist",
                                                                 "-mountrandom", NSTemporaryDirectory(), image.path], timeout: 300)
        guard attached.succeeded,
              let plist = try? PropertyListSerialization.propertyList(from: attached.output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let point = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError(tr("The update’s disk image does not open: ", "L’image disque de la mise à jour ne s’ouvre pas : ", "La imagen de disco de la actualización no se abre: ", "Das Disk-Image des Updates lässt sich nicht öffnen: ") + attached.tail(2))
        }
        let mount = URL(fileURLWithPath: point, isDirectory: true)
        do {
            let found = try newApp(in: mount, named: app.lastPathComponent)
            try check(found, version: version, identifier: identifier)
            let signature = try await Run.program("/usr/bin/codesign", ["--verify", "--deep", "--strict", found.path], timeout: 300)
            guard signature.succeeded else {
                throw UpdateError(tr("The new version’s signature is not intact: ", "La signature de la nouvelle version n’est pas intacte : ", "La firma de la nueva versión no está intacta: ", "Die Signatur der neuen Version ist nicht intakt: ") + signature.tail(2))
            }
            try await replace(app, with: found)
        } catch {
            await detach(mount)
            throw error
        }
        await detach(mount)
    }

    nonisolated private static func detach(_ mount: URL) async {
        let detached = try? await Run.program("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"], timeout: 120)
        if detached?.succeeded != true {
            _ = try? await Run.program("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"], timeout: 120)
        }
    }

    nonisolated private static func newApp(in mount: URL, named name: String) throws -> URL {
        let manager = FileManager.default
        let named = mount.appendingPathComponent(name)
        if manager.fileExists(atPath: named.path) { return named }
        if let other = try manager.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) {
            return mount.appendingPathComponent(other)
        }
        throw UpdateError(tr("The update’s disk image has no app.", "L’image disque de la mise à jour n’a pas d’app.", "La imagen de disco de la actualización no contiene ninguna app.", "Das Disk-Image des Updates enthält keine App."))
    }

    /// The new app is Cartouche Builder, at the version its release names,
    /// for a macOS this Mac has.
    nonisolated static func check(_ found: URL, version: String, identifier: String) throws {
        let info = NSDictionary(contentsOf: found.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == identifier else {
            throw UpdateError(tr("The update’s app is not Cartouche.", "L’app de la mise à jour n’est pas Cartouche.", "La app de la actualización no es Cartouche.", "Die App des Updates ist nicht Cartouche."))
        }
        guard info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError(tr("The update’s app is not version \(version).", "L’app de la mise à jour n’est pas la version \(version).", "La app de la actualización no es la versión \(version).", "Die App des Updates ist nicht Version \(version)."))
        }
        if let minimum = info["LSMinimumSystemVersion"] as? String {
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let running = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
            if BuilderVersion.isHigher(minimum, than: running) {
                throw UpdateError(tr("Version \(version) needs macOS \(minimum): update the Mac first.",
                                     "La version \(version) demande macOS \(minimum) : mettez d’abord le Mac à jour.",
                                     "La versión \(version) necesita macOS \(minimum): actualiza primero el Mac.",
                                     "Version \(version) braucht macOS \(minimum): Aktualisiere zuerst den Mac."))
            }
        }
    }

    /// Copies FOUND beside APP, then swaps them; where the folder belongs to
    /// an administrator (Applications, for a standard account), macOS asks
    /// for the password.
    nonisolated private static func replace(_ app: URL, with found: URL) async throws {
        let manager = FileManager.default
        let parent = app.deletingLastPathComponent()
        let name = app.lastPathComponent
        let staged = parent.appendingPathComponent(".\(name).update")
        let old = parent.appendingPathComponent(".\(name).previous-\(UUID().uuidString.prefix(8))")
        if manager.isWritableFile(atPath: parent.path) {
            try? manager.removeItem(at: staged)
            let copied = try await Run.program("/usr/bin/ditto", [found.path, staged.path], timeout: 900)
            guard copied.succeeded else {
                try? manager.removeItem(at: staged)
                throw UpdateError(tr("The new version could not be copied: ", "La nouvelle version n’a pas pu être copiée : ", "No se pudo copiar la nueva versión: ", "Die neue Version konnte nicht kopiert werden: ") + copied.tail(2))
            }
            guard rename(app.path, old.path) == 0 else {
                let reason = String(cString: strerror(errno))
                try? manager.removeItem(at: staged)
                throw UpdateError(tr("The app could not be replaced: ", "L’app n’a pas pu être remplacée : ", "No se pudo sustituir la app: ", "Die App konnte nicht ersetzt werden: ") + reason)
            }
            guard rename(staged.path, app.path) == 0 else {
                let reason = String(cString: strerror(errno))
                _ = rename(old.path, app.path)
                try? manager.removeItem(at: staged)
                throw UpdateError(tr("The app could not be replaced: ", "L’app n’a pas pu être remplacée : ", "No se pudo sustituir la app: ", "Die App konnte nicht ersetzt werden: ") + reason)
            }
            try? manager.removeItem(at: old)
            return
        }
        let q = { (url: URL) in MacSetup.quoted(url.path) }
        let script = "set -e; /bin/rm -rf \(q(staged)); /usr/bin/ditto \(q(found)) \(q(staged)); /bin/mv \(q(app)) \(q(old)); "
            + "if ! /bin/mv \(q(staged)) \(q(app)); then /bin/mv \(q(old)) \(q(app)); exit 1; fi; /bin/rm -rf \(q(old))"
        let prompt = tr("Cartouche installs its update.", "Cartouche installe sa mise à jour.", "Cartouche instala su actualización.", "Cartouche installiert sein Update.")
        let command = "do shell script \"\(MacSetup.escaped(script))\" with prompt \"\(MacSetup.escaped(prompt))\" with administrator privileges"
        let result = try await Run.program("/usr/bin/osascript", ["-e", command], timeout: 900)
        guard result.succeeded else {
            let tail = result.tail(2)
            if tail.contains("-128") || tail.localizedCaseInsensitiveContains("User canceled") {
                throw UpdateError(tr("Cancelled: the update waits for the next time.", "Annulé : la mise à jour attend la prochaine fois.", "Cancelado: la actualización espera a la próxima vez.", "Abgebrochen: Das Update wartet auf das nächste Mal."))
            }
            throw UpdateError(tr("The app could not be replaced: ", "L’app n’a pas pu être remplacée : ", "No se pudo sustituir la app: ", "Die App konnte nicht ersetzt werden: ") + tail)
        }
    }

    /// Opens APP again once this process has ended.
    nonisolated private static func openAgain(_ app: URL, quietly: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let open = quietly ? "/usr/bin/open \"$2\" --args --background" : "/usr/bin/open \"$2\""
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.3; done; " + open,
                             "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
