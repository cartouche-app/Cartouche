//
//  AppNameTests.swift
//
//  A copy installed while the app was Cartouche Builder updates itself in
//  Cartouche Builder.app; its first start as Cartouche moves it to
//  Cartouche.app beside it, where it may, and opens it again with what it
//  was opened with (AppName.swift).
//

import BuilderKit
import Foundation
import XCTest

final class AppNameTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppNameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private func app(_ name: String) throws -> URL {
        let app = folder.appendingPathComponent(name, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testTheAppIsCalledCartouche() {
        XCTAssertEqual(AppName.name, "Cartouche")
        XCTAssertEqual(AppName.bundle, "Cartouche.app")
        XCTAssertEqual(AppName.former, "Cartouche Builder.app")
    }

    func testAnUpdatedCopyMovesToCartoucheBesideItWithAllItHas() throws {
        let old = try app("Cartouche Builder.app")
        let moved = try XCTUnwrap(AppName.move(old))
        XCTAssertEqual(moved.lastPathComponent, "Cartouche.app")
        XCTAssertEqual(moved.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Contents/Info.plist").path))
    }

    func testACopyAlreadyCalledCartoucheStays() throws {
        let app = try app("Cartouche.app")
        XCTAssertNil(AppName.destination(for: app))
        XCTAssertNil(AppName.move(app))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testACartoucheAlreadyBesideItIsNeverReplaced() throws {
        let old = try app("Cartouche Builder.app")
        let other = try app("Cartouche.app")
        XCTAssertNil(AppName.move(old))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.appendingPathComponent("Contents/Info.plist").path))
    }

    func testAFolderThePlayerMayNotChangeKeepsItWhereItIs() throws {
        let old = try app("Cartouche Builder.app")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertNil(AppName.destination(for: old))
        XCTAssertNil(AppName.move(old))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }

    func testOnItsDiskImageItStays() {
        let image = URL(fileURLWithPath: "/Volumes/Cartouche/Cartouche Builder.app")
        XCTAssertNil(AppName.destination(for: image))
    }

    func testTheMovedCopyOpensWithWhatThisOneHad() {
        XCTAssertEqual(AppName.arguments(from: ["/Applications/Cartouche Builder.app/Contents/MacOS/Cartouche", "--background"],
                                         opensAtLogin: false),
                       ["--background"])
        XCTAssertEqual(AppName.arguments(from: ["/Applications/Cartouche Builder.app/Contents/MacOS/Cartouche"], opensAtLogin: true),
                       ["--opens-at-login"])
        XCTAssertEqual(AppName.arguments(from: ["app", "--opens-at-login", "--background"], opensAtLogin: true),
                       ["--background", "--opens-at-login"])
    }
}
