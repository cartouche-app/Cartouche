//
//  HarnessGameTexts.swift
//  CartoucheHarness
//
//  Cartouche's code in the game's process that puts nxnative's texts in
//  Cartouche's language in the game's environment
//  (launcher/Guest/CartoucheGameTextsEnvironment.m), for the tests
//  (Tests/PlayTests.swift): on the iPhone, it runs in the game's process,
//  which the harness has none of, so the tests run it in the harness's own.
//

import Foundation

enum HarnessGameTexts {
    /// The file the game's process reads in its data folder.
    static var file: String { CartoucheGameTextsFile }

    /// The variables it may set, never another of nxnative's switches.
    static var variables: [String] { CartoucheGameTextsVariables() }

    /// Puts the texts of the file in the data folder HOME in this
    /// process's environment, but those it has already; the variables it
    /// set.
    @discardableResult
    static func apply(home: URL) -> [String] {
        CartoucheGameTextsApply(home.path)
    }
}
