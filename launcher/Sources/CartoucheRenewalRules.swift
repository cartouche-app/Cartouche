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
/// front in the last days of its signature, with LocalDevVPN connected, in
/// its last two only while Tailscale is on, which LocalDevVPN turns off: up
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
    /// From how many days left while Tailscale is on: its last two, under
    /// 48 hours. iOS keeps one VPN at a time, and LocalDevVPN, which the
    /// renewal connects, turns Tailscale off until the player turns it on
    /// again (CartoucheTailscale.swift): the nights before, the player's
    /// automation has the time to renew Cartouche first.
    static let tailscaleDays = 1
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
        /// Whether Apple said that the session the built-in SideStore renews
        /// Cartouche with has expired, for the signature Cartouche has, and
        /// no sign-in went through since (CartoucheExpiredSession).
        var sessionExpired = false
        /// Whether Tailscale is connected on this iPhone, which LocalDevVPN
        /// would turn off.
        var tailscaleConnected = false
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
        /// Apple said that the session the built-in SideStore renews
        /// Cartouche with has expired: a renewal would fail the same way
        /// every six hours, LocalDevVPN opened for each, until a sign-in
        /// gives SideStore a new one (CartoucheRenewalTrouble.sessionExpired).
        case sessionExpired
        /// The setup has something left, which a renewal needs.
        case setup
        /// LocalDevVPN is not connected: Cartouche tries again each time it
        /// comes back, as when the player turned it on.
        case vpn
        /// LocalDevVPN is not connected and Tailscale is, with more days
        /// left than `tailscaleDays`: connecting LocalDevVPN would turn
        /// Tailscale off.
        case tailscale
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
        guard !situation.sessionExpired else { return .sessionExpired }
        guard situation.isSetUp else { return .setup }
        guard !situation.sideStoreBusy else { return .sideStoreBusy }
        guard !situation.gameRunning else { return .gameRunning }
        guard !situation.signInsPaused else { return .signInsPaused }
        if let lastTry = situation.lastTry, now >= lastTry, now.timeIntervalSince(lastTry) < spacing {
            return .triedLately
        }
        if !situation.vpnConnected, situation.tailscaleConnected, daysLeft > tailscaleDays { return .tailscale }
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
    /// Apple said that the session the built-in SideStore asks it with has
    /// expired, as SideStore first asks it for the account's certificates
    /// (VerifyCertificateOperation): SideStore keeps the token of its last
    /// sign-in and renews with it, without signing in again, and only a
    /// sign-in gives it a new one. From November 19 to 24, 54 renewals and
    /// updates of 7 copies, from 0.13.1 to 0.15.1, failed so, with Apple's
    /// -1 and "Your session has expired", which the System page and the
    /// update's notice showed in SideStore's words; an install over
    /// Cartouche did not always mend it, and the one copy whose player
    /// signed in again went past that step on its next renewal.
    case sessionExpired
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
        if failure.stage == "VerifyCertificate",
           failure.details["apple"] == .number(Double(CartoucheSignInMessage.sessionExpiredCode))
            || failure.details["sessionExpired"] == .flag(true) {
            return .sessionExpired
        }
        return CartoucheSignInMessage.deviceTrouble(in: failure).map { .device($0) }
    }
}

/// Apple said that the session the built-in SideStore renews and updates
/// Cartouche with has expired (CartoucheRenewalTrouble.sessionExpired), as a
/// renewal or an update found it with the signature Cartouche had then: a
/// sign-in gives SideStore a new session. Cartouche then renews itself no
/// more (CartoucheAutomaticRenewal.Wait.sessionExpired), signs in again by
/// itself once, after the renewal it started by itself that found it, with
/// the Apple ID and password SideStore keeps, and renews itself once a
/// sign-in has gone through.
enum CartoucheExpiredSession {
    /// Whether the session that Cartouche noted expired with the signature
    /// that expired at NOTED still holds, the signature Cartouche has
    /// expiring at CURRENT: another signature, from a renewal, an update or
    /// an install over Cartouche, came with a session that worked. Nil for
    /// either, nothing tells it does.
    static func holds(current: Date?, noted: Date?) -> Bool {
        guard let current, let noted else { return false }
        return abs(current.timeIntervalSince(noted)) < 1
    }

    /// Whether Cartouche signs in again by itself for the session noted
    /// expired with the signature that expired at NOTED, the signature
    /// Cartouche has expiring at CURRENT: once for a signature, TRIED being
    /// the one it last did so for, as Apple limits sign-ins and may ask for a
    /// code each time. After that, the player signs in again.
    static func signsInAgain(current: Date?, noted: Date?, tried: Date?) -> Bool {
        holds(current: current, noted: noted) && !holds(current: current, noted: tried)
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
    /// Cartouche for Mac renewed it, from the Mac the iPhone is plugged
    /// into or on the Wi-Fi of, with a new profile, as its record in
    /// Cartouche's Documents says (CartoucheMacRenewal, decision 165).
    case mac

    /// What renewed the signature since Cartouche last read it: UPDATED, a
    /// new version; REINSTALLED, another installation of it, nil when
    /// Cartouche had not noted the one before; RENEWED HERE, Cartouche
    /// renewed itself meanwhile; BY MAC, the new date is the one Cartouche
    /// for Mac wrote. Nil when it cannot tell.
    static func of(updated: Bool, reinstalled: Bool?, renewedHere: Bool, byMac: Bool = false) -> CartoucheRenewalVia? {
        if updated { return .update }
        if reinstalled == true { return .reinstall }
        if renewedHere { return .cartouche }
        if byMac { return .mac }
        return reinstalled == false ? .outside : nil
    }
}

/// The renewal Cartouche for Mac made (decision 165): its helper,
/// cartouche-signer, installs a new provisioning profile on the iPhone and
/// leaves the app as it is, embedded.mobileprovision included, then writes
/// the renewal's date in Cartouche's Documents with the fields of the
/// built-in SideStore's record (builder/mac/signer/src/iphone.rs,
/// RENEWAL_RECORD), for Cartouche to show until when it opens.
struct CartoucheMacRenewal: Decodable, Equatable {
    /// Its place in Cartouche's Documents (builder/tests/test_signer.py).
    static let path = ".cartouche/renewal.json"

    let bundleIdentifier: String
    let expirationDate: Date
    let refreshedDate: Date
    /// Who renewed it: "mac".
    let by: String

    /// The record DATA holds, for the app BUNDLE IDENTIFIER as it is
    /// installed: nil for another app's, another renewer's, or a record
    /// that does not read.
    static func read(_ data: Data, bundleIdentifier: String) -> CartoucheMacRenewal? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(CartoucheMacRenewal.self, from: data),
              record.bundleIdentifier == bundleIdentifier, record.by == "mac" else { return nil }
        return record
    }
}

/// Until when Cartouche opens: a renewal installs a new profile and leaves
/// the embedded one as the last install wrote it, so the latest of the
/// embedded profile's date, the built-in SideStore's record of its last
/// renewal and Cartouche for Mac's counts.
enum CartoucheExpiry: Equatable {
    case embedded, sideStore, mac

    /// The latest date, and whose it is; nil when none is known.
    static func latest(embedded: Date?, sideStore: Date?, mac: Date?) -> (date: Date, source: CartoucheExpiry)? {
        var latest: (date: Date, source: CartoucheExpiry)? = embedded.map { (date: $0, source: CartoucheExpiry.embedded) }
        for (date, source) in [(sideStore, CartoucheExpiry.sideStore), (mac, CartoucheExpiry.mac)] {
            guard let date else { continue }
            if latest.map({ date > $0.date }) ?? true { latest = (date: date, source: source) }
        }
        return latest
    }
}

/// The automation of Shortcuts that renews Cartouche every night, as the
/// setup's last step, its page and the System page show it. iOS lets no app
/// create an automation, nor see the player's: Cartouche sees each run of
/// the Refresh All Apps action it runs, which the built-in SideStore's
/// support notes in Cartouche's defaults as it starts, once LocalDevVPN's
/// tunnel is up or not, and as it ends
/// (launcher/SideStoreSupport/CartoucheShortcutRun.swift), and whether the
/// player said they made it, on its page. Up to 0.15.1, nothing said
/// whether a player had one, nor whether it worked: a new player found its
/// steps under System alone, and the measurements saw its renewals only
/// once they had gone through (signature.renewed, via outside).
enum CartoucheNightlyRenewal {
    /// The run's key in Cartouche's defaults, CartoucheShortcutRun's too
    /// (app/tests/test_renewal.py).
    static let runKey = "Cartouche.nightly.run"
    /// When the player said they made the automation, on its page.
    static let madeKey = "Cartouche.nightly.made"

    /// How long after its last run the automation counts as no longer
    /// running: three nights, the iPhone off or out of power one night
    /// being no reason to say so.
    static let late: TimeInterval = 3 * 86_400
    /// How long after the player said they made it an automation never
    /// seen to run counts as not running: a night and a half.
    static let firstNight: TimeInterval = 36 * 3_600
    /// How long a run goes on at most: one started longer ago that never
    /// ended was ended by iOS. The longest renewal the measurements saw in
    /// the week of November 10 took 71 seconds.
    static let longest: TimeInterval = 10 * 60
    /// How much later than its start the signature expires, at least, after
    /// a run that renewed it, whatever SideStore said as it ended, or when
    /// iOS ended it first: a renewal gives seven days from the moment Apple
    /// makes the profiles, a minute or so into the run, and SideStore may
    /// quit on its way back (CartoucheFailure.renewalEnd). A signature
    /// renewed before the run, by an update the day before, expires
    /// earlier.
    static let renewedSpan: TimeInterval = 7 * 86_400 - 10 * 60

    /// One run of Refresh All Apps from Shortcuts, as CartoucheShortcutRun
    /// notes it.
    struct Run: Equatable {
        var started: Date
        /// Whether LocalDevVPN's tunnel was up once Refresh All Apps had
        /// waited for it: nil until then.
        var tunnel: Bool?
        /// When it ended: nil while it runs, or when iOS ended Cartouche
        /// first.
        var ended: Date?
        /// The built-in SideStore's words, when it failed.
        var message: String?

        init(started: Date, tunnel: Bool? = nil, ended: Date? = nil, message: String? = nil) {
            self.started = started
            self.tunnel = tunnel
            self.ended = ended
            self.message = message
        }

        /// The run in RECORD, as CartoucheShortcutRun writes it in
        /// Cartouche's defaults: nil for anything else.
        init?(record: Any?) {
            guard let record = record as? [String: Any], let started = record["started"] as? Date else { return nil }
            self.init(started: started, tunnel: record["tunnel"] as? Bool, ended: record["ended"] as? Date,
                      message: record["message"] as? String)
        }
    }

    /// Why the last run did not renew Cartouche.
    enum Problem: Equatable {
        /// LocalDevVPN's tunnel was not up once Refresh All Apps had waited
        /// for it: the automation runs no Enable LocalDevVPN before it.
        case vpn
        /// iOS ended Cartouche before the run ended.
        case interrupted
        /// The built-in SideStore failed, with these words.
        case sideStore(String)

        /// Its name in the measurements (app.opened, nightlyProblem).
        var name: String {
            switch self {
            case .vpn: return "vpn"
            case .interrupted: return "interrupted"
            case .sideStore: return "sideStore"
            }
        }
    }

    /// Where the automation stands.
    enum State: Equatable {
        /// No run seen, and the player has not said they made it.
        case toMake
        /// The player said they made it, then: no run seen since, its first
        /// night yet to come.
        case waiting(since: Date)
        /// The player said they made it, then, and no run came for a night
        /// and a half: its time, or Run Immediately, to check.
        case notRunning(since: Date)
        /// A run under way, since then.
        case running(since: Date)
        /// Its last run renewed Cartouche, then.
        case renewed(at: Date)
        /// Its last run, then, did not renew Cartouche.
        case failed(at: Date, Problem)
        /// Its last run was longer ago than `late`, then: the automation no
        /// longer runs, removed or turned off.
        case stopped(since: Date)

        /// Whether the setup's step is done: the automation renews
        /// Cartouche, or the player made it and its first night has not
        /// come yet.
        var isDone: Bool {
            switch self {
            case .waiting, .running, .renewed: return true
            case .toMake, .notRunning, .failed, .stopped: return false
            }
        }

        /// What its last run failed on, if it failed (app.opened,
        /// nightlyProblem).
        var problem: Problem? {
            if case .failed(_, let problem) = self { return problem }
            return nil
        }

        /// Its name in the measurements (app.opened, nightly).
        var name: String {
            switch self {
            case .toMake: return "toMake"
            case .waiting: return "waiting"
            case .notRunning: return "notRunning"
            case .running: return "running"
            case .renewed: return "renewed"
            case .failed: return "failed"
            case .stopped: return "stopped"
            }
        }
    }

    /// Where the automation stands at NOW, after RUN, its last run, MADE,
    /// when the player said they made it, the signature expiring at
    /// EXPIRATION.
    static func state(run: Run?, made: Date?, expiration: Date?, at now: Date) -> State {
        // Said made after its last run, as after one that failed or
        // stopped: its next night tells.
        if let made, run.map({ $0.started < made }) ?? true {
            return now.timeIntervalSince(made) > firstNight ? .notRunning(since: made) : .waiting(since: made)
        }
        guard let run else { return .toMake }
        if now.timeIntervalSince(run.started) > late { return .stopped(since: run.started) }
        // SideStore said it renewed Cartouche, whatever the tunnel read.
        if let ended = run.ended, run.message == nil { return .renewed(at: ended) }
        // Otherwise it reaches this iPhone through the tunnel alone.
        if run.tunnel == false { return .failed(at: run.started, .vpn) }
        if let expiration, expiration.timeIntervalSince(run.started) >= renewedSpan {
            return .renewed(at: run.ended ?? run.started)
        }
        guard run.ended != nil else {
            return now.timeIntervalSince(run.started) < longest ? .running(since: run.started)
                : .failed(at: run.started, .interrupted)
        }
        return .failed(at: run.started, .sideStore(run.message ?? ""))
    }
}
