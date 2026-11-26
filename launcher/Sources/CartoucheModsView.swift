//
//  CartoucheModsView.swift
//  Cartouche
//
//  A game's mods, from its sheet (CartoucheMods.swift): Add a mod, from
//  Files, as its folder or its ZIP, and the game's mods in their order, the
//  one higher up winning where two change the same file, each with its
//  size, a switch that turns it on or off, Move up, Move down and Delete,
//  and what stops it: no romfs folder, or code beside it, which an iPhone
//  cannot run. A mod added for another version of the game says so. Nothing
//  changes while the game runs behind the console; what changes takes
//  effect at its next start, as Cartouche writes the line nxnative reads
//  before it (CartoucheMods.prepareStart). The same page in the console on
//  the Mac, its words of a Mac (builder/mac/console/strings.json).
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: On the sheet

@available(iOS 17.0, *)
struct CartoucheModsSection: View {
    /// The game, as for its saves between the Switch and this iPhone: its
    /// Documents, where its mods are, made when the first comes.
    let game: CartoucheSwitchSaveGame
    /// Whether the game runs behind the console: its mods stay as they are.
    let isRunning: Bool
    /// How many the game takes, read as the sheet shows, and as its page
    /// changes them.
    @State private var taken: Int?

    /// The row, which a list can scroll to.
    static let row = "mods"

    var body: some View {
        Section {
            NavigationLink {
                CartoucheModsView(game: game, isRunning: isRunning, taken: $taken)
            } label: {
                LabeledContent {
                    Text(taken.map { $0 == 0 ? CartoucheText.modsNone : CartoucheText.modsOn($0) } ?? "")
                } label: {
                    Label(CartoucheText.modsTitle, systemImage: "puzzlepiece.extension")
                }
            }
            .id(Self.row)
        }
        .task(id: game.target?.documents) {
            guard let documents = game.target?.documents else {
                taken = 0
                return
            }
            taken = await Task.detached(priority: .utility) {
                CartoucheMods.load(in: documents).filter(\.isTaken).count
            }.value
        }
    }
}

// MARK: The page

@available(iOS 17.0, *)
struct CartoucheModsView: View {
    let game: CartoucheSwitchSaveGame
    let isRunning: Bool
    /// How many the game takes, for the sheet's row.
    @Binding var taken: Int?

    @State private var mods: [CartoucheMod] = []
    @State private var loaded = false
    @State private var choosing = false
    @State private var working = false
    /// What the last add brought: how many, and whether the one that came
    /// is on.
    @State private var added: (count: Int, on: Bool)?
    /// Why what was picked, or a switch, did not go through: a sentence for
    /// each.
    @State private var refusals: [String] = []
    /// Why the last step failed, and the report on it.
    @State private var failure: CartoucheReport?
    @State private var deleting: CartoucheMod?
    /// The game's Documents, once made for a mod that came before its
    /// first start.
    @State private var made: URL?

    #if CARTOUCHE_GALLERY
    /// What the gallery picks as the page opens, for its screenshot.
    static var galleryPick: (() async -> URL?)?
    #endif

    init(game: CartoucheSwitchSaveGame, isRunning: Bool, taken: Binding<Int?> = .constant(nil)) {
        self.game = game
        self.isRunning = isRunning
        self._taken = taken
    }

    private var documents: URL? { made ?? game.target?.documents }

    /// The game's title IDs, its regions' too: a mod of any is the game's.
    private var titleIds: [String] {
        guard let titleId = game.titleId, !titleId.isEmpty else { return [] }
        return CartoucheCatalog.shared.game(titleId: titleId)?.titleIds ?? [titleId]
    }

    private var isBusy: Bool { isRunning || working }

    var body: some View {
        List {
            addSection
            if added != nil || !refusals.isEmpty || failure != nil {
                outcomeSection
            }
            if loaded {
                modsSection
            }
        }
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.modsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .cartoucheConsolePage(CartoucheText.modsTitle)
        #endif
        .overlay {
            if working {
                ProgressView()
                    .controlSize(.large)
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip, .folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await add(url) }
        }
        .confirmationDialog(CartoucheText.modsDeleteQuestion, isPresented: Binding(get: { deleting != nil },
                                                                                set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { mod in
            Button(CartoucheText.modsDelete, role: .destructive) {
                Task { await delete(mod) }
            }
            Button(CartoucheText.cancel, role: .cancel) {}
        } message: { _ in
            Text(CartoucheText.modsDeleteMessage)
        }
        .task {
            await look()
            #if CARTOUCHE_GALLERY
            if let pick = Self.galleryPick, let url = await pick() { await add(url) }
            #endif
        }
    }

    // MARK: Sections

    private var addSection: some View {
        Section {
            Text(CartoucheText.modsIntro)
            Button {
                choosing = true
            } label: {
                Label(CartoucheText.modsAdd, systemImage: "plus.circle")
            }
            .disabled(isBusy)
            if isRunning {
                Text(CartoucheText.modsRunning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outcomeSection: some View {
        Section {
            if let added {
                Label(added.count == 1 && added.on ? CartoucheText.modsAddedOne : CartoucheText.modsAddedMany(added.count),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            }
            ForEach(refusals, id: \.self) { refusal in
                Label(refusal, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
            }
            if let failure {
                Label(failure.title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                CartoucheReportButton(report: failure)
            }
        }
    }

    private var modsSection: some View {
        CartoucheSection {
            if mods.isEmpty {
                Text(CartoucheText.modsEmpty)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(mods.enumerated()), id: \.element.id) { index, mod in
                row(mod, at: index)
            }
        } footer: {
            if !mods.isEmpty {
                Text(CartoucheText.modsOrderFooter)
            }
        }
    }

    private func row(_ mod: CartoucheMod, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: mod.name)
                        .lineLimit(2)
                    Text(CartoucheText.modsFiles(mod.files, CartoucheText.fileSize(mod.size)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    Button {
                        Task { await move(mod, by: -1) }
                    } label: {
                        Label(CartoucheText.modsMoveUp, systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        Task { await move(mod, by: 1) }
                    } label: {
                        Label(CartoucheText.modsMoveDown, systemImage: "arrow.down")
                    }
                    .disabled(index == mods.count - 1)
                    Button(role: .destructive) {
                        deleting = mod
                    } label: {
                        Label(CartoucheText.modsDelete, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .disabled(isBusy)
                Toggle(isOn: Binding(get: { mod.isTaken }, set: { on in Task { await turn(mod, on: on) } })) {
                    Text(verbatim: mod.name)
                }
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.switch)
                #endif
                .disabled(isBusy || mod.problem != nil)
            }
            if let problem = mod.problem {
                Label(Self.text(of: problem), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            } else if let version = mod.gameVersion, let current = game.version, version != current {
                Label(CartoucheText.modsOtherVersion(version), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Steps

    /// Reads the game's mods again, off the main thread: a folder copied in
    /// by hand is counted file by file.
    private func look() async {
        guard let documents else {
            mods = []
            loaded = true
            taken = 0
            return
        }
        show(await Task.detached(priority: .userInitiated) { CartoucheMods.load(in: documents) }.value)
    }

    private func show(_ mods: [CartoucheMod]) {
        self.mods = mods
        loaded = true
        taken = min(mods.filter(\.isTaken).count, CartoucheMods.mostOn)
    }

    private func clear() {
        added = nil
        refusals = []
        failure = nil
    }

    /// Adds the mods in URL, the folder or the ZIP the player picked: the
    /// only one that came turned on, several turned off.
    private func add(_ url: URL) async {
        clear()
        guard !game.isRunningNow() else {
            refusals = [CartoucheText.modsRunning]
            return
        }
        working = true
        defer { working = false }
        if documents == nil { made = game.makeTarget()?.documents }
        guard let documents else {
            refusals = [CartoucheText.modsAddFailed]
            return
        }
        let titleIds = titleIds
        let version = game.version
        let roomForOne = mods.filter(\.isTaken).count < CartoucheMods.mostOn
        do {
            let (pick, came) = try await Task.detached(priority: .userInitiated) { () -> (CartoucheModPick, [CartoucheMod]) in
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let pick = try await CartoucheMods.read(url, titleIds: titleIds)
                let needed = pick.found.reduce(UInt64(0)) { $0 + $1.size }
                if let free = CartoucheFreeSpace.forImportantUsage(at: documents), free >= 0, UInt64(free) < needed {
                    throw NoRoom(needed: needed, free: UInt64(free))
                }
                let came = try await CartoucheMods.add(pick.found, of: pick, to: documents,
                                                       on: pick.found.count == 1 && roomForOne, gameVersion: version)
                return (pick, came)
            }.value
            added = (came.count, came.first?.isOn ?? false)
            refusals = pick.refused.map { CartoucheText.modsNotAdded($0.name, Self.text(of: $0.problem)) }
            CartoucheReports.note("Mods of " + game.name + ": " + String(came.count) + " added from a "
                                  + (pick.isArchive ? "ZIP" : "folder") + Self.refusedNote(pick.refused.map(\.problem)))
        } catch let problem as CartoucheModProblem {
            refusals = [Self.text(of: problem)]
            CartoucheReports.note("Mod for " + game.name + " refused:" + Self.refusedNote([problem]))
        } catch is CartoucheZipError {
            refusals = [CartoucheText.modsUnreadable]
            CartoucheReports.note("Mod for " + game.name + ": not an archive Cartouche can read")
        } catch let room as NoRoom {
            refusals = [CartoucheText.modsNoRoom(CartoucheText.fileSize(room.needed), CartoucheText.fileSize(room.free))]
            CartoucheReports.note("Mod for " + game.name + ": no room, " + CartoucheReport.bytes(Int64(clamping: room.needed))
                                  + " needed, " + CartoucheReport.bytes(Int64(clamping: room.free)) + " free")
        } catch {
            failure = CartoucheReports.make(.mods, CartoucheText.modsAddFailed, message: error.localizedDescription,
                                            error: error, step: "Adding a mod to " + game.name, stage: "modAdd")
        }
        await look()
    }

    private func turn(_ mod: CartoucheMod, on: Bool) async {
        await change(CartoucheText.modsChangeFailed, step: "Turning a mod of " + game.name + (on ? " on" : " off"),
                     stage: "modTurn") { documents in
            try CartoucheMods.turn(mod.folder, on: on, in: documents)
        }
    }

    private func move(_ mod: CartoucheMod, by offset: Int) async {
        await change(CartoucheText.modsChangeFailed, step: "Moving a mod of " + game.name, stage: "modMove") { documents in
            try CartoucheMods.move(mod.folder, by: offset, in: documents)
        }
    }

    private func delete(_ mod: CartoucheMod) async {
        deleting = nil
        await change(CartoucheText.modsDeleteFailed, step: "Deleting a mod of " + game.name, stage: "modDelete") { documents in
            try CartoucheMods.delete(mod.folder, in: documents)
        }
    }

    /// Makes a change to the game's mods, off the main thread, unless the
    /// game runs: what stops it said, what fails reported as TITLE.
    private func change(_ title: String, step: String, stage: String,
                        _ work: @escaping @Sendable (URL) throws -> [CartoucheMod]) async {
        clear()
        guard let documents else { return }
        guard !game.isRunningNow() else {
            refusals = [CartoucheText.modsRunning]
            return
        }
        working = true
        defer { working = false }
        do {
            show(try await Task.detached(priority: .userInitiated) { try work(documents) }.value)
        } catch is CartoucheModsFull {
            refusals = [CartoucheText.modsTooMany(CartoucheMods.mostOn)]
        } catch let problem as CartoucheModProblem {
            refusals = [Self.text(of: problem)]
        } catch {
            failure = CartoucheReports.make(.mods, title, message: error.localizedDescription, error: error, step: step,
                                            stage: stage)
            await look()
        }
    }

    /// The problems of the mods that did not come, for the journal: their
    /// kinds, never their names.
    private static func refusedNote(_ problems: [CartoucheModProblem]) -> String {
        guard !problems.isEmpty else { return "" }
        return "; refused: " + problems.map { problem -> String in
            switch problem {
            case .noRomfs: return "no romfs"
            case .empty: return "empty"
            case .code: return "code"
            case .otherGame(let titleId): return "another game, " + titleId
            case .unsafe: return "a link or a path out of it"
            }
        }.joined(separator: ", ")
    }

    /// What the player reads of PROBLEM.
    static func text(of problem: CartoucheModProblem) -> String {
        switch problem {
        case .noRomfs: return CartoucheText.modsNoRomfs
        case .empty: return CartoucheText.modsEmptyRomfs
        case .code: return CartoucheText.modsCode
        case .otherGame(let titleId):
            return CartoucheText.modsOtherGame(CartoucheCatalog.shared.game(titleId: titleId)?.name ?? titleId)
        case .unsafe: return CartoucheText.modsUnsafe
        }
    }
}

/// The mods picked need more room than the disk has.
private struct NoRoom: Error {
    let needed: UInt64
    let free: UInt64
}
