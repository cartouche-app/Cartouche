//
//  CartoucheGameSheetView.swift
//  Cartouche
//
//  A game's sheet. On top, its cover, name and badges, and its main action:
//  Play for the player's own copy, with Game settings and, when the games
//  folder holds a newer build, Update beside it, or Resume, with Quit, for
//  the game paused behind the console; Install from the player's
//  games folder for a copy there; or Import my copy. Under them, its
//  description, the player's or IGDB's (CartoucheGameSummaryView), the time
//  the player played it and the space it takes (CartoucheGameStats), what
//  stops the game on this iPhone, if anything (what it needs folds into
//  one line when this iPhone has it all; in the console on the Mac, an
//  Apple chip and the macOS of the game's app in place of an iOS and
//  Increased Memory Limit), its build on the player's Mac,
//  with the button that asks the Mac for one, the one that stops it, and
//  the way to all the Mac's builds, once Cartouche reaches the Mac and its
//  Cartouche Builder knows the game (CartoucheMacBuildsView),
//  the copies of its saves, its mods (CartoucheModsView), Edit
//  the game's info for the player's own game (CartoucheGameInfoView), with
//  what IGDB has of a game Cartouche does not know, after which the sheet
//  goes back to its top, where the name and cover show; for a game installed
//  on the iPhone, Siri and Home Screen (CartoucheGameShortcutsView); the
//  game's copy in the games folder, its log to share (CartoucheGameLogView)
//  and Uninstall, the testers' results, in Cartouche's language
//  (CartoucheGameResultsView), and last, folded, the technical details: the
//  recommended settings, what nxnative's profile says and which build is
//  installed.
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheGameSheetView: View {
    let entry: CartoucheEntry
    let memory: CartoucheMemoryReading?
    let onPlay: (LCAppModel) -> Void
    /// Opens the game's settings page.
    let onSettings: (LCAppModel) -> Void
    /// Opens Files. The view that presents the sheet holds the one file
    /// importer of its presentation: SwiftUI presents only one of several.
    let onImport: () -> Void
    /// Asks whether to uninstall the game, and whether its saves stay.
    let onUninstall: (LCAppModel) -> Void
    /// Installs the game's IPA from the player's games folder.
    var onInstallStored: (CartoucheStoredGame) -> Void = { _ in }
    /// Installs the game Cartouche Cloud built for the player.
    var onInstallCloud: (CartoucheCloudBuilt) -> Void = { _ in }
    /// Copies the installed game to the player's games folder.
    var onExport: (LCAppModel) -> Void = { _ in }
    /// Opens what the player says of their game: its name, platform, genre
    /// and cover.
    var onEditInfo: () -> Void = {}
    /// Opens Siri and Home Screen, for the installed game.
    var onShortcuts: (LCAppModel) -> Void = { _ in }
    /// Opens the guide, beside Import my copy: given while the player has
    /// no game, who may have no IPA to import.
    var onGuide: (() -> Void)?
    /// Whether the sheet opens on the game's management, near its bottom,
    /// rather than on its top: for the gallery's screens of it.
    var opensOnManagement = false
    @ObservedObject private var actions = CartoucheGameActions.shared
    @ObservedObject private var keeping = CartoucheGameKeeping.shared
    @ObservedObject private var reach = CartoucheStorageReach.shared
    #if os(iOS)
    /// The player's Mac, asked its builds while the sheet shows: on the
    /// Mac, the console is the app that builds, and its window shows them.
    @StateObject private var macBuilds = CartoucheMacBuildsWatch()
    #endif
    /// Whether the line that says this iPhone has what the game needs is
    /// open on each need: as the player opens it, or, in the gallery, as
    /// its scenario of those needs does (category: requirements).
    @State private var requirementsOpen: Bool = {
        #if CARTOUCHE_GALLERY
        return GalleryState.sheetSection == "requirements"
        #else
        return false
        #endif
    }()

    // Written out: the private state above would make the synthesized
    // initializer private.
    init(entry: CartoucheEntry, memory: CartoucheMemoryReading?, onPlay: @escaping (LCAppModel) -> Void,
         onSettings: @escaping (LCAppModel) -> Void, onImport: @escaping () -> Void,
         onUninstall: @escaping (LCAppModel) -> Void,
         onInstallStored: @escaping (CartoucheStoredGame) -> Void = { _ in },
         onInstallCloud: @escaping (CartoucheCloudBuilt) -> Void = { _ in },
         onExport: @escaping (LCAppModel) -> Void = { _ in },
         onEditInfo: @escaping () -> Void = {},
         onShortcuts: @escaping (LCAppModel) -> Void = { _ in },
         onGuide: (() -> Void)? = nil,
         opensOnManagement: Bool = false) {
        self.entry = entry
        self.memory = memory
        self.onPlay = onPlay
        self.onSettings = onSettings
        self.onImport = onImport
        self.onUninstall = onUninstall
        self.onInstallStored = onInstallStored
        self.onInstallCloud = onInstallCloud
        self.onExport = onExport
        self.onEditInfo = onEditInfo
        self.onShortcuts = onShortcuts
        self.onGuide = onGuide
        self.opensOnManagement = opensOnManagement
    }

    /// The memory the game has here, where Play starts it: behind the
    /// console, iOS may give it more than Cartouche's own limit; in
    /// Cartouche's place, Cartouche's own, as Game Mode raises it a moment
    /// after Cartouche comes to the front (CartoucheGameKeeping.placeLimitMiB).
    private var gameLimitMiB: Int? {
        keeping.gameLimitMiB(ownLimitMiB: memory?.limitMiB)
    }

    private var fit: CartoucheFit? {
        entry.sheet.map { CartoucheFit.of($0, limitMiB: gameLimitMiB, convertsBCTextures: entry.convertsBCTextures) }
    }

    /// The game's copy in the games folders, the one offered, of the
    /// update first: on a server that answers, of a game in several.
    private var storedCopy: CartoucheStoredGame? { entry.update ?? entry.stored }

    /// The name of the server of the copy offered.
    private var serverName: String {
        CartoucheStoredGames.shared.place(of: storedCopy)
    }

    /// Whether the server of the copy offered does not answer from here,
    /// nor any other copy's.
    private var isGamesFolderOffline: Bool {
        storedCopy?.isOffline ?? false
    }

    /// Whether that server is a Google Drive whose sign-in Google ended:
    /// the player signs in again, rather than waits.
    private var isGamesFolderSignedOut: Bool {
        storedCopy.map { CartoucheStoredGames.shared.isSignedOut($0) } ?? false
    }

    /// The other games folders' servers that hold the game too, each with
    /// whether it answers, as a line: "Also in the NAS (offline)."
    private var alsoIn: String? {
        guard let copy = storedCopy else { return nil }
        let stored = CartoucheStoredGames.shared
        var seen: Set<String> = [stored.place(of: copy)]
        let others = stored.copies(of: copy).dropFirst().compactMap { other -> String? in
            let name = stored.place(of: other)
            guard seen.insert(name).inserted else { return nil }
            return other.isOffline ? CartoucheText.storedAlsoInOffline(name) : name
        }
        return others.isEmpty ? nil : CartoucheText.storedAlsoIn(others)
    }

    /// The header's row, which the sheet goes back to when what the player
    /// says of the game changes.
    private static let top = "top"
    /// The last row of the game's management.
    private static let management = "management"

    #if os(iOS)
    /// The game's title IDs, as the player's Mac may know it: its regions',
    /// and those its copies say.
    private var macTitleIds: [String] {
        var seen = Set<String>()
        let ids = (entry.game?.titleIds ?? []) + [entry.titleId, entry.ownTitleId, entry.stored?.titleId].compactMap { $0 }
        return ids.filter { seen.insert($0.uppercased()).inserted }
    }
    #endif

    #if CARTOUCHE_GALLERY
    /// How the gallery brings the sheet down to its saves, for their
    /// screenshot, given SwiftUI's scroll to the row of the Switch saves.
    static var galleryToSaves: ((@escaping @MainActor () -> Void) async -> Void)?
    #endif

    var body: some View {
        ScrollViewReader { reader in
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .id(Self.top)
                }

                if let summary = entry.summary {
                    Section {
                        CartoucheGameSummaryView(text: summary, isIGDBs: entry.player?.summary == nil)
                    }
                }

                CartoucheGameStatsSection(entry: entry)

                if let sheet = entry.sheet {
                    if let fit, !fit.reasons.isEmpty {
                        Section {
                            ForEach(fit.reasons, id: \.self) { reason in
                                Label(reason, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(fit.isPlayable ? Color.primary : Color.orange)
                            }
                        }
                    }
                    requirements(sheet)
                } else {
                    // nxnative refuses this GPU for every game, with a sheet or
                    // without, unless the player's build converts the
                    // game's textures for it.
                    if let fit = CartoucheFit.withoutSheet(convertsBCTextures: entry.convertsBCTextures) {
                        Section {
                            ForEach(fit.reasons, id: \.self) { reason in
                                Label(reason, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                            }
                        }
                    }
                    if entry.isOwned {
                        Section {
                            Text(CartoucheText.noSheetMessage)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                #if os(iOS)
                CartoucheMacBuildsSection(titleIds: macTitleIds, isOwned: entry.isOwned, watch: macBuilds)
                #endif

                // The game's saves, with its saves between the player's
                // Switch and this iPhone; on the Mac, those the Builder keeps
                // in step there (Mac/ConsoleSaves.swift).
                if let app = entry.app, let game = switchGame(of: app) {
                    CartoucheSavesSection(target: game.target, isRunning: actions.isRunning(app), switchGame: game)
                    // Its mods, kept with its saves (CartoucheModsView).
                    CartoucheModsSection(game: game, isRunning: actions.isRunning(app))
                }

                if entry.isOwned {
                    infoSection
                }

                // Siri and Home Screen start a game in the iPhone's console;
                // on the Mac, each game is an app of its own.
                #if os(iOS)
                if let app = entry.app {
                    shortcutsSection(app)
                }
                #endif

                if let app = entry.app {
                    manageSection(app)
                }

                if let sheet = entry.sheet, !sheet.results.isEmpty {
                    CartoucheGameResultsSection(results: sheet.results)
                }

                if hasDetails {
                    detailsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(CartoucheStage(key: entry.tileKey, art: entry.backdrop))
            #if os(iOS)
            .onAppear { macBuilds.start() }
            .onDisappear { macBuilds.stop() }
            #endif
            #if CARTOUCHE_GALLERY
            // The gallery's sheet on the game's build on the Mac (screen:
            // sheet-mac): the game's build in the middle of the screen.
            // Twice: the list had only guessed the heights of the rows on
            // the way, which the first scroll lays out, and the second lands
            // where asked.
            .task {
                guard CartoucheMacBuildsWatch.galleryScrolls else { return }
                for _ in 0..<2 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    reader.scrollTo(CartoucheMacBuildsSection.anchor, anchor: .center)
                }
            }
            #endif
            // What the player gave in Edit the game's info shows at once:
            // the sheet goes back to the game's name and cover.
            .onChange(of: entry.player) { _, _ in
                withAnimation { reader.scrollTo(Self.top, anchor: .top) }
            }
            // The gallery's screens of the game's management: the sheet goes
            // to it once it has its rows, and again whenever they change,
            // as the player's copy and IGDB's summary of the game arrive
            // after the sheet opens.
            .task(id: opensOnManagement ? Optional(entry) : nil) {
                guard opensOnManagement else { return }
                for delay in [300, 1_000] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { return }
                    reader.scrollTo(Self.management, anchor: .center)
                }
            }
            #if CARTOUCHE_GALLERY
            // The gallery's scenario of the testers' results opens the sheet
            // on them, from their title to the line under them: the middle
            // one in the middle, as a List scrolls a row to its top, its
            // middle or its bottom only. Again every half second until the
            // gallery says it has settled (3 s): the rows above take their
            // heights as they show, and moved the results down after a
            // single scroll (run 43553256663).
            .onAppear {
                guard GalleryState.sheetSection == "results",
                      let results = entry.sheet.map({ CartoucheGameResultsSection.ordered($0.results) }),
                      !results.isEmpty else { return }
                let middle = results[results.count / 2]
                for delay in stride(from: 0.5, through: 2.5, by: 0.5) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        reader.scrollTo(middle, anchor: .center)
                    }
                }
            }
            // The gallery's screenshot of the sheet's saves, further down,
            // once the game's saves are on the sheet.
            .task(id: entry.app != nil) {
                guard entry.app != nil, let toSaves = Self.galleryToSaves else { return }
                await toSaves { reader.scrollTo(CartoucheSavesSection.switchRow, anchor: .center) }
            }
            #endif
        }
        // The header names the game: the bar above it stays empty.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The game's saves, and the game, for its saves between the player's
    /// Switch and this iPhone; nil for an app that is not an nxnative game.
    private func switchGame(of app: LCAppModel) -> CartoucheSwitchSaveGame? {
        let target = actions.saves(of: app)
        guard target != nil || CartoucheCatalog.shared.gameTitle(of: app) != nil else { return nil }
        return CartoucheSwitchSaveGame(name: entry.name, titleId: target?.titleId ?? entry.titleId,
                                       version: CartoucheInstalledBuilds.installedBuild(of: app).version,
                                       isSwitch2: entry.platform == "switch2", target: target,
                                       makeTarget: { actions.savesToImport(of: app) },
                                       isRunningNow: { actions.isRunning(app) })
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                CartoucheGameCartridge(entry: entry, width: 104, isPaused: actions.isRunning(entry.app))
                    .padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    // For the player's own copy, the badge says whether it
                    // is ready, or what stops it; while the game runs
                    // behind the console, the line says it is paused.
                    let isRunning = actions.isRunning(entry.app)
                    CartoucheMetaLine(entry: entry, showsStatus: entry.app == nil || entry.sheet == nil || isRunning,
                                      isPaused: isRunning, wraps: true)
                    if entry.sheet != nil, !isRunning {
                        CartoucheFitBadge(fit: fit, owned: entry.app != nil)
                    }
                }
                // As tall as the title and its lines need, whatever the list
                // offers: a list row first offers each part of the header a
                // share of its height, less than the cartridge then gives it,
                // and under the badge of a game with a sheet, a long title
                // shrank to one line cut short, as Ocarina of Time's did.
                .fixedSize(horizontal: false, vertical: true)
            }

            if let app = entry.app, actions.isRunning(app) {
                primaryButton(CartoucheText.resume, systemImage: "play.fill") { onPlay(app) }
                HStack(spacing: 10) {
                    secondaryButton(CartoucheText.gameSettings, systemImage: "slider.horizontal.3") { onSettings(app) }
                    secondaryButton(CartoucheText.quit, systemImage: "stop.circle") { actions.askToQuit() }
                }
                buildLine(CartoucheText.pausedDetail, systemImage: "pause.circle")
            } else if let app = entry.app {
                primaryButton(CartoucheText.play, systemImage: "play.fill") { onPlay(app) }
                HStack(spacing: 10) {
                    secondaryButton(CartoucheText.gameSettings, systemImage: "slider.horizontal.3") { onSettings(app) }
                    if let update = entry.update {
                        secondaryButton(CartoucheText.updateGame, systemImage: "arrow.down.circle.fill") { onInstallStored(update) }
                    }
                }
                if entry.update != nil, isGamesFolderOffline {
                    if isGamesFolderSignedOut {
                        buildLine(CartoucheText.statusUpdateSignedOut(serverName), systemImage: "person.crop.circle.badge.exclamationmark")
                    } else {
                        buildLine(CartoucheText.statusUpdateOffline(serverName), systemImage: "wifi.slash")
                    }
                }
                if let update = entry.update, let build = update.build {
                    buildLine(CartoucheText.buildNewer(serverName, CartoucheText.build(build, showsCommit: false)),
                              systemImage: "arrow.down.circle")
                    if let installed = installedBuild(of: app, showsCommit: false) {
                        buildLine(CartoucheText.buildHere(installed), systemImage: CartoucheDevice.symbol)
                    }
                    if let alsoIn {
                        buildLine(alsoIn, systemImage: "externaldrive")
                    }
                }
            } else if let stored = entry.stored {
                primaryButton(CartoucheText.installFrom(serverName), systemImage: "arrow.down.circle.fill") { onInstallStored(stored) }
                secondaryButton(CartoucheText.importOtherCopy, systemImage: "square.and.arrow.down", action: onImport)
                if isGamesFolderOffline {
                    if isGamesFolderSignedOut {
                        buildLine(CartoucheText.statusStoredSignedOut(serverName), systemImage: "person.crop.circle.badge.exclamationmark")
                    } else {
                        buildLine(CartoucheText.statusStoredOffline(serverName), systemImage: "wifi.slash")
                    }
                }
                if let alsoIn {
                    buildLine(alsoIn, systemImage: "externaldrive")
                }
            } else if let cloud = entry.cloud {
                primaryButton(CartoucheText.cloudInstall, systemImage: "icloud.and.arrow.down.fill") { onInstallCloud(cloud) }
                secondaryButton(CartoucheText.importOtherCopy, systemImage: "square.and.arrow.down", action: onImport)
                buildLine(CartoucheText.cloudKeptUntil(CartoucheText.dateAndTime(cloud.expiresAt)), systemImage: "clock")
            } else {
                primaryButton(CartoucheText.importCopy, systemImage: "square.and.arrow.down", action: onImport)
                if let onGuide {
                    secondaryButton(CartoucheText.howToGetGame, systemImage: "questionmark.circle") {
                        CartoucheOffer.howToGetGame.tapped(at: .sheet)
                        onGuide()
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// The sheet's main action, white on Cartouche's indigo: a list would
    /// otherwise tint its symbol with the accent colour.
    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .controlSize(.large)
        .cartouchePrimaryButton()
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .controlSize(.regular)
        .cartoucheSecondaryButton()
    }

    private func buildLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(CartoucheTheme.secondaryText)
            .lineLimit(3)
    }

    /// Which build of the game is installed, in a few words: as the IPA
    /// Cartouche installed it from said, or, for a game installed before
    /// Cartouche kept that, its version, commit and install date.
    private func installedBuild(of app: LCAppModel, showsCommit: Bool = true) -> String? {
        if let recorded = CartoucheInstalledBuilds.shared.record(of: app) {
            return CartoucheText.build(recorded, showsCommit: showsCommit)
        }
        let build = CartoucheInstalledBuilds.installedBuild(of: app)
        let installedAt: Date? = app.appInfo.installationDate
        guard build.version != nil || build.commit != nil || installedAt != nil else { return nil }
        return CartoucheText.build(build, installedOn: installedAt, showsCommit: showsCommit)
    }

    // MARK: On this iPhone

    private struct Requirement: Hashable {
        let ok: Bool
        let title: String
        let detail: String
    }

    private func requirementList(_ sheet: CartoucheGameSheet) -> [Requirement] {
        #if os(iOS)
        var list = [Requirement(ok: CartoucheDevice.runsAtLeast(sheet.requirements.minimumIOS),
                                title: CartoucheText.iosRequirement(sheet.requirements.minimumIOS),
                                detail: CartoucheText.iosCurrent(CartoucheDevice.iOSVersion))]
        #else
        // On the Mac, the app nxnative built of the game for this Mac: an
        // Apple chip, which Cartouche there needs too, and the macOS its
        // Info.plist names.
        let minimum = entry.app?.appInfo.minimumSystemVersion ?? CartoucheDevice.macMinimum
        var list = [Requirement(ok: CartoucheDevice.runsAtLeast(minimum), title: CartoucheText.macRequirement(minimum),
                                detail: CartoucheText.macCurrent(CartoucheDevice.chip, CartoucheDevice.iOSVersion))]
        #endif
        if sheet.requirements.bcTextureCompression || !CartoucheDevice.supportsBCTextureCompression {
            // The player's build may convert the textures for a GPU that
            // reads none (CartoucheBCConversion): then it needs none.
            let reads = CartoucheDevice.supportsBCTextureCompression
            let converts = !reads && entry.convertsBCTextures
            list.append(Requirement(ok: reads || converts,
                                    title: CartoucheText.bcRequirement,
                                    detail: reads ? CartoucheText.gpuSupported
                                        : converts ? CartoucheText.gpuConverted : CartoucheText.gpuUnsupported))
        }
        // iOS's alone: a Mac gives a game its memory without it.
        #if os(iOS)
        if sheet.requirements.increasedMemoryLimit {
            // Cartouche's own, as a game in its place has it, once Game
            // Mode came (CartoucheGameKeeping.placeLimitMiB).
            let limit = keeping.placeLimitMiB(memory?.limitMiB).map { CartoucheText.memoryAmount(mebibytes: $0) } ?? "–"
            list.append(Requirement(ok: CartoucheDevice.hasIncreasedMemoryLimit,
                                    title: CartoucheText.imlRequirement,
                                    detail: CartoucheDevice.hasIncreasedMemoryLimit ? CartoucheText.imlActive(limit) : CartoucheText.imlInactive(limit)))
        }
        #endif
        if let peak = sheet.peakMemoryMiB {
            let fits = gameLimitMiB.map { peak <= $0 } ?? true
            list.append(Requirement(ok: fits,
                                    title: CartoucheText.memoryRequirement,
                                    detail: CartoucheText.memoryNeeded(CartoucheText.memoryAmount(mebibytes: peak))))
        }
        return list
    }

    /// What the game needs against what this iPhone has: one line that
    /// opens on the details when it has it all, each need otherwise.
    @ViewBuilder
    private func requirements(_ sheet: CartoucheGameSheet) -> some View {
        let list = requirementList(sheet)
        if list.allSatisfy(\.ok) {
            Section {
                DisclosureGroup(isExpanded: $requirementsOpen) {
                    ForEach(list, id: \.self) { requirement in
                        row(requirement)
                    }
                } label: {
                    Label {
                        Text(CartoucheText.requirementsMet)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    }
                }
            }
        } else {
            Section(CartoucheText.onThisIPhone) {
                ForEach(list, id: \.self) { requirement in
                    row(requirement)
                }
            }
        }
    }

    private func row(_ requirement: Requirement) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                Text(requirement.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: requirement.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(requirement.ok ? Color.green : Color.red)
        }
    }

    // MARK: The player's copy

    /// What the player says of their game; for a game Cartouche does not
    /// know, what IGDB has of it by its name, or that it has nothing yet.
    private var infoSection: some View {
        CartoucheSection {
            Button(action: onEditInfo) {
                Label(CartoucheText.gameInfoEdit, systemImage: "square.and.pencil")
            }
        } footer: {
            if entry.isUnknown, entry.playerCover == nil {
                Text(entry.found.map { CartoucheText.gameInfoFound($0.name) } ?? CartoucheText.gameInfoNotFound)
            }
        }
    }

    #if os(iOS)
    /// Siri and Home Screen: what to say to Siri, and how to give the game
    /// an icon of its own (CartoucheGameShortcutsView), on a page the
    /// console opens over the sheet, as the game's settings.
    private func shortcutsSection(_ app: LCAppModel) -> some View {
        Section {
            Button {
                onShortcuts(app)
            } label: {
                Label(CartoucheText.shortcutsTitle, systemImage: "mic.fill")
            }
        }
    }
    #endif

    /// Whether the game starts in Cartouche's place, for its own needs or
    /// because games behind the console run without Increased Memory Limit
    /// here, the game's copy in the games folder, or the button that copies
    /// it there, its log, once it wrote one, and Uninstall, last, in red.
    private func manageSection(_ app: LCAppModel) -> some View {
        Section {
            if keeping.keepsConsoleOpen, CartoucheGameKeeping.isAvailable,
               let bundleId = app.appInfo.bundleIdentifier() {
                if keeping.startsInPlace(bundleId: bundleId, ownLimitMiB: memory?.limitMiB) {
                    inPlaceNote(CartoucheText.startsInPlaceNote) {
                        keeping.startBehind(bundleId: bundleId)
                    }
                } else if keeping.sendsGamesInPlace(ownLimitMiB: memory?.limitMiB), let limit = keeping.limitMiB,
                          !keeping.fitsBehind(needsIML: entry.sheet?.requirements.increasedMemoryLimit ?? false,
                                              peakMiB: entry.sheet?.peakMemoryMiB, ownLimitMiB: memory?.limitMiB) {
                    inPlaceNote(CartoucheText.startsInPlaceWithoutIML(CartoucheText.memoryAmount(mebibytes: limit))) {
                        keeping.tryBehindAgain()
                    }
                }
            }
            if let stored = entry.stored {
                if entry.update == nil {
                    Label(CartoucheText.storedIn(serverName, stored.fileName), systemImage: "externaldrive.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if let alsoIn {
                        Label(alsoIn, systemImage: "externaldrive")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            } else if let server = CartoucheStorageSettings.shared.location(.games)?.server,
                      // A folder the player's account only reads takes no copy.
                      !CartoucheStorageSettings.shared.isReadOnly(.games) {
                Button {
                    onExport(app)
                } label: {
                    Label(CartoucheText.exportTo(server.name), systemImage: "externaldrive.fill.badge.plus")
                }
            }
            // What the game wrote of its last sessions, for whoever helps
            // the player: shared as it is, or sent to Cartouche cleaned; on
            // the Mac, the logs nxnative's app for the Mac writes.
            if let logs = actions.logs(of: app), !logs.files.isEmpty {
                NavigationLink {
                    CartoucheGameLogView(folder: logs, tileKey: entry.tileKey)
                } label: {
                    Label(CartoucheText.gameLogRow, systemImage: "doc.text")
                }
            }
            // Quit the game first.
            if !actions.isRunning(app) {
                Button(role: .destructive) {
                    onUninstall(app)
                } label: {
                    Label(CartoucheText.uninstall, systemImage: "trash")
                        .foregroundStyle(CartoucheTheme.danger)
                }
                .id(Self.management)
            }
        }
    }

    /// Why the game starts in Cartouche's place, and the button that tries
    /// behind the console again.
    private func inPlaceNote(_ text: String, tryAgain: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "rectangle.on.rectangle.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(CartoucheText.tryBehindAgain, action: tryAgain)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    // MARK: Technical details

    private var recommended: CartoucheGameSheet.Recommended? {
        guard let recommended = entry.sheet?.recommended,
              recommended.resolution != nil || recommended.mode != nil else { return nil }
        return recommended
    }

    private var hasDetails: Bool {
        recommended != nil || entry.game != nil || entry.app != nil
    }

    /// What players rarely need, folded: the recommended settings, what
    /// nxnative's profile says about the game, and the build installed.
    private var detailsSection: some View {
        Section {
            DisclosureGroup(CartoucheText.sheetDetails) {
                if let recommended {
                    if let resolution = recommended.resolution {
                        LabeledContent(CartoucheText.resolution, value: resolution)
                    }
                    if let mode = recommended.mode {
                        LabeledContent(CartoucheText.mode, value: CartoucheText.modeName(mode))
                    }
                }
                if let game = entry.game {
                    nxnative(game)
                }
                if let app = entry.app, let installed = installedBuild(of: app) {
                    Label(CartoucheText.buildHere(installed), systemImage: CartoucheDevice.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What nxnative's profile says about the game.
    @ViewBuilder
    private func nxnative(_ game: CartoucheNxGame) -> some View {
        // The player's copy says nothing of where nxnative plays the game.
        let status: CartouchePlayStatus = {
            let status = CartouchePlayStatus.of(entry)
            return status == .ready || status == .update || status == .stored || status == .cloud ? .iphone : status
        }()
        Label {
            Text(status.long)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
        }
        LabeledContent(CartoucheText.sheetEngine, value: game.engine)
        LabeledContent(CartoucheText.sheetBuild, value: game.build)
        LabeledContent(CartoucheText.sheetSDK, value: game.sdk)
        LabeledContent(CartoucheText.sheetTitleID) {
            Text(verbatim: game.titleId)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
        ForEach(game.variants ?? [], id: \.self) { variant in
            LabeledContent(CartoucheText.region(variant.region)) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: variant.titleId)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Text(variant.build)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
