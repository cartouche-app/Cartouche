//
//  ConsoleWindow.swift
//  Cartouche Builder
//
//  The window's two interfaces, Cartouche's console and the builder, and
//  the switch between them at the top of the window: the console the first
//  time, then the one the player chose last. ⌘1 and ⌘2 in the View menu,
//  and the menu bar's item, switch too; the console's System leads to the
//  builder, for a player with a controller.
//
//  The console is CartoucheConsole's, the iPhone's screens (ConsoleView.swift
//  there). It is imported only in files that do not import CartoucheCore,
//  whose names it shares: this one and ConsoleGallery.swift. The rest of the
//  app reaches it through ConsoleLink, with the games' apps and words.
//

import AppKit
import BuilderKit
import CartoucheConsole
import Combine
import SwiftUI

/// What the window shows.
enum AppInterface: String, CaseIterable, Identifiable {
    case console, builder

    var id: String { rawValue }

    /// The same word in both languages.
    var title: String {
        switch self {
        case .console: return "Console"
        case .builder: return "Builder"
        }
    }

    /// ⌘1, ⌘2.
    var shortcut: KeyEquivalent { self == .console ? "1" : "2" }
}

/// The window: the console or the builder, the switch above them, the
/// setup assistant over either.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: MacSetup
    @EnvironmentObject private var bridge: BridgeController
    /// The console with every game open, with its first game's settings
    /// page, or with that game's info over it, or with the sheet of the
    /// game of that title ID, and a page of its saves, or its System page,
    /// or the Storage page that one opens, as the gallery shows it.
    var showingLibrary = false
    var showingSettings = false
    var showingInfo = false
    var showingSheetOf: String?
    var showingSaves: ConsoleSavesPage?
    var showingSystem = false
    var showingStorage = false
    /// The Mac's appearance, light or dark: the builder's.
    @State private var macScheme = MainView.scheme(of: NSApplication.shared.effectiveAppearance)

    var body: some View {
        Group {
            switch model.interface {
            case .console:
                CartoucheMacConsoleView(showingLibrary: showingLibrary, showingSettings: showingSettings, showingInfo: showingInfo,
                                        showingSheetOf: showingSheetOf, showingSaves: showingSaves?.console,
                                        showingSystem: showingSystem, showingStorage: showingStorage)
                    .overlay(alignment: .top) { consoleBanner }
            case .builder:
                ContentView()
            }
        }
        // The switch stands where the window's title would.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                InterfaceSwitch()
            }
        }
        // The window dark while the console is in it, as the iPhone's
        // console always is, and in the Mac's appearance for the builder,
        // said every time, never left to nothing: when the console's dark
        // gave way to nothing, SwiftUI gave the window back the Mac's light
        // appearance but kept the builder in the console's colours, its
        // words white on white, until the window was drawn again (on a
        // player's Mac in light mode, 17 November; the layout check takes
        // the window to the console and back, LayoutCheck.swift).
        .preferredColorScheme(model.interface == .console ? .dark : macScheme)
        .onReceive(NSApplication.shared.publisher(for: \.effectiveAppearance)) { appearance in
            let scheme = MainView.scheme(of: appearance)
            if scheme != macScheme { macScheme = scheme }
        }
        .sheet(isPresented: $model.showSetup) {
            SetupAssistant(start: model.setupStep)
                .environmentObject(model)
                .environmentObject(setup)
                .environmentObject(bridge)
        }
        // A build that holds games no Mac built asks first (Unbuilt.swift),
        // over the console as over the builder: the menu bar builds from
        // either.
        .confirmationDialog(model.askUnbuilt?.title ?? "", isPresented: Binding(get: { model.askUnbuilt != nil }, set: { if !$0 { model.askUnbuilt = nil } }),
                            presenting: model.askUnbuilt) { ask in
            Button(tr("Build anyway", "Construire quand même")) { model.build(ask.games, force: ask.force, confirmed: true) }
            if !ask.others.isEmpty {
                Button(tr("Build only the others", "Construire seulement les autres")) { model.build(ask.others, force: ask.force, confirmed: true) }
            }
            Button(tr("Cancel", "Annuler"), role: .cancel) {}
        } message: { ask in
            Text(model.unbuiltMessage(ask))
        }
        // Back from the Finder, where a game may have gone into the dumps or
        // the games folder: it shows at once.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.playerCameBack()
        }
        // The game playing, as the console shows it, and whether it is in
        // front of the console or behind it.
        .onReceive(model.macGames.$playing) { playing in
            ConsoleLink.showRunning(playing)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            ConsoleLink.showRunning(model.macGames.playing)
        }
        // A game installed from the NAS, how far it is, over the console.
        .onChange(of: model.installing) { _, _ in showInstall() }
        .onChange(of: model.installMessage) { _, _ in showInstall() }
    }

    private func showInstall() {
        let name = model.installing.map { model.game($0)?.name ?? $0 }
        ConsoleLink.showInstall(name, step: model.installMessage)
    }

    /// Light or dark, as APPEARANCE is.
    private static func scheme(of appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    /// What went wrong, above the console as above the builder's pages: a
    /// game that did not start, or stopped unexpectedly.
    @ViewBuilder private var consoleBanner: some View {
        if let banner = model.banner {
            BannerView(banner: banner) { model.banner = nil }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 640)
                .padding(16)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// A page of a game's saves the console opens over its sheet, for the
/// gallery (Gallery.swift, which does not import the console): the copies
/// of the saves, or the game's Switch saves.
enum ConsoleSavesPage {
    case copies, switchSaves

    var console: CartoucheMacSavesPage {
        switch self {
        case .copies: return .copies
        case .switchSaves: return .switchSaves
        }
    }
}

/// Console | Builder, at the top of the window.
struct InterfaceSwitch: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Picker(tr("Show", "Afficher"), selection: Binding(get: { model.interface }, set: { model.show($0) })) {
            ForEach(AppInterface.allCases) { interface in
                Text(interface.title).tag(interface)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(tr("Cartouche’s console, or the builder (⌘1, ⌘2)", "La console de Cartouche, ou le Builder (⌘1, ⌘2)"))
    }
}

/// The console, as the rest of the app reaches it.
@MainActor
enum ConsoleLink {
    /// What the console's buttons do, and the words it speaks: once, as
    /// the app starts.
    static func start(_ model: AppModel) {
        let console = CartoucheMacConsole.shared
        console.onPlay = { [weak model] game, settings in model?.play(app: game, settings: settings) }
        console.onQuit = { [weak model] game in model?.askToQuit(app: game) }
        console.onImport = { [weak model] in model?.showBuilder(.library) }
        console.onSystem = { [weak model] in model?.showBuilder(nil) }
        // This Mac's folders, on the console's Storage page: the Builder's
        // iPhone page shows them, the saves folder changed there.
        console.onFolders = { [weak model] in model?.showBuilder(.iphone) }
        console.onUninstall = { [weak model] game in model?.askToRemove(app: game) }
        console.onInstall = { [weak model] titleID in model?.install(titleID: titleID) }
        startSaves(model)
        speak()
    }

    // MARK: The player's storage

    /// Keeps the passwords, secret keys and Google sign-ins of the
    /// connections of the console's Storage page in FILE from now on
    /// (BuilderHome.connections): once, as the app starts, before the
    /// bridge takes a paired iPhone's.
    static func keepConnections(in file: URL) {
        CartoucheMacConsole.keepConnectionSecrets(in: file)
    }

    /// Takes THEIRS, a paired iPhone's connections as JSON, and gives this
    /// Mac's once it took them, the same JSON (BridgeController): nil for
    /// what is no list of connections.
    static func takeConnections(_ theirs: Data) -> Data? {
        CartoucheMacConsole.shared.takeConnections(theirs)
    }

    /// The Builder's games folder and saves folder, which the console's
    /// Storage page shows under This Mac.
    static func showFolders(games: URL?, saves: URL?) {
        CartoucheMacConsole.shared.showFolders(games: games, saves: saves)
    }

    // MARK: A game's saves

    /// What the games' sheets ask of their saves on this Mac, which the
    /// builder keeps in step (MacGames), and what they show of them, from
    /// now on.
    private static func startSaves(_ model: AppModel) {
        let console = CartoucheMacConsole.shared
        // The gallery's console shows saves of its own, and keeps none.
        guard !model.sample else { return }
        let games = model.macGames
        console.onSyncSaves = { [weak games] titleID in
            guard let games else { return }
            do {
                if try await games.syncNow(titleID)?.offline == true { throw CartoucheMacSaveError.offline }
            } catch let error as MacSavesError {
                throw consoleError(error)
            }
        }
        console.onSaveCopies = { [weak games] titleID in
            guard let games else { return [] }
            do {
                return try await games.copies(titleID).map { CartoucheMacSaveCopy(name: $0.name, date: $0.date, size: $0.size) }
            } catch let error as MacSavesError {
                throw consoleError(error)
            }
        }
        console.onPutBackSave = { [weak games] name, titleID in
            guard let games else { throw CartoucheMacSaveError.offline }
            do {
                try await games.putBack(name, of: titleID)
            } catch let error as MacSavesError {
                throw consoleError(error)
            }
        }
        console.onChangeSaves = { [weak games] titleID, change in
            guard let games else { throw CartoucheMacSaveError.busy }
            do {
                return try await games.change(titleID) { _ in try change() }
            } catch let error as MacSavesError {
                throw consoleError(error)
            }
        }
        // Each change, once it is made: the values in place.
        savesWatch = games.$last.combineLatest(games.$checked, games.$folder, games.$cloud)
            .receive(on: DispatchQueue.main)
            .sink { [weak games] _ in
                guard let games else { return }
                showSaves(of: games)
            }
    }

    private static var savesWatch: AnyCancellable?
    private static weak var savesOf: MacGames?

    /// The saves of the games played on this Mac, as their sheets show
    /// them, and the saves folder, named in the app's language.
    private static func showSaves(of games: MacGames) {
        savesOf = games
        // Away: it was not there when last tried, and has not been since.
        let away = games.last.values.filter(\.offline).map(\.at).max().map { offline in
            games.checked.values.max().map { offline > $0 } ?? true
        } ?? false
        let folder = games.folder.map { folder in
            CartoucheMacSavesFolder(name: folder.root.path.hasPrefix("/Volumes/") ? tr("the NAS", "le NAS")
                                        : tr("the saves folder", "le dossier des sauvegardes"),
                                    path: folder.root.path, isAway: away)
        }
        var saves: [String: CartoucheMacGameSaves] = [:]
        for titleID in Set(games.last.keys).union(games.checked.keys).union(games.cloud.keys) {
            let event = games.last[titleID]
            let moved = event.flatMap { $0.offline || $0.failed ? nil : $0.at }
            let news = event.flatMap { ["fetch", "keep", "keepAndFetch"].contains($0.step) ? $0 : nil }
            // The newest copy waits for the game's update, the saves of
            // this Mac kept under it meanwhile, which that says.
            let held = event.flatMap { $0.step == MacSaveEvent.heldBack ? $0 : nil }
            saves[titleID] = CartoucheMacGameSaves(
                lastSync: [games.checked[titleID], moved].compactMap { $0 }.max(),
                fetched: news?.fetchedDate, kept: news?.keptDate, waiting: event?.offline == true,
                failure: event?.failed == true
                    ? event?.failure ?? tr("Its saves could not be kept in step.", "Ses sauvegardes n’ont pas pu être mises en phase.")
                    : nil,
                inCloud: games.cloud[titleID] != nil, newer: held?.newer, game: held?.game)
        }
        CartoucheMacConsole.shared.showSaves(folder: folder, games: saves)
    }

    /// What the builder says when it did not do what the console asked.
    private static func consoleError(_ error: MacSavesError) -> CartoucheMacSaveError {
        switch error {
        case .offline: return .offline
        case .busy: return .busy
        case .unreadable: return .unreadable
        case .newerGame(let copy, let game): return .newerGame(copy: copy, game: game)
        }
    }

    /// The games built for this Mac, by their apps, and KEPT, the games
    /// the games folder keeps in one file (a NAS's) and has not installed
    /// on this Mac, in PLACE, the app's words for where they are.
    static func show(games: [URL], kept: [Game], keptIn place: String) {
        let keptGames = kept.compactMap { game -> CartoucheMacKeptGame? in
            guard let file = game.mac?.library else { return nil }
            return CartoucheMacKeptGame(titleID: game.titleID, name: game.name, file: file.path, size: file.size,
                                        built: game.mac?.build.flatMap { ISODate.parse($0.builtAt) })
        }
        CartoucheMacConsole.shared.show(games: games, kept: keptGames, keptIn: place)
    }

    /// The game NAME being installed on this Mac, at STEP; nil once it is.
    static func showInstall(_ name: String?, step: String) {
        CartoucheMacConsole.shared.showInstall(name, step: step)
    }

    /// Of the games PLAYING, the one started last, and whether its app is
    /// the Mac's active one.
    static func showRunning(_ playing: [String: MacGameRun]) {
        let run = playing.values.max { $0.started < $1.started }
        let front = NSWorkspace.shared.frontmostApplication
        let inFront = run.map { run in
            front?.processIdentifier == run.pid
                || front?.bundleURL?.standardizedFileURL.path == run.app.url.standardizedFileURL.path
        } ?? false
        CartoucheMacConsole.shared.showRunning(run?.app.url, inFront: inFront)
    }

    /// The app's language, which the console speaks too, the saves
    /// folder's name with it.
    static func speak() {
        CartoucheMacConsole.shared.speak(L10n.code)
        if let games = savesOf { showSaves(of: games) }
    }
}
