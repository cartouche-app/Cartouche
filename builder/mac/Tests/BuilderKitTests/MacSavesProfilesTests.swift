//
//  MacSavesProfilesTests.swift
//  BuilderKitTests
//
//  What a game played on this Mac keeps beside the saves of its first
//  profile, as on the iPhone (MacSaves.swift, CartoucheSaveSync): the saves
//  of its other profiles and their registry go and come in its copies, and
//  the list of the pipelines it prepared, pso_user.tsv, goes beside them,
//  where every device adds its lines, and comes before the game starts;
//  the sizes the game gave its saves, save.size..., go with them.
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

final class MacSavesProfilesTests: XCTestCase {
    private var root: URL!
    private let game = MacSaveGame(titleID: "0100152000022000", name: "Mario Kart 8 Deluxe")
    /// 12 November 2026, 18:02:00 UTC, in the past.
    private let t0 = Date(timeIntervalSince1970: 1_794_506_520)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var saves: URL { root.appendingPathComponent("Saves", isDirectory: true) }
    private var gameFolder: URL { saves.appendingPathComponent("Mario Kart 8 Deluxe [0100152000022000]", isDirectory: true) }

    /// The saves folder, as the Mac named GAMES keeps its games in
    /// nxnative's folder there.
    private func folder(_ games: String) throws -> MacSavesFolder {
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        return MacSavesFolder(root: saves, games: root.appendingPathComponent(games, isDirectory: true),
                              scratch: root.appendingPathComponent("scratch-\(games)", isDirectory: true))
    }

    private func documents(_ games: String) -> URL {
        root.appendingPathComponent("\(games)/\(game.titleID)", isDirectory: true)
    }

    private func write(_ files: [String: String], in documents: URL, at date: Date) throws {
        for (path, text) in files {
            let url = documents.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func text(_ path: String, in documents: URL) -> String? {
        (try? Data(contentsOf: documents.appendingPathComponent(path))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func testTheOtherProfilesAndThePipelinesGoFromOneMacAndComeToAnother() async throws {
        // Two profiles played on this Mac, which prepared some pipelines.
        let first = try folder("nxnative")
        let mac = documents("nxnative")
        try write(["save/slot0.bin": "joueur 1", "save_user2/slot0.bin": "joueur 2", "save.users": "nxnative-users-1 03\n",
                   "save_device/device.bin": "device", CartoucheSaveSync.pipelinesFile: "S\tabc\t0\nR\t0011\n"],
                  in: mac, at: t0)
        let sent = try await first.sync(game, base: nil, fetching: false)
        XCTAssertEqual(sent.step, .send)
        XCTAssertEqual(sent.pipelines, CartouchePipelinesMoved(came: false, went: true))
        let copy = try XCTUnwrap(sent.sent)
        XCTAssertEqual(names(in: gameFolder), [copy, CartoucheSaveSync.pipelinesFile])
        let entries = try await CartoucheZip.entries(of: CartoucheFileSource(gameFolder.appendingPathComponent(copy)))
        XCTAssertEqual(Set(entries.filter { !$0.isDirectory }.map(\.name)),
                       ["save/slot0.bin", "save_user2/slot0.bin", "save.users", "save_device/device.bin"])
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: gameFolder), "S\tabc\t0\nR\t0011\n")

        // Another Mac, its game never played: before it starts, the saves of
        // both profiles come, and the pipelines to prepare.
        let second = try folder("other")
        let other = documents("other")
        let came = try await second.sync(game, base: nil, fetching: true)
        XCTAssertEqual(came.step, .fetch)
        XCTAssertEqual(came.pipelines, CartouchePipelinesMoved(came: true, went: false))
        XCTAssertEqual(text("save_user2/slot0.bin", in: other), "joueur 2")
        XCTAssertEqual(text("save.users", in: other), "nxnative-users-1 03\n")
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: other), "S\tabc\t0\nR\t0011\n")

        // That Mac prepares more as it plays: they go after the game, after
        // the first Mac's lines, which take them before their next game.
        try write([CartoucheSaveSync.pipelinesFile: "S\tabc\t0\nR\t0011\nR\t0022\n"], in: other, at: t0.addingTimeInterval(600))
        let after = try await second.sync(game, base: came.base, fetching: false)
        XCTAssertEqual(after.step, .none, "no copy for pipelines prepared")
        XCTAssertEqual(after.pipelines, CartouchePipelinesMoved(came: false, went: true))
        let back = try await first.sync(game, base: sent.base, fetching: true)
        XCTAssertEqual(back.step, .none)
        XCTAssertEqual(back.pipelines, CartouchePipelinesMoved(came: true, went: false))
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: mac), "S\tabc\t0\nR\t0011\nR\t0022\n")
    }

    func testACopyOfAnOlderCartoucheLeavesTheOtherProfiles() async throws {
        let folder = try folder("nxnative")
        let mac = documents("nxnative")
        try write(["save/slot0.bin": "joueur 1", "save_user2/slot0.bin": "joueur 2", "save.users": "nxnative-users-1 03\n"],
                  in: mac, at: t0)
        let base = try await folder.sync(game, base: nil, fetching: false).base
        // An iPhone of an older Cartouche plays the first profile further.
        let iPhone = root.appendingPathComponent("iPhone/Documents", isDirectory: true)
        try write(["save/slot0.bin": "joueur 1, plus loin"], in: iPhone, at: t0.addingTimeInterval(3_600))
        let sink = try CartoucheFileSink(gameFolder.appendingPathComponent(CartoucheSaveSync.fileName(t0.addingTimeInterval(3_600))))
        try await CartoucheSaveSync.writeZip(ofSavesIn: iPhone, to: sink)
        try sink.close()
        let came = try await folder.sync(game, base: base, fetching: true)
        XCTAssertEqual(came.step, .fetch)
        XCTAssertEqual(text("save/slot0.bin", in: mac), "joueur 1, plus loin")
        XCTAssertEqual(text("save_user2/slot0.bin", in: mac), "joueur 2")
        XCTAssertEqual(text("save.users", in: mac), "nxnative-users-1 03\n")
        // In step since: nothing goes back.
        let again = try await folder.sync(game, base: came.base, fetching: false)
        XCTAssertEqual(again.step, .none)
    }

    func testTheSizesTheGameGaveItsSavesGoFromOneMacToAnother() async throws {
        // The game made its saves larger on this Mac (ExtendSaveData).
        let first = try folder("nxnative")
        let mac = documents("nxnative")
        try write(["save/slot0.bin": "joueur 1", "save.size": "67108864 1048576\n",
                   "save_user2/slot0.bin": "joueur 2", "save_user2.size": "134217728 1048576\n", "save.users": "nxnative-users-1 03\n"],
                  in: mac, at: t0)
        let sent = try await first.sync(game, base: nil, fetching: false)
        XCTAssertEqual(sent.step, .send)
        let copy = try XCTUnwrap(sent.sent)
        let entries = try await CartoucheZip.entries(of: CartoucheFileSource(gameFolder.appendingPathComponent(copy)))
        XCTAssertTrue(entries.contains { $0.name == "save.size" })
        XCTAssertTrue(entries.contains { $0.name == "save_user2.size" })

        // Another Mac, its game never played, finds them as large.
        let second = try folder("other")
        let other = documents("other")
        let came = try await second.sync(game, base: nil, fetching: true)
        XCTAssertEqual(came.step, .fetch)
        XCTAssertEqual(text("save.size", in: other), "67108864 1048576\n")
        XCTAssertEqual(text("save_user2.size", in: other), "134217728 1048576\n")

        // An iPhone of an older Cartouche plays the first profile further,
        // its save never made larger there: its copy takes the size away
        // with the save it replaces, and leaves the second profile's.
        let iPhone = root.appendingPathComponent("iPhone/Documents", isDirectory: true)
        try write(["save/slot0.bin": "joueur 1, sur l'iPhone"], in: iPhone, at: t0.addingTimeInterval(3_600))
        let sink = try CartoucheFileSink(gameFolder.appendingPathComponent(CartoucheSaveSync.fileName(t0.addingTimeInterval(3_600))))
        try await CartoucheSaveSync.writeZip(ofSavesIn: iPhone, to: sink)
        try sink.close()
        let back = try await first.sync(game, base: sent.base, fetching: true)
        XCTAssertEqual(back.step, .fetch)
        XCTAssertEqual(text("save/slot0.bin", in: mac), "joueur 1, sur l'iPhone")
        XCTAssertNil(text("save.size", in: mac))
        XCTAssertEqual(text("save_user2.size", in: mac), "134217728 1048576\n")
    }

    func testTheCopyMadeWhileTheGamePlaysSendsNoPipelines() async throws {
        let folder = try folder("nxnative")
        let mac = documents("nxnative")
        try write(["save/slot0.bin": "joueur 1", CartoucheSaveSync.pipelinesFile: "S\tabc\t0\n"], in: mac, at: t0)
        let keeper = MacSaveKeeper(store: MacSaveStore(url: root.appendingPathComponent("saves.json")))
        let played = await keeper.sendPlaying(game, from: mac, in: folder, scratch: root.appendingPathComponent("scratch", isDirectory: true),
                                              now: t0.addingTimeInterval(5))
        XCTAssertEqual(played.event?.step, "send")
        XCTAssertEqual(names(in: gameFolder), [CartoucheSaveSync.fileName(t0)], "the list waits for the game's end")
        // After the game, it goes.
        _ = await keeper.sync(game, in: folder, when: .after, now: t0.addingTimeInterval(60))
        XCTAssertEqual(text(CartoucheSaveSync.pipelinesFile, in: gameFolder), "S\tabc\t0\n")
    }
}
