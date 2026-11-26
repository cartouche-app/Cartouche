//
//  GalleryMods.swift
//  CartoucheGallery
//
//  The mods of the scenario's game (work: mods), made up as Cartouche keeps
//  them (CartoucheMods), in the game's Documents of GallerySaves: two on, in
//  their order, one off, added with an older version of the game, and one
//  copied in by hand without the romfs folder a mod's files go in, which
//  shows what stops it; and, for the page of its mods (screen: mods), a ZIP
//  of a mod that changes the game's code too, picked as the page opens,
//  which an iPhone refuses with why. Their names are made up.
//

import Foundation

enum GalleryMods {
    /// The game's version on this iPhone, newer than the one a mod was
    /// added with.
    static let gameVersion = "1.2.0"

    /// The name of the ZIP of a mod that changes the game's code.
    static let codeModName = "Faster loading.zip"

    @MainActor private static var codeModWritten: Task<URL?, Never>?

    /// The game's mods, in the Documents GallerySaves made for it.
    @MainActor
    static func prepare() {
        let documents = GallerySaves.documents
        let folder = CartoucheMods.folder(in: documents)
        let made: [(name: String, on: Bool, version: String?, files: [(String, Int)])] = [
            ("Brighter colours", true, gameVersion, [("romfs/Shader/colour.bin", 2_400_000)]),
            ("Retro soundtrack", true, gameVersion, [("romfs/Sound/Resource/Stream/track1.bfstm", 18_000_000),
                                                     ("romfs/Sound/Resource/Stream/track2.bfstm", 21_000_000)]),
            ("Bigger text", false, "1.0.0", [("romfs/UI/font.bfttf", 3_100_000)]),
            ("Old textures", false, nil, [("Texture/kart.bntx", 9_600_000)]),
        ]
        var mods: [CartoucheMod] = []
        do {
            for (index, mod) in made.enumerated() {
                let root = folder.appendingPathComponent(mod.name, isDirectory: true)
                for (file, size) in mod.files {
                    let url = root.appendingPathComponent(file)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    // Sparse: the sizes show, the disk keeps nothing.
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.truncate(atOffset: UInt64(size))
                    try handle.close()
                }
                // The one copied in by hand is not in the list.
                guard mod.files.allSatisfy({ $0.0.hasPrefix("romfs/") }) else { continue }
                mods.append(CartoucheMod(folder: mod.name, name: mod.name, isOn: mod.on, files: mod.files.count,
                                         size: UInt64(mod.files.reduce(0) { $0 + $1.1 }), gameVersion: mod.version,
                                         added: Date().addingTimeInterval(-Double(index + 1) * 86_400)))
            }
            try CartoucheMods.save(mods, in: documents)
        } catch {
            NSLog("[Gallery] cannot make the game's mods: %@", String(describing: error))
        }
        codeModWritten = Task { await writeCodeMod() }
    }

    /// The ZIP of a mod that changes the game's code, once written.
    @MainActor
    static func codeMod() async -> URL? {
        await codeModWritten?.value
    }

    /// A mod as one is passed around: its folder, with the files it lays
    /// over the game's, and a plugin of code beside them.
    private static func writeCodeMod() async -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(codeModName)
        do {
            try? FileManager.default.removeItem(at: url)
            let sink = try CartoucheFileSink(url)
            let writer = CartoucheZipWriter(sink: sink)
            try await writer.addFolder("Faster loading/")
            try await writer.addData("Faster loading/romfs/System/loading.bin", Data(count: 4_096))
            try await writer.addData("Faster loading/exefs/subsdk9", Data(count: 4_096))
            try await writer.finish()
            try sink.close()
            return url
        } catch {
            NSLog("[Gallery] cannot write %@: %@", codeModName, String(describing: error))
            return nil
        }
    }
}
