//
//  CartoucheSaveProfilesTests.swift
//  CartoucheCoreTests
//
//  What a game keeps beside the saves of its first profile
//  (Sources/CartoucheSaveSync.swift): the saves of its other profiles, 2 to
//  8, and their registry, which go and come in its copies, a copy an older
//  Cartouche made leaving them as they are; and the list of the pipelines
//  it prepared, pso_user.tsv, which is no save, and goes beside the copies,
//  every device adding its lines to it.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheSaveProfilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("CartoucheSaveProfilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, _ path: String, in documents: URL) throws {
        let url = documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func text(_ path: String, in documents: URL) -> String? {
        (try? Data(contentsOf: documents.appendingPathComponent(path))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func exists(_ path: String, in documents: URL) -> Bool {
        FileManager.default.fileExists(atPath: documents.appendingPathComponent(path).path)
    }

    /// A game's Documents as nxnative leaves them once the player added
    /// profiles 2 and 3: their saves beside the first's, the registry, the
    /// working copies of each, a registry being written, and the list of
    /// pipelines.
    private func documents(_ name: String = "Documents") throws -> URL {
        let documents = folder.appendingPathComponent(name, isDirectory: true)
        try write("partie 1", "save/progress.bin", in: documents)
        try write("appareil", "save_device/common.bin", in: documents)
        try write("partie 2", "save_user2/progress.bin", in: documents)
        try write("partie 3", "save_user3/progress.bin", in: documents)
        try write("nxnative-users-1 07\n", "save.users", in: documents)
        try write("en cours", "save.work/progress.bin", in: documents)
        try write("en cours", "save_user2.work/progress.bin", in: documents)
        try write("à moitié", "save_user3.new/progress.bin", in: documents)
        try write("nxnative-users-1 0f\n", "save.users.Ab12Cd", in: documents)
        try write("S\tabc\t0\nR\t0011\n", CartoucheSaveSync.pipelinesFile, in: documents)
        try write("journal", "log.txt", in: documents)
        return documents
    }

    private func zip(of documents: URL) async throws -> (data: Data, entries: [CartoucheZipEntry]) {
        let sink = MemorySink()
        try await CartoucheSaveSync.writeZip(ofSavesIn: documents, to: sink, gameVersion: "1.0.0")
        return (sink.data, try await CartoucheZip.entries(of: MemorySource(sink.data)))
    }

    // MARK: The other profiles

    func testACopyHoldsTheOtherProfilesAndTheirRegistry() async throws {
        let documents = try documents()
        let (_, entries) = try await zip(of: documents)
        let files = Set(entries.filter { !$0.isDirectory }.map(\.name))
        XCTAssertEqual(files, ["save/progress.bin", "save_device/common.bin", "save_user2/progress.bin",
                               "save_user3/progress.bin", "save.users"],
                       "the profiles and their registry, never their working copies, a registry half written nor the pipelines")
        XCTAssertTrue(CartoucheSaveSync.holdsSavesOnly(entries))
        XCTAssertTrue(CartoucheSaveSync.holdsProfiles(entries))
        // What it holds is what the saves hold, profiles included.
        XCTAssertEqual(CartoucheSaveSync.content(of: entries), try CartoucheSaveSync.content(ofSavesIn: documents))
    }

    func testAnotherProfileThatPlaysChangesTheSaves() throws {
        let documents = try documents()
        let look = try XCTUnwrap(CartoucheSaveSync.saves(in: documents)).look
        let content = try CartoucheSaveSync.content(ofSavesIn: documents)
        try write("partie 2, plus loin", "save_user2/progress.bin", in: documents)
        XCTAssertNotEqual(CartoucheSaveSync.saves(in: documents)?.look, look)
        XCTAssertNotEqual(try CartoucheSaveSync.content(ofSavesIn: documents), content)
        // A profile added: the registry changed.
        let again = try CartoucheSaveSync.content(ofSavesIn: documents)
        try write("nxnative-users-1 0f\n", "save.users", in: documents)
        XCTAssertNotEqual(try CartoucheSaveSync.content(ofSavesIn: documents), again)
        // Saves of the second profile alone are saves.
        let only = folder.appendingPathComponent("Only", isDirectory: true)
        try write("partie 2", "save_user2/progress.bin", in: only)
        XCTAssertNotNil(CartoucheSaveSync.saves(in: only))
    }

    func testAGameWithoutOtherProfilesLooksAsBefore() async throws {
        // The look and content an older Cartouche gave the same saves, kept
        // in its bases: a game no profile was added to makes no new copy.
        let documents = folder.appendingPathComponent("Single", isDirectory: true)
        try write("partie 1", "save/progress.bin", in: documents)
        try write("appareil", "save_device/common.bin", in: documents)
        try write("S\tabc\t0\n", CartoucheSaveSync.pipelinesFile, in: documents)
        let saves = try XCTUnwrap(CartoucheSaveSync.saves(in: documents))
        XCTAssertTrue(saves.look.hasPrefix("2|16|"))
        let (_, entries) = try await zip(of: documents)
        XCTAssertEqual(Set(entries.map(\.name)), ["save/", "save/progress.bin", "save_device/", "save_device/common.bin"])
        XCTAssertFalse(CartoucheSaveSync.holdsProfiles(entries))
    }

    func testACopyOfOtherFoldersIsNone() async throws {
        for name in ["save_user9/progress.bin", "save_user2.work/progress.bin", "save.users.Ab12Cd", "pso_user.tsv"] {
            let sink = MemorySink()
            let writer = CartoucheZipWriter(sink: sink)
            try await writer.addData("save/progress.bin", Data("partie".utf8))
            try await writer.addData(name, Data("autre".utf8))
            try await writer.finish()
            let entries = try await CartoucheZip.entries(of: MemorySource(sink.data))
            XCTAssertFalse(CartoucheSaveSync.holdsSavesOnly(entries), name)
        }
    }

    /// The copy of DOCUMENTS' saves, unpacked as it comes.
    private func unpacked(_ documents: URL) async throws -> (folder: URL, entries: [CartoucheZipEntry]) {
        let (data, entries) = try await zip(of: documents)
        let unpacked = folder.appendingPathComponent("Unpacked-\(UUID().uuidString)", isDirectory: true)
        try await CartoucheZip.extract(MemorySource(data), entries: entries, into: unpacked)
        return (unpacked, entries)
    }

    func testACopyWithProfilesReplacesThemAll() async throws {
        let documents = try documents()
        // Another device's saves: the second profile further on, no third.
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try write("autre partie 1", "save/progress.bin", in: other)
        try write("autre partie 2", "save_user2/progress.bin", in: other)
        try write("nxnative-users-1 03\n", "save.users", in: other)
        let (unpacked, entries) = try await unpacked(other)
        let aside = folder.appendingPathComponent("Aside", isDirectory: true)

        try CartoucheSaveSync.replaceSaves(in: documents, with: unpacked, aside: aside)
        XCTAssertEqual(text("save/progress.bin", in: documents), "autre partie 1")
        XCTAssertEqual(text("save_user2/progress.bin", in: documents), "autre partie 2")
        XCTAssertEqual(text("save.users", in: documents), "nxnative-users-1 03\n")
        // Both sides hold the same, and nxnative makes its working copies
        // again from them.
        XCTAssertFalse(exists("save_user3", in: documents))
        XCTAssertFalse(exists("save_device", in: documents))
        XCTAssertFalse(exists("save.work", in: documents))
        XCTAssertFalse(exists("save_user2.work", in: documents))
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: documents), CartoucheSaveSync.content(of: entries))
        // What was replaced is aside; the list of pipelines, no save, stays.
        XCTAssertEqual(text("save_user3/progress.bin", in: aside), "partie 3")
        XCTAssertEqual(text("save.users", in: aside), "nxnative-users-1 07\n")
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\tabc\t0\nR\t0011\n")
        XCTAssertEqual(text("log.txt", in: documents), "journal")
    }

    func testACopyWithoutProfilesLeavesThemAsTheyAre() async throws {
        let documents = try documents()
        // A copy an older Cartouche made, of the first profile's saves.
        let older = folder.appendingPathComponent("Older", isDirectory: true)
        try write("autre partie 1", "save/progress.bin", in: older)
        try write("autre appareil", "save_device/common.bin", in: older)
        let (unpacked, entries) = try await unpacked(older)
        XCTAssertFalse(CartoucheSaveSync.holdsProfiles(entries))

        try CartoucheSaveSync.replaceSaves(in: documents, with: unpacked, aside: folder.appendingPathComponent("Aside", isDirectory: true))
        XCTAssertEqual(text("save/progress.bin", in: documents), "autre partie 1")
        XCTAssertEqual(text("save_device/common.bin", in: documents), "autre appareil")
        XCTAssertEqual(text("save_user2/progress.bin", in: documents), "partie 2")
        XCTAssertEqual(text("save_user3/progress.bin", in: documents), "partie 3")
        XCTAssertEqual(text("save.users", in: documents), "nxnative-users-1 07\n")
        XCTAssertTrue(exists("save_user2.work", in: documents), "the profiles' own working copies stay with them")
        XCTAssertFalse(exists("save.work", in: documents))
    }

    func testAProfilesCopyThatFailsLeavesTheSavesAsTheyWere() async throws {
        let documents = try documents()
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try write("autre partie 2", "save_user2/progress.bin", in: other)
        let (unpacked, _) = try await unpacked(other)
        // The second profile's place aside is taken: its move fails, once
        // the first profile's saves went aside.
        let aside = folder.appendingPathComponent("Aside", isDirectory: true)
        try write("occupé", "save_user2", in: aside)
        XCTAssertThrowsError(try CartoucheSaveSync.replaceSaves(in: documents, with: unpacked, aside: aside))
        XCTAssertEqual(text("save/progress.bin", in: documents), "partie 1")
        XCTAssertEqual(text("save_device/common.bin", in: documents), "appareil")
        XCTAssertEqual(text("save_user2/progress.bin", in: documents), "partie 2")
        XCTAssertEqual(text("save.users", in: documents), "nxnative-users-1 07\n")
    }

    func testTheCopyMadeWhileTheGamePlaysHoldsTheProfiles() throws {
        let documents = try documents()
        let into = folder.appendingPathComponent("copy", isDirectory: true)
        let snapshot = try XCTUnwrap(CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into))
        XCTAssertEqual(snapshot.copyLook, snapshot.look, "the files keep their dates")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: into), try CartoucheSaveSync.content(ofSavesIn: documents))
        let names = try FileManager.default.contentsOfDirectory(atPath: into.path).sorted()
        XCTAssertEqual(names, ["save", "save.users", "save_device", "save_user2", "save_user3"],
                       "the saves alone: no working copy, no list of pipelines")
    }

    // MARK: The pipelines

    func testThePipelinesAreNoSave() throws {
        let documents = try documents()
        let look = try XCTUnwrap(CartoucheSaveSync.saves(in: documents)).look
        let content = try CartoucheSaveSync.content(ofSavesIn: documents)
        // The game prepared more, a minute after its last save.
        let list = documents.appendingPathComponent(CartoucheSaveSync.pipelinesFile)
        try Data("S\tabc\t0\nR\t0011\nR\t0022\n".utf8).write(to: list)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: list.path)
        XCTAssertEqual(CartoucheSaveSync.saves(in: documents)?.look, look, "no copy for pipelines prepared")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: documents), content)
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testListsAddTheLinesTheyLack() {
        // Their lines after mine, in their order, each once.
        XCTAssertEqual(CartoucheSaveSync.pipelines(data("S\ta\t0\nR\t01\n"), adding: data("R\t02\nR\t01\nS\tb\t1\n")),
                       data("S\ta\t0\nR\t01\nR\t02\nS\tb\t1\n"))
        // Nothing to add.
        XCTAssertNil(CartoucheSaveSync.pipelines(data("S\ta\t0\nR\t01\n"), adding: data("R\t01\n")))
        XCTAssertNil(CartoucheSaveSync.pipelines(data("S\ta\t0\n"), adding: data("")))
        XCTAssertNil(CartoucheSaveSync.pipelines(nil, adding: data("\n\n")))
        // No list here: theirs.
        XCTAssertEqual(CartoucheSaveSync.pipelines(nil, adding: data("R\t01\n")), data("R\t01\n"))
        // A line the game was writing as the list was read is left out.
        XCTAssertEqual(CartoucheSaveSync.pipelines(data("R\t01\n"), adding: data("R\t02\nR\t0")), data("R\t01\nR\t02\n"))
        // A last line mine did not end is ended first.
        XCTAssertEqual(CartoucheSaveSync.pipelines(data("R\t01\nR\t0"), adding: data("R\t03\n")), data("R\t01\nR\t0\nR\t03\n"))
    }

    func testWhenAListMoves() {
        // Comes when the game is installed or about to start, sizes apart.
        XCTAssertTrue(CartoucheSaveSync.bringsPipelines(here: nil, there: 40, fetching: true))
        XCTAssertTrue(CartoucheSaveSync.bringsPipelines(here: 30, there: 40, fetching: true))
        XCTAssertTrue(CartoucheSaveSync.bringsPipelines(here: 50, there: 40, fetching: true))
        XCTAssertFalse(CartoucheSaveSync.bringsPipelines(here: 40, there: 40, fetching: true))
        XCTAssertFalse(CartoucheSaveSync.bringsPipelines(here: nil, there: 40, fetching: false))
        XCTAssertFalse(CartoucheSaveSync.bringsPipelines(here: nil, there: nil, fetching: true))
        XCTAssertFalse(CartoucheSaveSync.bringsPipelines(here: nil, there: 0, fetching: true))
        XCTAssertFalse(CartoucheSaveSync.bringsPipelines(here: nil, there: UInt64(CartoucheSaveSync.pipelinesLimit) + 1, fetching: true))
        // Goes when larger than the folder's, or the folder has none.
        XCTAssertTrue(CartoucheSaveSync.sendsPipelines(here: 40, there: nil))
        XCTAssertTrue(CartoucheSaveSync.sendsPipelines(here: 50, there: 40))
        XCTAssertFalse(CartoucheSaveSync.sendsPipelines(here: 40, there: 40))
        XCTAssertFalse(CartoucheSaveSync.sendsPipelines(here: 30, there: 40))
        XCTAssertFalse(CartoucheSaveSync.sendsPipelines(here: nil, there: 40))
        XCTAssertFalse(CartoucheSaveSync.sendsPipelines(here: 0, there: nil))
    }

    /// The list beside a game's copies, in memory, which counts how it is
    /// read and written.
    private final class Beside {
        var list: Data?
        var reads = 0
        var writes = 0
        var fails = false

        init(_ list: String?) { self.list = list.map { Data($0.utf8) } }

        var size: UInt64? { list.map { UInt64($0.count) } }

        func read() throws -> Data {
            reads += 1
            if fails { throw CocoaError(.fileReadUnknown) }
            guard let list else { throw CocoaError(.fileNoSuchFile) }
            return list
        }

        func write(_ data: Data) throws {
            writes += 1
            if fails { throw CocoaError(.fileWriteUnknown) }
            list = data
        }
    }

    private func keep(_ documents: URL, _ beside: Beside, fetching: Bool, quiet: Bool = true) async -> CartouchePipelinesMoved {
        await CartoucheSaveSync.keepPipelines(in: documents, there: beside.size, fetching: fetching, quiet: { quiet },
                                              read: { try beside.read() }, write: { try beside.write($0) })
    }

    func testAReinstalledGameGetsItsPipelinesBack() async throws {
        // Reinstalled, or reset: no list here.
        let documents = folder.appendingPathComponent("Reinstalled", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let beside = Beside("S\ta\t0\nR\t01\n")
        let moved = await keep(documents, beside, fetching: true)
        XCTAssertEqual(moved, CartouchePipelinesMoved(came: true, went: false))
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\ta\t0\nR\t01\n")
        XCTAssertEqual(beside.writes, 0)
        // In step: nothing read, nothing written.
        let again = await keep(documents, beside, fetching: true)
        XCTAssertEqual(again, CartouchePipelinesMoved())
        XCTAssertEqual(beside.reads, 1)
    }

    func testWhatTheGamePreparedGoesAfterIt() async throws {
        let documents = try documents()
        let beside = Beside("S\tabc\t0\n")
        // After the game: what it prepared goes, after the folder's lines.
        let moved = await keep(documents, beside, fetching: false)
        XCTAssertEqual(moved, CartouchePipelinesMoved(came: false, went: true))
        XCTAssertEqual(beside.list, data("S\tabc\t0\nR\t0011\n"))
        // A game never had the folder's list taken in while it may run.
        let other = Beside("S\tabc\t0\nR\t0011\nR\t0099\nR\t0098\n")
        let after = await keep(documents, other, fetching: false)
        XCTAssertEqual(after, CartouchePipelinesMoved())
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\tabc\t0\nR\t0011\n")
        XCTAssertEqual(other.reads + other.writes, 0)
        // No folder list yet: the game's whole lines go.
        let none = Beside(nil)
        let first = await keep(documents, none, fetching: false)
        XCTAssertEqual(first, CartouchePipelinesMoved(came: false, went: true))
        XCTAssertEqual(none.list, data("S\tabc\t0\nR\t0011\n"))
        XCTAssertEqual(none.reads, 0)
    }

    func testTwoDevicesEndWithTheLinesOfBoth() async throws {
        // This device prepared some, another device others.
        let documents = try documents()
        let beside = Beside("S\tabc\t0\nR\t0077\nR\t0078\nR\t0079\n")
        let moved = await keep(documents, beside, fetching: true)
        XCTAssertEqual(moved, CartouchePipelinesMoved(came: true, went: true))
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\tabc\t0\nR\t0011\nR\t0077\nR\t0078\nR\t0079\n")
        XCTAssertEqual(beside.list, data("S\tabc\t0\nR\t0077\nR\t0078\nR\t0079\nR\t0011\n"))
        XCTAssertEqual(beside.reads, 1, "read once")
        // The same lines on both sides, in their own order: in step.
        let again = await keep(documents, beside, fetching: true)
        XCTAssertEqual(again, CartouchePipelinesMoved())
    }

    func testAGameStartedMeanwhileKeepsItsList() async throws {
        // On a Mac, from the Dock, as the folder's list was read.
        let documents = try documents()
        let beside = Beside("S\tabc\t0\nR\t0011\nR\t0077\n")
        let moved = await keep(documents, beside, fetching: true, quiet: false)
        XCTAssertEqual(moved, CartouchePipelinesMoved())
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\tabc\t0\nR\t0011\n")
    }

    func testAListThatCannotMoveHoldsNothingUp() async throws {
        let documents = try documents()
        let beside = Beside("S\tabc\t0\nR\t0077\nR\t0078\nR\t0079\n")
        beside.fails = true
        let moved = await keep(documents, beside, fetching: true)
        XCTAssertEqual(moved, CartouchePipelinesMoved())
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: documents), "S\tabc\t0\nR\t0011\n")
        // None here, none there: nothing to do.
        let empty = folder.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let none = Beside(nil)
        let nothing = await keep(empty, none, fetching: true)
        XCTAssertEqual(nothing, CartouchePipelinesMoved())
        XCTAssertEqual(none.reads + none.writes, 0)
    }
}
