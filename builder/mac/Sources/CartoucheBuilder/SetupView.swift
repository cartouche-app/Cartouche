//
//  SetupView.swift
//  Cartouche Builder
//
//  This Mac's tools: what a build needs, each with its state and the
//  button that installs it. "Get everything ready" goes through them in
//  order and waits where macOS asks something of the player. Under
//  nxnative's row, where it is downloaded from, which can be changed
//  before it is: Build for, or another repository (BuildSourceChoice).
//

import BuilderKit
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var setup: MacSetup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: tr("This Mac’s tools", "Outils du Mac"), subtitle: subtitle) {
                    SetupButtons()
                }
                SetupList()
            }
            .padding(28)
        }
        .task { await setup.refresh() }
    }

    private var subtitle: String {
        setup.ready
            ? tr("Everything a build needs is here.", "Tout ce qu’une construction demande est là.")
            : tr("What nxnative needs to build your games, installed for you.", "Ce dont nxnative a besoin pour construire vos jeux, installé pour vous.")
    }
}

struct SetupButtons: View {
    @EnvironmentObject private var setup: MacSetup

    var body: some View {
        HStack {
            if setup.running {
                Button(tr("Stop", "Arrêter")) { setup.cancel() }
                    .controlSize(.large)
            } else if !setup.ready {
                Button {
                    setup.fixAll()
                } label: {
                    Label(tr("Get everything ready", "Tout préparer"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task { await setup.refresh() }
                } label: {
                    Label(tr("Check again", "Vérifier à nouveau"), systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct SetupList: View {
    @EnvironmentObject private var setup: MacSetup
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(SetupItem.allCases.enumerated()), id: \.element) { index, item in
                        if index > 0 { Divider().padding(.leading, 52) }
                        SetupRow(item: item)
                    }
                }
            }
            if !setup.log.isEmpty {
                DisclosureGroup(isExpanded: $showLog) {
                    ScrollView {
                        Text(setup.log.suffix(200).joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                } label: {
                    Text(tr("Details", "Détails"))
                        .font(.callout.weight(.medium))
                }
            }
        }
    }
}

struct SetupRow: View {
    @EnvironmentObject private var setup: MacSetup
    let item: SetupItem

    var body: some View {
        let state = setup.state(item)
        HStack(alignment: .top, spacing: 14) {
            icon(state)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    if case let .ready(what) = state {
                        Text(what)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(line(state))
                    .font(.caption)
                    .foregroundStyle(lineColor(state))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if item == .nxnative {
                    BuildSourceChoice()
                }
                if case let .working(_, fraction) = state {
                    if let fraction {
                        ProgressView(value: fraction)
                            .padding(.top, 2)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 12)
            if case .missing = state, !setup.running {
                Button(buttonText) { setup.fixOne(item) }
                    .controlSize(.small)
            } else if case .failed = state, !setup.running, item != .mac {
                Button(tr("Try again", "Réessayer")) { setup.fixOne(item) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func icon(_ state: SetupState) -> some View {
        switch state {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .checking, .working:
            ProgressView()
                .controlSize(.small)
        case .waiting:
            Image(systemName: "hourglass.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.indigo)
        case .missing:
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.title2)
                .foregroundStyle(.red)
        case .blocked:
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private func line(_ state: SetupState) -> String {
        switch state {
        case .checking: return tr("Checking…", "Vérification…")
        case .ready: return item.explanation
        case let .missing(text): return text + " " + item.explanation
        case let .working(text, _): return text
        case let .waiting(text): return text
        case let .failed(text): return text
        case .blocked: return item.explanation
        }
    }

    private func lineColor(_ state: SetupState) -> Color {
        switch state {
        case .failed: return .red
        case .waiting: return Theme.indigo
        default: return .secondary
        }
    }

    private var buttonText: String {
        switch item {
        case .mac: return tr("Update macOS", "Mettre à jour macOS")
        case .xcode: return setup.outdatedXcode != nil ? tr("Update Xcode", "Mettre à jour Xcode") : tr("Get Xcode", "Obtenir Xcode")
        case .xcodeReady: return tr("Finish", "Terminer")
        case .iosPlatform, .metal, .nxnative: return tr("Download", "Télécharger")
        case .homebrew, .tools: return tr("Install", "Installer")
        }
    }
}

/// Under nxnative's row: the repository it is downloaded from, the one the
/// games are built from, and the choice of it, open on Change…: whom the
/// games are built for (an iPhone whose GPU reads no BC texture has them
/// built from nxnative-nobc, a separate fork), and another repository. Chosen
/// before the download, it is what the step downloads; changed after, the
/// next build fetches the other one.
struct BuildSourceChoice: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bridge: BridgeController
    @Environment(\.showsBuildSource) private var shown
    @State private var open: Bool?

    var body: some View {
        let config = model.config ?? BuilderConfig()
        let isOpen = open ?? shown
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(BuildSourceChoice.line(BuildFor.choice(config, devices: bridge.devices),
                                                repository: BuildFor.repository(config, devices: bridge.devices)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button(isOpen ? tr("Done", "OK") : tr("Change…", "Changer…")) {
                        withAnimation(.easeInOut(duration: 0.2)) { open = !isOpen }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(model.config == nil)
                }
                if isOpen {
                    VStack(alignment: .leading, spacing: 12) {
                        BuildForPicker()
                        Divider()
                        Text(tr("Or another repository, as under Advanced: one other than nxnative’s wins over Build for.",
                                "Ou un autre dépôt, comme dans Avancé : un autre que celui de nxnative passe avant Construire pour."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        EngineRepositoryFields(labeled: true)
                        Text(tr("Chosen before nxnative is downloaded, it is what this step downloads. Changed after, the next build fetches it.",
                                "Choisi avant que nxnative soit téléchargé, c’est lui que cette étape télécharge. Changé après, la prochaine construction va le chercher."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                    .id(BuildSourceChoice.panel)
                }
            }
            .padding(.top, 2)
            // nxnative's row is the list's last: what Change… opens is brought
            // into sight, below the steps' fold.
            .onChange(of: open) { _, now in
                guard now == true else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(BuildSourceChoice.panel, anchor: .bottom) }
                }
            }
            .task {
                guard shown else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                proxy.scrollTo(BuildSourceChoice.panel, anchor: .bottom)
            }
        }
    }

    static let panel = "build-source-choice"

    /// Where nxnative comes from, in the player's words.
    static func line(_ choice: BuildFor.Choice, repository: (url: String, branch: String)) -> String {
        let address = BuildFor.address(repository.url)
        switch choice.kind {
        case .nxnative:
            return tr("From nxnative: \(address), branch \(repository.branch).",
                      "Depuis nxnative : \(address), branche \(repository.branch).")
        case .noBC:
            let whom: String
            if let device = choice.device {
                whom = tr("for “\(device)”", "pour « \(device) »")
            } else {
                let name = choice.model.flatMap(BuildFor.name(of:)) ?? choice.model ?? "iPhone"
                whom = tr("for the \(name)", "pour l’\(name)")
            }
            return tr("From nxnative-nobc, a separate fork of nxnative by mianmuhammadse, \(whom): \(address), branch \(repository.branch).",
                      "Depuis nxnative-nobc, une fourche distincte de nxnative par mianmuhammadse, \(whom) : \(address), branche \(repository.branch).")
        case .custom:
            return tr("From your repository: \(address), branch \(repository.branch).",
                      "Depuis votre dépôt : \(address), branche \(repository.branch).")
        }
    }
}

private struct ShowsBuildSourceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The gallery's: the choice of nxnative open under its row, as Change…
    /// opens it.
    var showsBuildSource: Bool {
        get { self[ShowsBuildSourceKey.self] }
        set { self[ShowsBuildSourceKey.self] = newValue }
    }
}
