//
//  ConnectionGamesTests.swift
//  BuilderKitTests
//
//  The iPhone's games folder on one of the player's connections, as the
//  Builder sends its games there and the console installs from there the
//  Mac apps another Mac sent (ConnectionGames.swift): what goes and what
//  stays, in which order; what went and was removed there since; a Mac app
//  packed first, once for each build; the Mac apps of another Mac, by
//  their names; a round that stops for a folder this Mac cannot write to,
//  without room, or away, or before the next file once a batch starts; the
//  library's games as the files that go; and where the console says the
//  games to install are; the Mac apps of several folders, a game in more
//  than one once, from one that answers. The console's side, the iPhone's
//  code, is tested with Cartouche's storage (launcher/StorageTests).
//

import Foundation
import XCTest
@testable import BuilderKit

/// The console, as the app drives it: the folder's files, in memory.
private final class Folder: ConnectionGamesDriver, @unchecked Sendable {
    let connection = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!
    let path = "Cartouche/Jeux"
    var stored: [String: (data: Data, modified: Date)] = [:]
    var free: UInt64? = 1 << 40
    var writable = true
    var away = false
    var failing: Error?
    var sentNames: [String] = []
    var now = Date(timeIntervalSince1970: 1_794_506_520)

    func files() async throws -> [ConnectionFile] {
        if away { throw ConnectionGamesError.offline }
        return stored.map { ConnectionFile(name: $0.key, size: UInt64($0.value.data.count), modified: $0.value.modified) }
            .sorted { $0.name < $1.name }
    }

    func room() async throws -> UInt64? { free }

    func canWrite() async throws -> Bool { writable }

    func send(_ file: URL, as name: String, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        if let failing { throw failing }
        let data = try Data(contentsOf: file)
        progress(UInt64(data.count))
        stored[name] = (data, now)
        sentNames.append(name)
    }

    func fetch(_ name: String, to file: URL, progress: @escaping @Sendable (UInt64) -> Void) async throws {
        if let failing { throw failing }
        guard let kept = stored[name] else { throw CocoaError(.fileNoSuchFile) }
        try kept.data.write(to: file)
        progress(UInt64(kept.data.count))
    }
}

final class ConnectionGamesTests: XCTestCase {
    private var root: URL!
    private let mkw = "0100152000022000"
    private let odyssey = "0100000000010000"
    private let t0 = Date(timeIntervalSince1970: 1_794_506_520)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("connection-games-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A file of the Builder's games folder, of SIZE bytes.
    private func local(_ name: String, size: Int) throws -> URL {
        let url = root.appendingPathComponent("Jeux", isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: size).write(to: url)
        return url
    }

    private func ipa(_ titleID: String, _ game: String, size: UInt64, built: Date, build: String? = nil) -> GameToSend {
        GameToSend(titleID: titleID, game: game, kind: .ipa, url: URL(fileURLWithPath: "/Volumes/Jeux/\(game) [\(titleID)].ipa"),
                   size: size, modified: built, build: build)
    }

    private func macFile(_ titleID: String, _ game: String, size: UInt64, built: Date) -> GameToSend {
        GameToSend(titleID: titleID, game: game, kind: .macFile, url: URL(fileURLWithPath: "/Volumes/Jeux/\(game) [\(titleID)].app.zip"),
                   size: size, modified: built)
    }

    private func macApp(_ titleID: String, _ game: String, built: Date, build: String) -> GameToSend {
        GameToSend(titleID: titleID, game: game, kind: .macApp, url: URL(fileURLWithPath: "/Users/joueur/Jeux/\(game).app", isDirectory: true),
                   size: 4_000, modified: built, build: build)
    }

    func testWhatGoesIsWhatTheFolderLacksOrHoldsOlderTheNewestFirst() {
        let kart = ipa(mkw, "Mario Kart World", size: 100, built: t0)
        let kartMac = macFile(mkw, "Mario Kart World", size: 50, built: t0)
        let cap = ipa(odyssey, "Super Mario Odyssey", size: 200, built: t0 + 3_600)
        // The same IPA there: the Builder's own games folder on the share.
        var there = [ConnectionFile(name: "Mario Kart World [\(mkw)].ipa", size: 100, modified: t0 + 60)]
        // Its Mac app there, older.
        there.append(ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 40, modified: t0 - 60))
        XCTAssertEqual(ConnectionGames.due([kart, kartMac, cap], there: there, sent: [:]), [cap, kartMac])
        // A newer one there, another Mac's: it stays.
        there[1].modified = t0 + 60
        XCTAssertEqual(ConnectionGames.due([kart, kartMac, cap], there: there, sent: [:]), [cap])
        // A server that does not say when: the Builder's goes.
        there[1].modified = nil
        XCTAssertEqual(ConnectionGames.due([kart, kartMac, cap], there: there, sent: [:]), [cap, kartMac])
        // The same build first as an IPA, then as a Mac app.
        let both = [macFile(odyssey, "Super Mario Odyssey", size: 60, built: t0), ipa(odyssey, "Super Mario Odyssey", size: 200, built: t0)]
        XCTAssertEqual(ConnectionGames.due(both, there: [], sent: [:]).map(\.kind), [.ipa, .macFile])
    }

    func testABuildThatWentAndWasRemovedThereStaysRemoved() {
        let kart = ipa(mkw, "Mario Kart World", size: 100, built: t0, build: "a1b2c3|2026-11-17")
        let went = SentApp(build: kart.build, file: ConnectionFile(name: "Mario Kart World [\(mkw)].ipa", size: 100, modified: t0 + 60))
        XCTAssertEqual(ConnectionGames.due([kart], there: [], sent: [kart.sentKey: went]), [], "removed there by the player")
        // Its next build goes.
        let next = ipa(mkw, "Mario Kart World", size: 120, built: t0 + 86_400, build: "d4e5f6|2026-11-18")
        XCTAssertEqual(ConnectionGames.due([next], there: [], sent: [kart.sentKey: went]), [next])
        // A file there already, the same, is recorded as gone: once removed
        // there, it stays removed.
        let there = [ConnectionFile(name: "Mario Kart World [\(mkw)].ipa", size: 120, modified: t0)]
        XCTAssertEqual(ConnectionGames.there([next], in: there, sent: [:]),
                       [next.sentKey: SentApp(build: next.build, file: there[0])])
        XCTAssertEqual(ConnectionGames.there([next], in: there, sent: [next.sentKey: SentApp(build: next.build, file: there[0])]), [:])
    }

    func testAMacAppKeptAsItIsGoesPackedOnceForEachBuild() {
        let app = macApp(mkw, "Mario Kart World", built: t0, build: "a1b2c3")
        XCTAssertEqual(ConnectionGames.due([app], there: [], sent: [:]), [app])
        // Packed and sent, an hour after it was built.
        let file = ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 3_000, modified: t0 + 3_600)
        let went = [app.sentKey: SentApp(build: "a1b2c3", file: file)]
        XCTAssertEqual(ConnectionGames.due([app], there: [file], sent: went), [])
        // Built again meanwhile: the file there is the one that went, of
        // the older build, whatever its date.
        let next = macApp(mkw, "Mario Kart World", built: t0 + 1_800, build: "d4e5f6")
        XCTAssertEqual(ConnectionGames.due([next], there: [file], sent: went), [next])
        // Another Mac's, newer, in its place: it stays; older, it goes.
        let theirs = ConnectionFile(name: file.name, size: 3_300, modified: t0 + 7_200)
        XCTAssertEqual(ConnectionGames.due([next], there: [theirs], sent: went), [])
        let older = ConnectionFile(name: file.name, size: 3_300, modified: t0)
        XCTAssertEqual(ConnectionGames.due([next], there: [older], sent: went), [next])
        // None went from here: another Mac's of the game, newer, stays.
        XCTAssertEqual(ConnectionGames.due([next], there: [theirs], sent: [:]), [])
    }

    func testTheMacAppsAnotherMacSentByTheirNames() {
        XCTAssertEqual(ConnectionGames.titleID(inName: "Mario Kart World [0100152000022000].app.zip"), mkw)
        XCTAssertEqual(ConnectionGames.titleID(inName: "Mario Kart World [0100152000022000].APP.ZIP"), mkw)
        XCTAssertNil(ConnectionGames.titleID(inName: "Mario Kart World [0100152000022000].ipa"))
        XCTAssertNil(ConnectionGames.titleID(inName: "Mario Kart World.app.zip"))
        XCTAssertNil(ConnectionGames.titleID(inName: "Mario Kart World [v1.2].app.zip"))
        XCTAssertEqual(ConnectionGames.gameName(of: "Mario Kart World [0100152000022000].app.zip"), "Mario Kart World")
        XCTAssertEqual(ConnectionGames.gameName(of: "Odyssey.app.zip"), "Odyssey")
        let there = [
            ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 3_000, modified: t0),
            ConnectionFile(name: "MKW [\(mkw)].app.zip", size: 3_100, modified: t0 + 60),
            ConnectionFile(name: "Super Mario Odyssey [\(odyssey)].app.zip", size: 2_000, modified: t0),
            ConnectionFile(name: "Super Mario Odyssey [\(odyssey)].ipa", size: 5_000, modified: t0),
            ConnectionFile(name: "romfs.img", size: 9_000, modified: t0),
        ]
        XCTAssertEqual(ConnectionGames.macApps(in: there, known: []),
                       [ConnectionMacApp(titleID: mkw, game: "MKW", file: there[1]),
                        ConnectionMacApp(titleID: odyssey, game: "Super Mario Odyssey", file: there[2])])
        // A game this Mac has an app of is none of another Mac's.
        XCTAssertEqual(ConnectionGames.macApps(in: there, known: [mkw]).map(\.titleID), [odyssey])
    }

    /// The iPhone reads a NAS's games folder and a Google Drive's: a game
    /// in both is offered once, from the one that answers, then the newer
    /// file, then the first; each copy in the order to try them.
    func testTheMacAppsOfSeveralFoldersOnceFromOneThatAnswers() {
        let nas = "nas|Jeux", drive = "drive|Jeux"
        let nasFile = ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 3_000, modified: t0 + 60)
        let driveFile = ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 2_900, modified: t0)
        let odysseyFile = ConnectionFile(name: "Super Mario Odyssey [\(odyssey)].app.zip", size: 2_000, modified: t0)
        var looks = [ConnectionGamesLook(place: nas, files: [nasFile], answered: true),
                     ConnectionGamesLook(place: drive, files: [driveFile, odysseyFile], answered: true)]
        XCTAssertEqual(ConnectionGames.macApps(in: looks, known: []),
                       [ConnectionMacApp(titleID: mkw, game: "Mario Kart World", file: nasFile, place: nas),
                        ConnectionMacApp(titleID: odyssey, game: "Super Mario Odyssey", file: odysseyFile, place: drive)],
                       "the newer file")
        XCTAssertEqual(ConnectionGames.copies(of: mkw, in: looks).map(\.place), [nas, drive])
        // The NAS away from home: the Drive's, older, which answers.
        looks[0].answered = false
        XCTAssertEqual(ConnectionGames.macApps(in: looks, known: []).first?.place, drive)
        XCTAssertEqual(ConnectionGames.copies(of: mkw, in: looks).map(\.place), [drive, nas])
        // Only in the folder that does not answer: offered from there still.
        XCTAssertEqual(ConnectionGames.macApps(in: [looks[0]], known: []).map(\.place), [nas])
        // The same file in both: the first folder's.
        looks = [ConnectionGamesLook(place: nas, files: [driveFile], answered: true),
                 ConnectionGamesLook(place: drive, files: [driveFile], answered: true)]
        XCTAssertEqual(ConnectionGames.macApps(in: looks, known: []).map(\.place), [nas])
        XCTAssertEqual(ConnectionGames.macApps(in: looks, known: [mkw]), [])
    }

    func testAnAppInstalledFromThereIsMadeAgainOfANewerFile() {
        let file = ConnectionFile(name: "Mario Kart World [\(mkw)].app.zip", size: 3_000, modified: t0)
        let fetched = FetchedApp(titleID: mkw, place: "x", file: file, app: "/Applications/Mario Kart World.app", installed: t0 + 60)
        XCTAssertNil(ConnectionGames.newer(for: fetched, in: [file]))
        XCTAssertNil(ConnectionGames.newer(for: fetched, in: []))
        let newer = ConnectionFile(name: file.name, size: 3_200, modified: t0 + 86_400)
        XCTAssertEqual(ConnectionGames.newer(for: fetched, in: [newer])?.file, newer)
        let older = ConnectionFile(name: file.name, size: 2_900, modified: t0 - 60)
        XCTAssertNil(ConnectionGames.newer(for: fetched, in: [older]))
    }

    func testARoundSendsWhatIsDueAndStopsWhereItMust() async throws {
        let folder = Folder()
        let store = ConnectionGamesStore(url: root.appendingPathComponent("connection-games.json"))
        let packedInto = root.appendingPathComponent("Packed", isDirectory: true)
        let sender = ConnectionGamesSender(driver: folder, store: store) { game in
            try FileManager.default.createDirectory(at: packedInto, withIntermediateDirectories: true)
            let file = packedInto.appendingPathComponent("\(game.game) [\(game.titleID)].app.zip")
            try Data(repeating: 1, count: 300).write(to: file)
            return file
        }
        let kartFile = try local("Mario Kart World [\(mkw)].ipa", size: 100)
        let kart = GameToSend(titleID: mkw, game: "Mario Kart World", kind: .ipa, url: kartFile, size: 100, modified: t0)
        let cap = macApp(odyssey, "Super Mario Odyssey", built: t0 + 60, build: "a1b2c3")
        let report = await sender.send([kart, cap])
        XCTAssertNil(report.stopped)
        XCTAssertNil(report.failure)
        XCTAssertEqual(report.sent.map { $0.game }, [cap, kart])
        XCTAssertEqual(report.left, 0)
        XCTAssertEqual(folder.sentNames, ["Super Mario Odyssey [\(odyssey)].app.zip", "Mario Kart World [\(mkw)].ipa"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: packedInto.path), [], "the packed file goes once sent")
        XCTAssertEqual(store.sent(to: folder.place)[cap.sentKey]?.build, "a1b2c3")
        // Nothing more goes; the player removes the Mac app there.
        folder.stored["Super Mario Odyssey [\(odyssey)].app.zip"] = nil
        let again = await sender.send([kart, cap])
        XCTAssertEqual(again.sent.count, 0)
        XCTAssertEqual(again.files?.map(\.name), ["Mario Kart World [\(mkw)].ipa"])

        // A new build, to a folder this account may not write to, then
        // without room, then away: nothing goes, and it says why.
        let next = macApp(odyssey, "Super Mario Odyssey", built: t0 + 86_400, build: "d4e5f6")
        folder.writable = false
        let readOnly = await sender.send([next])
        XCTAssertEqual(readOnly.stopped, .readOnly)
        XCTAssertEqual(readOnly.left, 1)
        folder.writable = true
        folder.free = 100
        let full = await sender.send([next])
        XCTAssertEqual(full.stopped, .noRoom(needed: 300 + ConnectionGames.margin, free: 100))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: packedInto.path), [])
        folder.free = nil
        folder.away = true
        let away = await sender.send([next])
        XCTAssertEqual(away.stopped, .offline)
        XCTAssertNil(away.files)
        // A failure stops the round, said in the player's words.
        folder.away = false
        folder.failing = CocoaError(.fileWriteUnknown)
        let failed = await sender.send([next])
        XCTAssertNotNil(failed.failure)
        XCTAssertEqual(failed.left, 1)
        folder.failing = nil
        let sent = await sender.send([next])
        XCTAssertEqual(sent.sent.map { $0.game }, [next])
    }

    func testARoundAskedToStopEndsTheFileGoingFirst() async throws {
        let folder = Folder()
        let store = ConnectionGamesStore(url: root.appendingPathComponent("connection-games.json"))
        let sender = ConnectionGamesSender(driver: folder, store: store) { _ in throw CocoaError(.featureUnsupported) }
        let kart = GameToSend(titleID: mkw, game: "Mario Kart World", kind: .ipa,
                              url: try local("Mario Kart World [\(mkw)].ipa", size: 100), size: 100, modified: t0 + 60)
        let cap = GameToSend(titleID: odyssey, game: "Super Mario Odyssey", kind: .ipa,
                             url: try local("Super Mario Odyssey [\(odyssey)].ipa", size: 200), size: 200, modified: t0)
        // A batch starts while the first file goes.
        let report = await sender.send([kart, cap], stop: { !folder.sentNames.isEmpty })
        XCTAssertEqual(folder.sentNames, ["Mario Kart World [\(mkw)].ipa"])
        XCTAssertEqual(report.sent.map { $0.game }, [kart])
        XCTAssertEqual(report.left, 1)
        XCTAssertNil(report.stopped)
        // The next round, once it ends, sends the rest.
        let next = await sender.send([kart, cap])
        XCTAssertEqual(next.sent.map { $0.game }, [cap])
        XCTAssertEqual(next.left, 0)
    }

    func testTheLibrarysGamesGoAsTheirFiles() throws {
        let built = ISODate.parse("2026-11-13T21:49:05+00:00")
        let kept = try JSONDecoder().decode(Library.self, from: Data(contentsOf: Self.fixture("library")))
        let files = ConnectionGames.toSend(kept.games) { _ in self.t0 }
        // Each IPA by its build; the app the games folder keeps as it is on
        // this Mac's disk, to pack, by its build and its date.
        XCTAssertEqual(files.map(\.kind), [.ipa, .ipa, .ipa, .macApp])
        XCTAssertEqual(files.map(\.fileName), ["Hollow Knight [0100A0000E2F0000].ipa", "Mario Kart World [0400C3F00006E000].ipa",
                                                "Super Mario Odyssey [0100000000010000].ipa", nil])
        XCTAssertEqual(files[0].build, "000000000000|2026-11-09T21:15:52+00:00")
        XCTAssertEqual(files[0].modified, t0)
        XCTAssertEqual(files[3].titleID, odyssey)
        XCTAssertEqual(files[3].url.path, "/Users/player/Builder/games/Super Mario Odyssey.app")
        XCTAssertEqual(files[3].size, 1604)
        XCTAssertEqual(files[3].build, "387149ac481b|2026-11-13T21:49:05+00:00")
        XCTAssertEqual(files[3].modified, built)
        // A NAS's games folder keeps each app in one file, which goes as it
        // is; one it does not have yet goes not.
        let nas = try JSONDecoder().decode(Library.self, from: Data(contentsOf: Self.fixture("library-nas")))
        let onNAS = ConnectionGames.toSend(nas.games) { _ in self.t0 }
        XCTAssertEqual(onNAS.map(\.kind), [.ipa, .ipa, .macFile, .ipa])
        XCTAssertEqual(onNAS[2].fileName, "Mario Kart World [0400C3F00006E000].app.zip")
        XCTAssertEqual(onNAS[2].size, 2915)
        XCTAssertEqual(onNAS[2].build, "04354859e955|2026-11-13T21:49:11+00:00")
        XCTAssertEqual(onNAS[2].sentKey, "0400C3F00006E000|mac")
    }

    func testTheConsoleSaysWhereTheGamesToInstallAre() {
        defer { L10n.use("") }
        L10n.use("fr")
        // And why an install from there stopped, in the player's words.
        XCTAssertEqual(ConnectionGamesError.readOnly.localizedDescription, "Votre compte ne peut que lire le dossier des jeux de l’iPhone.")
        XCTAssertTrue(ConnectionGamesError.noRoom(needed: 3_000_000_000, free: 1_000_000_000).localizedDescription.hasPrefix("Pas assez de place : "))
        XCTAssertEqual(ConnectionGames.shownPlace(kept: "le NAS", offers: nil), "le NAS")
        XCTAssertEqual(ConnectionGames.shownPlace(kept: nil, offers: "Bucket S3"), "Bucket S3")
        XCTAssertEqual(ConnectionGames.shownPlace(kept: "Bucket S3", offers: "Bucket S3"), "Bucket S3")
        XCTAssertEqual(ConnectionGames.shownPlace(kept: "le NAS", offers: "Bucket S3"), "vos dossiers de jeux")
        XCTAssertEqual(ConnectionGames.shownPlace(kept: nil, offers: nil), "le dossier des jeux")
        L10n.use("en")
        XCTAssertEqual(ConnectionGames.shownPlace(kept: "the NAS", offers: "S3 bucket"), "your games folders")
    }

    /// The engine's answer NAME, as the app's contract test wrote it.
    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json")
    }

    func testAMacAppFetchedFromThereIsWholeOrNothing() async throws {
        let folder = Folder()
        let store = ConnectionGamesStore(url: root.appendingPathComponent("connection-games.json"))
        let sender = ConnectionGamesSender(driver: folder, store: store) { _ in throw CocoaError(.featureUnsupported) }
        let name = "Super Mario Odyssey [\(odyssey)].app.zip"
        folder.stored[name] = (Data(repeating: 3, count: 500), t0)
        let app = ConnectionMacApp(titleID: odyssey, game: "Super Mario Odyssey", file: ConnectionFile(name: name, size: 500, modified: t0))
        let into = root.appendingPathComponent("Fetched", isDirectory: true)
        let file = try await sender.fetch(app, into: into)
        XCTAssertEqual(try Data(contentsOf: file).count, 500)
        sender.installed(app, at: "/Applications/Super Mario Odyssey.app", now: t0 + 60)
        XCTAssertEqual(store.fetched[odyssey]?.file, app.file)
        XCTAssertEqual(store.fetched[odyssey]?.place, folder.place)
        // Kept across launches.
        let reopened = ConnectionGamesStore(url: root.appendingPathComponent("connection-games.json"))
        XCTAssertEqual(reopened.fetched[odyssey]?.app, "/Applications/Super Mario Odyssey.app")
        // A failed fetch leaves nothing.
        try FileManager.default.removeItem(at: file)
        folder.failing = CocoaError(.fileReadUnknown)
        do {
            _ = try await sender.fetch(app, into: into)
            XCTFail("the fetch should fail")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: into.path), [])
    }
}
