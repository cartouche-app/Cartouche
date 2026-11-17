//
//  CartoucheNamingTests.swift
//  CartoucheCoreTests
//
//  The help on naming the games (Sources/CartoucheNaming.swift) says what
//  Cartouche does: each example of the games folder and of the saves folder
//  is found, or left aside, by the rules Cartouche reads those folders by,
//  and named as Cartouche names what it writes. The dumps folder's are the
//  Builder's, which builder/tests/test_naming.py checks against its own.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheNamingTests: XCTestCase {
    private let game = CartoucheNaming.exampleTitleId

    // MARK: The rules

    func testTheTitleIdIsSixteenDigitsInSquareBrackets() {
        XCTAssertEqual(CartoucheNaming.titleId(inName: "Example Quest [0100F00D0BAD0000].ipa"), game)
        XCTAssertEqual(CartoucheNaming.titleId(inName: "example quest [0100f00d0bad0000].IPA"), game)
        XCTAssertEqual(CartoucheNaming.titleId(inName: "[0100F00D0BAD0000] Example Quest.ipa"), game)
        XCTAssertEqual(CartoucheNaming.titleId(inName: "Example Quest [0100F00D0BAD0800][v65536].nsp"), "0100F00D0BAD0800")
        XCTAssertNil(CartoucheNaming.titleId(inName: "Example Quest.ipa"))
        XCTAssertNil(CartoucheNaming.titleId(inName: "Example Quest 0100F00D0BAD0000.ipa"), "not in square brackets")
        XCTAssertNil(CartoucheNaming.titleId(inName: "Example Quest [0100F00D0BAD000].ipa"), "15 digits")
        XCTAssertNil(CartoucheNaming.titleId(inName: "Example Quest [0100F00D0BAD0000G].ipa"))
        XCTAssertNil(CartoucheNaming.titleId(inName: "Example Quest [v0].ipa"))
    }

    func testAnIPAIsANameEndingInIpaInAnyLetterCase() {
        XCTAssertTrue(CartoucheNaming.isIPA("Example Quest.ipa"))
        XCTAssertTrue(CartoucheNaming.isIPA("Example Quest.IPA"))
        XCTAssertFalse(CartoucheNaming.isIPA("Example Quest.ipa.zip"))
        XCTAssertFalse(CartoucheNaming.isIPA("Example Quest [0100F00D0BAD0000].app.zip"))
    }

    func testAGamesSavesFolderEndsWithItsTitleIdWhateverIsBefore() {
        XCTAssertTrue(CartoucheNaming.isSavesFolder("Example Quest [0100F00D0BAD0000]", of: game))
        // As a Mac names it, after the game's app for the Mac.
        XCTAssertTrue(CartoucheNaming.isSavesFolder("Example Quest for the Mac [0100f00d0bad0000]", of: game.lowercased()))
        XCTAssertFalse(CartoucheNaming.isSavesFolder("Example Quest", of: game))
        XCTAssertFalse(CartoucheNaming.isSavesFolder("[0100F00D0BAD0000] Example Quest", of: game))
        XCTAssertFalse(CartoucheNaming.isSavesFolder("Example Quest [0100F00D0BAD0800]", of: game))
    }

    // MARK: The examples

    func testEachPlaceShowsWhatItFindsThenWhatItLeavesAside() {
        for place in CartoucheNaming.Place.allCases {
            let examples = CartoucheNaming.examples(in: place)
            XCTAssertTrue(examples.contains { $0.isFound }, place.rawValue)
            XCTAssertTrue(examples.contains { !$0.isFound }, place.rawValue)
            let firstAside = examples.firstIndex { !$0.isFound } ?? examples.count
            XCTAssertTrue(examples[firstAside...].allSatisfy { !$0.isFound }, "\(place.rawValue): found after left aside")
        }
        XCTAssertEqual(CartoucheNaming.examples.map(\.place), CartoucheNaming.Place.allCases.flatMap { place in
            CartoucheNaming.examples(in: place).map(\.place)
        }, "by place, in the page's order")
    }

    func testEachMeaningIsOneExamplesAndEachPathIsOnce() {
        XCTAssertEqual(CartoucheNaming.examples.map(\.meaning).sorted { $0.rawValue < $1.rawValue },
                       CartoucheNaming.Meaning.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(Set(CartoucheNaming.examples.map(\.id)).count, CartoucheNaming.examples.count)
        for example in CartoucheNaming.examples {
            XCTAssertFalse(example.path.hasPrefix("/"), example.path)
            XCTAssertFalse(example.path.contains("//"), example.path)
            XCTAssertFalse(example.name.isEmpty, example.path)
            // A folder's name, or a file's, with no "/" of its own.
            XCTAssertFalse(example.name.contains("/"), example.path)
        }
    }

    /// The games folder, as CartoucheStoredGames reads it: its IPAs and the
    /// images of their game files, at its top and in the folders right in
    /// it. What the Builder keeps there for the Mac is not the iPhone's.
    func testTheGamesFolderExamplesAreWhatCartoucheFinds() {
        for example in CartoucheNaming.examples(in: .games) {
            let name = example.name
            let read = example.folders.count <= 1 && !example.isFolder
            switch example.meaning {
            case .macApp:
                XCTAssertFalse(CartoucheNaming.isIPA(name))
                XCTAssertFalse(CartoucheRomfs.isImageName(name))
                XCTAssertTrue(name.hasSuffix(".app.zip"))
                XCTAssertEqual(CartoucheNaming.titleId(inName: name), game)
                XCTAssertTrue(example.isFound, "found by the Mac")
            case .namedIPA:
                XCTAssertTrue(read && CartoucheNaming.isIPA(name))
                XCTAssertEqual(CartoucheNaming.titleId(inName: name), game)
                XCTAssertTrue(example.isFound)
            case .unnamedIPA:
                XCTAssertTrue(read && CartoucheNaming.isIPA(name))
                XCTAssertNil(CartoucheNaming.titleId(inName: name), "read inside")
                XCTAssertTrue(example.isFound)
            case .gameFiles:
                XCTAssertTrue(read && CartoucheRomfs.isImageName(name))
                XCTAssertTrue(example.isFound)
            case .tooDeep:
                XCTAssertTrue(CartoucheNaming.isIPA(name))
                XCTAssertFalse(read, "two folders down")
                XCTAssertFalse(example.isFound)
            default:
                XCTFail("\(example.meaning) in the games folder")
            }
        }
    }

    /// The saves folder, as CartoucheSavesFolder reads it: a folder per game
    /// whose name ends with its title ID, and in it the copies Cartouche
    /// named by their dates.
    func testTheSavesFolderExamplesAreWhatCartoucheFinds() {
        for example in CartoucheNaming.examples(in: .saves) {
            switch example.meaning {
            case .gameFolder:
                XCTAssertTrue(example.isFolder && example.folders.isEmpty)
                XCTAssertTrue(CartoucheNaming.isSavesFolder(example.name, of: game))
                XCTAssertTrue(example.isFound)
            case .unnamedFolder:
                XCTAssertTrue(example.isFolder && example.folders.isEmpty)
                XCTAssertFalse(CartoucheNaming.isSavesFolder(example.name, of: game))
                XCTAssertFalse(example.isFound)
            case .copy:
                XCTAssertEqual(example.folders.count, 1)
                XCTAssertTrue(example.folders.allSatisfy { CartoucheNaming.isSavesFolder($0, of: game) })
                let date = CartoucheSaveSync.date(inName: example.name)
                XCTAssertNotNil(date)
                // Named as Cartouche names the copies it makes.
                XCTAssertEqual(date.map(CartoucheSaveSync.fileName), example.name)
                XCTAssertTrue(example.isFound)
            case .notACopy:
                XCTAssertEqual(example.folders.count, 1)
                XCTAssertTrue(example.folders.allSatisfy { CartoucheNaming.isSavesFolder($0, of: game) })
                XCTAssertTrue(example.name.lowercased().hasSuffix(".zip"))
                XCTAssertNil(CartoucheSaveSync.date(inName: example.name))
                XCTAssertFalse(example.isFound)
            default:
                XCTFail("\(example.meaning) in the saves folder")
            }
        }
    }

    func testTheDumpsFolderExamplesAreTheBuilders() {
        let meanings: Set<CartoucheNaming.Meaning> = [.package, .update, .nup, .dump, .buildFolder, .built]
        XCTAssertEqual(Set(CartoucheNaming.examples(in: .dumps).map(\.meaning)), meanings)
    }
}
