//
//  CartoucheGameRoomTests.swift
//  CartoucheCoreTests
//
//  The room a game's memory takes on the disk (Sources/CartoucheGameRoom.swift):
//  nxnative stops a game whose memory it keeps in files once the free space
//  runs short, even when iOS counts much more as available, and Cartouche
//  said only that the game had closed on its own, start after start (a
//  problem report of 26 November 2026). The lines are nxnative's, as
//  guest_file_init and guest_file_thread write them (hle_svc.c, at
//  nxnative 2f959ed); the figures are made up.
//

import XCTest
@testable import CartoucheCore

final class CartoucheGameRoomTests: XCTestCase {
    private static let gigabyte: Int64 = 1 << 30

    private static let start = """
        boot: game language en-US
        [dm] main guest thread QoS 0x21 (priority 44)
        [dm] >>> nnosInitialize
        [dm] [mem] guest memory: memory pool 9.00 GB and the host's margin 4.50 GB (half the pool), room to the memory limit 5.98 GB, DM_GUEST_FILE unset: in files
        [dm] front end: Duo hinge status 3, angle 3.142
        [dm] [mem] guest memory: 22 files of 1.00 GB in <path> (unlinked, sparse, shared), 21.25 GB in all, on the apfs volume, 7.5 GB free on it (48.0 with what the system can purge); holes punched where the game gives memory back: on
        [dm] guest AS 0x7000000000 +0x550000000  heap 0x7010000000 alias 0x7150000000 stack 0x7140000000
        """
    private static let stop = "[dm] [RED] [mem] guest file: 2.4 GB free on its disk (47.2 with what the system can purge), 1.8 GB of it still to be taken by dirty pages: under 2.0 GB left, stopping the game"

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartoucheGameRoomTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The start of the log says the memory went in files, and how large
    /// the pool is: the game may take the pool and nxnative's minimum.
    func testTheStartTellsTheMemoryInFilesAndItsPool() throws {
        let files = try XCTUnwrap(CartoucheGameRoom.files(inLog: Self.start))
        XCTAssertEqual(files.poolBytes, 9 * Self.gigabyte)
        XCTAssertEqual(files.minimumBytes, 2 * Self.gigabyte)
        XCTAssertEqual(files.neededBytes, 11 * Self.gigabyte)
    }

    /// A game whose memory stayed in its process, or whose files could not
    /// be made, needs no room: no check before it starts.
    func testMemoryOutsideFilesNeedsNoRoom() {
        let anonymous = """
            [dm] [mem] guest memory: memory pool 3.21 GB and the host's margin 1.61 GB (half the pool), room to the memory limit 5.98 GB, DM_GUEST_FILE unset: anonymous
            """
        XCTAssertNil(CartoucheGameRoom.files(inLog: anonymous))
        let refused = """
            [dm] [mem] guest memory: memory pool 9.00 GB and the host's margin 4.50 GB (half the pool), room to the memory limit 5.98 GB, DM_GUEST_FILE unset: in files
            [dm] [RED] [mem] guest memory: anonymous (DM_GUEST_FILE: 1.2 GB free on their disk (1.4 with what the system can purge), under 2.0)
            """
        XCTAssertNil(CartoucheGameRoom.files(inLog: refused))
        XCTAssertNil(CartoucheGameRoom.files(inLog: ""))
    }

    /// A minimum the player set (DM_GUEST_FILE_MIN_FREE), which nxnative
    /// says when the files may not fit, counts in place of 2 GB.
    func testTheMinimumNxnativeSaysCounts() throws {
        let text = Self.start + "\n[dm] [RED] [mem] guest file: the files may take up to the memory pool, 9.0 GB, and 7.5 GB is free: the game is stopped if under 4.0 GB is left"
        let files = try XCTUnwrap(CartoucheGameRoom.files(inLog: text))
        XCTAssertEqual(files.minimumBytes, 4 * Self.gigabyte)
    }

    /// The end of the log says nxnative stopped the game for lack of room,
    /// with what was free and what iOS counted as available.
    func testTheEndTellsTheStop() throws {
        let text = Self.start + "\n[dm] [nvn-mtl] compute loop containment: kernel 1_b, 3 loop sites\n" + Self.stop
            + "\n[dm] [nvn-mtl] compute loop containment: kernel 2_b, 3 loop sites"
        let stop = try XCTUnwrap(CartoucheGameRoom.stop(inLog: text))
        XCTAssertEqual(stop.freeBytes, Int64((2.4 * 1_073_741_824).rounded()))
        XCTAssertEqual(stop.availableBytes, Int64((47.2 * 1_073_741_824).rounded()))
        XCTAssertEqual(stop.minimumBytes, 2 * Self.gigabyte)
        XCTAssertTrue(CartoucheGameRoom.countsPurgeable(free: stop.freeBytes, available: stop.availableBytes))
    }

    /// The going on nxnative writes while iOS counts enough, and a game
    /// that ended otherwise, are no stop.
    func testOnlyTheStopIsOne() {
        let goingOn = "[dm] [mem] guest file: 4.9 GB free on its disk, less 2.9 GB for dirty pages, is under 2.0 GB, but 47.2 GB with what the system can purge: going on (stopping under 1.0 GB of f_bavail)"
        XCTAssertFalse(CartoucheGameRoom.isStop(goingOn))
        XCTAssertNil(CartoucheGameRoom.stop(inLog: Self.start + "\n" + goingOn))
        XCTAssertNil(CartoucheGameRoom.stop(inLog: "[dm] CRASH sig=6 pc=main+0x10"))
        XCTAssertTrue(CartoucheGameRoom.isStop(Self.stop))
    }

    /// nxnative writes -1 when it could not read what iOS counts as
    /// available: the stop says none.
    func testAStopWithoutWhatIOSCounts() throws {
        let stop = try XCTUnwrap(CartoucheGameRoom.stop(inLog: "[RED] [mem] guest file: 0.9 GB free on its disk (-0.0 with what the system can purge), 0.2 GB of it still to be taken by dirty pages: under 2.0 GB left, stopping the game"))
        XCTAssertNil(stop.availableBytes)
        XCTAssertFalse(CartoucheGameRoom.countsPurgeable(free: stop.freeBytes, available: stop.availableBytes))
    }

    /// Before a start: free space under the pool and the minimum is short,
    /// whatever iOS counts as available, since iOS purges too late.
    func testTheFreeSpaceIsShortUnderThePoolAndTheMinimum() throws {
        let files = try XCTUnwrap(CartoucheGameRoom.files(inLog: Self.start))
        XCTAssertTrue(CartoucheGameRoom.isShort(7 * Self.gigabyte, for: files))
        XCTAssertTrue(CartoucheGameRoom.isShort(11 * Self.gigabyte - 1, for: files))
        XCTAssertFalse(CartoucheGameRoom.isShort(11 * Self.gigabyte, for: files))
        XCTAssertFalse(CartoucheGameRoom.isShort(80 * Self.gigabyte, for: files))
        XCTAssertFalse(CartoucheGameRoom.countsPurgeable(free: 7 * Self.gigabyte, available: 7 * Self.gigabyte + 10))
    }

    /// From the game's log on the disk: the start from its first lines, the
    /// stop from its last, however long the session was.
    func testTheLogOnTheDisk() throws {
        let log = folder.appendingPathComponent("log.txt")
        let middle = String(repeating: "[dm] [nvn-mtl] blend: a zero source weight on a floating-point target (outputs 0x1)\n", count: 4_000)
        try (Self.start + "\n" + middle + Self.stop + "\n").write(to: log, atomically: true, encoding: .utf8)
        XCTAssertEqual(CartoucheGameRoom.files(ofLog: log)?.poolBytes, 9 * Self.gigabyte)
        XCTAssertNotNil(CartoucheGameRoom.stop(ofLog: log))
        let played = folder.appendingPathComponent("played.txt")
        try (Self.start + "\n" + middle).write(to: played, atomically: true, encoding: .utf8)
        XCTAssertNil(CartoucheGameRoom.stop(ofLog: played))
        XCTAssertNil(CartoucheGameRoom.files(ofLog: folder.appendingPathComponent("none.txt")))
    }
}
