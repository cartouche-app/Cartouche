//
//  ConsoleStorageTests.swift
//  CartoucheConsoleTests
//
//  The player's storage in the console on the Mac (ConsoleStorage.swift):
//  the connections a paired iPhone gives, as the app hands them over from
//  its bridge (JSON), kept on this Mac with their secrets in the Builder's
//  file, readable by the player only, never in the preferences, and the
//  Mac's given back, those removed on either side among them; the saves
//  folder of this Mac, which never goes to an iPhone, or the iPhone's on a
//  connection, followed when it is replaced or removed; the gallery's,
//  which nothing keeps; This Mac's folders as the player knows them; the
//  iPhone's games folder, as the Builder sends its games there; and a
//  folder chosen here, which goes to the app.
//  Each test has preferences and a secrets file of its own.
//

import Foundation
import XCTest
@testable import CartoucheConsole

@MainActor
final class ConsoleStorageTests: XCTestCase {
    private var folder: URL!
    private var suite: String!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("console-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "console-storage-\(UUID().uuidString)"
        CartoucheStorageSettings.keepSecrets(in: secrets)
    }

    override func tearDown() async throws {
        CartoucheStorageSettings.keepSecrets(in: nil)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The Builder's connections.json, as the app gives it.
    private var secrets: URL { folder.appendingPathComponent("connections.json") }

    /// This Mac's settings, as the console keeps them, read again from its
    /// preferences as the app does once it starts again.
    private func settings() -> CartoucheStorageSettings {
        CartoucheStorageSettings(defaults: UserDefaults(suiteName: suite)!, keepsInKeychain: false)
    }

    private func json(_ connections: [CartoucheConnection]) throws -> Data {
        try JSONEncoder().encode(connections)
    }

    private func connections(_ data: Data?) throws -> [CartoucheConnection] {
        try JSONDecoder().decode([CartoucheConnection].self, from: XCTUnwrap(data))
    }

    func testTheIPhonesConnectionsStayHereWithTheirSecretsInTheBuildersFile() throws {
        let nas = CartoucheConnection(id: UUID(), kind: "smb", name: "NAS du salon", host: "192.168.1.20", username: "joueur",
                                      share: "Jeux", secret: "mot de passe", changed: now)
        let bucket = CartoucheConnection(id: UUID(), kind: "s3", name: "Sauvegardes", host: "s3.eu-west-3.amazonaws.com",
                                         username: "AKIA", share: "saves", region: "eu-west-3", secret: "secret key", changed: now)
        let mac = settings()
        let given = try connections(CartoucheMacConsole.takeConnections(json([nas, bucket]), in: mac))

        // The Mac's, the same as the iPhone's now, their secrets with them.
        XCTAssertEqual(Set(given.map(\.id)), [nas.id, bucket.id])
        XCTAssertEqual(given.first { $0.id == nas.id }?.secret, "mot de passe")
        XCTAssertEqual(given.first { $0.id == bucket.id }?.secret, "secret key")
        XCTAssertEqual(mac.servers.map(\.name).sorted(), ["NAS du salon", "Sauvegardes"])
        XCTAssertEqual(mac.server(bucket.id)?.region, "eu-west-3")

        // The secrets in the Builder's file, which only the player reads,
        // and nowhere in the preferences.
        let attributes = try FileManager.default.attributesOfItem(atPath: secrets.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let file = try String(contentsOf: secrets, encoding: .utf8)
        XCTAssertTrue(file.contains("mot de passe") && file.contains("secret key"))
        let preferences = UserDefaults(suiteName: suite)!.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("Cartouche.") }
            .map { "\($0.value)" + String(decoding: ($0.value as? Data) ?? Data(), as: UTF8.self) }
            .joined()
        XCTAssertFalse(preferences.contains("mot de passe") || preferences.contains("secret key"))

        // As the app starts again: the same connections, their secrets
        // from the file.
        let again = settings()
        XCTAssertEqual(Set(again.servers.map(\.id)), [nas.id, bucket.id])
        XCTAssertEqual(again.server(nas.id).flatMap { again.secret(of: $0) }, "mot de passe")
    }

    func testWhatAnIPhoneRemovedGoesHereWithItsSecret() throws {
        let mac = settings()
        let old = CartoucheStorageServer(kind: .ftp, name: "Ancien", host: "192.168.1.30", username: "joueur", changed: now)
        mac.save(old, secret: "ancien mot de passe")
        XCTAssertEqual(mac.secret(of: old), "ancien mot de passe")

        var gone = CartoucheConnection(id: old.id, kind: "ftp", name: "Ancien", changed: Date().addingTimeInterval(60))
        gone.removed = true
        let given = try connections(CartoucheMacConsole.takeConnections(json([gone]), in: mac))

        XCTAssertTrue(mac.servers.isEmpty)
        XCTAssertNil(mac.secret(of: old))
        XCTAssertFalse(try String(contentsOf: secrets, encoding: .utf8).contains("ancien mot de passe"))
        // Given back as removed, for the other iPhones.
        XCTAssertEqual(given.map(\.id), [old.id])
        XCTAssertEqual(given.first?.removed, true)
        XCTAssertEqual(settings().removed.map(\.id), [old.id])
    }

    func testWhatIsNoListOfConnectionsChangesNothing() throws {
        let mac = settings()
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "joueur", share: "Jeux", changed: now)
        mac.save(nas, secret: "mot de passe")
        XCTAssertNil(CartoucheMacConsole.takeConnections(Data(#"{"servers": []}"#.utf8), in: mac))
        XCTAssertNil(CartoucheMacConsole.takeConnections(Data("not JSON".utf8), in: mac))
        XCTAssertEqual(mac.servers.map(\.id), [nas.id])
        XCTAssertEqual(mac.secret(of: nas), "mot de passe")
    }

    /// The saves folder the Builder keeps the games played here in step
    /// with is this Mac's alone: never given to an iPhone, never kept in
    /// the preferences, and still there once the iPhone's are taken.
    func testThisMacsSavesFolderStaysHere() throws {
        let mac = settings()
        mac.showMacSaves(name: "le NAS", path: "/Volumes/Partage/Cartouche/Saves")
        let nas = CartoucheConnection(id: UUID(), kind: "smb", name: "NAS", host: "192.168.1.2", username: "joueur", share: "Jeux",
                                      secret: "mot de passe", changed: now)
        let given = try connections(CartoucheMacConsole.takeConnections(json([nas]), in: mac))

        XCTAssertEqual(given.map(\.id), [nas.id])
        XCTAssertEqual(mac.servers.map(\.id), [CartoucheStorageSettings.macSavesID, nas.id])
        XCTAssertEqual(mac.place(.saves)?.path, "/Volumes/Partage/Cartouche/Saves")
        XCTAssertEqual(settings().servers.map(\.id), [nas.id])
    }

    /// The iPhone's saves folder on one of the connections, where the
    /// Builder keeps the saves of this Mac's games: shown as that
    /// connection's folder, as the iPhone shows it, never kept; a
    /// connection no longer there leaves the Mac's own.
    func testTheIPhonesSavesFolderOnAConnection() throws {
        let mac = settings()
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS du salon", host: "192.168.1.2", username: "joueur", share: "Jeux",
                                         changed: now)
        mac.save(nas, secret: "mot de passe")
        mac.showMacSaves(name: "NAS du salon", path: "Cartouche/Saves", connection: nas.id)
        XCTAssertEqual(mac.place(.saves), CartoucheStoragePlace(server: nas.id, path: "Cartouche/Saves"))
        XCTAssertEqual(mac.servers.map(\.id), [nas.id], "no folder of this Mac's beside it")
        XCTAssertTrue(mac.keepsMacSavesOnConnection)
        XCTAssertNil(settings().place(.saves))
        // Back to the Mac's own.
        mac.showMacSaves(name: "le dossier des sauvegardes", path: "/Users/Shared/Saves")
        XCTAssertEqual(mac.place(.saves)?.server, CartoucheStorageSettings.macSavesID)
        XCTAssertFalse(mac.keepsMacSavesOnConnection)
        // A connection this Mac does not have: its own folder, by its name.
        mac.showMacSaves(name: "le dossier des sauvegardes", path: "/Users/Shared/Saves", connection: UUID())
        XCTAssertEqual(mac.place(.saves)?.server, CartoucheStorageSettings.macSavesID)
        // None.
        mac.showMacSaves(name: nil, path: "")
        XCTAssertNil(mac.place(.saves))
    }

    func testTheIPhonesFolderFollowsItsConnectionReplacedOrRemoved() throws {
        let mac = settings()
        let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let nas = CartoucheConnection(id: UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000002")!, kind: "smb", name: "NAS",
                                      host: "192.168.1.2", username: "joueur", share: "Jeux", secret: "mot de passe", changed: now)
        mac.take([nas])
        XCTAssertEqual(CartoucheMacConsole.currentConnection(nas.id, in: mac), nas.id)
        // The same NAS added on an iPhone, under an ID that sorts first.
        var same = nas
        same.id = first
        same.changed = now + 60
        mac.take([same])
        XCTAssertEqual(CartoucheMacConsole.currentConnection(nas.id, in: mac), first)
        // Removed: none, nor for a connection never there.
        var removed = same
        removed.removed = true
        removed.changed = now + 120
        mac.take([removed])
        XCTAssertNil(CartoucheMacConsole.currentConnection(nas.id, in: mac))
        XCTAssertNil(CartoucheMacConsole.currentConnection(UUID(), in: mac))
    }

    /// The gallery's connections, kept in memory only: nothing of them in
    /// the preferences or in the Builder's file.
    func testTheGallerysConnectionsAreKeptNowhere() throws {
        let mac = settings()
        let drive = CartoucheStorageServer(kind: .drive, name: "Google Drive", host: "player@example.com",
                                           username: "123456789012-example.apps.googleusercontent.com", changed: now)
        mac.showForGallery([drive])
        mac.save(CartoucheStorageServer(kind: .sftp, name: "Serveur", host: "192.168.1.40", username: "joueur", changed: now),
                 secret: "mot de passe")
        XCTAssertEqual(mac.servers.map(\.name), ["Google Drive", "Serveur"])
        XCTAssertTrue(settings().servers.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secrets.path))
    }

    func testThisMacsFoldersAsThePlayerKnowsThem() {
        XCTAssertEqual(CartoucheMacFoldersSection.name(URL(fileURLWithPath: "/Volumes/Jeux", isDirectory: true)), "Jeux")
        XCTAssertEqual(CartoucheMacFoldersSection.name(URL(fileURLWithPath: "/Volumes/Partage/Cartouche/Saves/", isDirectory: true)),
                       "Partage › Cartouche › Saves")
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        XCTAssertEqual(CartoucheMacFoldersSection.name(home.appendingPathComponent("Jeux", isDirectory: true)), "~/Jeux")
        XCTAssertEqual(CartoucheMacFoldersSection.name(URL(fileURLWithPath: "/Users/Shared/Cartouche", isDirectory: true)),
                       "/Users/Shared/Cartouche")
    }

    func testTheConsoleShowsTheBuildersFolders() {
        let console = CartoucheMacConsole.shared
        let before = console.folders
        defer { console.showFolders(games: before.games, saves: before.saves) }
        let games = URL(fileURLWithPath: "/Volumes/Jeux", isDirectory: true)
        console.showFolders(games: games, saves: nil)
        XCTAssertEqual(console.folders, CartoucheMacFolders(games: games, saves: nil))
    }

    /// The iPhone's games folder on a connection, as the Builder sends its
    /// games there: what the app says, the file going or how many went, or
    /// none once the iPhone chose another place.
    func testTheConsoleShowsTheIPhonesGamesFolder() {
        let console = CartoucheMacConsole.shared
        let before = console.iPhoneGames
        defer { console.showIPhoneGames(before) }
        let nas = UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000002")!
        let going = CartoucheMacGamesFolder(connection: nas, path: "Cartouche/Jeux",
                                            state: .sending(game: "Mario Kart World", packing: false, done: 100, total: 300, index: 1, count: 2),
                                            offers: 1)
        console.showIPhoneGames(going)
        XCTAssertEqual(console.iPhoneGames, going)
        let sent = CartoucheMacGamesFolder(connection: nas, path: "Cartouche/Jeux", state: .sent(2, of: 2))
        console.showIPhoneGames(sent)
        XCTAssertEqual(console.iPhoneGames?.state, .sent(2, of: 2))
        XCTAssertEqual(console.iPhoneGames?.offers, 0)
        console.showIPhoneGames(nil)
        XCTAssertNil(console.iPhoneGames)
    }

    /// A folder chosen on the Storage page goes to the app, as JSON it
    /// reads with CartoucheCore's copy of the type.
    func testAFolderChosenHereGoesToTheApp() throws {
        let console = CartoucheMacConsole.shared
        let before = console.onChangeFolders
        defer { console.onChangeFolders = before }
        var given: [Data] = []
        console.onChangeFolders = { given.append($0) }
        let nas = UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000002")!
        console.changeFolders(.saves(connection: nas, path: "Cartouche/Sauvegardes"))
        console.changeFolders(.addGames(connection: nas, path: "Jeux"))
        XCTAssertEqual(try given.map { try JSONDecoder().decode(CartoucheChosenFolders.Change.self, from: $0) },
                       [.saves(connection: nas, path: "Cartouche/Sauvegardes"), .addGames(connection: nas, path: "Jeux")])
    }
}
