//
//  CartoucheRenewalRulesTests.swift
//  CartoucheCoreTests
//
//  When Cartouche renews itself as it comes to the front, what renewed a
//  signature that lasts longer, and why a renewal or an update failed, when
//  Cartouche says what to do (Sources/CartoucheRenewalRules.swift).
//

import XCTest
@testable import CartoucheCore

final class CartoucheRenewalRulesTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A copy signed in with a free Apple account, set up, LocalDevVPN on,
    /// SideStore idle and no game running, with DAYS LEFT.
    private func situation(daysLeft: Int? = 2, canRenew: Bool = true, isSetUp: Bool = true, vpn: Bool = true,
                           busy: Bool = false, paused: Bool = false, playing: Bool = false,
                           lastTry: Date? = nil, revoked: Bool = false,
                           noLiveProcess: Bool = false, tailscale: Bool = false) -> CartoucheAutomaticRenewal.Situation {
        CartoucheAutomaticRenewal.Situation(daysLeft: daysLeft, canRenew: canRenew, isSetUp: isSetUp, vpnConnected: vpn,
                                            sideStoreBusy: busy, signInsPaused: paused, gameRunning: playing,
                                            lastTry: lastTry, certificateRevoked: revoked,
                                            liveProcessMissing: noLiveProcess, tailscaleConnected: tailscale)
    }

    /// Why a renewal failed, as Cartouche reads what the built-in SideStore
    /// left (CartoucheSideStoreOutcome) with its MESSAGE, LocalDevVPN
    /// connected or not (VPN).
    private func renewalFailure(_ fields: [String: Any], message: String = "Failed to Refresh Some App",
                                vpn: Bool = true) throws -> CartoucheFailure {
        var written: [String: Any] = ["version": 1, "action": "refresh", "ok": false,
                                      "date": Int(now.timeIntervalSince1970) - 30]
        written.merge(fields) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: written)
        let outcome = try XCTUnwrap(CartoucheSideStoreOutcome(data: data, expecting: .refresh, now: now))
        return CartoucheFailure.sideStore(outcome: outcome, message: message, fraction: 0.4, seconds: 9,
                                          vpn: vpn, pairing: true)
    }

    /// What SideStore leaves when Apple revoked the certificate it signs
    /// with, as 4 renewals of 0.12.x left it on November 13 and 14.
    private func revokedFailure() throws -> CartoucheFailure {
        try renewalFailure(["stage": "VerifyCertificate", "trail": "FetchAnisetteData>VerifyCertificate",
                            "family": "operation", "kind": "certificateRevoked", "codes": "SideStore.OperationError 2"],
                           message: "The certificate has been revoked.")
    }

    /// What LiveContainer's bridge says when LiveProcess is not in the app
    /// (app/LiveContainer/SideStoreSupport/SideStore.swift), SideStore never
    /// started, so that it left nothing: 11 updates of a copy of 0.12.1 to
    /// 0.13.0 failed so on November 15.
    private func noLiveProcessFailure(vpn: Bool = true) -> CartoucheFailure {
        CartoucheFailure.sideStore(outcome: nil, message: "Unable to locate LiveProcess bundle. To use the Refresh All Apps "
                                       + "shortcut, reinstall LiveContainer+SideStore with LiveProcess installed. If you use "
                                       + "SideStore, choose \"Keep App Extensions (Use Main Profile)\". If you use PlumeImpactor, "
                                       + "choose \"Only Register Main Bundle\". For other sideloaders, select keep all "
                                       + "extensions, i.e. DO NOT Remove any extension.",
                                   fraction: 0, seconds: 1, vpn: vpn, pairing: true)
    }

    private func wait(_ situation: CartoucheAutomaticRenewal.Situation) -> CartoucheAutomaticRenewal.Wait? {
        CartoucheAutomaticRenewal.wait(situation, at: now)
    }

    // MARK: When Cartouche renews itself

    /// The measurements of November 13: 87 copies signed for seven days,
    /// 27 of them expiring on November 17, and nothing but Renew now and an
    /// automation of the player's renewing them, while the System page said
    /// that Cartouche renewed itself with LocalDevVPN on.
    func testRenewsItselfInTheLastThreeDaysWithLocalDevVPNOn() {
        for days in [3, 2, 1, 0] {
            XCTAssertNil(wait(situation(daysLeft: days)), "\(days) days left")
            XCTAssertTrue(CartoucheAutomaticRenewal.isDue(situation(daysLeft: days), at: now))
        }
        // As the home's top bar shows the days left.
        XCTAssertEqual(CartoucheAutomaticRenewal.days, 3)
    }

    func testLeavesASignatureThatHasMoreDaysAlone() {
        for days in [4, 6, 7, 363] {
            XCTAssertEqual(wait(situation(daysLeft: days)), .notDue, "\(days) days left")
        }
        // A signature Cartouche could not read: nothing tells it is due.
        XCTAssertEqual(wait(situation(daysLeft: nil)), .notDue)
    }

    /// Cartouche opens once its signature has expired only when it read an
    /// older date than the one iOS holds: renewing then does no harm.
    func testAnExpiredSignatureIsDueToo() {
        XCTAssertNil(wait(situation(daysLeft: -1)))
    }

    /// The player's own certificate signs Cartouche with no Apple ID: they
    /// install it again from their computer.
    func testNeverWithThePlayersOwnCertificate() {
        XCTAssertEqual(wait(situation(canRenew: false)), .cannotRenew)
    }

    /// Not signed in, no pairing file, a certificate iOS refuses or still
    /// being checked, this iPhone left to register: SideStore would only
    /// fail, as Renew now did 4 times on 3 copies not signed in, in 0.11.1
    /// and 0.11.2.
    func testWaitsForTheSetup() {
        XCTAssertEqual(wait(situation(isSetUp: false)), .setup)
    }

    /// SideStore reaches the iPhone through LocalDevVPN: 9 renewals of
    /// 0.11.2 did not reach it. Cartouche tries again when it comes back,
    /// as when the player turned it on, and counts no try meanwhile.
    func testWaitsForLocalDevVPN() {
        XCTAssertEqual(wait(situation(vpn: false)), .vpn)
        XCTAssertNil(wait(situation(vpn: true)))
    }

    /// iOS keeps one VPN at a time: LocalDevVPN, which the renewal connects,
    /// turns Tailscale off until the player turns it on again. While it is
    /// on, Cartouche renews itself in the last two days alone, under 48
    /// hours, and counts no try before.
    func testWithTailscaleOnWaitsForTheLastTwoDays() {
        for days in [3, 2] {
            XCTAssertEqual(wait(situation(daysLeft: days, vpn: false, tailscale: true)), .tailscale, "\(days) days left")
        }
        for days in [1, 0, -1] {
            XCTAssertEqual(wait(situation(daysLeft: days, vpn: false, tailscale: true)), .vpn, "\(days) days left")
        }
        XCTAssertEqual(CartoucheAutomaticRenewal.tailscaleDays, 1)
        // Without Tailscale, from three days left as ever.
        XCTAssertEqual(wait(situation(daysLeft: 3, vpn: false, tailscale: false)), .vpn)
        // LocalDevVPN connected already turns nothing off.
        XCTAssertNil(wait(situation(daysLeft: 3, vpn: true, tailscale: true)))
        // Nor does it make a signature with more days due.
        XCTAssertEqual(wait(situation(daysLeft: 5, vpn: false, tailscale: true)), .notDue)
    }

    /// SideStore takes one action at a time: another, started meanwhile,
    /// fails with "Another refresh task is in progress".
    func testNeverWhileSideStoreIsAtSomethingElse() {
        XCTAssertEqual(wait(situation(busy: true)), .sideStoreBusy)
    }

    /// SideStore would start in a process of its own beside the game's.
    func testNeverWhileAGameRunsBehindTheConsole() {
        XCTAssertEqual(wait(situation(playing: true)), .gameRunning)
    }

    func testNeverWhileApplesLimitOnSignInsHolds() {
        XCTAssertEqual(wait(situation(paused: true)), .signInsPaused)
    }

    /// Each renewal asks Apple for the profiles: one that failed waits six
    /// hours before the next, whatever the player does meanwhile.
    func testTriesAgainSixHoursAfterTheLastTry() {
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-60))), .triedLately)
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-6 * 3_600 + 1))), .triedLately)
        XCTAssertNil(wait(situation(lastTry: now.addingTimeInterval(-6 * 3_600))))
        XCTAssertNil(wait(situation(lastTry: now.addingTimeInterval(-3 * 86_400))))
        // A try that LocalDevVPN would have failed was never made.
        XCTAssertEqual(wait(situation(vpn: false, lastTry: now.addingTimeInterval(-7 * 3_600))), .vpn)
    }

    /// The iPhone's clock went back: a try dated later holds nothing back.
    func testATryDatedLaterThanNowHoldsNothingBack() {
        XCTAssertNil(wait(situation(lastTry: now.addingTimeInterval(3_600))))
    }

    // MARK: A certificate Apple revoked

    /// On November 13 and 14, 4 renewals of 3 copies failed as Apple had
    /// revoked their certificate, which no renewal gives back: up to 0.13.0,
    /// Cartouche tried again every six hours, LocalDevVPN opened for each
    /// try, until the signature expired.
    func testNeverRenewsItselfOnACertificateAppleRevoked() {
        XCTAssertEqual(wait(situation(revoked: true)), .certificateRevoked)
        XCTAssertFalse(CartoucheAutomaticRenewal.isDue(situation(revoked: true), at: now))
        // Six hours or three days after the last try alike.
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-6 * 3_600), revoked: true)), .certificateRevoked)
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-3 * 86_400), revoked: true)), .certificateRevoked)
        // Nor does Cartouche open LocalDevVPN for it.
        XCTAssertEqual(wait(situation(vpn: false, revoked: true)), .certificateRevoked)
        // On its last day as on the others.
        XCTAssertEqual(wait(situation(daysLeft: 0, revoked: true)), .certificateRevoked)
        // A signature with more days left waits as any other.
        XCTAssertEqual(wait(situation(daysLeft: 5, revoked: true)), .notDue)
    }

    /// LiveProcess, which the built-in SideStore runs in, missing from the
    /// app: no renewal can even start, and up to 0.13.1 Cartouche tried
    /// again every six hours in its last three days, LocalDevVPN opened for
    /// each try, until the signature expired.
    func testNeverRenewsItselfWithoutLiveProcess() {
        XCTAssertEqual(wait(situation(noLiveProcess: true)), .liveProcessMissing)
        XCTAssertFalse(CartoucheAutomaticRenewal.isDue(situation(noLiveProcess: true), at: now))
        // Six hours or three days after the last try alike.
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-6 * 3_600), noLiveProcess: true)), .liveProcessMissing)
        XCTAssertEqual(wait(situation(lastTry: now.addingTimeInterval(-3 * 86_400), noLiveProcess: true)), .liveProcessMissing)
        // Nor does Cartouche open LocalDevVPN for it, nor wait for the setup,
        // which no sign-in can finish without LiveProcess either.
        XCTAssertEqual(wait(situation(vpn: false, noLiveProcess: true)), .liveProcessMissing)
        XCTAssertEqual(wait(situation(isSetUp: false, noLiveProcess: true)), .liveProcessMissing)
        // On its last day as on the others, the certificate revoked or not:
        // an install over itself gives back both.
        XCTAssertEqual(wait(situation(daysLeft: 0, noLiveProcess: true)), .liveProcessMissing)
        XCTAssertEqual(wait(situation(revoked: true, noLiveProcess: true)), .liveProcessMissing)
        // A signature with more days left waits as any other, and the
        // player's own certificate is never renewed here.
        XCTAssertEqual(wait(situation(daysLeft: 5, noLiveProcess: true)), .notDue)
        XCTAssertEqual(wait(situation(canRenew: false, noLiveProcess: true)), .cannotRenew)
    }

    /// The certificate Apple revoked is the one of the signature Cartouche
    /// noted: an install of Cartouche over itself, with the Cartouche
    /// Installer, gives it a signature that expires a week after it, and
    /// Cartouche renews itself again.
    func testOnlyTheSignatureAppleRevokedTheCertificateOfIsHeld() {
        let revoked = now.addingTimeInterval(2 * 86_400 + 5 * 3_600)
        XCTAssertTrue(CartoucheAutomaticRenewal.isRevoked(current: revoked, revoked: revoked))
        // Read again from the profile or from SideStore's record.
        XCTAssertTrue(CartoucheAutomaticRenewal.isRevoked(current: revoked.addingTimeInterval(0.4), revoked: revoked))
        // Installed again a day later: a new signature, for seven days.
        XCTAssertFalse(CartoucheAutomaticRenewal.isRevoked(current: now.addingTimeInterval(8 * 86_400), revoked: revoked))
        XCTAssertFalse(CartoucheAutomaticRenewal.isRevoked(current: revoked.addingTimeInterval(60), revoked: revoked))
        // Nothing noted, or a signature Cartouche could not read.
        XCTAssertFalse(CartoucheAutomaticRenewal.isRevoked(current: revoked, revoked: nil))
        XCTAssertFalse(CartoucheAutomaticRenewal.isRevoked(current: nil, revoked: revoked))
    }

    // MARK: What to tell of a renewal or an update that failed

    /// SideStore no longer finds the certificate among the account's, and
    /// Apple's OCSP answers that it is revoked: up to 0.13.0, the System
    /// page said "The certificate has been revoked." and showed Renew now,
    /// which failed the same way.
    func testTellsACertificateAppleRevoked() throws {
        let failure = try revokedFailure()
        XCTAssertEqual(failure.cause, .certificate)
        XCTAssertEqual(CartoucheRenewalTrouble.of(failure), .certificateRevoked)
        // LocalDevVPN off or not, the certificate is no less revoked.
        let offline = try renewalFailure(["stage": "VerifyCertificate", "family": "operation", "kind": "certificateRevoked"],
                                         vpn: false)
        XCTAssertEqual(CartoucheRenewalTrouble.of(offline), .certificateRevoked)
    }

    /// SideStore did not reach this iPhone through LocalDevVPN, as a renewal
    /// or an update needs it to: what to do, as a sign-in says it.
    func testTellsWhatKeptSideStoreFromThisIPhone() throws {
        let off = try renewalFailure(["stage": "InstallProvisioningProfiles", "family": "operation", "kind": "noVPN"],
                                     vpn: false)
        XCTAssertEqual(CartoucheRenewalTrouble.of(off), .device(.vpn))
        // LocalDevVPN connected, and this iPhone did not answer through it.
        let silent = try renewalFailure(["stage": "InstallProvisioningProfiles", "family": "operation", "kind": "noVPN"])
        XCTAssertEqual(CartoucheRenewalTrouble.of(silent), .device(.noAnswer))
        let noWiFi = try renewalFailure(["stage": "InstallProvisioningProfiles", "family": "minimuxer",
                                         "kind": "noConnection"])
        XCTAssertEqual(CartoucheRenewalTrouble.of(noWiFi), .device(.wifi))
        let refused = try renewalFailure(["stage": "InstallProvisioningProfiles", "family": "operation",
                                          "kind": "invalidPairingFile", "reason": "handshake"])
        XCTAssertEqual(CartoucheRenewalTrouble.of(refused), .device(.pairingRefused))
    }

    /// LiveContainer's bridge could not start SideStore, LiveProcess missing
    /// from the app: up to 0.13.1, the update's notice said to check
    /// LocalDevVPN and try again, before LiveContainer's words, in English,
    /// which send the player to the settings of other sideloaders.
    func testTellsLiveProcessMissing() {
        let failure = noLiveProcessFailure()
        XCTAssertEqual(failure.cause, .liveProcessMissing)
        XCTAssertEqual(CartoucheRenewalTrouble.of(failure), .liveProcessMissing)
        // LocalDevVPN off or not: it would not start SideStore either.
        XCTAssertEqual(CartoucheRenewalTrouble.of(noLiveProcessFailure(vpn: false)), .liveProcessMissing)
        // LiveProcess there, but refusing to start: not the same trouble.
        let refused = CartoucheFailure.sideStore(outcome: nil, message: "Failed to start extension Error Domain=NSCocoaErrorDomain",
                                                 fraction: 0, seconds: 1, vpn: true, pairing: true)
        XCTAssertEqual(refused.cause, .liveProcessFailed)
        XCTAssertNil(CartoucheRenewalTrouble.of(refused))
    }

    /// Anything else keeps SideStore's words, or Cartouche's of Apple's
    /// answers (CartoucheText.sideStoreMessage).
    func testLeavesAnyOtherFailureToSideStoresWords() throws {
        let profiles = try renewalFailure(["stage": "FetchProvisioningProfiles", "family": "portal",
                                           "kind": "provisioningProfileDoesNotExist"])
        XCTAssertNil(CartoucheRenewalTrouble.of(profiles))
        let refusedByApple = try renewalFailure(["stage": "FetchProvisioningProfiles", "family": "portal",
                                                 "kind": "unknown", "apple": 1100])
        XCTAssertNil(CartoucheRenewalTrouble.of(refusedByApple))
        // A certificate's trouble that does not say Apple revoked it.
        XCTAssertNil(CartoucheRenewalTrouble.of(CartoucheFailure(.certificate, stage: "VerifyCertificate")))
        // SideStore left nothing.
        XCTAssertNil(CartoucheRenewalTrouble.of(CartoucheFailure.sideStore(outcome: nil, message: "Something went wrong",
                                                                           fraction: 0.2, seconds: 3, vpn: true,
                                                                           pairing: true)))
    }

    // MARK: What renewed the signature

    /// signature.renewed, up to 0.12.0: 24 of 51 were updates, and the
    /// others could be Renew now, the automation of Shortcuts or the
    /// Cartouche Installer alike.
    func testAnUpdateComesFirst() {
        XCTAssertEqual(CartoucheRenewalVia.of(updated: true, reinstalled: true, renewedHere: true), .update)
        XCTAssertEqual(CartoucheRenewalVia.of(updated: true, reinstalled: nil, renewedHere: false), .update)
    }

    func testTheSameVersionInstalledAgainIsAReinstall() {
        XCTAssertEqual(CartoucheRenewalVia.of(updated: false, reinstalled: true, renewedHere: false), .reinstall)
        XCTAssertEqual(CartoucheRenewalVia.of(updated: false, reinstalled: true, renewedHere: true), .reinstall)
    }

    func testARenewalOfCartouchesOwn() {
        XCTAssertEqual(CartoucheRenewalVia.of(updated: false, reinstalled: false, renewedHere: true), .cartouche)
        XCTAssertEqual(CartoucheRenewalVia.of(updated: false, reinstalled: nil, renewedHere: true), .cartouche)
    }

    /// Neither an install nor Cartouche itself: the Refresh All Apps action,
    /// as the automation of Shortcuts runs it.
    func testWhatRenewedItWhileCartoucheWasClosedIsOutside() {
        XCTAssertEqual(CartoucheRenewalVia.of(updated: false, reinstalled: false, renewedHere: false), .outside)
    }

    /// The first start of a version that notes its installation cannot tell
    /// a reinstall from the rest.
    func testWithoutTheInstallationBeforeItCannotTell() {
        XCTAssertNil(CartoucheRenewalVia.of(updated: false, reinstalled: nil, renewedHere: false))
    }

    func testSendsShortNames() {
        XCTAssertEqual(CartoucheRenewalVia.update.rawValue, "update")
        XCTAssertEqual(CartoucheRenewalVia.reinstall.rawValue, "reinstall")
        XCTAssertEqual(CartoucheRenewalVia.cartouche.rawValue, "cartouche")
        XCTAssertEqual(CartoucheRenewalVia.outside.rawValue, "outside")
    }
}
