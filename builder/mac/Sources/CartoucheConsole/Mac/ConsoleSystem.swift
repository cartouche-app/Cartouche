//
//  ConsoleSystem.swift
//  Cartouche on the Mac
//
//  What the System page of the console on the Mac, the iPhone's
//  (CartoucheSystemView.swift), has of its own: Cartouche Builder, which
//  System opened before, in this window in place of the console, where
//  the iPhone has its Mac's builds; and the Builder's updates, where the
//  iPhone has Cartouche's, through its updater (BuilderKit/Updater.swift),
//  which the app shows here as its settings do (CartoucheMacUpdates).
//

import SwiftUI

/// Cartouche Builder, in the window in place of the console.
struct CartoucheMacBuilderSection: View {
    var body: some View {
        CartoucheSection {
            Button {
                CartoucheMacConsole.shared.onSystem()
            } label: {
                Label(CartoucheText.macSystemBuilder, systemImage: "hammer.fill")
            }
        } footer: {
            Text(CartoucheText.macSystemBuilderFooter)
        }
    }
}

// MARK: Updates

/// Cartouche Builder's updates, as its updater has them: the app keeps
/// these in step with it, and does what the buttons ask.
@MainActor
public final class CartoucheMacUpdates: ObservableObject {
    public static let shared = CartoucheMacUpdates()

    public enum Phase: Equatable {
        case idle, upToDate, checking
        /// A version on offer, not downloaded: updates do not install by
        /// themselves.
        case available(String)
        case downloading(String)
        /// Downloaded and checked: it installs when the app quits.
        case ready(String)
        case installing
        case failed(String)
    }

    @Published public var phase: Phase = .idle
    /// The last time the updater looked.
    @Published public var checked: Date?
    /// Whether updates download and install by themselves.
    @Published public var automatic = true
    /// The version that runs.
    @Published public var version = ""
    /// What's new in the version on offer.
    @Published public var notes: URL?
    /// Whether this copy can update: the app, not the engine run from a
    /// Terminal.
    @Published public var enabled = false

    public var onCheck: () -> Void = {}
    public var onDownload: () -> Void = {}
    public var onRestart: () -> Void = {}
    public var onAutomatic: (Bool) -> Void = { _ in }

    public init() {}

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

/// System › Updates on the Mac: the Builder's, with what its settings have.
struct CartoucheMacUpdatesSection: View {
    @ObservedObject private var updates = CartoucheMacUpdates.shared

    var body: some View {
        CartoucheSection {
            LabeledContent(CartoucheText.version, value: updates.version)
            state
            actions
            Toggle(CartoucheText.macUpdatesAutomatic, isOn: Binding(get: { updates.automatic }, set: { updates.onAutomatic($0) }))
        } header: {
            Text(CartoucheText.updatesTitle)
        } footer: {
            Text(CartoucheText.macUpdatesFooter)
        }
    }

    @ViewBuilder
    private var state: some View {
        switch updates.phase {
        case .idle:
            Text(updates.checked == nil ? CartoucheText.updateNotChecked : CartoucheText.updateUpToDate(updates.version))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(CartoucheText.updateUpToDate(updates.version))
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .available(let version):
            LabeledContent(CartoucheText.updateAvailable, value: version)
        case .downloading(let version):
            Label(CartoucheText.macUpdateDownloading(version), systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .ready(let version):
            Label(CartoucheText.macUpdateReady(version), systemImage: "checkmark.circle.fill")
        case .installing:
            Label(CartoucheText.macUpdateInstalling, systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updates.phase {
        case .available(let version):
            Button(CartoucheText.macUpdateDownload(version), systemImage: "arrow.down.circle") { updates.onDownload() }
            notesLink
        case .ready:
            Button(CartoucheText.macUpdateRestart, systemImage: "arrow.clockwise.circle") { updates.onRestart() }
            notesLink
        default:
            Button(CartoucheText.updateCheck, systemImage: "arrow.clockwise") { updates.onCheck() }
                .disabled(updates.isBusy || !updates.enabled)
        }
    }

    @ViewBuilder
    private var notesLink: some View {
        if let notes = updates.notes {
            Link(destination: notes) {
                Label(CartoucheText.updateNotes, systemImage: "doc.text")
            }
        }
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

    /// The Builder's updates, on the console's System page.
    static var macUpdatesAutomatic: String { s("mac.updates.automatic", "Install updates by itself") }
    static var macUpdatesFooter: String {
        s("mac.updates.footer",
          "Cartouche Builder looks for a new version every six hours, and installs it when it quits, never during a build.")
    }
    static func macUpdateDownload(_ version: String) -> String { f("mac.updates.download", "Download %@", version) }
    static func macUpdateDownloading(_ version: String) -> String { f("mac.updates.downloading", "Downloading %@…", version) }
    static func macUpdateReady(_ version: String) -> String {
        f("mac.updates.ready", "%@ is ready: it installs when Cartouche Builder quits.", version)
    }
    static var macUpdateRestart: String { s("mac.updates.restart", "Restart to update") }
    static var macUpdateInstalling: String { s("mac.updates.installing", "Installing…") }
}
