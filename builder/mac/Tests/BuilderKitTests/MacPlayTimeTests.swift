//
//  MacPlayTimeTests.swift
//  BuilderKitTests
//
//  A game's play time on this Mac (MacPlayTime.swift), counted as
//  Cartouche's counter counts it in a game on the iPhone, in the same file,
//  which Cartouche's console reads as the iPhone's does (CartouchePlayTime,
//  in CartoucheCore): the time its app is the Mac's active one, a session
//  for each run that came to the front, on a clock of the tests' own.
//

import CartoucheCore
import Foundation
import XCTest
@testable import BuilderKit

final class MacPlayTimeTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var uptime: TimeInterval = 1_000
    private var date = Date(timeIntervalSince1970: 1_763_200_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-play-time-\(UUID().uuidString)", isDirectory: true)
        folder = root.appendingPathComponent("0100152000022000", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func counter() -> MacPlayTime {
        MacPlayTime(folder: folder, clock: { [unowned self] in self.uptime }, now: { [unowned self] in self.date })
    }

    /// The time as the console reads it.
    private var read: CartouchePlayTime? { CartouchePlayTime.read(home: folder) }

    private func pass(_ seconds: TimeInterval) {
        uptime += seconds
        date = date.addingTimeInterval(seconds)
    }

    func testTheTimeInFrontIsWrittenWhereTheConsoleReadsIt() throws {
        let started = date
        let time = counter()
        XCTAssertEqual(time.file, folder.appendingPathComponent("Library/Cartouche/PlayTime.plist"))
        // In front: a session, written at once.
        time.cameToFront()
        XCTAssertTrue(time.isCounting)
        XCTAssertEqual(read, CartouchePlayTime(seconds: 0, sessions: 1, firstPlayed: started, lastPlayed: started))
        // Every 30 seconds, the time so far.
        pass(30)
        time.tick(inFront: true)
        XCTAssertEqual(read?.seconds, 30)
        pass(15)
        time.leftFront()
        XCTAssertFalse(time.isCounting)
        XCTAssertEqual(read?.seconds, 45)
        XCTAssertEqual(read?.lastPlayed, date)
        // Behind another app, nothing counts.
        pass(600)
        time.tick(inFront: false)
        time.leftFront()
        XCTAssertEqual(read?.seconds, 45)
        // Back in front: the same run, the same session.
        time.cameToFront()
        pass(20)
        time.leftFront()
        XCTAssertEqual(read?.seconds, 65)
        XCTAssertEqual(read?.sessions, 1)
        // The file holds this run as the iPhone's counter writes it.
        let data = try Data(contentsOf: time.file)
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual((plist["version"] as? NSNumber)?.intValue, CartouchePlayTime.version)
        let session = try XCTUnwrap(plist["lastSession"] as? [String: Any])
        XCTAssertEqual(session["start"] as? Date, started)
        XCTAssertEqual((session["seconds"] as? NSNumber)?.doubleValue, 65)
    }

    func testEachRunThatCameToTheFrontIsASession() throws {
        let first = date
        let time = counter()
        time.cameToFront()
        pass(100)
        time.leftFront()
        // The next run adds to what the last left.
        pass(3_600)
        let next = counter()
        next.tick(inFront: true)
        XCTAssertTrue(next.isCounting, "a game in front that nothing announced counts from the next tick")
        pass(50)
        next.leftFront()
        XCTAssertEqual(read, CartouchePlayTime(seconds: 150, sessions: 2, firstPlayed: first, lastPlayed: date))
        // A run that never came to the front is no session, and writes nothing.
        let behind = counter()
        let before = try Data(contentsOf: behind.file)
        behind.tick(inFront: false)
        behind.leftFront()
        XCTAssertEqual(try Data(contentsOf: behind.file), before)
    }

    func testNothingCountsWhileTheMacSleeps() {
        // The uptime stops while the Mac sleeps: a clock that goes back,
        // after a restart, adds nothing.
        let time = counter()
        time.cameToFront()
        uptime -= 500
        time.leftFront()
        XCTAssertEqual(read?.seconds, 0)
        XCTAssertEqual(read?.sessions, 1)
    }

    func testAnUnreadableFileStartsAgainFromNothing() throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Library/Cartouche"), withIntermediateDirectories: true)
        try Data("not a list".utf8).write(to: folder.appendingPathComponent(CartouchePlayTime.file))
        let time = counter()
        time.cameToFront()
        pass(12)
        time.leftFront()
        XCTAssertEqual(read?.seconds, 12)
        XCTAssertEqual(read?.sessions, 1)
    }
}
