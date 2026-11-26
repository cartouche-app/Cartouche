//
//  Run.swift
//  Cartouche Builder
//
//  Runs a program and collects what it writes, out of sight: the engine's
//  commands, Xcode's, Homebrew's. The lines of its error output can be
//  followed as they come, for the progress the app shows.
//
//  The program is started with posix_spawn and waited for with waitpid,
//  not with Foundation's Process: Process.waitUntilExit once waited for good
//  for a program whose output and errors had ended (the Builder's Mac tests
//  on CI, 15 November, run 43711191427), where waitpid returns as soon as
//  the program has ended, whatever else saw it end.
//

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct RunResult: Sendable {
    public var status: Int32
    public var output: Data
    public var errors: Data
    public var timedOut: Bool
    /// It was stopped because the task that ran it was cancelled, a page's
    /// that went away: what it said is not how it ends by itself.
    public var stopped: Bool

    public init(status: Int32, output: Data = Data(), errors: Data = Data(), timedOut: Bool = false, stopped: Bool = false) {
        self.status = status
        self.output = output
        self.errors = errors
        self.timedOut = timedOut
        self.stopped = stopped
    }

    public var succeeded: Bool { status == 0 && !timedOut }
    public var text: String { String(decoding: output, as: UTF8.self) }
    public var errorText: String { String(decoding: errors, as: UTF8.self) }

    /// The last lines it wrote, error output first, for a message.
    public func tail(_ count: Int = 6) -> String {
        let source = errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : errorText
        let lines = source.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(count).joined(separator: "\n")
    }
}

public enum Run {
    /// Where programs are looked for: Homebrew's folders and the system's,
    /// since an app opened from the Finder has almost no PATH.
    public static let searchPath = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// This process's environment, with the PATH above, and EXTRA.
    public static func environment(_ extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var path = searchPath
        for part in (environment["PATH"] ?? "").split(separator: ":").map(String.init) where !part.isEmpty && !path.contains(part) {
            path.append(part)
        }
        environment["PATH"] = path.joined(separator: ":")
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        for (key, value) in extra {
            environment[key] = value
        }
        return environment
    }

    /// The first of NAMES found in the PATH above, or nil.
    public static func which(_ names: String...) -> String? {
        for name in names {
            for folder in environment()["PATH", default: ""].split(separator: ":") {
                let path = "\(folder)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// What gets each line of a program's output as it comes. A type of its
    /// own, not a closure, so that a trailing closure stays the error
    /// output's LINE.
    public struct Lines: Sendable {
        let each: @Sendable (String) -> Void

        public init(_ each: @escaping @Sendable (String) -> Void) {
            self.each = each
        }
    }

    /// Runs EXECUTABLE with ARGUMENTS and waits for it; OUTPUT gets each line
    /// of its output as it comes, LINE each of its error output. It is
    /// stopped after TIMEOUT, or when the task is cancelled.
    public static func program(_ executable: String, _ arguments: [String] = [], environment: [String: String]? = nil,
                               directory: URL? = nil, timeout: TimeInterval? = nil, output: Lines? = nil,
                               line: (@Sendable (String) -> Void)? = nil) async throws -> RunResult {
        let collected = Collected()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RunResult, Error>) in
                let child: Child
                do {
                    child = try Child(executable, arguments, environment: environment ?? Run.environment(), directory: directory)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                collected.started(child.pid)
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    var pending = Data()
                    drain(child.output) { chunk in
                        collected.appendOutput(chunk)
                        guard let output else { return }
                        pending.append(chunk)
                        while let end = pending.firstIndex(of: 10) {
                            let text = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
                            pending.removeSubrange(pending.startIndex...end)
                            if !text.isEmpty { output.each(text) }
                        }
                    }
                    if let output, !pending.isEmpty { output.each(String(decoding: pending, as: UTF8.self)) }
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    var pending = Data()
                    drain(child.errors) { chunk in
                        collected.appendErrors(chunk)
                        guard let line else { return }
                        pending.append(chunk)
                        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                            let text = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
                            pending.removeSubrange(pending.startIndex...end)
                            if !text.trimmingCharacters(in: .whitespaces).isEmpty { line(text) }
                        }
                    }
                    if let line, !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
                    group.leave()
                }
                // Its end, from the kernel, which waitpid hears of at once.
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    var status: Int32 = 0
                    var waited: pid_t
                    repeat {
                        waited = waitpid(child.pid, &status, 0)
                    } while waited == -1 && errno == EINTR
                    collected.ended(waited == child.pid ? Run.status(status) : -1)
                    group.leave()
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        collected.stop(timedOut: true)
                    }
                }
                group.notify(queue: .global(qos: .utility)) {
                    continuation.resume(returning: collected.result())
                }
            }
        } onCancel: {
            collected.stop(timedOut: false)
        }
    }

    /// How a program ended, from what waitpid says of it, as Process said
    /// it: its exit status, or the signal that ended it.
    static func status(_ waited: Int32) -> Int32 {
        let signal = waited & 0x7f
        return signal == 0 ? (waited >> 8) & 0xff : signal
    }

    /// The error of a program that could not start: for one that is not
    /// there, the error Process gave.
    static func failure(_ code: Int32, _ path: String) -> Error {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        guard code == ENOENT else { return underlying }
        return NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                       userInfo: [NSFilePathErrorKey: path, NSUnderlyingErrorKey: underlying])
    }

    /// Reads FD to its end, CHUNK getting each piece as it comes, then closes it.
    private static func drain(_ fd: Int32, _ chunk: (Data) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                chunk(Data(buffer[0..<count]))
            } else if count == 0 || errno != EINTR {
                break
            }
        }
        close(fd)
    }
}

/// A program started: its process, and the app's ends of the pipes it
/// writes its output and its errors to.
private struct Child {
    let pid: pid_t
    let output: Int32
    let errors: Int32

    /// Starts EXECUTABLE as Process did: its input empty, none of the app's
    /// files open in it, in a process group of its own, its signals as they
    /// are when a program starts (a thread of Dispatch, where this runs,
    /// blocks them, and a program started there would not hear a Stop).
    init(_ executable: String, _ arguments: [String], environment: [String: String], directory: URL?) throws {
        let path = URL(fileURLWithPath: executable).path
        if let directory, !FileManager.default.fileExists(atPath: directory.path) {
            throw Run.failure(ENOENT, directory.path)
        }
        func check(_ code: Int32) throws {
            if code != 0 { throw Run.failure(code, path) }
        }
        var output: [Int32] = [-1, -1]
        var errors: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { throw Run.failure(errno, path) }
        guard pipe(&errors) == 0 else {
            let code = errno
            close(output[0])
            close(output[1])
            throw Run.failure(code, path)
        }
        for fd in output + errors {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        }
        // The program's ends, closed here once it has them: the end of what
        // it writes is its end, and its children's.
        defer {
            close(output[1])
            close(errors[1])
        }
        var started = false
        defer {
            if !started {
                close(output[0])
                close(errors[0])
            }
        }

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, output[1], 1))
        try check(posix_spawn_file_actions_adddup2(&actions, errors[1], 2))
        if let directory {
            #if canImport(Darwin)
            try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
            #else
            try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
            #endif
        }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        var none = sigset_t()
        sigemptyset(&none)
        try check(posix_spawnattr_setsigmask(&attributes, &none))
        var most = sigset_t()
        #if canImport(Darwin)
        sigfillset(&most)
        sigdelset(&most, SIGKILL)
        sigdelset(&most, SIGSTOP)
        #else
        // Linux takes only the signals a program may change.
        sigemptyset(&most)
        for signal in 1..<SIGSYS where signal != SIGKILL && signal != SIGSTOP {
            sigaddset(&most, signal)
        }
        #endif
        try check(posix_spawnattr_setsigdefault(&attributes, &most))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP
        #if canImport(Darwin)
        // Only what the actions above open: 0, 1 and 2.
        flags |= POSIX_SPAWN_CLOEXEC_DEFAULT
        #endif
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)))

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        try check(posix_spawn(&pid, path, &actions, &attributes, argv, envp))
        started = true
        self.pid = pid
        self.output = output[0]
        self.errors = errors[0]
    }
}

/// What a running program wrote and how it ended, from the threads that
/// follow it, and what stops it.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var errors = Data()
    private var pid: pid_t?
    private var status: Int32 = 0
    private var reaped = false
    private var timedOut = false
    private var stopped = false
    private var stopAsked = false

    func appendOutput(_ data: Data) {
        lock.lock()
        output.append(data)
        lock.unlock()
    }

    func appendErrors(_ data: Data) {
        lock.lock()
        errors.append(data)
        lock.unlock()
    }

    func started(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        self.pid = pid
        if stopAsked {
            stopped = true
            kill(pid, SIGTERM)
        }
    }

    /// The program ended with STATUS, and waitpid reaped it: its number is
    /// sent nothing more (it is given to no other process for long after:
    /// numbers are given in turn).
    func ended(_ status: Int32) {
        lock.lock()
        defer { lock.unlock() }
        self.status = status
        reaped = true
    }

    /// Asks the program to end, as Process.terminate did.
    func stop(timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        stopAsked = true
        guard let pid, !reaped else { return }
        if timedOut { self.timedOut = true } else { stopped = true }
        kill(pid, SIGTERM)
    }

    func result() -> RunResult {
        lock.lock()
        defer { lock.unlock() }
        return RunResult(status: status, output: output, errors: errors, timedOut: timedOut, stopped: stopped && !timedOut)
    }
}
