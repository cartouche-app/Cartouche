//
//  GameResultsTests.swift
//  CartoucheHarnessTests
//

import XCTest
@testable import CartoucheHarness

@MainActor
final class GameResultsTests: XCTestCase {
    func testResultsForThisModelComeFirst() {
        let ownModel = "iPhone19,4"
        let ownOld = result(device: ownModel, date: "2026-11-15")
        let ownNew = result(device: ownModel, date: "2026-11-18")
        let otherOld = result(device: "iPhone18,2", date: "2026-11-17")
        let otherNew = result(device: "iPhone18,1", date: "2026-11-19")
        let results = [otherOld, ownOld, otherNew, ownNew]

        XCTAssertEqual(CartoucheGameResultsSection.ordered(results, for: ownModel),
                       [ownNew, ownOld, otherNew, otherOld])
        XCTAssertEqual(CartoucheGameResultsSection.ordered(results, for: "iPad15,3"),
                       [otherNew, ownNew, otherOld, ownOld])
    }

    private func result(device: String, date: String) -> CartoucheGameSheet.Result {
        CartoucheGameSheet.Result(device: device, iOS: "27.2", date: date, engine: "nxnative",
                                  status: "playable", peakMemoryMiB: nil, notes: nil, measured: nil)
    }
}
