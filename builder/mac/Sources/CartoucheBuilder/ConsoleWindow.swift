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
//  whose names it shares: this one, ConsoleGallery.swift and NamingHelp.swift.
//  The rest of the app reaches it through ConsoleLink, with the games' apps
//  and words.
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
    /// game of that title ID, and a page of its saves or its log, or its
    /// System page, or the Storage, Game measurements or Report a problem
    /// page that one opens, or the guide to a first game on this Mac, as
    /// the gallery shows it.
    var showingLibrary = false
    var showingSettings = false
    var showingInfo = false
    var showingSheetOf: String?
    var showingSaves: ConsoleSavesPage?
    var showingSystem = false
    var showingStorage = false
    var showingMeasures = false
    var showingReport = false
    var showingGuide = false
    /// The builder's Builds page with what the batch said open, as the
    /// gallery shows it.
    var showingDetails = false
    /// The Mac's appearance, light or dark: the builder's.
    @State private var macScheme = MainView.scheme(of: NSApplication.shared.effectiveAppearance)

    var body: some View {
        Group {
            switch model.interface {
            case .console:
                CartoucheMacConsoleView(showingLibrary: showingLibrary, showingSettings: showingSettings, showingInfo: showingInfo,
                                        showingSheetOf: showingSheetOf, showingSaves: showingSaves?.console,
                                        showingSystem: showingSystem, showingStorage: showingStorage,
                                        showingMeasures: showingMeasures, showingReport: showingReport,
                                        showingGuide: showingGuide)
                    .overlay(alignment: .top) { consoleBanner }
            case .builder:
                ContentView(showingDetails: showingDetails)
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
            Button(tr("Build anyway", "Construire quand même", "Compilar de todos modos", "Trotzdem erstellen")) { model.build(ask.games, force: ask.force, confirmed: true) }
            if !ask.others.isEmpty {
                Button(tr("Build only the others", "Construire seulement les autres", "Compilar solo los demás", "Nur die anderen erstellen")) { model.build(ask.others, force: ask.force, confirmed: true) }
            }
            Button(tr("Cancel", "Annuler", "Cancelar", "Abbrechen"), role: .cancel) {}
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
        // A game installed from the NAS, or from the iPhone's games folder,
        // how far it is, over the console.
        .onChange(of: model.installing) { _, _ in showInstall() }
        .onChange(of: model.installMessage) { _, _ in showInstall() }
    }

    private func showInstall() {
        let name = model.installing.map { model.installingName ?? model.game($0)?.name ?? $0 }
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

/// A page the console opens over a game's sheet, for the gallery
/// (Gallery.swift, which does not import the console): the copies of the
/// game's saves, its Switch saves, its log, or its mods.
enum ConsoleSavesPage {
    case copies, switchSaves, log, mods

    var console: CartoucheMacSavesPage {
        switch self {
        case .copies: return .copies
        case .switchSaves: return .switchSaves
        case .log: return .log
        case .mods: return .mods
        }
    }
}

/// Console | Builder, at the top of the window.
struct InterfaceSwitch: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Picker(tr("Show", "Afficher", "Mostrar", "Zeigen"), selection: Binding(get: { model.interface }, set: { model.show($0) })) {
            ForEach(AppInterface.allCases) { interface in
                Text(interface.title).tag(interface)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(tr("Cartouche’s console, or the builder (⌘1, ⌘2)", "La console de Cartouche, ou le Builder (⌘1, ⌘2)", "La consola de Cartouche, o el Builder (⌘1, ⌘2)", "Die Konsole von Cartouche oder der Builder (⌘1, ⌘2)"))
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
        console.onPause = { [weak model] game in model?.pauseForController(app: game) }
        console.onImport = { [weak model] in model?.showBuilder(.library) }
        console.onSystem = { [weak model] in model?.showBuilder(nil) }
        // This Mac's folders, on the console's Storage page: the Builder's
        // iPhone page shows them, the saves folder changed there.
        console.onFolders = { [weak model] in model?.showBuilder(.iphone) }
        console.onUninstall = { [weak model] game in model?.askToRemove(app: game) }
        console.onInstall = { [weak model] titleID in model?.install(titleID: titleID) }
        // The iPhone's games folder, on the Storage page: Send now.
        console.onSendGames = { [weak model] in model?.iPhoneGames.round() }
        // The games folders or the saves folder, chosen on the Storage page
        // on one of the connections, as JSON from the console's copy of the
        // type to CartoucheCore's (AppModel).
        console.onChangeFolders = { [weak model] change in model?.changeFolders(change) }
        // The first step of the console's guide to a first game on this Mac:
        // the setup assistant, over the console, and whether it was gone
        // through, at once and at each change.
        console.onSetup = { [weak model] in model?.openSetup() }
        setupWatch = model.$config
            .map { $0?.setupDone ?? false }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { CartoucheMacConsole.shared.isSetUp = $0 }
        startSaves(model)
        startMeasures(model)
        startUpdates(model.updater)
        startIPhoneGames(model.iPhoneGames)
        speak()
    }

    private static var setupWatch: AnyCancellable?

    // MARK: The iPhone's games folder

    /// The iPhone's games folder, on a connection, as the Builder sends its
    /// games there, on the console's Storage page: at once and at each
    /// change, the file going a few times a second at most.
    private static func startIPhoneGames(_ games: IPhoneGames) {
        CartoucheMacConsole.shared.showIPhoneGames(folder(of: games))
        gamesWatch = games.objectWillChange
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak games] _ in
                guard let games else { return }
                CartoucheMacConsole.shared.showIPhoneGames(folder(of: games))
            }
    }

    private static var gamesWatch: AnyCancellable?

    /// GAMES' folder as the Storage page shows it: the file going, why none
    /// goes, or how many went.
    static func folder(of games: IPhoneGames) -> CartoucheMacGamesFolder? {
        guard let folder = games.folder else { return nil }
        let state: CartoucheMacGamesFolder.State
        if let going = games.progress {
            state = .sending(game: going.game, packing: going.packing, done: going.done, total: going.total,
                             index: going.index, count: going.count)
        } else if let stopped = games.stopped {
            switch stopped {
            case .offline: state = .offline
            case .readOnly: state = .readOnly
            case let .noRoom(needed, free): state = .noRoom(needed: needed, free: free)
            }
        } else if let failure = games.failure {
            state = .failed(failure)
        } else if games.lastRound != nil {
            state = .sent(games.sentCount, of: games.total)
        } else {
            state = .waiting
        }
        let others = games.others.map { other in
            CartoucheMacGamesFolder.Other(connection: other.folder.connection, path: other.folder.path, offline: other.offline,
                                          offers: other.offers)
        }
        return CartoucheMacGamesFolder(connection: folder.connection, path: folder.path, state: state, offers: games.offersInFirst,
                                       others: others)
    }

    // MARK: Updates

    /// The Builder's updates, on the console's System page as in its
    /// settings: what the updater has, at once and at each change, and the
    /// buttons it answers.
    private static func startUpdates(_ updater: Updater) {
        let updates = CartoucheMacUpdates.shared
        updates.version = updater.current
        updates.enabled = updater.enabled
        updates.onCheck = { [weak updater] in Task { await updater?.check(force: true) } }
        updates.onDownload = { [weak updater] in
            guard let updater, case let .available(release) = updater.state else { return }
            Task { await updater.download(release) }
        }
        updates.onRestart = { [weak updater] in Task { await updater?.install(relaunch: true) } }
        updates.onAutomatic = { [weak updater] on in updater?.automatic = on }
        updatesWatch = updater.$state.combineLatest(updater.$checked, updater.$automatic)
            .receive(on: DispatchQueue.main)
            .sink { state, checked, automatic in
                updates.phase = ConsoleLink.phase(of: state)
                updates.notes = ConsoleLink.release(of: state)?.page
                updates.checked = checked
                updates.automatic = automatic
            }
    }

    private static var updatesWatch: AnyCancellable?

    static func phase(of state: Updater.State) -> CartoucheMacUpdates.Phase {
        switch state {
        case .idle: return .idle
        case .upToDate: return .upToDate
        case .checking: return .checking
        case let .available(release): return .available(release.version)
        case let .downloading(release): return .downloading(release.version)
        case let .ready(release): return .ready(release.version)
        case .installing: return .installing
        case let .failed(message): return .failed(message)
        }
    }

    private static func release(of state: Updater.State) -> BuilderRelease? {
        switch state {
        case let .available(release), let .downloading(release), let .ready(release): return release
        default: return nil
        }
    }

    // MARK: Game measurements

    /// The app's telemetry, as the console's System › Game measurements
    /// shows it and turns it, the console's events, and the reports of the
    /// sessions of the games played on this Mac, which the console reads in
    /// their logs: one switch, one queue and one number for the app.
    private static func startMeasures(_ model: AppModel) {
        let console = CartoucheMacConsole.shared
        let telemetry = model.telemetry
        CartoucheMacConsole.measuresServer = telemetry.hasServer ? BuilderTelemetry.bundledEndpoint : nil
        console.onMeasuresSwitch = { [weak telemetry] on in telemetry?.setOn(on) }
        console.onMeasuresErase = { [weak telemetry] in
            guard let telemetry else { return false }
            return await telemetry.erase()
        }
        console.onMeasuresEvent = { [weak telemetry] name, game, fields in
            telemetry?.event(name, game: game, fields: fields.mapValues(ConsoleLink.value))
        }
        console.onMeasuresReport = { [weak telemetry] make in
            telemetry?.report { context, seq in
                make(CartoucheMacTelemetryContext(install: context.install, version: context.cartouche, device: context.device,
                                                  system: context.ios, language: context.language,
                                                  deviceLanguage: context.deviceLanguage), seq)
                    .map { (id: $0.id, body: $0.body) }
            }
        }
        // At once, so that the first sessions read know the switch, then
        // each change, once it is made: the values in place.
        showMeasures(of: telemetry)
        measuresWatch = telemetry.$isOn.combineLatest(telemetry.$sent, telemetry.$waiting, telemetry.$lastSent)
            .combineLatest(telemetry.$lastReport)
            .receive(on: DispatchQueue.main)
            .sink { [weak telemetry] _ in
                guard let telemetry else { return }
                ConsoleLink.showMeasures(of: telemetry)
            }
        console.keepSessions(in: model.home.sessions)
    }

    private static var measuresWatch: AnyCancellable?

    private static func showMeasures(of telemetry: BuilderTelemetry) {
        CartoucheMacConsole.shared.showMeasures(
            CartoucheMacMeasures(isOn: telemetry.isOn, sent: telemetry.sent, waiting: telemetry.waiting,
                                 lastSent: telemetry.lastSent, lastReport: telemetry.lastReport))
    }

    /// A field of a console's event, as the app's telemetry sends it.
    private static func value(_ measure: CartoucheMacMeasure) -> TelemetryValue {
        switch measure {
        case .text(let text): return .text(text)
        case .number(let number): return .number(number)
        case .flag(let flag): return .flag(flag)
        }
    }

    /// Has the console read the sessions of the games played on this Mac
    /// that it has not read yet, and the app send their reports: PLAYING,
    /// the games playing, by title ID, still write theirs.
    static func readSessions(playing: Set<String>) {
        CartoucheMacConsole.shared.readSessions(playing: playing)
    }

    // MARK: The player's storage

    /// Keeps the passwords, secret keys and Google sign-ins of the
    /// connections of the console's Storage page in FILE from now on
    /// (BuilderHome.connections): once, as the app starts, before the
    /// bridge takes a paired iPhone's.
    static func keepConnections(in file: URL) {
        CartoucheMacConsole.keepConnectionSecrets(in: file)
    }

    // MARK: Reports

    /// Keeps the console's journal and its last reports in FOLDER from now
    /// on (BuilderHome.console): once, as the app starts.
    static func keepReports(in folder: URL) {
        CartoucheMacConsole.keepReports(in: folder)
    }

    /// Takes THEIRS, a paired iPhone's connections as JSON, and gives this
    /// Mac's once it took them, the same JSON (BridgeController): nil for
    /// what is no list of connections.
    static func takeConnections(_ theirs: Data) -> Data? {
        CartoucheMacConsole.shared.takeConnections(theirs)
    }

    /// The connection the folders an iPhone chose on the connection ID are
    /// on now, the one it was replaced by: nil when it was removed, or this
    /// Mac does not have it.
    static func currentConnection(_ id: UUID) -> UUID? {
        CartoucheMacConsole.shared.currentConnection(id)
    }

    /// The name the player gave the connection ID.
    static func connectionName(_ id: UUID) -> String? {
        CartoucheMacConsole.shared.connectionName(id)
    }

    /// The connection ID's kind, for the measurements: smb, s3, ftp, sftp
    /// or drive.
    static func connectionKind(_ id: UUID) -> String? {
        CartoucheMacConsole.shared.connectionKind(id)
    }

    /// ACTION, a moment after each change the player makes to their
    /// connections on the console's Storage page: once, as the app starts.
    static func followConnections(_ action: @escaping () -> Void) {
        connectionsWatch = CartoucheMacConsole.shared.connectionsChanged
            .receive(on: DispatchQueue.main)
            .sink { _ in action() }
    }

    private static var connectionsWatch: AnyCancellable?

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
        ownSaves = model.home.saves
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
    /// The folder the builder keeps the saves in when the player chose
    /// none, in its own (BuilderHome.saves).
    private static var ownSaves: URL?

    /// The saves of the games played on this Mac, as their sheets show
    /// them, and the saves folder, named in the app's language.
    private static func showSaves(of games: MacGames) {
        savesOf = games
        // Away: it was not there when last tried, and has not been since.
        let away = games.last.values.filter(\.offline).map(\.at).max().map { offline in
            games.checked.values.max().map { offline > $0 } ?? true
        } ?? false
        let folder = games.folder.map { folder in
            // The iPhone's, on a connection: by the connection's name.
            if let connection = folder.connection {
                return CartoucheMacSavesFolder(name: CartoucheMacConsole.shared.connectionName(connection)
                                                   ?? tr("the saves folder", "le dossier des sauvegardes", "la carpeta de partidas guardadas", "der Spielstandordner"),
                                               path: folder.path, isAway: away, connection: connection)
            }
            // The builder's own, which it took by itself: the saves are on
            // this Mac alone, and the console's home offers a saves folder.
            let builders = ownSaves.map { $0.standardizedFileURL.path == URL(fileURLWithPath: folder.path).standardizedFileURL.path } ?? false
            return CartoucheMacSavesFolder(name: folder.path.hasPrefix("/Volumes/") ? tr("the NAS", "le NAS", "el NAS", "das NAS")
                                               : tr("the saves folder", "le dossier des sauvegardes", "la carpeta de partidas guardadas", "der Spielstandordner"),
                                           path: folder.path, isAway: away, isBuilders: builders)
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
                    ? event?.failure ?? tr("Its saves could not be kept in step.", "Ses sauvegardes n’ont pas pu être mises en phase.", "Sus partidas guardadas no se pudieron sincronizar.", "Seine Spielstände konnten nicht abgeglichen werden.")
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

    /// The games built for this Mac, by their apps, KEPT, the games the
    /// games folder keeps in one file (a NAS's) and has not installed on
    /// this Mac, and OFFERS, the Mac apps another Mac sent to the iPhone's
    /// games folder, in PLACE, the app's words for where they are.
    static func show(games: [URL], kept: [Game], offers: [ConnectionMacApp] = [], keptIn place: String) {
        var keptGames = kept.compactMap { game -> CartoucheMacKeptGame? in
            guard let file = game.mac?.library else { return nil }
            return CartoucheMacKeptGame(titleID: game.titleID, name: game.name, file: file.path, size: file.size,
                                        built: game.mac?.build.flatMap { ISODate.parse($0.builtAt) })
        }
        keptGames += offers.map { offer in
            CartoucheMacKeptGame(titleID: offer.titleID, name: offer.game, file: offer.file.name, size: offer.file.size,
                                 built: offer.file.modified)
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
