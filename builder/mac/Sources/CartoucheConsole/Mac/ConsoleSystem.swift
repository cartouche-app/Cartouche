//
//  ConsoleSystem.swift
//  Cartouche on the Mac
//
//  The console's System page on the Mac, which its dock's System opens,
//  until the iPhone's comes to the Mac with its reports and its guide
//  (CartoucheSystemView.swift, step 8 of the plan): the player's storage,
//  the iPhone's Storage page, its connections the same as the paired
//  iPhones'; the game measurements, the iPhone's page, of the telemetry
//  the Builder sends (ConsoleTelemetry.swift); and Cartouche Builder,
//  which System opened before.
//

import SwiftUI

struct CartoucheMacSystemView: View {
    @ObservedObject private var settings = CartoucheStorageSettings.shared
    @ObservedObject private var reach = CartoucheStorageReach.shared
    @ObservedObject private var telemetry = CartoucheTelemetry.shared
    /// Cartouche Builder, in the window in place of the console.
    let onBuilder: () -> Void

    // Written out: the private state above makes the synthesized
    // initializer private.
    init(onBuilder: @escaping () -> Void) {
        self.onBuilder = onBuilder
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: CartoucheMacConsoleView.Route.storage) {
                    LabeledContent {
                        // A server the console uses that does not answer
                        // from here, as on the iPhone's System page.
                        if let offline = reach.offlineInUse.first {
                            let away = CartoucheStorageOffline(offline)
                            Label(away.short, systemImage: away.symbol)
                                .lineLimit(1)
                                .foregroundStyle(Color.orange)
                        } else {
                            Text(CartoucheText.macStorageConnections(settings.servers.filter(\.travels).count))
                                .lineLimit(1)
                        }
                    } label: {
                        Label(CartoucheText.storageTitle, systemImage: "externaldrive.fill")
                    }
                }
            }
            // As on the iPhone's System page.
            Section {
                NavigationLink(value: CartoucheMacConsoleView.Route.telemetry) {
                    LabeledContent {
                        Text(telemetry.isOn ? CartoucheText.telemetryOn : CartoucheText.telemetryOff)
                    } label: {
                        Label(CartoucheText.telemetryTitle, systemImage: "chart.bar.xaxis")
                    }
                }
            }
            CartoucheSection {
                Button(action: onBuilder) {
                    Label(CartoucheText.macSystemBuilder, systemImage: "hammer.fill")
                }
            } footer: {
                Text(CartoucheText.macSystemBuilderFooter)
            }
        }
        .tint(.primary)
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.systemTab)
    }
}

extension CartoucheText {
    /// Cartouche Builder, on the console's System page.
    static var macSystemBuilder: String { s("mac.system.builder", "Open Cartouche Builder") }
    static var macSystemBuilderFooter: String {
        s("mac.system.builder.footer",
          "Your games built for this Mac, their builds, this Mac’s folders and its iPhones: the Builder, in this window in place of the console.")
    }

    /// The way back from the console's System page.
    static var macBackToConsole: String { s("mac.system.back", "Back to the console") }

    /// The connections of the Storage page, on the System page.
    static func macStorageConnections(_ count: Int) -> String {
        switch count {
        case 0: return s("mac.storage.connections.none", "No connection")
        case 1: return s("mac.storage.connections.one", "1 connection")
        default: return f("mac.storage.connections.many", "%lld connections", count)
        }
    }
}
