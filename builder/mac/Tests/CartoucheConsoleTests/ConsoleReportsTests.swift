//
//  ConsoleReportsTests.swift
//  CartoucheConsoleTests
//
//  The reports of the console on the Mac, the iPhone's
//  (CartoucheReporting.swift): the journal and the last reports kept in
//  Cartouche Builder's folder from one start to the next; what a report says
//  of this Mac and of Cartouche Builder, without the iPhone's setup or
//  signature, nor the names of the Mac's account; System › Report a problem
//  without an entry for devices.json; and a game's logs, where nxnative's
//  app for the Mac writes them, for Share the log on its sheet. Each test
//  has a folder of its own.
//

import Foundation
import XCTest
@testable import CartoucheConsole

@MainActor
final class ConsoleReportsTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("console-reports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        CartoucheReports.flush()
        CartoucheReports.keep(in: nil)
        try? FileManager.default.removeItem(at: folder)
    }

    /// An nxnative game's app for the Mac, of TITLEID, as the Builder puts
    /// it in the games folder.
    private func game(_ name: String, titleID: String) throws -> LCAppModel {
        let app = folder.appendingPathComponent("Applications/\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "org.nxnative." + titleID.lowercased(), "CFBundleName": name,
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return LCAppModel(appInfo: LCAppInfo(url: app))
    }

    func testTheJournalAndTheReportsAreKeptInTheBuildersFolder() throws {
        CartoucheReports.keep(in: folder)
        XCTAssertTrue(CartoucheReports.recent.isEmpty)
        CartoucheReports.note("Saves sent to the saves folder: 3 games", own: true)
        let report = CartoucheReports.make(.saves, "Les sauvegardes n’ont pas été copiées", message: "Le disque est plein.")
        CartoucheReports.flush()
        let journal = try String(contentsOf: folder.appendingPathComponent("Journal.txt"), encoding: .utf8)
        XCTAssertTrue(journal.contains("Saves sent to the saves folder: 3 games\n"), journal)
        XCTAssertTrue(journal.contains("Problem (saves): Les sauvegardes n’ont pas été copiées: Le disque est plein."), journal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Reports.json").path))
        XCTAssertEqual(CartoucheReports.recent.map(\.message), [report.message])

        // In memory alone, as the gallery and the tests keep them.
        CartoucheReports.keep(in: nil)
        XCTAssertTrue(CartoucheReports.recent.isEmpty)
        XCTAssertFalse(CartoucheReports.journal(last: CartoucheReports.journalShown).contains { $0.contains("3 games") })

        // As the Builder starts again: the same, read from its folder.
        CartoucheReports.keep(in: folder)
        XCTAssertEqual(CartoucheReports.recent.map(\.message), ["Le disque est plein."])
        XCTAssertTrue(CartoucheReports.journal(last: CartoucheReports.journalShown).contains { $0.hasSuffix(" Saves sent to the saves folder: 3 games") })
    }

    func testAReportSaysThisMacAndCartoucheBuilder() {
        let environment = CartoucheReports.environment()
        XCTAssertEqual(environment.appShown, "Cartouche Builder")
        XCTAssertEqual(environment.systemShown, "macOS")
        XCTAssertNil(environment.basedOn)
        XCTAssertTrue(environment.device.hasSuffix(" GB)"), environment.device)
        // A Mac has no setup, signature or game behind the console to say.
        let names = environment.facts.map(\.name)
        XCTAssertEqual(names.last, "Storage")
        for name in ["Setup", "Signature", "Memory", "Memory behind Cartouche"] {
            XCTAssertFalse(names.contains(name), "\(names)")
        }
        XCTAssertFalse(names.contains { $0.contains("iPhone") }, "\(names)")

        let text = CartoucheReports.text(of: CartoucheReports.make(.storage, "Problème", message: "Rien ne répond.", inBackground: true))
        XCTAssertTrue(text.contains("\nCartouche Builder: "), text)
        XCTAssertTrue(text.contains("\nmacOS: "), text)
        XCTAssertFalse(text.contains("\niOS: "), text)
        // System › Report a problem: no entry for devices.json, which holds
        // no Mac.
        XCTAssertNil(CartoucheReportView.measurement(now: Date()))
    }

    func testTheMacsAccountNeverGoesInAReport() {
        let user = NSUserName()
        CartoucheReports.note("Could not read /Users/\(user)/Games/Celeste.app")
        let line = CartoucheReports.journal(last: 1).first ?? ""
        XCTAssertFalse(line.contains("/Users/\(user)/"), line)
        XCTAssertTrue(line.hasSuffix(" Could not read /Users/<account>/Games/Celeste.app"), line)
        let report = CartoucheReports.make(.storage, "Problème", message: "Pas d’accès à /Users/\(user)/Games", inBackground: true)
        let text = CartoucheReports.text(of: report)
        XCTAssertFalse(text.contains("/Users/\(user)/"), text)
        XCTAssertTrue(text.contains("Message: Pas d’accès à /Users/<account>/Games\n"), text)
    }

    func testAGamesLogsAreWhereNxnativesAppForTheMacWritesThem() throws {
        let actions = CartoucheGameActions.shared
        let kept = actions.logsRoot
        defer { actions.logsRoot = kept }
        let logs = folder.appendingPathComponent("Logs/nxnative", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        actions.logsRoot = logs

        let app = try game("Mario Kart World", titleID: "0400C3F00006E000")
        let none = try XCTUnwrap(actions.logs(of: app))
        XCTAssertEqual(none.game, "Mario Kart World")
        XCTAssertEqual(none.titleId, "0400C3F00006E000")
        XCTAssertTrue(none.files.isEmpty)

        // The last session's, the one before, and another game's.
        try Data("boot: game files\n".utf8).write(to: logs.appendingPathComponent("0400C3F00006E000.log"))
        try Data("boot: game files\n".utf8).write(to: logs.appendingPathComponent("0400C3F00006E000.prev.log"))
        try Data("boot: game files\n".utf8).write(to: logs.appendingPathComponent("0100152000022000.log"))
        let found = try XCTUnwrap(actions.logs(of: app))
        XCTAssertEqual(found.files.map(\.lastPathComponent), ["0400C3F00006E000.log", "0400C3F00006E000.prev.log"])
        XCTAssertEqual(found.logs.map { $0.name }, ["log.txt", "log.prev.txt"])

        // An app that is not an nxnative game has none.
        let notes = folder.appendingPathComponent("Applications/Notes.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.notes"], format: .xml, options: 0)
            .write(to: notes.appendingPathComponent("Info.plist"))
        XCTAssertNil(actions.logs(of: LCAppModel(appInfo: LCAppInfo(url: notes.deletingLastPathComponent()))))
    }
}
