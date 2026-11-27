//
//  SignerPlanTests.swift
//  BuilderKitTests
//
//  When the app renews Cartouche from this Mac, and what it says when it
//  cannot (SignerPlan.swift, decision 165): never before Cartouche's last
//  two days, again six hours after a failure and an hour after an iPhone
//  away, the password asked only once Apple ended the session, an install
//  over Cartouche once its certificate is gone, and what a renewal
//  measures.
//

import Foundation
import XCTest
@testable import BuilderKit

final class SignerPlanTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-12-01T10:00:00Z")!
    private var expires: Date { now.addingTimeInterval(36 * 3_600) }

    private func copy(due: String, expires: Date? = nil, from: Date? = nil) -> SignerCartouche {
        SignerCartouche(bundleId: "io.github.clabeuhtegrite.cartouche.ABCDE12345", version: "0.16.2", teamId: "ABCDE12345",
                        expires: expires ?? self.expires, due: due, from: from)
    }

    func testNothingBeforeItsLastTwoDays() {
        let from = now.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "not-yet", expires: from.addingTimeInterval(2 * 86_400), from: from),
                                       signedIn: true, last: nil, now: now), .wait(until: from))
        // Even after a failure, or without a session: nothing to ask yet.
        let failed = SignerAttempt(at: now, kind: "session-ended", expires: from.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "not-yet", expires: from.addingTimeInterval(2 * 86_400), from: from),
                                       signedIn: false, last: failed, now: now), .wait(until: from))
    }

    func testInItsLastTwoDaysOrExpiredItRenews() {
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: nil, now: now), .renew)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: now.addingTimeInterval(-3_600)), signedIn: true, last: nil, now: now), .renew)
    }

    func testWithoutASessionItAsksForThePasswordOnlyWhenDue() {
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: false, last: nil, now: now), .askPassword)
    }

    func testAnEndedSessionAsksForThePasswordUntilThePlayerSignsInAgain() {
        let ended = SignerAttempt(at: now.addingTimeInterval(-600), kind: "session-ended", expires: expires)
        // The session file is still there, signed in: Apple ended it.
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, since: now.addingTimeInterval(-86_400), last: ended, now: now),
                       .askPassword)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, since: now.addingTimeInterval(-60), last: ended, now: now), .renew)
    }

    func testAFailureWaitsSixHoursAndAnIphoneAwayOne() {
        let apple = SignerAttempt(at: now.addingTimeInterval(-3_600), kind: "apple", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: apple, now: now),
                       .wait(until: apple.at.addingTimeInterval(6 * 3_600)))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: apple, now: apple.at.addingTimeInterval(6 * 3_600)), .renew)
        let tooMany = SignerAttempt(at: now.addingTimeInterval(-3_600), kind: "too-many-requests", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: tooMany, now: now),
                       .wait(until: tooMany.at.addingTimeInterval(6 * 3_600)))
        let locked = SignerAttempt(at: now.addingTimeInterval(-1_800), kind: "iphone-refused", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: locked, now: now),
                       .wait(until: locked.at.addingTimeInterval(3_600)))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: locked, now: now.addingTimeInterval(1_800)), .renew)
    }

    func testOnlyAnInstallOpensItAgainOnceItsCertificateIsGone() {
        let gone = SignerAttempt(at: now.addingTimeInterval(-86_400), kind: "certificate-gone", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: gone, now: now), .needsInstall)
        let other = SignerAttempt(at: now.addingTimeInterval(-86_400), kind: "other-team", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: other, now: now), .otherTeam)
    }

    /// Its certificate gone, the newest Cartouche goes over it once it has
    /// expired, when none of its games can be playing; before, Reinstall
    /// waits for the player, even before its last two days.
    func testAnExpiredCopyWhoseCertificateIsGoneIsInstalledAgainOverItself() {
        let ended = now.addingTimeInterval(-3_600)
        let gone = SignerAttempt(at: now.addingTimeInterval(-7_200), kind: "certificate-gone", expires: ended)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: gone, now: now), .reinstall)
        // Expired by the clock, before the iPhone was read again.
        let soon = SignerAttempt(at: now.addingTimeInterval(-7_200), kind: "certificate-gone", expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: soon, now: expires.addingTimeInterval(60)), .reinstall)
        let from = now.addingTimeInterval(3 * 86_400)
        let early = SignerAttempt(at: now.addingTimeInterval(-60), kind: "certificate-gone", expires: from.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "not-yet", expires: from.addingTimeInterval(2 * 86_400), from: from),
                                       signedIn: true, last: early, now: now), .needsInstall)
        // Signed out: nothing is installed, the page says why.
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: false, last: gone, now: now), .needsInstall)
    }

    func testAFailedInstallIsTriedAgainSixHoursLaterOnceExpired() {
        let ended = now.addingTimeInterval(-3_600)
        let download = SignerAttempt(at: now.addingTimeInterval(-3_600), kind: "download", expires: ended, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: download, now: now),
                       .wait(until: download.at.addingTimeInterval(6 * 3_600)))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: download,
                                       now: download.at.addingTimeInterval(6 * 3_600)), .reinstall)
        let full = SignerAttempt(at: now.addingTimeInterval(-3_600), kind: "no-certificate-left", expires: ended, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: full, now: now),
                       .wait(until: full.at.addingTimeInterval(6 * 3_600)))
        let away = SignerAttempt(at: now.addingTimeInterval(-1_800), kind: "no-iphone", expires: ended, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: away, now: now),
                       .wait(until: away.at.addingTimeInterval(3_600)))
        // Asked before it expired: the player tries again when they like.
        let asked = SignerAttempt(at: now.addingTimeInterval(-60), kind: "download", expires: expires, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: asked, now: now), .needsInstall)
        // Apple ended the session on the way: the password first.
        let session = SignerAttempt(at: now.addingTimeInterval(-600), kind: "session-ended", expires: ended, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, since: now.addingTimeInterval(-86_400),
                                       last: session, now: now), .askPassword)
        // Another Apple Account's, as the install found: left alone.
        let other = SignerAttempt(at: now.addingTimeInterval(-60), kind: "other-team", expires: ended, install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "expired", expires: ended), signedIn: true, last: other, now: now), .otherTeam)
        // Installed: a renewal again for the copy it made.
        let installed = SignerAttempt(at: now.addingTimeInterval(-60), kind: nil, expires: now.addingTimeInterval(7 * 86_400), install: true)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "not-yet", expires: now.addingTimeInterval(7 * 86_400), from: now.addingTimeInterval(5 * 86_400)),
                                       signedIn: true, last: installed, now: now), .wait(until: now.addingTimeInterval(5 * 86_400)))
    }

    /// The tries kept before installs over Cartouche read as renewals, and
    /// a renewal is kept as before.
    func testTheTriesKeptBeforeReadTheSame() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(SignerAttempt.self, from: Data(#"{"at":"2026-11-30T10:00:00Z","kind":"certificate-gone","expires":"2026-12-01T22:00:00Z"}"#.utf8))
        XCTAssertFalse(old.wasInstall)
        XCTAssertEqual(old.kind, "certificate-gone")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let renewal = try XCTUnwrap(String(data: encoder.encode(SignerAttempt(at: now, kind: nil, expires: expires)), encoding: .utf8))
        XCTAssertFalse(renewal.contains("install"), renewal)
        let install = SignerAttempt(at: now, kind: "download", expires: expires, install: true)
        XCTAssertEqual(try decoder.decode(SignerAttempt.self, from: encoder.encode(install)), install)
    }

    func testAnInstallSaysHowFarItIs() {
        XCTAssertEqual(SignerProgress(step: "download", fraction: 0.5).overall, 0.2, accuracy: 0.001)
        XCTAssertEqual(SignerProgress(step: "sign", fraction: 0.5).overall, 0.5, accuracy: 0.001)
        XCTAssertEqual(SignerProgress(step: "install", fraction: 1).overall, 1, accuracy: 0.001)
        XCTAssertEqual(SignerProgress(step: "install", fraction: 7).fraction, 1)
        XCTAssertEqual(SignerProgress.read(#"{"event":"progress","step":"sign","fraction":0.25}"#), SignerProgress(step: "sign", fraction: 0.25))
        XCTAssertNil(SignerProgress.read(#"{"event":"code","bySms":false}"#))
        XCTAssertNil(SignerProgress.read(#"{"result":{"reinstalled":true}}"#))
    }

    /// Renewed or installed again elsewhere, Cartouche opens until another
    /// date: the failure was for the copy before.
    func testAFailureHoldsOnlyForTheCopyItWasTriedFor() {
        let gone = SignerAttempt(at: now.addingTimeInterval(-86_400), kind: "certificate-gone", expires: expires.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: gone, now: now), .renew)
        let renewed = SignerAttempt(at: now.addingTimeInterval(-60), kind: nil, expires: expires)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, last: renewed, now: now), .renew)
    }

    /// A copy another Apple Account installed: the Mac leaves it alone,
    /// before any try.
    func testACopyOfAnotherTeamIsLeftAlone() {
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, team: "ZZZZZ99999", last: nil, now: now), .otherTeam)
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: true, team: "ABCDE12345", last: nil, now: now), .renew)
        // Not signed in, the team is not known yet.
        XCTAssertEqual(SignerPlan.next(for: copy(due: "now"), signedIn: false, team: "ZZZZZ99999", last: nil, now: now), .askPassword)
    }

    /// The password is asked by a notification only of a player who signed
    /// in here and whose session Apple ended: never of one who did not
    /// sign in, or signed out, who reads it on the page.
    func testOnlyAnEndedSessionNotifies() {
        let since = now.addingTimeInterval(-86_400)
        let ended = SignerAttempt(at: now.addingTimeInterval(-600), kind: "session-ended", expires: expires)
        let before = SignerAttempt(at: since.addingTimeInterval(-60), kind: "session-ended", expires: expires)
        let away = SignerAttempt(at: now.addingTimeInterval(-600), kind: "no-iphone", expires: expires)
        XCTAssertTrue(SignerPlan.sessionEnded(since: since, attempts: [away, ended]))
        XCTAssertFalse(SignerPlan.sessionEnded(since: since, attempts: [away, before]))
        XCTAssertTrue(SignerPlan.notifiesPassword(.askPassword, signedIn: true, ended: true))
        XCTAssertFalse(SignerPlan.notifiesPassword(.askPassword, signedIn: false, ended: false))
        XCTAssertFalse(SignerPlan.notifiesPassword(.askPassword, signedIn: true, ended: false))
        XCTAssertFalse(SignerPlan.notifiesPassword(.renew, signedIn: true, ended: true))
    }

    func testThePasswordIsAskedAtMostOnceADay() {
        XCTAssertTrue(SignerPlan.mayAsk(asked: nil, now: now))
        XCTAssertFalse(SignerPlan.mayAsk(asked: now.addingTimeInterval(-23 * 3_600), now: now))
        XCTAssertTrue(SignerPlan.mayAsk(asked: now.addingTimeInterval(-24 * 3_600), now: now))
    }

    // MARK: What it measures

    func testARenewalMeasuresNeitherTheAccountNorTheIphone() {
        let renewal = SignerRenewal(renewed: true, bundleId: "io.github.clabeuhtegrite.cartouche.ABCDE12345", before: expires,
                                    expires: now.addingTimeInterval(7 * 86_400 - 60), due: "now", registeredAppId: false,
                                    refreshedSession: true, recorded: true, link: "usb", seconds: 3.24)
        XCTAssertEqual(SignerMeasures.renewed(renewal, asked: false, now: now), [
            "asked": .flag(false), "daysGiven": .count(6), "daysLeft": .count(1), "due": .text("now"), "link": .text("usb"),
            "recorded": .flag(true), "refreshedSession": .flag(true), "registeredAppId": .flag(false), "seconds": .number(3.2),
        ])
    }

    func testAnInstallOverCartoucheMeasuresNeitherTheAccountNorItsVersions() {
        let reinstall = SignerReinstall(reinstalled: true, bundleId: "io.github.clabeuhtegrite.cartouche.ABCDE12345", version: "0.16.3",
                                        previousVersion: "0.16.2", before: now.addingTimeInterval(-3_600),
                                        expires: now.addingTimeInterval(7 * 86_400 - 60), due: "expired", link: "network", seconds: 48.26)
        let fields = SignerMeasures.reinstalled(reinstall, asked: false, now: now)
        XCTAssertEqual(fields, [
            "asked": .flag(false), "daysGiven": .count(6), "daysLeft": .count(-1), "due": .text("expired"), "link": .text("network"),
            "refreshedSession": .flag(false), "seconds": .number(48.3), "updated": .flag(true),
        ])
        XCTAssertFalse(fields.values.contains(.text("0.16.3")))
        let failure = SignerFailure(kind: "no-certificate-left", stage: "apple", code: 7460, message: "Maximum number of certificates reached")
        XCTAssertEqual(SignerMeasures.failed(failure, copy: copy(due: "now"), asked: true, install: true, now: now)["how"], .text("install"))
        XCTAssertNil(SignerMeasures.failed(failure, copy: copy(due: "now"), asked: true, now: now)["how"])
    }

    func testAFailureMeasuresItsKindAndCodeAndNeverItsMessage() {
        let failure = SignerFailure(kind: "session-ended", stage: "session", code: -22406, message: "camille@example.com: Your session has expired.")
        let fields = SignerMeasures.failed(failure, copy: copy(due: "expired", expires: now.addingTimeInterval(-3_600)), asked: true, now: now)
        XCTAssertEqual(fields, ["asked": .flag(true), "code": .count(-22406), "daysLeft": .count(-1), "due": .text("expired"),
                                "kind": .text("session-ended"), "stage": .text("session")])
        XCTAssertFalse(fields.values.contains(.text(failure.message)))
    }

    // MARK: What the page says

    func testThePageSaysUntilWhenAndWhatThisMacDoes() {
        L10n.use("fr")
        defer { L10n.use("") }
        let from = now.addingTimeInterval(3 * 86_400)
        let notYet = copy(due: "not-yet", expires: from.addingTimeInterval(2 * 86_400), from: from)
        let lines = SignerWords.lines(for: notYet, plan: .wait(until: from), last: nil, working: false, now: now)
        XCTAssertEqual(lines.map(\.warning), [false, false])
        XCTAssertTrue(lines[0].text.hasPrefix("Cartouche s’ouvre jusqu’au "), lines[0].text)
        XCTAssertTrue(lines[1].text.hasPrefix("Ce Mac le renouvelle à partir du "), lines[1].text)
        let failed = SignerAttempt(at: now.addingTimeInterval(-3_600), kind: "network", expires: expires)
        let retry = SignerWords.lines(for: copy(due: "now"), plan: .wait(until: now.addingTimeInterval(5 * 3_600)), last: failed, working: false, now: now)
        XCTAssertEqual(retry.count, 3)
        XCTAssertEqual(retry[1], SignerLine("Apple ne répond pas : vérifiez la connexion à Internet.", warning: true))
        XCTAssertTrue(retry[2].text.hasPrefix("Ce Mac réessaie "), retry[2].text)
        let ask = SignerWords.lines(for: copy(due: "expired", expires: now.addingTimeInterval(-7_200)), plan: .askPassword, last: nil, working: false, now: now)
        XCTAssertEqual(ask.map(\.warning), [true, true])
        XCTAssertEqual(ask[1].text, "Connectez-vous à Apple ci-dessus pour que ce Mac le renouvelle.")
        // Not signed in yet: what it would do once signed in.
        let unsigned = SignerWords.lines(for: notYet, plan: .wait(until: from), last: nil, working: false, signedIn: false, now: now)
        XCTAssertTrue(unsigned[1].text.hasPrefix("Connecté à Apple, ce Mac le renouvelle à partir du "), unsigned[1].text)
        XCTAssertFalse(unsigned[1].warning)
        XCTAssertEqual(SignerWords.passwordNotice(expires: now.addingTimeInterval(-60), now: now).title, "Cartouche a expiré sur votre iPhone")
        XCTAssertEqual(SignerWords.passwordNotice(expires: expires, now: now).title, "Cartouche expire bientôt sur votre iPhone")
        XCTAssertTrue(SignerWords.passwordNotice(expires: expires, now: now).body.contains("page iPhone"))
        let renewed = SignerAttempt(at: now.addingTimeInterval(-60), kind: nil, expires: from.addingTimeInterval(2 * 86_400))
        XCTAssertTrue(SignerWords.lines(for: notYet, plan: .wait(until: from), last: renewed, working: false, now: now)[1].text.hasPrefix("Renouvelé par ce Mac "))
    }

    func testThePageSaysWhatAnInstallOverCartoucheDoes() {
        L10n.use("fr")
        defer { L10n.use("") }
        let needs = SignerWords.lines(for: copy(due: "now"), plan: .needsInstall, last: nil, working: false, now: now)
        XCTAssertEqual(needs.map(\.warning), [false, true])
        XCTAssertEqual(needs[1].text, "Réinstaller met le dernier Cartouche par-dessus, avec ses jeux et ses sauvegardes. Ce Mac le fait de lui-même une fois qu’il a expiré.")
        // The install the player asked found the account full.
        let full = SignerAttempt(at: now.addingTimeInterval(-600), kind: "no-certificate-left", expires: expires, install: true)
        let after = SignerWords.lines(for: copy(due: "now"), plan: .needsInstall, last: full, working: false, now: now)
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(after[1].text.contains("page Certificats de l’Installeur Cartouche"), after[1].text)
        let ended = now.addingTimeInterval(-3_600)
        let going = SignerWords.lines(for: copy(due: "expired", expires: ended), plan: .reinstall, last: nil, working: true,
                                      progress: SignerProgress(step: "download", fraction: 0.426), now: now)
        XCTAssertEqual(going.last, SignerLine("Réinstallation : téléchargement de Cartouche, 42 %"))
        XCTAssertEqual(SignerWords.lines(for: copy(due: "expired", expires: ended), plan: .reinstall, last: nil, working: false, now: now).last?.text,
                       "Ce Mac le réinstalle maintenant, avec ses jeux et ses sauvegardes")
        let installed = SignerAttempt(at: now.addingTimeInterval(-120), kind: nil, expires: expires, install: true)
        XCTAssertTrue(SignerWords.lines(for: copy(due: "now"), plan: .renew, last: installed, working: false, now: now)[1].text.hasPrefix("Réinstallé par ce Mac "))
        XCTAssertEqual(SignerWords.installNotice.title, "Cartouche est à réinstaller")
        XCTAssertTrue(SignerWords.reinstalledNotice(version: "0.16.3").body.contains("Cartouche 0.16.3 par-dessus"))
    }

    func testTheAccountSaysThePasswordIsNotKept() {
        L10n.use("fr")
        defer { L10n.use("") }
        let none = SignerWords.account(nil, ended: false, now: now)
        XCTAssertEqual(none.title, "Compte Apple")
        XCTAssertTrue(none.line.text.contains("ce Mac ne le garde pas"), none.line.text)
        let session = SignerSession(signedIn: true, email: "camille@example.com", teamId: "ABCDE12345", teamName: "Camille Testeur",
                                    since: now.addingTimeInterval(-86_400))
        let signed = SignerWords.account(session, ended: false, now: now)
        XCTAssertEqual(signed.title, "camille@example.com")
        XCTAssertTrue(signed.line.text.hasPrefix("Équipe Camille Testeur · connecté "), signed.line.text)
        XCTAssertTrue(signed.line.text.hasSuffix(" · le mot de passe n’est pas gardé"), signed.line.text)
        XCTAssertFalse(signed.line.warning)
        XCTAssertTrue(SignerWords.account(session, ended: true, now: now).line.warning)
    }

    /// The helper's kinds of error (builder/mac/signer/src/error.rs), each
    /// in the player's words in every language (builder/tests/test_signer.py
    /// checks the list against the helper's).
    func testEveryKindOfFailureHasItsWordsInEachLanguage() {
        let kinds = ["no-session", "session-ended", "wrong-password", "wrong-code", "cancelled", "account-refused", "too-many-requests",
                     "anisette", "apple", "network", "no-iphone", "iphone-refused", "no-cartouche", "other-team", "certificate-gone",
                     "no-app-ids", "no-certificate-left", "download", "profile-refused", "iphone"]
        defer { L10n.use("") }
        for language in L10n.languages {
            L10n.use(language)
            let words = kinds.map { SignerWords.failure(kind: $0) }
            XCTAssertEqual(Set(words).count, kinds.count, language)
            for (kind, text) in zip(kinds, words) {
                XCTAssertFalse(text.contains("(\(kind))"), "\(language): \(kind)")
            }
        }
    }

    func testASignInMeasuresItsResult() {
        XCTAssertEqual(SignerMeasures.signIn(result: "wrong-code", seconds: 41.6), ["result": .text("wrong-code"), "seconds": .number(42)])
    }
}
