//
//  CartoucheSideStoreLaunch.swift
//  Cartouche
//
//  The wait for the built-in SideStore to say it has launched in LiveProcess,
//  before LiveContainer's bridge (SideStoreSupport/SideStore.swift,
//  RefreshHandler) hands it an action: a sign-in, a renewal or an update.
//  Each launch's wait ends once, with the first of: SideStore saying it has
//  launched, its process quitting, or the time it has running out, whether
//  that comes before or after the bridge starts waiting
//  (app/patches/livecontainer/0016). The bridge's own wait was forgotten
//  when the process quit as it launched: the action then waited forever,
//  and Cartouche showed it under way, with no error.
//
//  This file joins LiveContainer's SideStoreSupport framework, as
//  CartoucheSignIn.swift does.
//

import Foundation

final class CartoucheSideStoreLaunch: @unchecked Sendable {
    private let lock = NSLock()
    /// The latest launch's number; 0 before the first.
    private var launch = 0
    /// How the latest launch's wait ended, once it has.
    private var ended: Result<Void, Error>?
    /// The bridge, waiting for the latest launch.
    private var waiting: UnsafeContinuation<Void, Error>?

    /// Whether a launch has begun whose wait has not ended.
    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return launch > 0 && ended == nil
    }

    /// A new launch, whose number tells what ends its wait from what ends an
    /// earlier one's. A wait still under way for an earlier launch ends.
    func begin() -> Int {
        lock.lock()
        launch += 1
        ended = nil
        let earlier = waiting
        waiting = nil
        let number = launch
        lock.unlock()
        earlier?.resume(throwing: CancellationError())
        return number
    }

    /// Returns once launch NUMBER's SideStore said it has launched, and
    /// throws why it did not: at once when its wait has already ended.
    func wait(for number: Int) async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
            lock.lock()
            guard number == launch, let result = ended else {
                if number == launch, waiting == nil {
                    waiting = continuation
                    lock.unlock()
                } else {
                    // A later launch began, or someone already waits.
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                }
                return
            }
            lock.unlock()
            continuation.resume(with: result)
        }
    }

    /// Ends the wait of launch NUMBER, or of the latest launch when nil,
    /// with RESULT, unless it has ended already or a later launch began.
    /// Returns whether this ended it.
    @discardableResult
    func end(_ number: Int? = nil, with result: Result<Void, Error>) -> Bool {
        lock.lock()
        guard launch > 0, number == nil || number == launch, ended == nil else {
            lock.unlock()
            return false
        }
        ended = result
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(with: result)
        return true
    }
}
