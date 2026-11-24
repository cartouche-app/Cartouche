//
//  CartoucheBCConversion.swift
//  Cartouche
//
//  Whether a game was built with an nxnative that converts its
//  BC-compressed textures for a GPU that reads none, the A16's and older,
//  and for which of its graphics APIs: nxnative refuses such a GPU for every
//  game (CartoucheGameFit), but a fork of it stores BC1 to BC3 as ASTC 4x4
//  there and decompresses the others (BC4 to BC7, and 3D textures), as
//  mianmuhammadse/nxnative's no-bc branch does (its dm/gfx/tex/README.md).
//  nxnative's host is built into the game's executable, with its words: such
//  a build reads the setting of the conversion, DM_NO_BC_ASTC, and no longer
//  carries either of nxnative's refusals of the GPU (dm/ios/Sources/main.m
//  and dm/gfx/nvn/nvn_mtl.m). Only the executable's C strings are read
//  (__TEXT,__cstring and the sections like it), where a C program's words
//  are: the same letters in the game's data say nothing. A file that is not
//  an arm64 executable, or that ends too soon, converts nothing, and a
//  build that says nothing of it keeps the GPU's warning: nothing here ever
//  hides an incompatibility it did not read lifted.
//
//  The conversion was NVN's alone; since 22 November (53f5d9a) the fork's
//  Vulkan layer stores BC images the same way, and its build then says so in
//  its own words, the line it logs at its first such image (hle_vk.m).
//  Until Then, a Vulkan game, played on an iPhone 15 so. A game drawn with
//  OpenGL still needs a GPU with BC formats (covers).
//
//  Platform-independent: tested on its own by launcher/Package.swift.
//

import Foundation

enum CartoucheBCConversion {
    /// The graphics APIs whose BC textures a build converts: none for
    /// nxnative's own builds.
    struct APIs: OptionSet, Hashable {
        let rawValue: Int
        /// NVN, the Switch's, and NVN2, the Switch 2's.
        static let nvn = APIs(rawValue: 1 << 0)
        static let vulkan = APIs(rawValue: 1 << 1)
    }

    /// The setting of the conversion, which only a build that converts reads:
    /// NVN's, which the Vulkan layer's follows.
    static let marker = "DM_NO_BC_ASTC"
    /// What the fork's Vulkan layer logs at the first BC image it stores
    /// otherwise, "[dm] [vk] no BC: BC images are stored as ASTC 4x4
    /// (BC1-3) or decompressed (the other formats), first one: …": a build
    /// whose Vulkan layer does not convert has no such words.
    static let vulkanMarker = "[vk] no BC:"
    /// nxnative's refusals of a GPU without BC formats, at the game's start
    /// (main.m) and at its first image (nvn_mtl.m): a build that still says
    /// either stops on such a GPU, whatever else it carries.
    static let refusals = ["cannot read BC-compressed textures", "has no BC texture formats"]

    /// The APIs whose BC textures the executable at URL converts. Mapped,
    /// not read: a game's executable can be hundreds of megabytes, of which
    /// only its header and its C strings are touched.
    static func conversion(executableAt url: URL) -> APIs {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        return conversion(executable: data)
    }

    /// The APIs whose BC textures the executable DATA, a Mach-O file, thin or
    /// universal, converts: none when its C strings say either of
    /// nxnative's refusals; else NVN's when they name the conversion's
    /// setting, Vulkan's when they have its layer's words.
    static func conversion(executable data: Data) -> APIs {
        data.withUnsafeBytes { (file: UnsafeRawBufferPointer) -> APIs in
            guard let sections = cStringSections(of: file), !sections.isEmpty else { return [] }
            var apis: APIs = []
            for section in sections {
                let strings = UnsafeRawBufferPointer(rebasing: file[section])
                if refusals.contains(where: { contains(strings, $0) }) { return [] }
                if !apis.contains(.nvn), contains(strings, marker) { apis.insert(.nvn) }
                if !apis.contains(.vulkan), contains(strings, vulkanMarker) { apis.insert(.vulkan) }
            }
            return apis
        }
    }

    /// Whether a build that converts the BC textures of CONVERTED covers a
    /// game drawn with GRAPHICS, as nxnative's list of games says it
    /// (CartoucheNxGame.graphics): every API the game draws with, NVN or
    /// NVN2, and Vulkan, is among them; OpenGL never is. Of a game the list
    /// does not know, the build's word stands.
    static func covers(graphics: String?, by converted: APIs) -> Bool {
        guard !converted.isEmpty else { return false }
        guard let graphics else { return true }
        let apis = graphics.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        return !apis.isEmpty && apis.allSatisfy { api in
            switch api {
            case "NVN", "NVN2": return converted.contains(.nvn)
            case "VULKAN": return converted.contains(.vulkan)
            default: return false
            }
        }
    }

    // MARK: Mach-O

    private static let magic64: UInt32 = 0xfeed_facf
    private static let fatMagic: UInt32 = 0xcafe_babe
    private static let fatMagic64: UInt32 = 0xcafe_babf
    private static let cpuARM64: UInt32 = 0x0100_000c
    private static let segment64: UInt32 = 0x19
    /// A section of C strings (S_CSTRING_LITERALS), in a section's flags'
    /// type (SECTION_TYPE).
    private static let cStringLiterals: UInt32 = 0x02

    /// The ranges of FILE that hold C strings: those of its arm64
    /// executable, the file itself or a slice of a universal one. Nil when
    /// it is no such executable, or its load commands go past its end.
    private static func cStringSections(of file: UnsafeRawBufferPointer) -> [Range<Int>]? {
        if file.uint32(at: 0) == magic64 { return cStringSections(of: file, slice: 0..<file.count) }
        // A universal file: its header and its list of slices are big-endian.
        let fat = file.uint32(at: 0, bigEndian: true)
        guard fat == fatMagic || fat == fatMagic64,
              let count = file.uint32(at: 4, bigEndian: true), count <= 64 else { return nil }
        // Each slice: its CPU, then where it starts and its size, on 32 bits
        // in a fat_arch, on 64 in a fat_arch_64.
        let wide = fat == fatMagic64
        let entry = wide ? 32 : 20
        for index in 0..<Int(count) {
            let at = 8 + index * entry
            guard let cpu = file.uint32(at: at, bigEndian: true) else { return nil }
            guard cpu == cpuARM64 else { continue }
            let start: UInt64?, size: UInt64?
            if wide {
                start = file.uint64(at: at + 8, bigEndian: true)
                size = file.uint64(at: at + 16, bigEndian: true)
            } else {
                start = file.uint32(at: at + 8, bigEndian: true).map(UInt64.init)
                size = file.uint32(at: at + 12, bigEndian: true).map(UInt64.init)
            }
            guard let start, let size, start <= UInt64(file.count), size <= UInt64(file.count) - start else { return nil }
            let slice = Int(start)..<Int(start + size)
            guard file.uint32(at: slice.lowerBound) == magic64 else { return nil }
            return cStringSections(of: file, slice: slice)
        }
        return nil
    }

    /// The ranges of FILE, in the arm64 Mach-O that is its SLICE, that hold
    /// C strings.
    private static func cStringSections(of file: UnsafeRawBufferPointer, slice: Range<Int>) -> [Range<Int>]? {
        let base = slice.lowerBound
        // mach_header_64: magic, cputype, cpusubtype, filetype, ncmds,
        // sizeofcmds, flags, reserved.
        guard file.uint32(at: base + 4) == cpuARM64,
              let commands = file.uint32(at: base + 16), let commandBytes = file.uint32(at: base + 20),
              base + 32 + Int(commandBytes) <= slice.upperBound else { return nil }
        var sections: [Range<Int>] = []
        var at = base + 32
        let end = at + Int(commandBytes)
        for _ in 0..<commands {
            guard let command = file.uint32(at: at), let size = file.uint32(at: at + 4),
                  size >= 8, at + Int(size) <= end else { return nil }
            if command == segment64 {
                // segment_command_64: its sections, section_64 each, after
                // its 72 bytes; their count at 64.
                guard size >= 72, let count = file.uint32(at: at + 64),
                      72 + UInt64(count) * 80 <= UInt64(size) else { return nil }
                for index in 0..<Int(count) {
                    let section = at + 72 + index * 80
                    // section_64: its size at 40, its offset in the file at
                    // 48, its flags at 64.
                    guard let bytes = file.uint64(at: section + 40), let offset = file.uint32(at: section + 48),
                          let flags = file.uint32(at: section + 64) else { return nil }
                    guard flags & 0xff == cStringLiterals, bytes > 0 else { continue }
                    let start = base + Int(offset)
                    guard bytes <= UInt64(slice.upperBound - min(start, slice.upperBound)) else { return nil }
                    sections.append(start..<start + Int(bytes))
                }
            }
            at += Int(size)
        }
        return sections
    }

    /// Whether WORDS are in BYTES.
    private static func contains(_ bytes: UnsafeRawBufferPointer, _ words: String) -> Bool {
        let needle = Array(words.utf8)
        guard let first = needle.first, bytes.count >= needle.count, let start = bytes.baseAddress else { return false }
        return needle.withUnsafeBytes { needleBytes -> Bool in
            guard let wanted = needleBytes.baseAddress else { return false }
            var from = start
            let last = start + (bytes.count - needle.count)
            while from <= last {
                guard let hit = memchr(from, Int32(first), last - from + 1) else { return false }
                if memcmp(hit, wanted, needle.count) == 0 { return true }
                from = UnsafeRawPointer(hit) + 1
            }
            return false
        }
    }
}

private extension UnsafeRawBufferPointer {
    /// The UInt32 at OFFSET, little-endian as an arm64 Mach-O's, or
    /// BIGENDIAN as a universal file's header; nil past the end.
    func uint32(at offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, offset <= count - 4 else { return nil }
        let raw = loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        return bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
    }

    /// The UInt64 at OFFSET, as uint32(at:bigEndian:) reads one.
    func uint64(at offset: Int, bigEndian: Bool = false) -> UInt64? {
        guard offset >= 0, offset <= count - 8 else { return nil }
        let raw = loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        return bigEndian ? UInt64(bigEndian: raw) : UInt64(littleEndian: raw)
    }
}
