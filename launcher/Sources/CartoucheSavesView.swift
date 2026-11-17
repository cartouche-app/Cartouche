//
//  CartoucheSavesView.swift
//  Cartouche
//
//  A game's saves on its sheet, kept in step with the player's saves folder
//  (CartoucheSaveBackups): when they were last, what came and what was
//  kept, Sync now, and the copies of the saves, one of which can be put
//  back, with the game's saves between the player's Switch and this iPhone
//  (CartoucheSwitchSaveView). The same screens on the Mac, in Cartouche's
//  console, where the Builder keeps the saves of nxnative's apps for the
//  Mac in step (builder/mac/Sources/CartoucheConsole/Mac/ConsoleSaves.swift).
//

import Combine
import SwiftUI

// MARK: A game's saves, on its sheet

@available(iOS 17.0, *)
struct CartoucheSavesSection: View {
    /// The game's saves; nil for a game that never started, which has no
    /// data folder yet: a save can come from the Switch then.
    let target: CartoucheSaveTarget?
    /// Whether the game runs behind the console, writing its saves: they
    /// are neither synced nor put back meanwhile.
    let isRunning: Bool
    /// The game, for its saves between the player's Switch and this
    /// iPhone (CartoucheSwitchSaveView).
    let switchGame: CartoucheSwitchSaveGame?
    @ObservedObject var backups = CartoucheSaveBackups.shared
    @ObservedObject private var settings = CartoucheStorageSettings.shared
    @ObservedObject private var reach = CartoucheStorageReach.shared
    @State private var syncing = false

    init(target: CartoucheSaveTarget?, isRunning: Bool = false, switchGame: CartoucheSwitchSaveGame? = nil) {
        self.target = target
        self.isRunning = isRunning
        self.switchGame = switchGame
    }

    /// The row of the saves between the Switch and this iPhone, which a
    /// list can scroll to.
    static let switchRow = "switchSaves"

    #if CARTOUCHE_GALLERY
    /// Where the row of the Switch saves is in the window, once the list has
    /// laid it out, for the gallery's screenshot of the sheet at its saves.
    static var galleryRowFrame: CGRect?
    #endif

    var body: some View {
        Section {
            if let target {
                rows(of: target)
            }
            if let switchGame {
                NavigationLink {
                    CartoucheSwitchSaveView(game: switchGame, isRunning: isRunning)
                } label: {
                    Label(CartoucheText.switchSaveTitle, systemImage: "arrow.left.arrow.right")
                }
                .id(Self.switchRow)
                #if CARTOUCHE_GALLERY
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { Self.galleryRowFrame = $0 }
                #endif
            }
        } header: {
            Text(CartoucheText.savesTitle)
        } footer: {
            if let target, !isLeftToCloud(target) {
                Text(CartoucheText.savesFooter(CartoucheSaveBackups.kept))
                    .cartoucheFooter()
            }
        }
    }

    /// Whether nxnative's own cloud saves keep TARGET's saves: only the Mac
    /// leaves them to it.
    private func isLeftToCloud(_ target: CartoucheSaveTarget) -> Bool {
        #if os(macOS)
        return backups.isLeftToCloud(target)
        #else
        return false
        #endif
    }

    /// The rows of TARGET's saves: on the Mac, those of a game whose saves
    /// nxnative's own cloud saves keep, chosen in its window, say so, as
    /// the Builder leaves them alone (MacGames in BuilderKit).
    @ViewBuilder
    private func rows(of target: CartoucheSaveTarget) -> some View {
        #if os(macOS)
        if backups.isLeftToCloud(target) {
            Label(CartoucheText.savesInCloud, systemImage: "icloud")
                .foregroundStyle(.secondary)
        } else {
            keptRows(of: target)
        }
        #else
        keptRows(of: target)
        #endif
    }

    /// The rows of TARGET's saves, kept in step with the saves folder.
    @ViewBuilder
    private func keptRows(of target: CartoucheSaveTarget) -> some View {
        if let location = settings.location(.saves) {
            if let news = backups.news[target.key], let line = Self.line(of: news) {
                Label(line, systemImage: news.kept == nil ? "arrow.down.circle.fill" : "arrow.triangle.branch")
                    .font(.footnote)
            }
            LabeledContent(CartoucheText.savesLastSync) {
                if let date = backups.lastSync[target.key] {
                    Text(date, format: .relative(presentation: .named).locale(CartoucheText.locale))
                } else {
                    Text(CartoucheText.savesNoCopy)
                }
            }
            if settings.isReadOnly(.saves) {
                Text(CartoucheText.savesReadOnly)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            } else {
                Button {
                    syncing = true
                    Task {
                        _ = await backups.syncNow(target)
                        syncing = false
                    }
                } label: {
                    HStack {
                        Label(CartoucheText.savesSyncNow(location.server.name), systemImage: "arrow.triangle.2.circlepath")
                        if syncing || backups.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(syncing || backups.isSyncing || isRunning)
            }
            NavigationLink {
                CartoucheSaveCopiesView(target: target)
            } label: {
                Label(CartoucheText.savesPutBack, systemImage: "clock.arrow.circlepath")
            }
            .disabled(isRunning)
            if isRunning {
                Text(CartoucheText.savesRunning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if reach.isOffline(location.server.id) {
                let away = CartoucheStorageOffline(location.server)
                Label(away.localizedDescription, systemImage: away.symbol)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                if backups.waiting.contains(target.key) {
                    Text(CartoucheText.savesWaitingHere)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let problem = backups.problem(of: target) {
                Text(problem.message)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                CartoucheReportButton(report: problem)
            }
        } else {
            Text(CartoucheText.savesNoFolder)
                .foregroundStyle(.secondary)
        }
    }

    /// What the last sync did that the player should know: the saves that
    /// came, and those of this iPhone kept as a copy, by their dates.
    private static func line(of news: CartoucheSaveNews) -> String? {
        let fetched = news.fetched.map(CartoucheText.dateAndTime)
        let kept = news.kept.map(CartoucheText.dateAndTime)
        if let fetched, let kept {
            return CartoucheText.savesFetchedOver(fetched, kept)
        }
        if let fetched {
            return CartoucheText.savesFetched(fetched)
        }
        return kept.map(CartoucheText.savesKeptHere)
    }
}

/// A game's copies of saves, the newest first: one is put back after a
/// question.
@available(iOS 17.0, *)
struct CartoucheSaveCopiesView: View {
    let target: CartoucheSaveTarget
    @State private var copies: [CartoucheSaveBackup]?
    @State private var problem: CartoucheReport?
    @State private var asking: CartoucheSaveBackup?
    @State private var restoring = false
    @State private var restored: Date?
    /// Why the last copy was not put back, and the report on it.
    @State private var failure: CartoucheReport?
    /// Why the server did not answer, when it is offline from here: for
    /// the list, and for the last copy put back.
    @State private var offline: String?
    @State private var restoreOffline: String?

    init(target: CartoucheSaveTarget) {
        self.target = target
    }

    var body: some View {
        List {
            if let restored {
                Section {
                    Label(CartoucheText.savesPutBackDone(CartoucheText.dateAndTime(restored)),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
            }
            if let failure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    CartoucheReportButton(report: failure)
                }
            } else if let restoreOffline {
                Section {
                    Label(restoreOffline, systemImage: "wifi.slash")
                        .foregroundStyle(Color.orange)
                }
            }
            Section {
                if let copies {
                    ForEach(copies) { copy in
                        Button {
                            asking = copy
                        } label: {
                            LabeledContent {
                                Text(CartoucheText.fileSize(copy.size))
                            } label: {
                                Label(CartoucheText.dateAndTime(copy.date), systemImage: "doc.zipper")
                            }
                        }
                        .tint(.primary)
                        .disabled(restoring)
                    }
                    if copies.isEmpty {
                        Text(CartoucheText.savesNoCopy)
                            .foregroundStyle(.secondary)
                    }
                } else if let offline {
                    CartoucheOfflineRows(message: offline) {
                        self.offline = nil
                        Task { await load() }
                    }
                } else if let problem {
                    Text(problem.message)
                        .foregroundStyle(Color.orange)
                    CartoucheReportButton(report: problem)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(CartoucheText.savesPutBackFooter)
                    .cartoucheFooter()
            }
        }
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.savesPutBack)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .cartoucheConsolePage(CartoucheText.savesPutBack)
        #endif
        .overlay {
            if restoring {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .confirmationDialog(CartoucheText.savesPutBackQuestion, isPresented: askingShown, titleVisibility: .visible,
                            presenting: asking) { copy in
            Button(CartoucheText.savesPutBackAction(CartoucheText.dateAndTime(copy.date)),
                   role: .destructive) {
                Task { await restore(copy) }
            }
            Button(CartoucheText.cancel, role: .cancel) {}
        } message: { _ in
            Text(CartoucheText.savesPutBackMessage)
        }
        .task { await load() }
        // The server answers again: the list it could not give comes.
        .onReceive(CartoucheStorageReach.shared.cameBack) { _ in
            guard offline != nil else { return }
            offline = nil
            Task { await load() }
        }
    }

    private var askingShown: Binding<Bool> {
        Binding(get: { asking != nil }, set: { shown in if !shown { asking = nil } })
    }

    private func load() async {
        do {
            copies = try await CartoucheSaveBackups.shared.copies(of: target)
            problem = nil
            offline = nil
        } catch let away as CartoucheStorageOffline {
            // No problem to report: the player is away from the server.
            copies = nil
            offline = away.localizedDescription
        } catch {
            problem = CartoucheReports.make(.saves, CartoucheText.savesListFailed, message: error.localizedDescription,
                                            error: error, step: "Listing the copies of " + target.name + "'s saves, in "
                                                + CartoucheReports.place(.saves), stage: "savesList")
        }
    }

    private func restore(_ copy: CartoucheSaveBackup) async {
        restoring = true
        restored = nil
        failure = nil
        restoreOffline = nil
        do {
            try await CartoucheSaveBackups.shared.restore(copy, of: target)
            restored = copy.date
            CartoucheReports.note("Saves of " + target.name + " put back from " + CartoucheReport.timestamp(copy.date))
        } catch let away as CartoucheStorageOffline {
            restoreOffline = away.localizedDescription
        } catch {
            failure = CartoucheReports.make(.saves, CartoucheText.savesPutBackFailed, message: error.localizedDescription,
                                            error: error, step: "Putting back a copy of " + target.name + "'s saves", stage: "savesPutBack",
                                            facts: [.init("Copy", CartoucheReport.timestamp(copy.date) + ", "
                                                + CartoucheReport.bytes(Int64(clamping: copy.size)))])
        }
        restoring = false
        // Putting a copy back first copies the saves it replaces.
        await load()
    }
}

/// A server that does not answer from here, where what it holds would
/// show, with a button that tries it again.
@available(iOS 17.0, *)
struct CartoucheOfflineRows: View {
    let message: String
    var isTrying = false
    let tryAgain: () -> Void

    var body: some View {
        Label(message, systemImage: "wifi.slash")
            .foregroundStyle(Color.orange)
        CartoucheTryAgainButton(isTrying: isTrying, action: tryAgain)
    }
}

/// Try again, for a server that does not answer from here: busy while it
/// is being tried.
@available(iOS 17.0, *)
struct CartoucheTryAgainButton: View {
    var isTrying = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(CartoucheText.storageTryAgain, systemImage: "arrow.clockwise")
                if isTrying {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isTrying)
    }
}
