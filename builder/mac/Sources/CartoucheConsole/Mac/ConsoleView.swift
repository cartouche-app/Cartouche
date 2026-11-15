//
//  ConsoleView.swift
//  Cartouche on the Mac
//
//  Cartouche's console on the Mac: its home and every game, with the sheet
//  of the game in focus beside them, as the iPhone Duo unfolded shows them
//  (launcher/Sources/CartoucheGamesView.swift). The screens are the
//  iPhone's own (Shared/); the app gives the console the games nxnative
//  built for this Mac, by their apps, and those its games folder keeps on
//  a NAS without having installed them here, as the iPhone's console knows
//  the IPAs of its games folder; it does what the player asks of them:
//  Play starts a game's app, Install installs a game from the NAS, how far
//  it is over the console, Import and System lead to the app's own pages.
//  Game settings opens the game's settings page in place of its sheet, the
//  way back to the sheet above it, where the controller's L and R change
//  the category and B goes back, as on the iPhone; the page's last button
//  starts the game on nxnative's settings window. The game's info, its
//  name, platform, genre, summary and cover, opens over the console.
//
//  This is the console's only public part: the app imports it in one file,
//  so that its names never meet those of the launcher's other library,
//  CartoucheCore, which shares some of its files.
//

import SwiftUI

/// A game the Builder keeps for this Mac in its games folder, in one file
/// on a NAS, and has not installed on this Mac: the console shows it as the
/// iPhone's shows an IPA of its games folder, with Install.
public struct CartoucheMacKeptGame: Equatable, Sendable {
    public let titleID: String
    public let name: String
    /// Its file in the games folder.
    public let file: String
    public let size: UInt64
    /// When it was built.
    public let built: Date?

    public init(titleID: String, name: String, file: String, size: UInt64, built: Date?) {
        self.titleID = titleID
        self.name = name
        self.file = file
        self.size = size
        self.built = built
    }
}

/// The console's games, and what the app does for it.
@MainActor
public final class CartoucheMacConsole: ObservableObject {
    public static let shared = CartoucheMacConsole()

    /// The games' apps, as the console's screens know a game.
    @Published private(set) var apps: [LCAppModel] = []
    private var models: [String: LCAppModel] = [:]
    /// The games the Builder keeps for this Mac and has not installed here,
    /// as the console's screens know an IPA of the games folder.
    @Published private(set) var stored: [CartoucheStoredGame] = []

    /// Starts the game's app, on nxnative's settings window first when
    /// SHOWINGSETTINGS, or brings it to the front if it runs.
    public var onPlay: (_ game: URL, _ showingSettings: Bool) -> Void = { _, _ in }
    /// Asks the running game's app to quit.
    public var onQuit: (_ game: URL) -> Void = { _ in }
    /// Import, on the home or the sheet of a game the player has no copy
    /// of: the Builder adds games.
    public var onImport: () -> Void = {}
    /// System, on the home's dock.
    public var onSystem: () -> Void = {}
    /// Removes the game from this Mac; the app asks the player first.
    public var onUninstall: (_ game: URL) -> Void = { _ in }
    /// Install, on a game the Builder keeps on a NAS: the app installs it
    /// on this Mac, by its title ID (showInstall says how far it is).
    public var onInstall: (_ titleID: String) -> Void = { _ in }
    /// Whether the console asks Cartouche's server for newer covers and
    /// for what IGDB has of the games it does not know, as the iPhone's
    /// does: not for the app's gallery, which shows the covers it carries.
    public var asksServer = true

    /// Whether the games' settings pages keep the player's choices in
    /// memory, reading none of the games' preferences and writing none:
    /// the app's gallery's.
    public var keepsChoicesInMemory: Bool {
        get { CartoucheGameActions.shared.keepsChoicesInMemory }
        set { CartoucheGameActions.shared.keepsChoicesInMemory = newValue }
    }

    private init() {
        CartoucheGameActions.shared.onQuit = { [weak self] app in self?.onQuit(app.appInfo.url) }
    }

    /// Where nxnative's apps keep each game's data on this Mac, its saves
    /// among them: ~/Library/Application Support/nxnative/<title ID>.
    public var dataFolder: URL {
        get { CartoucheGameActions.shared.dataRoot }
        set { CartoucheGameActions.shared.dataRoot = newValue }
    }

    /// The play time and the size on this Mac, of the app and of its data,
    /// of the games the app's gallery shows, by title ID, in place of what
    /// the console reads and measures: from then on, nothing of the
    /// player's is read again or kept.
    public func showForGallery(playTimes: [String: CartouchePlayTime], sizes: [String: (app: UInt64, data: UInt64)]) {
        func bundleID(_ titleID: String) -> String { "org.nxnative." + titleID.lowercased() }
        CartoucheGameStats.shared.showForGallery(
            sizes: Dictionary(uniqueKeysWithValues: sizes.map { (bundleID($0.key), CartoucheGameSize(bundle: $0.value.app, data: $0.value.data)) }),
            playTimes: Dictionary(uniqueKeysWithValues: playTimes.map { (bundleID($0.key), $0.value) }))
    }

    /// The games built for this Mac, by their apps, and KEPT, those the
    /// Builder keeps in its games folder and has not installed here, in
    /// PLACE, the app's words for where they are ("the NAS"). A game the
    /// console showed already stays the same game, its focus and its sheet
    /// with it.
    public func show(games: [URL], kept keptGames: [CartoucheMacKeptGame] = [], keptIn place: String = "") {
        var kept: [String: LCAppModel] = [:]
        var shown: [LCAppModel] = []
        for url in games {
            let key = url.standardizedFileURL.path
            guard kept[key] == nil else { continue }
            let model = models[key] ?? LCAppModel(appInfo: LCAppInfo(url: url))
            kept[key] = model
            shown.append(model)
        }
        models = kept
        apps = shown
        if let running = CartoucheGameActions.shared.running, !shown.contains(where: { $0 === running.app }) {
            CartoucheGameActions.shared.running = nil
        }
        // As Cartouche on the iPhone reads them from an IPA's Info.plist.
        let stored = keptGames.map { game in
            CartoucheStoredGame(path: game.file, size: game.size, modified: game.built,
                                bundleId: "org.nxnative." + game.titleID.lowercased(), displayName: game.name,
                                titleId: game.titleID.uppercased(), isGame: true)
        }
        if stored != self.stored { self.stored = stored }
        let folder = CartoucheStoredGames.shared
        if folder.games != stored || folder.serverName != place {
            folder.showForMac(stored, server: place)
        }
    }

    /// Install, on a game of the games folder.
    func install(_ game: CartoucheStoredGame) {
        guard let titleID = game.titleId else { return }
        onInstall(titleID)
    }

    /// The game NAME the app installs on this Mac, at STEP, in its words,
    /// over the console as the iPhone shows an install; nil once it is over.
    public func showInstall(_ name: String?, step: String) {
        let actions = CartoucheGameActions.shared
        guard let name else {
            if actions.work != nil { actions.work = nil }
            return
        }
        if var work = actions.work, work.kind == .installing, work.name == name {
            work.step = step
            if work != actions.work { actions.work = work }
        } else {
            actions.work = CartoucheGameWork(kind: .installing, name: name, step: step,
                                             place: CartoucheStoredGames.shared.serverName)
        }
    }

    /// The game whose app runs, if one of the console's does, and whether
    /// it is the Mac's active app.
    public func showRunning(_ game: URL?, inFront: Bool) {
        let actions = CartoucheGameActions.shared
        guard let game, let app = models[game.standardizedFileURL.path] else {
            actions.running = nil
            return
        }
        if let running = actions.running, running.app === app {
            if running.isInFront != inFront { actions.running?.isInFront = inFront }
        } else {
            actions.running = CartoucheRunningGame(app: app, started: Date(), isInFront: inFront)
        }
    }

    /// The language the console speaks, as the app's settings choose it:
    /// "fr" or "en", or nil for the Mac's.
    @Published public private(set) var language: String?

    /// Speaks LANGUAGE from now on, "fr" or "en", or the Mac's language for
    /// nil: the console's words change at once, as the app's do.
    public func speak(_ language: String?) {
        speak(language, from: Bundle.main.resourceURL)
    }

    /// Speaks LANGUAGE with the words in RESOURCES/Console/<language>, which
    /// holds that language alone (bundle.sh, console/strings.py), and names
    /// the games' languages in it.
    func speak(_ language: String?, from resources: URL?) {
        let chosen = language.flatMap { ["fr", "en"].contains($0) ? $0 : nil }
        let folder = chosen.flatMap { resources?.appendingPathComponent("Console/" + $0, isDirectory: true) }
        CartoucheText.bundle = folder.flatMap { Bundle(url: $0) } ?? Bundle(for: CartoucheCatalog.self)
        CartoucheText.locale = chosen.map { Locale(identifier: $0) } ?? Locale.current
        self.language = chosen
    }

    /// Loads the covers and artworks the console shows of its games, and
    /// of EVERYGAME's covers too: the gallery waits for them before it
    /// takes its pictures.
    public func loadCovers(everyGame: Bool) async {
        let entries = CartoucheCatalog.shared.entries(for: apps, stored: stored)
        var arts = entries.owned.flatMap { [$0.coverArt, $0.backdrop].compactMap { $0 } }
        if everyGame {
            arts += entries.others.compactMap(\.coverArt)
        }
        for art in arts {
            _ = await CartoucheCoverStore.shared.image(art)
        }
    }
}

/// The console: the home, or every game, and the sheet of the game in
/// focus beside it once the player has a game here.
public struct CartoucheMacConsoleView: View {
    @ObservedObject private var console = CartoucheMacConsole.shared
    @ObservedObject private var catalog = CartoucheCatalog.shared
    @ObservedObject private var actions = CartoucheGameActions.shared
    @State private var path: [Route]
    /// The game in focus, or the last one whose sheet opened: the game of
    /// the sheet beside the console.
    @State private var paneID: String?
    /// The settings page open in place of the sheet, and its game's ID.
    @State private var gameSettings: CartoucheGameSettingsModel?
    @State private var settingsID: String?
    /// The game whose info the player changes, over the console.
    @State private var editingInfo: CartoucheEntry?
    /// Whether the console opens on the settings page of its first game on
    /// this Mac, or with that game's info over it, or with the sheet of the
    /// game of that title ID beside it: the app's gallery's.
    private let opensSettings: Bool
    private let opensInfo: Bool
    private let opensSheetOf: String?
    @Namespace private var zoom

    enum Route: Hashable {
        case library
    }

    /// The console on its home, or with every game open (SHOWINGLIBRARY),
    /// or with the settings page of its first game on this Mac beside it
    /// (SHOWINGSETTINGS), or that game's info over it (SHOWINGINFO), or the
    /// sheet of the game of the title ID SHOWINGSHEETOF beside it, as the
    /// app's gallery shows it.
    public init(showingLibrary: Bool = false, showingSettings: Bool = false, showingInfo: Bool = false,
                showingSheetOf titleID: String? = nil) {
        _path = State(initialValue: showingLibrary ? [.library] : [])
        opensSettings = showingSettings
        opensInfo = showingInfo
        opensSheetOf = titleID
    }

    /// Nothing open beside the console or over it that takes the
    /// controller: the settings page, the game's info.
    private var nothingOver: Bool { gameSettings == nil && editingInfo == nil }

    public var body: some View {
        let entries = catalog.entries(for: console.apps, stored: console.stored)
        HStack(spacing: 0) {
            home(entries)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            // Before the player has a game here, nothing stands beside the
            // console, never a game they do not have.
            if let entry = paneEntry(in: entries) {
                gameSheet(entry)
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // A game the Builder installs from the NAS, over the console, as
        // the iPhone's shows an install.
        .overlay {
            if let work = actions.work {
                CartoucheGameWorkView(work: work)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: actions.work)
        // Another language: every word again.
        .id(console.language ?? "")
        .animation(.easeInOut(duration: 0.25), value: entries.owned.isEmpty)
        .preferredColorScheme(.dark)
        .onAppear {
            if let entry = entries.owned.first(where: { $0.app != nil }), let app = entry.app {
                if opensSettings { openSettings(app, of: entry) }
                if opensInfo { editingInfo = entry }
            }
            if let titleID = opensSheetOf, let entry = entries.owned.first(where: { $0.titleId == titleID }) {
                paneID = entry.id
            }
            guard console.asksServer else { return }
            catalog.refreshCoversIfDue()
            catalog.lookUpGamesIfDue(among: entries)
        }
        // A game added, removed or renamed: Cartouche asks its server about
        // those it does not know.
        .onChange(of: CartoucheCatalog.wanted(among: entries)) { _, _ in
            guard console.asksServer else { return }
            catalog.lookUpGamesIfDue(among: catalog.entries(for: console.apps, stored: console.stored))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            CartoucheGameStats.shared.cameBack(console.apps)
            guard console.asksServer else { return }
            catalog.refreshCoversIfDue()
        }
    }

    /// The home, and every game one step further.
    private func home(_ entries: CartoucheCatalog.Entries) -> some View {
        NavigationStack(path: $path) {
            CartoucheHomeView(
                entries: entries,
                gameCount: entries.all.count,
                isActive: path.isEmpty && nothingOver,
                onPlay: { play($0) },
                onImport: { console.onImport() },
                onInstall: { console.install($0) },
                onUninstall: { console.onUninstall($0.appInfo.url) },
                onSheet: { focus($0) },
                onLibrary: { path.append(.library) },
                onSetup: {},
                onTab: { tab in
                    if tab == .system { console.onSystem() }
                },
                zoom: path.isEmpty ? zoom : nil,
                // Beside the console, the sheet describes the game in focus.
                showsHero: entries.owned.isEmpty,
                focusing: opensSheetOf.flatMap { titleID in entries.owned.first { $0.titleId == titleID }?.id },
                onFocus: { item in
                    if case .game(let entry) = item { focus(entry) }
                })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .library:
                        CartoucheLibraryView(
                            entries: entries,
                            isActive: path.last == .library && nothingOver,
                            onPlay: { play($0) },
                            onSheet: { focus($0) },
                            onBack: { if !path.isEmpty { path.removeLast() } },
                            zoom: zoom,
                            onFocus: { focus($0) })
                    }
                }
        }
    }

    /// A game's sheet, beside the console, or its settings page in its
    /// place.
    private func gameSheet(_ entry: CartoucheEntry) -> some View {
        NavigationStack {
            if let settings = gameSettings, settingsID == entry.id {
                settingsPage(settings, of: entry)
            } else {
                CartoucheGameSheetView(
                    entry: entry,
                    memory: nil,
                    onPlay: { play($0) },
                    onSettings: { openSettings($0, of: entry) },
                    onImport: { console.onImport() },
                    onUninstall: { console.onUninstall($0.appInfo.url) },
                    onInstallStored: { console.install($0) },
                    onEditInfo: { editingInfo = entry })
                    .id(entry.id)
            }
        }
        // The settings page takes the controller: L and R change the
        // category, B goes back to the sheet.
        .onReceive(CartoucheGamepad.shared.inputs) { input in
            guard editingInfo == nil, let settings = gameSettings else { return }
            switch input {
            case .b: closeSettings()
            case .previous: settings.moveCategory(by: -1)
            case .next: settings.moveCategory(by: 1)
            default: break
            }
        }
        // What the player says of their game, over the console, which B
        // closes as Cancel does (CartoucheGameInfoView).
        .sheet(item: $editingInfo) { edited in
            NavigationStack {
                CartoucheGameInfoView(entry: edited) { editingInfo = nil }
            }
            .frame(minWidth: 520, idealWidth: 560, minHeight: 620, idealHeight: 700)
            .preferredColorScheme(.dark)
        }
    }

    /// A game's settings page, in place of its sheet: the way back to the
    /// sheet above it, which Escape takes too, and its switches as the
    /// iPhone's.
    private func settingsPage(_ settings: CartoucheGameSettingsModel, of entry: CartoucheEntry) -> some View {
        CartoucheGameSettingsView(model: settings) {
            if let app = entry.app { play(app, showingSettings: true) }
        }
        .toggleStyle(.switch)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text(CartoucheText.gameSettings)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Button(action: closeSettings) {
                        Label(CartoucheText.backToSheet, systemImage: "chevron.backward")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.bar)
        }
    }

    private func openSettings(_ app: LCAppModel, of entry: CartoucheEntry) {
        paneID = entry.id
        settingsID = entry.id
        gameSettings = actions.settings(for: app, tileKey: entry.tileKey)
    }

    private func closeSettings() {
        gameSettings = nil
        settingsID = nil
    }

    /// The game of the sheet beside the console: the game in focus, or the
    /// last whose sheet opened; before any, the player's first game.
    private func paneEntry(in entries: CartoucheCatalog.Entries) -> CartoucheEntry? {
        guard !entries.owned.isEmpty else { return nil }
        return entries.entry(id: paneID) ?? entries.owned.first
    }

    /// Another game in focus closes the settings page of the last; the
    /// gallery's pages of the settings and of a sheet stay as they opened.
    private func focus(_ entry: CartoucheEntry) {
        guard !opensSettings, opensSheetOf == nil else { return }
        if paneID != entry.id { closeSettings() }
        paneID = entry.id
    }

    /// Starts the game's app, or brings it back to the front.
    private func play(_ app: LCAppModel, showingSettings: Bool = false) {
        console.onPlay(app.appInfo.url, showingSettings)
    }
}
