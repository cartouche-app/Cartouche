//
//  OtherAudioTests.swift
//  CartoucheHarnessTests
//
//  Keep other apps' sound (System › While a game runs), in the game's
//  process (launcher/Guest/CartoucheOtherAudioSession.m), run here with the
//  Simulator's AVAudioSession: nxnative sets the game's session to the
//  Playback category alone (front_ios.m), which stops other apps' sound;
//  kept, every category the game sets that takes it mixes with theirs,
//  however the game sets it, and the rest of its options stay. Off, the
//  category is as the game sets it. What Play tells the game is in
//  PlayTests.
//

import AVFAudio
import XCTest
@testable import CartoucheHarness

final class OtherAudioTests: HarnessCase {
    private let session = AVAudioSession.sharedInstance()

    override func setUp() async throws {
        // The Simulator's first category goes to its audio server, before
        // the watchdog times the main thread: a game sets its own long
        // before the player hears it.
        try? session.setCategory(.soloAmbient, mode: .default, options: [])
        try await super.setUp()
    }

    override func tearDown() async throws {
        HarnessOtherAudio.keep(false)
        try? session.setCategory(.soloAmbient, mode: .default, options: [])
        try await super.tearDown()
    }

    private var mixes: Bool { session.categoryOptions.contains(.mixWithOthers) }

    /// Up to 0.16.2, a game's sound stopped the player's music or podcast:
    /// nxnative's Playback category, set alone, does not mix.
    func testOffTheGamesCategoryStaysAsTheGameSetsIt() throws {
        XCTAssertTrue(HarnessOtherAudio.keep(false))
        try session.setCategory(.playback)
        XCTAssertEqual(session.category, .playback)
        XCTAssertFalse(mixes)
        try session.setCategory(.playback, mode: .default, options: [])
        XCTAssertFalse(mixes)
    }

    /// Kept, the category nxnative sets, and sets again as the game comes
    /// back to the front or after a call, mixes with other apps' sound.
    func testKeptTheGamesCategoryMixesWithOtherAppsSound() throws {
        XCTAssertTrue(HarnessOtherAudio.keep(true), "the Simulator's AVAudioSession has the calls that set its category")
        try session.setCategory(.playback)
        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(mixes)
        try session.setCategory(.playback)
        XCTAssertTrue(mixes, "set again, as nxnative does after an interruption")
    }

    /// However the game sets its category, with its options, its mode or a
    /// policy for its route: the mix comes with its own options.
    func testEveryWayOfSettingTheCategoryMixesAndKeepsTheGamesOptions() throws {
        HarnessOtherAudio.keep(true)
        try session.setCategory(.playback, options: [])
        XCTAssertTrue(mixes)
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        XCTAssertEqual(session.mode, .moviePlayback)
        XCTAssertTrue(mixes)
        try session.setCategory(.playback, mode: .default, policy: .default, options: [])
        XCTAssertTrue(mixes)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertTrue(session.categoryOptions.contains(.defaultToSpeaker), "the game's own option stays")
        XCTAssertTrue(mixes)
    }

    /// A category that does not take the option is set as the game sets it,
    /// without an error.
    func testACategoryThatTakesNoMixIsLeftAsItIs() throws {
        HarnessOtherAudio.keep(true)
        try session.setCategory(.soloAmbient)
        XCTAssertEqual(session.category, .soloAmbient)
        XCTAssertFalse(mixes)
    }

    /// A category the game set before Cartouche's code heard it should keep
    /// other apps' sound mixes from then on.
    func testACategorySetBeforeMixesOnceKept() throws {
        HarnessOtherAudio.keep(false)
        try session.setCategory(.playback, mode: .default, options: [])
        XCTAssertFalse(mixes)
        HarnessOtherAudio.keep(true)
        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(mixes)
    }
}
