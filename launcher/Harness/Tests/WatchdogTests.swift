//
//  WatchdogTests.swift
//  CartoucheHarnessTests
//
//  The watchdog of every test of the harness (HarnessCase): it sees the
//  main thread held, and says where, all its frames; the time the main
//  thread waits for RunningBoard's answer does not count (HarnessWait).
//  UprightTests failed once on a wait of 4.17 s, all of it but its first
//  second unseen, with 30 frames that stopped short of the launcher's, the
//  main thread waiting for RunningBoard as UIKit told the keyboard's process
//  of a new key window, on a busy Mac of the CI's; green when run again
//  (run 43673497623).
//

import Foundation
import XCTest

@MainActor
final class WatchdogTests: XCTestCase {
    /// The main thread of run 43673497623, a second into its wait, the
    /// innermost frame first, as the watchdog said it then.
    private static let keyWindowChange = [
        "libsystem_kernel.dylib mach_msg2_trap",
        "libsystem_kernel.dylib mach_msg2_internal",
        "libsystem_kernel.dylib mach_msg_overwrite",
        "libsystem_kernel.dylib mach_msg",
        "libdispatch.dylib _dispatch_mach_send_and_wait_for_reply",
        "libdispatch.dylib dispatch_mach_send_with_result_and_wait_for_reply",
        "libxpc.dylib xpc_connection_send_message_with_reply_sync",
        "RunningBoardServices -[RBSXPCMessage sendToConnection:error:]",
        "RunningBoardServices -[RBSXPCMessage invokeOnConnection:withReturnCollectionClass:entryClass:error:]",
        "RunningBoardServices -[RBSXPCMessage invokeOnConnection:withReturnClass:error:]",
        "RunningBoardServices -[RBSConnection acquireAssertion:error:]",
        "RunningBoardServices -[RBSAssertion acquireWithError:]",
        "BoardServices -[BSNSXPCTransport _newAcquiredAssertionWithAttributes:]",
        "BoardServices -[BSNSXPCTransport _newMessageSessionWithReason:]",
        "BoardServices -[BSNSXPCTransport _sendMessage:asNotification:]",
        "BoardServices -[BSNSXPCTransport sendMessage:]",
        "Foundation -[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:]",
        "Foundation -[NSXPCConnection _sendSelector:withProxy:arg1:]",
        "Foundation _NSXPCDistantObjectSimpleMessageSend1",
        "UIKitCore -[_UIRemoteKeyboards _performRequiredSceneUpdateIfPermittedForWindow:withContext:]",
        "UIKitCore -[_UIRemoteKeyboards applicationKeyWindowDidChange:]",
        "CoreFoundation __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__",
        "CoreFoundation ___CFXRegistrationPost_block_invoke",
        "CoreFoundation _CFXRegistrationPost",
        "CoreFoundation _CFXNotificationPost",
        "Foundation -[NSNotificationCenter postNotificationName:object:userInfo:]",
        "UIKitCore -[_UIKeyWindowEvaluator _evaluateApplicationKeyWindowWithComparisonWindowScene:changingKeyWindowSceneActions:sceneKeyWindowActions:ignoringOldKeyWindow:sceneResignKeyWindowActions:andSceneBecomeKeyWindowActions:forReason:]",
        "UIKitCore -[_UIKeyWindowEvaluator evaluateApplicationKeyWindowForWindowScene:withWindowMadeKey:sceneKeyWindowActions:ignoringOldKeyWindow:sceneResignKeyWindowActions:andSceneBecomeKeyWindowActions:forReason:]",
        "UIKitCore -[UIWindowScene _evaluateSceneKeyWindowForWindowMadeKey:consideringVisibility:findingNewKeyWindowIfNeeded:ignoringOldKeyWindow:forReason:]",
        "UIKitCore -[UIWindowScene _pushKeyWindow:ignoringOldKeyWindow:]",
    ]

    /// The main thread at the launcher's own work, deeper than the 30
    /// frames the watchdog used to say.
    private static let launcherWork = ["libsystem_kernel.dylib __semwait_signal", "libsystem_c.dylib nanosleep",
                                       "Foundation +[NSThread sleepForTimeInterval:]"]
        + (1...40).map { "CartoucheHarness the launcher's frame \($0)" }

    /// Held on purpose, as the launcher's own work would hold it: the
    /// watchdog counts it all, and says where the main thread was. It looks
    /// at it again and again from a fifth of a second in, a tenth of a
    /// second apart at least: as often as the Mac lets it, which on a busy
    /// Mac of the CI's was 4 times in that second, not 8, each look taking a
    /// tenth of a second more (run 43755471628). Its question can reach the
    /// main thread after the hold began, later on such a Mac.
    func testTheMainThreadHeldCounts() async throws {
        let watchdog = HarnessWatchdog()
        watchdog.start()
        try await Task.sleep(for: .milliseconds(300))
        holdTheMainThread(for: 1)
        // The watchdog's question answered, once the main thread goes on.
        try await Task.sleep(for: .milliseconds(300))
        let worst = watchdog.stop()
        XCTAssertGreaterThan(worst.longest.counted, 0.5)
        XCTAssertEqual(worst.longest.forRunningBoard, 0)
        let times = worst.longest.looks.map(\.at)
        XCTAssertGreaterThanOrEqual(times.count, 2, "looked at more than once: \(times)")
        XCTAssertGreaterThanOrEqual(times.first ?? 0, HarnessWait.lookFrom - 0.01, "from a fifth of a second in: \(times)")
        for (earlier, later) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, HarnessWait.lookEvery - 0.01, "a tenth of a second apart at least: \(times)")
        }
        #if arch(arm64)
        XCTAssertTrue(worst.longest.failure.contains("sleep"), worst.longest.failure)
        #endif
    }

    /// Its thread runs as urgently as the main thread it watches: at the
    /// default urgency, a busy Mac of the CI's let it look once, then not
    /// at all, while testTheMainThreadHeldCounts held the main thread
    /// (run 45684262541).
    func testTheWatchdogRunsAsUrgentlyAsTheMainThread() async throws {
        XCTAssertEqual(HarnessWatchdog.urgency, .userInteractive)
        let watchdog = HarnessWatchdog()
        watchdog.start()
        var waited = 0
        while watchdog.urgencyItRanAs == nil, waited < 50 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        _ = watchdog.stop()
        XCTAssertEqual(watchdog.urgencyItRanAs, HarnessWatchdog.urgency)
    }

    /// Once the main queue has answered, the time the watchdog spends
    /// reading the current step belongs to the harness.
    func testTheWatchdogsOwnStepReadDoesNotCount() async {
        let next = expectation(description: "The watchdog finished timing its first probe")
        let reads = HarnessBox(0)
        let watchdog = HarnessWatchdog()
        watchdog.start {
            reads.value += 1
            if reads.value == 1 { Thread.sleep(forTimeInterval: 2) }
            if reads.value == 2 { next.fulfill() }
            return "test step"
        }
        await fulfillment(of: [next], timeout: 15)
        let worst = watchdog.stop()
        XCTAssertLessThan(worst.longest.counted, 1.5, worst.longest.failure)
    }

    /// The wait of run 43673497623, as the watchdog looks at it now, the
    /// main thread waiting for RunningBoard each time: only its first fifth
    /// of a second counts, before the first look, and the log says the rest
    /// with all the frames.
    func testTheTimeTheMainThreadWaitsForRunningBoardDoesNotCount() {
        let wait = HarnessWait(seconds: 4.17, from: "no step under way", to: "no step under way",
                               looks: looks(from: 0.2, to: 4.17, Self.keyWindowChange))
        XCTAssertEqual(wait.forRunningBoard, 3.97, accuracy: 0.001)
        XCTAssertEqual(wait.counted, 0.2, accuracy: 0.001)
        XCTAssertLessThan(wait.counted, 1.5, "within HarnessCase's mainThreadLimit")
        XCTAssertTrue(wait.waitedForRunningBoard.hasPrefix("the main thread waited 3.97 s for RunningBoard, not counted"),
                      wait.waitedForRunningBoard)
        XCTAssertTrue(wait.waitedForRunningBoard.hasSuffix("0.2 s in, it was in: " + Self.keyWindowChange.joined(separator: " < ")),
                      wait.waitedForRunningBoard)
    }

    /// RunningBoard first, then the launcher's own work: that counts, and
    /// the failure says where the main thread was then, all its frames.
    func testTheRestOfAWaitCounts() {
        let wait = HarnessWait(seconds: 3, from: "install unpacking", to: "install signing",
                               looks: looks(from: 0.2, to: 1, Self.keyWindowChange) + looks(from: 1, to: 3, Self.launcherWork))
        XCTAssertEqual(wait.forRunningBoard, 0.8, accuracy: 0.001)
        XCTAssertEqual(wait.counted, 2.2, accuracy: 0.001)
        XCTAssertGreaterThan(wait.counted, 1.5, "beyond HarnessCase's mainThreadLimit")
        XCTAssertEqual(wait.failure, "The main thread was held up 2.20 s, from install unpacking to install signing "
                       + "(and 0.80 s waiting for RunningBoard, not counted); 1.0 s in, it was in: "
                       + Self.launcherWork.joined(separator: " < "))
        // Held without a look at it, on a Mac where the harness cannot read
        // the frames: it all counts.
        let unseen = HarnessWait(seconds: 2, from: "no step under way", to: "no step under way",
                                 looks: looks(from: 0.2, to: 2, []))
        XCTAssertEqual(unseen.counted, 2, accuracy: 0.001)
        XCTAssertTrue(unseen.failure.hasSuffix("; no look at where it was"), unseen.failure)
    }

    /// Only a message that RunningBoardServices sent, and waits for the reply
    /// to, is a wait for RunningBoard.
    func testWhatAWaitForRunningBoardIs() {
        XCTAssertTrue(HarnessWait.waitsForRunningBoard(Self.keyWindowChange))
        XCTAssertFalse(HarnessWait.waitsForRunningBoard(Self.launcherWork))
        XCTAssertFalse(HarnessWait.waitsForRunningBoard([]))
        // Another daemon's answer, as a file provider's, which the first
        // bookmark of a folder waits for.
        XCTAssertFalse(HarnessWait.waitsForRunningBoard([
            "libsystem_kernel.dylib mach_msg2_trap",
            "libxpc.dylib xpc_connection_send_message_with_reply_sync",
            "Foundation __NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__",
            "Foundation -[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:]",
            "FileProvider -[NSURL(FPAdditions) fp_bookmarkData]",
        ]))
        // RunningBoardServices at work, not waiting for an answer.
        XCTAssertFalse(HarnessWait.waitsForRunningBoard([
            "RunningBoardServices -[RBSProcessHandle currentState]",
            "CartoucheHarness the launcher's frame 1",
        ]))
    }

    /// Holds the main thread SECONDS, as the launcher's own work would: a
    /// sleep, which a test of HarnessCase never does.
    private func holdTheMainThread(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Looks at STACK ten times a second, from FROM until before TO.
    private func looks(from: TimeInterval, to: TimeInterval, _ stack: [String]) -> [HarnessWait.Look] {
        stride(from: from, to: to - 0.0001, by: HarnessWait.lookEvery).map { HarnessWait.Look(at: $0, stack: stack) }
    }
}
