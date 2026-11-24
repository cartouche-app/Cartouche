//
//  BuildForTests.swift
//  Cartouche Builder
//
//  The app's copy of whom the games are built for (BuildFor) says what
//  the engine decides (cartouche_builder/build_for.py): its answers on the
//  same examples (Fixtures/build-for.json, from builder/tests/test_build_for.py),
//  every model Build for offers among them. And the paired iPhones keep
//  what Cartouche tells of itself, never more.
//

import CartoucheCore
import XCTest
@testable import BuilderKit

final class BuildForTests: XCTestCase {
    private struct Examples: Decodable {
        struct Device: Decodable {
            var name: String
            var model: String?
            var readsBC: Bool?
        }

        struct Example: Decodable {
            var config: [String: String]
            var devices: [Device]
            var kind: String
            var model: String
            var device: String
            var url: String
            var branch: String
        }

        var models: [String: Bool]
        var choices: [Example]
    }

    private func examples() throws -> Examples {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/build-for.json")
        return try JSONDecoder().decode(Examples.self, from: Data(contentsOf: url))
    }

    func testEachModelReadsBCAsTheEngineSays() throws {
        let examples = try examples()
        for (model, reads) in examples.models {
            XCTAssertEqual(BuildFor.readsBC(model), reads, model)
        }
    }

    func testEveryModelOfferedIsOneOfTheEnginesExamples() throws {
        let examples = try examples()
        for model in BuildFor.models {
            XCTAssertNotNil(examples.models[model.id], "\(model.id) (\(model.name)): add it to EXAMPLE_MODELS in test_build_for.py")
        }
        XCTAssertEqual(Set(BuildFor.models.map(\.id)).count, BuildFor.models.count)
        XCTAssertEqual(BuildFor.name(of: "iPhone15,4"), "iPhone 15")
        XCTAssertFalse(BuildFor.models.first { $0.id == "iPhone15,4" }!.readsBC)
        XCTAssertTrue(BuildFor.models.first { $0.id == "iPhone16,1" }!.readsBC)
    }

    func testTheNxnativeChosenIsTheEnginesChoice() throws {
        for example in try examples().choices {
            var config = BuilderConfig()
            config.buildFor = example.config["build_for"] ?? ""
            config.engineURL = example.config["engine_url"] ?? BuilderConfig.engineURL
            config.engineBranch = example.config["engine_branch"] ?? BuilderConfig.engineBranch
            let devices = example.devices.enumerated().map { index, device in
                PairedDevice(id: "device-\(index)", name: device.name, key: Data(), model: device.model, readsBC: device.readsBC)
            }
            let choice = BuildFor.choice(config, devices: devices)
            let said = "\(example.config) \(example.devices.map(\.name))"
            XCTAssertEqual(choice.kind.rawValue, example.kind, said)
            XCTAssertEqual(choice.model ?? "", example.model, said)
            XCTAssertEqual(choice.device ?? "", example.device, said)
            // What the setup assistant's tools step says it downloads.
            let repository = BuildFor.repository(config, devices: devices)
            XCTAssertEqual(repository.url, example.url, said)
            XCTAssertEqual(repository.branch, example.branch, said)
        }
    }

    func testTheToolsStepSaysTheRepositoryAsThePlayerReadsIt() {
        XCTAssertEqual(BuildFor.address(BuilderConfig.engineURL), "github.com/seedds/nxnative")
        XCTAssertEqual(BuildFor.address(BuildFor.forkURL), "github.com/mianmuhammadse/nxnative-nobc")
        XCTAssertEqual(BuildFor.address("https://github.com/someone/nxnative/"), "github.com/someone/nxnative")
        XCTAssertEqual(BuildFor.address("git@github.com:someone/nxnative.git"), "github.com/someone/nxnative")
        XCTAssertEqual(BuildFor.address(" /Users/me/nxnative "), "/Users/me/nxnative")
    }

    func testAPairedIPhoneKeepsWhatItTellsOfItself() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("targets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("bridge.json")
        let devices = BridgeDevices(url: url)
        devices.add(id: "phone", name: "iPhone de Lou", key: Data([1, 2, 3]))
        XCTAssertNil(devices.all[0].model)
        XCTAssertNil(BuildFor.readsBC(devices.all[0]))

        XCTAssertTrue(devices.describe("phone", as: CartoucheBridgeDevice(model: "iPhone15,4", readsBC: false)))
        XCTAssertFalse(devices.describe("phone", as: CartoucheBridgeDevice(model: "iPhone15,4", readsBC: false)))
        XCTAssertFalse(devices.describe("unknown", as: CartoucheBridgeDevice(model: "iPhone15,4", readsBC: false)))
        // Kept in bridge.json, as the engine reads it (targets.paired).
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let kept = try XCTUnwrap((file["devices"] as? [[String: Any]])?.first)
        XCTAssertEqual(kept["model"] as? String, "iPhone15,4")
        XCTAssertEqual(kept["readsBC"] as? Bool, false)
        XCTAssertEqual(BridgeDevices(url: url).all[0].model, "iPhone15,4")
        XCTAssertEqual(BuildFor.choice(BuilderConfig(), devices: BridgeDevices(url: url).all),
                       BuildFor.Choice(kind: .noBC, model: "iPhone15,4", device: "iPhone de Lou"))
    }

    func testAnOlderBridgeFileStillReads() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("targets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("bridge.json")
        try Data(#"{"mac": "mac-id", "devices": [{"id": "phone", "name": "iPhone", "key": "AQID", "paired": "2026-11-20T10:00:00Z"}]}"#.utf8).write(to: url)
        let devices = BridgeDevices(url: url).all
        XCTAssertEqual(devices.map(\.id), ["phone"])
        XCTAssertNil(devices[0].model)
        XCTAssertEqual(BuildFor.choice(BuilderConfig(), devices: devices).kind, .nxnative)
    }
}
