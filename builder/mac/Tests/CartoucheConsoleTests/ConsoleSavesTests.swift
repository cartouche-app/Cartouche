//
//  ConsoleSavesTests.swift
//  CartoucheConsoleTests
//
//  A game's saves on its sheet in the console (ConsoleSaves.swift): where a
//  game keeps them on this Mac, what the sheet shows of what the Builder
//  says, the saves folder away, and what the sheet asks the Builder, in
//  folders and closures of the tests' own.
//

import Foundation
import XCTest
@testable import CartoucheConsole

@MainActor
final class ConsoleSavesTests: XCTestCase {
    private var root: URL!
    private var keptDataRoot: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("console-saves-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        keptDataRoot = CartoucheGameActions.shared.dataRoot
        CartoucheGameActions.shared.dataRoot = root.appendingPathComponent("nxnative", isDirectory: true)
    }

    override func tearDown() async throws {
        let console = CartoucheMacConsole.shared
        console.showSaves(folder: nil, games: [:])
        console.onSyncSaves = { _ in throw CartoucheMacSaveError.offline }
        console.onSaveCopies = { _ in [] }
        console.onPutBackSave = { _, _ in throw CartoucheMacSaveError.offline }
        console.onChangeSaves = { _, change in try change() }
        CartoucheGameActions.shared.dataRoot = keptDataRoot
        try? FileManager.default.removeItem(at: root)
    }

    private let titleID = "0100152000022000"

    private func game() throws -> LCAppModel {
        let app = root.appendingPathComponent("Applications/Mario Kart 8 Deluxe.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "org.nxnative." + titleID.lowercased(), "CFBundleName": "Mario Kart 8 Deluxe",
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return LCAppModel(appInfo: LCAppInfo(url: app))
    }

    private var folder: CartoucheMacSavesFolder {
        CartoucheMacSavesFolder(name: "the NAS", path: "/Volumes/Partage/Cartouche/Saves")
    }

    func testAGamesSavesAreNxnativesFolderOfItByItsTitleID() throws {
        let actions = CartoucheGameActions.shared
        let app = try game()
        // Before its first start: no saves yet, but one can come from the
        // Switch, its folder made as nxnative makes it.
        XCTAssertNil(actions.saves(of: app))
        let made = try XCTUnwrap(actions.savesToImport(of: app))
        let documents = actions.dataRoot.appendingPathComponent(titleID, isDirectory: true)
        XCTAssertEqual(made.documents.standardizedFileURL.path, documents.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: documents.path))
        let target = try XCTUnwrap(actions.saves(of: app))
        XCTAssertEqual(target.key, titleID)
        XCTAssertEqual(target.titleId, titleID)
        XCTAssertEqual(target.name, "Mario Kart 8 Deluxe")
        // An app that is not a game has none.
        let notes = root.appendingPathComponent("Applications/Notes.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.notes"], format: .xml, options: 0)
            .write(to: notes.appendingPathComponent("Info.plist"))
        XCTAssertNil(actions.savesToImport(of: LCAppModel(appInfo: LCAppInfo(url: notes.deletingLastPathComponent()))))
    }

    func testTheSheetShowsWhatTheBuilderSaysOfTheSaves() throws {
        let console = CartoucheMacConsole.shared
        let backups = CartoucheSaveBackups.shared
        let settings = CartoucheStorageSettings.shared
        let target = CartoucheSaveTarget(key: titleID, name: "Mario Kart 8 Deluxe", titleId: titleID, documents: root)
        let synced = Date(timeIntervalSince1970: 1_794_000_000)
        console.showSaves(folder: folder, games: [titleID.lowercased(): CartoucheMacGameSaves(
            lastSync: synced, fetched: synced.addingTimeInterval(-3_600), kept: synced.addingTimeInterval(-7_200))])
        // The saves folder is the place of the saves, under its name.
        XCTAssertTrue(backups.isOn)
        let location = try XCTUnwrap(settings.location(.saves))
        XCTAssertEqual(location.server.name, "the NAS")
        XCTAssertEqual(location.server.kind, .folder)
        XCTAssertEqual(location.path, "/Volumes/Partage/Cartouche/Saves")
        XCTAssertEqual(backups.lastSync[titleID], synced)
        XCTAssertEqual(backups.news[titleID], CartoucheSaveNews(fetched: synced.addingTimeInterval(-3_600),
                                                                 kept: synced.addingTimeInterval(-7_200)))
        XCTAssertFalse(backups.waiting.contains(titleID))
        XCTAssertNil(backups.problem(of: target))
        XCTAssertFalse(backups.isLeftToCloud(target))
        XCTAssertFalse(CartoucheStorageReach.shared.isOffline(location.server.id))

        // What went wrong: one report, kept while it is the same.
        console.showSaves(folder: folder, games: [titleID: CartoucheMacGameSaves(lastSync: synced, failure: "The disk is full.")])
        let report = try XCTUnwrap(backups.problem(of: target))
        XCTAssertEqual(report.message, "The disk is full.")
        XCTAssertNil(backups.news[titleID])
        console.showSaves(folder: folder, games: [titleID: CartoucheMacGameSaves(lastSync: synced, failure: "The disk is full.")])
        XCTAssertEqual(backups.problem(of: target), report)

        // The saves folder away: the saves wait, and the sheet says it is
        // offline; nxnative's own cloud saves keep another game's.
        var away = folder
        away.isAway = true
        console.showSaves(folder: away, games: [titleID: CartoucheMacGameSaves(waiting: true),
                                                "01004D300C5AE000": CartoucheMacGameSaves(inCloud: true)])
        XCTAssertTrue(backups.waiting.contains(titleID))
        XCTAssertNil(backups.problem(of: target))
        XCTAssertTrue(CartoucheStorageReach.shared.isOffline(location.server.id))
        XCTAssertTrue(backups.isLeftToCloud(CartoucheSaveTarget(key: "01004D300C5AE000", name: "Kirby", titleId: "01004D300C5AE000",
                                                                documents: root)))
        console.showSaves(folder: folder, games: [:])
        XCTAssertFalse(CartoucheStorageReach.shared.isOffline(location.server.id))

        // No saves folder: the saves stay on this Mac.
        console.showSaves(folder: nil, games: [:])
        XCTAssertFalse(backups.isOn)
        XCTAssertNil(settings.location(.saves))
    }

    func testTheCopiesComeFromTheBuilderAndTheFolderAwaySaysSo() async throws {
        let console = CartoucheMacConsole.shared
        let backups = CartoucheSaveBackups.shared
        let target = CartoucheSaveTarget(key: titleID, name: "Mario Kart 8 Deluxe", titleId: titleID, documents: root)
        let date = Date(timeIntervalSince1970: 1_794_000_000)
        console.showSaves(folder: folder, games: [:])
        let server = try XCTUnwrap(CartoucheStorageSettings.shared.location(.saves)?.server)

        var asked: [String] = []
        console.onSaveCopies = { titleID in
            asked.append(titleID)
            return [CartoucheMacSaveCopy(name: "2026-11-12T18-00-00Z.zip", date: date, size: 1_310_720)]
        }
        let copies = try await backups.copies(of: target)
        XCTAssertEqual(asked, [titleID])
        XCTAssertEqual(copies, [CartoucheSaveBackup(path: "2026-11-12T18-00-00Z.zip", date: date, size: 1_310_720)])

        // A share not mounted: offline, as a server away from the iPhone.
        console.onSaveCopies = { _ in throw CartoucheMacSaveError.offline }
        do {
            _ = try await backups.copies(of: target)
            XCTFail("the copies of a saves folder away")
        } catch let away as CartoucheStorageOffline {
            XCTAssertEqual(away.name, "the NAS")
        }
        XCTAssertTrue(CartoucheStorageReach.shared.isOffline(server.id))
        // There again: the copies come.
        console.onSaveCopies = { _ in [] }
        let none = try await backups.copies(of: target)
        XCTAssertEqual(none, [])
        XCTAssertFalse(CartoucheStorageReach.shared.isOffline(server.id))

        // Putting one back asks the Builder, by the copy's name.
        var putBack: [String] = []
        console.onPutBackSave = { name, titleID in putBack.append(name + "|" + titleID) }
        console.showSaves(folder: folder, games: [titleID: CartoucheMacGameSaves(fetched: date)])
        try await backups.restore(copies[0], of: target)
        XCTAssertEqual(putBack, ["2026-11-12T18-00-00Z.zip|" + titleID])
        XCTAssertNil(backups.news[titleID], "no news of a copy the player put back")
        XCTAssertFalse(backups.isSyncing)
        console.onPutBackSave = { _, _ in throw CartoucheMacSaveError.busy }
        do {
            try await backups.restore(copies[0], of: target)
            XCTFail("a copy never comes under a game playing")
        } catch {
            XCTAssertEqual(error.localizedDescription, CartoucheText.savesRunning)
        }

        // Sync now: whether it went through.
        var synced: [String] = []
        console.onSyncSaves = { synced.append($0) }
        let went = await backups.syncNow(target)
        XCTAssertTrue(went)
        XCTAssertEqual(synced, [titleID])
        console.onSyncSaves = { _ in throw CartoucheMacSaveError.offline }
        let wentAway = await backups.syncNow(target)
        XCTAssertFalse(wentAway)
        XCTAssertTrue(CartoucheStorageReach.shared.isOffline(server.id))
    }

    func testASaveFromTheSwitchComesInTheBuildersTurn() async throws {
        let console = CartoucheMacConsole.shared
        let backups = CartoucheSaveBackups.shared
        let documents = root.appendingPathComponent("nxnative/\(titleID)", isDirectory: true)
        let target = CartoucheSaveTarget(key: titleID, name: "Mario Kart 8 Deluxe", titleId: titleID, documents: documents)
        // The Mac's save, and the one from the Switch, staged.
        try FileManager.default.createDirectory(at: documents.appendingPathComponent("save"), withIntermediateDirectories: true)
        try Data("mac".utf8).write(to: documents.appendingPathComponent("save/slot0.bin"))
        let staged = root.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staged.appendingPathComponent("save"), withIntermediateDirectories: true)
        try Data("switch".utf8).write(to: staged.appendingPathComponent("save/slot0.bin"))

        var turns: [String] = []
        console.onChangeSaves = { titleID, change in
            turns.append(titleID)
            return try change()
        }
        let kept = try await backups.bringIn(staged, of: target, running: { false })
        XCTAssertEqual(turns, [titleID])
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("save/slot0.bin"), encoding: .utf8), "switch")
        let backup = try XCTUnwrap(kept)
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("save/slot0.bin"), encoding: .utf8), "mac")

        // The one it replaced, put back the same way.
        let before = try XCTUnwrap(CartoucheSwitchSave.backups(CartoucheSwitchSave.beforeImport, in: documents).first)
        try await backups.putBack(beforeImport: before, of: target, running: { false })
        XCTAssertEqual(turns, [titleID, titleID])
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("save/slot0.bin"), encoding: .utf8), "mac")

        // The game started meanwhile, as the console or the Builder says:
        // nothing changes.
        do {
            _ = try await backups.bringIn(staged, of: target, running: { true })
            XCTFail("a save never comes under a game playing")
        } catch {
            XCTAssertEqual(error as? CartoucheSwitchSaveProblem, .running)
        }
        console.onChangeSaves = { _, _ in throw CartoucheMacSaveError.busy }
        do {
            try await backups.putBack(beforeImport: before, of: target, running: { false })
            XCTFail("a save never comes under a game playing")
        } catch {
            XCTAssertEqual(error as? CartoucheSwitchSaveProblem, .running)
        }
        XCTAssertEqual(turns, [titleID, titleID])
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("save/slot0.bin"), encoding: .utf8), "mac")
    }
}
