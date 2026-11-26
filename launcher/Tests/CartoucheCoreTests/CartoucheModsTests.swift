import XCTest
@testable import CartoucheCore

/// A game's mods (CartoucheMods.swift): what the player picks, read; the
/// mods kept in the game's folder, in their order; and the line of its
/// env.txt that hands them to nxnative before each start.
final class CartoucheModsTests: XCTestCase {
    private let game = "0100F2C0115B6000"
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CartoucheModsTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }

    private func file(_ path: String, in folder: URL, _ text: String = "data") throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func items(_ paths: [String]) -> [CartoucheModItem] {
        paths.map { path in
            path.hasSuffix("/") ? CartoucheModItem(path: path, isFolder: true) : CartoucheModItem(path: path, size: 10)
        }
    }

    // MARK: What the player picked

    func testAModsRomfsFolderIsFoundUnderItsOwnFolderOrAtTheRoot() throws {
        let nested = try CartoucheMods.plan(items(["Better Textures/", "Better Textures/romfs/", "Better Textures/romfs/Tex/a.bntx",
                                                   "Better Textures/romfs/Tex/b.bntx", "Better Textures/readme.txt"]),
                                            pickName: "Better Textures v2", titleIds: [game])
        XCTAssertEqual(nested.found, [CartoucheModFound(name: "Better Textures v2", romfs: "Better Textures/romfs", files: 2, size: 20)])
        XCTAssertEqual(nested.refused, [])
        let atRoot = try CartoucheMods.plan(items(["romfs/Tex/a.bntx"]), pickName: "Mod", titleIds: [game])
        XCTAssertEqual(atRoot.found.map(\.romfs), ["romfs"])
    }

    func testTheMicroSDLayoutOfTheGameComesAndAnotherGamesIsRefused() throws {
        let mine = try CartoucheMods.plan(items(["atmosphere/contents/0100F2C0115B6000/romfs/Sound/bgm.bfstm"]),
                                          pickName: "Music", titleIds: [game])
        XCTAssertEqual(mine.found.map(\.romfs), ["atmosphere/contents/0100F2C0115B6000/romfs"])
        // The game's update, 0x800 further, is the same game.
        let update = try CartoucheMods.plan(items(["atmosphere/contents/0100F2C0115B6800/romfs/a"]),
                                            pickName: "Music", titleIds: [game])
        XCTAssertEqual(update.found.count, 1)
        XCTAssertThrowsError(try CartoucheMods.plan(items(["atmosphere/contents/01006A800016E000/romfs/a"]),
                                                    pickName: "Other", titleIds: [game])) { error in
            XCTAssertEqual(error as? CartoucheModProblem, .otherGame("01006A800016E000"))
        }
        // A game Cartouche does not know takes any.
        XCTAssertEqual(try CartoucheMods.plan(items(["contents/01006A800016E000/romfs/a"]), pickName: "M", titleIds: []).found.count, 1)
    }

    func testAModThatChangesTheGamesCodeIsRefused() {
        XCTAssertThrowsError(try CartoucheMods.plan(items(["Compass/romfs/script/main.blua", "Compass/exefs/subsdk9",
                                                           "Compass/exefs/main.npdm"]),
                                                    pickName: "Compass", titleIds: [game])) { error in
            XCTAssertEqual(error as? CartoucheModProblem, .code)
        }
        // An empty exefs folder changes nothing.
        XCTAssertEqual(try CartoucheMods.plan(items(["M/romfs/a", "M/exefs/"]), pickName: "M", titleIds: [game]).found.count, 1)
    }

    func testAPackOfVariantsGivesAModForEachNamedAfterItsFolder() throws {
        let pack = try CartoucheMods.plan(items(["Pack/60 fps/romfs/a", "Pack/30 fps/romfs/a", "Pack/Code/romfs/b",
                                                 "Pack/Code/exefs/subsdk9"]),
                                          pickName: "Pack", titleIds: [game])
        XCTAssertEqual(pack.found.map(\.name), ["30 fps", "60 fps"])
        XCTAssertEqual(pack.refused, [CartoucheModRefused(name: "Code", problem: .code)])
    }

    func testWithoutARomfsFolderNothingComes() {
        XCTAssertThrowsError(try CartoucheMods.plan(items(["Mod/Tex/a.bntx", "Mod/romfs"]), pickName: "Mod", titleIds: [game])) { error in
            XCTAssertEqual(error as? CartoucheModProblem, .noRomfs)
        }
        // What a Mac adds to a ZIP is no mod.
        XCTAssertThrowsError(try CartoucheMods.plan(items(["__MACOSX/romfs/._a", "a.txt"]), pickName: "Mod", titleIds: [game]))
        XCTAssertThrowsError(try CartoucheMods.plan(items(["Mod/romfs/"]), pickName: "Mod", titleIds: [game])) { error in
            XCTAssertEqual(error as? CartoucheModProblem, .empty)
        }
    }

    func testPickingTheRomfsFolderItselfTakesItNamedAfterItsFolder() throws {
        let picked = try CartoucheMods.plan(items(["Tex/a.bntx"]), pickName: "romfs", parentName: "HD Pack", titleIds: [game])
        XCTAssertEqual(picked.found, [CartoucheModFound(name: "HD Pack", romfs: "", files: 1, size: 10)])
    }

    func testALinkOrAPathOutsideTheModIsRefused() {
        XCTAssertThrowsError(try CartoucheMods.plan([CartoucheModItem(path: "Mod/romfs/a", isLink: true)], pickName: "Mod", titleIds: []))
        XCTAssertThrowsError(try CartoucheMods.plan(items(["Mod/romfs/../../a"]), pickName: "Mod", titleIds: []))
    }

    // MARK: Adding one

    func testAModFromAFolderComesFirstTurnedOnWithItsFilesOnly() async throws {
        let pick = root.appendingPathComponent("Picked/Better Textures", isDirectory: true)
        try file("romfs/Tex/a.bntx", in: pick)
        try file("romfs/.DS_Store", in: pick)
        try file("readme.txt", in: pick)
        let earlier = try await addFolder("Older", files: ["romfs/b"])
        let read = try await CartoucheMods.read(pick, titleIds: [game])
        XCTAssertFalse(read.isArchive)
        let added = try await CartoucheMods.add(read.found, of: read, to: documents, on: true, gameVersion: "1.2.0")
        XCTAssertEqual(added.map(\.name), ["Better Textures"])
        let mods = CartoucheMods.load(in: documents)
        XCTAssertEqual(mods.map(\.name), ["Better Textures", "Older"])
        XCTAssertEqual(mods.map(\.isOn), [true, true])
        XCTAssertEqual(mods.first?.gameVersion, "1.2.0")
        XCTAssertEqual(mods.first?.files, 1)
        let folder = CartoucheMods.folder(in: documents).appendingPathComponent("Better Textures", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("romfs/Tex/a.bntx").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("romfs/.DS_Store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("readme.txt").path))
        XCTAssertEqual(earlier.map(\.name), ["Older"])
        // Nothing of the add is left beside the mods.
        let names = try FileManager.default.contentsOfDirectory(atPath: CartoucheMods.folder(in: documents).path)
        XCTAssertEqual(Set(names), ["Better Textures", "Older", "mods.json"])
    }

    func testAModFromAZipIsUnpackedFromItsRomfsFolderAlone() async throws {
        let zip = root.appendingPathComponent("Music Pack.zip")
        let sink = try CartoucheFileSink(zip)
        let writer = CartoucheZipWriter(sink: sink)
        try await writer.addFolder("atmosphere/contents/0100F2C0115B6000/romfs/")
        try await writer.addData("atmosphere/contents/0100F2C0115B6000/romfs/Sound/bgm.bfstm", Data(repeating: 7, count: 4096))
        try await writer.addData("__MACOSX/atmosphere/contents/0100F2C0115B6000/romfs/Sound/._bgm.bfstm", Data("junk".utf8))
        try await writer.addData("atmosphere/contents/0100F2C0115B6000/cheats/0123.txt", Data("[x]".utf8))
        try await writer.finish()
        try sink.close()
        let read = try await CartoucheMods.read(zip, titleIds: [game])
        XCTAssertTrue(read.isArchive)
        XCTAssertEqual(read.found.map(\.name), ["Music Pack"])
        let added = try await CartoucheMods.add(read.found, of: read, to: documents, on: true, gameVersion: nil)
        let romfs = CartoucheMods.folder(in: documents).appendingPathComponent(added[0].folder + "/romfs", isDirectory: true)
        XCTAssertEqual(try Data(contentsOf: romfs.appendingPathComponent("Sound/bgm.bfstm")), Data(repeating: 7, count: 4096))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: romfs.path), ["Sound"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: romfs.appendingPathComponent("Sound").path), ["bgm.bfstm"])
    }

    /// Adds a mod from a folder named NAME holding FILES.
    @discardableResult
    private func addFolder(_ name: String, files: [String], on: Bool = true) async throws -> [CartoucheMod] {
        let pick = root.appendingPathComponent("Picks/" + UUID().uuidString + "/" + name, isDirectory: true)
        for path in files { try file(path, in: pick) }
        let read = try await CartoucheMods.read(pick, titleIds: [game])
        return try await CartoucheMods.add(read.found, of: read, to: documents, on: on, gameVersion: nil)
    }

    func testAFoldersNameKeepsNothingAPathOrNxnativesLineWouldCut() {
        XCTAssertEqual(CartoucheMods.folderName(for: "Zelda: HD/60", taken: []), "Zelda- HD-60")
        XCTAssertEqual(CartoucheMods.folderName(for: "..hidden", taken: []), "hidden")
        XCTAssertEqual(CartoucheMods.folderName(for: "   ", taken: []), "Mod")
        XCTAssertEqual(CartoucheMods.folderName(for: "Music", taken: ["music", "Music 2"]), "Music 3")
    }

    // MARK: The list

    func testAFolderCopiedByHandShowsTurnedOffWithWhatStopsIt() async throws {
        try await addFolder("Listed", files: ["romfs/a"])
        let folder = CartoucheMods.folder(in: documents)
        try file("By Hand/romfs/b", in: folder)
        try file("Code/romfs/c", in: folder)
        try file("Code/exefs/subsdk9", in: folder)
        try file("Bare/Tex/d", in: folder)
        let mods = CartoucheMods.load(in: documents)
        XCTAssertEqual(mods.map(\.folder), ["Listed", "Bare", "By Hand", "Code"])
        XCTAssertEqual(mods.map(\.isOn), [true, false, false, false])
        XCTAssertEqual(mods.map(\.problem), [nil, .noRomfs, nil, .code])
        XCTAssertEqual(mods[2].files, 1)
        XCTAssertThrowsError(try CartoucheMods.turn("Code", on: true, in: documents)) { error in
            XCTAssertEqual(error as? CartoucheModProblem, .code)
        }
        // A listed mod whose folder went is gone from the list.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Listed"))
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.folder), ["Bare", "By Hand", "Code"])
    }

    func testTheOrderTheSwitchesAndDeletingAreKept() async throws {
        try await addFolder("C", files: ["romfs/c"])
        try await addFolder("B", files: ["romfs/b"])
        try await addFolder("A", files: ["romfs/a"])
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.folder), ["A", "B", "C"])
        try CartoucheMods.move("C", by: -1, in: documents)
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.folder), ["A", "C", "B"])
        try CartoucheMods.move("A", by: -1, in: documents)
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.folder), ["A", "C", "B"])
        try CartoucheMods.turn("C", on: false, in: documents)
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.isOn), [true, false, true])
        try CartoucheMods.delete("A", in: documents)
        XCTAssertEqual(CartoucheMods.load(in: documents).map(\.folder), ["C", "B"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: CartoucheMods.folder(in: documents).appendingPathComponent("A").path))
    }

    func testNoMoreThanTheMostAGameTakesAreOn() async throws {
        for index in 0..<CartoucheMods.mostOn {
            try await addFolder("Mod \(index)", files: ["romfs/a"])
        }
        try await addFolder("One more", files: ["romfs/a"], on: false)
        XCTAssertThrowsError(try CartoucheMods.turn("One more", on: true, in: documents)) { error in
            XCTAssertTrue(error is CartoucheModsFull)
        }
        try CartoucheMods.turn("Mod 3", on: false, in: documents)
        XCTAssertNoThrow(try CartoucheMods.turn("One more", on: true, in: documents))
    }

    // MARK: Before a start

    func testTheLineNamesTheModsOnInTheirOrderWithThePathsTheGameSees() async throws {
        try file("env.txt", in: documents, "DM_SHOW_FPS=1\n")
        try await addFolder("Low", files: ["romfs/a"])
        try await addFolder("Off", files: ["romfs/a"], on: false)
        try await addFolder("High", files: ["RomFS/a"])
        // A folder copied by hand keeps its romfs folder's letters.
        try file("Hand/RomFS/a", in: CartoucheMods.folder(in: documents))
        try CartoucheMods.turn("Hand", on: true, in: documents)
        let game = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/X/Documents/Data/Application/Y/Documents",
                       isDirectory: true)
        XCTAssertEqual(try CartoucheMods.prepareStart(documents: documents, gameDocuments: game), 3)
        let env = try String(contentsOf: documents.appendingPathComponent("env.txt"), encoding: .utf8)
        XCTAssertEqual(env, "DM_SHOW_FPS=1\n" + CartoucheModsLine.note + "\n" + "DM_ROMFS_OVERLAY="
                       + game.path + "/mods/High/romfs:" + game.path + "/mods/Low/romfs:" + game.path + "/mods/Hand/RomFS\n")
        // Written again, the same: once.
        XCTAssertEqual(try CartoucheMods.prepareStart(documents: documents, gameDocuments: game), 3)
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("env.txt"), encoding: .utf8), env)
        // None on: the line goes, the player's own lines stay.
        for folder in ["High", "Low", "Hand"] {
            try CartoucheMods.turn(folder, on: false, in: documents)
        }
        XCTAssertEqual(try CartoucheMods.prepareStart(documents: documents, gameDocuments: game), 0)
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("env.txt"), encoding: .utf8), "DM_SHOW_FPS=1\n")
    }

    func testAGameWithoutModsKeepsNoEnvFileOfCartouches() throws {
        XCTAssertEqual(try CartoucheMods.prepareStart(documents: documents, gameDocuments: documents), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent("env.txt").path))
        try CartoucheModsLine.write("/a/romfs", documents: documents)
        try CartoucheModsLine.write(nil, documents: documents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent("env.txt").path))
    }

    func testTheLogSaysHowManyModsTheGameTook() {
        XCTAssertEqual(CartoucheModsLine.count(inLogLine: "boot: env DM_ROMFS_OVERLAY=/var/a/mods/X (v2)/romfs:/var/a/mods/Y/romfs (env.txt)"), 2)
        XCTAssertEqual(CartoucheModsLine.count(inLogLine: "launcher: env DM_ROMFS_OVERLAY=/Users/a/mods/X/romfs (/Users/a/env.txt)"), 1)
        XCTAssertNil(CartoucheModsLine.count(inLogLine: "boot: env DM_ROMFS=/var/a/romfs.img (env.txt)"))
        XCTAssertNil(CartoucheModsLine.count(inLogLine: "fs mount rom: → /var/a/romfs.img (read-only) (overlay first)"))
    }
}
