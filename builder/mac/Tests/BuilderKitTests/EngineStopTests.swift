//
//  EngineStopTests.swift
//  BuilderKitTests
//
//  A command of the engine stopped because what asked for it went away. The
//  Storage page measured in its .task, which SwiftUI cancels when the page
//  goes away or is made anew: the engine was sent SIGTERM, the app read its
//  end as a crash and showed "exit 15", and the page measured no more (a
//  player's Mac, Cartouche for Mac 0.5.0 to 0.8.0, 25 November). A stop is
//  now a CancellationError, never the engine's error; and a measurement run
//  through SharedRun goes on to its end whoever stops waiting for it.
//

import Foundation
import XCTest
@testable import BuilderKit

final class EngineStopTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("EngineStopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// An engine whose Python is a script of SHELL's lines, whatever it is asked.
    private func engine(_ shell: String) throws -> Engine {
        let python = folder.appendingPathComponent("python3")
        try Data("#!/bin/sh\n\(shell)\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        return Engine(package: folder, python: python, home: BuilderHome(folder.appendingPathComponent("home", isDirectory: true)))
    }

    func testAStoppedCommandIsACancellationNotTheEnginesError() async throws {
        // What the engine wrote of the Storage page's measurement as the
        // page went away: nothing, and SIGTERM's 15.
        XCTAssertThrowsError(try Engine.decode(StorageAnswer.self, from: RunResult(status: SIGTERM, stopped: true))) { error in
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        // Ended by a SIGTERM the app did not send: the engine's end, as before.
        XCTAssertThrowsError(try Engine.decode(StorageAnswer.self, from: RunResult(status: SIGTERM))) { error in
            XCTAssertEqual((error as? EngineFailure)?.kind, "crashed", "\(error)")
            XCTAssertEqual((error as? EngineFailure)?.message, "exit 15")
        }
        // Stopped as it had answered: its answer.
        let answered = RunResult(status: 0, output: Data("{\"api\":1,\"followed\":true}\n".utf8), stopped: true)
        XCTAssertEqual(try Engine.decode(FollowAnswer.self, from: answered).followed, true)
    }

    func testTheStorageMeasuredInATaskCancelledIsNoError() async throws {
        let engine = try engine("exec sleep 30")
        let measuring = Task { try await engine.storage() }
        try await Task.sleep(nanoseconds: 500_000_000)
        let asked = Date()
        measuring.cancel()
        do {
            _ = try await measuring.value
            XCTFail("a measurement stopped half-way answered")
        } catch {
            XCTAssertTrue(error is CancellationError, "the player read: \(error.localizedDescription)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(asked), 15)
    }

    func testAMeasurementGoesOnWhenItsPageStopsWaiting() async throws {
        let engine = try engine("sleep 1; echo '{\"api\":1,\"followed\":true}'")
        let shared = await SharedRun<String>()
        let runs = Counter()
        let measure: @MainActor () async -> String = {
            runs.add()
            do {
                try await engine.follow("0100000000010000", true)
                return "answered"
            } catch {
                return error is CancellationError ? "stopped" : "failed: \(error)"
            }
        }
        // The page's .task, cancelled as the page goes away.
        let page = Task { await shared.run(measure) }
        try await Task.sleep(nanoseconds: 300_000_000)
        page.cancel()
        // The page made anew, asking again as the first still runs: it waits
        // for that one, which nothing stopped.
        let again = Task { await shared.run(measure) }
        let first = await page.value
        let second = await again.value
        XCTAssertEqual(first, "answered")
        XCTAssertEqual(second, "answered")
        XCTAssertEqual(runs.count, 1)
        let running = await shared.isRunning
        XCTAssertFalse(running)
        // Once ended, a new call measures again.
        let third = await shared.run(measure)
        XCTAssertEqual(third, "answered")
        XCTAssertEqual(runs.count, 2)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func add() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
