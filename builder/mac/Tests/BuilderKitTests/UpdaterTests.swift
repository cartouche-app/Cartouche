//
//  UpdaterTests.swift
//  BuilderKitTests
//
//  The app's updates (Updater.swift): which release of GitHub's it takes,
//  on which of GitHub's answers, the versions it compares, the SHA-256 it
//  checks, and the new app it accepts in place of its own. A copy updated
//  from end to end: UpdaterEndToEndTests.swift.
//

import Foundation
import XCTest
@testable import BuilderKit

/// GitHub's answers to the releases, a page each, as
/// BuilderReleases.newest(fetch:) reads them: the first at the address the
/// app asks for, answered from where GitHub sent it (ANSWERED FROM, once
/// the repository moved), each but the last with GitHub's Link header to
/// the next.
private final class ReleasePages {
    private var answers: [String: (Data, URLResponse)] = [:]
    private(set) var asked: [String] = []

    init(_ pages: [[[String: Any]]], answeredFrom: String? = nil) throws {
        let first = BuilderReleases.api.absoluteString
        let base = answeredFrom ?? first
        for (index, releases) in pages.enumerated() {
            let address = index == 0 ? base : base + "&page=\(index + 1)"
            var headers: [String: String] = [:]
            if index + 1 < pages.count {
                headers["Link"] = "<\(base)&page=\(index + 2)>; rel=\"next\", <\(base)&page=\(pages.count)>; rel=\"last\""
            }
            let response = HTTPURLResponse(url: URL(string: address)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            answers[index == 0 ? first : address] = (try JSONSerialization.data(withJSONObject: releases), response)
        }
    }

    func fetch(_ address: URL) async throws -> (Data, URLResponse) {
        asked.append(address.absoluteString)
        guard let answer = answers[address.absoluteString] else { throw URLError(.fileDoesNotExist) }
        return answer
    }
}

final class UpdaterTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, files: [String]? = nil,
                         host: String = "https://github.com/cartouche-app/Cartouche/releases/download",
                         page: String = "https://github.com/cartouche-app/Cartouche") -> [String: Any] {
        let version = tag.hasPrefix("builder-v") ? String(tag.dropFirst("builder-v".count)) : tag
        let names = files ?? ["Cartouche-Builder-\(version).dmg", "Cartouche-Builder-\(version).dmg.sha256"]
        return [
            "tag_name": tag,
            "draft": draft,
            "prerelease": prerelease,
            "body": "What \(tag) brings.",
            "html_url": "\(page)/releases/tag/\(tag)",
            "assets": names.map { ["name": $0, "browser_download_url": "\(host)/\(tag)/\($0)", "size": $0.hasSuffix(".dmg") ? 41_234_567 : 97] },
        ]
    }

    func testTheNewestReleaseIsTheBuildersWithItsImageAndChecksum() throws {
        let releases: [[String: Any]] = [
            release("builder-v0.3.0", draft: true),
            release("builder-v0.2.9", prerelease: true),
            release("v0.10.0", files: ["Cartouche-0.10.0.ipa"]),
            release("installer-v0.4.0", files: ["Cartouche-Installer-0.4.0-Mac.dmg"]),
            release("builder-v0.2.5", files: ["Cartouche-Builder-0.2.5.dmg"]),
            release("builder-v0.2.4", host: "https://example.com/clabeuhtegrite/Cartouche/releases/download"),
            release("builder-v0.2.3", host: "https://github.com/someone-else/Cartouche/releases/download"),
            release("builder-vnext"),
            release("builder-v0.2.1"),
            release("builder-v0.2.0"),
        ]
        let data = try JSONSerialization.data(withJSONObject: releases)
        let newest = try XCTUnwrap(try BuilderReleases.newest(in: data))
        XCTAssertEqual(newest.version, "0.2.1")
        XCTAssertEqual(newest.tag, "builder-v0.2.1")
        XCTAssertEqual(newest.notes, "What builder-v0.2.1 brings.")
        XCTAssertEqual(newest.size, 41_234_567)
        XCTAssertEqual(newest.image.lastPathComponent, "Cartouche-Builder-0.2.1.dmg")
        XCTAssertEqual(newest.checksum.lastPathComponent, "Cartouche-Builder-0.2.1.dmg.sha256")
        XCTAssertEqual(newest.page.absoluteString, "https://github.com/cartouche-app/Cartouche/releases/tag/builder-v0.2.1")

        XCTAssertNil(try BuilderReleases.newest(in: Data("[]".utf8)))
        XCTAssertThrowsError(try BuilderReleases.newest(in: Data("{\"message\": \"API rate limit exceeded\"}".utf8)))
    }

    func testAMovedRepositorysReleasesComeFromWhereGitHubAnswered() throws {
        // GitHub redirects the API of a repository that moved to an
        // organization, and its answer gives the new place's addresses.
        let moved = "https://github.com/new-owner/Cartouche/releases/download"
        let releases: [[String: Any]] = [
            release("builder-v0.4.0", host: "https://github.com/someone-else/Cartouche/releases/download"),
            release("builder-v0.3.0", host: moved),
            release("builder-v0.2.0"),
        ]
        let data = try JSONSerialization.data(withJSONObject: releases)
        XCTAssertEqual(try XCTUnwrap(try BuilderReleases.newest(in: data)).version, "0.2.0")

        let answering = BuilderReleases.answeringRepository(URL(string: "https://api.github.com/repos/new-owner/Cartouche/releases?per_page=40"))
        XCTAssertEqual(answering, "new-owner/Cartouche")
        let newest = try XCTUnwrap(try BuilderReleases.newest(in: data, answering: answering))
        XCTAssertEqual(newest.version, "0.3.0")
        XCTAssertEqual(newest.image.absoluteString, moved + "/builder-v0.3.0/Cartouche-Builder-0.3.0.dmg")

        XCTAssertEqual(BuilderReleases.answeringRepository(BuilderReleases.api), BuilderReleases.repository)
        for other in ["http://api.github.com/repos/a/b/releases", "https://example.com/repos/a/b/releases",
                      "https://api.github.com/repos/a/b/tags", "https://api.github.com/repos/a/releases"] {
            XCTAssertNil(BuilderReleases.answeringRepository(URL(string: other)), other)
        }
        XCTAssertNil(BuilderReleases.answeringRepository(nil))
    }

    func testARedirectToTheRepositorysNumberTakesTheRepositoryItsReleasesName() throws {
        // GitHub may send the API of a repository that moved to its number,
        // https://api.github.com/repositories/ID/releases, which names no
        // repository: its releases' pages name where it is now.
        let moved = "https://github.com/new-owner/Cartouche"
        let releases: [[String: Any]] = [
            release("builder-v0.3.0", host: moved + "/releases/download", page: moved),
            release("builder-v0.2.0", host: moved + "/releases/download", page: moved),
        ]
        let data = try JSONSerialization.data(withJSONObject: releases)
        let byNumber = URL(string: "https://api.github.com/repositories/123456789/releases?per_page=40")
        XCTAssertNil(BuilderReleases.answeringRepository(byNumber))
        XCTAssertNil(try BuilderReleases.newest(in: data, answering: BuilderReleases.answeringRepository(byNumber)))

        let answering = BuilderReleases.answeringRepository(byNumber, releases: data)
        XCTAssertEqual(answering, "new-owner/Cartouche")
        let newest = try XCTUnwrap(try BuilderReleases.newest(in: data, answering: answering))
        XCTAssertEqual(newest.version, "0.3.0")
        XCTAssertEqual(newest.image.absoluteString, moved + "/releases/download/builder-v0.3.0/Cartouche-Builder-0.3.0.dmg")
        XCTAssertEqual(BuilderReleases.answeringRepository(BuilderReleases.api, releases: data), BuilderReleases.repository)

        // Releases that name two repositories, or one of them none, name none.
        for other: [[String: Any]] in [
            [release("builder-v0.3.0", host: moved + "/releases/download", page: moved), release("builder-v0.2.0")],
            [release("builder-v0.3.0", host: moved + "/releases/download", page: moved),
             release("builder-v0.2.0", page: "https://example.com/new-owner/Cartouche")],
            [],
        ] {
            XCTAssertNil(BuilderReleases.answeringRepository(byNumber, releases: try JSONSerialization.data(withJSONObject: other)))
        }
        XCTAssertNil(BuilderReleases.answeringRepository(byNumber, releases: Data("{\"message\": \"Not Found\"}".utf8)))
        for other in ["https://api.github.com/repositories/12ab/releases", "https://api.github.com/repositories/123/tags",
                      "https://example.com/repositories/123/releases", "http://api.github.com/repositories/123/releases"] {
            XCTAssertNil(BuilderReleases.answeringRepository(URL(string: other), releases: data), other)
        }
    }

    /// Cartouche's releases and its Installer's, two at each of its
    /// versions, as many as GitHub gives in one answer.
    private func others(_ count: Int = BuilderReleases.perPage, page: String = "https://github.com/cartouche-app/Cartouche") -> [[String: Any]] {
        (0..<count).map { index in
            let version = "0.\(900 - index).0"
            return index.isMultiple(of: 2)
                ? release("v\(version)", prerelease: true, files: ["Cartouche-\(version).ipa"], host: page + "/releases/download", page: page)
                : release("installer-v\(version)", files: ["Cartouche-Installer-\(version)-Mac.dmg"], host: page + "/releases/download", page: page)
        }
    }

    func testTheBuildersNewestReleaseMayBeOnALaterAnswer() async throws {
        // Two answers full of Cartouche's releases and its Installer's
        // before the builder's: a copy that read the first alone found
        // none, and said it was up to date.
        let pages = try ReleasePages([others(), others(), [release("builder-v0.7.0"), release("v0.13.0", prerelease: true), release("builder-v0.6.0")]])
        let found = try await BuilderReleases.newest(fetch: pages.fetch)
        let newest = try XCTUnwrap(found)
        XCTAssertEqual(newest.version, "0.7.0")
        XCTAssertEqual(newest.image.absoluteString, "https://github.com/cartouche-app/Cartouche/releases/download/builder-v0.7.0/Cartouche-Builder-0.7.0.dmg")
        let api = BuilderReleases.api.absoluteString
        XCTAssertEqual(api, "https://api.github.com/repos/cartouche-app/Cartouche/releases?per_page=100")
        XCTAssertEqual(pages.asked, [api, api + "&page=2", api + "&page=3"])

        // The first answer that has the builder's ends the reading.
        let early = try ReleasePages([others(3) + [release("builder-v0.7.0")], others()])
        let first = try await BuilderReleases.newest(fetch: early.fetch)
        XCTAssertEqual(first?.version, "0.7.0")
        XCTAssertEqual(early.asked, [api])

        // A release of the builder's that is not one to take (a draft, a
        // pre-release, without its SHA-256) does not end it.
        let unfinished = try ReleasePages([[release("builder-v0.8.0", draft: true), release("builder-v0.7.1", files: ["Cartouche-Builder-0.7.1.dmg"])],
                                           [release("builder-v0.7.0")]])
        let taken = try await BuilderReleases.newest(fetch: unfinished.fetch)
        XCTAssertEqual(taken?.version, "0.7.0")
        XCTAssertEqual(unfinished.asked.count, 2)

        // At most `pages` answers, then none.
        let endless = try ReleasePages(Array(repeating: others(), count: BuilderReleases.pages + 2) + [[release("builder-v0.7.0")]])
        let none = try await BuilderReleases.newest(fetch: endless.fetch)
        XCTAssertNil(none)
        XCTAssertEqual(endless.asked.count, BuilderReleases.pages)

        // One answer, none of the builder's: none, and nothing more asked.
        let alone = try ReleasePages([others(5)])
        let nothing = try await BuilderReleases.newest(fetch: alone.fetch)
        XCTAssertNil(nothing)
        XCTAssertEqual(alone.asked, [api])
    }

    func testAMovedRepositorysLaterAnswersComeFromWhereGitHubAnswered() async throws {
        // The repository moved again: GitHub sends the app's address to the
        // repository's number, its answers name the new place, and the
        // next ones are at the number too. 0.5.0 and older, which took
        // disk images from their own repository's address alone, found none.
        let moved = "https://github.com/new-owner/Cartouche"
        let number = "https://api.github.com/repositories/123456789/releases?per_page=100"
        let pages = try ReleasePages([others(page: moved), [release("builder-v0.7.0", host: moved + "/releases/download", page: moved)]],
                                     answeredFrom: number)
        let found = try await BuilderReleases.newest(fetch: pages.fetch)
        let newest = try XCTUnwrap(found)
        XCTAssertEqual(newest.version, "0.7.0")
        XCTAssertEqual(newest.image.absoluteString, moved + "/releases/download/builder-v0.7.0/Cartouche-Builder-0.7.0.dmg")
        XCTAssertEqual(newest.checksum.absoluteString, moved + "/releases/download/builder-v0.7.0/Cartouche-Builder-0.7.0.dmg.sha256")
        XCTAssertEqual(pages.asked, [BuilderReleases.api.absoluteString, number + "&page=2"])

        // Disk images somewhere else than the repository asked for or the
        // one GitHub answered for are still never taken.
        let elsewhere = try ReleasePages([others(page: moved), [release("builder-v0.7.0", host: "https://github.com/someone-else/Cartouche/releases/download", page: moved)]],
                                         answeredFrom: number)
        let notTaken = try await BuilderReleases.newest(fetch: elsewhere.fetch)
        XCTAssertNil(notTaken)
    }

    func testTheNextAnswerIsGitHubsOwn() {
        let next = "https://api.github.com/repositories/123/releases?per_page=100&page=2"
        let last = "https://api.github.com/repositories/123/releases?per_page=100&page=4"
        XCTAssertEqual(BuilderReleases.nextPage("<\(next)>; rel=\"next\", <\(last)>; rel=\"last\"")?.absoluteString, next)
        XCTAssertEqual(BuilderReleases.nextPage("<\(last)>; rel=\"prev\",<\(next)>;rel=\"next\"")?.absoluteString, next)
        XCTAssertNil(BuilderReleases.nextPage(nil))
        XCTAssertNil(BuilderReleases.nextPage(""))
        XCTAssertNil(BuilderReleases.nextPage("<\(last)>; rel=\"prev\", <\(next)>; rel=\"first\""))
        XCTAssertNil(BuilderReleases.nextPage("\(next); rel=\"next\""))
        for elsewhere in ["http://api.github.com/a?page=2", "https://example.com/a?page=2", "https://api.github.com.example.com/a?page=2"] {
            XCTAssertNil(BuilderReleases.nextPage("<\(elsewhere)>; rel=\"next\""), elsewhere)
        }
    }

    func testVersions() {
        XCTAssertEqual(BuilderVersion.parts("0.2.0"), [0, 2, 0])
        XCTAssertEqual(BuilderVersion.parts("26"), [26])
        for odd in ["", "v0.2", "0..2", "0.2.", "1.2.3.4.5", "0.2-beta", "１.２"] {
            XCTAssertNil(BuilderVersion.parts(odd), odd)
        }
        XCTAssertTrue(BuilderVersion.isHigher("0.10.0", than: "0.9.9"))
        XCTAssertTrue(BuilderVersion.isHigher("0.2.1", than: "0.2"))
        XCTAssertFalse(BuilderVersion.isHigher("0.2", than: "0.2.0"))
        XCTAssertFalse(BuilderVersion.isHigher("0.2.0", than: "0.2.1"))
        XCTAssertFalse(BuilderVersion.isHigher("next", than: "0.2.0"))
    }

    func testChecksums() throws {
        let sum = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        XCTAssertEqual(BuilderReleases.checksum(in: "\(sum)  Cartouche-Builder-0.2.1.dmg\n"), sum.lowercased())
        XCTAssertNil(BuilderReleases.checksum(in: ""))
        XCTAssertNil(BuilderReleases.checksum(in: "ba7816bf  Cartouche-Builder-0.2.1.dmg"))
        XCTAssertNil(BuilderReleases.checksum(in: String(repeating: "z", count: 64)))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("Cartouche-Builder-0.2.1.dmg")
        try Data("abc".utf8).write(to: image)
        XCTAssertEqual(try Updater.sha256(of: image), sum.lowercased())
        try Data("\(sum)  Cartouche-Builder-0.2.1.dmg\n".utf8).write(to: image.appendingPathExtension("sha256"))
        XCTAssertTrue(try Updater.verify(image))
        try Data("abd".utf8).write(to: image)
        XCTAssertFalse(try Updater.verify(image))
    }

    func testTheNewAppMustBeCartoucheBuilderAtTheReleasesVersion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func app(_ info: [String: Any]) throws -> URL {
            let app = folder.appendingPathComponent(UUID().uuidString + ".app", isDirectory: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
            return app
        }
        let identifier = "io.github.clabeuhtegrite.cartouche-builder"
        let good = try app(["CFBundleIdentifier": identifier, "CFBundleShortVersionString": "0.2.1", "LSMinimumSystemVersion": "26.0"])
        XCTAssertNoThrow(try Updater.check(good, version: "0.2.1", identifier: identifier))
        XCTAssertThrowsError(try Updater.check(good, version: "0.2.2", identifier: identifier))
        let other = try app(["CFBundleIdentifier": "com.example.other", "CFBundleShortVersionString": "0.2.1"])
        XCTAssertThrowsError(try Updater.check(other, version: "0.2.1", identifier: identifier))
        let later = try app(["CFBundleIdentifier": identifier, "CFBundleShortVersionString": "0.2.1", "LSMinimumSystemVersion": "99.0"])
        XCTAssertThrowsError(try Updater.check(later, version: "0.2.1", identifier: identifier))
        XCTAssertThrowsError(try Updater.check(folder.appendingPathComponent("Missing.app"), version: "0.2.1", identifier: identifier))
    }

    @MainActor
    func testAnUpdateWaitsForTheBuildAndForTheApplicationsFolder() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let release = BuilderRelease(version: "0.2.1", tag: "builder-v0.2.1", notes: "", page: URL(string: "https://github.com/")!,
                                     image: URL(string: "https://github.com/a.dmg")!, checksum: URL(string: "https://github.com/a.dmg.sha256")!, size: 1)
        let fromImage = Updater(app: URL(fileURLWithPath: "/Volumes/Cartouche Builder/Cartouche Builder.app"), version: "0.2.0",
                                identifier: Updater.identifier, folder: folder, enabled: true)
        XCTAssertTrue(fromImage.runsFromDiskImage)
        fromImage.preview(.ready(release))
        XCTAssertFalse(fromImage.installsAtQuit)

        let installed = Updater(app: folder.appendingPathComponent("Cartouche Builder.app"), version: "0.2.0",
                                identifier: Updater.identifier, folder: folder, enabled: true)
        XCTAssertFalse(installed.runsFromDiskImage)
        XCTAssertFalse(installed.installsAtQuit)
        installed.preview(.ready(release))
        XCTAssertTrue(installed.isReady)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(installed.installsAtQuit)
        var building = true
        installed.isBuilding = { building }
        XCTAssertFalse(installed.installsAtQuit)
        building = false
        XCTAssertTrue(installed.installsAtQuit)

        let fromTerminal = Updater(app: URL(fileURLWithPath: "/Volumes/x/python3"), version: "0.2.0", identifier: "", folder: folder, enabled: false)
        XCTAssertFalse(fromTerminal.runsFromDiskImage)
    }
}
