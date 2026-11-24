//
//  ConsoleTelemetry.swift
//  Cartouche on the Mac
//
//  Cartouche's game measurements on the Mac (CartoucheTelemetry.swift on
//  the iPhone): the console's side of the app's telemetry, which Cartouche
//  Builder keeps (BuilderTelemetry), so that the app has one switch, one
//  queue and one random number. System › Game measurements shows them as
//  the iPhone's System page does (CartoucheTelemetryView.swift, shared),
//  and the Builder's settings turn the same switch.
//
//  After each game played on this Mac, the console reads its session in
//  the log nxnative's app for the Mac writes, ~/Library/Logs/nxnative/
//  <title ID>.log, the run before kept as <title ID>.prev.log
//  (dm/mac/launcher.c), as Cartouche on the iPhone reads a game's log.txt:
//  the same lines (dm/gfx/nvn/hle_nvn.c is the same on both), the same
//  reader (CartoucheGameLog.swift), the same report (CartoucheSessionReport),
//  which the app sends with its own (telemetry/README.md#cartouche-builder).
//  The launcher's own last line says how the game ended, which an iPhone's
//  log never does. Never a line of the log, a path, a game's name or the
//  Mac's name: the report holds the reader's numbers, the game's title ID,
//  version and settings, and the nxnative commit it was built from.
//

import Combine
import Foundation

// MARK: What the app gives the console

/// What the app's telemetry says of itself, which System › Game
/// measurements shows.
public struct CartoucheMacMeasures: Equatable, Sendable {
    public var isOn: Bool
    public var sent: Int
    public var waiting: Int
    public var lastSent: Date?
    /// The last report made, as it is sent.
    public var lastReport: String?

    public init(isOn: Bool, sent: Int = 0, waiting: Int = 0, lastSent: Date? = nil, lastReport: String? = nil) {
        self.isOn = isOn
        self.sent = sent
        self.waiting = waiting
        self.lastSent = lastSent
        self.lastReport = lastReport
    }
}

/// What every report of this copy of the app carries, as its telemetry
/// has it: in a session's report, the fields the iPhone's have.
public struct CartoucheMacTelemetryContext: Equatable, Sendable {
    /// The random number of this copy of the app.
    public var install: String
    /// The app's version.
    public var version: String
    /// The Mac's model identifier, such as "Mac16,12".
    public var device: String
    /// macOS's version.
    public var system: String
    /// The language the app shows.
    public var language: String?

    public init(install: String, version: String, device: String, system: String, language: String? = nil) {
        self.install = install
        self.version = version
        self.device = device
        self.system = system
        self.language = language
    }
}

/// A value of an event's field: text, a number or a yes or no.
public enum CartoucheMacMeasure: Equatable, Sendable {
    case text(String)
    case number(Double)
    case flag(Bool)
}

/// A report the console made, which the app queues and sends: its random
/// number, and its JSON.
public struct CartoucheMacReport: Equatable, Sendable {
    public var id: String
    public var body: String

    public init(id: String, body: String) {
        self.id = id
        self.body = body
    }
}

extension CartoucheMacConsole {
    /// The server the app sends to, nil for a build that has none, which
    /// System › Game measurements then says.
    public static var measuresServer: URL? {
        get { CartoucheTelemetry.endpoint }
        set { CartoucheTelemetry.endpoint = newValue }
    }

    /// The app's telemetry as it is now, which System › Game measurements
    /// shows.
    public func showMeasures(_ measures: CartoucheMacMeasures) {
        CartoucheTelemetry.shared.show(measures)
    }

    /// The player's switch, on System › Game measurements.
    public var onMeasuresSwitch: (_ on: Bool) -> Void {
        get { CartoucheTelemetry.shared.onSwitch }
        set { CartoucheTelemetry.shared.onSwitch = newValue }
    }

    /// Has the server delete what this copy of the app sent: false when
    /// it could not be reached.
    public var onMeasuresErase: () async -> Bool {
        get { CartoucheTelemetry.shared.onErase }
        set { CartoucheTelemetry.shared.onErase = newValue }
    }

    /// An event of the console's screens, under the name the iPhone's
    /// Cartouche gives it (game.infoChanged), the title ID of its game.
    public var onMeasuresEvent: (_ name: String, _ game: String?, _ fields: [String: CartoucheMacMeasure]) -> Void {
        get { CartoucheTelemetry.shared.onEvent }
        set { CartoucheTelemetry.shared.onEvent = newValue }
    }

    /// A session's report to queue: the app calls MAKE with this copy's
    /// context and the report's number, if the player has telemetry on and
    /// the app a server, and queues what it gives.
    public var onMeasuresReport: (_ make: (CartoucheMacTelemetryContext, Int) -> CartoucheMacReport?) -> Void {
        get { CartoucheTelemetry.shared.onReport }
        set { CartoucheTelemetry.shared.onReport = newValue }
    }

    /// Keeps in FILE which of the games' logs the console read (the
    /// Builder's folder), those of LOGS, nxnative's folder of them unless
    /// a test gives another: once, as the app starts. The first time, the
    /// logs already there are of games played before this version, and
    /// only those after it are reported.
    public func keepSessions(in file: URL, logs: URL? = nil) {
        CartoucheMacSessions.shared.keep(in: file, logs: logs ?? CartoucheMacSessions.nxnativeLogs)
    }

    /// Reads the sessions of the games' logs not read yet, and has the app
    /// send their reports: as the app starts, and after a game. PLAYING,
    /// the title IDs of the games playing, which are still writing theirs.
    public func readSessions(playing: Set<String>) {
        CartoucheMacSessions.shared.collect(playing: playing)
    }
}

// MARK: The iPhone's names

/// Cartouche's measurements, as the console's screens know them on the
/// iPhone (CartoucheTelemetry.swift): here, what the app's telemetry
/// says, and what the player asks of it.
@MainActor
final class CartoucheTelemetry: ObservableObject {
    static let shared = CartoucheTelemetry()

    /// The server the app sends to, nil for a build that has none.
    static var endpoint: URL?
    /// Where the docs say what leaves the Mac.
    static let privacyURL = URL(string: "https://github.com/cartouche-app/Cartouche/blob/main/docs/privacy.md#cartouche-builder")!

    @Published private(set) var isOn = true
    @Published private(set) var sent = 0
    @Published private(set) var waiting = 0
    @Published private(set) var lastSent: Date?
    @Published private(set) var lastReport: String?
    @Published private(set) var isErasing = false

    var onSwitch: (Bool) -> Void = { _ in }
    var onErase: () async -> Bool = { false }
    var onEvent: (String, String?, [String: CartoucheMacMeasure]) -> Void = { _, _, _ in }
    var onReport: ((CartoucheMacTelemetryContext, Int) -> CartoucheMacReport?) -> Void = { _ in }
    private var reports: AnyCancellable?

    init() {
        // Each error the console shows, with its report, as the iPhone's
        // Cartouche sends it (CartoucheTelemetry.noteError): an error
        // event, its origin, cause and codes, never its words. Reports are
        // posted on the main thread.
        reports = NotificationCenter.default.publisher(for: CartoucheReports.reported)
            .sink { [weak self] note in self?.event("error", fields: CartoucheErrorEvent.fields(of: note.userInfo)) }
    }

    func show(_ measures: CartoucheMacMeasures) {
        if isOn != measures.isOn {
            // On again from the Builder's settings: only the sessions after
            // it are reported, as from System › Game measurements.
            if measures.isOn { CartoucheMacSessions.shared.collect(playing: CartoucheMacSessions.shared.playing, reporting: false) }
            isOn = measures.isOn
        }
        if sent != measures.sent { sent = measures.sent }
        if waiting != measures.waiting { waiting = measures.waiting }
        if lastSent != measures.lastSent { lastSent = measures.lastSent }
        if lastReport != measures.lastReport { lastReport = measures.lastReport }
    }

    /// The player's switch. On again, only the sessions after it are
    /// reported, as on the iPhone.
    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on { CartoucheMacSessions.shared.collect(playing: CartoucheMacSessions.shared.playing, reporting: false) }
        isOn = on
        onSwitch(on)
    }

    /// Has the server delete every report of this copy of the app, which
    /// then takes a new number. False if the server could not be reached.
    func erase() async -> Bool {
        guard !isErasing else { return false }
        isErasing = true
        defer { isErasing = false }
        return await onErase()
    }

    /// An event of the console's screens: the app keeps it, with telemetry
    /// on, and sends it.
    func event(_ name: String, game: String? = nil, fields: [String: CartoucheTelemetryValue] = [:]) {
        guard isOn else { return }
        onEvent(name, game, fields.mapValues { value in
            switch value {
            case .text(let text): return .text(text)
            case .number(let number): return .number(number)
            case .flag(let flag): return .flag(flag)
            }
        })
    }

    /// Has the app queue REPORT, if the player has telemetry on and the app
    /// a server, with this copy's context and its number.
    func report(_ make: (CartoucheTelemetryContext, Int) -> CartoucheSessionReport?) {
        guard isOn else { return }
        onReport { context, seq in
            let shared = CartoucheTelemetryContext(install: context.install, cartouche: context.version, device: context.device,
                                                   ios: context.system, language: context.language)
            guard let report = make(shared, seq), let body = try? CartoucheTelemetryFormat.json(report) else { return nil }
            return CartoucheMacReport(id: report.id, body: body)
        }
    }
}

// MARK: The games' sessions

/// The sessions of the games played on this Mac, each read once from its
/// log, as Cartouche on the iPhone reads them (CartoucheTelemetry.collect).
@MainActor
final class CartoucheMacSessions {
    static let shared = CartoucheMacSessions()

    /// Where nxnative's apps for the Mac write each game's log.
    nonisolated static var nxnativeLogs: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Logs/nxnative", isDirectory: true)
    }

    /// The launcher's last lines, once the game's host ended
    /// (dm/mac/launcher.c).
    nonisolated static let exited = "launcher: the host exited with "
    nonisolated static let signalled = "launcher: the host stopped on signal "
    /// The signals of a game stopped from outside, which is no crash
    /// (MacGameEnding in BuilderKit).
    nonisolated static let stoppedBy: Set<Int> = [1, 2, 9, 15]
    /// The exit status of a game nxnative stopped once macOS took the GPU
    /// away from it (MacGameEnding.gpu).
    nonisolated static let gpuLostExit = 70

    /// A log to read, and what is known of its game.
    struct Job: Sendable {
        let url: URL
        let key: String
        let session: String
        let bytes: Int
        let seconds: Double
        let game: String
        let gameVersion: String?
        let nxnative: String?
        let nxnativeChanged: Bool?
        /// On a GPU without BC textures, whether the build converts them, as
        /// on the iPhone: a Mac's reads them, and says nothing of it.
        let bcTextures: String?
        let settings: [String: String]
    }

    /// The folder of the games' logs.
    private(set) var logs = CartoucheMacSessions.nxnativeLogs
    /// Where the logs read are kept; nil keeps nothing and reads nothing,
    /// as after the tests.
    var file: URL?
    private var read = CartoucheTelemetryLogs()
    /// The games playing when the app last said.
    private(set) var playing: Set<String> = []
    /// The pass reading the logs, while it runs.
    private var pass: Task<Void, Never>?
    /// Another pass asked for meanwhile: whether it reports.
    private var collectAgain: Bool?

    /// Keeps the logs read in FILE from now on, LOGS being the folder of
    /// the games' logs. Without FILE yet, every log there is noted as read,
    /// whatever its game, and reported never.
    func keep(in file: URL, logs: URL) {
        self.logs = logs
        self.file = file
        if let data = try? Data(contentsOf: file), let kept = try? JSONDecoder().decode(CartoucheTelemetryLogs.self, from: data) {
            read = kept
            return
        }
        read = CartoucheTelemetryLogs()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: logs.path)) ?? []
        for name in names.sorted() {
            guard let titleID = Self.titleID(ofLog: name) else { continue }
            let url = logs.appendingPathComponent(name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let created = attributes[.creationDate] as? Date,
                  let bytes = (attributes[.size] as? NSNumber)?.intValue else { continue }
            read.record(key: CartoucheTelemetryLogs.key(folder: titleID, created: created), session: UUID().uuidString.lowercased(),
                        bytes: bytes)
        }
        save()
    }

    /// The title ID a log of nxnative's is named after: <title ID>.log, or
    /// <title ID>.prev.log for the run before.
    nonisolated static func titleID(ofLog name: String) -> String? {
        let stem = name.hasSuffix(".prev.log") ? String(name.dropLast(9)) : name.hasSuffix(".log") ? String(name.dropLast(4)) : nil
        guard let stem, stem.count == 16, stem.allSatisfy(\.isHexDigit) else { return nil }
        return stem.uppercased()
    }

    /// Reads the sessions of the logs not read yet, then has the app send
    /// their reports; without REPORTING, only notes them as read.
    func collect(playing: Set<String>, reporting: Bool = true) {
        self.playing = Set(playing.map { $0.uppercased() })
        guard file != nil else { return }
        guard pass == nil else {
            // A pass noting them as read wins over one reporting them.
            collectAgain = (collectAgain ?? true) && reporting
            return
        }
        let telemetry = CartoucheTelemetry.shared
        guard telemetry.isOn || !reporting else { return }
        let jobs = findLogs()
        guard !jobs.isEmpty else { return }
        guard reporting else {
            for job in jobs { read.record(key: job.key, session: job.session, bytes: job.bytes) }
            save()
            return
        }
        pass = Task {
            let measured = await Task.detached(priority: .utility) {
                jobs.map { job in (job, Self.measures(of: job)) }
            }.value
            for (job, measures) in measured {
                read.record(key: job.key, session: job.session, bytes: job.bytes)
                guard let measures else { continue }
                telemetry.report { context, seq in
                    CartoucheSessionReport(
                        id: UUID().uuidString.lowercased(), session: job.session, seq: seq, context: context,
                        game: job.game, gameVersion: job.gameVersion, nxnative: job.nxnative, nxnativeChanged: job.nxnativeChanged,
                        bcTextures: job.bcTextures, settings: job.settings, minutes: CartoucheGameLogReader.rounded(job.seconds / 60, 1), measures: measures)
                }
            }
            save()
            pass = nil
            if let again = collectAgain {
                collectAgain = nil
                collect(playing: self.playing, reporting: again)
            }
        }
    }

    /// Returns once the logs are read and their reports made, those asked
    /// for meanwhile too.
    func finished() async {
        while let pass { await pass.value }
    }

    /// The logs of the console's games that have a session to read: not
    /// the one a game playing is still writing.
    func findLogs() -> [Job] {
        var jobs: [Job] = []
        let actions = CartoucheGameActions.shared
        for app in CartoucheMacConsole.shared.apps {
            guard let titleID = actions.titleId(of: app)?.uppercased() else { continue }
            let names = playing.contains(titleID) ? ["\(titleID).prev.log"] : ["\(titleID).prev.log", "\(titleID).log"]
            var details: (build: CartoucheGameBuild, settings: [String: String], bcTextures: String?)?
            for name in names {
                let url = logs.appendingPathComponent(name)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let created = attributes[.creationDate] as? Date,
                      let modified = attributes[.modificationDate] as? Date,
                      let bytes = (attributes[.size] as? NSNumber)?.intValue, bytes > 0 else { continue }
                let key = CartoucheTelemetryLogs.key(folder: titleID, created: created)
                guard read.needsReading(key: key, bytes: bytes) else { continue }
                if details == nil {
                    details = (build: CartoucheInstalledBuilds.installedBuild(of: app),
                               settings: actions.settings(for: app, tileKey: "").values,
                               bcTextures: CartoucheSessionReport.bcTextures(
                                   readsBCTextures: CartoucheDevice.supportsBCTextureCompression) {
                                       CartoucheInstalledBuilds.convertsBCTextures(of: app)
                                   })
                }
                let build = details?.build
                jobs.append(Job(url: url, key: key, session: read.session(of: key) ?? UUID().uuidString.lowercased(), bytes: bytes,
                                seconds: max(modified.timeIntervalSince(created), 0), game: titleID,
                                gameVersion: build?.version, nxnative: build?.shortCommit,
                                nxnativeChanged: build?.commit == nil ? nil : build?.isDirty,
                                bcTextures: details?.bcTextures,
                                settings: details?.settings ?? [:]))
            }
        }
        return jobs
    }

    /// The measures of the session JOB's log holds; nil when no game ran,
    /// its player having quit on nxnative's settings window. No memory
    /// limit: macOS sets a game none.
    nonisolated static func measures(of job: Job) -> CartoucheGameMeasures? {
        guard let reader = CartoucheGameLogReader.read(contentsOf: job.url) else { return nil }
        let ending = launcherEnding(of: job.url)
        var measures = reader.measures(seconds: job.seconds, limitMiB: nil)
        guard ending != nil || (measures.frames ?? 0) > 0 else { return nil }
        // How the game ended, as the launcher says it, when the game's own
        // lines do not: stopped from outside is no crash, and another exit
        // status before the first frame is a game that did not start.
        if measures.end == nil || measures.end?.kind == "unknown", let ending {
            if let signal = ending.signal {
                measures.end = stoppedBy.contains(signal) ? CartoucheGameMeasures.End(kind: "unknown")
                                                          : CartoucheGameMeasures.End(kind: "crash", signal: signal)
            } else if let exit = ending.exit {
                switch exit {
                case 0: measures.end = CartoucheGameMeasures.End(kind: "quit")
                case gpuLostExit: measures.end = CartoucheGameMeasures.End(kind: "crash", cause: "gpuLost")
                default: measures.end = CartoucheGameMeasures.End(kind: (measures.frames ?? 0) > 0 ? "crash" : "boot-failed")
                }
            }
        }
        return measures
    }

    /// The last line the launcher wrote once its host ended: its exit
    /// status, or the signal it stopped on; nil when the host never ran
    /// or the log does not say. The end of the log alone is read.
    nonisolated static func launcherEnding(of url: URL) -> (exit: Int?, signal: Int?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            if line.hasPrefix(exited), let code = Int(line.dropFirst(exited.count).trimmingCharacters(in: .whitespaces)) {
                return (code, nil)
            }
            if line.hasPrefix(signalled), let signal = Int(line.dropFirst(signalled.count).trimmingCharacters(in: .whitespaces)) {
                return (nil, signal)
            }
        }
        return nil
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(read) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
