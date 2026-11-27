//
//  ConsoleTelemetryTests.swift
//  CartoucheConsoleTests
//
//  The sessions of the games played on this Mac (ConsoleTelemetry.swift):
//  each read once from the log nxnative's app for the Mac writes, field for
//  field as the server's tests hold it (telemetry/test/builder-reports.json),
//  never a line of the log, a path or a game's name; the log a game playing
//  still writes left for its end; the logs there before the first start,
//  and those of the games played with telemetry off, never reported; no
//  session for a player who quit on nxnative's window; how the launcher
//  says the game ended; and the console's events, as the app's telemetry
//  takes them. In folders and closures of the tests' own.
//

import Foundation
import XCTest
@testable import CartoucheConsole

/// A run of Mario Kart 8 Deluxe as nxnative's app for the Mac logs it
/// (dm/mac/launcher.c, dm/gfx/nvn/hle_nvn.c): the launcher's lines, which
/// name the game and its app's path, then the game's, then how it ended.
private let sampleRun = """
    launcher: Mario Kart 8 Deluxe (0100152000022000), host /Applications/Mario Kart 8 Deluxe.app/Contents/MacOS/dmhost
    launcher: env DM_FPS_TARGET=60 (saved choice)
    [dm] build: commit 6c3aeb3d70a1, shader chain 844bf1a5ea8f, profile mk8
    [dm] [nvn-mtl] pipeline prepare: 4210 lines (3000 shaders, 4000 render pipelines, 210 compute pipelines) in 6.20 s on 10 workers before the first frame, progress screen shown; bases 40 compiled, 4170 from the archive, 0 reused; 3 specializations
    [dm] [nvn] timing up to frame 300: frame time p50 16.67 / p95 17.80 / max 40.00 ms (300 frames); frame work p50 8.00 / p95 10.00 / max 20.00 ms (300 frames); GPU p50 6.50 / p95 9.00 / max 12.00 ms (300 frames);
    [dm] [nvn] pipelines up to frame 300: on the submit thread pipelines 40.0 ms, shader libraries 0.0 ms, predictions 0 / 0.0 ms
    [dm] [nvn] frame interval up to frame 300: >16.7ms 4 / 300 frames, p99 25.00 ms
    [dm] [nvn] on-screen up to frame 300: 300 frames, dropped 2 (discarded 0), p99 24.00 ms; footprint 3900 MiB; brightness -1.00; thermal -1
    [dm] [nvn] power up to frame 300: CPU energy 9.80 W, 163.3 mJ per frame (60.0 fps); CPU 310% (100 = one core), 70% of it on performance cores; wakeups 900/s (out of platform idle 0); GPU 380.0 ms/s; thermal -1; top yielders: none
    [dm] [nvn] timing up to frame 600: frame time p50 16.67 / p95 17.20 / max 22.00 ms (300 frames); GPU p50 6.40 / p95 8.80 / max 11.00 ms (300 frames);
    [dm] [nvn] pipelines up to frame 600: on the submit thread pipelines 0.0 ms, shader libraries 0.0 ms, predictions 0 / 0.0 ms
    [dm] [nvn] frame interval up to frame 600: >16.7ms 1 / 300 frames, p99 18.00 ms
    [dm] [nvn] on-screen up to frame 600: 300 frames, dropped 0 (discarded 0), p99 17.50 ms; footprint 4020 MiB; brightness -1.00; thermal -1
    [dm] [nvn-mtl] present command buffer GPU time over 600 presents through MetalFX: p50 0.800 ms, p95 1.000 ms, max 1.300 ms
    [dm] audio #1 device callbacks 4000: 512–512 frames each, 2.5 blocks queued on average at callback; in these 2000, 0 underruns, 0.0 ms zero-padded
    launcher: the save did not reach the cloud; it goes at the next start

    """

/// The game's settings list, as nxnative's settings.py writes it for the Mac.
private let settingsList = """
    {"schema": 1, "game": "0100152000022000", "settings": [
      {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "", "default": "60",
       "options": [["30", "30 fps"], ["60", "60 fps"]], "level": "basic"},
      {"env": "DM_LANG", "kind": "choice", "section": "Game", "label": "Game language", "note": "", "default": "en-US",
       "options": [["en-US", "American English"], ["fr", "French"]], "level": "basic"},
      {"env": "DM_FULLSCREEN", "kind": "choice", "section": "Game", "label": "Display mode", "note": "", "default": "0",
       "options": [["0", "Window"], ["1", "Fullscreen"]], "level": "basic"}
    ]}
    """

@MainActor
final class ConsoleTelemetryTests: XCTestCase {
    private var root: URL!
    private var logs: URL!
    private var sessions: URL!
    private var keptDataRoot: URL!
    private var keptMemory = false
    /// What the app was given to send, and the number of its last report.
    private var reports: [CartoucheMacReport] = []
    private var seq = 33
    private var switched: [Bool] = []
    private let titleID = "0100152000022000"
    private let started = Date(timeIntervalSince1970: 1_794_000_000)
    /// This copy's context, as builder-reports.json has it.
    private let context = CartoucheMacTelemetryContext(install: "8c1f6c2e-7a2f-4e19-8c3d-2f6a9b0e1d7c", version: "0.2.1",
                                                       device: "Mac16,12", system: "26.6", language: "fr", deviceLanguage: "fr")

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("console-telemetry-\(UUID().uuidString)", isDirectory: true)
        logs = root.appendingPathComponent("Logs/nxnative", isDirectory: true)
        sessions = root.appendingPathComponent("Builder/sessions.json")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let actions = CartoucheGameActions.shared
        keptDataRoot = actions.dataRoot
        keptMemory = actions.keepsChoicesInMemory
        actions.dataRoot = root.appendingPathComponent("nxnative", isDirectory: true)
        actions.keepsChoicesInMemory = true
        let console = CartoucheMacConsole.shared
        console.showMeasures(CartoucheMacMeasures(isOn: true))
        // As the app's telemetry does: a report it is given takes the next
        // number, one it is not takes none.
        console.onMeasuresReport = { [unowned self] make in
            guard let report = make(self.context, self.seq + 1) else { return }
            self.seq += 1
            self.reports.append(report)
        }
        console.onMeasuresSwitch = { [unowned self] on in self.switched.append(on) }
    }

    override func tearDown() async throws {
        await CartoucheMacSessions.shared.finished()
        let console = CartoucheMacConsole.shared
        console.show(games: [])
        CartoucheMacSessions.shared.file = nil
        console.showMeasures(CartoucheMacMeasures(isOn: true))
        console.onMeasuresReport = { _ in }
        console.onMeasuresSwitch = { _ in }
        console.onMeasuresEvent = { _, _, _ in }
        CartoucheGameActions.shared.dataRoot = keptDataRoot
        CartoucheGameActions.shared.keepsChoicesInMemory = keptMemory
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    /// The game's app as nxnative builds it for the Mac, in the console: its
    /// version, the nxnative commit it was built from, the shader chain
    /// beside it, as nxnative writes them in long, and its settings, the
    /// frame rate and the display mode as they come, the language the one
    /// the player's env.txt sets.
    private func showGame() throws {
        let app = root.appendingPathComponent("Applications/Mario Kart 8 Deluxe.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources/dm"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.mk8.\(UUID().uuidString.lowercased())",
                                   "CFBundleName": "Mario Kart 8 Deluxe", "DMTitleID": titleID, "CFBundleShortVersionString": "3.0.3",
                                   "DMCommit": "6c3aeb3d70a1f00d5eed0123456789abcdef0123",
                                   "DMChain": "844BF1A5EA8F00112233", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(settingsList.utf8).write(to: contents.appendingPathComponent("Resources/dm/launcher.json"))
        let folder = CartoucheGameActions.shared.dataRoot.appendingPathComponent(titleID, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("DM_LANG=fr\n".utf8).write(to: folder.appendingPathComponent("env.txt"))
        CartoucheMacConsole.shared.show(games: [app])
    }

    /// A run of the game as nxnative's launcher starts one: the log of the
    /// run before becomes <title ID>.prev.log, its birth kept, and TEXT is
    /// the new one's, as if it started AT and was last written SECONDS later.
    private func newRun(_ text: String = sampleRun + "launcher: the host exited with 0\n", at start: Date,
                        seconds: TimeInterval = 1_800) throws {
        let log = logs.appendingPathComponent("\(titleID).log")
        let prev = logs.appendingPathComponent("\(titleID).prev.log")
        if FileManager.default.fileExists(atPath: log.path) {
            try? FileManager.default.removeItem(at: prev)
            try FileManager.default.moveItem(at: log, to: prev)
        }
        try write(text, at: start, seconds: seconds)
    }

    /// The current run's log written again, TEXT, as at its end.
    private func write(_ text: String, at start: Date, seconds: TimeInterval) throws {
        let log = logs.appendingPathComponent("\(titleID).log")
        try Data(text.utf8).write(to: log)
        try FileManager.default.setAttributes([.creationDate: start, .modificationDate: start.addingTimeInterval(seconds)],
                                              ofItemAtPath: log.path)
    }

    /// The console reads the logs, as the app has it after a game.
    private func read(playing: Set<String> = []) async {
        CartoucheMacConsole.shared.readSessions(playing: playing)
        await CartoucheMacSessions.shared.finished()
    }

    private func object(_ report: CartoucheMacReport) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.body.utf8)) as? [String: Any])
    }

    private func end(_ report: CartoucheMacReport) throws -> [String: Any] {
        try XCTUnwrap(try object(report)["end"] as? [String: Any])
    }

    // MARK: Tests

    /// The server's tests hold the report the console makes of a session,
    /// field for field (telemetry/test/worker.test.js keeps each one):
    /// only its random numbers are the console's own.
    func testASessionIsReportedOnceAsTheServersTestsHoldIt() async throws {
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        try showGame()
        try newRun(at: started)
        await read()
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        var made = try object(report)
        XCTAssertEqual(made["id"] as? String, report.id)
        let session = try XCTUnwrap(made["session"] as? String)

        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../telemetry/test/builder-reports.json").standardizedFileURL
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var kept = try XCTUnwrap((file["reports"] as? [[String: Any]])?.first { $0["kind"] as? String == "session" })
        for key in ["id", "session"] {
            XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(made[key] as? String)), key)
            XCTAssertEqual(made[key] as? String, (made[key] as? String)?.lowercased(), key)
            made[key] = nil
            kept[key] = nil
        }
        XCTAssertEqual(NSDictionary(dictionary: made), NSDictionary(dictionary: kept),
                       "builder-reports.json should hold the console's session: \(report.body)")
        // Never a line of the log, a path, a name: the shader chain is the
        // Info.plist's, in 12 digits, as the commit.
        for word in ["launcher", "Mario", "Applications", "dmhost", "cloud", "shader chain", "mk8", "844bf1a5ea8f0011",
                     root.path] {
            XCTAssertFalse(report.body.contains(word), word)
        }

        // Read once: again, or when the app starts again, nothing new.
        await read()
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        await read()
        XCTAssertEqual(reports.count, 1)
        // The next run, its own session; the run before, now the
        // .prev.log, is not read again.
        try newRun(at: started.addingTimeInterval(7_200), seconds: 600)
        await read()
        XCTAssertEqual(reports.count, 2)
        let next = try object(reports[1])
        XCTAssertNotEqual(next["session"] as? String, session)
        XCTAssertEqual(next["minutes"] as? Double, 10)
        XCTAssertEqual(next["seq"] as? Int, 35)
    }

    /// A game playing still writes its log: the run before is read, its
    /// own once it ended, under one session whatever was read before.
    func testTheLogOfAGamePlayingWaitsForItsEnd() async throws {
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        try showGame()
        try newRun(at: started)
        let now = started.addingTimeInterval(7_200)
        try newRun(sampleRun, at: now, seconds: 300)
        await read(playing: [titleID.lowercased()])
        XCTAssertEqual(reports.count, 1, "the run before only")
        XCTAssertEqual(try object(reports[0])["minutes"] as? Double, 30)

        // The game ended: its log, read at last.
        try write(sampleRun + "launcher: the host exited with 0\n", at: now, seconds: 900)
        await read()
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(try object(reports[1])["minutes"] as? Double, 15)
        XCTAssertEqual(try end(reports[1])["kind"] as? String, "quit")

        // A log read before it ended, read again once it grew: the same
        // session, which the server keeps once.
        let later = now.addingTimeInterval(7_200)
        try newRun(sampleRun, at: later, seconds: 300)
        await read()
        XCTAssertEqual(reports.count, 3)
        try write(sampleRun + "launcher: the host exited with 0\n", at: later, seconds: 600)
        await read()
        XCTAssertEqual(reports.count, 4)
        XCTAssertEqual(try object(reports[3])["session"] as? String, try object(reports[2])["session"] as? String)
    }

    /// The logs there at the first start are of games played before: noted
    /// as read whatever the console shows, and never reported.
    func testTheLogsThereAtTheFirstStartAreNeverReported() async throws {
        try newRun(at: started)
        try newRun(at: started.addingTimeInterval(7_200))
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessions.path), "noted before the console shows any game")
        try showGame()
        await read()
        XCTAssertTrue(reports.isEmpty)
        // A game played after them is.
        try newRun(at: started.addingTimeInterval(14_400))
        await read()
        XCTAssertEqual(reports.count, 1)
    }

    /// A player who quit on nxnative's settings window played no game: no
    /// session, and the log is not read again.
    func testQuittingOnNxnativesWindowIsNoSession() async throws {
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        try showGame()
        try newRun("launcher: Mario Kart 8 Deluxe (0100152000022000)\nlauncher: env DM_FPS_TARGET=60 (saved choice)\n",
                   at: started, seconds: 20)
        await read()
        XCTAssertTrue(reports.isEmpty)
        try newRun(at: started.addingTimeInterval(7_200))
        await read()
        XCTAssertEqual(reports.count, 1, "the game played next only")
    }

    /// With telemetry off, nothing is read, and once it is on again, from
    /// System › Game measurements or from the Builder's settings, only the
    /// games played after it are reported.
    func testNothingPlayedWithTelemetryOffIsReported() async throws {
        let console = CartoucheMacConsole.shared
        console.keepSessions(in: sessions, logs: logs)
        try showGame()
        console.showMeasures(CartoucheMacMeasures(isOn: false))
        try newRun(at: started)
        await read()
        XCTAssertTrue(reports.isEmpty)
        // On again from System › Game measurements.
        CartoucheTelemetry.shared.setOn(true)
        XCTAssertEqual(switched, [true])
        await read()
        XCTAssertTrue(reports.isEmpty, "played while it was off")
        try newRun(at: started.addingTimeInterval(7_200))
        await read()
        XCTAssertEqual(reports.count, 1)

        // Off, then on again, from the Builder's settings.
        console.showMeasures(CartoucheMacMeasures(isOn: false))
        try newRun(at: started.addingTimeInterval(14_400))
        await read()
        console.showMeasures(CartoucheMacMeasures(isOn: true))
        await CartoucheMacSessions.shared.finished()
        await read()
        XCTAssertEqual(reports.count, 1, "played while it was off")
        XCTAssertEqual(switched, [true], "the Builder's own switch")
    }

    /// How the game ended, as the launcher's last line says it when the
    /// game's own lines do not: a quit, a crash and its signal, a game
    /// stopped from outside, which is no crash, the GPU taken away, a
    /// game that did not start.
    func testTheLauncherSaysHowTheGameEnded() async throws {
        CartoucheMacConsole.shared.keepSessions(in: sessions, logs: logs)
        try showGame()
        let endings: [(String, [String: Any])] = [
            (sampleRun + "launcher: the host exited with 0\n", ["kind": "quit"]),
            (sampleRun + "launcher: the host stopped on signal 11\n", ["kind": "crash", "signal": 11]),
            (sampleRun + "launcher: the host stopped on signal 15\n", ["kind": "unknown"]),
            (sampleRun + "launcher: the host exited with 70\n", ["kind": "crash", "cause": "gpuLost"]),
            (sampleRun + "launcher: the host exited with 1\n", ["kind": "crash"]),
            ("launcher: Mario Kart 8 Deluxe (0100152000022000), host /Applications/Mario Kart 8 Deluxe.app/Contents/MacOS/dmhost\n"
                + "launcher: the host exited with 1\n", ["kind": "boot-failed"]),
        ]
        for (index, (text, expected)) in endings.enumerated() {
            try newRun(text, at: started.addingTimeInterval(Double(index) * 7_200))
            await read()
            XCTAssertEqual(reports.count, index + 1, "\(expected)")
            guard reports.count == index + 1 else { return }
            XCTAssertEqual(NSDictionary(dictionary: try end(reports[index])), NSDictionary(dictionary: expected))
        }
        XCTAssertEqual(CartoucheMacSessions.titleID(ofLog: "0100152000022000.prev.log"), titleID)
        XCTAssertEqual(CartoucheMacSessions.titleID(ofLog: "0100152000022000.log"), titleID)
        XCTAssertNil(CartoucheMacSessions.titleID(ofLog: "launcher.log"))
    }

    /// The console's events go to the app's telemetry as they are, with
    /// telemetry on only.
    func testTheConsolesEventsGoToTheAppsTelemetry() {
        let console = CartoucheMacConsole.shared
        var heard: [(String, String?, [String: CartoucheMacMeasure])] = []
        console.onMeasuresEvent = { name, game, fields in heard.append((name, game, fields)) }
        CartoucheTelemetry.shared.event("game.infoChanged", game: titleID,
                                        fields: ["field": .text("name"), "length": .number(12), "cleared": .flag(false)])
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(heard.first?.0, "game.infoChanged")
        XCTAssertEqual(heard.first?.1, titleID)
        XCTAssertEqual(heard.first?.2, ["field": .text("name"), "length": .number(12), "cleared": .flag(false)])
        console.showMeasures(CartoucheMacMeasures(isOn: false))
        CartoucheTelemetry.shared.event("game.infoChanged", game: titleID)
        XCTAssertEqual(heard.count, 1)

        // What System › Game measurements shows is the app's.
        let sent = Date(timeIntervalSince1970: 1_794_000_000)
        console.showMeasures(CartoucheMacMeasures(isOn: true, sent: 12, waiting: 2, lastSent: sent, lastReport: "{}"))
        let telemetry = CartoucheTelemetry.shared
        XCTAssertTrue(telemetry.isOn)
        XCTAssertEqual(telemetry.sent, 12)
        XCTAssertEqual(telemetry.waiting, 2)
        XCTAssertEqual(telemetry.lastSent, sent)
        XCTAssertEqual(telemetry.lastReport, "{}")
    }

    /// An error the console shows, with its report, goes to the app's
    /// telemetry as the iPhone's does (CartoucheErrorEvent): an error
    /// event, with its origin, cause and codes, never its words; with
    /// telemetry on only.
    func testTheConsolesErrorsGoToTheAppsTelemetry() {
        let console = CartoucheMacConsole.shared
        var heard: [(String, String?, [String: CartoucheMacMeasure])] = []
        console.onMeasuresEvent = { name, game, fields in heard.append((name, game, fields)) }
        let full = NSError(domain: NSPOSIXErrorDomain, code: 28, userInfo: [NSLocalizedDescriptionKey: "No space left on the NAS"])
        _ = CartoucheReports.make(.saves, "The saves were not sent", message: "No space left on the NAS", error: full,
                                  stage: "savesSync", inBackground: true)
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(heard.first?.0, "error")
        XCTAssertNil(heard.first?.1)
        let fields = heard.first?.2 ?? [:]
        XCTAssertEqual(fields["origin"], .text("saves"))
        XCTAssertEqual(fields["error"], .text("NSPOSIXErrorDomain 28"))
        XCTAssertEqual(fields["stage"], .text("savesSync"))
        XCTAssertEqual(fields["background"], .flag(true))
        XCTAssertNotNil(fields["cause"])
        XCTAssertFalse("\(fields)".contains("NAS"))
        XCTAssertFalse("\(fields)".contains("saves were not sent"))
        console.showMeasures(CartoucheMacMeasures(isOn: false))
        _ = CartoucheReports.make(.storage, "Problem", message: "Nothing answers.", inBackground: true)
        XCTAssertEqual(heard.count, 1)
    }
}
