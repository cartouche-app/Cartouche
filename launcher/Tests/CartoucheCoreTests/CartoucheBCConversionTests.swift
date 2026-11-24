//
//  CartoucheBCConversionTests.swift
//  CartoucheCoreTests
//
//  Whether a game was built with an nxnative that converts its BC
//  textures for a GPU without BC formats, and for which APIs
//  (Sources/CartoucheBCConversion.swift): the executable's C strings name
//  the conversion's setting, NVN's, or have the Vulkan layer's words, and
//  neither of nxnative's refusals. The executables here are made as the
//  linker lays one out, with the words of nxnative's main.m and nvn_mtl.m
//  and of mianmuhammadse/nxnative's no-bc branch (18 November, and its
//  hle_vk.m since 22 November).
//

import XCTest
@testable import CartoucheCore

final class CartoucheBCConversionTests: XCTestCase {
    // MARK: Executables

    private struct Section {
        var segment = "__TEXT"
        var name = "__cstring"
        /// S_CSTRING_LITERALS; 0, S_REGULAR, for other bytes.
        var type: UInt32 = 0x02
        var strings: [String]

        var bytes: [UInt8] { strings.flatMap { Array($0.utf8) + [0] } }
    }

    private static let arm64: UInt32 = 0x0100_000c
    private static let x86_64: UInt32 = 0x0100_0007

    /// A thin Mach-O for CPU with SECTIONS, a segment each, their bytes after
    /// the load commands, as ld lays them out.
    private func executable(_ sections: [Section], cpu: UInt32 = arm64) -> [UInt8] {
        var file: [UInt8] = []
        let commandsSize = sections.count * (72 + 80)
        // mach_header_64: MH_MAGIC_64, cputype, cpusubtype, MH_EXECUTE,
        // ncmds, sizeofcmds, MH_PIE | MH_TWOLEVEL | MH_DYLDLINK, reserved.
        for value in [0xfeed_facf, cpu, 0, 2, UInt32(sections.count), UInt32(commandsSize), 0x0020_0085, 0] {
            file += le(value)
        }
        var offset = 32 + commandsSize
        for section in sections {
            let size = section.bytes.count
            // segment_command_64, with its one section_64.
            file += le(UInt32(0x19)) + le(UInt32(72 + 80)) + name(section.segment)
            file += le(UInt64(0x1_0000_0000 + offset)) + le(UInt64(size)) + le(UInt64(offset)) + le(UInt64(size))
            file += le(UInt32(5)) + le(UInt32(5)) + le(UInt32(1)) + le(UInt32(0))
            file += name(section.name) + name(section.segment)
            file += le(UInt64(0x1_0000_0000 + offset)) + le(UInt64(size))
            file += le(UInt32(offset)) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0))
            file += le(section.type) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0))
            offset += size
        }
        for section in sections { file += section.bytes }
        return file
    }

    /// A universal file of SLICES, each a thin Mach-O and its CPU, at 16 KiB
    /// boundaries; in fat_arch_64 entries when WIDE.
    private func universal(_ slices: [(cpu: UInt32, file: [UInt8])], wide: Bool = false) -> [UInt8] {
        var header = be(UInt32(wide ? 0xcafe_babf : 0xcafe_babe)) + be(UInt32(slices.count))
        var body: [UInt8] = []
        var offset = 0x4000
        for slice in slices {
            header += be(slice.cpu) + be(UInt32(0))
            if wide {
                header += be(UInt64(offset)) + be(UInt64(slice.file.count)) + be(UInt32(14)) + be(UInt32(0))
            } else {
                header += be(UInt32(offset)) + be(UInt32(slice.file.count)) + be(UInt32(14))
            }
            body += [UInt8](repeating: 0, count: offset - 0x4000 - body.count) + slice.file
            offset = 0x4000 + (body.count + 0x3fff) / 0x4000 * 0x4000
        }
        return header + [UInt8](repeating: 0, count: 0x4000 - header.count) + body
    }

    private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }
    private func be<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    private func name(_ text: String) -> [UInt8] { Array(text.utf8) + [UInt8](repeating: 0, count: 16 - text.utf8.count) }

    private func conversion(_ bytes: [UInt8]) -> CartoucheBCConversion.APIs {
        CartoucheBCConversion.conversion(executable: Data(bytes))
    }

    private func converts(_ bytes: [UInt8]) -> Bool { !conversion(bytes).isEmpty }

    // The host's words, as each build has them.
    private let host = Section(strings: ["[RED] boot: %s", "DM_FPS_TARGET", "romfs.img"])
    /// mianmuhammadse/nxnative's no-bc branch, nvn_mtl.m.
    private let conversion = Section(strings: [
        "DM_TEST_NO_BC",
        "the GPU has no BC compressed formats%s: BC textures are stored as ASTC 4x4 (BC1–3) or decompressed (see the DM_NO_BC_ASTC line)",
        "DM_NO_BC_ASTC",
        "no BC: DM_NO_BC_ASTC=%s: %s%s",
        "DM_NO_BC_ASTC_KEEP",
        "no BC: BC1–3 transcoded to ASTC on the GPU",
    ])
    /// The same branch's hle_vk.m, since 22 November (53f5d9a): the line its
    /// Vulkan layer logs at its first BC image, and its red lines.
    private let vulkanConversion = Section(strings: [
        "[dm] [vk] no BC: BC images are stored as ASTC 4x4 (BC1-3) or decompressed (the other formats), first one: format %d %ux%u → pixel format %lu",
        "[dm] [vk] [RED] no BC: the CPU cannot read the staging buffer of an upload to a BC image",
    ])
    /// nxnative's own: main.m, then nvn_mtl.m.
    private let refusalAtStart = "This device's GPU (%s) cannot read BC-compressed textures, which the games use. It needs an iPhone 15 Pro or newer (A17 Pro chip or later) or an iPad with an M1 chip or later."
    private let refusalAtFirstImage = "the Metal device %s has no BC texture formats, which the games' textures use and the host does not decompress: an iPhone needs an A17 Pro or later, an iPad an M1 or later"

    // MARK: The build's words

    func testABuildThatConvertsSaysSo() {
        var strings = host
        strings.strings += conversion.strings
        XCTAssertTrue(converts(executable([strings])))
        // Its words may be in any section of C strings, os_log's too.
        XCTAssertTrue(converts(executable([host, Section(name: "__oslogstring", strings: conversion.strings)])))
    }

    func testNxnativesOwnBuildDoesNot() {
        var strings = host
        strings.strings += [refusalAtStart, refusalAtFirstImage]
        XCTAssertFalse(converts(executable([strings])))
        XCTAssertFalse(converts(executable([host])))
    }

    func testABuildThatStillRefusesTheGPUDoesNotConvert() {
        // Whatever else it carries, nxnative stops it on such a GPU, at its
        // start or at its first image.
        XCTAssertFalse(converts(executable([host, conversion, Section(strings: [refusalAtStart])])))
        XCTAssertFalse(converts(executable([Section(strings: [refusalAtFirstImage]), conversion])))
    }

    func testTheSameLettersOutsideCStringsSayNothing() {
        // The game's own data, or a symbol's name.
        XCTAssertFalse(converts(executable([host, Section(name: "__const", type: 0, strings: conversion.strings)])))
        XCTAssertFalse(converts(executable([host, Section(segment: "__LINKEDIT", name: "__symbols", type: 0,
                                                         strings: ["_DM_NO_BC_ASTC_enabled"])])))
    }

    // MARK: Files

    func testAUniversalFileIsReadInItsARM64Slice() {
        let converted = executable([host, conversion])
        let refused = executable([host, Section(strings: [refusalAtStart])], cpu: Self.x86_64)
        XCTAssertTrue(converts(universal([(Self.x86_64, refused), (Self.arm64, converted)])))
        XCTAssertTrue(converts(universal([(Self.arm64, converted)], wide: true)))
        XCTAssertFalse(converts(universal([(Self.arm64, executable([host, Section(strings: [refusalAtStart])])),
                                           (Self.x86_64, executable([host, conversion], cpu: Self.x86_64))])))
        // An executable for another CPU, alone, says nothing of this one.
        XCTAssertFalse(converts(universal([(Self.x86_64, executable([host, conversion], cpu: Self.x86_64))])))
        XCTAssertFalse(converts(executable([host, conversion], cpu: Self.x86_64)))
    }

    func testWhatIsNoExecutableConvertsNothing() {
        XCTAssertFalse(converts([]))
        XCTAssertFalse(converts(Array("DM_NO_BC_ASTC".utf8)))
        XCTAssertFalse(converts([0xfe, 0xed, 0xfa]))
        let whole = executable([host, conversion])
        // Cut in its load commands, or before the end of its strings.
        XCTAssertFalse(converts(Array(whole.prefix(100))))
        XCTAssertFalse(converts(Array(whole.dropLast(3))))
        // A section that says it is longer than the file.
        var longer = whole
        let sizeAt = 32 + (72 + 80) + 72 + 40
        longer.replaceSubrange(sizeAt..<sizeAt + 8, with: le(UInt64(1 << 40)))
        XCTAssertFalse(converts(longer))
        // A universal file whose slice goes past its end.
        var cut = universal([(Self.arm64, whole)])
        cut.removeLast(whole.count / 2)
        XCTAssertFalse(converts(cut))
    }

    func testTheExecutableIsReadFromItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let converted = folder.appendingPathComponent("Game")
        try Data(executable([host, conversion, vulkanConversion])).write(to: converted)
        XCTAssertEqual(CartoucheBCConversion.conversion(executableAt: converted), [.nvn, .vulkan])
        let upstream = folder.appendingPathComponent("Upstream")
        try Data(executable([host, Section(strings: [refusalAtStart, refusalAtFirstImage])])).write(to: upstream)
        XCTAssertEqual(CartoucheBCConversion.conversion(executableAt: upstream), [])
        XCTAssertEqual(CartoucheBCConversion.conversion(executableAt: folder.appendingPathComponent("Missing")), [])
    }

    // MARK: An IPA not installed

    /// An IPA as nxnative's build_ipa.sh zips one, its executable EXECUTABLE.
    private func ipa(executable: [UInt8], named name: String = "Game") async throws -> MemorySource {
        let sink = MemorySink()
        let writer = CartoucheZipWriter(sink: sink)
        try await writer.addFolder("Payload/")
        try await writer.addFolder("Payload/Game.app/")
        try await writer.addData("Payload/Game.app/Info.plist", Data("<plist/>".utf8))
        // The rest of a game's executable after its header and strings,
        // its entry deflated, as nxnative's IPAs have it.
        try await writer.addData("Payload/Game.app/" + name, Data(executable + [UInt8](repeating: 0x1f, count: 200_000)), mode: 0o755)
        try await writer.addData("Payload/Game.app/romfs.img", Data(repeating: 7, count: 4096))
        try await writer.finish()
        return MemorySource(sink.data)
    }

    private func conversion(ofIPA source: MemorySource, executable: String = "Game") async throws -> CartoucheBCConversion.APIs {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let entries = try await CartoucheZip.entries(of: source)
        let apis = try await CartoucheBCConversion.conversion(ofIPA: source, entries: entries, executable: executable, in: folder)
        // Nothing left of the executable unpacked.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        return apis
    }

    /// A game on the Mac or in a games folder, not installed: its
    /// executable is read where the IPA sits, as an installed game's
    /// (decision 145), so that its sheet says its build converts the
    /// textures rather than that nxnative refuses the GPU.
    func testTheExecutableOfAnIPANotInstalledIsReadWhereItSits() async throws {
        let converted = try await ipa(executable: executable([host, conversion, vulkanConversion]))
        let apis = try await conversion(ofIPA: converted)
        XCTAssertEqual(apis, [.nvn, .vulkan])

        let nvnOnly = try await ipa(executable: executable([host, conversion]))
        let nvn = try await conversion(ofIPA: nvnOnly)
        XCTAssertEqual(nvn, [.nvn])
        let upstream = try await ipa(executable: executable([host, Section(strings: [refusalAtStart, refusalAtFirstImage])]))
        let none = try await conversion(ofIPA: upstream)
        XCTAssertEqual(none, [])
    }

    /// The executable is the one the Info.plist names, a file at the top of
    /// the app: another name, or a path, reads nothing.
    func testAnIPAWithoutTheExecutableItsInfoPlistNamesConvertsNothing() async throws {
        let source = try await ipa(executable: executable([host, conversion]), named: "Game")
        let other = try await conversion(ofIPA: source, executable: "Other")
        XCTAssertEqual(other, [])
        let path = try await conversion(ofIPA: source, executable: "../Game.app/Game")
        XCTAssertEqual(path, [])
        let empty = try await conversion(ofIPA: source, executable: "")
        XCTAssertEqual(empty, [])
        let named = try await conversion(ofIPA: source, executable: "Game")
        XCTAssertEqual(named, [.nvn])
    }

    // MARK: Vulkan

    func testABuildWhoseVulkanLayerConvertsSaysSoToo() {
        // The fork's build since 22 November: NVN's setting, and the line of
        // its Vulkan layer.
        XCTAssertEqual(conversion(executable([host, conversion, vulkanConversion])), [.nvn, .vulkan])
        // As on 18 November: NVN's alone. Until Then, a Vulkan game, stopped
        // at its first BC image on an iPhone 15 with such a build (ada1018b).
        XCTAssertEqual(conversion(executable([host, conversion])), [.nvn])
        // Its words in os_log's section count as in __cstring.
        XCTAssertEqual(conversion(executable([host, conversion, Section(name: "__oslogstring", strings: vulkanConversion.strings)])),
                       [.nvn, .vulkan])
        // A refusal of nxnative's still says it all.
        XCTAssertEqual(conversion(executable([host, conversion, vulkanConversion, Section(strings: [refusalAtFirstImage])])), [])
        // The same letters outside the C strings say nothing.
        XCTAssertEqual(conversion(executable([host, conversion, Section(name: "__const", type: 0, strings: vulkanConversion.strings)])),
                       [.nvn])
    }

    // MARK: Games

    func testTheConversionCoversTheAPIsTheBuildConverts() {
        // nxnative's list of games, at the commit Cartouche pins: The Legend
        // of Zelda: Breath of the Wild and Mario Kart World, then the games
        // drawn with OpenGL (Balatro), Vulkan (Hades, Super Mario Galaxy), or
        // both NVN and Vulkan (Super Mario 3D All-Stars).
        let nvn: CartoucheBCConversion.APIs = [.nvn]
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: "NVN", by: nvn))
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: "NVN2", by: nvn))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "OpenGL", by: nvn))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "Vulkan", by: nvn))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "NVN, Vulkan", by: nvn))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "", by: nvn))
        // The fork's build since 22 November converts Vulkan's too; OpenGL
        // still needs a GPU with BC.
        let both: CartoucheBCConversion.APIs = [.nvn, .vulkan]
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: "Vulkan", by: both))
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: "NVN, Vulkan", by: both))
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: "NVN", by: both))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "OpenGL", by: both))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "Vulkan, OpenGL", by: both))
        // A game the list does not know: the build's word stands.
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: nil, by: nvn))
        XCTAssertTrue(CartoucheBCConversion.covers(graphics: nil, by: [.vulkan]))
        // nxnative's own build converts nothing, for any game.
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: nil, by: []))
        XCTAssertFalse(CartoucheBCConversion.covers(graphics: "NVN", by: []))
    }

    // MARK: The sheet's words

    /// What a converted game's sheet says on its BC line, in
    /// Cartouche.xcstrings: the fork stores BC1 to BC3 as ASTC and
    /// decompresses BC4 to BC7 and 3D textures, so "converted to ASTC" said
    /// more than the build does (its author, on Discord, 19 November).
    func testTheSheetSaysTheTexturesAreConvertedForTheGPU() throws {
        struct Unit: Decodable { let value: String }
        struct Localization: Decodable { let stringUnit: Unit? }
        struct Entry: Decodable { let localizations: [String: Localization]? }
        struct Catalog: Decodable { let strings: [String: Entry] }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/Cartouche.xcstrings"))
        let words = try JSONDecoder().decode(Catalog.self, from: data).strings["sheet.gpu.converted"]?.localizations
        XCTAssertEqual(words?["en"]?.stringUnit?.value, "Textures converted for this GPU by this game’s build")
        XCTAssertEqual(words?["fr"]?.stringUnit?.value, "Textures converties pour ce GPU par la construction de ce jeu")
        for language in ["en", "fr", "es", "de"] {
            XCTAssertFalse(words?[language]?.stringUnit?.value.contains("ASTC") ?? true, language)
        }
    }
}
