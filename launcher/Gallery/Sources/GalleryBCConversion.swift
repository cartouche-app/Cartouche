//
//  GalleryBCConversion.swift
//  CartoucheGallery
//
//  An iPhone whose GPU reads no BC-compressed texture, an A16's, for the
//  works gpu-no-bc and gpu-no-bc-converted: the sheet's game installed as
//  nxnative builds it, which refuses that GPU, or as a fork of nxnative
//  that converts those textures builds it (CartoucheBCConversion). Its
//  executable is a small one, made as ld lays one out, with the words of
//  that build where a game's executable has them: Cartouche reads it as it
//  reads a game's.
//

import Foundation

enum GalleryBCConversion {
    /// Whether WORK is an A16's.
    static func isWithoutBC(_ work: String?) -> Bool {
        work == "gpu-no-bc" || work == "gpu-no-bc-converted"
    }

    /// Gives INFO, the sheet's game, its Info.plist and its executable, for
    /// WORK: as a fork that converts the textures builds it
    /// (gpu-no-bc-converted), else as nxnative does.
    static func install(_ info: LCAppInfo, work: String?) {
        guard isWithoutBC(work) else { return }
        info.infoPlist = NSMutableDictionary(dictionary: ["CFBundleExecutable": "Game"])
        guard let bundle = info.bundlePath() else { return }
        let strings = work == "gpu-no-bc-converted"
            // mianmuhammadse/nxnative's no-bc branch, nvn_mtl.m.
            ? ["DM_NO_BC_ASTC", "no BC: DM_NO_BC_ASTC=%s: %s%s", "no BC: BC1–3 transcoded to ASTC on the GPU"]
            // nxnative's main.m.
            : ["This device's GPU (%s) cannot read BC-compressed textures, which the games use."]
        try? executable(strings: strings).write(to: URL(fileURLWithPath: bundle).appendingPathComponent("Game"))
    }

    /// A thin arm64 executable whose C strings are STRINGS: its header, a
    /// __TEXT segment with its __cstring section, then the strings.
    static func executable(strings: [String]) -> Data {
        let bytes: [UInt8] = strings.flatMap { Array($0.utf8) + [0] }
        var file = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) } }
        func put64(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { file.append(contentsOf: $0) } }
        func name(_ text: String) { file.append(contentsOf: Array(text.utf8) + [UInt8](repeating: 0, count: 16 - text.utf8.count)) }
        let commands = 72 + 80
        let offset = 32 + commands
        // mach_header_64: MH_MAGIC_64, arm64, MH_EXECUTE, one command.
        for value: UInt32 in [0xfeed_facf, 0x0100_000c, 0, 2, 1, UInt32(commands), 0x0020_0085, 0] { put32(value) }
        // LC_SEGMENT_64 __TEXT, and its section __cstring.
        put32(0x19); put32(UInt32(commands)); name("__TEXT")
        put64(0x1_0000_0000); put64(UInt64(offset + bytes.count)); put64(0); put64(UInt64(offset + bytes.count))
        put32(5); put32(5); put32(1); put32(0)
        name("__cstring"); name("__TEXT")
        put64(0x1_0000_0000 + UInt64(offset)); put64(UInt64(bytes.count))
        put32(UInt32(offset)); put32(0); put32(0); put32(0)
        put32(0x02); put32(0); put32(0); put32(0)
        file.append(contentsOf: bytes)
        return file
    }
}
