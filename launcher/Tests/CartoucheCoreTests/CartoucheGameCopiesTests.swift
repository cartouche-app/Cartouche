//
//  CartoucheGameCopiesTests.swift
//  CartoucheCoreTests
//
//  A game in several of the player's games folders (Sources/
//  CartoucheGameCopies.swift): the copy Cartouche offers is one it can
//  reach, and the folders keep their order, the first one being where a
//  game is copied to.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheGameCopiesTests: XCTestCase {
    private let night = Date(timeIntervalSince1970: 1_794_281_224)

    private func rank(offline: Bool = false, folder: Int = 0, version: String? = nil, builtAt: Date? = nil,
                      modified: Date? = nil) -> CartoucheCopyRank {
        let build = version == nil && builtAt == nil ? nil : CartoucheGameBuild(version: version, builtAt: builtAt)
        return CartoucheCopyRank(offline: offline, folder: folder, build: build, modified: modified)
    }

    // MARK: Which copy

    /// The NAS away from home, the same game on the Drive: the Drive's.
    func testACopyThatAnswersComesBeforeOneThatDoesNot() {
        let nas = rank(offline: true, folder: 0, builtAt: night)
        let drive = rank(offline: false, folder: 1, builtAt: night)
        XCTAssertTrue(CartoucheGameCopies.prefers(drive, over: nas))
        XCTAssertFalse(CartoucheGameCopies.prefers(nas, over: drive))
    }

    /// Even a newer build waits for its server: the older one plays now.
    func testAnOlderBuildThatAnswersComesBeforeANewerOneThatDoesNot() {
        let newer = rank(offline: true, folder: 0, version: "1.2.0", builtAt: night)
        let older = rank(offline: false, folder: 1, version: "1.0.0", builtAt: night.addingTimeInterval(-86_400))
        XCTAssertTrue(CartoucheGameCopies.prefers(older, over: newer))
    }

    /// Both answer: the newer build, wherever it is; then the one written
    /// last; then the first folder's.
    func testBetweenCopiesThatAnswerTheNewerBuildThenTheFirstFolder() {
        let first = rank(folder: 0, version: "1.0.0", builtAt: night)
        let second = rank(folder: 1, version: "1.1.0", builtAt: night.addingTimeInterval(-3_600))
        XCTAssertTrue(CartoucheGameCopies.prefers(second, over: first))
        XCTAssertFalse(CartoucheGameCopies.prefers(first, over: second))

        let rebuilt = rank(folder: 1, version: "1.0.0", builtAt: night.addingTimeInterval(3_600))
        XCTAssertTrue(CartoucheGameCopies.prefers(rebuilt, over: first))

        let unread = rank(folder: 1, modified: night)
        let unreadFirst = rank(folder: 0, modified: night.addingTimeInterval(-60))
        XCTAssertTrue(CartoucheGameCopies.prefers(unread, over: unreadFirst), "written there last")

        let same = rank(folder: 1, version: "1.0.0", builtAt: night)
        XCTAssertTrue(CartoucheGameCopies.prefers(first, over: same))
        XCTAssertFalse(CartoucheGameCopies.prefers(same, over: first))
        XCTAssertFalse(CartoucheGameCopies.prefers(first, over: first))
    }

    /// Both offline: as before, the newer build, which the console names.
    func testBetweenCopiesThatDoNotAnswerTheNewerBuild() {
        let nas = rank(offline: true, folder: 0, version: "1.0.0", builtAt: night)
        let mac = rank(offline: true, folder: 1, version: "1.1.0", builtAt: night)
        XCTAssertTrue(CartoucheGameCopies.prefers(mac, over: nas))
    }

    func testTheCopiesInTheOrderToTryThem() {
        let copies = [("NAS", rank(offline: true, folder: 0, builtAt: night)),
                      ("Drive", rank(folder: 1, builtAt: night)),
                      ("Mac", rank(folder: 2, builtAt: night)),
                      ("S3", rank(offline: true, folder: 3, builtAt: night.addingTimeInterval(60)))]
        XCTAssertEqual(CartoucheGameCopies.ordered(copies, by: \.1).map(\.0), ["Drive", "Mac", "S3", "NAS"])
        XCTAssertEqual(CartoucheGameCopies.ordered([("A", rank()), ("B", rank())], by: \.1).map(\.0), ["A", "B"],
                       "the same: in the order given")
    }

    // MARK: The folders

    func testTheFoldersKeepTheirOrderAndNeverTheSameTwice() {
        var folders = CartoucheGamesFolderList<String>(first: nil)
        XCTAssertTrue(folders.isEmpty)
        XCTAssertTrue(folders.add("NAS|Jeux"))
        XCTAssertEqual(folders.first, "NAS|Jeux", "the first one added is the first")
        XCTAssertTrue(folders.add("Drive|Jeux"))
        XCTAssertTrue(folders.add("Mac|Games"))
        XCTAssertFalse(folders.add("Drive|Jeux"))
        XCTAssertFalse(folders.add("NAS|Jeux"))
        XCTAssertEqual(folders.all, ["NAS|Jeux", "Drive|Jeux", "Mac|Games"])

        let kept = CartoucheGamesFolderList(first: "NAS|Jeux", others: ["NAS|Jeux", "Drive|Jeux", "Drive|Jeux"])
        XCTAssertEqual(kept.all, ["NAS|Jeux", "Drive|Jeux"])
        let without = CartoucheGamesFolderList<String>(first: nil, others: ["Drive|Jeux", "Mac|Games"])
        XCTAssertEqual(without.first, "Drive|Jeux", "the others with no first: the first of them")
        XCTAssertEqual(without.others, ["Mac|Games"])
    }

    func testStoppingTheFirstFolderGivesItsPlaceToTheNext() {
        var folders = CartoucheGamesFolderList(first: "NAS|Jeux", others: ["Drive|Jeux", "Mac|Games"])
        XCTAssertFalse(folders.remove("Mac|Games"))
        XCTAssertEqual(folders.all, ["NAS|Jeux", "Drive|Jeux"])
        XCTAssertTrue(folders.remove("NAS|Jeux"))
        XCTAssertEqual(folders.first, "Drive|Jeux")
        XCTAssertEqual(folders.others, [])
        XCTAssertTrue(folders.remove("Drive|Jeux"))
        XCTAssertNil(folders.first)
        XCTAssertFalse(folders.remove("Drive|Jeux"))
    }

    func testChangingTheFirstFolderToAnotherTakesItFromTheOthers() {
        var folders = CartoucheGamesFolderList(first: "NAS|Jeux", others: ["Drive|Jeux", "Mac|Games"])
        folders.choose("Mac|Games")
        XCTAssertEqual(folders.all, ["Mac|Games", "Drive|Jeux"], "the NAS's folder changed for the Mac's")
        folders.choose("S3|Jeux")
        XCTAssertEqual(folders.all, ["S3|Jeux", "Drive|Jeux"])
    }

    /// A server removed, here or on the paired Mac, and one replaced by
    /// another of the same place.
    func testFoldersOfAServerGoneGoAndTheNextTakesTheFirstsPlace() {
        var folders = CartoucheGamesFolderList(first: "NAS|Jeux", others: ["Drive|Jeux", "NAS|Autres", "Old|Jeux"])
        XCTAssertTrue(folders.move { $0.hasPrefix("NAS|") ? nil : $0 })
        XCTAssertEqual(folders.all, ["Drive|Jeux", "Old|Jeux"])
        XCTAssertFalse(folders.move { $0 == "Old|Jeux" ? "New|Jeux" : $0 })
        XCTAssertEqual(folders.all, ["Drive|Jeux", "New|Jeux"])
        XCTAssertFalse(folders.move { $0 == "New|Jeux" ? "Drive|Jeux" : $0 })
        XCTAssertEqual(folders.all, ["Drive|Jeux"], "moved onto one there already: once")
    }
}
