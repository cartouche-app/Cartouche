//
//  CartoucheUpdate.swift
//  Cartouche
//
//  Lets Cartouche update itself without a computer, and without showing
//  SideStore. The built-in SideStore starts in LiveProcess, as it does to
//  renew the app (CartoucheRefresh), and runs its Update Cartouche action
//  (app/patches/sidestore/0010): it reads Cartouche's source, downloads the
//  newest version, signs it and installs it over the app, and reports its
//  progress.
//
//  Installed by the player's own SideStore, Cartouche also has the built-in
//  SideStore install the version that runs again, once, with its Reinstall
//  Cartouche action (app/patches/sidestore/0025): signed by the built-in
//  SideStore, Cartouche gets Increased Memory Limit, which the player's
//  leaves out on a free team (docs/decisions/147.md).
//
//  This file joins LiveContainer's SideStoreSupport framework, which
//  LiveContainer loads when the app carries the built-in SideStore. The
//  launcher cannot import that framework, so it finds this class by its
//  Objective-C name (CartoucheUpdates).
//

import Foundation

@objc(CartoucheUpdate)
public final class CartoucheUpdate: NSObject {
    /// Installs the newest version of Cartouche that its source lists.
    /// `progress` counts to 100; `completion` runs on the main queue, with
    /// nil or the error's text.
    @objc(updateCartoucheWithProgress:completion:)
    public static func updateCartouche(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else {
            completion("Updating from Cartouche needs iOS 17 or later.")
            return
        }
        Task { @MainActor in
            do {
                // UpdateCartoucheIntent, in SideStore's module.
                try await performIntentRefresh(
                    identifier: "UpdateCartoucheIntent",
                    mangledTypeName: "9SideStore21UpdateCartoucheIntentV",
                    intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Installs the version of Cartouche that runs, or a newer one, from
    /// its source, signed by the built-in SideStore. `progress` counts to
    /// 100; `completion` runs on the main queue, with nil or the error's
    /// text.
    @objc(reinstallCartoucheWithProgress:completion:)
    public static func reinstallCartouche(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else {
            completion("Installing Cartouche again needs iOS 17 or later.")
            return
        }
        Task { @MainActor in
            do {
                // ReinstallCartoucheIntent, in SideStore's module.
                try await performIntentRefresh(
                    identifier: "ReinstallCartoucheIntent",
                    mangledTypeName: "9SideStore24ReinstallCartoucheIntentV",
                    intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }
}
