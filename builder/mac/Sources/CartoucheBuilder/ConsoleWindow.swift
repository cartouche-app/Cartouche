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
    /// The console with every game open, as the gallery shows it.
    var showingLibrary = false

    var body: some View {
        Group {
            switch model.interface {
            case .console:
                CartoucheMacConsoleView(showingLibrary: showingLibrary)
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
        console.onUninstall = { [weak model] game in model?.askToRemove(app: game) }
        speak()
    }

    /// The games built for this Mac, by their apps.
    static func show(games: [URL]) {
        CartoucheMacConsole.shared.show(games: games)
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

    /// The app's language, which the console speaks too.
    static func speak() {
        CartoucheMacConsole.shared.speak(L10n.code)
    }
}
