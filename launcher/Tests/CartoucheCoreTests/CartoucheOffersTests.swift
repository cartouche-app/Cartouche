//
//  CartoucheOffersTests.swift
//  CartoucheCoreTests
//
//  The buttons of the way to a first game the player tapped, and the
//  question to warn before Cartouche expires: their `offer.tapped` and
//  `alerts.asked` events, which the server takes, and which the telemetry's
//  README tells, each offer and each place.
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
        let alerts = try row(CartoucheAlertsAsk.event)
        for name in CartoucheAlertsAsk.allCases.map(\.rawValue) + ["place", "granted"] {
            XCTAssertTrue(alerts.contains("`\(name)`"), "alerts.asked's row should tell \(name)")
        }
    }
}
