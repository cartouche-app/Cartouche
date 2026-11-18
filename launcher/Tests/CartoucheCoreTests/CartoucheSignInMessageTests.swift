import XCTest
@testable import CartoucheCore

final class CartoucheSignInMessageTests: XCTestCase {
    func testCredentialsAreWhatSideStoreReads() throws {
        let data = CartoucheSignInMessage.credentials(appleID: "  player@example.com\n", password: " secret ")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(fields, ["appleID": "player@example.com", "password": " secret "])
    }

    func testARequestFromSideStore() throws {
        let data = Data(#"{"id":"A","mode":"sms","phone":"+33 •• •• •• •• 12","canTextMessage":false,"error":"Incorrect code"}"#.utf8)
        let request = try XCTUnwrap(CartoucheSignInMessage.request(from: data))
        XCTAssertEqual(request, .init(id: "A", mode: .sms, phone: "+33 •• •• •• •• 12", canTextMessage: false, error: "Incorrect code"))
    }

    func testATrustedDeviceRequestWithoutPhoneOrError() throws {
        let data = Data(#"{"id":"B","mode":"trustedDevice","canTextMessage":true,"error":""}"#.utf8)
        let request = try XCTUnwrap(CartoucheSignInMessage.request(from: data))
        XCTAssertEqual(request, .init(id: "B", mode: .trustedDevice, phone: nil, canTextMessage: true, error: nil))
    }

    func testWhatIsNotARequest() {
        XCTAssertNil(CartoucheSignInMessage.request(from: Data("{}".utf8)))
        XCTAssertNil(CartoucheSignInMessage.request(from: Data(#"{"id":"C","mode":"pigeon"}"#.utf8)))
        XCTAssertNil(CartoucheSignInMessage.request(from: Data(#"{"id":"","mode":"sms"}"#.utf8)))
        XCTAssertNil(CartoucheSignInMessage.request(from: Data("not json".utf8)))
    }

    func testResponses() throws {
        func fields(_ answer: CartoucheSignInMessage.Answer) throws -> [String: String] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: CartoucheSignInMessage.response(to: "A", answer)) as? [String: String])
        }
        XCTAssertEqual(try fields(.code("123456")), ["id": "A", "code": "123456"])
        XCTAssertEqual(try fields(.textMessage), ["id": "A", "action": "sms"])
        XCTAssertEqual(try fields(.trustedDevice), ["id": "A", "action": "trustedDevice"])
        XCTAssertEqual(try fields(.cancel), ["id": "A", "action": "cancel"])
    }

    func testCodes() {
        XCTAssertEqual(CartoucheSignInMessage.code(from: "123456"), "123456")
        XCTAssertEqual(CartoucheSignInMessage.code(from: "123 456"), "123456")
        XCTAssertNil(CartoucheSignInMessage.code(from: "12345"))
        XCTAssertNil(CartoucheSignInMessage.code(from: "1234567"))
        XCTAssertNil(CartoucheSignInMessage.code(from: "١٢٣٤٥٦"))
    }

    func testWhatCanBeSent() {
        XCTAssertTrue(CartoucheSignInMessage.canSignIn(appleID: "player@example.com", password: "x"))
        XCTAssertTrue(CartoucheSignInMessage.canSignIn(appleID: "+33 6 12 34 56 78".replacingOccurrences(of: " ", with: ""), password: "x"))
        XCTAssertFalse(CartoucheSignInMessage.canSignIn(appleID: "player@example.com", password: ""))
        XCTAssertFalse(CartoucheSignInMessage.canSignIn(appleID: "player", password: "x"))
        XCTAssertFalse(CartoucheSignInMessage.canSignIn(appleID: "pla yer@example.com", password: "x"))
    }

    func testTheLinkInAnError() {
        let message = "Apple asks you to review your account.\n\nhttps://appleid.apple.com/account/manage"
        XCTAssertEqual(CartoucheSignInMessage.link(in: message), URL(string: "https://appleid.apple.com/account/manage"))
        XCTAssertNil(CartoucheSignInMessage.link(in: "The password is incorrect."))
    }

    func testTheIntentErrorNameGoes() {
        XCTAssertEqual(CartoucheSignInMessage.readable("LNPerformActionErrorCodeLocalizedStringResource: This Apple account already has a certificate."),
                       "This Apple account already has a certificate.")
        XCTAssertEqual(CartoucheSignInMessage.readable("The password is incorrect: try again."), "The password is incorrect: try again.")
        XCTAssertEqual(CartoucheSignInMessage.readable("LNPerform Action: no"), "LNPerform Action: no")
    }

    // MARK: Apple's pages and limits

    private let page = "Invalid server response: unparseable format\n<html>\n<head><title>429 Too Many Requests</title></head>\n"
        + "<body>\n<center><h1>429 Too Many Requests</h1></center>\n<hr><center>Apple</center>\n</body>\n</html>"

    func testApplesPageAndItsStatus() {
        XCTAssertTrue(CartoucheSignInMessage.hasPage(page))
        XCTAssertEqual(CartoucheSignInMessage.pageStatus(in: page), 429)
        XCTAssertEqual(CartoucheSignInMessage.pageStatus(in: "<!DOCTYPE html><html><head><TITLE>503 Service Unavailable</TITLE>"), 503)
        XCTAssertEqual(CartoucheSignInMessage.pageStatus(in: "<html><body><h1 class=\"x\">502 Bad Gateway</h1></body></html>"), 502)
        XCTAssertNil(CartoucheSignInMessage.pageStatus(in: "<html><head><title>Apple</title></head></html>"))
        XCTAssertNil(CartoucheSignInMessage.pageStatus(in: "<html><head><title>4290 things</title></head></html>"))
        XCTAssertNil(CartoucheSignInMessage.pageStatus(in: "Error 429: too many requests"))
        XCTAssertFalse(CartoucheSignInMessage.hasPage("Your Apple ID or password is incorrect."))
    }

    func testTheTroubleCartoucheTellsInItsOwnWords() {
        let none = CartoucheFailure(.appleServer, details: ["kind": .text("underlyingError")])
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: page, failure: none), .tooManyRequests)
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "Too many codes", failure: CartoucheFailure(.tooManyAttempts)), .tooManyRequests)
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "Apple refuses more requests for now (HTTP 429).",
                                                      failure: CartoucheFailure(.appleServer, details: ["http": .number(429)])),
                       .tooManyRequests)
        let unavailable = CartoucheFailure(.appleServer, details: ["kind": .text("httpStatus"), "http": .number(503)])
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "Apple Developer Portal is temporarily unavailable (HTTP 503)",
                                                      failure: unavailable), .unreadable(status: 503))
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: page.replacingOccurrences(of: "429 Too Many Requests", with: "403 Forbidden"),
                                                      failure: none), .unreadable(status: 403))
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "Invalid server response: unparseable format\n3c3f786d6c",
                                                      failure: CartoucheFailure(.appleServer, details: ["kind": .text("invalidResponseFormat")])),
                       .unreadable(status: nil))
        XCTAssertNil(CartoucheSignInMessage.trouble(in: "Your Apple ID or password is incorrect.",
                                                    failure: CartoucheFailure(.appleCredentials, details: ["kind": .text("incorrectCredentials")])))
        // The built-in SideStore closed before it finished, as it launched or
        // on its way: LiveContainer's English words say nothing of what to do.
        for message in ["Built-in SideStore quit unexpectedly while starting", "Built-in SideStore quit unexpectedly"] {
            let quit = CartoucheFailure.sideStore(outcome: nil, message: message, fraction: 0, seconds: 1, vpn: true, pairing: true)
            XCTAssertEqual(CartoucheSignInMessage.trouble(in: message, failure: quit), .sideStoreQuit, message)
        }
        // The built-in SideStore found no app group, as when a signing app
        // signed the IPA for an Apple ID: its database's error as it starts,
        // or its operations', whose words say nothing of the IPA to sign.
        for (family, stage, message) in [("database", "database", "App Group Container Inaccessible"),
                                         ("operation", "ClearAppCache", "SideStore's shared app group could not be accessed.")] {
            let noGroup = sideStoreFailure(["stage": stage, "family": family, "kind": "missingAppGroup"], message: message)
            XCTAssertEqual(CartoucheSignInMessage.trouble(in: message, failure: noGroup), .noAppGroup, family)
        }
        // Apple's portal refusing an app group of the account is another
        // matter.
        XCTAssertNil(CartoucheSignInMessage.trouble(in: "The app group does not exist.",
                                                    failure: CartoucheFailure(.appGroup, details: ["kind": .text("appGroupDoesNotExist")])))
        // The Apple ID already has a certificate the built-in SideStore does
        // not hold, which it never revokes: its words are in English, and
        // end with the certificates' serial numbers.
        let certificate = "This Apple account already has a certificate, which signs the apps installed with it."
        let other = sideStoreFailure(["stage": "certificate", "family": "operation", "kind": "forbidden"], message: certificate)
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: certificate, failure: other), .otherCertificate)
        // SideStore's forbidden at another step is not that.
        let elsewhere = sideStoreFailure(["stage": "ResignApp", "family": "operation", "kind": "forbidden"], message: "Forbidden")
        XCTAssertNil(CartoucheSignInMessage.trouble(in: "Forbidden", failure: elsewhere))
        // LiveProcess, which the built-in SideStore runs in, is not in the
        // app: LiveContainer's bridge cannot start it, and its English words
        // send the player to the settings of other sideloaders.
        let noLiveProcess = "Unable to locate LiveProcess bundle. To use the Refresh All Apps shortcut, reinstall "
            + "LiveContainer+SideStore with LiveProcess installed."
        let missing = CartoucheFailure.sideStore(outcome: nil, message: noLiveProcess, fraction: 0, seconds: 0, vpn: true, pairing: true)
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: noLiveProcess, failure: missing), .noLiveProcess)
        // LiveProcess there, refusing to start, is not that.
        let refusing = "Failed to start extension Error Domain=NSCocoaErrorDomain Code=4099"
        let failed = CartoucheFailure.sideStore(outcome: nil, message: refusing, fraction: 0, seconds: 0, vpn: true, pairing: true)
        XCTAssertNil(CartoucheSignInMessage.trouble(in: refusing, failure: failed))
    }

    func testApplesRefusalsThatSideStorePassesOnInEnglish() {
        // Apple refusing a new machine for the sign-in, before the Apple ID
        // went to it (app/patches/sidestore/0024): AnisetteKit's words name
        // the endpoint, at whichever step of the provisioning it was.
        for (status, step, message) in [(401, "finish", "HTTP error (401): Apple PTM/TK endpoint returned HTTP 401"),
                                        (403, "lookup", "HTTP error (403): Apple lookup endpoint returned HTTP 403")] {
            let refused = sideStoreFailure(["stage": "account", "family": "provisioning", "kind": "httpError", "http": status,
                                            "service": "provisioning", "reason": step, "codes": "AnisetteKit.AnisetteError 5"],
                                           message: message)
            let trouble = CartoucheSignInMessage.trouble(in: message, failure: refused)
            XCTAssertEqual(trouble, .provisioningRefused(status: status), message)
            XCTAssertTrue(CartoucheSignInMessage.pausesSignIns(trouble), message)
        }
        // Its 429 is Apple's limit, as for the sign-in.
        let limited = sideStoreFailure(["stage": "account", "family": "provisioning", "kind": "httpError", "http": 429,
                                        "service": "provisioning", "reason": "start"],
                                       message: "HTTP error (429): Apple SPIM endpoint returned HTTP 429")
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "HTTP error (429): Apple SPIM endpoint returned HTTP 429", failure: limited),
                       .tooManyRequests)
        // An error of its servers, or an answer that could not be read, is
        // no refusal: no wait, the words of Apple's answers that could not be
        // read.
        let unavailable = sideStoreFailure(["stage": "account", "family": "provisioning", "kind": "httpError", "http": 503,
                                            "service": "provisioning", "reason": "start"],
                                           message: "HTTP error (503): Apple SPIM endpoint returned HTTP 503")
        let down = CartoucheSignInMessage.trouble(in: "HTTP error (503): Apple SPIM endpoint returned HTTP 503", failure: unavailable)
        XCTAssertEqual(down, .unreadable(status: 503))
        XCTAssertFalse(CartoucheSignInMessage.pausesSignIns(down))
        let garbled = sideStoreFailure(["stage": "account", "family": "provisioning", "kind": "invalidResponse",
                                        "service": "provisioning", "reason": "lookup"],
                                       message: "Invalid response: Failed to parse provisioning URLs from lookup")
        XCTAssertEqual(CartoucheSignInMessage.trouble(in: "Invalid response: Failed to parse provisioning URLs from lookup",
                                                      failure: garbled), .unreadable(status: nil))

        // Apple says the sign-in's session has expired, and refuses one
        // without saying why: its codes, which SideSign passes on with
        // Apple's English words.
        let expired = sideStoreFailure(["stage": "account", "family": "server", "kind": "underlyingError",
                                        "codes": "SideSign.ServerError 3", "apple": 1100],
                                       message: "Your session has expired. Please log in. (1100)")
        let again = CartoucheSignInMessage.trouble(in: "Your session has expired. Please log in. (1100)", failure: expired)
        XCTAssertEqual(again, .sessionExpired)
        XCTAssertFalse(CartoucheSignInMessage.pausesSignIns(again))
        let refused = sideStoreFailure(["stage": "account", "family": "server", "kind": "underlyingError",
                                        "codes": "SideSign.ServerError 3", "apple": -22405],
                                       message: "This Action Cannot Be Completed (-22405)")
        let unexplained = CartoucheSignInMessage.trouble(in: "This Action Cannot Be Completed (-22405)", failure: refused)
        XCTAssertEqual(unexplained, .cannotComplete)
        XCTAssertFalse(CartoucheSignInMessage.pausesSignIns(unexplained))
        // Apple's limit still waits.
        let limit = sideStoreFailure(["stage": "account", "family": "server", "kind": "underlyingError",
                                      "codes": "SideSign.ServerError 3", "apple": -22411],
                                     message: "Too many verification codes have been sent. (-22411)")
        let tooMany = CartoucheSignInMessage.trouble(in: "Too many verification codes have been sent. (-22411)", failure: limit)
        XCTAssertEqual(tooMany, .tooManyRequests)
        XCTAssertTrue(CartoucheSignInMessage.pausesSignIns(tooMany))
        XCTAssertFalse(CartoucheSignInMessage.pausesSignIns(nil))
    }

    /// What Cartouche makes of the built-in SideStore's MESSAGE, its sign-in
    /// having left FIELDS as its outcome.
    private func sideStoreFailure(_ fields: [String: Any], message: String) -> CartoucheFailure {
        var left: [String: Any] = ["version": 1, "action": "signIn", "ok": false, "date": Int(Date().timeIntervalSince1970)]
        left.merge(fields) { _, new in new }
        let outcome = (try? JSONSerialization.data(withJSONObject: left))
            .flatMap { CartoucheSideStoreOutcome(data: $0, expecting: .signIn) }
        XCTAssertNotNil(outcome, "\(fields)")
        return CartoucheFailure.sideStore(outcome: outcome, message: message, fraction: 0, seconds: 0, vpn: true, pairing: true)
    }

    func testTheTroubleWithThisIPhone() {
        XCTAssertEqual(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.vpn, stage: "device",
                                                                                 details: ["kind": .text("noVPN")])), .vpn)
        XCTAssertEqual(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.pairing, stage: "deviceCheck",
                                                                                 details: ["kind": .text("invalidPairingFile")])),
                       .pairing)
        XCTAssertEqual(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.device, stage: "device",
                                                                                 details: ["kind": .text("noConnection")])), .wifi)
        XCTAssertEqual(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.device, stage: "device",
                                                                                 details: ["kind": .text("noDevice")])), .noAnswer)
        XCTAssertEqual(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.device)), .noAnswer)
        XCTAssertNil(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.deviceRegistration, stage: "device")))
        XCTAssertNil(CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(.appleCredentials, stage: "account")))
    }

    func testTheTroubleMinimuxerToldOf() {
        func trouble(_ cause: CartoucheFailure.Cause, _ kind: String, reason: String?, vpn: Bool?) -> CartoucheSignInMessage.DeviceTrouble? {
            var details: [String: CartoucheTelemetryValue] = ["kind": .text(kind)]
            if let reason { details["reason"] = .text(reason) }
            if let vpn { details["vpn"] = .flag(vpn) }
            return CartoucheSignInMessage.deviceTrouble(in: CartoucheFailure(cause, stage: "deviceCheck", details: details))
        }
        // A Lockdown pairing file, which minimuxer takes through LocalDevVPN
        // from iOS 26.4 only beside an IPsec interface (patch 0022).
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: "noIPsec", vpn: true), .olderPairing)
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: "noIPsec", vpn: false), .olderPairing)
        // LocalDevVPN connected, as Cartouche saw it: the iPhone did not
        // answer through it, whatever minimuxer made of it: the player is
        // not told that LocalDevVPN is not connected.
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: "portClosed", vpn: true), .noAnswer)
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: "dropped", vpn: true), .noAnswer)
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: nil, vpn: true), .noAnswer)
        // LocalDevVPN off, or not known.
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: "portClosed", vpn: false), .vpn)
        XCTAssertEqual(trouble(.vpn, "noVPN", reason: "noTunnel", vpn: false), .vpn)
        XCTAssertEqual(trouble(.vpn, "invalidVPN", reason: nil, vpn: nil), .vpn)
        // A pairing file this iPhone refused when minimuxer reached it.
        for reason in ["handshake", "serviceRefused", "lockdownSession", "lockdownValue"] {
            XCTAssertEqual(trouble(.pairing, "invalidPairingFile", reason: reason, vpn: true), .pairingRefused, reason)
        }
        // One missing, or that does not read, or a reason not known.
        for reason in ["notLoaded", "unreadable", "incomplete", "noUDID", "other"] {
            XCTAssertEqual(trouble(.pairing, "invalidPairingFile", reason: reason, vpn: true), .pairing, reason)
        }
        XCTAssertEqual(trouble(.pairing, "invalidPairingFile", reason: nil, vpn: true), .pairing)
        XCTAssertEqual(trouble(.pairing, "pairingNotComplete", reason: "notLoaded", vpn: true), .pairing)
    }

    func testWhatASignInLeavesOfTheIPhonesStep() {
        // Apple accepted the account and SideStore kept it: only this
        // iPhone is left, whatever stopped its step.
        XCTAssertTrue(CartoucheSignInMessage.leavesDeviceStep(CartoucheFailure(.vpn, stage: "device")))
        XCTAssertTrue(CartoucheSignInMessage.leavesDeviceStep(CartoucheFailure(.deviceRegistration, stage: "device")))
        // Before Apple, or with Apple, nothing is kept.
        XCTAssertFalse(CartoucheSignInMessage.leavesDeviceStep(CartoucheFailure(.vpn, stage: "deviceCheck")))
        XCTAssertFalse(CartoucheSignInMessage.leavesDeviceStep(CartoucheFailure(.appleCredentials, stage: "account")))
        XCTAssertFalse(CartoucheSignInMessage.leavesDeviceStep(CartoucheFailure(.sideStoreQuit)))

        // The iPhone's step alone, without the account it needs.
        XCTAssertTrue(CartoucheSignInMessage.needsSignIn(afterDeviceStep: CartoucheFailure(.notSignedIn, stage: "account")))
        XCTAssertTrue(CartoucheSignInMessage.needsSignIn(afterDeviceStep: CartoucheFailure(.noTeam, stage: "account")))
        XCTAssertTrue(CartoucheSignInMessage.needsSignIn(afterDeviceStep: CartoucheFailure(.notSignedIn)))
        XCTAssertFalse(CartoucheSignInMessage.needsSignIn(afterDeviceStep: CartoucheFailure(.vpn, stage: "deviceCheck")))
        XCTAssertFalse(CartoucheSignInMessage.needsSignIn(afterDeviceStep: CartoucheFailure(.deviceRegistration, stage: "device")))
    }

    func testThePasswordStaysOnlyWhenItNeverLeftThisIPhone() {
        for stage in ["start", "database", "credentials", "deviceCheck"] {
            XCTAssertTrue(CartoucheSignInMessage.keepsPassword(after: CartoucheFailure(.vpn, stage: stage)), stage)
        }
        for stage in ["account", "verification", "team", "certificate", "device", "finish"] {
            XCTAssertFalse(CartoucheSignInMessage.keepsPassword(after: CartoucheFailure(.other, stage: stage)), stage)
        }
        XCTAssertFalse(CartoucheSignInMessage.keepsPassword(after: CartoucheFailure(.sideStoreQuit)))
        XCTAssertFalse(CartoucheSignInMessage.keepsPassword(after: nil))
    }

    func testWhenTheTroubleWithThisIPhoneWasMet() {
        XCTAssertEqual(CartoucheSignInMessage.deviceMoment(of: CartoucheFailure(.vpn, stage: "deviceCheck")), .beforeApple)
        XCTAssertEqual(CartoucheSignInMessage.deviceMoment(of: CartoucheFailure(.vpn, stage: "device")), .afterApple)
        XCTAssertEqual(CartoucheSignInMessage.deviceMoment(of: CartoucheFailure(.pairing, stage: "account")), .elsewhere)
        XCTAssertEqual(CartoucheSignInMessage.deviceMoment(of: CartoucheFailure(.device)), .elsewhere)
    }

    func testWhatTheSignInScreenShows() {
        let request = CartoucheSignInMessage.CodeRequest(id: "A", mode: .sms, phone: nil, canTextMessage: false, error: nil)
        let phases: [CartoucheSignInPhase?] = [nil, .waitingForVPN(deviceStep: false), .waitingForVPN(deviceStep: true),
                                               .signingIn, .code(request), .registeringDevice]
        XCTAssertEqual(phases.map { $0?.needsCode ?? false }, [false, false, false, false, true, false])
        XCTAssertEqual(phases.map { $0?.isWaitingForVPN ?? false }, [false, true, true, false, false, false])
        // Nothing interrupts SideStore at work; a wait or a code can be cancelled.
        XCTAssertEqual(phases.map { $0?.sideStoreRuns ?? false }, [false, false, false, true, false, true])

        // The step that registers this iPhone alone, while it runs or waits,
        // and, in between, while it is left, unless the player signs in again.
        XCTAssertEqual(phases.map { CartoucheSignInPhase.showsDeviceStep($0, left: true, signingInAgain: false) },
                       [true, false, true, false, false, true])
        XCTAssertEqual(phases.map { CartoucheSignInPhase.showsDeviceStep($0, left: false, signingInAgain: false) },
                       [false, false, true, false, false, true])
        XCTAssertFalse(CartoucheSignInPhase.showsDeviceStep(nil, left: true, signingInAgain: true))

        // What ends a sign-in that SideStore ran, for the password to go.
        XCTAssertTrue(CartoucheSignInPhase.endsSignIn(from: .signingIn, to: nil))
        XCTAssertTrue(CartoucheSignInPhase.endsSignIn(from: .code(request), to: nil))
        XCTAssertFalse(CartoucheSignInPhase.endsSignIn(from: .registeringDevice, to: nil))
        XCTAssertFalse(CartoucheSignInPhase.endsSignIn(from: .waitingForVPN(deviceStep: false), to: nil))
        XCTAssertFalse(CartoucheSignInPhase.endsSignIn(from: .signingIn, to: .code(request)))
        XCTAssertFalse(CartoucheSignInPhase.endsSignIn(from: nil, to: nil))
    }

    func testTheWaitForLocalDevVPN() {
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        let wait = CartoucheVPNWait(started: start)
        XCTAssertEqual(wait.next(connected: false, at: start), .keepWaiting)
        XCTAssertEqual(wait.next(connected: false, at: start.addingTimeInterval(600)), .keepWaiting)
        XCTAssertEqual(wait.next(connected: false, at: start.addingTimeInterval(601)), .stop)
        // Once connected, what waited goes on, even at the last moment.
        XCTAssertEqual(wait.next(connected: true, at: start.addingTimeInterval(2)), .goOn)
        XCTAssertEqual(wait.next(connected: true, at: start.addingTimeInterval(601)), .goOn)
        // How long the player waited, for the measurements.
        XCTAssertEqual(wait.seconds(at: start.addingTimeInterval(41.6)), 42)
        XCTAssertEqual(wait.seconds(at: start.addingTimeInterval(-5)), 0)
    }

    func testCartoucheTakesTheIPhonesStepByItselfOnceLocalDevVPNConnects() {
        var watch = CartoucheDeviceStepWatch()
        // Cartouche opens with LocalDevVPN connected and the step left: it
        // takes it.
        XCTAssertTrue(watch.look(connected: true, left: true, idle: true))
        // Not again while LocalDevVPN stays connected, once the step failed.
        watch.ended(connected: true)
        XCTAssertFalse(watch.look(connected: true, left: true, idle: true))
        // Once LocalDevVPN connects again, it does.
        XCTAssertFalse(watch.look(connected: false, left: true, idle: true))
        XCTAssertTrue(watch.look(connected: true, left: true, idle: true))
        watch.ended(connected: true)
        // Three times at most while Cartouche is open.
        XCTAssertFalse(watch.look(connected: false, left: true, idle: true))
        XCTAssertTrue(watch.look(connected: true, left: true, idle: true))
        watch.ended(connected: false)
        XCTAssertEqual(watch.tries, 3)
        XCTAssertFalse(watch.look(connected: true, left: true, idle: true))
        XCTAssertFalse(watch.look(connected: false, left: true, idle: true))
        XCTAssertFalse(watch.look(connected: true, left: true, idle: true))
        XCTAssertEqual(watch.tries, 3)
    }

    func testCartoucheTakesNoStepWhileBusyOrWithoutOne() {
        var watch = CartoucheDeviceStepWatch()
        // No step left: LocalDevVPN connecting starts nothing...
        XCTAssertFalse(watch.look(connected: true, left: false, idle: true))
        // ...nor does the step a sign-in leaves as it ends, LocalDevVPN
        // still connected.
        watch.ended(connected: true)
        XCTAssertFalse(watch.look(connected: true, left: true, idle: true))
        XCTAssertEqual(watch.tries, 0)

        // LocalDevVPN connecting while Cartouche signs in, or while Apple's
        // limit holds, starts nothing, then or once it is over.
        var busy = CartoucheDeviceStepWatch()
        XCTAssertFalse(busy.look(connected: false, left: true, idle: true))
        XCTAssertFalse(busy.look(connected: true, left: true, idle: false))
        XCTAssertFalse(busy.look(connected: true, left: true, idle: true))
        // A sign-in that ended without LocalDevVPN: the step is taken once
        // it connects.
        busy.ended(connected: false)
        XCTAssertTrue(busy.look(connected: true, left: true, idle: true))
        XCTAssertEqual(busy.tries, 1)
    }

    func testThePauseAfterApplesLimit() throws {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let first = CartoucheSignInPause.after(nil, at: now, retryAfter: nil)
        XCTAssertEqual(first, CartoucheSignInPause(until: now.addingTimeInterval(900), inARow: 1, last: now))
        XCTAssertEqual(first.seconds, 900)
        XCTAssertTrue(first.holds(at: now.addingTimeInterval(899)))
        XCTAssertFalse(first.holds(at: now.addingTimeInterval(900)))

        // Each limit in a row waits longer, up to two hours.
        var pause = first
        var waits: [Int] = []
        for step in 1...5 {
            pause = CartoucheSignInPause.after(pause, at: now.addingTimeInterval(Double(step) * 3_600), retryAfter: nil)
            waits.append(pause.seconds)
        }
        XCTAssertEqual(waits, [1_800, 3_600, 7_200, 7_200, 7_200])
        XCTAssertEqual(pause.inARow, 6)

        // A day after the last one, it starts again from the first step.
        XCTAssertEqual(CartoucheSignInPause.after(pause, at: pause.last.addingTimeInterval(86_400), retryAfter: nil).seconds, 900)

        // What Apple asks for, a minute to a day.
        XCTAssertEqual(CartoucheSignInPause.after(nil, at: now, retryAfter: 3_600).seconds, 3_600)
        XCTAssertEqual(CartoucheSignInPause.after(nil, at: now, retryAfter: 0).seconds, 60)
        XCTAssertEqual(CartoucheSignInPause.after(first, at: now, retryAfter: 604_800).seconds, 86_400)

        // Kept across launches as JSON.
        let kept = try JSONDecoder().decode(CartoucheSignInPause.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(kept, first)
    }
}
