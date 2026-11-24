//
//  ConnectionsExchangeTests.swift
//  CartoucheStorageTests
//
//  The player's connections to their storage, as Cartouche gives them to
//  the Mac it is paired with and takes the Mac's (CartoucheStorageMac.swift,
//  CartoucheConnectionsExchange), the Mac played by the test (FakeMac,
//  MacBridgeTests.swift) as Cartouche Builder's console keeps them: both
//  end with the same, passwords and the key of an SFTP server included,
//  never the Mac's pairing nor a folder picked here; what the Mac removed
//  goes here with the folders chosen on it; the same NAS added on both
//  sides becomes one, the folders chosen on either kept on it; a change
//  made here meanwhile stays; a Mac too old to take them is left alone;
//  each change goes to the Mac a moment after it is made; the folders
//  chosen here go with them, on a connection the Mac has or on none, with
//  when they were chosen, and those chosen later on the Mac come back
//  here. The rule both
//  sides follow is tested on its own (launcher/Tests,
//  CartoucheConnectionsTests), the Mac's side in builder/mac's tests
//  (BridgeConnectionsTests). It needs no server, so it always runs.
//

import Foundation
import Network
import XCTest
@testable import CartoucheStorage

final class ConnectionsExchangeTests: XCTestCase {
    private var mac: FakeMac!
    private var suites: [String] = []

    override func setUp() async throws {
        mac = FakeMac()
        try await mac.start()
    }

    override func tearDown() async throws {
        mac.stop()
        for suite in suites {
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// Settings of their own, in preferences the test removes.
    private func settings() -> CartoucheStorageSettings {
        let suite = "ConnectionsExchangeTests." + UUID().uuidString
        suites.append(suite)
        return CartoucheStorageSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    /// The Mac, paired as the Storage page pairs it, in SETTINGS.
    private func pair(in settings: CartoucheStorageSettings) async throws -> CartoucheStorageServer {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(mac.port))!)
        let (server, secret) = try await CartoucheMacStorage.pair(CartoucheStorageServer(kind: .mac, name: ""), at: endpoint,
                                                                  name: "Mac de test", deviceName: "iPhone de test") { _ in }
        settings.save(server, secret: secret)
        return server
    }

    private func sorted(_ connections: [CartoucheConnection]?) -> [CartoucheConnection] {
        (connections ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Whether CONDITION holds within SECONDS.
    private func becomes(within seconds: TimeInterval = 15, _ condition: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await condition()
    }

    func testTheConnectionsGoToTheMacAndComeBack() async throws {
        let server = CartoucheConnection(id: UUID(), kind: "sftp", name: "Serveur", host: "server.example", port: 2222,
                                         username: "player", hostKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest",
                                         secret: "their password", changed: Date())
        mac.takeConnections([server])
        let settings = settings()
        let paired = try await pair(in: settings)
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "nas password")
        let folder = CartoucheStorageServer(kind: .folder, name: "Dossier", bookmark: Data([1, 2, 3]))
        settings.save(folder, secret: nil)

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(took)
        // The Mac has the NAS with its password, never its own pairing nor
        // the folder, which only this device opens.
        let given = mac.givenConnections
        XCTAssertEqual(given.map { $0.map(\.id) }, [[nas.id]])
        XCTAssertEqual(given.first?.first?.secret, "nas password")
        XCTAssertEqual(given.first?.first?.kind, "smb")
        XCTAssertEqual(Set(mac.keptConnections?.map(\.id) ?? []), [server.id, nas.id])
        // Here, the Mac's server with its password and the key it was
        // first reached with.
        let theirs = try XCTUnwrap(settings.server(server.id))
        XCTAssertEqual(theirs.kind, .sftp)
        XCTAssertEqual(theirs.name, "Serveur")
        XCTAssertEqual(theirs.host, "server.example")
        XCTAssertEqual(theirs.port, 2222)
        XCTAssertEqual(theirs.username, "player")
        XCTAssertEqual(theirs.hostKey, server.hostKey)
        XCTAssertEqual(theirs.changed, server.changed)
        XCTAssertEqual(settings.secret(of: theirs), "their password")
        XCTAssertEqual(settings.servers.map(\.id), [paired.id, nas.id, folder.id, server.id])
        // Both the same, to the second the player last changed each.
        XCTAssertEqual(sorted(settings.connections()), sorted(mac.keptConnections))

        // Again: nothing changes on either side.
        let before = settings.servers
        let again = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(again)
        XCTAssertEqual(settings.servers, before)
        XCTAssertEqual(sorted(settings.connections()), sorted(mac.keptConnections))
    }

    func testAMacTooOldToTakeThemIsLeftAlone() async throws {
        let settings = settings()
        let paired = try await pair(in: settings)
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "nas password")
        let before = settings.servers

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertFalse(took)
        // Its info says nothing of them: it is never asked, and its
        // session goes on as before.
        XCTAssertEqual(mac.givenConnections, [])
        XCTAssertEqual(settings.servers, before)
        XCTAssertEqual(settings.secret(of: nas), "nas password")
    }

    func testWhatTheMacRemovedGoesHereWithTheFoldersChosenOnIt() async throws {
        let settings = settings()
        let paired = try await pair(in: settings)
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "nas password")
        settings.setPlace(CartoucheStoragePlace(server: nas.id, path: "Jeux"), for: .games)
        settings.setPlace(CartoucheStoragePlace(server: nas.id, path: "Sauvegardes"), for: .saves)
        // Removed on the Mac after it was saved here.
        mac.takeConnections([CartoucheConnection(id: nas.id, kind: "smb", name: "NAS", changed: Date().addingTimeInterval(60),
                                                 removed: true)])

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(took)
        XCTAssertNil(settings.server(nas.id))
        XCTAssertNil(settings.place(.games))
        XCTAssertNil(settings.place(.saves))
        XCTAssertNil(settings.secret(of: nas), "its password goes with it")
        XCTAssertEqual(settings.servers.map(\.id), [paired.id], "the Mac stays paired")
        // Remembered, for another Mac that has not heard of it yet.
        XCTAssertEqual(settings.removed.map(\.id), [nas.id])
        XCTAssertEqual(settings.removed.first?.removed, true)
        XCTAssertEqual(sorted(settings.connections()), sorted(mac.keptConnections))
    }

    func testTheSameNASOnBothSidesBecomesOneWithTheFoldersChosenHere() async throws {
        let settings = settings()
        let paired = try await pair(in: settings)
        let here = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(here, secret: "old password")
        settings.setPlace(CartoucheStoragePlace(server: here.id, path: "Jeux"), for: .games)
        settings.setPlace(CartoucheStoragePlace(server: here.id, path: "Sauvegardes"), for: .saves)
        // The same NAS, added on the Mac since, under another name and an
        // ID that sorts first: the one both keep.
        let first = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        mac.takeConnections([CartoucheConnection(id: first, kind: "smb", name: "NAS du salon", host: " 192.168.1.2", username: "Player",
                                                 share: "games", secret: "new password", changed: Date().addingTimeInterval(60))])

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(took)
        XCTAssertEqual(settings.servers.filter(\.travels).map(\.id), [first])
        let kept = try XCTUnwrap(settings.server(first))
        XCTAssertEqual(kept.name, "NAS du salon", "as changed last")
        XCTAssertEqual(settings.secret(of: kept), "new password")
        XCTAssertNil(settings.server(here.id))
        XCTAssertNil(settings.secret(of: here))
        // The folders chosen here, on the one kept.
        XCTAssertEqual(settings.place(.games), CartoucheStoragePlace(server: first, path: "Jeux"))
        XCTAssertEqual(settings.place(.saves), CartoucheStoragePlace(server: first, path: "Sauvegardes"))
        XCTAssertEqual(settings.removed.map(\.id), [here.id])
        XCTAssertEqual(settings.removed.first?.replacedBy, first)
        XCTAssertEqual(sorted(settings.connections()), sorted(mac.keptConnections))
    }

    func testTheFoldersChosenHereGoToTheMacWithWhenTheyWereChosen() async throws {
        mac.takeConnections()
        let settings = settings()
        let paired = try await pair(in: settings)
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "nas password")
        let before = Date()
        settings.setPlace(CartoucheStoragePlace(server: nas.id, path: "Cartouche/Sauvegardes"), for: .saves)
        // The games on the Mac itself, through the bridge: on no
        // connection the Mac has, its own folder.
        settings.setPlace(CartoucheStoragePlace(server: paired.id, path: "Games"), for: .games)
        let after = Date()

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(took)
        let told = try XCTUnwrap(mac.toldFolders.last ?? nil)
        let saves = try XCTUnwrap(told.saves)
        XCTAssertEqual(saves.connection, nas.id)
        XCTAssertEqual(saves.path, "Cartouche/Sauvegardes")
        XCTAssertGreaterThanOrEqual(saves.chosen, before)
        XCTAssertLessThanOrEqual(saves.chosen, after)
        let games = try XCTUnwrap(told.games)
        XCTAssertNil(games.connection)
        XCTAssertEqual(games.path, "")

        // None chosen since: no folder, chosen later.
        settings.setPlace(nil, for: .saves)
        XCTAssertEqual(settings.chosenFolders().saves?.connection, nil)
        XCTAssertGreaterThan(try XCTUnwrap(settings.chosenFolders().saves?.chosen), saves.chosen)
        // Removing its connection chooses none too.
        settings.setPlace(CartoucheStoragePlace(server: nas.id, path: "Sauvegardes"), for: .saves)
        let chosenAgain = try XCTUnwrap(settings.chosenFolders().saves)
        settings.remove(nas)
        let removed = try XCTUnwrap(settings.chosenFolders().saves)
        XCTAssertNil(removed.connection)
        XCTAssertGreaterThanOrEqual(removed.chosen, chosenAgain.chosen)
    }

    /// The player chose, on the Mac's console, folders of the NAS for the
    /// games and the saves, after the Mac's own folders here: the exchange
    /// brings the NAS and the folders, the Mac's own staying among the
    /// games folders. Chosen here later still, they go to the Mac, which
    /// keeps them and gives them back.
    func testTheFoldersChosenLaterOnTheMacComeHere() async throws {
        let nas = CartoucheConnection(id: UUID(), kind: "smb", name: "NAS", host: "192.168.1.2", username: "player", share: "Games",
                                      secret: "nas password", changed: Date())
        mac.takeConnections([nas])
        let settings = settings()
        let paired = try await pair(in: settings)
        settings.setPlace(CartoucheStoragePlace(server: paired.id, path: "Games"), for: .games)
        settings.setPlace(CartoucheStoragePlace(server: paired.id, path: "Saves"), for: .saves)
        let onMac = Date().addingTimeInterval(0.001)
        mac.keepFolders(CartoucheChosenFolders(games: .init(connection: nas.id, path: "Cartouche/Jeux", chosen: onMac),
                                               saves: .init(connection: nas.id, path: "Cartouche/Sauvegardes", chosen: onMac)))

        let took = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(took)
        XCTAssertEqual(settings.place(.games), CartoucheStoragePlace(server: nas.id, path: "Cartouche/Jeux"))
        XCTAssertEqual(settings.otherGames, [CartoucheStoragePlace(server: paired.id, path: "Games")], "the Mac's own, read too")
        XCTAssertEqual(settings.place(.saves), CartoucheStoragePlace(server: nas.id, path: "Cartouche/Sauvegardes"))
        XCTAssertEqual(settings.chosen[.saves], onMac)
        XCTAssertEqual(mac.keptFolders?.saves?.path, "Cartouche/Sauvegardes", "the iPhone's, older, left it")

        // Chosen here since: the Mac takes it, and gives it back.
        try await Task.sleep(nanoseconds: 10_000_000)
        settings.setPlace(CartoucheStoragePlace(server: nas.id, path: "Autres"), for: .saves)
        let again = await CartoucheConnectionsExchange.exchange(with: paired, settings: settings)
        XCTAssertTrue(again)
        XCTAssertEqual(mac.keptFolders?.saves?.path, "Autres")
        XCTAssertEqual(settings.place(.saves), CartoucheStoragePlace(server: nas.id, path: "Autres"))
        XCTAssertEqual(settings.place(.games), CartoucheStoragePlace(server: nas.id, path: "Cartouche/Jeux"))
    }

    func testAFolderAnOlderCartoucheChoseGoesAsChosenLongAgo() throws {
        let suite = "ConnectionsExchangeTests." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games",
                                         changed: Date())
        defaults.set(try JSONEncoder().encode([nas]), forKey: "Cartouche.storage.servers")
        defaults.set(try JSONEncoder().encode(CartoucheStoragePlace(server: nas.id, path: "Saves")), forKey: "Cartouche.storage.saves")
        let told = CartoucheStorageSettings(defaults: defaults).chosenFolders()
        XCTAssertEqual(told.saves, CartoucheChosenFolders.Folder(connection: nas.id, path: "Saves", chosen: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(told.games, "nothing chosen, nothing told")
    }

    func testAChangeMadeHereMeanwhileStays() throws {
        let settings = settings()
        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "password")
        let saved = try XCTUnwrap(settings.server(nas.id)?.changed)
        // The Mac's, changed before this one.
        var older = nas.connection(secret: "older password")
        older.name = "Ancien nom"
        older.changed = saved.addingTimeInterval(-60)
        XCTAssertFalse(settings.take([older]))
        XCTAssertEqual(settings.server(nas.id)?.name, "NAS")
        XCTAssertEqual(settings.server(nas.id)?.changed, saved)
        XCTAssertEqual(settings.secret(of: nas), "password")
        // Changed after: it wins, and the password it does not give stays.
        var newer = older
        newer.name = "Nouveau nom"
        newer.secret = nil
        newer.changed = saved.addingTimeInterval(60)
        XCTAssertTrue(settings.take([newer]))
        XCTAssertEqual(settings.server(nas.id)?.name, "Nouveau nom")
        XCTAssertEqual(settings.server(nas.id)?.changed, newer.changed)
        XCTAssertEqual(settings.secret(of: nas), "password")
    }

    func testTheServersAnOlderCartoucheKeptAreDatedOnce() throws {
        let suite = "ConnectionsExchangeTests." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let old = CartoucheStorageServer(kind: .ftp, name: "FTP", host: "192.168.1.3", username: "player")
        XCTAssertNil(old.changed)
        defaults.set(try JSONEncoder().encode([old]), forKey: "Cartouche.storage.servers")
        let started = Date()
        let dated = try XCTUnwrap(CartoucheStorageSettings(defaults: defaults).server(old.id)?.changed)
        XCTAssertGreaterThanOrEqual(dated, started)
        XCTAssertLessThan(dated.timeIntervalSince(started), 5)
        // Kept so: the same date when Cartouche starts again.
        XCTAssertEqual(CartoucheStorageSettings(defaults: defaults).server(old.id)?.changed, dated)
    }

    func testEachChangeGoesToTheMacAMomentAfter() async throws {
        mac.takeConnections()
        let settings = settings()
        let paired = try await pair(in: settings)
        let exchange = await MainActor.run { () -> CartoucheConnectionsExchange in
            let exchange = CartoucheConnectionsExchange(settings: settings)
            exchange.start()
            return exchange
        }
        // The pairing itself goes nowhere: it is no connection.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(mac.givenConnections, [])

        let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "player", share: "Games")
        settings.save(nas, secret: "nas password")
        let s3 = CartoucheStorageServer(kind: .s3, name: "Bucket", host: "s3.eu-west-3.amazonaws.com", username: "AKIA", share: "saves")
        settings.save(s3, secret: "secret key")
        // Both, in one exchange a moment after the last.
        let gone = await becomes { await MainActor.run { !exchange.isExchanging } && mac.givenConnections.count == 1 }
        XCTAssertTrue(gone)
        XCTAssertEqual(mac.givenConnections.first.map { Set($0.map(\.id)) }, [nas.id, s3.id])
        let last = await MainActor.run { exchange.last[paired.id] }
        XCTAssertNotNil(last)
        // What it took from the Mac is no change of the player's: nothing
        // goes back.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(mac.givenConnections.count, 1)

        // Removed here: the Mac hears of it.
        settings.remove(s3)
        let removed = await becomes { mac.givenConnections.count == 2 }
        XCTAssertTrue(removed)
        XCTAssertEqual(mac.keptConnections?.first { $0.id == s3.id }?.removed, true)

        // Cartouche coming to the front, within ten minutes of the last
        // exchange and after them.
        await MainActor.run { exchange.cameForward(now: Date()) }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(mac.givenConnections.count, 2)
        await MainActor.run { exchange.cameForward(now: Date().addingTimeInterval(CartoucheConnectionsExchange.interval + 1)) }
        let cameForward = await becomes { mac.givenConnections.count == 3 }
        XCTAssertTrue(cameForward)
    }
}
