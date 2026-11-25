//
//  SharedRun.swift
//  Cartouche Builder
//
//  One run of a long operation at a time, which every caller waits for and
//  none stops. SwiftUI cancels a page's .task when the page goes away, or is
//  made anew; the Storage page measured the builder's folders in its own,
//  and its cancellation stopped the engine with SIGTERM: the player read
//  "exit 15", and the page, whose next .task found the measurement still
//  marked under way, measured nothing more (a player's Mac whose build
//  folders were on a NAS, a measurement of minutes, 25 November). Run here,
//  the operation goes on to its end whatever becomes of the page that asked
//  for it, and what it found is kept.
//

import Foundation

@MainActor
public final class SharedRun<Value: Sendable> {
    private var running: Task<Value, Never>?

    public init() {}

    /// Whether the operation runs now.
    public var isRunning: Bool { running != nil }

    /// What OPERATION gives: the run under way's, when there is one, else a
    /// run of its own. A caller whose task is cancelled stops nothing: the
    /// run goes on, for the next caller as for those still waiting.
    @discardableResult
    public func run(_ operation: @escaping @MainActor () async -> Value) async -> Value {
        if let running { return await running.value }
        let task = Task { @MainActor [weak self] () -> Value in
            let value = await operation()
            self?.running = nil
            return value
        }
        running = task
        return await task.value
    }
}
