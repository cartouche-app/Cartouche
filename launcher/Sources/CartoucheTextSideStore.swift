//
//  CartoucheTextSideStore.swift
//  Cartouche
//
//  What Cartouche tells the player of the built-in SideStore's error, in
//  Cartouche.xcstrings with the other words (CartoucheText.swift): its own
//  words when Apple limits the requests or answers with a page, which
//  SideStore's would show as they are, when SideStore could not reach this
//  iPhone for the sign-in, which SideStore's would send to its own
//  settings, when it found no app group, which SideStore's would only name,
//  when the Apple ID has a certificate it does not hold, which SideStore's
//  tell in English, when LiveProcess, which it runs in, is missing from
//  the app, which LiveContainer's tell in English, sending the player to
//  the settings of other sideloaders, and when Apple refuses a new machine
//  for the sign-in, says its session has expired or refuses it without a
//  reason, which AnisetteKit's and Apple's own words tell in English. A
//  file of its own, since it reads CartoucheFailure and
//  CartoucheSignInMessage, which the storage tests (launcher/StorageTests)
//  build CartoucheText.swift without.
//

import Foundation

extension CartoucheText {
    // MARK: Apple's answers the built-in SideStore could not read

    static var appleTooManyRequests: String { s("apple.tooManyRequests", "Apple is refusing more requests for now, after too many in a short time from this Apple ID or from this network. Wait a while, then try again.") }
    static func applePage(_ status: Int) -> String { f("apple.page", "Apple’s servers sent back an error page (%lld) instead of an answer. Try again in a few minutes.", status) }
    static var appleUnreadable: String { s("apple.unreadable", "Cartouche could not read Apple’s answer. Check this iPhone’s connection, then try again.") }
    static func appleProvisioningRefused(_ status: Int) -> String { f("apple.provisioningRefused", "Apple is refusing, for now, to set up a new sign-in on this iPhone (%lld). Wait a while, then try again.", status) }

    /// What Cartouche tells the player of the built-in SideStore's MESSAGE,
    /// FAILURE being what Cartouche told of how its action ended: its own
    /// words when Apple limits the requests, answered with a page, or
    /// refuses a new machine, or LiveProcess is missing from the app, those
    /// of a SIGN-IN when it is one, also when SideStore closed before it
    /// finished, found no app group or met a certificate it does not hold,
    /// and when Apple says the sign-in's session has expired or refuses it
    /// without a reason; SideStore's otherwise, without the App Intents
    /// error's name.
    static func sideStoreMessage(_ message: String, failure: CartoucheFailure, signIn: Bool = false) -> String {
        let readable = CartoucheSignInMessage.readable(message)
        switch CartoucheSignInMessage.trouble(in: readable, failure: failure) {
        case .tooManyRequests?: return signIn ? signInTooManyRequests : appleTooManyRequests
        case .unreadable(let status?)?: return applePage(status)
        case .unreadable(nil)?: return appleUnreadable
        case .sideStoreQuit?: return signIn ? signInSideStoreQuit : readable
        case .noAppGroup?: return signIn ? signInNoAppGroup : readable
        case .otherCertificate?:
            guard signIn else { return readable }
            #if os(iOS)
            // Installed by the player's own SideStore, whose certificate
            // the sign-in takes.
            if CartoucheSideStoreInstall.isSideStoreInstall { return signInOtherCertificateSideStore }
            #endif
            return signInOtherCertificate
        case .noLiveProcess?: return noLiveProcess
        case .provisioningRefused(let status)?: return signIn ? signInProvisioningRefused(status) : appleProvisioningRefused(status)
        case .sessionExpired?: return signIn ? signInSessionExpired : readable
        case .cannotComplete?: return signIn ? signInCannotComplete : readable
        case nil:
            guard signIn, let trouble = CartoucheSignInMessage.deviceTrouble(in: failure) else { return readable }
            // Before Apple, or once it accepted the account.
            switch CartoucheSignInMessage.deviceMoment(of: failure) {
            case .beforeApple: return deviceMessage(trouble) + " " + deviceBeforeApple
            case .afterApple: return deviceMessage(trouble) + " " + deviceAfterApple
            case .elsewhere: return deviceMessage(trouble)
            }
        }
    }

    // MARK: Apple's refusals, which SideStore passes on in English

    /// Apple refused, for now, the new machine Cartouche asked it for, which
    /// signs the sign-in's requests (app/patches/sidestore/0024): no server
    /// changes that, and the sign-in waits as for Apple's limits
    /// (CartoucheSignInPause).
    static func signInProvisioningRefused(_ status: Int) -> String { f("signIn.provisioningRefused", "Apple is refusing, for now, to set up a new sign-in on this iPhone (%lld), before your Apple ID is even sent. There is nothing to reset or reinstall. Wait for the countdown to end, then sign in again.", status) }
    static var signInSessionExpired: String { s("signIn.sessionExpired", "Apple says this iPhone’s sign-in has expired (1100). There is nothing to reset or reinstall: sign in again, and type the code Apple sends if it asks for one.") }
    static var signInCannotComplete: String { s("signIn.cannotComplete", "Apple refused this sign-in without saying why (-22405). There is nothing to reset or reinstall. Wait a few hours, then sign in again, once. If Apple still refuses the next day, sign in at account.apple.com in Safari: Apple says there whether your Apple ID needs anything from you.") }

    // MARK: The built-in SideStore, closed before it finished

    static var signInSideStoreQuit: String { s("signIn.sideStoreQuit", "The built-in SideStore closed before it finished. Restart this iPhone, then try again. If it closes again, install the update offered in Settings › General › Software Update, if there is one.") }

    // MARK: The built-in SideStore, without its app group

    /// What a sign-in that stopped as the built-in SideStore found no app
    /// group says: what the setup and the guide say of the IPA for an Apple
    /// ID that a signing app signed (CartoucheTextSigning.swift), with the
    /// version of this copy, which names the IPA to sign instead.
    static var signInNoAppGroup: String {
        signedElsewhere(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    // MARK: The Apple ID's certificate, made elsewhere

    static var signInOtherCertificate: String { s("signIn.otherCertificate", "This Apple ID already has a certificate that Cartouche does not hold, made by another app or computer, and Cartouche never revokes it. If you installed Cartouche with another Apple ID, sign in with that one. Otherwise, install Cartouche again over this copy with the Cartouche Installer on your computer, with this Apple ID: it gives Cartouche its certificate. Then sign in again.") }

    // MARK: LiveProcess, missing from the app

    /// What a sign-in, a renewal or an update of Cartouche that stopped as
    /// LiveProcess is missing from the app says, and the System page after
    /// them: up to 0.13.1, LiveContainer's words, in English, which send the
    /// player to the settings of LiveContainer+SideStore and of other
    /// sideloaders, and the update's notice said before them to check
    /// LocalDevVPN and try again.
    static var noLiveProcess: String { s("app.noLiveProcess", "This copy of Cartouche is missing the part of the app the built-in SideStore runs in (LiveProcess): without it, Cartouche can neither sign in to your Apple ID, nor renew or update itself. Install Cartouche again over this copy with the Cartouche Installer, on your computer, with the same Apple ID: it puts that part back. Your games and saves stay.") }

    // MARK: This iPhone, through LocalDevVPN

    static var deviceVPN: String { s("signIn.device.vpn", "LocalDevVPN is not connected, or does not carry this iPhone’s traffic. Connect it, or disconnect it and connect it again.") }
    static var deviceWiFi: String { s("signIn.device.wifi", "This iPhone is not on Wi-Fi, which LocalDevVPN needs to reach it. Join a Wi-Fi network.") }
    static var devicePairing: String { s("signIn.device.pairing", "This iPhone did not accept its pairing file. Put the pairing file in Cartouche again with the Cartouche Installer, on your computer.") }
    static var devicePairingRefused: String { s("signIn.device.pairingRefused", "This iPhone refused its pairing file, made before it stopped trusting your computer, or for another device. On your computer, in the Cartouche Installer’s Settings, choose Delete the stored pairing, choose this iPhone again, then Put the pairing file in Cartouche again, and tap Trust on this iPhone when it asks.") }
    static var deviceOlderPairing: String { s("signIn.device.olderPairing", "This iPhone’s pairing file is of an older kind, which Cartouche can no longer use on this iPhone since iOS 26.4. On your computer, choose Put the pairing file in Cartouche again in the Cartouche Installer: it makes one of the newer kind.") }
    static var deviceNoAnswer: String { s("signIn.device.noAnswer", "This iPhone did not answer through LocalDevVPN. Disconnect LocalDevVPN, connect it again, then try again. If it happens again, restart this iPhone.") }
    static var deviceBeforeApple: String { s("signIn.device.beforeApple", "Nothing was sent to Apple yet: sign in again once this is fixed.") }
    static var deviceAfterApple: String { s("signIn.device.afterApple", "Apple accepted your Apple ID: only this iPhone is left to register, which Cartouche does by itself once LocalDevVPN is connected.") }

    /// What to do about TROUBLE.
    static func deviceMessage(_ trouble: CartoucheSignInMessage.DeviceTrouble) -> String {
        switch trouble {
        case .vpn: return deviceVPN
        case .wifi: return deviceWiFi
        case .pairing: return devicePairing
        case .pairingRefused: return devicePairingRefused
        case .olderPairing: return deviceOlderPairing
        case .noAnswer: return deviceNoAnswer
        }
    }

    /// What Cartouche tells the player when registering this iPhone alone
    /// (CartoucheAccount.registerDevice) ended with SideStore's MESSAGE, as
    /// FAILURE tells: what to do when SideStore did not reach the iPhone,
    /// the sign-in's words otherwise.
    static func deviceStepMessage(_ message: String, failure: CartoucheFailure) -> String {
        if let trouble = CartoucheSignInMessage.deviceTrouble(in: failure) { return deviceMessage(trouble) }
        return sideStoreMessage(message, failure: failure, signIn: true)
    }
}
