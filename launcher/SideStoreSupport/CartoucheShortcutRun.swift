//
//  CartoucheShortcutRun.swift
//  Cartouche
//
//  Notes each run of Refresh All Apps, the action of Shortcuts that the
//  player's automation runs every night to renew Cartouche
//  (app/patches/livecontainer/0018): when it started, whether LocalDevVPN's
//  tunnel was up once it had waited for it, and how it ended. iOS lets no
//  app see the player's automations: the launcher reads this run in
//  Cartouche's defaults (CartoucheNightlyRenewal, CartoucheRenewalRules.swift)
//  for the setup's last step, the page of the automation and the System
//  page. Renew now and Cartouche's own renewals go through CartoucheRefresh,
//  never through this action, and note nothing here.
//
//  This file joins LiveContainer's SideStoreSupport framework, which
//  cannot import the launcher: app/tests/test_renewal.py checks that both
//  read and write the same key and the same names.
//

import Foundation

enum CartoucheShortcutRun {
    /// The run's key in Cartouche's defaults: CartoucheNightlyRenewal.runKey.
    static let key = "Cartouche.nightly.run"

    /// Refresh All Apps starts, before it waits for LocalDevVPN: a run that
    /// iOS ends before it ends stays so.
    static func started() {
        UserDefaults.standard.set(["started": Date()], forKey: key)
    }

    /// Whether LocalDevVPN's tunnel was up once Refresh All Apps had waited
    /// for it.
    static func tunnel(_ up: Bool) {
        update { $0["tunnel"] = up }
    }

    /// Refresh All Apps ended, with the error it failed on, if any.
    static func ended(_ error: Error?) {
        update { run in
            run["ended"] = Date()
            if let error { run["message"] = error.localizedDescription }
        }
    }

    private static func update(_ change: (inout [String: Any]) -> Void) {
        var run = UserDefaults.standard.dictionary(forKey: key) ?? ["started": Date()]
        change(&run)
        UserDefaults.standard.set(run, forKey: key)
    }
}
