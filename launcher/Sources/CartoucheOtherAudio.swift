//
//  CartoucheOtherAudio.swift
//  Cartouche
//
//  Keep other apps' sound (System › While a game runs): the music or
//  podcast the player plays in another app goes on under the game's sound,
//  rather than stopping as the game starts. Off unless the player turns it
//  on: then nothing changes from before, the game's sound stops other
//  apps', as nxnative sets it (docs/decisions/168.md).
//
//  As Play starts one of nxnative's games, behind the console or in
//  Cartouche's place, Cartouche writes the player's choice in the game's
//  data folder: Library/Cartouche/OtherAudio.plist, which Cartouche's code
//  in the game's process reads (launcher/Guest/CartoucheOtherAudio.m), and
//  which mixes the game's audio session with other apps' sound
//  (CartoucheOtherAudioSession.m). Off, the file goes. A game paused behind
//  the console keeps what it started with until it starts again. The game
//  measurements say, for each session, whether the game ran with it
//  (otherAudio, telemetry/README.md), as the file in its data folder says.
//
//  Only the iPhone has it: on the Mac, macOS plays every app's sound
//  together, and a game of nxnative's plays through the Mac's default
//  output, as any app does, without taking the device for itself.
//

import Combine
import Foundation

/// The file that tells a game to keep other apps' sound.
enum CartoucheOtherAudio {
    /// In the game's data folder; CartoucheOtherAudioSession.m reads it
    /// (CartoucheOtherAudioFile).
    static let file = "Library/Cartouche/OtherAudio.plist"
    /// YES while the player keeps other apps' sound
    /// (CartoucheOtherAudioKey).
    static let key = "keep"
    static let version = 1

    /// Writes KEEPING in HOME, the data folder of a game about to start:
    /// the file, or none at all.
    static func write(keeping: Bool, home: URL) throws {
        let url = home.appendingPathComponent(file)
        guard keeping else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = [key: true, "version": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
    }

    /// Whether the game whose data folder is HOME started with other apps'
    /// sound kept, as its file says.
    static func isKept(home: URL) -> Bool {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(file)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        return (plist[key] as? NSNumber)?.boolValue == true
    }
}

/// The player's choice, in Cartouche's preferences: off until they turn it
/// on.
@MainActor
final class CartoucheOtherAudioSetting: ObservableObject {
    static let shared = CartoucheOtherAudioSetting()

    static let defaultsKey = "Cartouche.keepOtherAudio"

    @Published var keeps: Bool {
        didSet { UserDefaults.standard.set(keeps, forKey: Self.defaultsKey) }
    }

    private init() {
        keeps = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }
}
