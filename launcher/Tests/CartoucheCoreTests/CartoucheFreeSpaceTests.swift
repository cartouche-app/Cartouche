//
//  CartoucheFreeSpaceTests.swift
//  CartoucheCoreTests
//
//  The room left on a disk, read again at each question
//  (Sources/CartoucheFreeSpace.swift): on 15 November 2026, Cartouche
//  refused Ocarina of Time for want of the room it had 49 seconds before,
//  9.3 GB, which LCPath.docPath kept, though the player had freed 64 GB
//  since (cartouche-reports #10).
//

import XCTest
@testable import CartoucheCore

final class CartoucheFreeSpaceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartoucheFreeSpaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The same URL asked twice, as Cartouche asks LCPath.docPath before
    /// each install, with a game's files written on the disk in between:
    /// the second answer is the room the disk has now, not the one it had
    /// at the first.
    func testTheSecondReadingSaysTheRoomTheDiskHasNow() throws {
        let place = URL(fileURLWithPath: folder.path, isDirectory: true)
        let before = try XCTUnwrap(CartoucheFreeSpace.available(at: place))
        try write(megabytes: 256, to: place.appendingPathComponent("game.bin"))
        let after = try XCTUnwrap(CartoucheFreeSpace.available(at: place))
        // Half of it at least, whatever else writes or frees on this disk
        // meanwhile; a reading kept from the first would say the same.
        XCTAssertLessThan(after, before - (128 << 20),
                          "256 MB written between the two readings, which say \(before) and \(after) bytes")
    }

    /// A URL that holds a value for the room for a game, as LCPath.docPath
    /// held the 9.26 GB of the install refused before: the room is read
    /// again, not taken from it.
    func testTheRoomForAGameIsNotWhatTheURLHolds() throws {
        let kept: Int64 = 9_262_491_986
        var place = URL(fileURLWithPath: folder.path, isDirectory: true)
        #if canImport(Darwin)
        place.setTemporaryResourceValue(kept, forKey: .volumeAvailableCapacityForImportantUsageKey)
        let held = (try place.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
            .volumeAvailableCapacityForImportantUsage
        #else
        place.setTemporaryResourceValue(Int(kept), forKey: .volumeAvailableCapacityKey)
        let held = (try place.resourceValues(forKeys: [.volumeAvailableCapacityKey])).volumeAvailableCapacity.map(Int64.init)
        #endif
        // What reading the URL itself gives: the value it holds, as the
        // install of 15 November read it.
        guard held == kept else {
            throw XCTSkip("this system's own value comes before the one the URL holds: \(String(describing: held))")
        }
        XCTAssertNotEqual(CartoucheFreeSpace.forImportantUsage(at: place), kept)
    }

    /// Writes MEGABYTES of bytes in a file at URL, all on the disk.
    private func write(megabytes: Int, to url: URL) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let block = Data(repeating: 0xA5, count: 1 << 20)
        for _ in 0 ..< megabytes {
            try handle.write(contentsOf: block)
        }
        try handle.synchronize()
    }
}
