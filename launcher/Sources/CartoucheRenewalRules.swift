//
//  CartoucheRenewalRules.swift
//  CartoucheCore
//
//  When Cartouche renews itself, as it comes to the front in the last days
//  of its signature, what renewed a signature that lasts longer than it
//  did, as the measurements send it, and why a renewal or an update failed,
//  when Cartouche says what to do in its own words, apart from the renewal
//  itself (CartoucheRenewal.swift), so that they can be tested.
//

import Foundation

/// Cartouche renews itself, without the player, each time it comes to the
/// front in the last days of its signature, with LocalDevVPN connected: up
/// to 0.12.0, only Renew now, on the System page, and an automation the
/// player made in Shortcuts renewed it, while the System page said that it
/// renewed itself. A renewal installs new provisioning profiles, and signs
/// nothing again: Cartouche keeps Increased Memory Limit, as the
/// measurements of the week of November 10 showed on every renewal.
enum CartoucheAutomaticRenewal {
    /// From how many days left: those from which the home's top bar shows
    /// them (CartoucheHomeView.expirySoonDays). A free Apple account's
    /// signature lasts seven days.
    static let days = 3
    /// How long Cartouche waits after it tried, whether the renewal went
    /// through or not, before it tries again: each renewal asks Apple's
    /// servers for the profiles, and one that failed, with Apple or with
    /// LocalDevVPN, fails the same way minutes later.
    static let spacing: TimeInterval = 6 * 3_600

    /// What Cartouche finds as it comes to the front.
    struct Situation: Equatable {
        /// Whole days left on the signature (CartoucheSignature.daysLeft),
        /// nil when Cartouche could not read it.
        var daysLeft: Int?
        /// Whether the built-in SideStore renews it, with the Apple ID: not
        /// with the player's own certificate (docs/imported-signing.md).
        var canRenew: Bool
        /// Whether the setup has nothing left: the certificate works, the
        /// pairing file is in place, SideStore is signed in and this iPhone
        /// is registered with the account.
        var isSetUp: Bool
        var vpnConnected: Bool
        /// Whether the built-in SideStore is at something else, which it
        /// takes one at a time: a renewal, an update of Cartouche, a sign-in
        /// or the registration of this iPhone, under way or waiting for
        /// LocalDevVPN.
        var sideStoreBusy: Bool
        /// Whether Apple's limit on sign-ins holds (CartoucheSignInPause): a
        /// renewal signs in again when Apple asks for it.
        var signInsPaused: Bool
        /// Whether a game runs behind the console: SideStore would start in
        /// a process of its own beside the game's, which iOS ends first.
        var gameRunning: Bool
        /// When Cartouche last renewed itself, or tried to.
        var lastTry: Date?
        /// Whether Apple revoked the certificate of the signature Cartouche
        /// has, as its last renewal or update found (isRevoked).
        var certificateRevoked = false
        /// Whether LiveContainer's LiveProcess extension, which the built-in
        /// SideStore runs in, is missing from the app (CartoucheLiveProcess).
        var liveProcessMissing = false
    }

    /// Why Cartouche does not renew itself now.
    enum Wait: String, Equatable {
        /// More days are left than `days`, or none could be read.
        case notDue
        /// The player's own certificate signs Cartouche, or the built-in
        /// SideStore is not there.
        case cannotRenew
        /// LiveProcess, which the built-in SideStore runs in, is not in the
        /// app: SideStore cannot even start, and a renewal would fail the
        /// same way every six hours, LocalDevVPN opened for each, until an
        /// install of Cartouche over itself puts LiveProcess back
        /// (CartoucheRenewalTrouble.liveProcessMissing).
        case liveProcessMissing
        /// Apple revoked the certificate of the signature Cartouche has: a
        /// renewal, which signs nothing again, would fail the same way every
        /// six hours, until an install of Cartouche over itself gives it
        /// another signature (CartoucheRenewalTrouble.certificateRevoked).
        case certificateRevoked
        /// The setup has something left, which a renewal needs.
        case setup
        /// LocalDevVPN is not connected: Cartouche tries again each time it
        /// comes back, as when the player turned it on.
        case vpn
        case sideStoreBusy
        case signInsPaused
        case gameRunning
        /// Cartouche tried less than `spacing` ago.
        case triedLately
    }

    /// Why Cartouche does not renew itself, in SITUATION, at NOW: nil when
    /// it does. A last try dated after NOW, as when the iPhone's clock went
    /// back, holds nothing back.
    static func wait(_ situation: Situation, at now: Date) -> Wait? {
        guard let daysLeft = situation.daysLeft, daysLeft <= days else { return .notDue }
        guard situation.canRenew else { return .cannotRenew }
        guard !situation.liveProcessMissing else { return .liveProcessMissing }
        guard !situation.certificateRevoked else { return .certificateRevoked }
        guard situation.isSetUp else { return .setup }
        guard !situation.sideStoreBusy else { return .sideStoreBusy }
        guard !situation.gameRunning else { return .gameRunning }
        guard !situation.signInsPaused else { return .signInsPaused }
        if let lastTry = situation.lastTry, now >= lastTry, now.timeIntervalSince(lastTry) < spacing {
            return .triedLately
        }
        guard situation.vpnConnected else { return .vpn }
        return nil
    }

    /// Whether Cartouche renews itself now.
    static func isDue(_ situation: Situation, at now: Date) -> Bool {
        wait(situation, at: now) == nil
    }

    /// Whether the signature that expires at CURRENT is the one whose
    /// certificate Apple revoked, which expired at REVOKED, as Cartouche
    /// noted it when a renewal or an update found it: an install of
    /// Cartouche over itself gives it a signature that expires at another
    /// time. Nil for either, nothing tells it is.
    static func isRevoked(current: Date?, revoked: Date?) -> Bool {
        guard let current, let revoked else { return false }
        return abs(current.timeIntervalSince(revoked)) < 1
    }
}

/// Why a renewal or an update of Cartouche by the built-in SideStore failed,
/// when Cartouche says what to do in its own words rather than SideStore's:
/// up to 0.13.0, the System page showed SideStore's words of a renewal that
/// failed, and the update's notice put them after its own, which always
/// said to check LocalDevVPN and try again; up to 0.13.1, LiveContainer's,
/// in English, when LiveProcess was missing.
enum CartoucheRenewalTrouble: Equatable {
    /// Apple revoked the certificate of Cartouche's signature: SideStore no
    /// longer finds it among the account's, and Apple's OCSP answers that it
    /// is revoked (VerifyCertificateOperation). Another app or computer took
    /// a new one with the same Apple ID. A renewal signs nothing again, and
    /// a new sign-in stops on the account's other certificate, which
    /// SideStore never revokes (app/patches/sidestore/0004, 0012): only an
    /// install of Cartouche over itself, with the Cartouche Installer and
    /// the same Apple ID, gives it a new one. On November 13 and 14, 4
    /// renewals failed so on 3 copies of 0.12.x, while LiveContainer's
    /// check still found the certificate working.
    case certificateRevoked
    /// SideStore did not reach this iPhone through LocalDevVPN, as a
    /// sign-in tells it (CartoucheSignInMessage.deviceTrouble(in:)).
    case device(CartoucheSignInMessage.DeviceTrouble)
    /// LiveContainer's LiveProcess extension, which the built-in SideStore
    /// runs in, is not in the app: LiveContainer's bridge cannot start
    /// SideStore, and says so in English, sending the player to the
    /// settings of other sideloaders. Nothing in Cartouche puts it back: only
    /// an install of Cartouche over itself, with the Cartouche Installer and
    /// the same Apple ID, which keeps every extension. On November 15, a
    /// copy of 0.12.1 tried its update to 0.13.0 11 times so, its notice
    /// saying each time to check LocalDevVPN and try again.
    case liveProcessMissing

    /// The trouble FAILURE tells, nil for any other.
    static func of(_ failure: CartoucheFailure) -> CartoucheRenewalTrouble? {
        if failure.cause == .liveProcessMissing { return .liveProcessMissing }
        if failure.cause == .certificate, case .text("certificateRevoked")? = failure.details["kind"] {
            return .certificateRevoked
        }
        return CartoucheSignInMessage.deviceTrouble(in: failure).map { .device($0) }
    }
}

/// What renewed the signature, when it lasts longer than it did, as
/// signature.renewed sends it (`via`): up to 0.12.0, the measurements could
/// not tell the automation of Shortcuts from Renew now, from an install of
/// the Cartouche Installer, or from an update.
enum CartoucheRenewalVia: String, Equatable {
    /// A new version of Cartouche, which its update signed again, from the
    /// built-in SideStore or from the Cartouche Installer.
    case update
    /// The same version installed again, by the Cartouche Installer or
    /// another signer: iOS put it in a folder of its own
    /// (CartoucheLastSignIn.installation(of:)).
    case reinstall
    /// Cartouche renewed itself: Renew now, or by itself as it came to the
    /// front (CartoucheAutomaticRenewal).
    case cartouche
    /// Something else renewed it, while Cartouche was closed or in the
    /// background: its Refresh All Apps action, as the automation of
    /// Shortcuts runs it every night.
    case outside

    /// What renewed the signature since Cartouche last read it: UPDATED, a
    /// new version; REINSTALLED, another installation of it, nil when
    /// Cartouche had not noted the one before; RENEWED HERE, Cartouche
    /// renewed itself meanwhile. Nil when it cannot tell.
    static func of(updated: Bool, reinstalled: Bool?, renewedHere: Bool) -> CartoucheRenewalVia? {
        if updated { return .update }
        if reinstalled == true { return .reinstall }
        if renewedHere { return .cartouche }
        return reinstalled == false ? .outside : nil
    }
}
