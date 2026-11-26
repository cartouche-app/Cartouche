//
//  CartoucheSaveSizesTests.swift
//  CartoucheCoreTests
//
//  The size a game gave its saves (Sources/CartoucheSaveSync.swift):
//  nxnative's records of it beside each folder of saves, save.size,
//  save_device.size and save_userN.size, go and come in the copies with
//  the saves they were given to, count in what tells that the saves
//  changed, and go when a copy without them, as one made before, replaces
//  their saves, as nxnative's own sync does.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheSaveSizesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("CartoucheSaveSizesTests-\(UUID().uuidString)")
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

    /// A game's Documents as nxnative leaves them once the game made its
    /// saves larger, its first profile's, the device's and the second
    /// profile's (ExtendSaveData, ExtendDeviceSaveData), with a record
    /// being written.
    private func documents(_ name: String = "Documents") throws -> URL {
        let documents = folder.appendingPathComponent(name, isDirectory: true)
        try write("partie 1", "save/progress.bin", in: documents)
        try write("appareil", "save_device/common.bin", in: documents)
        try write("partie 2", "save_user2/progress.bin", in: documents)
        try write("nxnative-users-1 03\n", "save.users", in: documents)
        try write("67108864 1048576\n", "save.size", in: documents)
        try write("33554432 16777216\n", "save_device.size", in: documents)
        try write("134217728 1048576\n", "save_user2.size", in: documents)
        try write("268435456 1048576\n", "save.size.tmp", in: documents)
        return documents
    }

    private func zip(of documents: URL) async throws -> (data: Data, entries: [CartoucheZipEntry]) {
        let sink = MemorySink()
        try await CartoucheSaveSync.writeZip(ofSavesIn: documents, to: sink, gameVersion: "1.0.0")
        return (sink.data, try await CartoucheZip.entries(of: MemorySource(sink.data)))
    }

    /// The copy of DOCUMENTS' saves, unpacked as it comes.
    private func unpacked(_ documents: URL) async throws -> (folder: URL, entries: [CartoucheZipEntry]) {
        let (data, entries) = try await zip(of: documents)
        let unpacked = folder.appendingPathComponent("Unpacked-\(UUID().uuidString)", isDirectory: true)
        try await CartoucheZip.extract(MemorySource(data), entries: entries, into: unpacked)
        return (unpacked, entries)
    }

    func testACopyHoldsTheSizesOfItsSaves() async throws {
        let documents = try documents()
        let (_, entries) = try await zip(of: documents)
        let files = Set(entries.filter { !$0.isDirectory }.map(\.name))
        XCTAssertEqual(files, ["save/progress.bin", "save_device/common.bin", "save_user2/progress.bin", "save.users",
                               "save.size", "save_device.size", "save_user2.size"],
                       "each save's size, never a record half written")
        XCTAssertTrue(CartoucheSaveSync.holdsSavesOnly(entries))
        XCTAssertEqual(CartoucheSaveSync.content(of: entries), try CartoucheSaveSync.content(ofSavesIn: documents))
    }

    func testASizeTheGameGaveChangesTheSaves() throws {
        let documents = folder.appendingPathComponent("Single", isDirectory: true)
        try write("partie 1", "save/progress.bin", in: documents)
        let look = try XCTUnwrap(CartoucheSaveSync.saves(in: documents)).look
        let content = try CartoucheSaveSync.content(ofSavesIn: documents)
        // The game makes its save larger, and nothing else.
        try write("67108864 1048576\n", "save.size", in: documents)
        XCTAssertNotEqual(CartoucheSaveSync.saves(in: documents)?.look, look)
        XCTAssertNotEqual(try CartoucheSaveSync.content(ofSavesIn: documents), content)
        let larger = try CartoucheSaveSync.content(ofSavesIn: documents)
        try write("134217728 1048576\n", "save.size", in: documents)
        XCTAssertNotEqual(try CartoucheSaveSync.content(ofSavesIn: documents), larger)
        // The device's too.
        try write("33554432 16777216\n", "save_device.size", in: documents)
        XCTAssertNotEqual(try CartoucheSaveSync.content(ofSavesIn: documents), larger)
    }

    func testASizeWithoutASaveIsNone() throws {
        // As nxnative packs the sizes only of saves there are.
        let documents = folder.appendingPathComponent("Sizes", isDirectory: true)
        try write("67108864 1048576\n", "save.size", in: documents)
        try write("33554432 16777216\n", "save_device.size", in: documents)
        XCTAssertNil(CartoucheSaveSync.saves(in: documents))
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: documents), "")
    }

    func testACopyOfAnotherRecordIsNone() async throws {
        for name in ["save.size.tmp", "save_user9.size", "save.work.size", "save_device.size.tmp"] {
            let sink = MemorySink()
            let writer = CartoucheZipWriter(sink: sink)
            try await writer.addData("save/progress.bin", Data("partie".utf8))
            try await writer.addData(name, Data("1 0\n".utf8))
            try await writer.finish()
            let entries = try await CartoucheZip.entries(of: MemorySource(sink.data))
            XCTAssertFalse(CartoucheSaveSync.holdsSavesOnly(entries), name)
        }
    }

    func testACopyBringsTheSizesOfItsSaves() async throws {
        let documents = try documents()
        // Another device's saves, made larger still there.
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try write("autre partie 1", "save/progress.bin", in: other)
        try write("autre appareil", "save_device/common.bin", in: other)
        try write("autre partie 2", "save_user2/progress.bin", in: other)
        try write("nxnative-users-1 03\n", "save.users", in: other)
        try write("134217728 2097152\n", "save.size", in: other)
        try write("67108864 16777216\n", "save_device.size", in: other)
        try write("268435456 1048576\n", "save_user2.size", in: other)
        let (unpacked, entries) = try await unpacked(other)
        let aside = folder.appendingPathComponent("Aside", isDirectory: true)

        try CartoucheSaveSync.replaceSaves(in: documents, with: unpacked, aside: aside)
        XCTAssertEqual(text("save.size", in: documents), "134217728 2097152\n")
        XCTAssertEqual(text("save_device.size", in: documents), "67108864 16777216\n")
        XCTAssertEqual(text("save_user2.size", in: documents), "268435456 1048576\n")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: documents), CartoucheSaveSync.content(of: entries))
        // Those replaced are aside.
        XCTAssertEqual(text("save.size", in: aside), "67108864 1048576\n")
        XCTAssertEqual(text("save_user2.size", in: aside), "134217728 1048576\n")
    }

    func testACopyWithoutTheSizesTakesThemAwayWithTheSavesItReplaces() async throws {
        let documents = try documents()
        // A copy made before the game made its saves larger, of the first
        // profile's saves only, as an older Cartouche made it.
        let older = folder.appendingPathComponent("Older", isDirectory: true)
        try write("partie 1, avant", "save/progress.bin", in: older)
        try write("appareil, avant", "save_device/common.bin", in: older)
        let (first, entries) = try await unpacked(older)
        XCTAssertFalse(CartoucheSaveSync.holdsProfiles(entries))
        let aside = folder.appendingPathComponent("Aside", isDirectory: true)

        try CartoucheSaveSync.replaceSaves(in: documents, with: first, aside: aside)
        XCTAssertFalse(exists("save.size", in: documents), "the size goes with the save it was given to")
        XCTAssertFalse(exists("save_device.size", in: documents))
        XCTAssertEqual(text("save.size", in: aside), "67108864 1048576\n")
        XCTAssertEqual(text("save_device.size", in: aside), "33554432 16777216\n")
        // The second profile, which the copy leaves as it is, keeps its size.
        XCTAssertEqual(text("save_user2/progress.bin", in: documents), "partie 2")
        XCTAssertEqual(text("save_user2.size", in: documents), "134217728 1048576\n")

        // A copy that holds the second profile, saved before it was made
        // larger, takes its size away too.
        let profiles = folder.appendingPathComponent("Profiles", isDirectory: true)
        try write("partie 1, avant", "save/progress.bin", in: profiles)
        try write("partie 2, avant", "save_user2/progress.bin", in: profiles)
        try write("nxnative-users-1 03\n", "save.users", in: profiles)
        let (again, _) = try await unpacked(profiles)
        try CartoucheSaveSync.replaceSaves(in: documents, with: again, aside: folder.appendingPathComponent("Aside 2", isDirectory: true))
        XCTAssertEqual(text("save_user2/progress.bin", in: documents), "partie 2, avant")
        XCTAssertFalse(exists("save_user2.size", in: documents))
    }

    func testACopyOfAProfilesSizeAloneHoldsProfiles() async throws {
        // The second profile, made larger before it saved anything.
        let sink = MemorySink()
        let writer = CartoucheZipWriter(sink: sink)
        try await writer.addData("save/progress.bin", Data("partie".utf8))
        try await writer.addData("save_user2.size", Data("134217728 1048576\n".utf8))
        try await writer.finish()
        let entries = try await CartoucheZip.entries(of: MemorySource(sink.data))
        XCTAssertTrue(CartoucheSaveSync.holdsSavesOnly(entries))
        XCTAssertTrue(CartoucheSaveSync.holdsProfiles(entries))
    }

    func testTheCopyMadeWhileTheGamePlaysHoldsTheSizes() throws {
        let documents = try documents()
        let into = folder.appendingPathComponent("copy", isDirectory: true)
        let snapshot = try XCTUnwrap(CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into))
        XCTAssertEqual(snapshot.copyLook, snapshot.look, "the records keep their dates")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: into), try CartoucheSaveSync.content(ofSavesIn: documents))
        let names = try FileManager.default.contentsOfDirectory(atPath: into.path).sorted()
        XCTAssertEqual(names, ["save", "save.size", "save.users", "save_device", "save_device.size", "save_user2", "save_user2.size"])
    }
}
