//
//  UpdaterEndToEndTests.swift
//  BuilderKitTests
//
//  A copy of Cartouche Builder already installed updates itself, as on a
//  player's Mac (Updater.swift): it reads GitHub's releases an answer at a
//  time, a first answer full of Cartouche's releases and its Installer's,
//  finds the builder's newest on the next, downloads its disk image and its
//  SHA-256, checks them, mounts the image out of sight, checks the app in
//  it and puts it in place of its own, the new app's signature intact, with
//  nothing left beside it. GitHub is the tests' own (FakeGitHub, in a
//  URLSession of the tests'); the rest is this Mac's: hdiutil, codesign,
//  ditto.
//
//  With CARTOUCHE_BUILDER_DMG naming the disk image the Builder workflow
//  made (Cartouche-Builder-<version>.dmg), that image is the update, and a
//  copy of an older version must take it: what the workflow publishes is
//  what the copies already installed take. Skipped without it.
//

import Foundation
import XCTest
@testable import BuilderKit

/// GitHub as the updater reaches it, in a session of the tests' own: each
/// address answers what `serve` gave it, any other GitHub's 404.
final class FakeGitHub: URLProtocol {
    struct Answer {
        var body: Data
        var headers: [String: String] = [:]
        var status = 200
    }

    private static let lock = NSLock()
    private static var answers: [String: Answer] = [:]
    private static var asked: [String] = []

    /// GIVEN, by address, from now on.
    static func serve(_ given: [String: Answer]) {
        lock.lock()
        answers = given
        asked = []
        lock.unlock()
    }

    /// The addresses asked since `serve`, in order.
    static var addresses: [String] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeGitHub.self]
        return URLSession(configuration: configuration)
    }

    private static func answer(_ address: String) -> Answer {
        lock.lock()
        defer { lock.unlock() }
        asked.append(address)
        return answers[address] ?? Answer(body: Data(#"{"message": "Not Found"}"#.utf8), status: 404)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client = client else { return }
        let answer = Self.answer(url.absoluteString)
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: answer.body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UpdaterEndToEndTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cartouche-update-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        FakeGitHub.serve([:])
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: The tests

    @MainActor
    func testAnInstalledBuilderFindsItsUpdateOnALaterAnswerAndPutsItInPlace() async throws {
        let new = try await makeApp("0.9.1", in: "new")
        let image = try await makeImage(of: new, version: "0.9.1")
        let installed = try await makeApp("0.9.0", in: "Applications")
        try await update(installed, from: "0.9.0", with: image, version: "0.9.1")
    }

    @MainActor
    func testTheDiskImageTheWorkflowMadeUpdatesAnInstalledBuilder() async throws {
        guard let path = ProcessInfo.processInfo.environment["CARTOUCHE_BUILDER_DMG"], !path.isEmpty else {
            throw XCTSkip("CARTOUCHE_BUILDER_DMG names no disk image: the Builder workflow names the one it made")
        }
        let image = URL(fileURLWithPath: path)
        let name = image.lastPathComponent
        let prefix = "Cartouche-Builder-"
        let suffix = ".dmg"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else {
            return XCTFail("\(name) is not named as the copies already installed look for it, \(BuilderReleases.imageName("<version>"))")
        }
        let version = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        XCTAssertNotNil(BuilderVersion.parts(version), "\(version) is not a version the copies already installed compare")
        XCTAssertEqual(BuilderReleases.imageName(version), name)
        let installed = try await makeApp("0.0.1", in: "Applications")
        try await update(installed, from: "0.0.1", with: image, version: version)
    }

    // MARK: The update

    /// INSTALLED, a copy of the builder at OLD, updates itself to IMAGE,
    /// the disk image of VERSION, from GitHub's releases, and is VERSION
    /// after, its signature intact.
    @MainActor
    private func update(_ installed: URL, from old: String, with image: URL, version: String) async throws {
        try serve(image: image, version: version, old: old)
        let updates = folder.appendingPathComponent("Updates", isDirectory: true)
        let updater = Updater(app: installed, version: old, identifier: Updater.identifier, folder: updates, enabled: true,
                              session: FakeGitHub.session())
        XCTAssertFalse(updater.runsFromDiskImage)
        XCTAssertTrue(updater.installsWithoutPassword)

        await updater.check(force: true)
        guard case let .ready(release) = updater.state else {
            return XCTFail("the update is not ready: \(updater.state), GitHub asked for \(FakeGitHub.addresses)")
        }
        XCTAssertEqual(release.version, version)
        XCTAssertEqual(release.tag, BuilderReleases.tagPrefix + version)
        let api = BuilderReleases.api.absoluteString
        XCTAssertEqual(Array(FakeGitHub.addresses.prefix(2)), [api, api + "&page=2"])
        XCTAssertTrue(updater.installsAtQuit)

        let done = await updater.install(relaunch: false)
        XCTAssertTrue(done, "the update did not go in place: \(updater.state)")
        let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, Updater.identifier)
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, version)
        try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", installed.path])
        // Neither the copy staged beside the app nor the one it replaced is
        // left, nor the disk image downloaded.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path),
                       [installed.lastPathComponent])
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: updates.path)) ?? [], [])
    }

    /// What GitHub answers of the releases: a first answer full of
    /// Cartouche's releases and its Installer's, as at each of its
    /// versions, then the builder's VERSION and OLD; and VERSION's disk
    /// image, IMAGE, and its SHA-256, at their addresses.
    @MainActor
    private func serve(image: URL, version: String, old: String) throws {
        let repository = "https://github.com/\(BuilderReleases.repository)"
        func release(_ tag: String, prerelease: Bool = false, files: [String: Int]) -> [String: Any] {
            [
                "tag_name": tag,
                "draft": false,
                "prerelease": prerelease,
                "body": "What \(tag) brings.",
                "html_url": "\(repository)/releases/tag/\(tag)",
                "assets": files.sorted { $0.key < $1.key }.map { name, size -> [String: Any] in
                    ["name": name, "browser_download_url": "\(repository)/releases/download/\(tag)/\(name)", "size": size]
                },
            ]
        }
        let others = (0..<BuilderReleases.perPage).map { index -> [String: Any] in
            let cartouche = "0.\(900 - index).0"
            return index.isMultiple(of: 2)
                ? release("v\(cartouche)", prerelease: true, files: ["Cartouche-\(cartouche).ipa": 36_636_781])
                : release("installer-v\(cartouche)", files: ["Cartouche-Installer-\(cartouche)-Mac.dmg": 9_000_000])
        }
        let name = BuilderReleases.imageName(version)
        let size = try image.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let builder = [
            release(BuilderReleases.tagPrefix + version, files: [name: size, name + ".sha256": 94]),
            release(BuilderReleases.tagPrefix + old, files: [BuilderReleases.imageName(old): 1, BuilderReleases.imageName(old) + ".sha256": 94]),
        ]
        let first = BuilderReleases.api.absoluteString
        let second = first + "&page=2"
        let download = "\(repository)/releases/download/\(BuilderReleases.tagPrefix + version)/\(name)"
        let sum = try Updater.sha256(of: image)
        FakeGitHub.serve([
            first: .init(body: try JSONSerialization.data(withJSONObject: others),
                         headers: ["Link": "<\(second)>; rel=\"next\", <\(second)>; rel=\"last\""]),
            second: .init(body: try JSONSerialization.data(withJSONObject: builder),
                          headers: ["Link": "<\(first)&page=1>; rel=\"prev\", <\(first)&page=1>; rel=\"first\""]),
            download: .init(body: try Data(contentsOf: image)),
            download + ".sha256": .init(body: Data("\(sum)  \(name)\n".utf8)),
        ])
    }

    // MARK: Apps and disk images

    /// A copy of Cartouche Builder at VERSION, alone in the folder NAME of
    /// this test's: an app whose program is macOS's `true`, signed ad hoc
    /// as bundle.sh signs the builder.
    @MainActor
    private func makeApp(_ version: String, in name: String) async throws -> URL {
        let app = folder.appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("Cartouche Builder.app", isDirectory: true)
        let program = app.appendingPathComponent("Contents/MacOS/Cartouche Builder")
        try FileManager.default.createDirectory(at: program.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: program)
        let info: [String: Any] = [
            "CFBundleIdentifier": Updater.identifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "CFBundleExecutable": "Cartouche Builder",
            "CFBundleName": "Cartouche Builder",
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try await run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    /// The disk image of APP, the app at its root as make_dmg.sh has the
    /// builder's, under the name its release gives it. hdiutil is sometimes
    /// busy on a CI Mac: three tries.
    @MainActor
    private func makeImage(of app: URL, version: String) async throws -> URL {
        let image = folder.appendingPathComponent(BuilderReleases.imageName(version))
        let arguments = ["create", "-quiet", "-srcfolder", app.deletingLastPathComponent().path, "-volname", "Cartouche Builder",
                         "-fs", "HFS+", "-format", "UDZO", "-ov", image.path]
        var last = ""
        for attempt in 1...3 {
            let made = try await Run.program("/usr/bin/hdiutil", arguments, timeout: 300)
            if made.succeeded { return image }
            last = made.tail(4)
            if attempt < 3 { try await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        throw UpdateError("hdiutil create: \(last)")
    }

    @MainActor
    @discardableResult
    private func run(_ program: String, _ arguments: [String]) async throws -> RunResult {
        let result = try await Run.program(program, arguments, timeout: 300)
        guard result.succeeded else {
            throw UpdateError("\(program) \(arguments.joined(separator: " ")): \(result.tail(6))")
        }
        return result
    }
}
