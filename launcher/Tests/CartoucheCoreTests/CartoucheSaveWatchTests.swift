//
//  CartoucheSaveWatchTests.swift
//  CartoucheCoreTests
//
//  A game's saves while it plays: when those it makes go to the saves
//  folder (CartoucheSaveWatch), and the copy of them that goes, made at one
//  moment, never of a save half written (CartoucheSaveSync.snapshot).
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheSaveWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_795_000_000)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("save-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    // MARK: When they go

    /// A game often saves several times in a row: its saves go once they
    /// have stayed as they are for a few seconds, and once only.
    func testSavesGoOnceTheyHaveStayedAsTheyAreForAFewSeconds() {
        var watch = CartoucheSaveWatch(inStep: "a")
        XCTAssertFalse(watch.due("a", now: at(0)), "in step with the saves folder")
        XCTAssertFalse(watch.due("b", now: at(2)))
        XCTAssertFalse(watch.due("c", now: at(4)), "it saves again")
        XCTAssertFalse(watch.due("c", now: at(6)))
        XCTAssertFalse(watch.due("c", now: at(8)))
        XCTAssertTrue(watch.due("c", now: at(9)), "five seconds without a save")
        watch.sent("c")
        XCTAssertEqual(watch.inStep, "c")
        XCTAssertFalse(watch.due("c", now: at(11)), "never twice the same")
        XCTAssertFalse(watch.due("c", now: at(100)))
        XCTAssertFalse(watch.isPending("c"))
        XCTAssertTrue(watch.isPending("d"))
        XCTAssertFalse(watch.isPending(nil))
    }

    /// A game that never stops saving still has its saves go, a minute after
    /// they first changed.
    func testSavesThatKeepChangingGoAMinuteAfterTheyFirstChanged() {
        var watch = CartoucheSaveWatch(inStep: "a")
        var due: [TimeInterval] = []
        for step in 0 ... 40 {
            let seconds = TimeInterval(step * 2)
            if watch.due("save \(step)", now: at(seconds)) {
                due.append(seconds)
                watch.sent("save \(step)")
            }
        }
        XCTAssertEqual(due, [60], "once a minute while it keeps saving")
    }

    /// A game that never saved, or whose saves are gone, has nothing to send.
    func testNoSavesNothingGoes() {
        var watch = CartoucheSaveWatch(inStep: nil)
        for seconds in stride(from: 0.0, through: 120, by: 2) {
            XCTAssertFalse(watch.due(nil, now: at(seconds)))
        }
        XCTAssertTrue(watch.due("first", now: at(122)) == false)
        XCTAssertTrue(watch.due("first", now: at(127)), "its first saves, never synced")
    }

    /// Saves that did not go are tried again a minute later, as soon as they
    /// change, or as soon as the saves folder's server answers again.
    func testSavesThatDidNotGoAreTriedAgainLater() {
        var watch = CartoucheSaveWatch(inStep: "a")
        XCTAssertFalse(watch.due("b", now: at(0)))
        XCTAssertTrue(watch.due("b", now: at(6)))
        watch.failed(now: at(6))
        XCTAssertFalse(watch.due("b", now: at(8)))
        XCTAssertFalse(watch.due("b", now: at(64)))
        XCTAssertTrue(watch.due("b", now: at(66)), "a minute later")
        watch.failed(now: at(66))
        XCTAssertFalse(watch.due("c", now: at(68)), "changed: it waits for the game to stop saving")
        XCTAssertTrue(watch.due("c", now: at(74)), "then tried at once")
        watch.failed(now: at(74))
        XCTAssertFalse(watch.due("c", now: at(76)))
        watch.retryNow()
        XCTAssertTrue(watch.due("c", now: at(78)), "the server answers again")
    }

    /// Saves that changed while they were copied go once they have stayed
    /// as they are again; those that changed while they went, in their turn.
    func testSavesThatMovedGoOnceTheyStopMoving() {
        var watch = CartoucheSaveWatch(inStep: "a")
        XCTAssertFalse(watch.due("b", now: at(0)))
        XCTAssertTrue(watch.due("b", now: at(6)))
        watch.moved()
        XCTAssertFalse(watch.due("b", now: at(8)), "a few seconds more")
        XCTAssertFalse(watch.due("b", now: at(12)))
        XCTAssertTrue(watch.due("b", now: at(13)))
        // The copy that went was of saves older than those seen since.
        XCTAssertFalse(watch.due("c", now: at(14)))
        watch.sent("b")
        XCTAssertFalse(watch.due("c", now: at(16)))
        XCTAssertTrue(watch.due("c", now: at(19)), "five seconds after they were seen so")
    }

    // MARK: The copy that goes

    /// A game's Documents, as nxnative leaves them: its committed saves in
    /// save/ and save_device/, its working copy, and its logs.
    private func documents() throws -> URL {
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let fileManager = FileManager.default
        for folder in ["save/0000000000000001", "save_device", "save.work", "logs"] {
            try fileManager.createDirectory(at: documents.appendingPathComponent(folder, isDirectory: true),
                                            withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 70_000).write(to: documents.appendingPathComponent("save/0000000000000001/progress.bin"))
        try Data("profil".utf8).write(to: documents.appendingPathComponent("save/profile.dat"))
        try Data("device".utf8).write(to: documents.appendingPathComponent("save_device/common.bin"))
        try Data("working".utf8).write(to: documents.appendingPathComponent("save.work/profile.dat"))
        try Data("log".utf8).write(to: documents.appendingPathComponent("logs/game.log"))
        // Written a while ago, at a date finer than a second.
        for file in ["save/0000000000000001/progress.bin", "save/profile.dat", "save_device/common.bin"] {
            try fileManager.setAttributes([.modificationDate: t0.addingTimeInterval(0.4321)],
                                          ofItemAtPath: documents.appendingPathComponent(file).path)
        }
        return documents
    }

    /// nxnative's commit: the game's working copy swapped whole in place of
    /// its committed saves.
    private func commit(_ text: String, in documents: URL) throws {
        let fileManager = FileManager.default
        let next = documents.appendingPathComponent("save.new", isDirectory: true)
        try fileManager.copyItem(at: documents.appendingPathComponent("save", isDirectory: true), to: next)
        try Data(text.utf8).write(to: next.appendingPathComponent("profile.dat"))
        try fileManager.removeItem(at: documents.appendingPathComponent("save", isDirectory: true))
        try fileManager.moveItem(at: next, to: documents.appendingPathComponent("save", isDirectory: true))
    }

    func testTheCopyHoldsTheSavesAsTheyAre() throws {
        let documents = try documents()
        let into = root.appendingPathComponent("copy", isDirectory: true)
        let snapshot = try XCTUnwrap(CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into))
        XCTAssertEqual(snapshot.documents, into)
        XCTAssertEqual(snapshot.look, CartoucheSaveSync.saves(in: documents)?.look)
        XCTAssertEqual(snapshot.copyLook, snapshot.look, "the files keep their dates")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: into), try CartoucheSaveSync.content(ofSavesIn: documents))
        let names = try FileManager.default.contentsOfDirectory(atPath: into.path).sorted()
        XCTAssertEqual(names, ["save", "save_device"], "the saves alone, not the working copy nor the logs")
        // Made again over what an earlier one left.
        try commit("profil 2", in: documents)
        let again = try XCTUnwrap(CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into))
        XCTAssertEqual(try String(contentsOf: again.documents.appendingPathComponent("save/profile.dat"), encoding: .utf8), "profil 2")
    }

    /// The game commits while the copy is made: the copy, which may hold
    /// files of both saves, is made again, of the save it committed.
    func testACopyMadeWhileTheGameSavesIsMadeAgain() throws {
        let documents = try documents()
        let into = root.appendingPathComponent("copy", isDirectory: true)
        var commits = 0
        let snapshot = try XCTUnwrap(CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into) {
            guard commits == 0 else { return }
            commits += 1
            try? self.commit("profil 2", in: documents)
        })
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(snapshot.look, CartoucheSaveSync.saves(in: documents)?.look, "the save committed last")
        XCTAssertEqual(try String(contentsOf: into.appendingPathComponent("save/profile.dat"), encoding: .utf8), "profil 2")
        XCTAssertEqual(try CartoucheSaveSync.content(ofSavesIn: into), try CartoucheSaveSync.content(ofSavesIn: documents))
    }

    /// A game that commits all the time has no copy made of its saves now:
    /// they go once it stops.
    func testSavesThatKeepChangingHaveNoCopy() throws {
        let documents = try documents()
        let into = root.appendingPathComponent("copy", isDirectory: true)
        var commits = 0
        let snapshot = try CartoucheSaveSync.snapshot(ofSavesIn: documents, into: into) {
            commits += 1
            try? self.commit("profil \(commits + 1)", in: documents)
        }
        XCTAssertNil(snapshot)
        XCTAssertEqual(commits, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: into.path), "nothing left of the copies")
    }

    func testNoSavesNoCopy() throws {
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents.appendingPathComponent("save", isDirectory: true),
                                                withIntermediateDirectories: true)
        XCTAssertNil(try CartoucheSaveSync.snapshot(ofSavesIn: documents, into: root.appendingPathComponent("copy")))
    }

    /// A base made for the saves of the game holds for the copy, and the
    /// base a sync from the copy makes holds for the saves of the game,
    /// whatever the disk the copy is on kept of their dates.
    func testABaseHoldsForTheCopyAndBack() {
        let snapshot = CartoucheSavesSnapshot(documents: root, look: "2|10|1795000000432", copyLook: "2|10|1795000000000")
        let base = CartoucheSaveBase(place: "p", copy: "2026-11-24T08-00-00Z.zip", content: "abc", look: "2|10|1795000000432")
        XCTAssertEqual(snapshot.forCopy(base)?.look, "2|10|1795000000000")
        XCTAssertEqual(snapshot.forGame(snapshot.forCopy(base)), base)
        var other = base
        other.look = "1|5|1794000000000"
        XCTAssertEqual(snapshot.forCopy(other), other, "a base of other saves stays as it is")
        XCTAssertEqual(snapshot.forGame(other), other)
        XCTAssertNil(snapshot.forCopy(nil))
    }
}
