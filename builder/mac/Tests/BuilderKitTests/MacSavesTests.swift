//
//  MacSavesTests.swift
//  BuilderKitTests
//
//  A game's saves on this Mac kept in step with their copies in the saves
//  folder (MacSaves.swift), with the iPhone's own code on the other side:
//  its copies are made and read as Cartouche makes and reads them
//  (CartoucheSaveSync), in folders of the tests' own.
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

final class MacSavesTests: XCTestCase {
    private var root: URL!
    private let game = MacSaveGame(titleID: "0100152000022000", name: "Mario Kart 8 Deluxe")
    /// When the tests' games saved first: 12 November 2026, 18:02:00 UTC, in
    /// the past (a copy is never named after now).
    private let t0 = Date(timeIntervalSince1970: 1_794_506_520)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-saves-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: The world

    private var saves: URL { root.appendingPathComponent("Saves", isDirectory: true) }

    private func makeFolder(_ saves: URL? = nil) throws -> MacSavesFolder {
        let saves = saves ?? self.saves
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        return MacSavesFolder(root: saves, games: root.appendingPathComponent("nxnative", isDirectory: true),
                              scratch: root.appendingPathComponent("scratch", isDirectory: true))
    }

    /// The game's saves in DOCUMENTS, as the game writes them: FILES under
    /// save/ (or save_device/ for a path that starts with it), last written
    /// at DATE.
    private func write(_ files: [String: String], in documents: URL, at date: Date) throws {
        for folder in CartoucheSaveSync.folders {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(folder))
        }
        for (path, text) in files {
            let relative = path.hasPrefix("save_device/") ? path : "save/" + path
            let url = documents.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    /// What the saves in DOCUMENTS hold, by path.
    private func read(_ documents: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        for folder in CartoucheSaveSync.folders {
            let top = documents.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(atPath: top.path) else { continue }
            while let relative = walker.nextObject() as? String {
                let url = top.appendingPathComponent(relative)
                var isFolder: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue {
                    files[folder + "/" + relative] = try String(contentsOf: url, encoding: .utf8)
                }
            }
        }
        return files
    }

    /// A copy of the saves in DOCUMENTS, made as Cartouche makes one on the
    /// iPhone, named NAME in the game's folder of SAVES, by VERSION of the
    /// game.
    @discardableResult
    private func iPhoneCopy(of documents: URL, named name: String, folder: String? = nil, in saves: URL? = nil,
                            version: String? = nil) async throws -> URL {
        let gameFolder = (saves ?? self.saves).appendingPathComponent(folder ?? MacSavesFolder.folderName(game), isDirectory: true)
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        let url = gameFolder.appendingPathComponent(name)
        let sink = try CartoucheFileSink(url)
        try await CartoucheSaveSync.writeZip(ofSavesIn: documents, to: sink, gameVersion: version)
        try sink.close()
        return url
    }

    /// What a copy holds, unpacked as Cartouche unpacks one on the iPhone.
    private func unpack(_ copy: URL) async throws -> [String: String] {
        let source = try CartoucheFileSource(copy)
        let entries = try await CartoucheZip.entries(of: source)
        XCTAssertTrue(CartoucheSaveSync.holdsSavesOnly(entries))
        let into = root.appendingPathComponent("unpacked-\(UUID().uuidString)", isDirectory: true)
        try await CartoucheZip.extract(source, entries: entries, into: into)
        return try read(into)
    }

    /// The version of the game a copy names.
    private func version(of copy: URL) async throws -> String? {
        CartoucheSaveSync.gameVersion(inComment: try await CartoucheZip.archive(of: CartoucheFileSource(copy)).comment)
    }

    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private var mac: URL { root.appendingPathComponent("nxnative/\(game.titleID)", isDirectory: true) }
    private var iPhone: URL { root.appendingPathComponent("iPhone/Documents", isDirectory: true) }
    private var gameFolder: URL { saves.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]", isDirectory: true) }

    /// A whole, readable zip of one file NAME, stored, as another tool
    /// would make it: only what it holds keeps it from the Mac's saves.
    private static func storedZip(name: String, data: Data) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 { crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        }
        let check = Int(~crc)
        let path = Array(name.utf8)
        var zip: [UInt8] = []
        zip += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(check)
        zip += le32(data.count) + le32(data.count) + le16(path.count) + le16(0) + path + Array(data)
        let directory = zip.count
        zip += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(check)
        zip += le32(data.count) + le32(data.count) + le16(path.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + path
        let size = zip.count - directory
        zip += le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(size) + le32(directory) + le16(0)
        return Data(zip)
    }

    // MARK: Which way

    func testTheMacsFirstSavesGoAsTheNewestCopyWhichTheIPhoneReads() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1", "save_device/settings.bin": "keys"], in: mac, at: t0)
        let sent = try await folder.sync(game, base: nil, fetching: false)
        XCTAssertEqual(sent.step, .send)
        XCTAssertEqual(sent.sent, "2026-11-12T18-02-00Z.zip")
        XCTAssertEqual(names(in: gameFolder), ["2026-11-12T18-02-00Z.zip"])
        // Read on the iPhone: the same files, and what its base says they hold.
        let copy = gameFolder.appendingPathComponent("2026-11-12T18-02-00Z.zip")
        let unpacked = try await unpack(copy)
        XCTAssertEqual(unpacked, ["save/slot0.bin": "mac 1", "save_device/settings.bin": "keys"])
        let entries = try await CartoucheZip.entries(of: CartoucheFileSource(copy))
        XCTAssertEqual(CartoucheSaveSync.content(of: entries), try CartoucheSaveSync.content(ofSavesIn: mac))
        let base = try XCTUnwrap(sent.base)
        XCTAssertEqual(base.place, "mac|" + saves.standardizedFileURL.path)
        XCTAssertEqual(base.copy, "2026-11-12T18-02-00Z.zip")
        // Nothing changed since: nothing moves, before a game or after one.
        for fetching in [true, false] {
            let again = try await folder.sync(game, base: base, fetching: fetching)
            XCTAssertEqual(again.step, .none)
            XCTAssertFalse(again.moved)
        }
    }

    func testTheIPhonesNewerCopyComesBeforeTheGameAndOnlyThen() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let first = try await folder.sync(game, base: nil, fetching: false)
        let base = try XCTUnwrap(first.base)
        // The iPhone played on and sent its saves, as the newest copy.
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(3600))
        let name = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(3600), after: t0)
        try await iPhoneCopy(of: iPhone, named: name)
        // After a game on the Mac, nothing comes: it waits for the next start.
        let after = try await folder.sync(game, base: base, fetching: false)
        XCTAssertEqual(after.step, .none)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // Before the next one, it comes, in place of the Mac's, which the
        // folder has already; nxnative's working copy goes with them.
        try FileManager.default.createDirectory(at: mac.appendingPathComponent("save.work"), withIntermediateDirectories: true)
        let before = try await folder.sync(game, base: base, fetching: true)
        XCTAssertEqual(before.step, .fetch)
        XCTAssertEqual(before.fetched, name)
        XCTAssertNil(before.kept)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mac.appendingPathComponent("save.work").path))
        XCTAssertEqual(before.base?.copy, name)
        let again = try await folder.sync(game, base: before.base, fetching: true)
        XCTAssertEqual(again.step, .none)
    }

    func testBothChangedTheSavesWrittenLastWinAndTheOthersAreKept() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let first = try await folder.sync(game, base: nil, fetching: false)
        let base = try XCTUnwrap(first.base)
        // Both played on: the iPhone last.
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(600))
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(1200))
        let newest = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(1200), after: t0)
        try await iPhoneCopy(of: iPhone, named: newest)
        let before = try await folder.sync(game, base: base, fetching: true)
        XCTAssertEqual(before.step, .keepAndFetch)
        XCTAssertEqual(before.kept, "2026-11-12T18-12-00Z.zip")
        XCTAssertEqual(before.fetched, newest)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
        let kept = try await unpack(gameFolder.appendingPathComponent("2026-11-12T18-12-00Z.zip"))
        XCTAssertEqual(kept, ["save/slot0.bin": "mac 2"])

        // Both again: the Mac last, whose saves go as the newest copy after
        // the game, the iPhone's staying under it.
        let base2 = try XCTUnwrap(before.base)
        try write(["slot0.bin": "iPhone 3"], in: iPhone, at: t0.addingTimeInterval(1800))
        let iPhones = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(1800), after: t0.addingTimeInterval(1200))
        try await iPhoneCopy(of: iPhone, named: iPhones)
        try write(["slot0.bin": "mac 3"], in: mac, at: t0.addingTimeInterval(2400))
        let after = try await folder.sync(game, base: base2, fetching: false)
        XCTAssertEqual(after.step, .send)
        XCTAssertEqual(after.sent, "2026-11-12T18-42-00Z.zip")
        XCTAssertEqual(names(in: gameFolder).last, "2026-11-12T18-42-00Z.zip")
        XCTAssertTrue(names(in: gameFolder).contains(iPhones))
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 3"])
    }

    func testAMacThatNeverSyncedTheGameKeepsItsOlderSavesAsACopy() async throws {
        let folder = try makeFolder()
        // The iPhone's copy is newer than what the Mac has, a first sync.
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0.addingTimeInterval(60))
        let name = CartoucheSaveSync.fileName(t0.addingTimeInterval(60))
        try await iPhoneCopy(of: iPhone, named: name)
        try write(["slot0.bin": "mac 0"], in: mac, at: t0)
        let outcome = try await folder.sync(game, base: nil, fetching: true)
        XCTAssertEqual(outcome.step, .keepAndFetch)
        XCTAssertEqual(outcome.kept, "2026-11-12T18-02-00Z.zip")
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1"])
        // The same saves on both sides: nothing moves, and the base says so.
        try write(["slot0.bin": "same"], in: mac, at: t0.addingTimeInterval(900))
        try write(["slot0.bin": "same"], in: iPhone, at: t0.addingTimeInterval(900))
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(900)))
        let same = try await folder.sync(game, base: nil, fetching: true)
        XCTAssertEqual(same.step, .same)
        XCTAssertEqual(same.base?.copy, CartoucheSaveSync.fileName(t0.addingTimeInterval(900)))
    }

    func testAGameWithoutSavesOnTheMacTakesTheNewestCopy() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0))
        // nxnative's launcher makes an empty save/ at each start.
        try FileManager.default.createDirectory(at: mac.appendingPathComponent("save"), withIntermediateDirectories: true)
        let after = try await folder.sync(game, base: nil, fetching: false)
        XCTAssertEqual(after.step, .none)
        let outcome = try await folder.sync(game, base: nil, fetching: true)
        XCTAssertEqual(outcome.step, .fetch)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1"])
    }

    // MARK: Another saves folder

    /// Ad's first game on a Mac (15 November): played before the Mac kept
    /// its saves with the iPhone's folder on the NAS, it started without
    /// them and saved anew, in the builder's own folder. Chosen then, the
    /// NAS's folder would have taken the Mac's new saves as its newest copy,
    /// written last, for the iPhone to take in place of its own.
    func testAGamePlayedBeforeTheIPhonesFolderWasChosenTakesTheIPhonesSaves() async throws {
        let own = try makeFolder(root.appendingPathComponent("Builder Saves", isDirectory: true))
        let nasSaves = root.appendingPathComponent("NAS/Saves", isDirectory: true)
        let nas = try makeFolder(nasSaves)
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        // The iPhone's progress, in its folder on the NAS.
        try write(["slot0.bin": "iPhone 7"], in: iPhone, at: t0)
        let iPhones = CartoucheSaveSync.fileName(t0)
        try await iPhoneCopy(of: iPhone, named: iPhones, in: nasSaves)
        // The game played on the Mac an hour later, from nothing; its saves
        // went to the builder's own folder after it.
        try write(["slot0.bin": "new game"], in: mac, at: t0.addingTimeInterval(3600))
        let sent = await keeper.sync(game, in: own, when: .after, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(sent?.step, "send")
        let ownCopy = try XCTUnwrap(sent?.sent)
        XCTAssertEqual(store.games(syncedIn: own.root), [game.titleID])
        XCTAssertEqual(store.games(syncedIn: nasSaves), [])
        // The NAS's folder is chosen while the game plays: after it, with
        // saves it did not change, nothing moves, and the Mac remembers them.
        let after = await keeper.sync(game, in: nas, when: .after, now: t0.addingTimeInterval(3700))
        XCTAssertNil(after)
        XCTAssertEqual(store.record(game.titleID).base?.place, "mac|" + own.root.path)
        // The next round: the iPhone's saves come, the Mac's staying in the
        // builder's folder; the NAS's folder holds the iPhone's copy alone.
        let round = await keeper.sync(game, in: nas, when: .round, now: t0.addingTimeInterval(3760))
        XCTAssertEqual(round?.step, "fetch")
        XCTAssertEqual(round?.fetched, iPhones)
        XCTAssertNil(round?.kept)
        XCTAssertNil(round?.sent)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 7"])
        let nasGame = nasSaves.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]", isDirectory: true)
        XCTAssertEqual(names(in: nasGame), [iPhones])
        let kept = try await unpack(own.root.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]/" + ownCopy))
        XCTAssertEqual(kept, ["save/slot0.bin": "new game"])
        XCTAssertEqual(store.record(game.titleID).base?.place, "mac|" + nasSaves.standardizedFileURL.path)
        XCTAssertEqual(store.games(syncedIn: nasSaves), [game.titleID])
        // In step now: the Mac's next game goes as the newest copy, written last.
        try write(["slot0.bin": "iPhone 7 +mac"], in: mac, at: t0.addingTimeInterval(7200))
        let next = await keeper.sync(game, in: nas, when: .after, now: t0.addingTimeInterval(7200))
        XCTAssertEqual(next?.step, "send")
        XCTAssertEqual(names(in: nasGame).count, 2)
    }

    func testSavesNoLongerInTheFolderTheMacLeftAreKeptInTheNewOneFirst() async throws {
        let own = try makeFolder(root.appendingPathComponent("Builder Saves", isDirectory: true))
        let nasSaves = root.appendingPathComponent("NAS/Saves", isDirectory: true)
        let nas = try makeFolder(nasSaves)
        try write(["slot0.bin": "iPhone 7"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0), in: nasSaves)
        try write(["slot0.bin": "new game"], in: mac, at: t0.addingTimeInterval(3600))
        let sent = try await own.sync(game, base: nil, fetching: false)
        let base = try XCTUnwrap(sent.base)
        // The builder's folder lost that copy since.
        try FileManager.default.removeItem(at: own.root.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]/" + base.copy))
        let outcome = try await nas.sync(game, base: base, fetching: true)
        XCTAssertEqual(outcome.step, .keepAndFetch)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 7"])
        // Kept under the iPhone's copy, which stays the newest.
        let nasGame = nasSaves.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]", isDirectory: true)
        let kept = try XCTUnwrap(outcome.kept)
        XCTAssertEqual(names(in: nasGame), [kept, CartoucheSaveSync.fileName(t0)].sorted())
        XCTAssertEqual(names(in: nasGame).last, CartoucheSaveSync.fileName(t0))
        let keptSaves = try await unpack(nasGame.appendingPathComponent(kept))
        XCTAssertEqual(keptSaves, ["save/slot0.bin": "new game"])
    }

    func testSavesTheMacChangedSinceTheFolderItLeftAreNewsThere() async throws {
        let own = try makeFolder(root.appendingPathComponent("Builder Saves", isDirectory: true))
        let nasSaves = root.appendingPathComponent("NAS/Saves", isDirectory: true)
        let nas = try makeFolder(nasSaves)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let first = try await own.sync(game, base: nil, fetching: false)
        let base = try XCTUnwrap(first.base)
        // Played again on the Mac, the builder closed; the iPhone's copy older.
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0.addingTimeInterval(1800))
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(1800)), in: nasSaves)
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(3600))
        // The saves written last win, as for any two that changed.
        let outcome = try await nas.sync(game, base: base, fetching: true)
        XCTAssertEqual(outcome.step, .send)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 2"])
        // A folder without the game's copies takes the Mac's saves, changed or not.
        let empty = try makeFolder(root.appendingPathComponent("Empty Saves", isDirectory: true))
        let fresh = try await empty.sync(game, base: outcome.base, fetching: true)
        XCTAssertEqual(fresh.step, .send)
    }

    func testTheMacTakesTheIPhonesFolderOnAShareWhenNoOneElseUsesItsOwn() async throws {
        let own = root.appendingPathComponent("Builder Saves", isDirectory: true)
        let nas = root.appendingPathComponent("Volumes/NAS/Saves", isDirectory: true)
        let other = root.appendingPathComponent("Volumes/Other/Saves", isDirectory: true)
        // Found alone, no iPhone paired: taken, the builder's folder empty or not.
        XCTAssertEqual(MacSavesFolder.adopted(found: [nas], own: own, paired: false, synced: []), nas)
        XCTAssertNil(MacSavesFolder.adopted(found: [], own: own, paired: false, synced: []))
        XCTAssertNil(MacSavesFolder.adopted(found: [nas, other], own: own, paired: false, synced: []))
        XCTAssertNil(MacSavesFolder.adopted(found: [own], own: own, paired: false, synced: []))
        // An iPhone paired: the builder's folder is left only when what is
        // in it is this Mac's games'.
        XCTAssertEqual(MacSavesFolder.adopted(found: [nas], own: own, paired: true, synced: []), nas)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        try await iPhoneCopy(of: mac, named: CartoucheSaveSync.fileName(t0), in: own)
        try FileManager.default.createDirectory(at: own.appendingPathComponent("Zelda [01008CF01BAAC000]"), withIntermediateDirectories: true)
        XCTAssertEqual(MacSavesFolder.adopted(found: [nas], own: own, paired: true, synced: [game.titleID]), nas)
        XCTAssertNil(MacSavesFolder.adopted(found: [nas], own: own, paired: true, synced: []))
        XCTAssertEqual(MacSavesFolder.adopted(found: [nas], own: own, paired: false, synced: []), nas)
        // An iPhone's copies of a game this Mac does not play: its folder stays.
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0), folder: "Zelda [01008cf01baac000]", in: own)
        XCTAssertNil(MacSavesFolder.adopted(found: [nas], own: own, paired: true, synced: [game.titleID]))
        XCTAssertEqual(MacSavesFolder.adopted(found: [nas], own: own, paired: true, synced: [game.titleID, "01008CF01BAAC000"]), nas)
    }

    // MARK: The game's folder

    func testTheGamesFolderIsCartouchesOrAnyEndingWithItsTitleID() async throws {
        XCTAssertEqual(MacSavesFolder.folderName(MacSaveGame(titleID: "0100f2c0115b6000", name: "The Legend of Zelda: Tears of the Kingdom")),
                       "The Legend of Zelda Tears of the Kingdom [0100F2C0115B6000]")
        XCTAssertEqual(MacSavesFolder.folderName(MacSaveGame(titleID: "0100F2C0115B6000", name: " ..? ")), "Game [0100F2C0115B6000]")
        let folder = try makeFolder()
        XCTAssertEqual(folder.gameFolder(of: game).lastPathComponent, "Mario Kart 8 Deluxe [0100152000022000]")
        // A folder Cartouche named after another name of the game.
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0), folder: "MK8 Deluxe [0100152000022000]")
        XCTAssertEqual(folder.gameFolder(of: game).lastPathComponent, "MK8 Deluxe [0100152000022000]")
        let outcome = try await folder.sync(game, base: nil, fetching: true)
        XCTAssertEqual(outcome.step, .fetch)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1"])
        XCTAssertEqual(folder.copies(of: game).map(\.name), [CartoucheSaveSync.fileName(t0)])
        // Two folders of the game, made before either was seen: the one
        // holding the newest copy, whichever name it has, as Cartouche
        // takes it on the iPhone, so that both keep to one.
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        XCTAssertEqual(folder.gameFolder(of: game).lastPathComponent, "MK8 Deluxe [0100152000022000]")
        let other = root.appendingPathComponent("other iPhone/Documents", isDirectory: true)
        try write(["slot0.bin": "iPhone 2"], in: other, at: t0.addingTimeInterval(600))
        try await iPhoneCopy(of: other, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(600)))
        XCTAssertEqual(folder.gameFolder(of: game).lastPathComponent, "Mario Kart 8 Deluxe [0100152000022000]")
        let newer = try await folder.sync(game, base: outcome.base, fetching: true)
        XCTAssertEqual(newer.fetched, CartoucheSaveSync.fileName(t0.addingTimeInterval(600)))
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
        try write(["slot0.bin": "iPhone 3"], in: iPhone, at: t0.addingTimeInterval(1200))
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(1200)), folder: "MK8 Deluxe [0100152000022000]")
        XCTAssertEqual(folder.gameFolder(of: game).lastPathComponent, "MK8 Deluxe [0100152000022000]")
    }

    func testTheTenNewestCopiesAreKept() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "iPhone"], in: iPhone, at: t0)
        for minute in 0 ..< 12 {
            try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(Double(minute) * 60)))
        }
        try Data("half".utf8).write(to: gameFolder.appendingPathComponent("2026-11-12T17-00-00Z.zip.partial"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)],
                                              ofItemAtPath: gameFolder.appendingPathComponent("2026-11-12T17-00-00Z.zip.partial").path)
        try write(["slot0.bin": "mac"], in: mac, at: t0.addingTimeInterval(3600))
        let outcome = try await folder.sync(game, base: nil, fetching: false)
        XCTAssertEqual(outcome.step, .send)
        let left = names(in: gameFolder)
        XCTAssertEqual(left.count, CartoucheSaveSync.kept)
        XCTAssertEqual(left.last, outcome.sent)
        XCTAssertEqual(left.first, CartoucheSaveSync.fileName(t0.addingTimeInterval(3 * 60)))
    }

    // MARK: Putting a copy back

    func testACopyPutBackComesAndBecomesTheNewestWhichTheIPhoneTakes() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let first = try await folder.sync(game, base: nil, fetching: false)
        let oldest = try XCTUnwrap(first.sent)
        // The iPhone played, then the Mac, each sending its saves.
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(600))
        let iPhones = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(600), after: t0)
        try await iPhoneCopy(of: iPhone, named: iPhones)
        let fetched = try await folder.sync(game, base: first.base, fetching: true)
        XCTAssertEqual(fetched.step, .fetch)
        try write(["slot0.bin": "mac 3"], in: mac, at: t0.addingTimeInterval(1200))
        let sent = try await folder.sync(game, base: fetched.base, fetching: false)
        XCTAssertEqual(sent.step, .send)
        let base = try XCTUnwrap(sent.base)
        let before = names(in: gameFolder)
        XCTAssertEqual(before, [oldest, iPhones, try XCTUnwrap(sent.sent)])

        // The player puts back the oldest copy from the console: the Mac's
        // saves are in the folder already, so nothing is kept again.
        let putBack = try await folder.putBack(oldest, of: game, base: base)
        XCTAssertEqual(putBack.step, .fetch)
        XCTAssertNil(putBack.kept, "the saves it replaced were in the folder already")
        XCTAssertEqual(putBack.fetched, oldest)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // It goes again as the newest copy, which the iPhone reads.
        let newest = try XCTUnwrap(putBack.sent)
        XCTAssertEqual(names(in: gameFolder), before + [newest])
        let sentAgain = try await unpack(gameFolder.appendingPathComponent(newest))
        XCTAssertEqual(sentAgain, ["save/slot0.bin": "mac 1"])
        let newBase = try XCTUnwrap(putBack.base)
        XCTAssertEqual(newBase.copy, newest)
        XCTAssertEqual(newBase.place, "mac|" + saves.standardizedFileURL.path)
        // Both sides the same since: nothing moves, before a game or after.
        for fetching in [true, false] {
            let again = try await folder.sync(game, base: newBase, fetching: fetching)
            XCTAssertEqual(again.step, .none)
        }
    }

    func testPuttingBackSendsTheMacsSavesFirstWhenTheFolderLacksThem() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let first = try await folder.sync(game, base: nil, fetching: false)
        let copy = try XCTUnwrap(first.sent)
        // Played since, its saves not sent yet, as with the builder closed.
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(600))
        let putBack = try await folder.putBack(copy, of: game, base: first.base)
        let kept = try XCTUnwrap(putBack.kept)
        XCTAssertEqual(kept, "2026-11-12T18-12-00Z.zip")
        let keptSaves = try await unpack(gameFolder.appendingPathComponent(kept))
        XCTAssertEqual(keptSaves, ["save/slot0.bin": "mac 2"])
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // The copy put back is the newest again, after the one kept.
        let newest = try XCTUnwrap(putBack.sent)
        XCTAssertEqual(names(in: gameFolder), [copy, kept, newest])
        let sentAgain = try await unpack(gameFolder.appendingPathComponent(newest))
        XCTAssertEqual(sentAgain, ["save/slot0.bin": "mac 1"])
        XCTAssertEqual(putBack.base?.copy, newest)
    }

    func testTheNewestCopyPutBackIsNotSentAgain() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        let name = CartoucheSaveSync.fileName(t0)
        try await iPhoneCopy(of: iPhone, named: name)
        // A game without saves on this Mac yet: nothing to keep first.
        let putBack = try await folder.putBack(name, of: game, base: nil)
        XCTAssertNil(putBack.kept)
        XCTAssertNil(putBack.sent)
        XCTAssertEqual(putBack.base?.copy, name)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1"])
        XCTAssertEqual(names(in: gameFolder), [name])
    }

    func testACopyIsNeverPutBackAwayFromTheFolderUnderAGameOrUnread() async throws {
        let share = root.appendingPathComponent("Volumes/NAS/Saves", isDirectory: true)
        let away = MacSavesFolder(root: share, games: root.appendingPathComponent("nxnative", isDirectory: true),
                                  scratch: root.appendingPathComponent("scratch", isDirectory: true))
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        do {
            _ = try await away.putBack(CartoucheSaveSync.fileName(t0), of: game, base: nil)
            XCTFail("a share not mounted puts nothing back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .offline)
        }
        let folder = try makeFolder()
        let first = try await folder.sync(game, base: nil, fetching: false)
        let copy = try XCTUnwrap(first.sent)
        // A copy that is not there.
        do {
            _ = try await folder.putBack(CartoucheSaveSync.fileName(t0.addingTimeInterval(-60)), of: game, base: first.base)
            XCTFail("only a copy of the folder is put back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .unreadable(CartoucheSaveSync.fileName(t0.addingTimeInterval(-60))))
        }
        // The game started from the Dock meanwhile: its saves stay.
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(600))
        do {
            _ = try await folder.putBack(copy, of: game, base: first.base, quiet: { false })
            XCTFail("a copy never comes under a game playing")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .busy)
        }
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 2"])
        // A copy that is no zip: the saves of the Mac stay, kept in the folder.
        let broken = CartoucheSaveSync.fileName(t0.addingTimeInterval(-120))
        try Data("PK no zip".utf8).write(to: gameFolder.appendingPathComponent(broken))
        do {
            _ = try await folder.putBack(broken, of: game, base: first.base)
            XCTFail("a copy that is no zip is never put back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .unreadable(broken))
        }
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 2"])
        XCTAssertEqual(names(in: root.appendingPathComponent("scratch", isDirectory: true)), [])
    }

    func testTheKeeperRecordsAPutBackAndWhenTheSavesWereLastInStep() async throws {
        let folder = try makeFolder()
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        _ = await keeper.sync(game, in: folder, when: .after, now: t0)
        let copy = try XCTUnwrap(store.record(game.titleID).last?.sent)
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(600))
        _ = await keeper.sync(game, in: folder, when: .after, now: t0.addingTimeInterval(600))
        // Nothing moved: still in step, at that time.
        let none = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(660))
        XCTAssertNil(none)
        let checked = await keeper.lastChecked(game.titleID)
        XCTAssertEqual(checked, t0.addingTimeInterval(660))
        let event = try await keeper.putBack(copy, of: game, in: folder, now: t0.addingTimeInterval(720))
        XCTAssertEqual(event.step, MacSaveEvent.putBack)
        XCTAssertEqual(event.fetched, copy)
        XCTAssertNil(event.kept)
        let newest = try XCTUnwrap(event.sent)
        XCTAssertEqual(store.record(game.titleID).last, event)
        XCTAssertEqual(store.record(game.titleID).base?.copy, newest)
        let afterPutBack = await keeper.lastChecked(game.titleID)
        XCTAssertEqual(afterPutBack, t0.addingTimeInterval(720))
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // A copy that cannot come leaves the record as it was.
        do {
            _ = try await keeper.putBack(CartoucheSaveSync.fileName(t0.addingTimeInterval(-60)), of: game, in: folder)
            XCTFail("only a copy of the folder is put back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .unreadable(CartoucheSaveSync.fileName(t0.addingTimeInterval(-60))))
        }
        XCTAssertEqual(store.record(game.titleID).last, event)
    }

    func testAChangeOfTheSavesGoesAsTheNewestCopyAfter() async throws {
        let folder = try makeFolder()
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        _ = await keeper.sync(game, in: folder, when: .after, now: t0)
        // A save from the Switch put in place, in the keeper's turn: what
        // the change gives comes back, and what it throws.
        let mac = self.mac
        let written = t0.addingTimeInterval(900)
        let changed = try await keeper.change { () -> String in
            let url = mac.appendingPathComponent("save/slot0.bin")
            try Data("switch 2".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: url.path)
            return "changed"
        }
        XCTAssertEqual(changed, "changed")
        do {
            _ = try await keeper.change { () -> Int in throw MacSavesError.busy }
            XCTFail("what a change throws comes back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .busy)
        }
        // The sync after it sends it as the newest copy, for the iPhones.
        let sent = await keeper.sync(game, in: folder, when: .after, now: t0.addingTimeInterval(960))
        XCTAssertEqual(sent?.step, "send")
        let newest = try XCTUnwrap(sent?.sent)
        XCTAssertEqual(names(in: gameFolder).last, newest)
        let sentSaves = try await unpack(gameFolder.appendingPathComponent(newest))
        XCTAssertEqual(sentSaves, ["save/slot0.bin": "switch 2"])
    }

    // MARK: While the game plays

    /// The saves a game makes while it plays go a few seconds after it
    /// saved (MacGames.lookAtPlaying), from a copy of them made at one
    /// moment; each copy of the same game takes the place of the one before
    /// it, the one after the game too, for one copy for each game.
    func testSavesThatChangeWhileTheGamePlaysGoAsOneCopyOfTheGame() async throws {
        let folder = try makeFolder()
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        _ = await keeper.sync(game, in: folder, when: .after, now: t0)
        let before = CartoucheSaveSync.fileName(t0)
        // The game starts: nothing new to take.
        let start = await keeper.sync(game, in: folder, when: .before, now: t0.addingTimeInterval(60))
        XCTAssertNil(start)
        // It saves twice while it plays: each time, its saves go.
        for (step, text) in ["mac 2", "mac 3"].enumerated() {
            let written = t0.addingTimeInterval(600 * Double(step + 1))
            try write(["slot0.bin": text, "save_device/device.bin": "device"], in: mac, at: written)
            let played = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: written.addingTimeInterval(5))
            XCTAssertEqual(played.event?.step, "send")
            XCTAssertEqual(played.event?.when, .during)
            XCTAssertEqual(played.event?.sent, CartoucheSaveSync.fileName(written))
            XCTAssertEqual(played.inStep, CartoucheSaveSync.saves(in: mac)?.look)
            XCTAssertFalse(played.failed)
            XCTAssertEqual(names(in: gameFolder), [before, CartoucheSaveSync.fileName(written)],
                           "the game before's copy, and this game's newest saves alone")
        }
        let newest = try XCTUnwrap(names(in: gameFolder).last)
        let sentSaves = try await unpack(gameFolder.appendingPathComponent(newest))
        XCTAssertEqual(sentSaves, ["save/slot0.bin": "mac 3", "save_device/device.bin": "device"])
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 3", "save_device/device.bin": "device"], "the game's saves as they were")
        // The base holds for the saves in nxnative's folder, and nothing is
        // left of their copy.
        XCTAssertEqual(store.record(game.titleID).base?.look, CartoucheSaveSync.saves(in: mac)?.look)
        XCTAssertEqual(store.record(game.titleID).base?.copy, newest)
        XCTAssertEqual(names(in: scratch.appendingPathComponent("playing")), [])
        // Nothing changed since: nothing goes.
        let same = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(1_300))
        XCTAssertEqual(same, MacSavePlayed(inStep: CartoucheSaveSync.saves(in: mac)?.look))
        // It saves once more, and the player quits: the copy after the
        // game takes the place of the last one too.
        try write(["slot0.bin": "mac 4"], in: mac, at: t0.addingTimeInterval(1_800))
        let after = await keeper.sync(game, in: folder, when: .after, now: t0.addingTimeInterval(1_860))
        XCTAssertEqual(after?.step, "send")
        XCTAssertEqual(names(in: gameFolder), [before, CartoucheSaveSync.fileName(t0.addingTimeInterval(1_800))])
        // The next game makes a copy of its own.
        _ = await keeper.sync(game, in: folder, when: .before, now: t0.addingTimeInterval(2_000))
        try write(["slot0.bin": "mac 5"], in: mac, at: t0.addingTimeInterval(2_400))
        let next = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(2_405))
        XCTAssertEqual(next.event?.step, "send")
        XCTAssertEqual(names(in: gameFolder), [before, CartoucheSaveSync.fileName(t0.addingTimeInterval(1_800)),
                                               CartoucheSaveSync.fileName(t0.addingTimeInterval(2_400))])
    }

    /// While the saves folder is away, the saves a game makes while it
    /// plays stay where they are, said once; they go after the game, or as
    /// soon as the folder is back.
    func testSavesThatChangeWhileTheGamePlaysWaitForTheFolderAway() async throws {
        let share = root.appendingPathComponent("Volumes/NAS/Saves", isDirectory: true)
        let folder = MacSavesFolder(root: share, games: root.appendingPathComponent("nxnative", isDirectory: true),
                                    scratch: root.appendingPathComponent("scratch", isDirectory: true))
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let played = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(5))
        XCTAssertTrue(played.failed)
        XCTAssertNil(played.inStep)
        XCTAssertEqual(played.event?.step, "offline")
        XCTAssertEqual(played.event?.when, .during)
        let again = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(65))
        XCTAssertEqual(again, MacSavePlayed(failed: true), "said once")
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // Back: they go.
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        let back = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(125))
        XCTAssertEqual(back.event?.step, "send")
        XCTAssertEqual(back.event?.sent, CartoucheSaveSync.fileName(t0))
        // Away again as the game ends: the next game's saves never take the
        // place of this one's.
        let away = root.appendingPathComponent("Volumes/NAS/Away", isDirectory: true)
        try FileManager.default.moveItem(at: share, to: away)
        let ended = await keeper.sync(game, in: folder, when: .after, now: t0.addingTimeInterval(180))
        XCTAssertEqual(ended?.step, "offline")
        try FileManager.default.moveItem(at: away, to: share)
        let start = await keeper.sync(game, in: folder, when: .before, now: t0.addingTimeInterval(240))
        XCTAssertNil(start)
        try write(["slot0.bin": "mac 2"], in: mac, at: t0.addingTimeInterval(600))
        let next = await keeper.sendPlaying(game, from: mac, in: folder, scratch: scratch, now: t0.addingTimeInterval(605))
        XCTAssertEqual(next.event?.step, "send")
        XCTAssertEqual(names(in: share.appendingPathComponent(MacSavesFolder.folderName(game), isDirectory: true)),
                       [t0, t0.addingTimeInterval(600)].map(CartoucheSaveSync.fileName))
    }

    func testAnEventSaysWhenTheSavesThatCameAndThoseKeptWereWritten() {
        let event = MacSaveEvent(at: t0, when: .round, step: "keepAndFetch", fetched: CartoucheSaveSync.fileName(t0.addingTimeInterval(-600)),
                                 kept: CartoucheSaveSync.fileName(t0.addingTimeInterval(-1200)))
        XCTAssertEqual(event.fetchedDate, t0.addingTimeInterval(-600))
        XCTAssertEqual(event.keptDate, t0.addingTimeInterval(-1200))
        let none = MacSaveEvent(at: t0, when: .after, step: "send", sent: CartoucheSaveSync.fileName(t0))
        XCTAssertNil(none.fetchedDate)
        XCTAssertNil(none.keptDate)
    }

    // MARK: What does not go

    func testAShareNotMountedIsOfflineAndTheMacsSavesStay() async throws {
        let share = root.appendingPathComponent("Volumes/NAS/Saves", isDirectory: true)
        let folder = MacSavesFolder(root: share, games: root.appendingPathComponent("nxnative", isDirectory: true),
                                    scratch: root.appendingPathComponent("scratch", isDirectory: true))
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        XCTAssertFalse(folder.reachable)
        do {
            _ = try await folder.sync(game, base: nil, fetching: true)
            XCTFail("a folder that is not there is offline")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .offline)
        }
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        let event = await keeper.sync(game, in: folder, when: .before, now: t0)
        XCTAssertEqual(event?.step, "offline")
        // Still offline: the event stays the first one.
        let again = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(60))
        XCTAssertNil(again)
        XCTAssertEqual(store.record(game.titleID).last?.at, t0)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // Back: the saves of the Mac go.
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        let back = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(120))
        XCTAssertEqual(back?.step, "send")
        XCTAssertEqual(back?.sent, "2026-11-12T18-02-00Z.zip")
    }

    func testACopyOfOtherFilesNeverReplacesTheMacsSaves() async throws {
        let folder = try makeFolder()
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        // A zip of something else, newest in the game's folder.
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        let url = gameFolder.appendingPathComponent(CartoucheSaveSync.fileName(t0.addingTimeInterval(3600)))
        try Self.storedZip(name: "notes/a.txt", data: Data("not a save".utf8)).write(to: url)
        // Whole and readable: only what it holds keeps it out.
        let source = try CartoucheFileSource(url)
        let entries = try await CartoucheZip.entries(of: source)
        try await CartoucheZip.extract(source, entries: entries, into: root.appendingPathComponent("other", isDirectory: true))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("other/notes/a.txt"), encoding: .utf8), "not a save")
        let keeper = MacSaveKeeper(store: MacSaveStore(url: root.appendingPathComponent("saves.json")))
        let event = await keeper.sync(game, in: folder, when: .before, now: t0)
        XCTAssertEqual(event?.step, "failed")
        XCTAssertTrue(event?.failure?.contains(url.lastPathComponent) ?? false, event?.failure ?? "")
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // And a file that is no zip at all.
        try Data("PK no zip".utf8).write(to: url)
        do {
            _ = try await folder.sync(game, base: nil, fetching: true)
            XCTFail("a copy that is no zip never comes")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .unreadable(url.lastPathComponent))
        }
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        // Nor for a game that has no saves on this Mac yet, the copy named.
        try write([:], in: mac, at: t0)
        do {
            _ = try await folder.sync(game, base: nil, fetching: true)
            XCTFail("a copy that is no zip never comes")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .unreadable(url.lastPathComponent))
        }
        XCTAssertEqual(try read(mac), [:])
        XCTAssertEqual(names(in: root.appendingPathComponent("scratch", isDirectory: true)), [])
    }

    func testACopyNeverComesUnderAGameThatStartedMeanwhile() async throws {
        let folder = try makeFolder()
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        _ = await keeper.sync(game, in: folder, when: .after, now: t0)
        let base = store.record(game.titleID).base
        XCTAssertNotNil(base)
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(3600))
        let name = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(3600), after: t0)
        try await iPhoneCopy(of: iPhone, named: name)
        // The game started from the Dock while its copy was on its way: the
        // saves it found stay, and nothing is left of the copy on the Mac.
        do {
            _ = try await folder.sync(game, base: base, fetching: true, quiet: { false })
            XCTFail("a copy never comes under a game playing")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .busy)
        }
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1"])
        XCTAssertEqual(names(in: root.appendingPathComponent("scratch", isDirectory: true)), [])
        // The keeper says nothing of it and keeps its base: the copy comes
        // at the next round with the game quiet.
        let busy = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(7200), quiet: { false })
        XCTAssertNil(busy)
        XCTAssertEqual(store.record(game.titleID).base, base)
        XCTAssertEqual(store.record(game.titleID).last?.step, "send")
        let quiet = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(7260))
        XCTAssertEqual(quiet?.step, "fetch")
        XCTAssertEqual(quiet?.fetched, name)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
    }

    // MARK: What the Mac keeps

    func testTwoSyncsOfAGameAtOnceRunOneAfterTheOther() async throws {
        let folder = try makeFolder()
        let keeper = MacSaveKeeper(store: MacSaveStore(url: root.appendingPathComponent("saves.json")))
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        _ = await keeper.sync(game, in: folder, when: .after, now: t0)
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(3600))
        let name = CartoucheSaveSync.sendName(written: t0.addingTimeInterval(3600), after: t0)
        try await iPhoneCopy(of: iPhone, named: name)
        // A start and a round at the same moment: the copy comes once, and
        // the second sync finds both sides the same.
        async let start = keeper.sync(game, in: folder, when: .before, now: t0.addingTimeInterval(7200))
        async let round = keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(7200))
        let first = await start
        let second = await round
        XCTAssertEqual([first, second].compactMap { $0?.step }, ["fetch"])
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
        XCTAssertEqual(names(in: gameFolder), ["2026-11-12T18-02-00Z.zip", name])
    }

    func testTheKeeperKeepsEachGamesBaseAndWhatMovedLast() async throws {
        let folder = try makeFolder()
        let file = root.appendingPathComponent("saves.json")
        let keeper = MacSaveKeeper(store: MacSaveStore(url: file))
        try write(["slot0.bin": "mac 1"], in: mac, at: t0)
        let sent = await keeper.sync(game, in: folder, when: .after, now: t0)
        XCTAssertEqual(sent, MacSaveEvent(at: t0, when: .after, step: "send", sent: "2026-11-12T18-02-00Z.zip"))
        // Nothing moved: no event, the last one stays.
        let none = await keeper.sync(game, in: folder, when: .round, now: t0.addingTimeInterval(60))
        XCTAssertNil(none)
        // Read again from its file, as at the Builder's next start.
        let store = MacSaveStore(url: file)
        XCTAssertEqual(store.record(game.titleID).last, sent)
        XCTAssertEqual(store.record("0100152000022000").base?.copy, "2026-11-12T18-02-00Z.zip")
        // Another saves folder starts from none.
        let other = try makeFolder(root.appendingPathComponent("Other Saves", isDirectory: true))
        let first = await MacSaveKeeper(store: store).sync(game, in: other, when: .round, now: t0.addingTimeInterval(120))
        XCTAssertEqual(first?.step, "send")
        XCTAssertEqual(store.record(game.titleID).base?.place, "mac|" + root.appendingPathComponent("Other Saves").standardizedFileURL.path)
    }

    // MARK: A newer version of the game

    func testACopyOfANewerVersionOfTheGameWaitsForItsUpdateOnTheMac() async throws {
        let folder = try makeFolder()
        let older = MacSaveGame(titleID: game.titleID, name: game.name, version: "1.1.0")
        // The iPhone's game was updated to 1.2.0, and played there.
        try write(["slot0.bin": "iPhone 1.2"], in: iPhone, at: t0)
        let newest = CartoucheSaveSync.fileName(t0)
        try await iPhoneCopy(of: iPhone, named: newest, version: "1.2.0")

        // The Mac's app, built from 1.1.0, never takes it: not before a game,
        let waits = try await folder.sync(older, base: nil, fetching: true)
        XCTAssertEqual(waits.step, .none)
        XCTAssertEqual(waits.newer, "1.2.0")
        XCTAssertFalse(waits.moved)
        XCTAssertEqual(try read(mac), [:])
        // nor over the saves it plays meanwhile, which go under it as a copy
        // of their own, naming their version: the newest stays the iPhone's.
        try write(["slot0.bin": "mac 1.1"], in: mac, at: t0.addingTimeInterval(600))
        let kept = try await folder.sync(older, base: waits.base, fetching: false)
        XCTAssertEqual(kept.step, .keep)
        XCTAssertEqual(kept.newer, "1.2.0")
        let keptName = try XCTUnwrap(kept.kept)
        XCTAssertEqual(keptName, CartoucheSaveSync.fileName(t0.addingTimeInterval(-1)))
        XCTAssertEqual(names(in: gameFolder), [keptName, newest])
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1.1"])
        let keptCopy = gameFolder.appendingPathComponent(keptName)
        let keptSaves = try await unpack(keptCopy)
        XCTAssertEqual(keptSaves, ["save/slot0.bin": "mac 1.1"])
        let keptVersion = try await version(of: keptCopy)
        XCTAssertEqual(keptVersion, "1.1.0")
        let base = try XCTUnwrap(kept.base)
        XCTAssertEqual(base.gameVersion, "1.1.0")
        for fetching in [true, false] {
            let again = try await folder.sync(older, base: base, fetching: fetching)
            XCTAssertEqual(again.step, .none)
            XCTAssertEqual(again.newer, fetching ? "1.2.0" : nil, "after a game, nothing would come")
        }
        // nor when the player puts it back from the console.
        do {
            _ = try await folder.putBack(newest, of: older, base: base)
            XCTFail("a copy of a newer version of the game was put back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .newerGame(copy: "1.2.0", game: "1.1.0"))
        }
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "mac 1.1"])
        XCTAssertEqual(names(in: gameFolder), [keptName, newest])

        // Built again from 1.2.0: the newest copy comes before its next game.
        let updated = MacSaveGame(titleID: game.titleID, name: game.name, version: "1.2.0")
        let comes = try await folder.sync(updated, base: base, fetching: true)
        XCTAssertEqual(comes.step, .fetch)
        XCTAssertNil(comes.newer)
        XCTAssertEqual(comes.fetched, newest)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1.2"])
        XCTAssertEqual(comes.base?.gameVersion, "1.2.0")
        // Its next copy names its version.
        try write(["slot0.bin": "mac 1.2"], in: mac, at: t0.addingTimeInterval(1_200))
        let sent = try await folder.sync(updated, base: comes.base, fetching: false)
        XCTAssertEqual(sent.step, .send)
        let sentVersion = try await version(of: gameFolder.appendingPathComponent(try XCTUnwrap(sent.sent)))
        XCTAssertEqual(sentVersion, "1.2.0")
    }

    func testACopyThatNamesNoVersionOrAnOlderOneComesAsBefore() async throws {
        let folder = try makeFolder()
        // An older Cartouche's copy names none.
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0))
        let game = MacSaveGame(titleID: self.game.titleID, name: self.game.name, version: "1.1.0")
        let first = try await folder.sync(game, base: nil, fetching: true)
        XCTAssertEqual(first.step, .fetch)
        XCTAssertNil(first.newer)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1"])
        // One of an older version comes to a newer game too.
        try write(["slot0.bin": "iPhone 2"], in: iPhone, at: t0.addingTimeInterval(600))
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(600)), version: "1.0.0")
        let second = try await folder.sync(game, base: first.base, fetching: true)
        XCTAssertEqual(second.step, .fetch)
        XCTAssertNil(second.newer)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 2"])
        // An app that says no version holds nothing back.
        try write(["slot0.bin": "iPhone 3"], in: iPhone, at: t0.addingTimeInterval(1_200))
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0.addingTimeInterval(1_200)), version: "9.0.0")
        let third = try await folder.sync(self.game, base: second.base, fetching: true)
        XCTAssertEqual(third.step, .fetch)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 3"])
    }

    func testTheKeeperSaysOnceThatTheNewestCopyWaitsForTheGamesUpdate() async throws {
        let folder = try makeFolder()
        let store = MacSaveStore(url: root.appendingPathComponent("saves.json"))
        let keeper = MacSaveKeeper(store: store)
        let older = MacSaveGame(titleID: game.titleID, name: game.name, version: "1.1.0")
        try write(["slot0.bin": "iPhone 1.2"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0), version: "1.2.0")
        let held = await keeper.sync(older, in: folder, when: .before, now: t0.addingTimeInterval(60))
        XCTAssertEqual(held, MacSaveEvent(at: t0.addingTimeInterval(60), when: .before, step: MacSaveEvent.heldBack,
                                          newer: "1.2.0", game: "1.1.0"))
        XCTAssertEqual(store.record(game.titleID).last, held)
        // Still waiting: told once, the time it started to kept.
        let again = await keeper.sync(older, in: folder, when: .round, now: t0.addingTimeInterval(120))
        XCTAssertNil(again)
        XCTAssertEqual(store.record(game.titleID).last, held)
        let checked = await keeper.lastChecked(game.titleID)
        XCTAssertEqual(checked, t0.addingTimeInterval(120))
        // The Mac's saves kept under it after a game: that is news.
        try write(["slot0.bin": "mac 1.1"], in: mac, at: t0.addingTimeInterval(600))
        let kept = await keeper.sync(older, in: folder, when: .after, now: t0.addingTimeInterval(660))
        XCTAssertEqual(kept?.step, MacSaveEvent.heldBack)
        XCTAssertEqual(kept?.kept, CartoucheSaveSync.fileName(t0.addingTimeInterval(-1)))
        XCTAssertEqual(kept?.newer, "1.2.0")
        XCTAssertEqual(kept?.keptDate, t0.addingTimeInterval(-1))
        XCTAssertEqual(store.record(game.titleID).base?.copy, kept?.kept)
        // Read again from its file, as at the Builder's next start.
        XCTAssertEqual(MacSaveStore(url: root.appendingPathComponent("saves.json")).record(game.titleID).last, kept)
        // Once the game is updated, it comes.
        let updated = MacSaveGame(titleID: game.titleID, name: game.name, version: "1.2.0")
        let fetched = await keeper.sync(updated, in: folder, when: .before, now: t0.addingTimeInterval(720))
        XCTAssertEqual(fetched?.step, "fetch")
        XCTAssertNil(fetched?.newer)
        XCTAssertEqual(try read(mac), ["save/slot0.bin": "iPhone 1.2"])
        // Put back to an app of 1.1.0, it is refused, and leaves the record.
        do {
            _ = try await keeper.putBack(CartoucheSaveSync.fileName(t0), of: older, in: folder)
            XCTFail("a copy of a newer version of the game was put back")
        } catch {
            XCTAssertEqual(error as? MacSavesError, .newerGame(copy: "1.2.0", game: "1.1.0"))
        }
        XCTAssertEqual(store.record(game.titleID).last, fetched)
    }

    // MARK: Finding the folder on a share

    func testTheSavesFolderIsFoundOnTheSharesMountedHere() async throws {
        let volumes = root.appendingPathComponent("Volumes", isDirectory: true)
        let nasSaves = volumes.appendingPathComponent("NAS/Cartouche/Saves", isDirectory: true)
        try write(["slot0.bin": "iPhone 1"], in: iPhone, at: t0)
        try await iPhoneCopy(of: iPhone, named: CartoucheSaveSync.fileName(t0), in: nasSaves)
        // A disk of games without saves, and a folder of game folders without copies.
        try FileManager.default.createDirectory(at: volumes.appendingPathComponent("Games SSD/Switch/Mario Kart 8 Deluxe [0100152000022000]"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(MacSavesFolder.found(in: volumes).map(\.lastPathComponent), ["Saves"])
        XCTAssertEqual(MacSavesFolder.found(in: volumes).first?.standardizedFileURL, nasSaves.standardizedFileURL)
        XCTAssertTrue(MacSavesFolder.looksLikeSaves(nasSaves))
        XCTAssertFalse(MacSavesFolder.looksLikeSaves(volumes.appendingPathComponent("Games SSD/Switch")))
        // Deeper than it looks, or past its budget: not found.
        XCTAssertEqual(MacSavesFolder.found(in: volumes, depth: 1), [])
        XCTAssertEqual(MacSavesFolder.found(in: volumes, budget: 2), [])
        XCTAssertTrue(MacSavesFolder.hasTitleID("Mario Kart 8 Deluxe [0100152000022000]"))
        XCTAssertFalse(MacSavesFolder.hasTitleID("Mario Kart 8 Deluxe [v131072]"))
    }
}
