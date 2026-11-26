//
//  SignerTests.swift
//  BuilderKitTests
//
//  The app's side of cartouche-signer (Signer.swift), against a helper of
//  the tests' own that answers as the real one does (its own tests:
//  builder/mac/signer/tests): the iPhones and their copies of Cartouche, a
//  renewal, an install over Cartouche and its progress, each failure by its
//  kind, and a sign-in whose password goes to the helper's input alone,
//  then a code.
//

import Foundation
import XCTest
@testable import BuilderKit

final class SignerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SignerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A helper that runs SCRIPT, its arguments in "$@", and writes them in
    /// arguments.txt.
    private func helper(_ script: String) throws -> Signer {
        let url = folder.appendingPathComponent("cartouche-signer")
        let text = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(folder.path)/arguments.txt'\n" + script + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return Signer(helper: url, folder: folder.appendingPathComponent("Signer"))
    }

    private func arguments() throws -> [String] {
        try String(contentsOf: folder.appendingPathComponent("arguments.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    func testTheIphonesAndUntilWhenCartoucheOpens() async throws {
        let signer = try helper("""
        echo '{"event":"something the app does not know"}'
        echo '{"result":{"iphones":[{"udid":"00008150-001A2B3C4D5E6F01","name":"iPhone de Camille","ios":"26.1","link":"usb","cartouche":[{"bundleId":"io.github.clabeuhtegrite.cartouche.ABCDE12345","version":"0.16.2","teamId":"ABCDE12345","expires":"2026-12-03T09:41:00Z","due":"not-yet","from":"2026-12-01T09:41:00Z"}]},{"udid":"00008150-001A2B3C4D5E6F02","link":"network","cartouche":[],"error":{"kind":"iphone-refused","stage":"iphone","message":"locked"}}]}}'
        """)
        let iphones = try await signer.devices()
        XCTAssertEqual(try arguments(), ["--folder", signer.folder.path, "devices"])
        XCTAssertEqual(iphones.count, 2)
        XCTAssertEqual(iphones[0].name, "iPhone de Camille")
        XCTAssertEqual(iphones[0].link, "usb")
        let copy = try XCTUnwrap(iphones[0].cartouche.first)
        XCTAssertEqual(copy.teamId, "ABCDE12345")
        XCTAssertEqual(copy.due, "not-yet")
        XCTAssertEqual(copy.expires, ISO8601DateFormatter().date(from: "2026-12-03T09:41:00Z"))
        XCTAssertEqual(iphones[1].error?.kind, "iphone-refused")
        XCTAssertTrue(iphones[1].error?.iphoneAway ?? false)
    }

    func testARenewal() async throws {
        let signer = try helper("""
        echo '{"result":{"renewed":true,"bundleId":"io.github.clabeuhtegrite.cartouche.ABCDE12345","before":"2026-11-27T08:00:00Z","expires":"2026-12-03T09:41:00Z","due":"now","registeredAppId":false,"refreshedSession":true,"recorded":true,"link":"usb","seconds":3.2}}'
        """)
        let renewal = try await signer.renew(udid: "00008150-001A2B3C4D5E6F01", onlyIfDue: true)
        XCTAssertEqual(try arguments(), ["--folder", signer.folder.path, "renew", "--udid", "00008150-001A2B3C4D5E6F01", "--if-due"])
        XCTAssertTrue(renewal.renewed)
        XCTAssertEqual(renewal.due, "now")
        XCTAssertTrue(renewal.refreshedSession)
        XCTAssertEqual(renewal.seconds, 3.2, accuracy: 0.001)
        _ = try await signer.renew(udid: "X", onlyIfDue: false)
        XCTAssertEqual(try arguments(), ["--folder", signer.folder.path, "renew", "--udid", "X"])
    }

    func testAnInstallOverCartoucheWithItsProgress() async throws {
        let signer = try helper("""
        echo '{"event":"progress","step":"download","fraction":0}'
        echo '{"event":"progress","step":"download","fraction":0.5}'
        echo '{"event":"something the app does not know"}'
        echo '{"event":"progress","step":"sign","fraction":1}'
        echo '{"event":"progress","step":"install","fraction":0.25}'
        echo '{"result":{"reinstalled":true,"bundleId":"io.github.clabeuhtegrite.cartouche.ABCDE12345","version":"0.16.3","previousVersion":"0.16.2","before":"2026-11-30T08:00:00Z","expires":"2026-12-08T09:41:00Z","due":"expired","refreshedSession":false,"link":"usb","seconds":52.4}}'
        """)
        let steps = Steps()
        let done = try await signer.reinstall(udid: "00008150-001A2B3C4D5E6F01") { steps.append($0) }
        XCTAssertEqual(try arguments(), ["--folder", signer.folder.path, "reinstall", "--udid", "00008150-001A2B3C4D5E6F01"])
        XCTAssertTrue(done.reinstalled)
        XCTAssertEqual(done.version, "0.16.3")
        XCTAssertTrue(done.updated)
        XCTAssertEqual(done.due, "expired")
        XCTAssertEqual(done.expires, ISO8601DateFormatter().date(from: "2026-12-08T09:41:00Z"))
        XCTAssertEqual(steps.all, [SignerProgress(step: "download", fraction: 0), SignerProgress(step: "download", fraction: 0.5),
                                   SignerProgress(step: "sign", fraction: 1), SignerProgress(step: "install", fraction: 0.25)])
        // An account with as many certificates as Apple allows: said, and
        // nothing installed.
        let full = try helper("""
        echo '{"event":"progress","step":"download","fraction":1}'
        echo '{"error":{"kind":"no-certificate-left","stage":"apple","code":7460,"message":"Maximum number of certificates reached"}}'
        exit 1
        """)
        do {
            _ = try await full.reinstall(udid: "X") { _ in }
            XCTFail("installed")
        } catch let failure as SignerFailure {
            XCTAssertEqual(failure.kind, "no-certificate-left")
            XCTAssertEqual(failure.code, 7460)
        }
    }

    func testEachFailureByItsKind() async throws {
        let signer = try helper("""
        echo '{"error":{"kind":"session-ended","stage":"session","code":-22406,"message":"Your session has expired."}}'
        exit 1
        """)
        do {
            _ = try await signer.renew(udid: "X", onlyIfDue: true)
            XCTFail("no failure")
        } catch let failure as SignerFailure {
            XCTAssertEqual(failure.kind, "session-ended")
            XCTAssertEqual(failure.code, -22406)
            XCTAssertTrue(failure.needsPassword)
            XCTAssertFalse(failure.needsInstall)
        }
        let gone = SignerFailure(kind: "certificate-gone", stage: "apple", message: "")
        XCTAssertTrue(gone.needsInstall)
        XCTAssertFalse(gone.needsPassword)
    }

    func testAHelperThatSaysNothingOrNonsense() async throws {
        let silent = try helper("exit 0")
        do {
            _ = try await silent.session()
            XCTFail("no failure")
        } catch let failure as SignerFailure {
            XCTAssertEqual(failure.kind, "internal")
        }
        let nonsense = try helper("echo 'not JSON'")
        do {
            _ = try await nonsense.session()
            XCTFail("no failure")
        } catch let failure as SignerFailure {
            XCTAssertEqual(failure.kind, "internal")
        }
    }

    func testASignInSendsThePasswordToTheHelperAloneThenACode() async throws {
        let signer = try helper("""
        echo '{"event":"password"}'
        read -r password
        printf '%s\\n' "$password" > '\(folder.path)/password.txt'
        echo '{"event":"code","bySms":false,"lastError":null,"numbers":[{"id":1,"number":"+33 •• •• •• •• 42","lastTwoDigits":"42"}],"selectedNumber":null}'
        read -r code
        printf '%s\\n' "$code" > '\(folder.path)/code.txt'
        echo '{"result":{"signedIn":true,"email":"camille@example.com","teamId":"ABCDE12345","teamName":"Camille Testeur","since":"2026-11-26T14:00:00Z","refreshed":null}}'
        """)
        let asked = Requests()
        let session = try await signer.signIn(email: "camille@example.com", password: "Correct \"Horse\" 7") { request in
            asked.append(request)
            return .code("246810")
        }
        XCTAssertTrue(session.signedIn)
        XCTAssertEqual(session.teamId, "ABCDE12345")
        XCTAssertEqual(try arguments(), ["--folder", signer.folder.path, "sign-in", "--email", "camille@example.com"])
        // The password, as JSON on the input, and not in the arguments.
        let sent = try Data(contentsOf: folder.appendingPathComponent("password.txt"))
        let password = try JSONSerialization.jsonObject(with: sent) as? [String: String]
        XCTAssertEqual(password, ["password": "Correct \"Horse\" 7"])
        let code = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("code.txt"))) as? [String: String]
        XCTAssertEqual(code, ["code": "246810"])
        XCTAssertEqual(asked.all.count, 1)
        XCTAssertEqual(asked.all.first?.numbers.first?.lastTwoDigits, "42")
    }

    func testASignInThePlayerCloses() async throws {
        let signer = try helper("""
        echo '{"event":"password"}'
        read -r password
        echo '{"event":"code","bySms":false,"numbers":[]}'
        read -r code
        case "$code" in *cancel*) echo '{"error":{"kind":"cancelled","stage":"session","message":"No 2FA code provided"}}'; exit 1;; esac
        echo '{"result":{"signedIn":true}}'
        """)
        do {
            _ = try await signer.signIn(email: "camille@example.com", password: "x") { _ in .cancel }
            XCTFail("signed in")
        } catch let failure as SignerFailure {
            XCTAssertEqual(failure.kind, "cancelled")
        }
    }

    func testTheSignersFolderIsTheBuildersOwn() {
        let home = BuilderHome(URL(fileURLWithPath: "/tmp/Cartouche Builder"))
        XCTAssertEqual(home.signer.path, "/tmp/Cartouche Builder/Signer")
        // The tests' process carries no helper: the app says so, and runs none.
        if ProcessInfo.processInfo.environment["CARTOUCHE_SIGNER"] == nil {
            XCTAssertNil(Signer.bundled(home: home))
        }
    }
}

/// The steps an install went through, from the helper's thread.
private final class Steps: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [SignerProgress] = []

    func append(_ step: SignerProgress) {
        lock.lock()
        steps.append(step)
        lock.unlock()
    }

    var all: [SignerProgress] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

/// The code requests a sign-in made, from the helper's thread.
private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SignerCodeRequest] = []

    func append(_ request: SignerCodeRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    var all: [SignerCodeRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
