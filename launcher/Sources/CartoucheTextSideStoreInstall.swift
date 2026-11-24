//
//  CartoucheTextSideStoreInstall.swift
//  Cartouche
//
//  The words of Cartouche installed by the player's own SideStore, from its
//  source for SideStore (CartoucheSideStoreInstall.swift,
//  docs/decisions/147.md), in Cartouche.xcstrings with the other words
//  (CartoucheText.swift): the pairing file asked of that SideStore, the
//  sign-in with its Apple ID, and Increased Memory Limit, which Cartouche
//  gets by installing itself again, once, through the built-in SideStore
//  (CartoucheUpdates.reinstallForMemory). The iPhone's alone.
//

import Foundation

extension CartoucheText {
    // MARK: The setup

    static var sideStoreIntro: String { s("sideStore.intro", "Four steps, once on this iPhone, then an automation that renews Cartouche every night.") }
    static var sideStorePairingHow: String { s("sideStore.pairing.how", "Your SideStore holds this iPhone’s pairing file: Cartouche asks it for it. SideStore opens for a moment, then brings you back here.") }
    static var sideStorePairingAsk: String { s("sideStore.pairing.ask", "Ask SideStore") }
    static var sideStoreNoAnswer: String { s("sideStore.pairing.noAnswer", "Cartouche could not open your SideStore. Open SideStore once, then try again, or choose the pairing file here.") }
    static var sideStoreAppleIDHow: String { s("sideStore.appleID.how", "Sign in once, with the Apple ID your SideStore uses: Cartouche takes the certificate SideStore signed it with, then renews itself every week.") }
    static var signInOtherCertificateSideStore: String { s("sideStore.signIn.otherCertificate", "This Apple ID has a certificate that Cartouche does not hold, and Cartouche never revokes it. Sign in with the Apple ID your SideStore uses: Cartouche takes the certificate SideStore signed it with. If it is this one, install Cartouche again from your SideStore, then sign in again.") }

    // MARK: Increased Memory Limit

    static var sideStoreMemoryTitle: String { s("sideStore.memory.title", "Increased Memory Limit") }
    static var sideStoreMemoryGranted: String { s("sideStore.memory.granted", "Active: iOS gives Cartouche and its games more memory.") }
    static var sideStoreMemoryAfterSetup: String { s("sideStore.memory.afterSetup", "Your SideStore leaves it out with a free Apple ID: without it, iOS gives Cartouche and its games about 3 GB. Once the steps above are done, Cartouche installs itself again, once, to get it.") }
    static var sideStoreMemoryReinstall: String { s("sideStore.memory.reinstall", "Your SideStore left it out with a free Apple ID: without it, iOS gives Cartouche and its games about 3 GB. Cartouche installs itself again, once, signed by itself, which gets it. It then goes to the home screen: open it again.") }
    static var sideStoreMemoryButton: String { s("sideStore.memory.button", "Reinstall Cartouche") }
    static var sideStoreMemoryLeftTitle: String { s("sideStore.memory.left.title", "One last step") }
    static var sideStoreMemoryLeft: String { s("sideStore.memory.left", "Increased Memory Limit, which your games need: Cartouche installs itself again, once, to get it.") }
    static var sideStoreMemoryBannerTitle: String { s("sideStore.memory.banner.title", "Get Increased Memory Limit") }
    static var sideStoreMemoryBannerDetail: String { s("sideStore.memory.banner.detail", "Cartouche installs itself again, once") }

    // MARK: The reinstall

    static var memoryReinstallPreparingTitle: String { s("memoryReinstall.preparing.title", "Reinstalling Cartouche") }
    static var memoryReinstallPreparingMessage: String { s("memoryReinstall.preparing.message", "Cartouche downloads itself again and the built-in SideStore signs it, with Increased Memory Limit. Keep Cartouche open.") }
    static var memoryReinstallInstallingTitle: String { s("memoryReinstall.installing.title", "Installing Cartouche again") }
    static var memoryReinstallInstallingMessage: String { s("memoryReinstall.installing.message", "Cartouche goes to the home screen for iOS to install it again. Open it again in a few seconds.") }
    static var memoryReinstallFailedTitle: String { s("memoryReinstall.failed.title", "The reinstall did not go through") }
    static var memoryReinstallDoneTitle: String { s("memoryReinstall.done.title", "Increased Memory Limit is active") }
    static var memoryReinstallDone: String { s("memoryReinstall.done", "Cartouche installed itself again with it: iOS now gives Cartouche and its games more memory.") }
    static var memoryReinstallWithoutTitle: String { s("memoryReinstall.without.title", "Still without Increased Memory Limit") }
    static var memoryReinstallWithout: String { s("memoryReinstall.without", "Cartouche opened again without it. Try again from Setup, with LocalDevVPN on. If it stays this way, copy the report.") }
}
