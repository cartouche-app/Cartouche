//
//  CartoucheOffersTests.swift
//  CartoucheCoreTests
//
//  The buttons of the way to a first game the player tapped, and the
//  question to warn before Cartouche expires: their `offer.tapped` and
//  `alerts.asked` events, which the server takes, and which the telemetry's
//  README tells, each offer and each place. The home's offer of a saves
//  folder once the first game ended (decision 178): when it shows, and its
//  `offer.shown` and `offer.taken` events.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheOffersTests: XCTestCase {
    private let context = CartoucheTelemetryContext(install: "8c1f6c2e-7a2f-4e19-8c3d-2f6a9b0e1d7c", cartouche: "0.16.1",
                                                    device: "iPhone19,4", ios: "27.2", language: "en")

    private func report(_ name: String, _ fields: [String: CartoucheTelemetryValue]) -> CartoucheEventReport? {
        CartoucheEventReport(id: "3d9b2f5e-0000-4000-8000-000000000001", seq: 1, context: context, name: name, fields: fields)
    }

    private func assertWords(_ fields: [String: CartoucheTelemetryValue], file: StaticString = #filePath, line: UInt = #line) {
        for (key, value) in fields {
            XCTAssertNotNil(key.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression), key, file: file, line: line)
            if case .text(let text) = value {
                XCTAssertNotNil(text.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression), text, file: file, line: line)
            }
        }
    }

    func testEachTapSaysWhichButtonAndWhere() {
        XCTAssertEqual(CartoucheOffer.howToGetGame.fields(at: .sheet), ["offer": .text("howToGetGame"), "place": .text("sheet")])
        XCTAssertEqual(CartoucheOffer.nightlyHidden.fields(at: .home), ["offer": .text("nightlyHidden"), "place": .text("home")])
        XCTAssertEqual(CartoucheOffer.buildCloud.fields(at: .guide), ["offer": .text("buildCloud"), "place": .text("guide")])
        for offer in CartoucheOffer.allCases {
            for place in CartoucheOffer.Place.allCases {
                let fields = offer.fields(at: place)
                assertWords(fields)
                let made = report(CartoucheOffer.event, fields)
                XCTAssertNotNil(made, "\(offer) at \(place)")
                XCTAssertEqual(made?.fields, fields)
            }
        }
    }

    /// Once the first game is over, back on the console, with the saves on
    /// this device alone: never before a minute of play, nor while a game
    /// plays, nor once the player took it off. Up to 0.16.2, nothing
    /// offered a saves folder: 57 of the 135 copies that had a game on
    /// November 26 had none.
    func testTheSavesFolderIsOfferedOnceTheFirstGameIsOver() {
        XCTAssertTrue(CartoucheSavesOfferRule.shows(played: 60, playing: false, needsFolder: true, hidden: false))
        XCTAssertTrue(CartoucheSavesOfferRule.shows(played: 45_240, playing: false, needsFolder: true, hidden: false))
        // A game that stopped as it started, or none played yet.
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: 0, playing: false, needsFolder: true, hidden: false))
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: 59, playing: false, needsFolder: true, hidden: false))
        // The first game still plays, paused behind the console.
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: 2_820, playing: true, needsFolder: true, hidden: false))
        // A saves folder already, or the offer taken off for good.
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: 2_820, playing: false, needsFolder: false, hidden: false))
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: 2_820, playing: false, needsFolder: true, hidden: true))
    }

    /// On the iPhone, the saves need a folder while they have none and the
    /// player never chose one: a folder chosen, then stopped, was the
    /// player's own choice, and the offer stays away.
    func testTheIPhonesSavesNeedAFolderTheyNeverHad() {
        XCTAssertTrue(CartoucheSavesOfferRule.needsFolder(hasFolder: false, choseOnce: false))
        XCTAssertFalse(CartoucheSavesOfferRule.needsFolder(hasFolder: true, choseOnce: false))
        XCTAssertFalse(CartoucheSavesOfferRule.needsFolder(hasFolder: true, choseOnce: true))
        XCTAssertFalse(CartoucheSavesOfferRule.needsFolder(hasFolder: false, choseOnce: true))
    }

    /// The play time that makes the first game over: every game's, every
    /// data folder's, together.
    func testThePlayTimeOfEveryGameAddsUp() {
        var record = CartouchePlayTimeRecord()
        XCTAssertEqual(record.seconds, 0)
        record.note(CartouchePlayTime(seconds: 40, sessions: 1), bundleId: "org.nxnative.0400c3f00006e000",
                    titleId: "0400C3F00006E000", folder: "A")
        XCTAssertFalse(CartoucheSavesOfferRule.shows(played: record.seconds, playing: false, needsFolder: true, hidden: false))
        record.note(CartouchePlayTime(seconds: 15, sessions: 1), bundleId: "org.nxnative.0400c3f00006e000",
                    titleId: "0400C3F00006E000", folder: "B")
        record.note(CartouchePlayTime(seconds: 5, sessions: 1), bundleId: "org.nxnative.040074a01bf12000",
                    titleId: "040074A01BF12000", folder: "A")
        XCTAssertEqual(record.seconds, 60)
        XCTAssertTrue(CartoucheSavesOfferRule.shows(played: record.seconds, playing: false, needsFolder: true, hidden: false))
    }

    /// The banner says it showed, once, and the kind of storage the player
    /// then chose, never its name nor its address.
    func testTheSavesOfferSaysItShowedAndWhatThePlayerChose() {
        XCTAssertEqual(CartoucheOffer.savesBanner.fields(at: .home), ["offer": .text("savesBanner"), "place": .text("home")])
        XCTAssertEqual(CartoucheOffer.savesHidden.fields(at: .home), ["offer": .text("savesHidden"), "place": .text("home")])
        for kind in ["smb", "folder", "s3", "ftp", "sftp", "mac", "drive"] {
            let fields = CartoucheOffer.savesBanner.takenFields(kind: kind)
            XCTAssertEqual(fields, ["offer": .text("savesBanner"), "kind": .text(kind)])
            assertWords(fields)
            XCTAssertEqual(report(CartoucheOffer.takenEvent, fields)?.fields, fields)
        }
        let shown = CartoucheOffer.savesBanner.fields(at: .home)
        XCTAssertEqual(report(CartoucheOffer.shownEvent, shown)?.name, "offer.shown")
        XCTAssertEqual(report(CartoucheOffer.takenEvent, shown)?.name, "offer.taken")
    }

    func testTheQuestionToWarnSaysWhereAndWhatThePlayerAnswered() {
        XCTAssertEqual(CartoucheAlertsAsk.firstGame.fields(granted: true), ["place": .text("firstGame"), "granted": .flag(true)])
        XCTAssertEqual(CartoucheAlertsAsk.system.fields(granted: false), ["place": .text("system"), "granted": .flag(false)])
        for ask in CartoucheAlertsAsk.allCases {
            for granted in [true, false] {
                let fields = ask.fields(granted: granted)
                assertWords(fields)
                XCTAssertEqual(report(CartoucheAlertsAsk.event, fields)?.fields, fields)
            }
        }
    }

    /// telemetry/README.md tells each name either event sends.
    func testTheTelemetrysReadmeTellsEveryName() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../telemetry/README.md").standardizedFileURL
        let readme = try String(contentsOf: url, encoding: .utf8)
        func row(_ event: String) throws -> String {
            try XCTUnwrap(readme.components(separatedBy: "\n").first { $0.hasPrefix("| `\(event)` |") }, "no row for \(event)")
        }
        let offers = try row(CartoucheOffer.event)
        for name in CartoucheOffer.allCases.map(\.rawValue) + CartoucheOffer.Place.allCases.map(\.rawValue) {
            XCTAssertTrue(offers.contains("`\(name)`"), "offer.tapped's row should tell \(name)")
        }
        let shown = try row(CartoucheOffer.shownEvent)
        XCTAssertTrue(shown.contains("`savesBanner`") && shown.contains("`home`"), "offer.shown's row should tell savesBanner at home")
        let taken = try row(CartoucheOffer.takenEvent)
        for name in ["savesBanner", "kind", "smb", "folder", "s3", "ftp", "sftp", "mac", "drive"] {
            XCTAssertTrue(taken.contains("`\(name)`"), "offer.taken's row should tell \(name)")
        }
        let alerts = try row(CartoucheAlertsAsk.event)
        for name in CartoucheAlertsAsk.allCases.map(\.rawValue) + ["place", "granted"] {
            XCTAssertTrue(alerts.contains("`\(name)`"), "alerts.asked's row should tell \(name)")
        }
    }
}
