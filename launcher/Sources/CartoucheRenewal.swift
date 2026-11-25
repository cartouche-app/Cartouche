//
//  CartoucheRenewal.swift
//  Cartouche
//
//  Renewing Cartouche before its signature expires, and warning the player
//  in time. The built-in SideStore does the renewal: from the System page,
//  and by itself each time Cartouche comes to the front in the last days of
//  its signature (CartoucheAutomaticRenewal), through CartoucheRefresh
//  (launcher/SideStoreSupport), or every night, through an automation in
//  Shortcuts that runs its Refresh All Apps action.
//

import Foundation
import UIKit
import UserNotifications

@available(iOS 17.0, *)
enum CartoucheRenewal {
    struct Failure: LocalizedError, CartoucheExplainedError {
        let message: String
        /// Why, as the built-in SideStore left it (CartoucheSideStoreOutcome).
        var failure: CartoucheFailure?
        var errorDescription: String? { message }
    }

    static let shortcutsURL = URL(string: "shortcuts://")!

    // MARK: Renew now

    private typealias RefreshAllApps = @convention(c) (
        AnyObject, Selector, Progress, @escaping @convention(block) (NSString?) -> Void) -> Void

    private static let refreshSelector = NSSelectorFromString("refreshAllAppsWithProgress:completion:")

    /// CartoucheRefresh is in SideStoreSupport, which LiveContainer loads
    /// only when the app carries the built-in SideStore.
    private static var refreshAllApps: (receiver: AnyObject, call: RefreshAllApps)? {
        guard let refresh = NSClassFromString("CartoucheRefresh"),
              let method = class_getClassMethod(refresh, refreshSelector) else { return nil }
        return (refresh as AnyObject, unsafeBitCast(method_getImplementation(method), to: RefreshAllApps.self))
    }

    static var canRenew: Bool { !CartoucheImportedSigning.accountSigningDisabled && refreshAllApps != nil }

    /// Renews Cartouche without leaving the app; its SideStore renews no
    /// other app (app/patches/sidestore/0017). LocalDevVPN has to be
    /// connected. A failure says why, as SideStore left it. AUTOMATIC:
    /// Cartouche renews itself, as it came to the front, and renewal.done
    /// says so, as it says whether Cartouche had LocalDevVPN connect for it
    /// (VPN).
    ///
    /// SideStore can stop, or iOS end it, as it finishes, before it says how
    /// the renewal went: Cartouche then reads the signature SideStore
    /// records for it. Newer than before, the renewal went through;
    /// otherwise Cartouche asks a new SideStore, once.
    @MainActor
    static func renew(progress: Progress, automatic: Bool = false,
                      vpn: CartoucheLocalDevVPN.Connection = .connectedAlready) async throws {
        guard !CartoucheImportedSigning.accountSigningDisabled else {
            throw Failure(message: CartoucheText.signingUpdateOnComputer, failure: nil)
        }
        guard let refresh = refreshAllApps else {
            throw Failure(message: CartoucheText.renewUnavailable, failure: CartoucheFailure(.bridgeMissing, stage: "start"))
        }
        let started = Date()
        var attempt = 1
        while true {
            let before = CartoucheSignature.current()
            CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)
            let message: String? = await withCheckedContinuation { continuation in
                refresh.call(refresh.receiver, refreshSelector, progress) { message in
                    continuation.resume(returning: message.map { $0 as String })
                }
            }
            let outcome = CartoucheStoreKeychain.data(CartoucheSideStoreOutcome.account)
                .flatMap { CartoucheSideStoreOutcome(data: $0, expecting: .refresh) }
            CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)
            let seconds = Date().timeIntervalSince(started)
            let failure = message.map {
                CartoucheFailure.sideStore(outcome: outcome, message: $0, fraction: progress.fractionCompleted,
                                           seconds: seconds, vpn: CartoucheVPN.isConnected, pairing: CartouchePairing.exists)
            }
            let renewed = CartoucheSignature.current().isRenewal(of: before)
            switch CartoucheFailure.renewalEnd(failure: failure, outcome: outcome, renewed: renewed) {
            case .renewed(let despite):
                var fields = CartoucheFailure.sideStoreSuccess(outcome: outcome, seconds: seconds)
                if let despite {
                    CartoucheReports.note("Renewal: SideStore failed on its way back (\(despite.cause.rawValue)), yet Cartouche is renewed")
                    fields["recovered"] = .flag(true)
                    fields["cause"] = .text(despite.cause.rawValue)
                }
                if attempt > 1 {
                    fields["attempts"] = .number(Double(attempt))
                }
                fields["automatic"] = .flag(automatic)
                note(vpn, in: &fields)
                CartoucheTelemetry.shared.renewed(fields: fields)
                return
            case .quit where attempt == 1:
                // A new SideStore starts in a new LiveProcess, LiveContainer's
                // bridge having let the last one go.
                CartoucheReports.note("Renewal: SideStore quit before it answered, asking again")
                attempt += 1
                progress.completedUnitCount = 0
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            case .quit, .failed:
                guard let message, let failure else {
                    throw Failure(message: CartoucheText.renewFailed, failure: failure)
                }
                throw Failure(message: playerMessage(message, failure: failure), failure: failure)
            }
        }
    }

    /// What Cartouche tells the player when a renewal or an update of
    /// Cartouche ended with the built-in SideStore's MESSAGE, FAILURE being
    /// why: what to do, in its own words, when Apple revoked the certificate,
    /// SideStore did not reach this iPhone, or LiveProcess, which SideStore
    /// runs in, is missing from the app (CartoucheRenewalTrouble); otherwise
    /// SideStore's words, never Apple's page for an error, as they would show
    /// it (CartoucheText.sideStoreMessage).
    static func playerMessage(_ message: String, failure: CartoucheFailure) -> String {
        CartoucheRenewalTrouble.of(failure).map(advice) ?? CartoucheText.sideStoreMessage(message, failure: failure)
    }

    /// What to do about TROUBLE.
    static func advice(_ trouble: CartoucheRenewalTrouble) -> String {
        switch trouble {
        case .sessionExpired: return CartoucheText.renewSessionExpired
        case .certificateRevoked: return CartoucheText.renewRevoked
        case .device(let device): return CartoucheText.deviceMessage(device)
        case .liveProcessMissing: return CartoucheText.noLiveProcess
        }
    }

    /// Whether Cartouche opened LocalDevVPN for what it measures, and how
    /// long it then waited for it in front: `vpnOpened` and `vpnWait`.
    static func note(_ vpn: CartoucheLocalDevVPN.Connection, in fields: inout [String: CartoucheTelemetryValue]) {
        guard vpn.opened else { return }
        fields["vpnOpened"] = .flag(true)
        fields["vpnWait"] = .number(vpn.seconds)
    }

    // MARK: Warnings before expiry

    /// SideStore schedules its own warnings under these identifiers each
    /// time it renews (ScheduleExpirationWarningNotificationOperation), in
    /// English and about "SideStore". Cartouche's replace them, and theirs
    /// replace Cartouche's after a renewal in the background, so that only
    /// one of each shows, always for the latest expiry date.
    private static var warnings: [(identifier: String, before: TimeInterval, title: String, body: String)] {
        [
            ("sidestore-expiration-warning.24h", 24 * 3600, CartoucheText.warning24hTitle, CartoucheText.warningBody),
            ("sidestore-expiration-warning.6h", 6 * 3600, CartoucheText.warning6hTitle, CartoucheText.warningBody),
            ("sidestore-expiration-warning.0h", 0, CartoucheText.warningExpiredTitle, CartoucheText.warningExpiredBody),
        ]
    }

    /// Where the warnings are scheduled, one call after the other, away from
    /// the main thread: removePendingNotificationRequests waits there for
    /// usernotificationsd to answer, which can take minutes right after the
    /// iPhone starts. On the iPhone Duo simulator of run 42266582948, the
    /// games page's first frame waited for it for more than five minutes,
    /// on a white screen.
    private static let warningQueue = DispatchQueue(label: "io.github.clabeuhtegrite.cartouche.warnings", qos: .utility)

    /// Schedules the warnings for the current expiry date. Without the
    /// player's permission iOS drops them, so this is safe to call often. It
    /// returns at once: warningQueue does the work.
    static func scheduleWarnings() {
        warningQueue.async {
            let center = UNUserNotificationCenter.current()
            let warnings = Self.warnings
            center.removePendingNotificationRequests(withIdentifiers: warnings.map(\.identifier))
            guard let expirationDate = CartoucheSignature.current().expirationDate else { return }
            for warning in warnings {
                let interval = expirationDate.addingTimeInterval(-warning.before).timeIntervalSinceNow
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = warning.title
                content.body = warning.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let identifier = warning.identifier
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
                    if let error {
                        NSLog("[Cartouche] cannot schedule %@: %@", identifier, String(describing: error))
                    }
                }
            }
        }
    }

    static func alertStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for the permission to warn, then schedules the warnings.
    static func allowAlerts() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        scheduleWarnings()
    }

    /// Asks for it once the player's first game is installed, when nothing
    /// asked yet: a Cartouche no one opens for a week expires, and the
    /// warnings are what tells the player in time, even without the
    /// automation of every night. Asked or answered before, iOS shows
    /// nothing, and System's button stays the way to them.
    static func allowAlertsAfterFirstGame() async {
        #if CARTOUCHE_GALLERY
        // iOS's question would stand over the gallery's screens and tests.
        return
        #else
        guard await alertStatus() == .notDetermined else { return }
        await allowAlerts()
        #endif
    }

    @MainActor
    static var notificationSettingsURL: URL? {
        URL(string: UIApplication.openNotificationSettingsURLString)
    }
}

/// LiveContainer's LiveProcess extension, in Cartouche's PlugIns, which the
/// built-in SideStore runs in, for each of its actions: a renewal, an update
/// of Cartouche, a sign-in, the registration of this iPhone. An install that
/// removed the app's extensions leaves Cartouche without it, and
/// LiveContainer's bridge then cannot start SideStore
/// (CartoucheRenewalTrouble.liveProcessMissing).
enum CartoucheLiveProcess {
    /// Whether it is in the app, where LiveContainer's bridge looks for it
    /// (SideStoreSupport's RefreshHandler): as a folder, which a Bundle of
    /// it needs. The gallery has none, and says whether it is missing.
    static var isInApp: Bool {
        #if CARTOUCHE_GALLERY
        return !GalleryState.liveProcessMissing
        #else
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: plugins.appendingPathComponent("LiveProcess.appex").path,
                                              isDirectory: &isFolder) && isFolder.boolValue
        #endif
    }

    #if CARTOUCHE_GALLERY
    /// What LiveContainer's bridge says when it is missing
    /// (app/LiveContainer/SideStoreSupport/SideStore.swift), for the
    /// gallery's screens.
    static let bridgeSentenceForGallery = "Unable to locate LiveProcess bundle. To use the Refresh All Apps shortcut, "
        + "reinstall LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions "
        + "(Use Main Profile)\". If you use PlumeImpactor, choose \"Only Register Main Bundle\". For other sideloaders, "
        + "select keep all extensions, i.e. DO NOT Remove any extension."
    #endif
}

/// The renewal under way, from Renew now or by Cartouche itself as it comes
/// to the front, and why the last one failed: one at a time, as the
/// built-in SideStore takes its actions. The System page shows it, and
/// Cartouche's update, its sign-in and the registration of this iPhone wait
/// for its end before they hand SideStore their own: one started meanwhile
/// would fail with "Another refresh task is in progress".
@available(iOS 17.0, *)
@MainActor
final class CartoucheRenewals: ObservableObject {
    static let shared = CartoucheRenewals()

    /// How far the renewal under way has gone.
    @Published private(set) var progress: Progress?
    /// Whether Cartouche started it by itself.
    @Published private(set) var isAutomatic = false
    /// Why the last renewal failed, and the report on it.
    @Published private(set) var report: CartoucheReport?

    var isRenewing: Bool { progress != nil }

    /// When Cartouche last renewed itself, or tried to, kept across
    /// launches.
    static let lastTryKey = "Cartouche.renewal.automatic.last"
    /// When the signature whose certificate Apple revoked expires, as a
    /// renewal or an update found it, kept across launches: an install of
    /// Cartouche over itself gives it a signature that expires at another
    /// time (CartoucheAutomaticRenewal.isRevoked).
    static let revokedKey = "Cartouche.renewal.revokedSignature"
    /// When the signature with which a renewal or an update found the Apple
    /// session expired expires, kept across launches until a sign-in goes
    /// through (CartoucheExpiredSession); and when the one Cartouche last
    /// signed in again by itself for does.
    static let sessionExpiredKey = "Cartouche.renewal.sessionExpired"
    static let sessionSignInKey = "Cartouche.renewal.sessionExpired.signedInAgain"

    /// How long an update, a sign-in or the registration of this iPhone
    /// waits for the renewal under way before it goes on: three minutes,
    /// when the longest renewal the measurements saw in the week of
    /// November 10 took 71 seconds. A renewal that never ends, SideStore no
    /// longer answering, holds them up no longer: SideStore, still at it,
    /// may then refuse them, and Cartouche says why.
    var waitLimit: TimeInterval = 180

    private init() {}

    /// Whether the built-in SideStore is at an action of Cartouche's: a
    /// renewal, an update, a sign-in or the registration of this iPhone,
    /// under way or waiting for LocalDevVPN.
    var sideStoreBusy: Bool {
        isRenewing || CartoucheUpdates.shared.phase != nil || CartoucheAccount.shared.phase != nil
    }

    /// Whether the player can renew now: Cartouche set up, and SideStore
    /// free.
    var canRenewNow: Bool {
        CartoucheRenewal.canRenew && CartoucheSetup.shared.isComplete && !sideStoreBusy
    }

    /// Whether Apple revoked the certificate of the signature Cartouche has,
    /// as a renewal or an update found it: Cartouche no longer renews itself,
    /// which would fail the same way every six hours, and the System page
    /// says to install it again over itself, with the Cartouche Installer,
    /// until that gives it another signature. Renew now stays, for the
    /// player who wants to see it fail again.
    var certificateRevoked: Bool {
        CartoucheAutomaticRenewal.isRevoked(current: CartoucheSignature.current().expirationDate,
                                            revoked: UserDefaults.standard.object(forKey: Self.revokedKey) as? Date)
    }

    /// Whether LiveProcess, which the built-in SideStore runs in, is missing
    /// from the app (CartoucheLiveProcess): Cartouche no longer renews
    /// itself, which would fail the same way every six hours, LocalDevVPN
    /// opened for each, and the System page says to install it again over
    /// itself, with the Cartouche Installer, which puts it back. Renew now
    /// stays, which then says the same.
    var liveProcessMissing: Bool { !CartoucheLiveProcess.isInApp }

    /// Whether Apple said that the session the built-in SideStore renews
    /// Cartouche with has expired, as a renewal or an update found it with
    /// the signature Cartouche has, and no sign-in went through since
    /// (CartoucheExpiredSession): Cartouche no longer renews itself, which
    /// would fail the same way every six hours, and the System page and the
    /// setup ask the player to sign in again. Renew now stays.
    var sessionExpired: Bool {
        CartoucheExpiredSession.holds(current: CartoucheSignature.current().expirationDate,
                                      noted: UserDefaults.standard.object(forKey: Self.sessionExpiredKey) as? Date)
    }

    /// Notes the signature Cartouche has when FAILURE, why a renewal or an
    /// update failed, says that Apple revoked its certificate.
    func noteIfRevoked(_ failure: CartoucheFailure?) {
        guard let failure, CartoucheRenewalTrouble.of(failure) == .certificateRevoked,
              let expirationDate = CartoucheSignature.current().expirationDate else { return }
        UserDefaults.standard.set(expirationDate, forKey: Self.revokedKey)
        CartoucheReports.note("Apple revoked the certificate of this signature: Cartouche no longer renews itself on it")
        objectWillChange.send()
    }

    /// Notes the signature Cartouche has when FAILURE, why a renewal or an
    /// update failed, says that Apple's session has expired.
    func noteIfSessionExpired(_ failure: CartoucheFailure?) {
        guard let failure, CartoucheRenewalTrouble.of(failure) == .sessionExpired,
              let expirationDate = CartoucheSignature.current().expirationDate else { return }
        UserDefaults.standard.set(expirationDate, forKey: Self.sessionExpiredKey)
        CartoucheReports.note("Apple says the session SideStore renews with has expired: Cartouche no longer renews itself until a sign-in")
        objectWillChange.send()
    }

    /// Signs the built-in SideStore in again by itself, with the Apple ID
    /// and password it keeps, once for the signature with which Apple said
    /// that the session expired (CartoucheExpiredSession.signsInAgain): after
    /// the renewal Cartouche started by itself that found it, as it came to
    /// the front. The player sees the sign-in only should Apple ask for a
    /// code; without LocalDevVPN, or should the sign-in fail, the System page
    /// and the setup ask the player to sign in again.
    private func signInAgainForTheSession() {
        let defaults = UserDefaults.standard
        let current = CartoucheSignature.current().expirationDate
        guard CartoucheExpiredSession.signsInAgain(current: current,
                                                   noted: defaults.object(forKey: Self.sessionExpiredKey) as? Date,
                                                   tried: defaults.object(forKey: Self.sessionSignInKey) as? Date),
              CartoucheLocalDevVPN.isConnected, !sideStoreBusy else { return }
        defaults.set(current, forKey: Self.sessionSignInKey)
        if CartoucheAccount.shared.signInAgain(for: "for an expired Apple session") {
            CartoucheReports.note("Apple's session has expired: signing in again by itself")
        }
    }

    /// A sign-in went through: SideStore has a new session. When a renewal
    /// or an update had found the last one expired, Cartouche renews itself
    /// at once, which it no longer did meanwhile.
    func signedIn() {
        guard sessionExpired else { return }
        UserDefaults.standard.removeObject(forKey: Self.sessionExpiredKey)
        objectWillChange.send()
        guard canRenewNow else { return }
        CartoucheReports.note("Signed in again after Apple's session expired: renewing by itself")
        UserDefaults.standard.set(Date(), forKey: Self.lastTryKey)
        start(automatic: true)
    }

    /// What Cartouche finds as it comes to the front.
    var situation: CartoucheAutomaticRenewal.Situation {
        let setup = CartoucheSetup.shared
        return CartoucheAutomaticRenewal.Situation(
            daysLeft: CartoucheSignature.current().daysLeft,
            canRenew: CartoucheRenewal.canRenew,
            isSetUp: setup.isComplete && !setup.needsDevice,
            vpnConnected: CartoucheLocalDevVPN.isConnected,
            sideStoreBusy: sideStoreBusy,
            signInsPaused: CartoucheAccount.shared.pausedUntil != nil,
            gameRunning: CartoucheGameActions.shared.running != nil,
            lastTry: UserDefaults.standard.object(forKey: Self.lastTryKey) as? Date,
            certificateRevoked: certificateRevoked,
            liveProcessMissing: liveProcessMissing,
            sessionExpired: sessionExpired,
            tailscaleConnected: CartoucheTailscale.isConnected)
    }

    /// Renew now, from the System page.
    func renewNow() {
        guard canRenewNow else { return }
        start(automatic: false)
    }

    /// Renews Cartouche by itself when it is due (CartoucheAutomaticRenewal):
    /// CartoucheSetupRefresh calls it each time Cartouche comes to the front,
    /// and once the setup is found complete, a few seconds after the launch.
    /// When only LocalDevVPN is missing, Cartouche has it connect first, if
    /// it can open it (CartoucheLocalDevVPN): otherwise it counts no try,
    /// and renews itself as it comes back once LocalDevVPN is connected.
    /// While Tailscale is on, which LocalDevVPN turns off, it waits for the
    /// last two days, as the player's automation renews it at night.
    func renewIfDue() {
        let situation = self.situation
        switch CartoucheAutomaticRenewal.wait(situation, at: Date()) {
        case nil:
            break
        case .vpn:
            guard CartoucheLocalDevVPN.shared.decide(playerAsked: false) == .open else { return }
        default:
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastTryKey)
        CartoucheReports.note("Renewal started by itself, \(situation.daysLeft ?? 0) days left")
        start(automatic: true)
    }

    /// Runs ACTION, which hands the built-in SideStore an action, once no
    /// renewal is under way: at once when none is, otherwise once it has
    /// ended, or after `waitLimit` at most. WHAT names the action in the
    /// journal.
    func afterRenewal(_ what: String, _ action: @escaping @MainActor () -> Void) {
        guard isRenewing else {
            action()
            return
        }
        CartoucheReports.note(what + ": waiting for the renewal under way")
        let limit = waitLimit
        Task {
            let started = Date()
            while isRenewing, Date().timeIntervalSince(started) < limit {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if isRenewing {
                CartoucheReports.note(what + ": the renewal under way has not ended after \(Int(limit)) s, going on")
            }
            action()
        }
    }

    private func start(automatic: Bool) {
        let progress = Progress(totalUnitCount: 100)
        self.progress = progress
        isAutomatic = automatic
        report = nil
        if !automatic { CartoucheReports.note("Renewal started") }
        Task {
            // SideStore reaches this iPhone through LocalDevVPN, which
            // Cartouche has connect first, when it is off.
            let vpn = await CartoucheLocalDevVPN.shared.connect(for: "Renewal", playerAsked: !automatic)
            do {
                try await CartoucheRenewal.renew(progress: progress, automatic: automatic, vpn: vpn)
                CartoucheReports.note("Renewal done")
                UserDefaults.standard.removeObject(forKey: Self.revokedKey)
                UserDefaults.standard.removeObject(forKey: Self.sessionExpiredKey)
            } catch {
                let failure = (error as? CartoucheRenewal.Failure)?.failure
                noteIfRevoked(failure)
                noteIfSessionExpired(failure)
                fail(error, automatic: automatic, fraction: progress.fractionCompleted, vpn: vpn)
            }
            self.progress = nil
            isAutomatic = false
            // The player who renewed from the System page signs in again
            // there, as it says.
            if automatic { signInAgainForTheSession() }
            // SideStore scheduled its own warnings, in English and about
            // SideStore: Cartouche's take their place.
            CartoucheRenewal.scheduleWarnings()
        }
    }

    /// Why the renewal failed, as the System page shows it, and the report
    /// on it, which says whether Cartouche had LocalDevVPN connect for it
    /// (VPN).
    private func fail(_ error: Error, automatic: Bool, fraction: Double,
                      vpn: CartoucheLocalDevVPN.Connection = .connectedAlready) {
        var failure = CartoucheFailure.of(error, fraction: fraction)
        failure.details["automatic"] = .flag(automatic)
        CartoucheRenewal.note(vpn, in: &failure.details)
        report = CartoucheReports.make(.renewal, CartoucheText.renewFailed, message: error.localizedDescription,
                                       error: error,
                                       step: automatic ? "Renewing by itself, before it expires" : CartoucheText.renewing,
                                       fraction: fraction, failure: failure)
    }

    #if CARTOUCHE_GALLERY
    /// Cartouche renewing itself, FRACTION of the way, for the gallery's
    /// screens (launcher/Gallery).
    func showRenewingForGallery(at fraction: Double) {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = Int64(fraction * 100)
        self.progress = progress
        isAutomatic = true
    }

    /// The renewal Cartouche started by itself, failed with ERROR, for the
    /// gallery's screens.
    func showFailedForGallery(_ error: Error) {
        fail(error, automatic: true, fraction: 0.3)
    }

    /// The renewal Cartouche started by itself, failed as Apple had revoked
    /// its certificate, as SideStore tells it, for the gallery's screens:
    /// without noting the signature, which the gallery's next screens keep.
    func showRevokedForGallery() {
        let failure = CartoucheFailure(.certificate, stage: "VerifyCertificate", fraction: 0.1, seconds: 4,
                                       codes: "SideStore.OperationError 2",
                                       details: ["kind": .text("certificateRevoked"), "vpn": .flag(true)])
        let message = CartoucheRenewal.playerMessage("The certificate has been revoked.", failure: failure)
        fail(CartoucheRenewal.Failure(message: message, failure: failure), automatic: true, fraction: 0.1)
    }

    /// What the built-in SideStore leaves when Apple says that the session it
    /// renews with has expired, as 54 renewals and updates of 7 copies left
    /// it from November 19 to 24, for the gallery's screens.
    static var sessionExpiredForGallery: CartoucheFailure {
        CartoucheFailure(.appleServer, stage: "VerifyCertificate", fraction: 1, seconds: 2,
                         codes: "SideSign.ServerError 3",
                         details: ["kind": .text("underlyingError"), "apple": .number(-1), "sessionExpired": .flag(true),
                                   "vpn": .flag(true)])
    }

    /// The renewal Cartouche started by itself, failed as Apple said that
    /// the session SideStore renews with had expired, for the gallery's
    /// screens: as after Cartouche signed in again by itself, and Apple
    /// asked for a code the player did not type.
    func showSessionExpiredForGallery() {
        let failure = Self.sessionExpiredForGallery
        let message = CartoucheRenewal.playerMessage("Your session has expired. Please log in. (-1)", failure: failure)
        noteIfSessionExpired(failure)
        fail(CartoucheRenewal.Failure(message: message, failure: failure), automatic: true, fraction: 1)
    }

    /// The renewal Cartouche started by itself, failed as this iPhone did not
    /// answer through LocalDevVPN, connected, as SideStore tells it, for the
    /// gallery's screens.
    func showUnansweredForGallery() {
        let failure = CartoucheFailure(.vpn, stage: "InstallProvisioningProfiles", fraction: 0.6, seconds: 14,
                                       details: ["kind": .text("noVPN"), "vpn": .flag(true)])
        let message = CartoucheRenewal.playerMessage("VPN Connection Error:\nNo device found.\n\nPlease make sure LocalDevVPN is connected and running properly.",
                                                     failure: failure)
        fail(CartoucheRenewal.Failure(message: message, failure: failure), automatic: true, fraction: 0.6)
    }
    #endif
}

/// The automation of Shortcuts that renews Cartouche every night, as the
/// setup's last step, its page and the System page show it
/// (CartoucheNightlyRenewal): read again as each of them appears, and as
/// Cartouche comes back to the front.
@available(iOS 17.0, *)
@MainActor
final class CartoucheNightly: ObservableObject {
    static let shared = CartoucheNightly()

    @Published private(set) var state: CartoucheNightlyRenewal.State = .toMake
    /// Whether the player took the home's banner on the automation off
    /// (CartoucheSetup.nightlyLeft): the setup's step and the System page
    /// still offer it.
    @Published private(set) var isBannerHidden = UserDefaults.standard.bool(forKey: CartoucheNightly.bannerHiddenKey)

    private static let bannerHiddenKey = "Cartouche.nightly.bannerHidden"

    private init() {
        read()
    }

    /// Takes the home's banner on the automation off, for good.
    func hideBanner() {
        guard !isBannerHidden else { return }
        isBannerHidden = true
        UserDefaults.standard.set(true, forKey: Self.bannerHiddenKey)
    }

    /// Reads again the last run of Refresh All Apps from Shortcuts, as the
    /// built-in SideStore's support noted it (CartoucheShortcutRun).
    func read(at now: Date = Date()) {
        let defaults = UserDefaults.standard
        let state = CartoucheNightlyRenewal.state(
            run: CartoucheNightlyRenewal.Run(record: defaults.object(forKey: CartoucheNightlyRenewal.runKey)),
            made: defaults.object(forKey: CartoucheNightlyRenewal.madeKey) as? Date,
            expiration: CartoucheSignature.current().expirationDate, at: now)
        if state != self.state { self.state = state }
    }

    /// The player says they made the automation, on its page.
    func made() {
        UserDefaults.standard.set(Date(), forKey: CartoucheNightlyRenewal.madeKey)
        CartoucheReports.note("Renew every night: the player says they made the automation")
        read()
    }

    /// What the setup's step and the automation's page say of it.
    var detail: String {
        switch state {
        case .toMake: return CartoucheText.dailyToMake
        case .waiting(let since): return CartoucheText.dailyWaiting(CartoucheText.dateAndTime(since))
        case .notRunning(let since): return CartoucheText.dailyNotRunning(CartoucheText.dateAndTime(since))
        case .running: return CartoucheText.dailyRunning
        case .renewed(let at): return CartoucheText.dailyRenewed(CartoucheText.dateAndTime(at))
        case .failed(let at, .vpn): return CartoucheText.dailyFailedVPN(CartoucheText.dateAndTime(at))
        case .failed(let at, .interrupted): return CartoucheText.dailyInterrupted(CartoucheText.dateAndTime(at))
        case .failed(let at, .sideStore(let message)):
            // In Cartouche's words when it has its own, as for Renew now.
            let failure = CartoucheFailure.sideStore(outcome: nil, message: message, fraction: nil, seconds: nil,
                                                     vpn: true, pairing: CartouchePairing.exists)
            return CartoucheText.dailyFailed(CartoucheText.dateAndTime(at), CartoucheRenewal.playerMessage(message, failure: failure))
        case .stopped(let since): return CartoucheText.dailyStopped(CartoucheText.dateAndTime(since))
        }
    }

    /// What the System page's row says of it, beside Renew every night.
    var status: String {
        switch state {
        case .toMake: return CartoucheText.dailyStatusToMake
        case .waiting, .running: return CartoucheText.dailyStatusWaiting
        case .renewed: return CartoucheText.dailyStatusOn
        case .failed: return CartoucheText.dailyStatusFailed
        case .notRunning, .stopped: return CartoucheText.dailyStatusStopped
        }
    }

    /// The button that opens the automation's page, from the setup.
    var action: String {
        switch state {
        case .toMake: return CartoucheText.dailyMake
        case .failed, .notRunning, .stopped: return CartoucheText.dailyFix
        case .waiting, .running, .renewed: return CartoucheText.dailySee
        }
    }

    #if CARTOUCHE_GALLERY
    /// The automation as the gallery's WORK has it (launcher/Gallery): its
    /// last run at 4:00 this night, which renewed Cartouche, or which ran
    /// without LocalDevVPN; otherwise never made.
    func showForGallery(_ work: String?) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CartoucheNightlyRenewal.runKey)
        defaults.removeObject(forKey: CartoucheNightlyRenewal.madeKey)
        defaults.removeObject(forKey: Self.bannerHiddenKey)
        isBannerHidden = false
        let calendar = Calendar.current
        var started = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: Date()) ?? Date()
        if started > Date() { started = calendar.date(byAdding: .day, value: -1, to: started) ?? started }
        switch work {
        case "nightly-renewed":
            defaults.set(["started": started, "tunnel": true, "ended": started.addingTimeInterval(38)],
                         forKey: CartoucheNightlyRenewal.runKey)
        case "nightly-no-vpn":
            defaults.set(["started": started, "tunnel": false, "ended": started.addingTimeInterval(19),
                          "message": "VPN Connection Error:\nNo device found."], forKey: CartoucheNightlyRenewal.runKey)
        default:
            break
        }
        read()
    }
    #endif
}
