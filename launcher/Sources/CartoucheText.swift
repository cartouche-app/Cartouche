//
//  CartoucheText.swift
//  Cartouche
//
//  The launcher's words, in Cartouche.xcstrings (English, French, Spanish and
//  German). Each
//  call also carries the English text, which shows if a translation is missing.
//  They call the device Cartouche runs on the iPhone: on an iPad, the iPad
//  (CartoucheDeviceWords.swift).
//

import Foundation

enum CartoucheText {
    /// The app's bundle. On the Mac (builder/mac), the console's words are
    /// read from the folder of the language the app speaks, which its
    /// settings can change while it runs.
    nonisolated(unsafe) static var bundle = Bundle(for: CartoucheCatalog.self)

    #if os(macOS)
    /// The reader's language, in which the games' languages are named and
    /// numbers and days written: on the Mac, the one the console speaks,
    /// which the app's settings may choose other than the Mac's
    /// (builder/mac, ConsoleView.swift).
    nonisolated(unsafe) static var locale = Locale.current
    #else
    /// The reader's language, in which the games' languages are named and
    /// numbers and days written: the iPhone's.
    static var locale: Locale { Locale.current }
    #endif

    static func s(_ key: String, _ english: String) -> String {
        let text = NSLocalizedString(key, tableName: "Cartouche", bundle: bundle, value: english, comment: "")
        #if canImport(UIKit)
        return CartoucheDevice.isPad ? CartoucheDeviceWords.onIPad(text) : text
        #else
        // The storage's tests on a Mac (launcher/StorageTests), without the device.
        return text
        #endif
    }

    static func f(_ key: String, _ english: String, _ arguments: CVarArg...) -> String {
        String(format: s(key, english), locale: locale, arguments: arguments)
    }

    // MARK: Tabs and titles

    static var gamesTab: String { s("tab.games", "Games") }
    static var systemTab: String { s("tab.system", "System") }
    static var needsNewerIOS: String { s("app.needsIOS17", "Cartouche needs iOS 17 or later.") }

    // MARK: Catalogue

    static var emptyMessage: String { s("games.empty.message", "Import the IPA of a supported game, made from your own copy.") }
    static var noSheet: String { s("games.noSheet", "No sheet yet") }
    static var importCopy: String { s("action.import", "Import my copy") }
    /// Beside Import my copy, while the player has no game: the guide,
    /// which says how a game is made from their own copy.
    static var howToGetGame: String { s("action.howToGetGame", "How to get a game") }
    static var play: String { s("action.play", "Play") }
    static var done: String { s("action.done", "Done") }

    // MARK: Console

    static var homeLibrary: String { s("home.library", "My library") }
    static var importTile: String { s("home.import", "Import a game") }
    static var allGames: String { s("home.all", "All games") }
    static func allGamesDetail(_ count: Int) -> String { f("home.all.detail", "%lld games have a profile in nxnative. Cartouche plays each one from your own copy.", count) }
    static var controllerConnected: String { s("home.controller", "Controller connected") }
    static func daysLeftShort(_ days: Int) -> String { f("home.daysLeft", "%lld\u{00A0}d", days) }
    static var details: String { s("action.details", "Details") }
    static var dockImport: String { s("dock.import", "Import") }
    static var hintOpen: String { s("hint.open", "Open") }
    static var hintFilter: String { s("hint.filter", "Filter") }
    static var hintBack: String { s("hint.back", "Back") }
    static var filterAll: String { s("library.filter.all", "All") }
    static var searchPrompt: String { s("library.search", "Name or title ID") }

    // MARK: Where a game plays

    static var statusReadyShort: String { ready }
    static var statusIPhoneShort: String { s("status.iphone.short", "On iPhone") }
    static var statusMacShort: String { s("status.mac.short", "On Mac") }
    static var statusBringupShort: String { s("status.bringup.short", "In bring-up") }
    static var statusUnknownShort: String { s("status.unknown.short", "Not tried") }
    static var statusIPhoneLong: String { s("status.iphone.long", "nxnative plays it on the iPhone and the Mac.") }
    static var statusMacLong: String { s("status.mac.long", "nxnative plays it on the Mac; nobody has reported it on an iPhone yet.") }
    static var statusBringupLong: String { s("status.bringup.long", "nxnative is still bringing it up: it may not start yet.") }
    static var statusUnknownLong: String { s("status.unknown.long", "nxnative’s profile does not say where it plays yet.") }
    static var statusStoredShort: String { s("status.stored.short", "In storage") }
    static var statusStoredLong: String { s("status.stored.long", "Its IPA is in your games folder: install it to play it on this iPhone.") }
    static var statusUpdateShort: String { s("status.update.short", "Update") }
    static var statusUpdateLong: String { s("status.update.long", "A newer IPA of it is in your games folder: updating keeps your saves.") }
    static func statusStoredOffline(_ server: String) -> String { f("status.stored.offline", "%@ is offline: install this game once the iPhone is back on its network or on your VPN.", server) }
    static func statusUpdateOffline(_ server: String) -> String { f("status.update.offline", "%@ is offline: update this game once the iPhone is back on its network or on your VPN.", server) }
    // A game Cartouche Cloud built for the player, in the library and on its
    // sheet, which the console shares with the Mac: the rest of Cartouche
    // Cloud's words are the iPhone's alone (CartoucheTextCloud.swift).
    static var cloudName: String { s("cloud.name", "Cartouche Cloud") }
    static var statusCloudShort: String { s("status.cloud.short", "In Cartouche Cloud") }
    static var statusCloudLong: String { s("status.cloud.long", "Cartouche Cloud built it for you: install it to play it on this iPhone.") }
    static var statsCloud: String { statsStored(cloudName) }
    static var cloudInstall: String { installFrom(cloudName) }
    static func cloudKeptUntil(_ moment: String) -> String { f("cloud.keptUntil", "Cartouche Cloud keeps it until %@, then deletes it.", moment) }

    /// A genre of nxnative.json, or nil for "other".
    static func genre(_ genre: String) -> String? {
        switch genre {
        case "action": return s("genre.action", "Action")
        case "adventure": return s("genre.adventure", "Adventure")
        case "rpg": return s("genre.rpg", "Role-playing")
        case "puzzle": return s("genre.puzzle", "Puzzle")
        case "strategy": return s("genre.strategy", "Strategy")
        case "simulation": return s("genre.simulation", "Simulation")
        case "racing": return s("genre.racing", "Racing")
        case "sports": return s("genre.sports", "Sports")
        case "board": return s("genre.board", "Board game")
        case "card": return s("genre.card", "Card game")
        case "family": return s("genre.family", "Family")
        case "music": return s("genre.music", "Music")
        default: return nil
        }
    }

    // MARK: Fit on this iPhone

    static var ready: String { s("status.ready", "Ready") }
    static var fitRecommended: String { s("status.recommended", "Runs on this iPhone") }
    static var fitUntested: String { s("status.untested", "Not tried on this iPhone yet") }
    static var fitNotRecommended: String { s("status.notRecommended", "Not recommended on this iPhone") }
    static var fitUnsupported: String { s("status.unsupported", "Not supported on this iPhone") }

    static func reasonIOS(_ version: String) -> String { f("reason.ios", "Needs iOS %@ or later.", version) }
    static var reasonGPU: String { s("reason.gpu", "nxnative’s games need an iPhone 15 Pro or later, or an iPad with an M1 chip or later: this iPhone’s GPU cannot read their compressed textures, and a game stops there before its first image.") }
    static var reasonIML: String { s("reason.iml", "Needs Increased Memory Limit, which is not active for Cartouche yet.") }
    static func reasonMemory(needed: String, limit: String) -> String {
        f("reason.memory", "Needs about %1$@; a game may use %2$@ on this iPhone.", needed, limit)
    }
    static var reasonDoesNotRun: String { s("reason.doesNotRun", "Testers could not run it on this iPhone model.") }

    static func resultStatus(_ status: String) -> String {
        switch status {
        case "playable": return s("result.playable", "Playable")
        case "playable-with-issues": return s("result.playableWithIssues", "Playable with issues")
        case "boots": return s("result.boots", "Starts")
        case "does-not-run": return s("result.doesNotRun", "Does not run")
        default: return status
        }
    }

    static func platform(_ platform: String) -> String {
        switch platform {
        case "switch2": return s("platform.switch2", "Switch 2")
        case "switch": return s("platform.switch", "Switch")
        default: return platform
        }
    }

    // MARK: Game sheet

    static var onThisIPhone: String { s("sheet.onThisIPhone", "On this iPhone") }
    static var requirementsMet: String { s("sheet.requirements.met", "This iPhone has what it needs") }
    static var sheetDetails: String { s("sheet.details", "Technical details") }
    static func iosRequirement(_ version: String) -> String { f("sheet.ios", "iOS %@ or later", version) }
    static func iosCurrent(_ version: String) -> String { f("sheet.ios.current", "This iPhone: iOS %@", version) }
    static var imlRequirement: String { s("sheet.memory.iml", "Increased Memory Limit") }
    static func imlActive(_ limit: String) -> String { f("sheet.memory.iml.active", "Active: %@ for Cartouche", limit) }
    static func imlInactive(_ limit: String) -> String { f("sheet.memory.iml.inactive", "Not active: %@ for Cartouche", limit) }
    static var memoryRequirement: String { s("sheet.memory", "Memory") }
    static func memoryNeeded(_ amount: String) -> String { f("sheet.memory.peak", "Needs about %@", amount) }
    static var bcRequirement: String { s("sheet.gpu.bc", "BC texture compression") }
    static var gpuSupported: String { s("sheet.gpu.supported", "Supported by this GPU") }
    static var gpuUnsupported: String { s("sheet.gpu.unsupported", "Not supported by this GPU") }
    /// The player's build of the game converts its BC textures for this
    /// GPU, which reads none (CartoucheBCConversion): BC1 to BC3 to ASTC,
    /// the others decompressed, so not "to ASTC" alone.
    static var gpuConverted: String { s("sheet.gpu.converted", "Textures converted for this GPU by this game’s build") }
    static var recommendedSettings: String { s("sheet.recommended", "Recommended settings") }
    static var resolution: String { s("sheet.resolution", "Resolution") }
    static var mode: String { s("sheet.mode", "Mode") }
    static func modeName(_ mode: String) -> String {
        switch mode {
        case "handheld": return s("sheet.mode.handheld", "Handheld")
        case "docked": return s("sheet.mode.docked", "Docked")
        default: return mode
        }
    }
    static var results: String { s("sheet.results", "Testers’ results") }
    static var noResults: String { s("sheet.results.none", "No result yet.") }
    static var thisModel: String { s("sheet.result.thisModel", "This iPhone model") }
    static func peak(_ amount: String) -> String { f("sheet.result.peak", "Memory peak: %@", amount) }
    static var resultsTranslated: String { s("sheet.results.translated", "Testers’ notes translated by the iPhone") }
    static var noSheetMessage: String { s("sheet.noSheet.message", "Cartouche has no sheet for this game yet: it can still start it, without checking what the game needs.") }
    static var sheetNxnative: String { s("sheet.nxnative", "In nxnative") }
    static var sheetEngine: String { s("sheet.engine", "Engine") }
    static var sheetBuild: String { s("sheet.build", "Game version") }
    static var sheetSDK: String { s("sheet.sdk", "SDK") }
    static var sheetTitleID: String { s("sheet.titleID", "Title ID") }
    static func region(_ region: String) -> String {
        switch region {
        case "asia": return s("region.asia", "Asian release")
        case "japan": return s("region.japan", "Japanese release")
        case "korea": return s("region.korea", "Korean release")
        case "china": return s("region.china", "Chinese release")
        default: return region
        }
    }

    // MARK: Setup

    static var setupTitle: String { s("setup.title", "Setup") }
    static var setupIntroTitle: String { s("setup.intro.title", "Before your first game") }
    static var setupIntro: String { s("setup.intro", "Three steps, once on this iPhone, then an automation that renews Cartouche every night.") }
    static var setupAllDone: String { s("setup.done.title", "All set") }
    static var setupAllDoneDetail: String { s("setup.done.detail", "Cartouche signs your games and renews itself. There is nothing more to do here.") }
    static var setupSessionExpiredTitle: String { s("setup.sessionExpired.title", "One step to do again") }
    static var setupSessionExpiredDetail: String { s("setup.sessionExpired.detail", "Apple asks for a new sign-in with your Apple ID. Cartouche renews itself again as soon as it has gone through; your games and saves stay.") }
    static var setupAllDoneButNightly: String { s("setup.done.nightly", "Cartouche signs your games. One last step: the automation that renews it every night, even while it stays closed.") }
    static func setupStepDone(_ step: String) -> String { f("setup.step.done", "%@, done", step) }
    static var setupPairingTitle: String { s("setup.pairing.title", "Pairing file") }
    static var setupPairingHow: String { s("setup.pairing.how", "Only a computer can make it: the Cartouche Installer puts it in Cartouche as it installs it, and this step ticks itself. You can also choose it here, or open it with Cartouche.") }
    static var setupPairingDone: String { s("setup.pairing.done", "Received. The built-in SideStore uses it to install and renew apps on this iPhone.") }
    static var setupPairingChoose: String { s("setup.pairing.choose", "Choose the file") }
    static var setupPairingReplace: String { s("setup.pairing.replace", "Choose another file") }
    static var setupPairingInvalid: String { s("setup.pairing.invalid", "This file is not a pairing file. The Cartouche Installer puts the right one in Cartouche: Put the pairing file in Cartouche again.") }
    static var setupPairingFailed: String { s("setup.pairing.failed", "The pairing file was refused") }
    static var setupAppleIDTitle: String { s("setup.appleID.title", "Apple ID") }
    static var setupAppleIDHow: String { s("setup.appleID.how", "Sign in once, here in Cartouche: Cartouche then takes its certificate and renews itself every week.") }
    static func setupAppleIDDone(_ appleID: String) -> String { f("setup.appleID.done", "Signed in: %@", appleID) }
    static func setupAppleIDUnfinished(_ appleID: String) -> String { f("setup.appleID.unfinished", "The sign-in with %@ stopped before Cartouche got its certificate. Sign in again.", appleID) }
    static func setupAppleIDSessionExpired(_ appleID: String) -> String { f("setup.appleID.sessionExpired", "Apple says the session of %@ has expired: Cartouche can no longer renew itself. Sign in again with this Apple ID.", appleID) }
    static var setupSignIn: String { s("setup.appleID.signIn", "Sign In") }
    static func setupAppleIDDevice(_ appleID: String) -> String { f("setup.appleID.device", "Signed in: %@. This iPhone is left to register, which Cartouche does by itself once LocalDevVPN is connected.", appleID) }
    static var setupCertificateTitle: String { s("setup.certificate.title", "Certificate") }
    static var setupCertificateHow: String { s("setup.certificate.how", "Comes by itself at the end of the sign-in with your Apple ID.") }
    static var setupCertificateDone: String { s("setup.certificate.done", "Cartouche signs your games with it.") }
    static var setupCertificateChecking: String { s("setup.certificate.checking", "Cartouche checks that iOS accepts it.") }
    static var setupCertificateRefused: String { s("setup.certificate.refused", "iOS no longer accepts it, perhaps after an install from another computer. Sign in again with your Apple ID: Cartouche takes a new one.") }
    static var setupCertificateRenewing: String { s("setup.certificate.renewing", "iOS no longer accepts it. Cartouche signs in again with your Apple ID to take a new one…") }
    static var setupCheckAgain: String { s("setup.checkAgain", "Check again") }
    static var setupVPNTitle: String { s("setup.vpn.title", "LocalDevVPN, for renewals") }
    static var setupVPNHow: String { s("setup.vpn.how", "This free VPN from the App Store lets Cartouche renew itself every 7 days, while it is on. Its traffic never leaves this iPhone.") }
    static var setupVPNOpen: String { s("setup.vpn.open", "Open LocalDevVPN") }
    static var setupBannerTitle: String { s("setup.banner.title", "Set up Cartouche") }
    static var setupBannerDetail: String { s("setup.banner.detail", "Once, before your first game") }
    static var setupBannerUnfinishedDetail: String { s("setup.banner.unfinished", "The sign-in stopped before the certificate") }
    static var setupBannerRenewal: String { s("setup.banner.renewal", "Renewal to set up") }
    static var setupBannerRenewalDetail: String { s("setup.banner.renewal.detail", "Add your pairing file") }
    /// Once the first game is installed, under Renew every night.
    static var setupBannerNightlyDetail: String { s("setup.banner.nightly.detail", "So that Cartouche renews itself, even if you leave it closed for a week.") }
    static var setupBannerNightlyHide: String { s("setup.banner.nightly.hide", "Hide this reminder") }
    static var setupBannerSignInDetail: String { s("setup.banner.renewal.signIn", "Sign in with your Apple ID") }
    static var setupBannerCertificate: String { s("setup.banner.certificate", "The certificate no longer works") }
    static var setupBannerCertificateDetail: String { s("setup.banner.certificate.detail", "Sign in again to play") }
    static var setupBannerCertificateRenewing: String { s("setup.banner.certificate.renewing", "Cartouche signs in again…") }
    static var setupBannerDeviceDetail: String { s("setup.banner.device.detail", "Connect LocalDevVPN to register this iPhone") }
    static var setupBannerDeviceWorking: String { s("setup.banner.device.working", "Cartouche registers this iPhone…") }
    static var setupStatusDone: String { s("setup.status.done", "Done") }
    static var setupStatusToDo: String { s("setup.status.todo", "To do") }

    // MARK: The Apple ID sign-in

    static var signInTitle: String { s("signIn.title", "Sign in with your Apple ID") }
    static var signInIntro: String { s("signIn.intro", "Once on this iPhone: Cartouche registers it with your account, takes its certificate and renews itself every week, without asking you again.") }
    static var signInAppleID: String { s("signIn.appleID", "Apple ID (email or phone number)") }
    static var signInPassword: String { s("signIn.password", "Password") }
    static var signInFreeAccount: String { s("signIn.freeAccount", "A free Apple ID will do. Your password goes to Apple only, and stays in this iPhone’s keychain.") }
    static var signInButton: String { s("signIn.button", "Sign In") }
    static var signInAgain: String { s("signIn.again", "Sign in again") }
    static var signInWorking: String { s("signIn.working", "Signing in, registering this iPhone and fetching the certificate…") }
    static var signInCodeTitle: String { s("signIn.code.title", "Verification code") }
    static var signInCodeTrustedDevice: String { s("signIn.code.trustedDevice", "Apple sent a code to your other Apple devices. Allow the sign-in there, then type the code here.") }
    static func signInCodeSMS(_ phone: String) -> String { f("signIn.code.sms", "Apple sent a code by text message to %@.", phone) }
    static var signInCodeSMSAnyNumber: String { s("signIn.code.sms.any", "Apple sent a code by text message to your phone number.") }
    static func signInCodeVoice(_ phone: String) -> String { f("signIn.code.voice", "Apple is calling %@ with a code.", phone) }
    static var signInCodeVoiceAnyNumber: String { s("signIn.code.voice.any", "Apple is calling your phone number with a code.") }
    static var signInCodePlaceholder: String { s("signIn.code.placeholder", "6-digit code") }
    static var signInCodeContinue: String { s("signIn.code.continue", "Continue") }
    static var signInCodeBySMS: String { s("signIn.code.bySMS", "Get a text message instead") }
    static var signInCodeByDevice: String { s("signIn.code.byDevice", "Send it to my Apple devices") }
    static var signInFailedTitle: String { s("signIn.failed.title", "The sign-in did not go through") }
    static var signInOpenPage: String { s("signIn.openPage", "Open the page") }
    static var signInVPNTitle: String { s("signIn.vpn.title", "Connect LocalDevVPN first") }
    static var signInVPNHow: String { s("signIn.vpn.how", "Cartouche goes through it to register this iPhone with your account, as for each renewal.") }
    static var signInUnavailable: String { s("signIn.unavailable", "The built-in SideStore did not load. Close Cartouche, open it again, then sign in.") }
    static var signInKeychainFailed: String { s("signIn.keychainFailed", "Cartouche could not hand your Apple ID to the built-in SideStore. Try again.") }
    static var signInCertificateUnopened: String { s("signIn.certificateUnopened", "The built-in SideStore signed in, but Cartouche could not open the certificate it took. Copy the report for whoever helps you.") }
    static var signInTooManyRequests: String { s("signIn.tooManyRequests", "Apple is refusing new sign-ins for now: too many attempts in a short time, from this Apple ID or from this network. There is nothing to reset or reinstall. Wait for the countdown to end, then sign in again: trying sooner can make the wait longer.") }
    static func signInWait(_ remaining: String) -> String { f("signIn.wait", "Try again in %@", remaining) }
    static var signInVPNWaiting: String { s("signIn.vpnWait", "Waiting for LocalDevVPN: Cartouche goes on by itself as soon as it is connected.") }
    static var signInVPNGoOn: String { s("signIn.vpnWait.goOn", "Go on without waiting") }
    static var signInDeviceTitle: String { s("signIn.device.title", "Last step: this iPhone") }
    static var signInDeviceHow: String { s("signIn.device.how", "Apple accepted your Apple ID. Cartouche only has to register this iPhone with it, through LocalDevVPN: no password, no code.") }
    static var signInDeviceButton: String { s("signIn.device.button", "Register this iPhone") }
    static var signInDeviceWorking: String { s("signIn.device.working", "Registering this iPhone with your account…") }
    static var signInDeviceFailedTitle: String { s("signIn.device.failed.title", "This iPhone is not registered yet") }
    // What Cartouche says instead of SideStore's words when Apple limits the
    // requests or answers with a page: CartoucheTextSideStore.swift.

    // MARK: System

    static var memory: String { s("system.memory", "Memory") }
    static var memoryLimit: String { s("system.memory.limit", "Limit for Cartouche") }
    static var memoryUsed: String { s("system.memory.used", "Used now") }
    static var memoryAvailable: String { s("system.memory.available", "Available now") }
    static var imlOn: String { s("system.memory.iml.on", "Active") }
    static var imlOff: String { s("system.memory.iml.off", "Not active") }
    static var measureAgain: String { s("system.memory.measure", "Measure again") }
    static var memoryUnavailable: String { s("system.memory.unavailable", "iOS gives no memory limit here.") }
    static var memoryFooter: String { s("system.memory.footer", "Your games share this limit. With Increased Memory Limit, an iPhone with 12 GB allows Cartouche about 8 GiB.") }
    static func memoryKnown(_ limit: String) -> String { f("system.memory.known", "Testers measured %@ on this model with Increased Memory Limit.", limit) }
    static var signature: String { s("system.signature", "Signature") }
    static var expires: String { s("system.signature.expires", "Expires") }
    static var daysLeft: String { s("system.signature.daysLeft", "Days left") }
    static var expired: String { s("system.signature.expired", "Expired") }
    static var renewed: String { s("system.signature.renewed", "Last renewed") }
    static var team: String { s("system.signature.team", "Apple account team") }
    static var profileUnknown: String { s("system.signature.unknown", "Cartouche could not read its provisioning profile.") }
    static var signatureFooter: String { s("system.signature.footer", "Cartouche renews itself each time you open it in its last 3 days, and connects LocalDevVPN for it. Once expired, it no longer opens: install it again with the Cartouche Installer.") }
    static var renewNow: String { s("system.signature.renew", "Renew now") }
    static var renewing: String { s("system.signature.renewing", "Renewing…") }
    static var renewingByItself: String { s("system.signature.renewing.auto", "Cartouche renews itself…") }
    static var renewUnavailable: String { s("system.signature.renew.unavailable", "The built-in SideStore did not load. Close Cartouche, open it again, then renew.") }
    static var renewFailed: String { s("system.signature.renew.failed", "The renewal did not go through") }
    static var renewSessionExpired: String { s("system.signature.renew.sessionExpired", "Apple says the session of your Apple ID has expired: Cartouche can no longer renew or update itself until you sign in again. Choose Sign in again, on the System page, with the same Apple ID: Cartouche then renews itself. Your games and saves stay.") }
    static var renewRevoked: String { s("system.signature.renew.revoked", "Apple revoked the certificate Cartouche is signed with, most likely because another app or computer took a new one with the same Apple ID. Cartouche can no longer renew or update itself with this certificate: install Cartouche again over this copy with the Cartouche Installer, on your computer, with the same Apple ID. Your games and saves stay.") }
    static var automaticRenewal: String { s("system.auto", "Automatic renewal") }
    static var renewEveryNight: String { s("system.auto.daily", "Renew every night") }
    static var alerts: String { s("system.auto.alerts", "Expiry alerts") }
    static var alertsOn: String { s("system.auto.alerts.on", "On") }
    static var alertsTurnOn: String { s("system.auto.alerts.turnOn", "Turn on") }
    static var alertsInSettings: String { s("system.auto.alerts.settings", "Turn on in Settings") }
    static var automaticRenewalFooter: String { s("system.auto.footer", "With alerts on, Cartouche warns you 24 hours and 6 hours before it expires.") }
    static var thisIPhone: String { s("system.device", "This iPhone") }
    static var model: String { s("system.device.model", "Model") }
    static var chip: String { s("system.device.chip", "Chip") }
    static var ram: String { s("system.device.ram", "Memory") }
    static var version: String { s("system.cartouche.version", "Version") }
    static var basedOn: String { s("system.cartouche.basedOn", "Based on") }
    static var sheets: String { s("system.cartouche.sheets", "Game sheets") }
    static var coversCredit: String { s("system.covers.credit", "Covers, artworks and descriptions of the games: IGDB.com.") }
    /// The apps installed in Cartouche that are not nxnative games
    /// (docs/decisions/154.md).
    static var otherAppsTitle: String { s("system.otherApps", "Other installed apps") }
    static var otherAppsFooter: String { s("system.otherApps.footer", "IPAs you installed that are not nxnative games: the console shows games only. They open in Cartouche’s place.") }
    static var openApp: String { s("action.open", "Open") }
    static var otherAppUninstallMessage: String { s("system.otherApps.uninstall", "The app and its data leave this iPhone.") }

    // MARK: Cartouche's updates

    static var updatesTitle: String { s("system.updates", "Updates") }
    static var updatesFooter: String { s("system.updates.footer", "New versions install without a computer, through LocalDevVPN, which Cartouche connects. Cartouche then closes: open it again. Your games and saves stay.") }
    static var updateAvailable: String { s("system.updates.available", "New version") }
    static func updateTo(_ version: String) -> String { f("system.updates.install", "Install Cartouche %@", version) }
    static var updateNeedsSetup: String { s("system.updates.needsSetup", "Finish setting up Cartouche first, or install this version from a computer with the Cartouche Installer, over this copy: your games and saves stay.") }
    static var updateNotes: String { s("system.updates.notes", "What’s new") }
    static func updateUpToDate(_ version: String) -> String { f("system.updates.upToDate", "Cartouche %@ is the latest version.", version) }
    static var updateNotChecked: String { s("system.updates.notChecked", "Cartouche has not looked for an update yet.") }
    static var updateCheck: String { s("system.updates.check", "Check for an update") }
    static func updateCheckFailed(_ reason: String) -> String { f("updates.check.failed", "Cartouche could not look for an update: %@", reason) }
    static var updateCheckFailedTitle: String { s("updates.check.failed.title", "The update check did not go through") }
    static func updateSourceStatus(_ status: Int) -> String { f("updates.source.status", "its source answered with error %lld.", status) }
    static var updateUnavailable: String { s("updates.unavailable", "The built-in SideStore did not load. Close Cartouche, open it again, then update.") }
    static func updateOfferTitle(_ version: String) -> String { f("updates.offer.title", "Cartouche %@ is available", version) }
    static func updateOfferMessage(_ running: String) -> String { f("updates.offer.message", "You have version %@. Cartouche installs the new one without a computer, through LocalDevVPN, then closes: open it again. Your games and saves stay.", running) }
    static func updateSize(_ size: String) -> String { f("updates.offer.size", "Download: %@", size) }
    static var updateNow: String { s("updates.now", "Update") }
    static var updateLater: String { s("updates.later", "Later") }
    static func updatePreparingTitle(_ version: String) -> String { f("updates.preparing.title", "Updating to Cartouche %@", version) }
    static var updatePreparingMessage: String { s("updates.preparing.message", "Cartouche downloads the new version, checks it and signs it. Keep Cartouche open.") }
    static func updateInstallingTitle(_ version: String) -> String { f("updates.installing.title", "Installing Cartouche %@", version) }
    static var updateInstallingMessage: String { s("updates.installing.message", "Cartouche goes to the home screen for iOS to install the new version. Open it again in a few seconds.") }
    static var updateLeaveNow: String { s("updates.leave", "Go to the home screen") }
    static func updateInstalledTitle(_ version: String) -> String { f("updates.installed.title", "Cartouche %@ is installed", version) }
    static var updateInstalledMessage: String { s("updates.installed.message", "Close Cartouche and open it again to use the new version.") }
    static var updateFailedTitle: String { s("updates.failed.title", "The update did not go through") }
    static func updateFailed(_ reason: String) -> String { f("updates.failed.message", "Check that LocalDevVPN is connected, then try again from the System page. SideStore says: %@", reason) }
    static var updateUnfinishedTitle: String { s("updates.unfinished.title", "The update did not finish") }
    static func updateUnfinished(_ version: String) -> String { f("updates.unfinished.message", "Cartouche closed before version %@ was installed. Try again from the System page.", version) }
    static var updatedMessage: String { s("updates.done.message", "Your games, their saves and Cartouche’s settings are all still here.") }

    // MARK: What's new (CartoucheWhatsNewView.swift)

    static func whatsNewTitle(_ version: String) -> String { f("whatsNew.title", "What’s new in Cartouche %@", version) }
    static var whatsNewContinue: String { s("whatsNew.continue", "Continue") }
    static var releaseNotesTitle: String { s("system.releaseNotes", "What’s new") }

    // MARK: Renewing every night

    static var dailyStepAutomation: String { s("daily.step2", "In Shortcuts, open Automation, then tap +.") }
    static var dailyStepTime: String { s("daily.time", "Choose Time of Day: 4:00 AM for instance, a time when the iPhone charges and is online, every day. Choose Run Immediately, then tap Next.") }
    static var dailyStepVPN: String { s("daily.vpn", "Tap New Blank Automation, then add the Enable LocalDevVPN action: it connects LocalDevVPN without opening it. An older LocalDevVPN calls it Start LocalDevVPN.") }
    static var dailyStepAction: String { s("daily.refresh", "Then add Refresh All Apps, among Cartouche’s actions and not LiveContainer’s, and tap Done.") }
    static var dailyTailscale: String { s("daily.tailscale", "With Tailscale, add its Connect action last, among those of the Tailscale app: LocalDevVPN turned Tailscale off, and the automation turns it on again.") }
    static var openShortcuts: String { s("daily.openShortcuts", "Open Shortcuts") }
    /// What the player makes, as Shortcuts shows it once made.
    static var dailyWhatYouMake: String { s("daily.result", "What you make") }
    static func dailyEveryDay(_ time: String) -> String { f("daily.result.when", "Every day at %@", time) }
    static var dailyMade: String { s("daily.made", "I made the automation") }
    static var dailyMadeFooter: String { s("daily.made.footer", "Cartouche then checks after its first night that it renews it.") }
    /// The setup's last step, and the System page's row.
    static var dailyToMake: String { s("daily.state.toMake", "An automation in Shortcuts renews Cartouche every night, even while it stays closed. Without it, Cartouche renews itself only when you open it, and expires 7 days after its last renewal.") }
    static func dailyWaiting(_ date: String) -> String { f("daily.state.waiting", "Made on %@: Cartouche checks after its first night that it renews it.", date) }
    static func dailyNotRunning(_ date: String) -> String { f("daily.state.notRunning", "Made on %@, it has not run yet. Check in Shortcuts its time, and that it runs immediately.", date) }
    static var dailyRunning: String { s("daily.state.running", "It is renewing Cartouche now.") }
    static func dailyRenewed(_ date: String) -> String { f("daily.state.renewed", "It renewed Cartouche on %@.", date) }
    static func dailyFailedVPN(_ date: String) -> String { f("daily.state.vpn", "On %@, it ran without LocalDevVPN connected, and could not renew Cartouche. Add the Enable LocalDevVPN action just before Refresh All Apps.", date) }
    static func dailyInterrupted(_ date: String) -> String { f("daily.state.interrupted", "On %@, iOS stopped it before it had renewed Cartouche. It tries again the next night.", date) }
    static func dailyFailed(_ date: String, _ why: String) -> String { f("daily.state.failed", "On %@, it could not renew Cartouche: %@", date, why) }
    static func dailyStopped(_ date: String) -> String { f("daily.state.stopped", "It has not run since %@. Check in Shortcuts that it is still there, on, and runs immediately.", date) }
    static var dailyMake: String { s("daily.action.make", "Make the automation") }
    static var dailyFix: String { s("daily.action.fix", "Fix the automation") }
    static var dailySee: String { s("daily.action.see", "See the steps") }
    /// The System page's row, beside Renew every night.
    static var dailyStatusToMake: String { s("daily.status.toMake", "To make") }
    static var dailyStatusWaiting: String { s("daily.status.waiting", "Made") }
    static var dailyStatusOn: String { s("daily.status.on", "On") }
    static var dailyStatusFailed: String { s("daily.status.failed", "Failed") }
    static var dailyStatusStopped: String { s("daily.status.stopped", "Not running") }

    // MARK: Installing, starting and uninstalling a game

    static func installTitle(_ name: String) -> String { f("work.install.title", "Installing %@", name) }
    static var installChecking: String { s("work.install.checking", "Checking the IPA and the room on this iPhone.") }
    static var installUnpacking: String { s("work.install.unpacking", "Unpacking the IPA.") }
    static var installSigning: String { s("work.signing", "Signing it for this iPhone") }
    static var installFailed: String { s("work.install.failed", "The game was not installed") }
    static var installDamagedIPA: String {
        s("work.install.damaged", "This IPA is damaged: it ends early, or one of its files changed since it was made, as when a copy stops before the end or goes wrong. Copy it again from where it came from, then install it again.")
    }
    static var installSignWarning: String { s("work.install.signWarning", "Installed, but not signed") }
    static var installDone: String { s("work.install.done", "Installed") }
    static var installGPUTitle: String { s("work.install.gpu", "This iPhone cannot run nxnative’s games") }
    static var installAnyway: String { s("work.install.gpu.anyway", "Install anyway") }
    /// Beside reasonGPU on an iPhone whose GPU reads no BC: the Mac's
    /// builds of nxnative-nobc, a separate fork (cartouche_builder/build_for.py).
    static var installGPUBuilder: String { s("work.install.gpu.builder", "Cartouche on your Mac builds them for this iPhone from nxnative-nobc, a separate fork of nxnative that converts those textures, once the two are paired.") }
    /// Where an app that is not an nxnative game is once installed: on the
    /// System page, as the console shows games only (docs/decisions/154.md).
    /// Up to 0.15.1, "in Apps", LiveContainer's tab, which Cartouche hides.
    static func installNotAGame(_ name: String) -> String {
        f("work.install.notAGame.system", "%@ is not an nxnative game: you will find it in System, under Other installed apps.", name)
    }
    static func installNoSpace(needed: String, free: String) -> String {
        f("work.install.noSpace", "Installing this game takes about %1$@ of free space, and this iPhone has %2$@. Free some space, then import it again.", needed, free)
    }
    static func startTitle(_ name: String) -> String { f("work.start.title", "Starting %@", name) }
    static var startSoon: String { s("work.start.soon", "The game opens in a moment.") }
    static var startSettings: String { s("work.start.settings", "The game opens on its settings: its Play button starts it and keeps your choices.") }
    static var startFailed: String { s("work.start.failed", "The game did not start") }
    /// The same, for an app that is not an nxnative game.
    static var openSoon: String { s("work.open.soon", "The app opens in a moment.") }
    static var openFailed: String { s("work.open.failed", "The app did not open") }
    static var startCertificateRefused: String { s("work.start.certificateRefused", "iOS no longer accepts the certificate the game was signed with. Cartouche signs in again with your Apple ID to take the new one: try again in a moment.") }

    // A game LiveContainer did not sign, or whose process stopped as it
    // started (CartoucheGameSigning): why, in the player's words, then what
    // to do, as they install it or start it.
    static func notSignedTitle(_ name: String) -> String { f("work.notSigned.title", "%@ is not signed", name) }
    static var notSignedFiles: String { s("work.notSigned.files", "Cartouche could not sign every file of the game for this iPhone.") }
    static var notSignedCertificateRefused: String {
        s("work.notSigned.certificateRefused", "iOS refuses the certificate Cartouche signs games with: Cartouche takes the new one with your Apple ID.")
    }
    static var notSignedNoCertificate: String {
        s("work.notSigned.noCertificate", "Cartouche has no certificate to sign games with yet: finish its setup on the System page.")
    }
    static var notSignedEncrypted: String {
        s("work.notSigned.encrypted", "This app is encrypted, as the App Store delivers it: Cartouche only runs apps that are not, such as the games nxnative builds.")
    }
    static var notSignedDamaged: String { s("work.notSigned.damaged", "The game’s files are damaged: install it again from its IPA.") }
    static var notSignedAtInstall: String { s("work.notSigned.atInstall", "Cartouche signs it again as you start it.") }
    static var notSignedAtStart: String { s("work.notSigned.atStart", "Sign it again; if it still fails, install it again from its IPA.") }
    static var signAgainAndPlay: String { s("action.signAgain", "Sign again and play") }
    static var gameSignatureRefused: String {
        s("running.stopped.signature", "iOS refused the game’s signature as it started. Sign it again; if it still fails, install it again from its IPA.")
    }
    static var gameStoppedOnError: String {
        s("running.stopped.error", "The game stopped on an error, which the report gives. If it happens again, install the game again from its IPA.")
    }
    static func uninstallTitle(_ name: String) -> String { f("work.uninstall.title", "Uninstalling %@", name) }
    static var uninstallStep: String { s("work.uninstall.step", "Removing it from this iPhone") }
    static var uninstallFailed: String { s("work.uninstall.failed", "The game was not uninstalled") }
    static func installFromStorageStep(_ server: String) -> String { f("work.install.stored", "Unpacking it from %@ as it arrives.", server) }
    static func installFromStorageNoSpace(needed: String, free: String) -> String {
        f("work.install.stored.noSpace", "Installing this game takes about %1$@ of free space, and this iPhone has %2$@. Free some space, then install it again.", needed, free)
    }
    static func installFromStorageRetry(_ server: String) -> String { f("work.install.stored.retry", "The connection to %@ dropped. Cartouche connects again and goes on from where it stopped.", server) }
    static func installFromStorageLost(_ server: String, _ reason: String) -> String {
        f("work.install.stored.lost", "The connection to %1$@ dropped and did not come back within three minutes. Install the game again once the network is back. (%2$@)", server, reason)
    }
    static var installGameFiles: String { s("work.install.gameFiles", "Copying its game files, romfs.img.") }
    static func installGameFilesMissing(_ name: String) -> String {
        f("work.install.gameFiles.missing", "%@ was built without its game files, and its romfs.img is not beside its IPA in your games folder. Put it there, as nxnative wrote it, then install the game again.", name)
    }
    static func installGameFilesMismatch(_ name: String) -> String {
        f("work.install.gameFiles.mismatch", "The romfs.img beside %@ is not the one it was built with. Put the one nxnative wrote with this IPA beside it, then install the game again.", name)
    }
    static func installGameFilesApart(_ name: String) -> String {
        f("work.install.gameFiles.apart", "%@ was built without its game files. Put this IPA and its romfs.img together in your games folder, then install the game from there.", name)
    }
    static func exportTitle(_ name: String) -> String { f("work.export.title", "Copying %@", name) }
    static func exportStep(_ server: String) -> String { f("work.export.step", "Copying it to %@.", server) }
    static var exportFailed: String { s("work.export.failed", "The game was not copied") }
    static func exportNoSpace(needed: String, server: String, free: String) -> String {
        f("work.export.noSpace", "The copy takes about %1$@, and %2$@ has %3$@ free. Free some space there, then copy the game again.", needed, server, free)
    }
    static var exportUnreadable: String { s("work.export.unreadable", "Cartouche could not read the installed game.") }
    static var savesFinishing: String { s("work.start.saves", "Cartouche first finishes syncing your saves.") }
    static func savesSyncing(_ server: String) -> String { f("work.saves.syncing", "Syncing your saves with %@", server) }

    // MARK: A game's transfer, outside Cartouche

    static var workKeepOpen: String { s("work.keepOpen", "Keep Cartouche open: a large game takes several minutes.") }
    static var workCanLeave: String { s("work.canLeave", "You can leave Cartouche: the Lock Screen and the Dynamic Island then show how far it has gone.") }
    static func outsideFrom(_ server: String) -> String { f("work.outside.from", "From %@", server) }
    static func outsideTo(_ server: String) -> String { f("work.outside.to", "To %@", server) }
    static func outsideFromPercent(_ percent: String, _ server: String) -> String { f("work.outside.fromPercent", "%1$@ · from %2$@", percent, server) }
    static func outsideToPercent(_ percent: String, _ server: String) -> String { f("work.outside.toPercent", "%1$@ · to %2$@", percent, server) }
    static func outsideUnpacking(_ percent: String) -> String { f("work.outside.unpacking", "%@ · unpacking", percent) }
    static func outsideReconnecting(_ server: String) -> String { f("work.outside.reconnecting", "Connecting to %@ again", server) }
    static var installStopped: String { s("work.install.stopped", "The install stopped") }

    // MARK: How a game comes, and how fast

    /// "By cable", "By cable, through the Mac", "On the Wi-Fi, the Mac on
    /// 2.4\u{00A0}GHz".
    static func transferWay(_ way: CartoucheTransferWay) -> String {
        switch way {
        case .cable:
            return s("work.transfer.cable", "By cable")
        case .relayed:
            return s("work.transfer.relayed", "By cable, through the Mac")
        case .tailnet:
            return s("work.transfer.tailnet", "Through Tailscale")
        case .network(let mac):
            if mac?.medium == CartoucheMacNetwork.ethernet {
                return s("work.transfer.macEthernet", "On the local network, the Mac on Ethernet")
            }
            if mac?.medium == CartoucheMacNetwork.wifi, let band = mac?.band {
                return f("work.transfer.macWiFi", "On the Wi-Fi, the Mac on %@\u{00A0}GHz", decimal(band))
            }
            return s("work.transfer.network", "On the local network")
        }
    }

    /// "3.1 MB/s", "31 MB/s": one decimal below 10.
    static func transferSpeed(_ bytes: Double) -> String {
        let (value, decimals) = CartoucheTransferMeter.megabytes(bytes)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let number = formatter.string(from: NSNumber(value: value)) ?? String(value)
        return f("unit.mbps", "%@\u{00A0}MB/s", number)
    }

    /// "By cable · 31 MB/s".
    static func transferLine(_ way: String, _ speed: String) -> String { f("work.transfer.line", "%1$@ · %2$@", way, speed) }

    static func transferAdvice(_ advice: CartoucheTransferAdvice) -> String {
        switch advice {
        case .macOnSlowBand:
            return s("work.transfer.advice.macBand", "The Mac is on its 2.4\u{00A0}GHz Wi-Fi, the slowest: plug this iPhone into the Mac with a cable, or put the Mac on the 5\u{00A0}GHz Wi-Fi, and the game comes much faster.")
        case .slowToMac:
            return s("work.transfer.advice.mac", "It is slow: plug this iPhone into the Mac with a cable, or put both on a 5\u{00A0}GHz Wi-Fi, and the game comes much faster.")
        case .slowTailnet:
            return s("work.transfer.advice.tailnet", "It is slow: through Tailscale, the game goes over the internet. At home, on the same Wi-Fi or by cable, it comes much faster.")
        case .slowNetwork:
            return s("work.transfer.advice.network", "It is slow: on a 5\u{00A0}GHz Wi-Fi, the game comes much faster.")
        }
    }

    /// "2.4" as the reader writes it: "2,4" in French.
    private static func decimal(_ number: String) -> String {
        guard let value = Double(number) else { return number }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? number
    }
    static var exportStopped: String { s("work.export.stopped", "The copy stopped") }
    static var workStoppedOutside: String {
        s("work.stopped.message", "It was stopped outside Cartouche: from the Lock Screen or the Dynamic Island, or by iOS. Start it again whenever you like.")
    }

    static var gameSettings: String { s("action.gameSettings", "Game settings") }
    static var uninstall: String { s("action.uninstall", "Uninstall") }
    static var cancel: String { s("action.cancel", "Cancel") }
    static func uninstallQuestion(_ name: String) -> String { f("uninstall.question", "Uninstall %@?", name) }
    static var uninstallMessage: String { s("uninstall.message", "Your saves can stay on this iPhone: the game finds them again the next time you import it.") }
    static var uninstallKeepSaves: String { s("uninstall.keep", "Uninstall, keep my saves") }
    static var uninstallEraseSaves: String { s("uninstall.erase", "Uninstall and erase my saves") }
    static func uninstallCopyFirst(_ server: String) -> String { f("uninstall.copyFirst", "Copy to %@, then uninstall", server) }
    static func uninstallMessageStored(_ server: String) -> String { f("uninstall.message.stored", "The game stays in %@, ready to install again. Your saves can stay on this iPhone: the game finds them again.", server) }
    static func installFrom(_ server: String) -> String { f("action.installFrom", "Install from %@", server) }
    static func updateFrom(_ server: String) -> String { f("action.updateFrom", "Update from %@", server) }
    static var updateGame: String { s("action.updateGame", "Update") }
    static var importOtherCopy: String { s("action.importOther", "Import another copy") }
    static func exportTo(_ server: String) -> String { f("action.exportTo", "Copy to %@", server) }
    static func storedIn(_ server: String, _ file: String) -> String { f("sheet.storedIn", "A copy is in %1$@: %2$@", server, file) }
    /// The other places that hold a copy of the game, by their names.
    static func storedAlsoIn(_ places: [String]) -> String {
        f("sheet.storedAlsoIn", "Also in %@.", places.formatted(.list(type: .and).locale(locale)))
    }
    static func storedAlsoInOffline(_ place: String) -> String { f("sheet.storedAlsoIn.offline", "%@ (offline)", place) }
    static func buildHere(_ build: String) -> String { f("sheet.build.here", "On this iPhone: %@", build) }
    static func buildNewer(_ server: String, _ build: String) -> String { f("sheet.build.newer", "Newer, in %1$@: %2$@", server, build) }
    static func buildVersion(_ version: String) -> String { f("build.version", "version %@", version) }
    static func buildBuilt(_ date: String) -> String { f("build.built", "built %@", date) }
    static func buildInstalled(_ date: String) -> String { f("build.installed", "installed %@", date) }
    static func buildCommit(_ commit: String) -> String { f("build.commit", "nxnative %@", commit) }

    /// A game's build in a few words: its version, when it was built, or
    /// else installed, and, with SHOWSCOMMIT, its nxnative commit.
    static func build(_ build: CartoucheGameBuild, installedOn: Date? = nil, showsCommit: Bool = true) -> String {
        var parts: [String] = []
        if let version = build.version { parts.append(buildVersion(version)) }
        if let installedOn {
            parts.append(buildInstalled(dateAndTime(installedOn)))
        } else if let builtAt = build.builtAt {
            parts.append(buildBuilt(dateAndTime(builtAt)))
        }
        if showsCommit, let commit = build.shortCommit { parts.append(buildCommit(build.isDirty ? commit + "+dirty" : commit)) }
        return parts.joined(separator: ", ")
    }

    /// A day and its time, in the reader's language: "Nov 14, 2026 at
    /// 6:22 PM", "14 nov. 2026 à 18:22".
    static func dateAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    // MARK: A game behind the console

    static var resume: String { s("action.resume", "Resume") }
    static var quit: String { s("action.quit", "Quit") }
    static var statusPausedShort: String { s("status.paused.short", "Paused") }
    static var pausedDetail: String { s("running.paused", "Paused behind Cartouche, where you left it.") }
    static var backToCartouche: String { s("running.back", "Back to Cartouche") }
    static var homeButtonHint: String { s("running.homeHint", "The controller’s Home button brings you back to Cartouche.") }
    static var homeFadesHint: String { s("running.homeFades", "The Home button hides after a few seconds: touch just below to bring it back.") }
    static var turnIPadSideways: String { s("running.turnIPadSideways", "Turn your iPad sideways to play.") }
    static func quitQuestion(_ name: String) -> String { f("running.quit.question", "Quit %@?", name) }
    static var quitGame: String { s("running.quit.confirm", "Quit the game") }
    static var quitMessage: String { s("running.quit.message", "Progress since the game last saved will be lost.") }
    static func quitAndStart(_ name: String) -> String { f("running.switch.action", "Quit and start %@", name) }
    static func quitAndStartMessage(_ name: String) -> String {
        f("running.switch.message", "One game at a time: progress since the game last saved will be lost, then %@ starts.", name)
    }
    static func quitFirst(_ name: String) -> String { f("running.quitFirst", "%@ is running behind Cartouche: quit it first.", name) }
    static func gameStoppedTitle(_ name: String) -> String { f("running.stopped.title", "%@ has closed", name) }
    static var gameStopped: String { s("running.stopped", "The game closed on its own. Your progress is kept up to its last save.") }
    static var gameStoppedPaused: String { s("running.stopped.paused", "iOS closed the game while it was paused. Your progress is kept up to its last save.") }
    static func gameStoppedMemory(_ limit: String) -> String {
        f("running.stopped.memory", "iOS closed the game near its limit of %@ behind Cartouche. From now on, it starts in Cartouche’s place, with all of Cartouche’s memory.", limit)
    }
    static func gameStoppedMemoryBehind(_ limit: String) -> String {
        f("running.stopped.memory.behind", "iOS closed the game near its limit of %@ behind Cartouche: in Cartouche’s place, it would have no more memory. Your progress is kept up to its last save.", limit)
    }
    static var startsInPlaceNote: String { s("sheet.inPlace", "Behind Cartouche, this game would run short of memory: it starts in Cartouche’s place, and the console closes while it runs.") }
    static func startsInPlaceWithoutIML(_ limit: String) -> String {
        f("sheet.inPlace.iml", "Behind Cartouche, games have only %@ here, without Increased Memory Limit: this game starts in Cartouche’s place, and the console closes while it runs.", limit)
    }
    static var tryBehindAgain: String { s("sheet.inPlace.retry", "Try behind Cartouche again") }
    static var playingTitle: String { s("system.playing", "While a game runs") }
    static var keepConsoleOpen: String { s("system.playing.keep", "Keep Cartouche open behind the game") }
    static var behindLimit: String { s("system.playing.limit", "Memory for a game behind Cartouche") }
    static var behindLimitUnknown: String { s("system.playing.limit.unknown", "Measured at the next game") }
    static var behindWithoutIML: String { s("system.playing.noIML", "Behind Cartouche, games run without Increased Memory Limit here: they start in Cartouche’s place, with all of its memory, unless their sheet shows they need less.") }
    static var playingFooter: String { s("system.playing.footer", "The Home button over the game, or the controller’s, brings back the console and pauses the game. A game that needs more memory than it has here starts in Cartouche’s place, when Cartouche has more.") }
    static var keepOtherAudio: String { s("system.playing.otherAudio", "Keep other apps’ sound") }
    static var otherAudioFooter: String { s("system.playing.otherAudio.footer", "On, the music or podcast you play in another app goes on under the game’s sound, from the game’s next start. Off, the game stops it as it starts.") }
    static var memoryFooterBehind: String { s("system.memory.footer.behind", "Games that start in Cartouche’s place share this limit; behind Cartouche, a game has its own, below. With Increased Memory Limit, an iPhone with 12 GB allows Cartouche about 8 GiB.") }
    static func updateWhilePlaying(_ name: String) -> String { f("system.updates.playing", "Quit %@ first: Cartouche closes to install its update.", name) }

    // MARK: A TV (CartoucheTV.swift)

    static var tvStarting: String { s("tv.starting", "Starting…") }
    static var tvOnIPhone: String { s("tv.onIPhone", "This game shows on the iPhone.") }
    static var tvPaused: String { s("tv.paused", "Paused: the console is on the iPhone.") }
    static var tvMoving: String { s("tv.moving", "Moving to the TV…") }
    static var tvMirrored: String {
        s("tv.mirrored", "The TV shows a copy of the iPhone’s screen, so the game stays hidden from it. To play on the iPhone, unplug the TV or stop Screen Mirroring.")
    }
    static var tvCaptured: String {
        s("tv.captured", "The iPhone’s screen is being recorded or shown on another screen, so the game stays hidden.")
    }
    static var tvShowAnyway: String { s("tv.showAnyway", "Show the game anyway") }

    // MARK: Play time and size

    static var statsTitle: String { s("stats.title", "Play time and size") }
    static var statsPlayTime: String { s("stats.playTime", "Play time") }
    static var statsNotCounted: String { s("stats.notCounted", "Not counted yet") }
    static var statsCountedNext: String { s("stats.countedNext", "Counted from your next game") }
    static func statsPlayTimeDetail(_ sessions: String, _ lastPlayed: String) -> String {
        f("stats.playTime.detail", "%1$@, last played %2$@", sessions, lastPlayed)
    }
    static func statsSessions(_ count: Int) -> String {
        count == 1 ? s("stats.session", "1 session") : f("stats.sessions", "%lld sessions", count)
    }
    static func statsSizeDetail(_ game: String, _ data: String) -> String { f("stats.size.detail", "Game %1$@, data %2$@", game, data) }
    static func statsStored(_ server: String) -> String { f("stats.stored", "In %@", server) }

    /// When a game was last played: "yesterday", "2 hours ago".
    static func lastPlayed(_ date: Date) -> String {
        min(date, Date()).formatted(.relative(presentation: .named).locale(locale))
    }

    /// A play time: "12 h 30 min", "45 min", "< 1 min".
    static func duration(seconds: Double) -> String {
        let minutes = Int(min(max(seconds, 0), 1e12) / 60)
        if minutes < 1 { return s("duration.underMinute", "<\u{00A0}1\u{00A0}min") }
        if minutes < 60 { return f("duration.minutes", "%lld\u{00A0}min", minutes) }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return f("duration.hours", "%lld\u{00A0}h", hours) }
        return f("duration.hoursMinutes", "%1$lld\u{00A0}h %2$lld\u{00A0}min", hours, rest)
    }

    // MARK: The player's storage

    static var storageTitle: String { s("storage.title", "Storage") }
    static var storageIntro: String { s("storage.intro", "Your games and saves on your own storage: your Mac with Cartouche, a shared folder of your Mac, PC or NAS, an S3 bucket, an FTP or SFTP server, your Google Drive, or a folder in Files. Its games show in your library.") }
    static var storageNotSet: String { s("storage.notSet", "Not set up") }
    static var storageGamesFolder: String { s("storage.games", "Games folder") }
    static var storageSavesFolder: String { s("storage.saves", "Saves folder") }
    static var storageGamesFound: String { s("storage.games.found", "Games found") }
    /// The games of the games folder built without their game files whose
    /// romfs.img is not there, by their names.
    static func storageGameFilesMissing(_ names: [String]) -> String {
        let list = names.formatted(.list(type: .and).locale(locale))
        if names.count == 1 {
            return f("storage.gameFiles.missing.one", "%@ was built without its game files: put its romfs.img beside its IPA, and Cartouche installs the two together.", list)
        }
        return f("storage.gameFiles.missing", "%@ were built without their game files: put each one’s romfs.img beside its IPA, and Cartouche installs the two together.", list)
    }
    /// The images of game files no IPA of the games folder needs, by their
    /// paths in it.
    static func storageGameFilesLoose(_ names: [String]) -> String {
        let list = names.formatted(.list(type: .and).locale(locale))
        if names.count == 1 {
            return f("storage.gameFiles.loose.one", "%@: a game’s files, but no IPA here was built to go with them. Put beside them the IPA nxnative built with them, or build the game with Cartouche on your Mac.", list)
        }
        return f("storage.gameFiles.loose", "%@: games’ files, but no IPA here was built to go with them. Put beside each the IPA nxnative built with it, or build the games with Cartouche on your Mac.", list)
    }
    static var storageReadAgain: String { s("storage.readAgain", "Read the folder again") }
    static var storageChangeFolder: String { s("storage.changeFolder", "Change folder") }
    static var storageStopUsing: String { s("storage.stopUsing", "Stop using this folder") }
    static var storageAddFirst: String { s("storage.addFirst", "First add your Mac, a shared folder, an S3 bucket, an FTP or SFTP server, your Google Drive, or a folder in Files, below.") }
    static var storageChooseFolder: String { s("storage.chooseFolder", "Choose a folder") }
    static var storageGamesFooter: String { s("storage.games.footer", "Your library shows the IPAs of this folder, ready to install. Copy a game here before you uninstall it.") }
    /// Several games folders, one after the other (CartoucheGameCopies).
    static var storageGamesFolders: String { s("storage.games.several", "Games folders") }
    static var storageOtherGamesFolder: String { s("storage.games.other", "Other folder") }
    static var storageReadAllAgain: String { s("storage.readAgain.all", "Read the folders again") }
    static var storageAddGamesFolder: String { s("storage.games.add", "Add another games folder") }
    static var storageStopReading: String { s("storage.stopReading", "Stop reading this folder") }
    static var storageGamesFoldersFooter: String { s("storage.games.several.footer", "Your library shows the IPAs of these folders, ready to install: a game in more than one shows once, and installs from a folder that answers. Copy a game to the first one before you uninstall it.") }
    /// Under a games folder whose server does not answer, among several.
    static var storageGamesElsewhere: String { s("storage.games.elsewhere", "Its games that another folder holds too install from that folder meanwhile.") }
    static var storageServers: String { s("storage.servers", "Places") }
    static var storageServersFooter: String { s("storage.servers.footer", "Only storage of your own, with your own account: Cartouche keeps the password, the secret key or the Google sign-in in this iPhone’s keychain. The Mac you pair keeps the same connections, passwords included, over the bridge’s encryption.") }
    static var storageAddSMB: String { s("storage.addSMB", "Add a shared folder (SMB)") }
    static var storageAddFolder: String { s("storage.addFolder", "Add a folder in Files") }
    static var storageAddS3: String { s("storage.addS3", "Add S3 storage") }
    static var storageS3Server: String { s("storage.s3.server", "Bucket") }
    static var storageS3Address: String { s("storage.s3.address", "Address (e.g. s3.eu-west-3.amazonaws.com)") }
    static var storageS3Bucket: String { s("storage.s3.bucket", "Bucket name") }
    static var storageS3Region: String { s("storage.s3.region", "Region (optional)") }
    static var storageS3ServerFooter: String { s("storage.s3.server.footer", "Amazon S3, or a server of your own such as MinIO on your NAS. Cartouche uses HTTPS, unless you type http:// before the address of a server on your network.") }
    static var storageS3Keys: String { s("storage.s3.keys", "Keys") }
    static var storageS3AccessKey: String { s("storage.s3.accessKey", "Access key ID") }
    static var storageS3SecretKey: String { s("storage.s3.secretKey", "Secret access key") }
    static var storageS3SecretKeyKept: String { s("storage.s3.secretKey.kept", "Secret access key (leave empty to keep it)") }
    static var storageS3KeysFooter: String { s("storage.s3.keys.footer", "Keys of your own account, allowed to read and write this bucket. Cartouche signs each request with them, keeps the secret key in this iPhone’s keychain, and never makes the bucket public.") }
    static var storageS3Checking: String { s("storage.s3.checking", "Signing in to the bucket…") }
    static var storageS3BadAddress: String { s("storage.s3.badAddress", "Cartouche cannot use this address: type the server’s name or IP address, with its port if it needs one, and nothing after it.") }
    static var storageS3BadBucket: String { s("storage.s3.badBucket", "Type the bucket’s name, without “/”.") }
    static var storageS3KeysNeeded: String { s("storage.s3.keysNeeded", "Cartouche needs the access key ID and the secret access key: it reaches only private buckets, with your keys.") }
    static var storageS3BadAnswer: String { s("storage.s3.badAnswer", "The S3 server gave an answer Cartouche does not understand.") }
    static var storageAddFTP: String { s("storage.addFTP", "Add an FTP server") }
    static var storageFTPChecking: String { s("storage.ftp.checking", "Signing in to the server…") }
    static var storageFTPFooter: String { s("storage.ftp.footer", "The account of your server, such as your NAS’s. FTP sends the password unencrypted: use it on your own network.") }
    static var storageFTPBadName: String { s("storage.ftp.badName", "Cartouche cannot use this name on an FTP server: it holds a line break.") }
    static var storageFTPAccountNeeded: String { s("storage.ftp.accountNeeded", "Cartouche needs the server’s address and your user name: it signs in only with your own account.") }
    static var storageFTPClosed: String { s("storage.ftp.closed", "The FTP server closed the connection.") }
    static var storageFTPTooLong: String { s("storage.ftp.tooLong", "This folder’s listing is larger than Cartouche expects.") }
    static var storageAddSFTP: String { s("storage.addSFTP", "Add an SFTP server") }
    static var storageSFTPFooter: String { s("storage.sftp.footer", "The account of your server, such as your NAS’s or your Mac’s (Remote Login). Cartouche keeps the server’s key when you save it, and refuses any other key afterwards.") }
    static var storageSFTPKey: String { s("storage.sftp.key", "Server key") }
    static var storageSFTPNoKey: String { s("storage.sftp.noKey", "The server did not show its key.") }
    static func storageSFTPKeyChanged(_ host: String) -> String { f("storage.sftp.keyChanged", "%@ shows another key than the one Cartouche kept, so Cartouche did not send your password. If you reinstalled the server, remove it here and add it again.", host) }
    static var storageSFTPRefused: String { s("storage.sftp.refused", "the server refused the user name or the password, or asks for a sign-in Cartouche does not offer.") }
    static var storageSFTPBadAnswer: String { s("storage.sftp.badAnswer", "The SFTP server gave an answer Cartouche does not understand.") }
    static var storageSFTPClosed: String { s("storage.sftp.closed", "The SFTP server closed the connection.") }
    static var storageSFTPNoSubsystem: String { s("storage.sftp.noSubsystem", "This server does not offer SFTP to this account.") }
    static func storageSFTPFailure(_ code: Int) -> String { f("storage.sftp.failure", "The SFTP server refused (code %lld).", code) }
    static func storagePort(_ port: Int) -> String { f("storage.port", "Port (%lld if empty)", port) }
    static var storageRemove: String { s("storage.remove", "Remove") }
    static var storageGuest: String { s("storage.guest", "guest") }
    static var storageFilesFolder: String { s("storage.filesFolder", "Folder in Files") }
    static var storageNearby: String { s("storage.nearby", "On this network") }
    static var storageAccount: String { s("storage.account", "Account") }
    static var storageHost: String { s("storage.host", "Address (name or IP)") }
    static var storageUser: String { s("storage.user", "User name") }
    static var storagePassword: String { s("storage.password", "Password") }
    static var storagePasswordKept: String { s("storage.password.kept", "Password (leave empty to keep it)") }
    static var storageAccountFooter: String { s("storage.account.footer", "The account of your Mac, PC or NAS. Leave the user name empty to sign in as a guest.") }
    static var storageConnect: String { s("storage.connect", "Sign in and list the shared folders") }
    static var storageNoShares: String { s("storage.noShares", "This account sees no shared folder there.") }
    /// Why an SMB server did not sign the player in (CartoucheSMBRefusal),
    /// after storage.signInFailed's colon.
    static var storageSMBRefused: String { s("storage.smb.refused", "the server refused the user name or the password.") }
    static var storageSMBNoGuests: String { s("storage.smb.noGuests", "the server does not let guests in. Type the user name and password of your account on it.") }
    static var storageSMBLocked: String { s("storage.smb.locked", "the server locked this account after too many wrong passwords. Try again later, or unlock it on the server.") }
    static var storageSMBHeldBack: String { s("storage.smb.heldBack", "the server does not let this account sign in as it is. On the server, turn the account on, or give it a new password.") }
    static var storageShare: String { s("storage.share", "Shared folder") }
    static var storageShareFooter: String { s("storage.share.footer", "On a Mac: System Settings › General › Sharing › File Sharing. On a PC: the folder’s Properties › Sharing.") }
    static var storageNameTitle: String { s("storage.name.title", "Name in Cartouche") }
    static var storageName: String { s("storage.name", "Name") }
    static var storageSave: String { s("storage.save", "Save") }
    static var storageUseThisFolder: String { s("storage.useThisFolder", "Use this folder") }
    static var storageNoFolders: String { s("storage.noFolders", "No folder here.") }
    static var storageNewFolder: String { s("storage.newFolder", "New folder") }
    static var storageCreate: String { s("storage.create", "Create") }
    static var storageFolderGone: String { s("storage.folderGone", "Cartouche can no longer open this folder. Remove it, then add it again.") }
    static var storageNotAnApp: String { s("storage.notAnApp", "This file is not an app’s IPA.") }
    static var storageReadOnlyGames: String { s("storage.readOnly.games", "Read-only for your account: Cartouche installs the games in this folder, but cannot copy any there.") }
    static var storageReadOnlySaves: String { s("storage.readOnly.saves", "Read-only for your account: Cartouche cannot copy your saves here. Choose a folder you can write to.") }
    static func storageReadOnlyServer(_ name: String) -> String { f("storage.readOnly.server", "%@ (read-only)", name) }
    static func exportReadOnly(_ server: String) -> String { f("work.export.readOnly", "Your account on %@ can only read the games folder: Cartouche cannot copy the game there.", server) }
    static func storageSavesFooter(_ kept: Int) -> String { f("storage.saves.footer", "Cartouche keeps your games’ saves in step with this folder, a folder per game: they come when a game is installed and before it starts, as after another iPhone played it or Cartouche was installed again, and go a few seconds after each save of the game, after the game at the latest. The %lld newest copies are kept, one for each game played.", kept) }
    static func storageSignInFailed(_ host: String, _ reason: String) -> String { f("storage.signInFailed", "Cartouche could not sign in to %1$@: %2$@", host, reason) }
    static func storageTooLarge(_ name: String) -> String { f("storage.tooLarge", "%@ is larger than Cartouche expects.", name) }
    static var storageConnectFailed: String { s("storage.failed.connect", "Cartouche could not connect") }
    static var storageBrowseFailed: String { s("storage.failed.browse", "The folder did not open") }
    static var storageNewFolderFailed: String { s("storage.failed.newFolder", "The folder was not created") }
    static var storageGamesFailed: String { s("storage.failed.games", "The games folder was not read") }
    static func storageOffline(_ name: String) -> String { f("storage.offline", "%@ does not answer on this network. Cartouche tries again as soon as the iPhone is back on its network or on your VPN.", name) }
    static func storageOfflineTitle(_ name: String) -> String { f("storage.offline.title", "%@ is offline", name) }
    /// In a server's form, which Cartouche does not try again by itself.
    static func storageOfflineCheck(_ name: String) -> String { f("storage.offline.check", "%@ does not answer on this network: check its address, and that the iPhone is on its network or on your VPN.", name) }
    /// A few words, beside the server's name.
    static func storageOfflineShort(_ name: String) -> String { f("storage.offline.short", "%@ offline", name) }
    static func storageOfflineTailscaleOff(_ name: String) -> String { f("storage.offline.tailscaleOff", "%@ answers only through Tailscale, which is off on this iPhone: turn it on in the Tailscale app, and Cartouche tries again at once.", name) }
    static func storageOfflineTailscaleOffShort(_ name: String) -> String { f("storage.offline.tailscaleOff.short", "%@: Tailscale off", name) }
    static var storageTailscaleTitle: String { s("storage.tailscale.title", "Away from home") }
    static var tailscaleTurnedOffShort: String { s("tailscale.turnedOff.short", "Tailscale off") }
    static var tailscaleTurnedOff: String { s("tailscale.turnedOff", "LocalDevVPN turned Tailscale off, as iOS keeps one VPN at a time: open Tailscale to turn it on again.") }
    static var storageTailscaleConnected: String { s("storage.tailscale.connected", "Connected") }
    static var storageTailscaleOff: String { s("storage.tailscale.off", "Off") }
    static var storageTailscaleAppStore: String { s("storage.tailscale.appStore", "Tailscale on the App Store") }
    static var storageTailscaleFooter: String { s("storage.tailscale.footer", "With Tailscale, installed apart on this iPhone and on your Mac or NAS, Cartouche reaches them wherever you are: your Mac by itself, a NAS by its name or its address in Tailscale. iOS keeps one VPN at a time: LocalDevVPN, which Cartouche connects to renew and update itself, turns Tailscale off until you turn it on again.") }
    static var storageTryAgain: String { s("storage.tryAgain", "Try again") }

    // MARK: A game's saves

    static var savesTitle: String { s("saves.title", "Saves") }
    static var savesLastSync: String { s("saves.lastSync", "Last sync") }
    static var savesNoCopy: String { s("saves.noCopy", "None yet") }
    static var savesPutBack: String { s("saves.putBack", "Put back a copy") }
    static var savesNoFolder: String { s("saves.noFolder", "Choose a saves folder in System › Storage: Cartouche will keep this game’s saves in step with it, and bring them back if Cartouche is installed again.") }
    static var savesPutBackFooter: String { s("saves.putBack.footer", "Putting back a copy replaces this game’s saves on this iPhone. Cartouche sends the current ones to your saves folder first, and the copy put back becomes the newest one there, which your other iPhones take too.") }
    static var savesPutBackQuestion: String { s("saves.putBack.question", "Put back this copy?") }
    static var savesPutBackMessage: String { s("saves.putBack.message", "It replaces the game’s saves on this iPhone. Cartouche sends them to your saves folder first, so you can come back to them.") }
    static var savesCopyUnreadable: String { s("saves.unreadable", "This copy cannot be read: it is incomplete, or holds more than a game’s saves.") }
    static var savesReadOnly: String { s("saves.readOnly", "Your saves folder is read-only for your account: choose another one in System › Storage.") }
    static func savesSyncNow(_ server: String) -> String { f("saves.syncNow", "Sync with %@ now", server) }
    static var savesRunning: String { s("saves.running", "While the game plays, its saves go a few seconds after each save. Quit it to sync now or put back a copy.") }
    static func savesFetched(_ date: String) -> String { f("saves.fetched", "The newest saves, of %@, came from your saves folder.", date) }
    static func savesFetchedOver(_ date: String, _ kept: String) -> String {
        f("saves.fetched.kept", "The newest saves, of %1$@, came from your saves folder. This iPhone’s are kept there as the copy of %2$@.", date, kept)
    }
    static func savesKeptHere(_ kept: String) -> String {
        f("saves.kept", "Newer saves are in your saves folder: they come when the game next starts. This iPhone’s are kept there as the copy of %@.", kept)
    }
    static func savesFooter(_ kept: Int) -> String { f("saves.footer", "Cartouche keeps these saves in step with your saves folder: the newest come when the game is installed and before it starts, and go there a few seconds after each save of the game, after the game at the latest. When both changed, the newest win and the others stay as a copy. The %lld newest copies are kept, one for each game played.", kept) }
    static func savesNewerGame(_ copy: String, _ game: String) -> String {
        f("saves.newerGame", "The newest copy of these saves comes from version %1$@ of the game, newer than the one installed here (%2$@): it comes once the game is updated. Until then, the saves played here go to your saves folder as a copy of their own.", copy, game)
    }
    static func savesPutBackNewer(_ copy: String, _ game: String) -> String {
        f("saves.putBack.newer", "This copy comes from version %1$@ of the game, newer than the one installed here (%2$@): update the game to put it back.", copy, game)
    }
    static func savesPutBackAction(_ date: String) -> String { f("saves.putBack.action", "Put back the copy of %@", date) }
    static func savesPutBackDone(_ date: String) -> String { f("saves.putBack.done", "The copy of %@ is back in place.", date) }
    static var savesCopyFailed: String { s("saves.failed.copy", "The saves were not synced") }
    static var savesListFailed: String { s("saves.failed.list", "The copies of the saves were not read") }
    static var savesPutBackFailed: String { s("saves.failed.putBack", "The copy was not put back") }
    /// The copies of a game's saves on this iPhone, which nxnative makes as
    /// each session starts, beside those of the saves folder.
    static var savesFolderCopies: String { s("saves.copies.folder", "In your saves folder") }
    static var savesHereHeader: String { s("saves.here.header", "On this iPhone") }
    static var savesHereStart: String { s("saves.here.start", "At the start of a game") }
    static var savesHereBeforePutBack: String { s("saves.here.beforePutBack", "Before a copy was put back") }
    static var savesHereFooter: String { s("saves.here.footer", "Each time the game starts, it keeps on this iPhone a copy of the saves it starts from, up to ten: if a mod or a game went wrong, put back the copy from its start. The saves a copy put back replaces are kept here too.") }
    static var savesHereMessage: String { s("saves.here.message", "It replaces the game’s saves on this iPhone. Cartouche keeps them here first, so you can come back to them.") }
    static var savesHereMessageFolder: String { s("saves.here.message.folder", "It replaces the game’s saves on this iPhone. Cartouche keeps them here and sends them to your saves folder first, so you can come back to them; the copy put back then goes there as the newest.") }
    static func savesWaiting(_ count: Int) -> String {
        count == 1 ? s("saves.waiting.one", "One game’s saves are waiting: Cartouche copies them as soon as the server answers.")
            : f("saves.waiting.many", "%lld games’ saves are waiting: Cartouche copies them as soon as the server answers.", count)
    }
    static var savesWaitingHere: String { s("saves.waiting.game", "These saves are waiting for the server: Cartouche copies them as soon as it answers.") }

    // MARK: A game's settings

    static var settingsIntro: String { s("settings.intro", "The settings Play starts this game with. Its in-game menu changes the same ones.") }
    static var settingsNone: String { s("settings.none", "This game has no settings to choose.") }
    static var settingsUnreachable: String { s("settings.unreachable", "Cartouche cannot open this game’s settings. Start it on nxnative’s screen to choose them.") }
    static var settingsReset: String { s("settings.reset", "Reset to tested defaults") }
    static var settingsResetFooter: String { s("settings.reset.footer", "Brings back all the settings this game was tested with, and the iPhone’s language.") }
    static var settingsNxnativeScreen: String { s("settings.nxnativeScreen", "Start on nxnative’s screen") }
    static var settingsNxnativeScreenFooter: String { s("settings.nxnativeScreen.footer", "Starts the game on nxnative’s own settings screen, in English, with these choices: its Play button starts the game.") }
    static var settingFixed: String { s("settings.fixed", "Set by an env.txt file") }
    static var settingAbout: String { s("settings.about", "About this setting") }
    static var cloudTitle: String { s("settings.cloud", "Cloud saves") }
    /// The cloud saves' category, a word on a button.
    static var settingsSaves: String { s("settings.category.saves", "Saves") }
    static var cloudOff: String { s("settings.cloud.off", "Off") }
    static var cloudChoose: String { s("settings.cloud.choose", "Choose a folder in iCloud Drive…") }
    static var cloudChange: String { s("settings.cloud.change", "Choose a different folder…") }
    static var cloudTurnOff: String { s("settings.cloud.turnOff", "Turn off cloud saves") }
    static var cloudFooter: String { s("settings.cloud.footer", "Choose a folder in iCloud Drive, and the same one in the Mac app’s Cloud saves. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups.") }
    static var cloudSaved: String { s("settings.cloud.saved", "Saved. The game uses this folder when you press Play.") }
    static var cloudStale: String { s("settings.cloud.stale", "The folder you chose before can no longer be read: the app was signed differently. Choose it again.") }
    static var cloudFailed: String { s("settings.cloud.failed", "That folder could not be remembered: try a different one.") }
    static var cloudFailedTitle: String { s("settings.cloud.failed.title", "The cloud saves folder was not kept") }

    /// A text of nxnative's settings list (a game's dm/launcher.json, from
    /// nxnative's settings.tsv) in the reader's language: a section, a
    /// setting's name or note, or an option. A text Cartouche does not know
    /// shows as nxnative wrote it.
    static func gameSettingText(_ text: String) -> String {
        switch text {
        case "Game": return s("setting.section.game", "Game")
        case "Controls": return s("setting.section.controls", "Controls")
        case "Performance": return s("setting.section.performance", "Performance")

        case "Frame rate": return s("setting.frameRate", "Frame rate")
        case "Dynamic resolution": return s("setting.dynamicResolution", "Dynamic resolution")
        case "Render scale": return s("setting.renderScale", "Render scale")
        case "Console mode": return s("setting.consoleMode", "Console mode")
        case "Upscaling": return s("setting.upscaling", "Upscaling")
        case "Game's upscaler": return s("setting.gameUpscaler", "Game’s upscaler")
        case "Game language": return s("setting.language", "Game language")
        case "Picture": return s("setting.picture", "Picture")
        case "Frame-rate counter": return s("setting.fpsCounter", "Frame-rate counter")
        case "Touch feedback": return s("setting.touchFeedback", "Touch feedback")
        case "Game rumble": return s("setting.rumble", "Game rumble")
        case "Rumble strength": return s("setting.rumbleStrength", "Rumble strength")
        case "Rumble cutoff": return s("setting.rumbleCutoff", "Rumble cutoff")
        case "Picture shape": return s("setting.pictureShape", "Picture shape")
        case "Frame buffering": return s("setting.frameBuffering", "Frame buffering")
        case "Metal 4 pipelines": return s("setting.metal4", "Metal 4 pipelines")
        case "Pipeline prebuild": return s("setting.prebuild", "Pipeline prebuild")
        case "Encode thread": return s("setting.encodeThread", "Encode thread")
        case "Hold frames when late": return s("setting.holdFrames", "Hold frames when late")
        case "Performance HUD": return s("setting.hud", "Performance HUD")
        case "Display mode": return s("setting.displayMode", "Display mode")
        case "Press a button to join": return s("setting.pressToJoin", "Press a button to join")
        case "Switch 2 controllers": return s("setting.switch2", "Switch 2 controllers")

        case "Docked": return modeName("docked")
        case "Handheld": return modeName("handheld")
        case "Standard": return s("setting.option.standard", "Standard")
        case "Game's own": return s("setting.option.gameOwn", "Game’s own")
        case "Fit": return s("setting.option.fit", "Fit")
        case "Fill": return s("setting.option.fill", "Fill")
        case "iPhone Duo screen (1.43:1)": return s("setting.option.duoScreen", "iPhone Duo screen (1.43:1)")
        case "Match screen": return s("setting.option.matchScreen", "Match screen")
        case "Window": return s("setting.option.window", "Window")
        case "Fullscreen": return s("setting.option.fullscreen", "Fullscreen")

        case "Adjusts resolution between 70% and 100% under load. Turn off to keep full resolution for the selected console mode.":
            let low = percent(0.7), high = percent(1)
            return f("setting.note.dynamicResolution", "Adjusts resolution between %1$@ and %2$@ under load. Turn off to keep full resolution for the selected console mode.", low, high)
        case "Lets the game lower its resolution under load. Turn off to keep full resolution for the selected console mode.":
            return s("setting.note.dynamicResolutionLoad", "Lets the game lower its resolution under load. Turn off to keep full resolution for the selected console mode.")
        case "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. macOS asks once for Bluetooth access.":
            return s("setting.note.switch2", "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. macOS asks once for Bluetooth access.")
        case "Uses more GPU time and can increase heat.":
            return s("setting.note.upscaling", "Uses more GPU time and can increase heat.")
        case "Fill crops the game's 16:9 picture to cover the screen. Health bars, subtitles or maps near the edges can be cut off. A full-screen picture without cropping needs a patch for each game.":
            return s("setting.note.picture", "Fill crops the game’s 16:9 picture to cover the screen. Health bars, subtitles or maps near the edges can be cut off. A full-screen picture without cropping needs a patch for each game.")
        case "Renders about a quarter more pixels: a little slower and warmer.":
            return s("setting.note.pictureShape", "Renders about a quarter more pixels: a little slower and warmer.")
        case "Up to one frame more display latency.":
            return s("setting.note.frameBuffering", "Up to one frame more display latency.")
        case "Keeps a pipeline archive; uses more memory.":
            return s("setting.note.metal4", "Keeps a pipeline archive; uses more memory.")
        case "The first start waits a few minutes for it, once.":
            return s("setting.note.prebuild", "The first start waits a few minutes for it, once.")
        case "This game's files do not list its languages, so some of these may not be in the game. It may then show another one.":
            return s("setting.note.languages", "This game’s files do not list its languages, so some of these may not be in the game. It may then show another one.")

        default:
            // "60 fps"
            if text.hasSuffix(" fps"), let rate = Int(text.dropLast(4)) {
                let frames = String(rate)
                return f("setting.option.fps", "%@ fps", frames)
            }
            return text
        }
    }

    /// One of the game's languages, by its code (nxnative's nacp.py), in the
    /// reader's language; nxnative's English name when iOS has none.
    static func languageName(_ code: String, english: String) -> String {
        guard let name = locale.localizedString(forIdentifier: code), !name.isEmpty else { return gameSettingText(english) }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// A language's name inside a sentence, in the reader's language
    /// ("French", "français"); nxnative's English name when iOS has none.
    static func languageNameInText(_ code: String, english: String) -> String {
        guard let name = locale.localizedString(forIdentifier: code), !name.isEmpty else { return gameSettingText(english) }
        return name
    }

    /// The game language's first option: the first of the iPhone's
    /// languages that the game has (CartoucheGameLanguage.swift).
    static var languageIPhone: String { s("setting.language.iPhone", "iPhone language") }

    static func languageIPhoneStarts(_ language: String) -> String {
        f("setting.language.iPhone.starts", "Starts in %@, the iPhone’s language.", language)
    }

    static func languageIPhoneMissing(_ language: String) -> String {
        f("setting.language.iPhone.missing", "None of the iPhone’s languages is in this game: it starts in %@.", language)
    }

    /// A share, as a percentage in the reader's language: "75%", "75\u{00A0}%".
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    // MARK: Game measurements

    static var telemetryTitle: String { s("telemetry.title", "Game measurements") }
    static var telemetryOn: String { s("telemetry.on", "On") }
    static var telemetryOff: String { s("telemetry.off", "Off") }
    static var telemetrySend: String { s("telemetry.send", "Send game measurements") }
    static var telemetryFooter: String { s("telemetry.footer", "After each game, Cartouche sends what nxnative measured while it ran, with Cartouche’s own events. They show which games run well on which iPhone, and what to fix.") }
    static var telemetryWhat: String { s("telemetry.what", "What is sent") }
    static var telemetryWhatGames: String { s("telemetry.what.games", "For each game session: frame rate, frame and GPU times, stutters and what caused them, shader preparation, memory, heat and power, sound, the screen’s sizes, how the game ended, and the game’s version and settings.") }
    static var telemetryWhatDevice: String { s("telemetry.what.device", "This iPhone’s model, iOS version, language and memory limit, Cartouche’s version and language, and a random number of this copy of Cartouche.") }
    static var telemetryWhatEvents: String { s("telemetry.what.events", "Each start of Cartouche, game installs, updates, renewals, resets, Apple ID sign-ins, signing certificates you import, how the Files picker of each import went, and errors, by their codes and the step they stopped at.") }
    static var telemetryWhatNever: String { s("telemetry.what.never", "Never your Apple ID, your iPhone’s name, your files, the addresses of your storage or the game’s log itself.") }
    static var telemetryLastSent: String { s("telemetry.lastSent", "Last sent") }
    static var telemetryNever: String { s("telemetry.never", "Never") }
    static var telemetrySentCount: String { s("telemetry.sentCount", "Reports sent") }
    static var telemetryWaiting: String { s("telemetry.waiting", "Waiting to be sent") }
    static var telemetryLastReport: String { s("telemetry.lastReport", "Last report") }
    static var telemetryNoServer: String { s("telemetry.noServer", "This build of Cartouche has no server to send to: its reports stay on this iPhone.") }
    static var telemetryErase: String { s("telemetry.erase", "Erase what this iPhone sent") }
    static var telemetryEraseConfirm: String { s("telemetry.erase.confirm", "Erase") }
    static var telemetryEraseMessage: String { s("telemetry.erase.message", "The server deletes every report of this copy of Cartouche, which then sends under a new number.") }
    static var telemetryEraseFailed: String { s("telemetry.erase.failed", "The server could not be reached. Try again when this iPhone is online.") }
    static var telemetryPrivacy: String { s("telemetry.privacy", "Privacy") }

    // MARK: Error reports

    static var reportCopy: String { s("errorReport.copy", "Copy the report") }
    static var reportCopied: String { s("errorReport.copied", "Report copied") }
    static var reportCopiedDetail: String { s("errorReport.copied.detail", "Paste it where you ask for help.") }
    static var reportHint: String { s("errorReport.hint", "Copies what went wrong, with the versions of Cartouche and iOS, without any password or server address.") }

    // MARK: Reporting a problem

    static var reportTitle: String { s("report.title", "Report a problem") }
    static var reportFooter: String { s("report.footer", "Say what went wrong. Cartouche adds its details, and you see everything first.") }
    static var reportNewDevice: String { s("report.newDevice", "Your report also adds this iPhone to Cartouche’s list.") }
    static var reportWhat: String { s("report.what", "What happened") }
    static var reportWhatPrompt: String { s("report.what.prompt", "What you did, what you expected, what happened instead") }
    static var reportWhatFooter: String { s("report.what.footer", "Cartouche adds this iPhone’s model and memory, the versions, and its last steps and errors.") }
    static var reportSend: String { s("report.send", "Send the report…") }
    static var reportGitHub: String { s("report.github", "Report it on GitHub") }
    static var reportSendToCartouche: String { s("report.sendToCartouche", "Send to Cartouche") }
    static var reportSending: String { s("report.sending", "Sending…") }
    static var reportSent: String { s("report.sent", "Sent to Cartouche") }
    static var reportSendTooMany: String { s("report.send.tooMany", "Cartouche’s server takes no more reports for now: send this one another way.") }
    static var reportSendRefused: String { s("report.send.refused", "Cartouche’s server did not take the report: send it another way.") }
    static func reportSendUnreachable(_ reason: String) -> String { f("report.send.unreachable", "Cartouche’s server could not be reached: %@", reason) }
    static var reportSendFooterServer: String { s("report.send.footer.server", "Send to Cartouche passes it to the project, privately. Or send it by Messages, Mail or AirDrop to whoever helps you. On GitHub, you check it and post it yourself: it is public there.") }
    static var reportSendFooter: String { s("report.send.footer", "Send it by Messages, Mail or AirDrop to whoever helps you. On GitHub, you check it and post it yourself: it is public there.") }
    static var reportContents: String { s("report.contents", "What the report holds") }
    static var reportPrivacy: String { s("report.privacy", "It leaves this iPhone only when you send it, without passwords, server names or addresses, user names, Apple ID or team, even in what you write.") }

    // MARK: A game's log (CartoucheGameLogView)

    static var gameLogRow: String { s("gameLog.row", "Share the log") }
    static var gameLogTitle: String { s("gameLog.title", "Game log") }
    static var gameLogLast: String { s("gameLog.last", "Last session") }
    static var gameLogBefore: String { s("gameLog.before", "Session before") }
    static var gameLogCrashed: String { s("gameLog.crashed", "Ended in a crash") }
    static var gameLogNone: String { s("gameLog.none", "The game has not written a log yet.") }
    static var gameLogFooter: String { s("gameLog.footer", "What the game wrote as it ran: whoever helps you sees in it how it started and how it ended.") }
    static var gameLogShare: String { s("gameLog.share", "Send the log…") }
    static var gameLogPreparing: String { s("gameLog.preparing", "Preparing the log…") }
    static func gameLogZipFailed(_ reason: String) -> String { f("gameLog.zipFailed", "The log could not be prepared: %@", reason) }
    static var gameLogShareFooter: String { s("gameLog.share.footer", "By Messages, Mail or AirDrop, to whoever helps you: the log goes as the game wrote it, with the names of your folders in it.") }
    static var gameLogWhatPrompt: String { s("gameLog.what.prompt", "What happened (optional)") }
    static var gameLogWhatIsSent: String { s("gameLog.whatIsSent", "What Cartouche receives") }
    static var gameLogSendFooter: String { s("gameLog.send.footer", "Cartouche receives the start and the end of each log, privately and cleaned: without the paths of your folders, addresses, names or identifiers.") }
    static var gameLogSentFooter: String { s("gameLog.sent.footer", "What is in angle brackets, such as <path> or <address>, stands for what was taken out. Cartouche’s server passes the rest to the project, privately.") }
    /// The word in the zip's name: "Mario Kart World log 2026-11-13 2105.zip".
    static var gameLogFileWord: String { s("gameLog.fileWord", "log") }

    // MARK: Warnings before expiry

    static var warning24hTitle: String { s("warning.24h.title", "Cartouche expires in 24 hours") }
    static var warning6hTitle: String { s("warning.6h.title", "Cartouche expires in 6 hours") }
    static var warningBody: String { s("warning.body", "Renew it on the System page.") }
    static var warningExpiredTitle: String { s("warning.0h.title", "Cartouche has expired") }
    static var warningExpiredBody: String { s("warning.0h.body", "Install it again from a computer with the Cartouche Installer, over this copy: your games stay.") }

    // MARK: Units

    static func mebibytes(_ value: Int) -> String {
        f("unit.mib", "%@\u{00A0}MiB", grouped(value))
    }

    static func gigabytes(_ value: Int) -> String {
        gigabytes(text: grouped(value))
    }

    private static func gigabytes(text: String) -> String {
        f("unit.gb", "%@\u{00A0}GB", text)
    }

    /// "6,143 MiB (6.0 GiB)", with the reader's separators.
    static func memoryAmount(mebibytes value: Int) -> String {
        let gibibytes = Double(value) / 1024
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let gib = formatter.string(from: NSNumber(value: gibibytes)) ?? String(format: "%.1f", gibibytes)
        return mebibytes(value) + " (" + f("unit.gib", "%@\u{00A0}GiB", gib) + ")"
    }

    /// A size on the disk, in decimal units as iOS counts storage:
    /// "23.4 GB", "312 MB", "48 KB".
    static func size(bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 { return storageAmount(bytes: Int64(clamping: bytes)) }
        if bytes >= 1_000_000 {
            let megabytes = grouped(Int(bytes / 1_000_000))
            return f("unit.mb", "%@\u{00A0}MB", megabytes)
        }
        let kilobytes = grouped(Int((bytes + 999) / 1_000))
        return f("unit.kb", "%@\u{00A0}KB", kilobytes)
    }

    /// A file's size as the system writes it, "48 KB", "1.2 MB": on the
    /// Mac, in the language the console speaks.
    static func fileSize(_ bytes: UInt64) -> String {
        #if os(macOS)
        return Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(locale))
        #else
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
        #endif
    }

    /// "23.4 GB", in decimal gigabytes as iOS counts storage.
    static func storageAmount(bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = Double(bytes) / 1_000_000_000
        return gigabytes(text: formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value))
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
