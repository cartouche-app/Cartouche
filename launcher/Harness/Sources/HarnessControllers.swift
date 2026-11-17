//
//  HarnessControllers.swift
//  CartoucheHarness
//
//  How a game's process asks for the keyboard, which brings it the
//  controllers (launcher/LiveProcessSupport/CartoucheGuestControllers.m),
//  for the tests (Tests/ControllerTests.swift): on the iPhone, it runs in
//  the game's process, in LiveContainer's LiveProcess extension, which the
//  harness has none of, so the tests run it in the harness's own scene.
//

import UIKit

enum HarnessControllers {
    /// The game's scene is active: its process asks for the keyboard.
    static func take(_ scene: UIWindowScene) {
        CartoucheGuestTakeControllers(scene)
    }

    /// The game's scene resigns active: its process lets the keyboard go.
    static func leave(_ scene: UIWindowScene) {
        CartoucheGuestLeaveControllers(scene)
    }

    /// Whether the game's process asks for the keyboard in SCENE now.
    static func holds(_ scene: UIWindowScene) -> Bool {
        CartoucheGuestHoldsControllers(scene)
    }
}
