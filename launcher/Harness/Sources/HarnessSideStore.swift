//
//  HarnessSideStore.swift
//  CartoucheHarness
//
//  The built-in SideStore's renewal, as the launcher reaches it: the class
//  CartoucheRefresh of SideStoreSupport (launcher/SideStoreSupport), which
//  LiveContainer loads with the built-in SideStore, and the record of
//  Cartouche's signature SideStore keeps for its widget, which Cartouche
//  reads its expiry from (CartoucheSignature). Here SideStore renews as a
//  test says (HarnessLC.renewal): it records each call, takes
//  HarnessLC.renewalTime, then records the new expiry and answers, or
//  fails with SideStore's words, or answers only when the test lets it.
//  Without LiveProcess in the app (HarnessLC.removeLiveProcess), the bridge
//  answers at once with LiveContainer's words, SideStore never started.
//

import Foundation

enum HarnessSideStore {
    /// How a renewal goes.
    enum Renewal: Equatable {
        /// Renewed: the signature lasts DAYS from then.
        case renews(days: Double)
        /// SideStore fails with this message, Cartouche not renewed.
        case fails(String)
        /// SideStore fails as Apple revoked the certificate it signs with,
        /// and leaves why, as the built-in SideStore does
        /// (CartoucheSideStoreOutcome): Cartouche not renewed.
        case revoked
        /// SideStore no longer answers, until the test lets it
        /// (HarnessLC.endHeldRenewal), which renews Cartouche for seven
        /// days.
        case hangs
    }

    /// Records Cartouche's signature as expiring DAYS from now, as SideStore
    /// does once it has renewed it, in widget_data.json in the app group.
    static func record(expiringIn days: Double, renewed: Date = Date()) {
        let record: [String: Any] = [
            "allApps": [[
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                "expirationDate": Date().addingTimeInterval(days * 86_400).timeIntervalSinceReferenceDate,
                "refreshedDate": renewed.timeIntervalSinceReferenceDate,
            ]],
        ]
        let data = try? JSONSerialization.data(withJSONObject: record)
        try? data?.write(to: LCSharedUtils.appGroupPath().appendingPathComponent("widget_data.json"), options: .atomic)
    }

    /// What LiveContainer's bridge says when LiveProcess is not in the app,
    /// where it looks for it before it starts SideStore
    /// (app/LiveContainer/SideStoreSupport/SideStore.swift).
    static let noLiveProcess = "Unable to locate LiveProcess bundle. To use the Refresh All Apps shortcut, reinstall "
        + "LiveContainer+SideStore with LiveProcess installed. If you use SideStore, choose \"Keep App Extensions (Use Main "
        + "Profile)\". If you use PlumeImpactor, choose \"Only Register Main Bundle\". For other sideloaders, select keep "
        + "all extensions, i.e. DO NOT Remove any extension."

    /// Whether LiveProcess is in the app's PlugIns, as LiveContainer's
    /// bridge finds it: a folder, read again at each call.
    static var hasLiveProcess: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: plugins.appendingPathComponent("LiveProcess.appex").path,
                                              isDirectory: &isFolder) && isFolder.boolValue
    }

    /// Leaves in Cartouche's keychain how ACTION ended, failed with FIELDS,
    /// as the built-in SideStore does (app/patches/sidestore/0014).
    static func leaveFailure(_ fields: [String: Any], action: CartoucheSideStoreOutcome.Action) {
        var written: [String: Any] = ["version": 1, "action": action.rawValue, "ok": false,
                                      "date": Int(Date().timeIntervalSince1970)]
        written.merge(fields) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: written) else { return }
        _ = CartoucheStoreKeychain.set(data, for: CartoucheSideStoreOutcome.account)
    }
}

/// Renews Cartouche as HarnessLC.renewal says, as the System page, and
/// Cartouche by itself, ask SideStore through LiveContainer's bridge.
@objc(CartoucheRefresh)
final class HarnessRefresh: NSObject {
    /// `progress` counts to 100; `completion` runs on the main queue, with
    /// nil or the error's text.
    @objc(refreshAllAppsWithProgress:completion:)
    static func refreshAllApps(progress: Progress, completion: @escaping (String?) -> Void) {
        HarnessLC.renewals.append(Date())
        HarnessLC.vpnAtRenewals.append(HarnessLC.vpnConnected)
        guard HarnessSideStore.hasLiveProcess else {
            DispatchQueue.main.async { completion(HarnessSideStore.noLiveProcess) }
            return
        }
        let renewal = HarnessLC.renewal
        progress.totalUnitCount = 100
        progress.completedUnitCount = 10
        if renewal == .hangs {
            HarnessLC.heldRenewal = {
                HarnessSideStore.record(expiringIn: 7)
                progress.completedUnitCount = 100
                completion(nil)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + HarnessLC.renewalTime) {
            switch renewal {
            case .renews(let days):
                HarnessSideStore.record(expiringIn: days)
                progress.completedUnitCount = 100
                completion(nil)
            case .fails(let message):
                completion(message)
            case .revoked:
                // As 4 renewals of 0.12.x left it on November 13 and 14.
                HarnessSideStore.leaveFailure(["stage": "VerifyCertificate", "trail": "FetchAnisetteData>VerifyCertificate",
                                               "family": "operation", "kind": "certificateRevoked",
                                               "codes": "SideStore.OperationError 2"], action: .refresh)
                completion("The certificate has been revoked.")
            case .hangs:
                break
            }
        }
    }
}
