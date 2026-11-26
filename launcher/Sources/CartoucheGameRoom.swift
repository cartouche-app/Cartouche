//
//  CartoucheGameRoom.swift
//  Cartouche
//
//  The room a game's memory takes on the iPhone's disk. When a game's
//  memory pool and the host's margin do not fit under the memory limit,
//  nxnative keeps the game's memory in files (DM_GUEST_FILE, hle_svc.c),
//  which take up to the pool on the disk as the game touches its memory. It
//  stops the game, with exit code 87, once the room left there, what is
//  free less what the dirty pages may still take, falls under 2 GB
//  (DM_GUEST_FILE_MIN_FREE), or under half of it on its own, even when iOS
//  counts much more as available: the system purges what it could free
//  only once the disk is nearly full, too late for the game.
//
//  So on an iPhone with a few GB free and tens of GB that iOS could purge,
//  a game stopped within seconds, start after start, and Cartouche said
//  only that it had closed on its own (a problem report of 26 November
//  2026). Here, what the game's log says of it: its memory in files and its
//  pool, from the start of the log, which Cartouche checks the free space
//  against before the next start (docs/decisions/169.md), and the stop, at
//  its end, which the notice and the session's measures tell
//  (CartoucheGameLogReader).
//
//  nxnative writes its sizes in GB of 2^30 bytes. Platform-independent:
//  tested on its own by launcher/Package.swift.
//

import Foundation

public enum CartoucheGameRoom {
    /// nxnative's own minimum when DM_GUEST_FILE_MIN_FREE is not set.
    public static let defaultMinimumBytes: Int64 = 2 << 30
    /// The start of a log that tells how the game keeps its memory: its
    /// first hundred lines or so.
    static let headBytes = 64 << 10
    /// The end of a log that tells why the game stopped.
    static let tailBytes = 16 << 10

    /// What the start of a game's log says: its memory went in files.
    public struct Files: Equatable, Sendable {
        /// The game's memory pool, in bytes: about the most its files take.
        public var poolBytes: Int64
        /// The room under which nxnative stops the game.
        public var minimumBytes: Int64

        /// The free space the game may need while it plays.
        public var neededBytes: Int64 { poolBytes + minimumBytes }
    }

    /// nxnative stopped the game: the room left on the disk of its memory's
    /// files ran out.
    public struct Stop: Equatable, Sendable {
        /// What was free on the disk, without what iOS could purge.
        public var freeBytes: Int64
        /// What iOS counted as available, with what it could purge; nil
        /// when nxnative could not read it.
        public var availableBytes: Int64?
        /// The room under which nxnative stopped it.
        public var minimumBytes: Int64
    }

    /// Whether the log's line is nxnative's stop for lack of room.
    public static func isStop(_ line: String) -> Bool {
        line.contains("guest file: ") && line.contains("stopping the game")
    }

    /// From TEXT, the start of a log: the game's memory in files, with its
    /// pool; nil for a game whose memory stayed in the process, or a log
    /// that does not say.
    public static func files(inLog text: String) -> Files? {
        var pool: Double?
        var mapped = false
        var minimum: Double?
        for line in text.split(whereSeparator: \.isNewline) {
            let line = String(line)
            if let groups = groups(poolLine, line) {
                pool = number(groups[0])
            } else if groups(filesLine, line) != nil {
                mapped = true
            } else if let groups = groups(warningLine, line) {
                minimum = number(groups[0])
            }
        }
        guard mapped, let pool, pool > 0 else { return nil }
        return Files(poolBytes: bytes(pool), minimumBytes: minimum.map(bytes) ?? defaultMinimumBytes)
    }

    /// From TEXT, the end of a log: nxnative's stop for lack of room, its
    /// last one; nil when the game ended otherwise.
    public static func stop(inLog text: String) -> Stop? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let line = String(line)
            guard isStop(line) else { continue }
            guard let groups = groups(stopLine, line), let free = number(groups[0]) else { return nil }
            let available = number(groups[1]).flatMap { $0 > 0 ? bytes($0) : nil }
            let minimum = number(groups[2]).map(bytes) ?? defaultMinimumBytes
            return Stop(freeBytes: bytes(free), availableBytes: available, minimumBytes: minimum)
        }
        return nil
    }

    /// The memory in files the log at URL says the game had, from its start.
    public static func files(ofLog url: URL) -> Files? {
        read(url, fromEnd: false).flatMap(files(inLog:))
    }

    /// nxnative's stop for lack of room the log at URL ends on.
    public static func stop(ofLog url: URL) -> Stop? {
        read(url, fromEnd: true).flatMap(stop(inLog:))
    }

    /// Whether FREE, the bytes free on the iPhone now without what iOS could
    /// purge, is short of what a game whose memory went in FILES may need.
    public static func isShort(_ free: Int64, for files: Files) -> Bool {
        free < files.neededBytes
    }

    /// Whether AVAILABLE, what iOS counts with what it could purge, is
    /// enough above FREE for the player to wonder why: then the notice says
    /// that iOS frees the rest too late.
    public static func countsPurgeable(free: Int64, available: Int64?) -> Bool {
        guard let available else { return false }
        return available > free + (1 << 30)
    }

    // MARK: Reading

    private static func read(_ url: URL, fromEnd: Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data: Data?
        if fromEnd {
            let end = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0)
            data = try? handle.readToEnd()
        } else {
            data = try? handle.read(upToCount: headBytes)
        }
        return data.map { String(decoding: $0, as: UTF8.self) }
    }

    private static func bytes(_ gigabytes: Double) -> Int64 {
        Int64((gigabytes * 1_073_741_824).rounded())
    }

    private static func number(_ text: String) -> Double? {
        Double(text).flatMap { $0.isFinite ? $0 : nil }
    }

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants: one that does not compile fails every test.
        try! NSRegularExpression(pattern: pattern)
    }

    /// guest_file_init, on iOS: why the memory goes in files.
    private static let poolLine = expression(
        #"\[mem\] guest memory: memory pool ([0-9.]+) GB and the host's margin [0-9.]+ GB .*: in files"#)
    /// guest_file_init, once the files are mapped.
    private static let filesLine = expression(#"\[mem\] guest memory: [0-9]+ files? of [0-9.]+ GB in .*\(unlinked, sparse, shared\)"#)
    /// guest_file_init, when the files may not fit: its minimum.
    private static let warningLine = expression(#"guest file: the files may take up to the memory pool, .*the game is stopped if under ([0-9.]+) GB is left"#)
    /// guest_file_thread, as it stops the game.
    private static let stopLine = expression(
        #"guest file: ([0-9.]+) GB free on its disk \((-?[0-9.]+) with what the system can purge\), -?[0-9.]+ GB of it still to be taken by dirty pages: under ([0-9.]+) GB left, stopping the game"#)

    private static func groups(_ expression: NSRegularExpression, _ line: String) -> [String]? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
        }
    }
}
