//
//  CartoucheSideStoreInstall.swift
//  Cartouche
//
//  Cartouche installed by the player's own SideStore, from Cartouche's
//  source for SideStore (app/sidestore-player-source.json), without a
//  computer (docs/decisions/147.md). Its IPA, the one for the player's
//  SideStore (app/scripts/sidestore_ipa.py), has an app group of its own,
//  so that the built-in SideStore never shares its database with the
//  player's. The setup then differs in three ways:
//
//  - the pairing file: the player's SideStore has the one of this iPhone,
//    and gives it to the app that asks for it with sidestore://pairing
//    (CartoucheSideStoreLink). SideStore opens a moment, then Cartouche
//    again with the file, which goes where the built-in SideStore reads it.
//    Cartouche takes an answer only for ten minutes after it asked;
//  - the certificate: the player's SideStore leaves the one it signed
//    Cartouche with in the app (ALTCertificate.p12), and the built-in
//    SideStore takes it at the sign-in with the same Apple ID
//    (app/patches/sidestore/0012): nothing is created or revoked;
//  - Increased Memory Limit: a SideStore on a free team leaves it out
//    (SideStore#1616), and iOS then gives Cartouche about 3 GB. Once set
//    up, Cartouche has the built-in SideStore install it again, once,
//    signed by itself, which asks Apple for it
//    (CartoucheUpdates.reinstallForMemory, app/patches/sidestore/0025).
//
//  After that, the built-in SideStore renews and updates Cartouche as it
//  does any other install, from the source for SideStore.
//

import Foundation
import UIKit

enum CartoucheSideStoreInstall {
    /// Whether this copy is the IPA for the player's SideStore.
    static var isSideStoreInstall: Bool { CartoucheImportedSigning.mode == .sideStore }

    /// How long Cartouche takes the answer of the player's SideStore after
    /// it asked: SideStore answers at once, and no other app's link is
    /// taken for a pairing file.
    static let answerWindow: TimeInterval = 600
    private static let askedKey = "Cartouche.sideStore.pairingAsked"

    /// Cartouche's own URL scheme, the first the app answers.
    static var ownScheme: String? {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first
    }

    /// Whether Increased Memory Limit is left, and what can be done of it.
    @MainActor static var memory: CartoucheSideStoreMemory {
        #if CARTOUCHE_GALLERY
        if let shown = GalleryState.sideStoreMemory { return shown }
        #endif
        return CartoucheSideStoreMemory(hasIncreasedMemoryLimit: CartoucheDevice.hasIncreasedMemoryLimit,
                                        setupComplete: CartoucheSetup.shared.isComplete)
    }

    /// Asks the player's SideStore for this iPhone's pairing file.
    @MainActor static func askForPairingFile() {
        guard let scheme = ownScheme, let url = CartoucheSideStoreLink.pairingRequest(answeringTo: scheme) else {
            CartoucheSetup.shared.pairingFromSideStoreFailed()
            return
        }
        CartoucheReports.note("Pairing file asked of the player's SideStore")
        UserDefaults.standard.set(Date(), forKey: askedKey)
        UIApplication.shared.open(url) { opened in
            guard !opened else { return }
            Task { @MainActor in
                UserDefaults.standard.removeObject(forKey: askedKey)
                CartoucheSetup.shared.pairingFromSideStoreFailed()
            }
        }
    }

    /// The pairing file the player's SideStore answered with
    /// (app/patches/livecontainer/0019): whether URL was that answer.
    @MainActor static func opened(_ url: URL) -> Bool {
        guard let scheme = ownScheme, let data = CartoucheSideStoreLink.pairingFile(in: url, scheme: scheme) else { return false }
        let defaults = UserDefaults.standard
        guard isSideStoreInstall, let asked = defaults.object(forKey: askedKey) as? Date,
              Date().timeIntervalSince(asked) < answerWindow else {
            // A link no request of Cartouche's led to: never a pairing file.
            CartoucheReports.note("A pairing file came by a link Cartouche did not ask for: left alone")
            return true
        }
        defaults.removeObject(forKey: askedKey)
        CartoucheSetup.shared.importPairingFile(data: data)
        return true
    }
}
