//
//  RunTests.swift
//  BuilderKitTests
//
//  Run.program, which runs the engine's commands, Xcode's and Homebrew's:
//  what a program wrote and how it ended, the lines of its errors as they
//  come, its folder and environment, a timeout or a Stop that ends it; and
//  thousands of programs that end at once, each seen to end. Foundation's
//  Process.waitUntilExit once waited for good for a program whose output and
//  errors had ended, and the app's tests with it (the Builder's Mac tests on
//  CI, 15 November, run 43711191427). Run.program waited in it then: here,
//  8 of its first 261 runs never ended, though their programs had (pull
//  request #214, run 43728948839).
//

import Foundation
import XCTest
@testable import BuilderKit

final class RunTests: XCTestCase {
    func testWhatAProgramWroteAndHowItEnded() async throws {
        let result = try await Run.program("/bin/sh", ["-c", "printf out; printf err >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.text, "out")
        XCTAssertEqual(result.errorText, "err")
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.succeeded)
        // Its input is empty: it never waits for what nobody will type.
        let reader = try await Run.program("/bin/cat")
        XCTAssertEqual(reader.status, 0)
        XCTAssertEqual(reader.text, "")
        XCTAssertTrue(reader.succeeded)
    }

    func testTheLinesOfItsErrorsAsTheyCome() async throws {
        let lines = Locked<[String]>([])
        let result = try await Run.program("/bin/sh", ["-c", "echo one >&2; printf 'two\\r\\n' >&2; echo >&2; printf three >&2"]) { line in
            lines.update { $0.append(line) }
        }
        XCTAssertEqual(lines.current, ["one", "two", "three"])
        XCTAssertEqual(result.errorText, "one\ntwo\r\n\nthree")
    }

    func testItsFolderAndEnvironment() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("here\n".utf8).write(to: folder.appendingPathComponent("file"))
        let result = try await Run.program("/bin/sh", ["-c", "cat file; echo \"$RUN_TESTS\""],
                                           environment: Run.environment(["RUN_TESTS": "yes"]), directory: folder)
        XCTAssertEqual(result.text, "here\nyes\n")
        XCTAssertEqual(result.status, 0)
    }

    func testATimeoutEndsIt() async throws {
        let asked = Date()
        let result = try await Run.program("/bin/sleep", ["30"], timeout: 1)
        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.status, SIGTERM)
        XCTAssertLessThan(Date().timeIntervalSince(asked), 15)
    }

    func testAStopEndsIt() async throws {
        let running = Task { try await Run.program("/bin/sleep", ["30"]) }
        try await Task.sleep(nanoseconds: 500_000_000)
        let asked = Date()
        running.cancel()
        let result = try await running.value
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, SIGTERM)
        XCTAssertLessThan(Date().timeIntervalSince(asked), 15)
    }

    func testAProgramASignalEnded() async throws {
        let result = try await Run.program("/bin/sh", ["-c", "kill -KILL $$"])
        XCTAssertEqual(result.status, SIGKILL)
        XCTAssertFalse(result.succeeded)
    }

    func testAProgramThatIsNotThere() async {
        do {
            _ = try await Run.program("/nonexistent/cartouche-builder-tests")
            XCTFail("a program that is not there ran")
        } catch {
            let error = error as NSError
            XCTAssertEqual(error.domain, NSCocoaErrorDomain, "\(error)")
            XCTAssertEqual(error.code, NSFileNoSuchFileError, "\(error)")
        }
    }

    /// Ten thousand programs that end at once, eight at a time: each run
    /// ends, with what its program wrote and how it ended.
    func testThousandsOfProgramsEachSeenToEnd() {
        let wrong = Locked<[String]>([])
        let unended = stress(10_000, timeout: 240) { index in
            let fails = index % 3 == 0
            do {
                let result = try await Run.program(fails ? "/usr/bin/false" : "/bin/echo", fails ? [] : ["\(index)"])
                if result.status != (fails ? 1 : 0) || result.text != (fails ? "" : "\(index)\n") || result.timedOut {
                    wrong.update { $0.append("\(index): \(result.status) \(result.text.debugDescription)") }
                }
            } catch {
                wrong.update { $0.append("\(index): \(error)") }
            }
        }
        XCTAssertEqual(unended, [], "runs that never ended")
        XCTAssertEqual(wrong.current, [])
    }

    /// Runs ONE for each of COUNT indexes, eight at a time, off the test's
    /// thread, and waits TIMEOUT at most for them all: a run that never ends
    /// fails the test rather than holding the tests for good. The indexes of
    /// the runs that had not ended.
    private func stress(_ count: Int, timeout: TimeInterval, _ one: @escaping @Sendable (Int) async -> Void) -> [Int] {
        let ended = expectation(description: "\(count) runs ended")
        ended.expectedFulfillmentCount = count
        let running = Locked<Set<Int>>([])
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<count {
                    if index >= 8 { await group.next() }
                    running.update { $0.insert(index) }
                    group.addTask {
                        await one(index)
                        running.update { $0.remove(index) }
                        ended.fulfill()
                    }
                }
            }
        }
        wait(for: [ended], timeout: timeout)
        return running.current.sorted()
    }
}

/// What the threads of a test found, under a lock.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func update(_ change: (inout Value) -> Void) {
        lock.lock()
        change(&value)
        lock.unlock()
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
