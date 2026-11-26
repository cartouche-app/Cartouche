//
//  HarnessOtherAudio.swift
//  CartoucheHarness
//
//  Cartouche's code in the game's process that mixes the game's sound with
//  other apps' sound, when the player keeps it
//  (launcher/Guest/CartoucheOtherAudioSession.m), for the tests
//  (Tests/OtherAudioTests.swift, Tests/PlayTests.swift): on the iPhone, it
//  runs in the game's process, which the harness has none of, so the tests
//  run it in the harness's own, with the Simulator's AVAudioSession.
//

import Foundation

enum HarnessOtherAudio {
    /// The file the game's process reads in its data folder.
    static var file: String { CartoucheOtherAudioFile }

    /// Whether the game's process, its data folder HOME, keeps other apps'
    /// sound, as it reads the file there.
    static func isKept(home: URL) -> Bool {
        CartoucheOtherAudioIsKept(home.path)
    }

    /// The game's process keeps other apps' sound, or no longer does: false
    /// when this process has not AVAudioSession's calls.
    @discardableResult
    static func keep(_ keep: Bool) -> Bool {
        CartoucheOtherAudioKeep(keep)
    }
}
