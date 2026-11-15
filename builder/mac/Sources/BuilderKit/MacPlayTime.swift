//
//  MacPlayTime.swift
//  BuilderKit
//
//  How long the player plays each game on this Mac, counted as Cartouche
//  counts it in a game on the iPhone (launcher/Guest/CartouchePlayTimeCounter.m):
//  the time the game's app is the Mac's active app, added up in the game's
//  own folder of nxnative's, in Library/Cartouche/PlayTime.plist, which
//  Cartouche's console reads as the iPhone's reads a game's
//  (CartouchePlayTime.swift, in CartoucheCore). The builder counts while
//  it runs, whoever started the game: MacGames says when the game's app
//  comes to the front and when it leaves it, the Mac asleep or locked
//  counting as left. The total is written each time the game leaves the
//  front, and every 30 seconds while it is there, so that a game the
//  builder stops following loses half a minute at most. The clock is the
//  uptime, which stops while the Mac sleeps.
//  Platform-independent: Foundation only.
//

import CartoucheCore
import Foundation

/// One game's counter, for one run of it.
public final class MacPlayTime {
    /// How often the total is written while the game is in front, in
    /// seconds.
    public static let interval: TimeInterval = 30

    /// The counter's file.
    public let file: URL
    /// What the file holds, this run's time included: seconds, sessions,
    /// firstPlayed, lastPlayed, and lastSession, this run's own start and
    /// seconds.
    private var total: [String: Any]
    /// The uptime when the game came to the front; nil while it is not
    /// there.
    private var inFrontSince: TimeInterval?
    /// Whether this run counts in the sessions yet: it does once the game
    /// has been in front.
    private var sessionCounted = false
    private var sessionStart: Date?
    private var sessionSeconds: Double = 0
    private let clock: () -> TimeInterval
    private let now: () -> Date

    /// The counter of the game whose folder of nxnative's is FOLDER
    /// (~/Library/Application Support/nxnative/<title ID>). CLOCK gives the
    /// uptime, in seconds, NOW the date: the tests' own.
    public init(folder: URL, clock: @escaping () -> TimeInterval = MacPlayTime.uptime,
                now: @escaping () -> Date = Date.init) {
        file = folder.appendingPathComponent(CartouchePlayTime.file)
        self.clock = clock
        self.now = now
        var total: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let saved = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            total = saved
        }
        if Self.number(total["seconds"]) == nil { total["seconds"] = 0.0 }
        if Self.number(total["sessions"]) == nil { total["sessions"] = 0 }
        total["version"] = CartouchePlayTime.version
        self.total = total
    }

    /// The time since the Mac started, its sleep left out.
    public static func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Whether the game is counting: in front.
    public var isCounting: Bool { inFrontSince != nil }

    /// The game's app became the Mac's active app: it counts from now on.
    /// Its first time in front makes this run a session.
    public func cameToFront() {
        guard inFrontSince == nil else { return }
        inFrontSince = clock()
        guard !sessionCounted else { return }
        sessionCounted = true
        let start = now()
        sessionStart = start
        total["sessions"] = Int(Self.number(total["sessions"]) ?? 0) + 1
        if !(total["firstPlayed"] is Date) { total["firstPlayed"] = start }
        total["lastPlayed"] = start
        total["lastSession"] = ["start": start, "seconds": 0.0] as [String: Any]
        save()
    }

    /// The game left the front, or ended: its time so far goes in the file.
    public func leftFront() {
        add(stillInFront: false)
    }

    /// Every 30 seconds: the time so far goes in the file while the game is
    /// in front (INFRONT), up to now if it left it without a word; a game in
    /// front that nothing announced starts counting.
    public func tick(inFront: Bool) {
        guard inFrontSince != nil else {
            if inFront { cameToFront() }
            return
        }
        add(stillInFront: inFront)
    }

    /// Adds the time since the game came to the front to the total, and
    /// writes it; STILLINFRONT keeps counting from now on.
    private func add(stillInFront: Bool) {
        guard let since = inFrontSince else { return }
        let uptime = clock()
        let seconds = max(0, uptime - since)
        sessionSeconds += seconds
        total["seconds"] = (Self.number(total["seconds"]) ?? 0) + seconds
        total["lastPlayed"] = now()
        if let sessionStart {
            total["lastSession"] = ["start": sessionStart, "seconds": sessionSeconds] as [String: Any]
        }
        inFrontSince = stillInFront ? uptime : nil
        save()
    }

    private func save() {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: total, format: .binary, options: 0) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let value as Double: return value
        case let value as Int: return Double(value)
        default: return nil
        }
    }
}
