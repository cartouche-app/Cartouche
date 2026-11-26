//
//  Gallery.swift
//  Cartouche Builder
//
//  Pictures of the app's pages with sample games, for the Builder workflow
//  and the docs: `Cartouche Builder --gallery FOLDER` saves each page as a
//  PNG, in French in light and dark, and in English, Spanish and German in
//  light, then ends.
//  Nothing runs: no engine, no check of the Mac, no server, and nothing of
//  the player's is read or kept. The games are real ones nxnative builds,
//  with their covers from IGDB as the app shows them; their folders, sizes
//  and builds are made up, as are the Mac's name and its iPhones. Each page
//  is a window of its own, taken as the window server shows it.
//

import AppKit
import BuilderKit
import CartoucheCore
import ScreenCaptureKit
import SwiftUI

@MainActor
enum Gallery {
    enum Page: String, CaseIterable {
        case library, game, gameNarrow = "game-narrow", gameQueue = "game-queue", activity, storage, iphone, setup, settings, menubar
        case menubarBuilding = "menubar-building"
        // What stops a build before it starts: too little room on the Mac,
        // an Xcode older than nxnative's, a game no Mac built yet.
        case libraryRoom = "library-room", gameXcode = "game-xcode", gameUnbuilt = "game-unbuilt", setupXcode = "setup-xcode"
        // A game's sheet whose newest copy of its saves waits for the
        // game's update, a newer version of the game having written it.
        case gameNewer = "game-newer"
        case assistantWelcome = "assistant-welcome", assistantTools = "assistant-tools", assistantSources = "assistant-sources"
        case assistantGames = "assistant-games", assistantKeys = "assistant-keys", assistantBuilds = "assistant-builds"
        case assistantIPhone = "assistant-iphone", assistantDone = "assistant-done"
        // The tools step, nxnative not downloaded yet, the choice of what
        // it downloads open under its row: an iPhone 15 chosen, whose GPU
        // reads no BC texture (BuildFor).
        case assistantToolsSource = "assistant-tools-source"
        // The settings' Folders tab, where the dumps folder and the games
        // folder are chosen; and the help on naming what they hold, as the
        // sheet it opens shows it, at its top and on the dumps folder, as
        // the library opens it.
        case settingsFolders = "settings-folders", names, namesDumps = "names-dumps"
        // Cartouche's console on this Mac (ConsoleGallery.swift): its home,
        // every game, a game's settings page beside them, a game's info over
        // them, and the whole sheet of a game played on this Mac, in a
        // window as tall as it, again with the newest copy of its saves
        // waiting for the game's update, a newer version having written it,
        // with the copies of its saves and its Switch saves, the pages its
        // saves open, and its log; its System page, and the Storage page
        // that one opens, with the player's connections, its Game
        // measurements page and its Report a problem page; the guide to a
        // first game on this Mac, and its card on the home, for a player
        // who has built games and played none yet.
        case console, consoleLibrary = "console-library", consoleSettings = "console-settings", consoleInfo = "console-info"
        case consoleSheet = "console-sheet", consoleSheetNewer = "console-sheet-newer"
        case consoleSaves = "console-saves", consoleSwitchSave = "console-switch-save", consoleGameLog = "console-game-log"
        case consoleSystem = "console-system", consoleStorage = "console-storage", consoleMeasures = "console-measures"
        case consoleReport = "console-report", consoleGuide = "console-guide", consoleFirstGame = "console-first-game"
        // What the window's height leaves out: the settings' Builds tab, and
        // the storage page down to the games on this Mac, in a window as
        // tall as it. The Builds tab again, an iPhone 15 paired in place of
        // the iPhone Duo: its GPU reads no BC texture, and the games are
        // built from nxnative-nobc, a separate fork (BuildFor).
        case settingsBuilds = "settings-builds", settingsBuildsNoBC = "settings-builds-no-bc", storageMac = "storage-mac"
        // The whole storage page of a player whose build folders are on
        // their NAS, which keeps them between two builds made on this Mac
        // (decision 163): one game building on this Mac, three waiting on
        // the NAS.
        case storageNAS = "storage-nas"
        // The iPhone page with Tailscale on this Mac, and its address there
        // (BridgeView.swift); the iPhone page above has it off.
        case iphoneTailscale = "iphone-tailscale"
        // The whole iPhone page, in a window as tall as it, the iPhone
        // connected now plugged into this Mac, by its cable
        // (BridgeCable.swift).
        case iphoneCable = "iphone-cable"
        // The whole iPhone page, in a window as tall as it, the iPhone
        // connected now reading a game on this Mac's 2.4 GHz Wi-Fi, at
        // 3.1 MB/s, with what would go faster (BridgeSendingWords, decision
        // 151).
        case iphoneSending = "iphone-sending"
        // The whole iPhone page, in a window as tall as it, down to the
        // iPhone's games folder on one of the player's connections, a NAS:
        // a game going there, and a Mac app another Mac sent
        // (IPhoneGames.swift).
        case iphoneGames = "iphone-games"
        // Cartouche renewed from this Mac (RenewalView.swift, decision
        // 165), the iPhone page above not signed in yet: signed in, the
        // iPhone 17 Pro by cable renewed two days ago, the iPhone Duo on
        // the Wi-Fi in its last two days, locked at the last try; and
        // signing in, Apple asking for its code, Cartouche expired on the
        // iPhone Duo; and, the certificate of both copies gone from the
        // account, Cartouche installed again over itself on the iPhone 17
        // Pro, where it expired, and Reinstall on the iPhone Duo, where it
        // still opens and its last install found the account full.
        case iphoneRenewal = "iphone-renewal", iphoneRenewalSignIn = "iphone-renewal-sign-in"
        case iphoneRenewalInstall = "iphone-renewal-install"
        // The game page of the builder in the window that showed the
        // console just before, the player back from it with the switch at
        // the top of the window: as the game page, whatever the Mac's
        // appearance.
        case gameAfterConsole = "game-after-console"
        // A game whose shaders nxnative's newest commit splits otherwise
        // than its profile says (decision 133), as Mario Kart World's since
        // nxnative's 8d62601f of 16 November 2026: built in a batch from
        // the commit before nxnative's splitter changed, alone, the other
        // games from the newest, with what the batch said open, in a window
        // as tall as the page; and its sheet once built, held there, down to
        // its build.
        case activitySplit = "activity-split", gameSplit = "game-split"

        /// Whether the page is the console's, which is always dark.
        var isConsole: Bool {
            [.console, .consoleLibrary, .consoleSettings, .consoleInfo, .consoleSheet, .consoleSheetNewer, .consoleSaves,
             .consoleSwitchSave, .consoleGameLog, .consoleSystem, .consoleStorage, .consoleMeasures, .consoleReport,
             .consoleGuide, .consoleFirstGame].contains(self)
        }

        /// Whether the page is a game's whole sheet, in a window as tall.
        var isWholeSheet: Bool { self == .consoleSheet || self == .consoleSheetNewer }

        /// Whether the page is in a window taller than the screen, as tall
        /// as the page, which AppKit would fit to the screen.
        var isTall: Bool {
            isWholeSheet || [.storageMac, .storageNAS, .iphoneGames, .iphoneCable, .iphoneSending, .consoleSystem, .consoleStorage, .consoleMeasures, .consoleReport,
                             .activitySplit, .gameSplit].contains(self)
        }

        /// The page of the sheet's saves it opens over the sheet.
        var savesPage: ConsoleSavesPage? {
            switch self {
            case .consoleSaves: return .copies
            case .consoleSwitchSave: return .switchSaves
            case .consoleGameLog: return .log
            default: return nil
            }
        }

        /// The setup assistant's step the page shows.
        var step: SetupStep? {
            switch self {
            case .assistantWelcome: return .welcome
            case .assistantTools, .assistantToolsSource: return .tools
            case .assistantSources: return .sources
            case .assistantGames: return .games
            case .assistantKeys: return .keys
            case .assistantBuilds: return .builds
            case .assistantIPhone: return .iphone
            case .assistantDone: return .done
            default: return nil
            }
        }

        var size: CGSize {
            if step != nil { return SetupAssistant.size }
            switch self {
            case .names, .namesDumps: return NamingHelp.size
            case .settings, .settingsBuilds, .settingsBuildsNoBC, .settingsFolders: return SettingsTab.size
            case .storageMac, .storageNAS: return CGSize(width: 1024, height: 1440)
            case .iphoneGames: return CGSize(width: 1024, height: 1500)
            // Down to the iPhone sending a game, and what would go faster.
            case .iphoneSending: return CGSize(width: 1024, height: 1000)
            case .consoleSheet, .consoleSheetNewer: return CGSize(width: 1024, height: 1640)
            // This Mac, the iPhone's games folders on a NAS and a Drive,
            // with the ways to change them, the saves folder to choose, and
            // every connection, down to the footer.
            case .consoleStorage: return CGSize(width: 1024, height: 1900)
            // What is sent, down to the way to erase it.
            case .consoleMeasures: return CGSize(width: 1024, height: 1180)
            // What the player writes, the ways to send it, and the report
            // down to its last steps.
            case .consoleReport: return CGSize(width: 1024, height: 1500)
            // The whole System page, down to Report a problem.
            case .consoleSystem: return CGSize(width: 1024, height: 980)
            // The game building, the games built, and what the batch said.
            case .activitySplit: return CGSize(width: 1024, height: 1060)
            // The sheet down to its build: why it is up to date, and the
            // commit it was built from.
            case .gameSplit: return CGSize(width: 1024, height: 1150)
            // The window at its smallest, with a game's sheet whose
            // nxnative commits are a paragraph each, as nxnative writes them.
            case .gameNarrow: return CGSize(width: Columns.window.width, height: 680)
            case .menubar, .menubarBuilding: return CGSize(width: 330, height: 0)
            default: return CGSize(width: 1220, height: 780)
            }
        }

        var inEnglish: Bool {
            [.library, .game, .gameQueue, .setup, .menubar, .assistantWelcome, .assistantGames, .console, .consoleStorage,
             .activitySplit, .gameSplit].contains(self)
        }

        /// The window as the app opens it: the settings as the Settings
        /// scene does, the menu bar's panel without a frame, the setup
        /// assistant as the sheet it is, without a title bar, which would
        /// add its height above it.
        var styleMask: NSWindow.StyleMask {
            if step != nil || isNaming { return [.borderless] }
            switch self {
            case .settings, .settingsBuilds, .settingsBuildsNoBC, .settingsFolders: return [.titled, .closable]
            case .menubar, .menubarBuilding: return [.borderless]
            default: return [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            }
        }

        /// Whether the page is the help on naming, the sheet it is.
        var isNaming: Bool { self == .names || self == .namesDumps }
    }

    /// Pictures AppKit drew itself, as ScreenCaptureKit could not take them.
    private static var drawnByAppKit = 0
    /// Pictures of a window in the background, as macOS kept the app
    /// inactive: its main buttons and its switches come out grey.
    private static var inBackground = 0
    /// A page takes a few seconds, its covers a minute at most: one still
    /// not taken after three ends the gallery, which says which, rather than
    /// hold the Mac until its job ends, as a window of macOS's waiting for
    /// an answer did once.
    private static let watchdog = GalleryWatchdog(limit: 180)

    static func run(into folder: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The bridge on and the menu bar item, for this run only.
        UserDefaults.standard.setVolatileDomain([AppSettings.bridgeKey: true, AppSettings.menuBarKey: true], forName: UserDefaults.argumentDomain)
        let samples: Samples
        do {
            samples = try Samples()
        } catch {
            FileHandle.standardError.write(Data("gallery: the samples do not decode: \(error)\n".utf8))
            exit(1)
        }
        loadCovers(samples.library.games.map(\.titleID) + [Gallery.unbuilt.titleID, Gallery.splitTitleID])
        var saved = 0
        for language in ["fr", "en", "es", "de"] {
            L10n.use(language)
            // The console speaks it too, as once the app read its settings
            // (AppModel): its words show in the builder's, as the help on
            // naming the games' title in the settings.
            ConsoleLink.speak()
            for page in Page.allCases where language == "fr" || page.inEnglish {
                for dark in page.isConsole ? [true] : language == "fr" ? [false, true] : [false] {
                    let file = folder.appendingPathComponent("\(page.rawValue)-\(language)-\(dark ? "dark" : "light").png")
                    watchdog.watch(file.lastPathComponent)
                    if render(page, samples: samples, dark: dark, to: file) { saved += 1 }
                }
            }
        }
        watchdog.watch(nil)
        ConsoleGallery.cleanUp()
        print("gallery: \(saved) pictures in \(folder.path)"
              + (drawnByAppKit > 0 ? ", \(drawnByAppKit) drawn by AppKit without the window server's effects" : "")
              + (inBackground > 0 ? ", \(inBackground) of a window in the background, its main buttons and switches grey" : ""))
        exit(saved > 0 ? 0 : 1)
    }

    /// The covers, downloaded before the pages are drawn.
    private static func loadCovers(_ titleIDs: [String]) {
        final class Done { var value = false }
        let done = Done()
        Task { @MainActor in
            for titleID in titleIDs { await CoverStore.shared.load(titleID) }
            done.value = true
        }
        wait(until: Date().addingTimeInterval(60)) { done.value }
    }

    private static func wait(until deadline: Date, _ finished: () -> Bool = { false }) {
        while !finished() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func render(_ page: Page, samples: Samples, dark: Bool, to file: URL) -> Bool {
        // The Mac in the page's mode, as the window: the builder's follows
        // the Mac's (MainView).
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let model = samples.model(for: page)
        var size = page.size
        let controller: NSViewController
        switch page {
        case .names, .namesDumps:
            // The sheet it is, as the setup assistant's steps are shown.
            controller = hosted(NamingHelp(onDumps: page == .namesDumps)
                                    .background(Color(nsColor: .windowBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)),
                                model, bridged: false)
        case .settingsFolders:
            controller = settings(model, open: .folders)
        case .settings, .settingsBuilds, .settingsBuildsNoBC:
            controller = settings(model, open: page == .settings ? .general : .builds)
        case .console, .consoleLibrary, .consoleSettings, .consoleInfo, .consoleSheet, .consoleSheetNewer, .consoleSaves, .consoleSwitchSave,
             .consoleGameLog, .consoleSystem, .consoleStorage, .consoleMeasures, .consoleReport, .consoleGuide, .consoleFirstGame:
            ConsoleGallery.prepare(language: L10n.code, newer: page == .consoleSheetNewer,
                                   firstGame: page == .consoleGuide || page == .consoleFirstGame)
            model.show(.console)
            let sheet = page.isWholeSheet || page.savesPage != nil
            controller = hosted(MainView(showingLibrary: page == .consoleLibrary, showingSettings: page == .consoleSettings,
                                         showingInfo: page == .consoleInfo,
                                         showingSheetOf: sheet ? ConsoleGallery.sheetGame : nil,
                                         showingSaves: page.savesPage,
                                         showingSystem: page == .consoleSystem, showingStorage: page == .consoleStorage,
                                         showingMeasures: page == .consoleMeasures, showingReport: page == .consoleReport,
                                         showingGuide: page == .consoleGuide), model)
        case .gameAfterConsole:
            // The console first, in the window, as the player had it.
            ConsoleGallery.prepare(language: L10n.code)
            model.show(.console)
            controller = hosted(MainView(), model)
        case .menubar, .menubarBuilding:
            let panel = hosted(MenuBarView().background(Color(nsColor: .windowBackgroundColor)), model)
            size.height = ceil(panel.sizeThatFits(in: CGSize(width: size.width, height: 2000)).height)
            controller = panel
        default:
            if let step = page.step {
                // The sheet it is: on the window's background, its corners
                // rounded.
                controller = hosted(SetupAssistant(start: step)
                                        .environment(\.showsBuildSource, page == .assistantToolsSource)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)),
                                    model, bridged: false)
            } else {
                // The window as the app shows it: the builder, below the
                // switch to the console.
                controller = hosted(MainView(showingDetails: page == .activitySplit), model)
            }
        }
        let frame = CGRect(origin: CGPoint(x: 80, y: 80), size: size)
        let window: NSWindow = page.isTall
            ? TallWindow(contentRect: frame, styleMask: page.styleMask, backing: .buffered, defer: false)
            : KeyWindow(contentRect: frame, styleMask: page.styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        switch page {
        case .settings: window.title = SettingsTab.general.title
        case .settingsBuilds, .settingsBuildsNoBC: window.title = SettingsTab.builds.title
        case .settingsFolders: window.title = SettingsTab.folders.title
        case _ where page.isConsole: window.title = "Cartouche"
        default: window.title = AppName.name
        }
        if [.settings, .settingsBuilds, .settingsBuildsNoBC, .settingsFolders].contains(page) {
            window.toolbarStyle = .preference
        }
        if page.step != nil || page.isNaming {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentViewController = controller
        window.setContentSize(size)
        // In front and, where macOS lets it, active, as the player sees the
        // app's window: an inactive window greys its main buttons and its
        // switches. activate() only asks, which macOS turns down to an app
        // nobody opened; on GitHub's runners, it keeps the gallery inactive
        // even so, and the last line says how many pictures show a window
        // in the background.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        wait(until: Date().addingTimeInterval(2.5))
        // Then the builder, the switch turned as the player turns it.
        if page == .gameAfterConsole {
            model.show(.builder)
            wait(until: Date().addingTimeInterval(2.5))
        }
        // A game's info opens over the console in a sheet, a window of its
        // own, which the window server shows with the console's window
        // under it, as one: the picture is as large as both.
        var shown: NSWindow = window
        var area: CGRect?
        if page == .consoleInfo {
            if let sheet = window.attachedSheet {
                shown = sheet
                area = window.frame.union(sheet.frame)
            } else {
                complain(file, "the game's info did not open over the console")
            }
        }
        if !(NSApp.isActive && shown.isKeyWindow) { inBackground += 1 }
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.orderOut(nil)
            window.close()
        }
        var picture = captured(shown, for: file, area: area)
        if picture == nil {
            drawnByAppKit += 1
            picture = drawn(shown)
        }
        guard let data = picture?.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: file)
            return true
        } catch {
            complain(file, "\(error)")
            return false
        }
    }

    /// A page with the app's models; its toolbar and its title become the
    /// window's, as in the app's window, unless the page is one of a tab
    /// view controller's.
    private static func hosted<Content: View>(_ content: Content, _ model: AppModel, bridged: Bool = true) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: AnyView(content
            .environmentObject(model)
            .environmentObject(model.setup)
            .environmentObject(model.bridge)
            .environmentObject(model.covers)
            .environmentObject(model.updater)
            .environmentObject(model.telemetry)
            .environment(\.locale, L10n.locale)))
        controller.sceneBridgingOptions = bridged ? [.toolbars, .title] : []
        return controller
    }

    /// The settings as the Settings scene shows them, which a TabView in a
    /// window of its own does not: a tab in the middle of the toolbar for
    /// each, OPEN open, its name as the window's title.
    private static func settings(_ model: AppModel, open: SettingsTab) -> NSViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let page = hosted(tab.content.frame(width: SettingsTab.size.width, height: SettingsTab.size.height), model, bridged: false)
            page.title = tab.title
            let item = NSTabViewItem(viewController: page)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: open) ?? 0
        return tabs
    }

    /// A window that becomes the key window, as the app's do, even without
    /// a title bar: the menu bar's panel and the setup assistant's sheet
    /// are, in the app.
    private class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    /// A window as tall as its page, which AppKit would fit to the screen,
    /// as it does the others on a screen smaller than they are.
    private final class TallWindow: KeyWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// The window as the window server shows it, with what only the window
    /// server draws: the sidebar's selection, the labels over the sidebar,
    /// the glass of the toolbar's buttons; AREA, in the screen's points,
    /// when the window server shows more than the window with it, as it
    /// shows a sheet with the window under it, which a picture of the
    /// window's size alone shrinks into a corner. Nil, said on standard
    /// error, when ScreenCaptureKit cannot take it.
    private static func captured(_ window: NSWindow, for file: URL, area: CGRect? = nil) -> NSBitmapImageRep? {
        final class Capture { var image: CGImage?; var done = false }
        let capture = Capture()
        let number = CGWindowID(window.windowNumber)
        Task { @MainActor in
            defer { capture.done = true }
            do {
                // The app's own windows, which need no permission to record
                // the screen.
                let content = try await SCShareableContent.currentProcess
                guard let shown = content.windows.first(where: { $0.windowID == number }) else {
                    Gallery.complain(file, "ScreenCaptureKit does not list the window")
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: shown)
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                let size = area?.size ?? filter.contentRect.size
                configuration.width = Int((size.width * scale).rounded())
                configuration.height = Int((size.height * scale).rounded())
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                // All of a window wider than the screen.
                configuration.ignoreGlobalClipSingleWindow = true
                capture.image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                Gallery.complain(file, "ScreenCaptureKit: \(error.localizedDescription)")
            }
        }
        wait(until: Date().addingTimeInterval(20)) { capture.done }
        return capture.image.map { NSBitmapImageRep(cgImage: $0) }
    }

    /// The window as AppKit draws it, without what the window server adds:
    /// the selection comes out black, and the labels over the sidebar faint.
    private static func drawn(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let drawn = window.contentView?.superview ?? window.contentView else { return nil }
        drawn.layoutSubtreeIfNeeded()
        guard let picture = drawn.bitmapImageRepForCachingDisplay(in: drawn.bounds) else { return nil }
        drawn.cacheDisplay(in: drawn.bounds, to: picture)
        return picture
    }

    private static func complain(_ file: URL, _ message: String) {
        FileHandle.standardError.write(Data("gallery: \(file.lastPathComponent): \(message)\n".utf8))
    }

    // MARK: The samples

    /// The engine's answers for a player with ten games on a NAS: two that
    /// nxnative improved, one that failed, one nxnative has no profile for,
    /// one there is only an IPA of.
    @MainActor
    struct Samples {
        let library: Library
        let building: BatchStatus
        let storage: StorageReport
        let nasStorage: StorageReport
        let config: BuilderConfig
        let info: BuilderInfo

        init() throws {
            let decoder = JSONDecoder()
            library = try decoder.decode(Library.self, from: Gallery.dated(Gallery.libraryJSON))
            building = try decoder.decode(BatchStatus.self, from: Gallery.dated(Gallery.buildingJSON))
            storage = try decoder.decode(StorageReport.self, from: Gallery.dated(Gallery.storageJSON))
            nasStorage = try decoder.decode(StorageReport.self, from: Gallery.dated(Gallery.storageNASJSON))
            config = try decoder.decode(BuilderConfig.self, from: Data(Gallery.configJSON.utf8))
            info = try decoder.decode(BuilderInfo.self, from: Data(Gallery.infoJSON.utf8))
        }

        func model(for page: Page) -> AppModel {
            let building = page == .activity || page == .menubarBuilding || page == .gameQueue
            var library = self.library
            library.issues = Gallery.issues
            if page == .gameNarrow, let index = library.games.firstIndex(where: { $0.titleID == "0100152000022000" }) {
                LayoutCheck.lengthen(&library.games[index])
            }
            if page == .libraryRoom {
                library.room = Gallery.room
            }
            // Kirby, skipped at its last build for the Mac's Xcode.
            if page == .gameXcode, let index = library.games.firstIndex(where: { $0.titleID == "01004D300C5AE000" }) {
                library.games[index].attempt = Gallery.metalAttempt
            }
            if page == .gameUnbuilt {
                library.games.append(Gallery.unbuilt)
            }
            // Mario Kart World, built from the commit before nxnative's
            // splitter changed: in the batch, Kirby building after it from
            // the newest.
            let split = page == .activitySplit
            if split || page == .gameSplit {
                library.games.append(Gallery.splitGame)
            }
            if split, let index = library.games.firstIndex(where: { $0.titleID == "01004D300C5AE000" }) {
                library.games[index].state = .building
            }
            if building {
                // The library as the engine gives it while the batch runs:
                // Kirby built in it, for the iPhone and this Mac, Mario Kart
                // 8 Deluxe building, Metroid Dread waiting its turn, Super
                // Mario Odyssey and Breath of the Wild, built for the iPhone
                // alone, asked for since (decision 127).
                let states: [String: GameState] = ["01004D300C5AE000": .upToDate, "0100152000022000": .building,
                                                   "010093801237C000": .queued, "0100000000010000": .queued,
                                                   "01007EF00011E000": .queued]
                for index in library.games.indices {
                    if let state = states[library.games[index].titleID] { library.games[index].state = state }
                }
            }
            var config = self.config
            if page == .assistantToolsSource { config.buildFor = "iPhone15,4" }
            if page == .storageNAS { config.workspace = "/Volumes/Jeux/Builds" }
            let model = AppModel.sampled(library: library, status: building ? self.building : split ? Gallery.splitBatch : nil,
                                         storage: page == .storageNAS ? nasStorage : storage, config: config, info: info,
                                         unbuilt: page == .gameUnbuilt ? [Gallery.unbuilt.titleID: Gallery.unbuiltFigures] : [:])
            if building {
                model.preview(queue: BuildQueue(games: [.init(titleID: "0100000000010000", force: true, batch: 4242, added: ""),
                                                        .init(titleID: "01007EF00011E000", force: true, batch: 4242, added: "")]))
            }
            switch page {
            case .library, .activity, .storage, .iphone: model.section = AppSection(rawValue: page.rawValue) ?? .library
            case .storageMac, .storageNAS: model.section = .storage
            case .activitySplit: model.section = .activity
            case .iphoneTailscale, .iphoneGames, .iphoneCable, .iphoneSending, .iphoneRenewal, .iphoneRenewalSignIn, .iphoneRenewalInstall:
                model.section = .iphone
            case .libraryRoom, .game, .gameNarrow, .gameNewer, .gameQueue, .gameXcode, .gameUnbuilt, .gameAfterConsole, .gameSplit:
                model.section = .library
            case .setup, .setupXcode: model.section = .setup
            default: break
            }
            if page == .game || page == .gameNarrow || page == .gameNewer || page == .gameAfterConsole { model.selection = "0100152000022000" }
            if page == .gameXcode { model.selection = "01004D300C5AE000" }
            if page == .gameUnbuilt { model.selection = Gallery.unbuilt.titleID }
            if page == .gameSplit { model.selection = Gallery.splitTitleID }
            // A game up to date, while a batch runs: added to its queue.
            if page == .gameQueue { model.selection = "01006F8002326000" }
            if page == .setup || page == .assistantTools || page == .assistantToolsSource {
                model.setup.preview([
                    .mac: .ready("macOS 26.1"),
                    .xcode: .ready("Xcode 27.2"),
                    .xcodeReady: .ready(""),
                    .iosPlatform: .ready("iOS 27.2"),
                    .metal: .working(tr("Downloading the Metal toolchain…", "Téléchargement de la Metal toolchain…", "Descargando la Metal toolchain…", "Metal-Toolchain wird geladen …"), 0.42),
                    .homebrew: .ready("Homebrew 5.0.4"),
                    .tools: .missing(tr("Missing: zstd, glslang.", "Manque : zstd, glslang.", "Faltan: zstd, glslang.", "Fehlt: zstd, glslang.")),
                    .nxnative: .blocked,
                ], xcode: "/Applications/Xcode-27.2.app")
            } else if page == .setupXcode {
                // Xcode 27.1, which nxnative refuses for the shaders of most
                // games (Ocarina of Time, 14 November 2026).
                model.setup.preview([
                    .mac: .ready("macOS 26.1"),
                    .xcode: .missing(tr("Xcode 27.1: nxnative builds the games’ shaders with the Metal compiler of Xcode 27.2, which it tested them with. Update Xcode in the App Store.",
                                        "Xcode 27.1 : nxnative construit les shaders des jeux avec le compilateur Metal de Xcode 27.2, avec lequel il les a testés. Mettez Xcode à jour dans l’App Store.",
                                        "Xcode 27.1: nxnative compila los shaders de los juegos con el compilador Metal de Xcode 27.2, con el que los probó. Actualiza Xcode en el App Store.",
                                        "Xcode 27.1: nxnative kompiliert die Shader der Spiele mit dem Metal-Compiler von Xcode 27.2, mit dem es sie getestet hat. Aktualisiere Xcode im App Store.")),
                    .iosPlatform: .ready("iOS 27.1"),
                    .homebrew: .ready("Homebrew 5.0.4"),
                    .tools: .ready("Python 3.13, XcodeGen, zstd, glslang"),
                    .nxnative: .ready("6c3aeb3"),
                ], xcode: "/Applications/Xcode.app", outdated: "27.1")
            } else {
                model.setup.preview([
                    .mac: .ready("macOS 26.1"),
                    .xcode: .ready("Xcode 27.2"),
                    .iosPlatform: .ready("iOS 27.2"),
                    .homebrew: .ready("Homebrew 5.0.4"),
                    .tools: .ready("Python 3.13, XcodeGen, zstd, glslang"),
                    .nxnative: .ready("6c3aeb3"),
                ], xcode: "/Applications/Xcode-27.2.app")
            }
            let now = Date()
            // Each with its model, as Cartouche tells it (BuildFor); on
            // settings-builds-no-bc, an iPhone 15 in the Duo's place.
            let iphones = [
                PairedDevice(id: "5D1C9A70-3E1B-4A7C-9D51-2F0E6B8A4C13", name: "iPhone 17 Pro", key: Data(repeating: 7, count: 32),
                             paired: now.addingTimeInterval(-6 * 86_400), seen: now.addingTimeInterval(-90), model: "iPhone18,1", readsBC: true),
                page == .settingsBuildsNoBC
                    ? PairedDevice(id: "A0F4E2B6-81C3-4D9E-B7A5-6C2D1E3F4A5B", name: "iPhone 15", key: Data(repeating: 9, count: 32),
                                   paired: now.addingTimeInterval(-2 * 86_400), seen: now.addingTimeInterval(-26 * 3600), model: "iPhone15,4", readsBC: false)
                    : PairedDevice(id: "A0F4E2B6-81C3-4D9E-B7A5-6C2D1E3F4A5B", name: "iPhone Duo", key: Data(repeating: 9, count: 32),
                                   paired: now.addingTimeInterval(-2 * 86_400), seen: now.addingTimeInterval(-26 * 3600), model: "iPhone19,4", readsBC: true),
            ]
            let saves = URL(fileURLWithPath: info.home).appendingPathComponent("Saves", isDirectory: true)
            // A made-up address in the tailnet, never one of the project's.
            // On iphone-sending, a game on its way on this Mac's 2.4 GHz Wi-Fi.
            let sending = page == .iphoneSending
                ? [iphones[0].id: BridgeSending(speed: 3_140_000, network: CartoucheMacNetwork(medium: CartoucheMacNetwork.wifi, band: "2.4"))]
                : [:]
            model.bridge.preview(devices: iphones, connected: [iphones[0].id], cabled: page == .iphoneCable ? [iphones[0].id] : [],
                                 sending: sending, games: config.games, name: "MacBook Air", saves: saves,
                                 tailnet: page == .iphoneTailscale ? ["100.101.102.103", "fd7a:115c:a1e0::1"] : [])
            // The copies of Cartouche on the iPhones this Mac reaches, with a
            // made-up account and team, never the project's.
            let team = "ABCDE12345"
            let bundleId = "io.github.clabeuhtegrite.cartouche." + team
            let pro = SignerIphone(udid: "00008150-000A1C2E3F40001E", name: "iPhone 17 Pro", ios: "27.1", link: "usb", cartouche: [
                SignerCartouche(bundleId: bundleId, version: "0.16.2", teamId: team, expires: now.addingTimeInterval(4.4 * 86_400), due: "not-yet",
                                from: now.addingTimeInterval(2.4 * 86_400)),
            ])
            let duoExpires = page == .iphoneRenewalSignIn ? now.addingTimeInterval(-3 * 3_600) : now.addingTimeInterval(30 * 3_600)
            let duo = SignerIphone(udid: "00008160-001B2D3E4F50002E", name: "iPhone Duo", ios: "27.1", link: "network", cartouche: [
                SignerCartouche(bundleId: bundleId, version: "0.16.2", teamId: team, expires: duoExpires, due: page == .iphoneRenewalSignIn ? "expired" : "now"),
            ])
            switch page {
            case .iphoneRenewal:
                model.renewals.preview(session: SignerSession(signedIn: true, email: "camille@example.com", teamId: team, teamName: "Camille Testeur",
                                                              since: now.addingTimeInterval(-3 * 86_400)),
                                       iphones: [pro, duo],
                                       attempts: [RenewalController.key(pro.udid, bundleId): SignerAttempt(at: now.addingTimeInterval(-2 * 86_400), kind: nil,
                                                                                                            expires: pro.cartouche[0].expires),
                                                  RenewalController.key(duo.udid, bundleId): SignerAttempt(at: now.addingTimeInterval(-20 * 60), kind: "iphone-refused",
                                                                                                            expires: duoExpires)])
            case .iphoneRenewalInstall:
                let proExpired = now.addingTimeInterval(-5 * 3_600)
                let expiredPro = SignerIphone(udid: pro.udid, name: pro.name, ios: pro.ios, link: pro.link, cartouche: [
                    SignerCartouche(bundleId: bundleId, version: "0.16.2", teamId: team, expires: proExpired, due: "expired"),
                ])
                let proKey = RenewalController.key(pro.udid, bundleId)
                model.renewals.preview(session: SignerSession(signedIn: true, email: "camille@example.com", teamId: team, teamName: "Camille Testeur",
                                                              since: now.addingTimeInterval(-3 * 86_400)),
                                       iphones: [expiredPro, duo],
                                       attempts: [proKey: SignerAttempt(at: now.addingTimeInterval(-6 * 3_600), kind: "certificate-gone", expires: proExpired),
                                                  RenewalController.key(duo.udid, bundleId): SignerAttempt(at: now.addingTimeInterval(-40 * 60),
                                                                                                            kind: "no-certificate-left",
                                                                                                            expires: duoExpires, install: true)],
                                       installing: [proKey: SignerProgress(step: "install", fraction: 0.6)])
            case .iphoneRenewalSignIn:
                model.renewals.preview(session: nil, iphones: [pro, duo],
                                       signIn: .code(SignerCodeRequest(bySms: false, numbers: [SignerCodeRequest.Number(id: 1, number: "+33 •• •• •• •• 42", lastTwoDigits: "42")])))
            default:
                model.renewals.preview(session: nil, iphones: [pro])
            }
            // Mario Kart 8 Deluxe played on this Mac, the iPhone's saves come
            // before its last game, or, on game-newer, held back, version
            // 3.0.4 of the game on the iPhone having written the newest copy
            // and this Mac's being 3.0.3; Super Mario Odyssey playing now.
            let odyssey = MacGameApp(url: URL(fileURLWithPath: "/Users/player/Applications/Super Mario Odyssey.app"),
                                     titleID: "0100000000010000", name: "Super Mario Odyssey")
            model.macGames.preview(folder: saves,
                                   playing: page == .menubar ? [MacGameRun(app: odyssey, pid: 0, started: now.addingTimeInterval(-1500), fromBuilder: true)] : [],
                                   last: ["0100152000022000": page == .gameNewer
                                       ? MacSaveEvent(at: now.addingTimeInterval(-26 * 60), when: .before, step: MacSaveEvent.heldBack,
                                                      newer: "3.0.4", game: "3.0.3")
                                       : MacSaveEvent(at: now.addingTimeInterval(-26 * 60), when: .before, step: "fetch",
                                                      fetched: "2026-11-13T18-02-00Z.zip")])
            if page == .iphoneGames {
                // The connections of the console's Storage page, made up and
                // kept in memory only: the iPhone chose its games folder on
                // the NAS; Mario Kart World's Mac app goes there, and
                // Animal Crossing's, another Mac's, waits to be installed.
                ConsoleGallery.showConnections(language: L10n.code)
                let name = "Animal Crossing New Horizons [01006F8002326000].app.zip"
                model.iPhoneGames.preview(folder: IPhoneGames.Folder(connection: ConsoleGallery.nas, path: "Cartouche/" + tr("Games", "Jeux", "Juegos", "Spiele")),
                                          progress: ConnectionGamesProgress(game: "Mario Kart World", kind: .macFile, done: 1_288_490_188,
                                                                            total: 2_915_000_000, index: 1, count: 2),
                                          sent: 4, total: 6,
                                          offers: [ConnectionMacApp(titleID: "01006F8002326000", game: "Animal Crossing New Horizons",
                                                                    file: ConnectionFile(name: name, size: 7_340_032_000, modified: now.addingTimeInterval(-26 * 3_600)))],
                                          checked: now.addingTimeInterval(-120))
            }
            if page == .menubar {
                let release = BuilderRelease(version: "0.3.0", tag: "builder-v0.3.0", notes: "",
                                             page: URL(string: "https://github.com/cartouche-app/Cartouche/releases/tag/builder-v0.3.0")!,
                                             image: URL(string: "https://github.com/cartouche-app/Cartouche/releases/download/builder-v0.3.0/Cartouche-Builder-0.3.0.dmg")!,
                                             checksum: URL(string: "https://github.com/cartouche-app/Cartouche/releases/download/builder-v0.3.0/Cartouche-Builder-0.3.0.dmg.sha256")!,
                                             size: 31_000_000)
                model.updater.preview(.ready(release))
            } else {
                model.updater.preview(.upToDate)
            }
            return model
        }
    }

    /// JSON whose "@-SECONDS" are dates and "#-SECONDS" times, that many
    /// seconds ago.
    static func dated(_ text: String, now: Date = Date()) -> Data {
        let expression = try! NSRegularExpression(pattern: "\"([@#])(-?[0-9]+)\"")
        let source = text as NSString
        let formatter = ISO8601DateFormatter()
        var result = ""
        var last = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let date = now.addingTimeInterval(Double(source.substring(with: match.range(at: 2))) ?? 0)
            result += source.substring(with: match.range(at: 1)) == "@"
                ? "\"\(formatter.string(from: date))\""
                : String(Int(date.timeIntervalSince1970))
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return Data(result.utf8)
    }

    static let head = "6c3aeb3d70a1c2b94f5e8d7a6b5c4d3e2f1a0b9c"

    /// The room on the build folders' disk, short of what the settings keep
    /// free, as the engine says it (disks.py, room).
    static var room: LibraryRoom {
        LibraryRoom(freeGB: 13, keepGB: 20, folders: 2, title: tr("7 GB missing to build", "Il manque 7 Go pour construire", "Faltan 7 GB para compilar", "Zum Erstellen fehlen 7 GB"),
                    text: tr("Cartouche starts a build only with 20 GB free on your Mac's disk, and only 13 GB are free there. It first removes the build folders of the games built longest ago (2), which may be enough. Free some room there (Storage shows what the build folders take), choose build folders on another disk, or lower “Keep at least 20 GB free”.",
                             "Cartouche ne commence une construction qu'avec 20 Go libres sur le disque du Mac, et il n'y en a que 13. Il supprime d'abord les dossiers de construction des jeux construits il y a le plus longtemps (2), ce qui peut suffire. Libérez-y de la place (Stockage montre ce que prennent les dossiers de construction), choisissez des dossiers de construction sur un autre disque ou baissez « Garder au moins 20 Go libres ».",
                             "Cartouche solo empieza una compilación con 20 GB libres en el disco del Mac, y solo quedan 13 GB libres. Primero borra las carpetas de compilación de los juegos compilados hace más tiempo (2), lo que puede bastar. Libera espacio allí (Almacenamiento muestra lo que ocupan las carpetas de compilación), elige carpetas de compilación en otro disco o baja “Mantener al menos 20 GB libres”.",
                             "Cartouche beginnt einen Build nur mit 20 GB freiem Platz auf der Festplatte des Mac, und dort sind nur 13 GB frei. Zuerst entfernt es die Build-Ordner der am längsten zurückliegend erstellten Spiele (2), was reichen kann. Gib dort Platz frei („Speicher“ zeigt, was die Build-Ordner belegen), wähle Build-Ordner auf einer anderen Festplatte oder senke „Mindestens 20 GB frei lassen“."))
    }

    /// A game skipped for the Mac's Xcode, as the engine records it
    /// (causes.py, metal_words).
    static var metalAttempt: GameAttempt? {
        let attempt: [String: Any] = [
            "commit": String(head.prefix(12)), "at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)), "result": "skipped",
            "error": tr("nxnative builds this game's shaders only with the Metal compiler of Xcode 27.2, which it tested them with, and this Mac has Xcode 27.1. Update Xcode in the App Store (the page “This Mac's tools” does it with you), then build the game again.",
                        "nxnative ne construit les shaders de ce jeu qu'avec le compilateur Metal de Xcode 27.2, avec lequel il les a testés, et ce Mac a Xcode 27.1. Mettez Xcode à jour dans l'App Store (la page « Outils du Mac » le fait avec vous), puis relancez la construction.",
                        "nxnative solo compila los shaders de este juego con el compilador Metal de Xcode 27.2, con el que los probó, y este Mac tiene Xcode 27.1. Actualiza Xcode en el App Store (la página “Herramientas de este Mac” lo hace contigo) y vuelve a compilar el juego.",
                        "nxnative kompiliert die Shader dieses Spiels nur mit dem Metal-Compiler von Xcode 27.2, mit dem es sie getestet hat, und dieser Mac hat Xcode 27.1. Aktualisiere Xcode im App Store (die Seite „Werkzeuge dieses Mac“ hilft dir dabei) und erstelle das Spiel dann erneut."),
            "log": "/tmp/kirby.log",
        ]
        return (try? JSONSerialization.data(withJSONObject: attempt)).flatMap { try? JSONDecoder().decode(GameAttempt.self, from: $0) }
    }

    /// A game no Mac built yet, nor this one, with what the weekly list says
    /// of it (Unbuilt.swift).
    static var unbuilt: Game {
        Game(titleID: "0400A3A01EE4C000", name: "Pokémon Pokopia", kind: "nup", source: "/Volumes/Jeux/Switch/Pokopia", sourceSize: 9_870_000_000,
             state: .due, reasons: ["new"], detail: tr("Never built", "Jamais construit", "Nunca compilado", "Nie erstellt"))
    }

    static let unbuiltFigures = UnbuiltGame(titleID: "0400A3A01EE4C000", macs: 4, failures: 8, hours: 4.7, stage: "iOS shaders")

    /// Mario Kart World, whose shaders nxnative's newest commit splits
    /// otherwise than its profile says, as its 8d62601f of 16 November 2026
    /// did: built from 24e007be, the commit before nxnative's splitter
    /// changed, its Mac app too, the others from the newest, and held
    /// there until nxnative has a newer commit (decision 133), with what
    /// the engine says of it (texts.py). Its folders and sizes are made up.
    static let splitTitleID = "0400C3F00006E000"
    static let beforeSplitter = "24e007bed7c2"

    static var splitGame: Game {
        let newest = String(head.prefix(12))
        let held = tr("Up to date (built from nxnative \(beforeSplitter): nxnative \(newest), its newest commit, reads its shaders otherwise than its profile for now)",
                      "À jour (construit avec nxnative \(beforeSplitter) : nxnative \(newest), son dernier commit, lit ses shaders autrement que son profil pour l'instant)",
                      "Al día (compilado con nxnative \(beforeSplitter): nxnative \(newest), su commit más reciente, lee sus shaders de otra forma que su perfil por ahora)",
                      "Aktuell (erstellt mit nxnative \(beforeSplitter): nxnative \(newest), sein neuester Commit, liest seine Shader vorerst anders als sein Profil)")
        let game: [String: Any] = [
            "title_id": splitTitleID, "name": "Mario Kart World", "kind": "nup", "source": "/Volumes/Jeux/Switch/Mario Kart World",
            "source_size": 21_474_836_480, "followed": true, "profile": true, "state": "up_to_date", "reasons": ["up_to_date"], "detail": held,
            "ipa": ["name": "Mario Kart World.ipa", "path": "/Volumes/Jeux/iPhone/Mario Kart World.ipa", "size": 18_400_000_000,
                    "present": true] as [String: Any],
            "build": ["commit": beforeSplitter, "built_at": "@-1400", "version": "1.0.0", "duration": 3480, "origin": "app", "toolchain": "27.2",
                      "size": 18_400_000_000] as [String: Any],
            "platforms": ["ios": true, "mac": true],
            "mac": ["folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "reason": "up_to_date",
                    "library": ["name": "Mario Kart World [0400C3F00006E000].app.zip",
                                "path": "/Volumes/Jeux/iPhone/Mario Kart World [0400C3F00006E000].app.zip", "size": 18_600_000_000,
                                "present": true] as [String: Any],
                    "build": ["commit": beforeSplitter, "built_at": "@-700", "version": "1.0.0", "duration": 900,
                              "size": 18_600_000_000] as [String: Any]] as [String: Any],
        ]
        return decoded(Game.self, game)
    }

    /// The batch that built it, as the engine says it (status.py, texts.py):
    /// Mario Kart World built from the commit before nxnative's splitter
    /// changed, the batch back to the newest, Kirby building from there.
    static var splitBatch: BatchStatus {
        let newest = String(head.prefix(12))
        let name = "Mario Kart World"
        let lines = [
            "\(name): " + tr("nxnative \(newest) reads its shaders otherwise than its profile says (shader split): trying again from \(beforeSplitter), from before nxnative changed how it reads them…",
                             "nxnative \(newest) lit ses shaders autrement que ne le dit son profil (« shader split ») : nouvel essai avec \(beforeSplitter), d'avant le changement de sa lecture des shaders…",
                             "nxnative \(newest) lee sus shaders de otra forma que la que dice su perfil (“shader split”): nuevo intento con \(beforeSplitter), de antes de que nxnative cambiara su lectura…",
                             "nxnative \(newest) liest seine Shader anders, als sein Profil sagt („shader split“): Neuer Versuch mit \(beforeSplitter), von bevor nxnative änderte, wie es sie liest …"),
            tr("\(name): going to nxnative \(beforeSplitter), from before nxnative changed how it reads shaders…",
               "\(name) : passage à nxnative \(beforeSplitter), d'avant le changement de sa lecture des shaders…",
               "\(name): pasando a nxnative \(beforeSplitter), de antes de que nxnative cambiara su lectura de los shaders…",
               "\(name): Wechsel zu nxnative \(beforeSplitter), von bevor nxnative änderte, wie es Shader liest …"),
            "\(name): " + tr("IPA copied to the games folder (18.4 GB)", "IPA copiée dans le dossier des jeux (18,4 Go)", "IPA copiada en la carpeta de juegos (18,4 GB)", "IPA in den Spieleordner kopiert (18,4 GB)"),
            tr("\(name) built from nxnative \(beforeSplitter): nxnative \(newest) reads its shaders otherwise than its profile for now. It is built from \(beforeSplitter) until nxnative has a newer commit; the other games are built from \(newest).",
               "\(name) construit avec nxnative \(beforeSplitter) : nxnative \(newest) lit ses shaders autrement que son profil pour l'instant. Il se construit avec \(beforeSplitter) jusqu'à un commit plus récent de nxnative ; les autres jeux se construisent avec \(newest).",
               "\(name) compilado con nxnative \(beforeSplitter): nxnative \(newest) lee sus shaders de otra forma que su perfil por ahora. Se compila con \(beforeSplitter) hasta que nxnative tenga un commit más reciente; los demás juegos se compilan con \(newest).",
               "\(name) mit nxnative \(beforeSplitter) erstellt: nxnative \(newest) liest seine Shader vorerst anders als sein Profil. Es wird mit \(beforeSplitter) erstellt, bis nxnative einen neueren Commit hat; die anderen Spiele werden mit \(newest) erstellt."),
            tr("Back to nxnative \(newest)…", "Retour à nxnative \(newest)…", "Volviendo a nxnative \(newest)…", "Zurück zu nxnative \(newest) …"),
            "Kirby and the Forgotten Land: " + tr("extracted", "extrait", "extraído", "extrahiert"),
            "Kirby and the Forgotten Land: shaders 1088/2410",
        ]
        let status: [String: Any] = [
            "pid": 4242, "scheduled": false, "state": "building", "started": "@-4900", "updated": "@-1", "head": head, "latest": head, "running": true,
            "games": [
                ["title_id": splitTitleID, "name": name, "reasons": ["profile"], "state": "built", "started": "@-4900", "ended": "@-700",
                 "duration": 4200, "ipa": "/Volumes/Jeux/iPhone/Mario Kart World.ipa", "commit": beforeSplitter, "fallback": true, "split": true,
                 "makes": ["ios", "mac"], "platform": "mac", "mac": "built", "mac_only": false, "mac_duration": 900],
                ["title_id": "01004D300C5AE000", "name": "Kirby and the Forgotten Land", "reasons": ["named"], "state": "building", "stage": "shaders",
                 "step": tr("Pipelines 1,088 / 2,410", "Pipelines 1 088 / 2 410", "Pipelines 1088 / 2410", "Pipelines 1.088 / 2.410"), "k": 1088, "n": 2410, "frac": 0.45, "overall": 0.52, "eta": 520,
                 "started": "@-640", "commit": newest, "fallback": false, "split": false, "makes": ["ios", "mac"], "platform": "ios", "mac": "waiting",
                 "mac_only": false],
            ] as [[String: Any]],
            "lines": lines,
        ]
        return decoded(BatchStatus.self, status)
    }

    /// OBJECT, whose "@-SECONDS" are dates (dated), as the engine writes
    /// it; a sample that does not decode ends the gallery, which says why.
    static func decoded<Value: Decodable>(_ type: Value.Type, _ object: [String: Any]) -> Value {
        do {
            let json = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(type, from: dated(String(decoding: json, as: UTF8.self)))
        } catch {
            FileHandle.standardError.write(Data("gallery: a sample does not decode: \(error)\n".utf8))
            exit(1)
        }
    }

    /// What the engine left aside in the sample sources folder, in the
    /// language of the page, as the engine says it (texts.py).
    static var issues: [String] {
        [tr("Splatoon 3 (copy): the same game (0100C2500FC20000) as Splatoon 3; only Splatoon 3 is built.",
            "Splatoon 3 (copie) : le même jeu (0100C2500FC20000) que Splatoon 3 ; seul Splatoon 3 est construit.",
            "Splatoon 3 (copia): el mismo juego (0100C2500FC20000) que Splatoon 3; solo se compila Splatoon 3.",
            "Splatoon 3 (Kopie): dasselbe Spiel (0100C2500FC20000) wie Splatoon 3; nur Splatoon 3 wird erstellt."),
         tr("Downloads/Pikmin 4.nsp: not a game Cartouche can read (the file is incomplete: copied or downloaded in part?).",
            "Téléchargements/Pikmin 4.nsp : pas un jeu que Cartouche sait lire (le fichier est incomplet : copié ou téléchargé en partie ?).",
            "Descargas/Pikmin 4.nsp: no es un juego que Cartouche pueda leer (el archivo está incompleto: ¿copiado o descargado a medias?).",
            "Downloads/Pikmin 4.nsp: kein Spiel, das Cartouche lesen kann (die Datei ist unvollständig: nur teilweise kopiert oder geladen?).")]
    }

    static let libraryJSON = """
    {
      "checked": "@-5400",
      "language": "fr",
      "folders": {
        "sources": {"path": "/Volumes/Jeux/Switch", "present": true, "share": "smb://nas.local/Jeux", "mounted": true},
        "games": {"path": "/Volumes/Jeux/iPhone", "present": true, "share": "smb://nas.local/Jeux", "mounted": true},
        "keys": {"path": "/Users/player/Switch/prod.keys", "present": true},
        "remote": true
      },
      "engine": {"head": "\(head)", "short": "6c3aeb3", "time": "#-10800", "subject": "Kirby: water reflections without the black frames",
                 "url": "https://github.com/seedds/nxnative", "branch": "main", "commit_url": "https://github.com/seedds/nxnative/commit/\(head)"},
      "games": [
        {"title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe", "kind": "nup", "source": "/Volumes/Jeux/Switch/Mario Kart 8 Deluxe",
         "source_size": 7340032000, "followed": true, "profile": true, "state": "due", "due": true, "reasons": ["profile", "shared"],
         "ipa": {"name": "Mario Kart 8 Deluxe.ipa", "path": "/Volumes/Jeux/iPhone/Mario Kart 8 Deluxe.ipa", "size": 6410000000, "present": true},
         "build": {"commit": "4f1d2c9a7b3e", "built_at": "@-777600", "version": "3.0.3", "duration": 1260, "origin": "app", "toolchain": "27.2", "size": 6410000000},
         "platforms": {"ios": true, "mac": true},
         "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "due": true, "reason": "with_ipa",
                 "library": {"name": "Mario Kart 8 Deluxe [0100152000022000].app.zip", "path": "/Volumes/Jeux/iPhone/Mario Kart 8 Deluxe [0100152000022000].app.zip", "size": 6480000000, "present": true},
                 "app": {"name": "Mario Kart 8 Deluxe.app", "path": "/Users/player/Applications/Mario Kart 8 Deluxe.app", "size": 6620000000, "present": true},
                 "behind": true,
                 "build": {"commit": "4f1d2c9a7b3e", "built_at": "@-776900", "version": "3.0.3", "duration": 610, "size": 6480000000}},
         "changes": [
           {"sha": "e2a94c1b7d6f5a3b2c1d0e9f8a7b6c5d4e3f2a1b", "short": "e2a94c1", "subject": "mk8dx: lighter kart shadows, 60 fps in the menus", "time": "#-14400", "kind": "profile"},
           {"sha": "b81e2f4a9c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f", "short": "b81e2f4", "subject": "mk8dx: no more flicker on the last track", "time": "#-190000", "kind": "profile"},
           {"sha": "9d2c7a1e8b6f5c4d3e2a1b0c9f8e7d6a5b4c3d2e", "short": "9d2c7a1", "subject": "Shader cache: compile the pipelines in parallel", "time": "#-260000", "kind": "shared"},
           {"sha": "7c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b", "short": "7c1b0a9", "subject": "Audio: fewer underruns when the iPhone is busy", "time": "#-430000", "kind": "shared"}
         ],
         "change_counts": {"profile": 2, "named": 0, "shared": 4}},
        {"title_id": "01004D300C5AE000", "name": "Kirby and the Forgotten Land", "kind": "dump", "source": "/Volumes/Jeux/Switch/Kirby",
         "source_size": 6012000000, "followed": true, "profile": true, "state": "due", "due": true, "reasons": ["named"],
         "ipa": {"name": "Kirby and the Forgotten Land.ipa", "path": "/Volumes/Jeux/iPhone/Kirby and the Forgotten Land.ipa", "size": 5480000000, "present": true},
         "build": {"commit": "4f1d2c9a7b3e", "built_at": "@-777600", "version": "1.0.0", "duration": 980, "origin": "app", "toolchain": "27.2", "size": 5480000000},
         "platforms": {"ios": true, "mac": true}, "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "due": true, "reason": "with_ipa"},
         "changes": [
           {"sha": "\(head)", "short": "6c3aeb3", "subject": "Kirby: water reflections without the black frames", "time": "#-10800", "kind": "named"}
         ],
         "change_counts": {"profile": 0, "named": 1, "shared": 4}},
        {"title_id": "010093801237C000", "name": "Metroid Dread", "kind": "nup", "source": "/Volumes/Jeux/Switch/Metroid Dread",
         "source_size": 4510000000, "followed": true, "profile": true, "state": "failed", "reasons": ["shared"],
         "attempt": {"commit": "6c3aeb3d70a1", "at": "@-9000", "result": "failed", "error": "Les shaders n’ont pas compilé : pipeline 1187.", "log": "/tmp/metroid.log"},
         "ipa": {"name": "Metroid Dread.ipa", "path": "/Volumes/Jeux/iPhone/Metroid Dread.ipa", "size": 4120000000, "present": true},
         "build": {"commit": "a3b2c1d0e9f8", "built_at": "@-1900000", "version": "2.1.0", "duration": 840, "origin": "app", "toolchain": "27.2", "size": 4120000000},
         "platforms": {"ios": true, "mac": true}, "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "reason": "after_ipa"},
         "change_counts": {"profile": 0, "named": 0, "shared": 6}},
        {"title_id": "0100000000010000", "name": "Super Mario Odyssey", "kind": "zip", "source": "/Volumes/Jeux/Switch/Super Mario Odyssey.zip",
         "source_size": 5650000000, "followed": true, "profile": true, "state": "up_to_date",
         "ipa": {"name": "Super Mario Odyssey.ipa", "path": "/Volumes/Jeux/iPhone/Super Mario Odyssey.ipa", "size": 5320000000, "present": true},
         "build": {"commit": "\(head)", "built_at": "@-7000", "version": "1.3.0", "duration": 1130, "origin": "app", "toolchain": "27.2", "size": 5320000000},
         "platforms": {"ios": true, "mac": true},
         "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "reason": "up_to_date",
                 "library": {"name": "Super Mario Odyssey [0100000000010000].app.zip", "path": "/Volumes/Jeux/iPhone/Super Mario Odyssey [0100000000010000].app.zip", "size": 5390000000, "present": true},
                 "app": {"name": "Super Mario Odyssey.app", "path": "/Users/player/Applications/Super Mario Odyssey.app", "size": 5510000000, "present": true},
                 "build": {"commit": "\(head)", "built_at": "@-6500", "version": "1.3.0", "duration": 480, "size": 5390000000}}},
        {"title_id": "01007EF00011E000", "name": "The Legend of Zelda: Breath of the Wild", "kind": "nup", "source": "/Volumes/Jeux/Switch/Zelda BotW",
         "source_size": 16200000000, "followed": true, "profile": true, "state": "up_to_date",
         "ipa": {"name": "Zelda BotW.ipa", "path": "/Volumes/Jeux/iPhone/Zelda BotW.ipa", "size": 15100000000, "present": true},
         "build": {"commit": "\(head)", "built_at": "@-6400", "version": "1.6.0", "duration": 2410, "origin": "app", "toolchain": "27.2", "size": 15100000000},
         "platforms": {"ios": true, "mac": false}, "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications"}},
        {"title_id": "01006F8002326000", "name": "Animal Crossing: New Horizons", "kind": "nup", "source": "/Volumes/Jeux/Switch/Animal Crossing",
         "source_size": 10500000000, "followed": true, "profile": true, "state": "up_to_date",
         "ipa": {"name": "Animal Crossing.ipa", "path": "/Volumes/Jeux/iPhone/Animal Crossing.ipa", "size": 9800000000, "present": true},
         "build": {"commit": "\(head)", "built_at": "@-90000", "version": "2.0.6", "duration": 1500, "origin": "app", "toolchain": "27.2", "size": 9800000000},
         "platforms": {"ios": true, "mac": true},
         "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "reason": "up_to_date", "library": {"name": "Animal Crossing - New Horizons [01006F8002326000].app.zip", "path": "/Volumes/Jeux/iPhone/Animal Crossing - New Horizons [01006F8002326000].app.zip", "size": 9950000000, "present": true},
                 "build": {"commit": "\(head)", "built_at": "@-89000", "version": "2.0.6", "duration": 640, "size": 9950000000}}},
        {"title_id": "01006A800016E000", "name": "Super Smash Bros. Ultimate", "kind": "nup", "source": "/Volumes/Jeux/Switch/Smash",
         "source_size": 16900000000, "followed": true, "profile": true, "state": "up_to_date",
         "ipa": {"name": "Smash.ipa", "path": "/Volumes/Jeux/iPhone/Smash.ipa", "size": 15700000000, "present": true},
         "build": {"commit": "\(head)", "built_at": "@-95000", "version": "13.0.3", "duration": 2700, "origin": "app", "toolchain": "27.2", "size": 15700000000},
         "platforms": {"ios": true, "mac": true},
         "mac": {"folder": "/Volumes/Jeux/iPhone", "packed": true, "installs": "/Users/player/Applications", "reason": "up_to_date", "library": {"name": "Super Smash Bros. Ultimate [01006A800016E000].app.zip", "path": "/Volumes/Jeux/iPhone/Super Smash Bros. Ultimate [01006A800016E000].app.zip", "size": 15900000000, "present": true},
                 "build": {"commit": "\(head)", "built_at": "@-94000", "version": "13.0.3", "duration": 900, "size": 15900000000}}},
        {"title_id": "010028600EBDA000", "name": "Super Mario 3D World + Bowser’s Fury", "kind": "nup", "source": "/Volumes/Jeux/Switch/3D World",
         "source_size": 2900000000, "followed": false, "profile": true, "state": "not_followed",
         "ipa": {"name": "3D World.ipa", "path": "/Volumes/Jeux/iPhone/3D World.ipa", "size": 2700000000, "present": true},
         "build": {"commit": "a3b2c1d0e9f8", "built_at": "@-2600000", "version": "1.1.0", "duration": 700, "origin": "app", "toolchain": "27.2", "size": 2700000000}},
        {"title_id": "010074F013262000", "name": "Xenoblade Chronicles 3", "kind": "nup", "source": "/Volumes/Jeux/Switch/Xenoblade 3",
         "source_size": 15100000000, "followed": true, "profile": false, "state": "no_profile"},
        {"title_id": "01001F5010DFA000", "name": "Pokémon Legends: Arceus", "kind": "ipa", "followed": true, "state": "no_source",
         "ipa": {"name": "Pokemon Legends Arceus.ipa", "path": "/Volumes/Jeux/iPhone/Pokemon Legends Arceus.ipa", "size": 6900000000, "present": true}}
      ]
    }
    """

    static let buildingJSON = """
    {
      "pid": 4242, "scheduled": false, "state": "building", "started": "@-1500", "updated": "@-1", "head": "\(head)", "running": true,
      "games": [
        {"title_id": "01004D300C5AE000", "name": "Kirby and the Forgotten Land", "reasons": ["named"], "state": "built",
         "started": "@-1500", "ended": "@-610", "duration": 890, "ipa": "/Volumes/Jeux/iPhone/Kirby and the Forgotten Land.ipa",
         "makes": ["ios", "mac"], "platform": "mac", "mac": "built", "mac_only": false, "mac_duration": 420},
        {"title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe", "reasons": ["profile", "shared"], "state": "building", "stage": "shaders",
         "step": "Pipelines 1 412 / 2 300", "k": 1412, "n": 2300, "frac": 0.61, "overall": 0.68, "eta": 380, "started": "@-600",
         "makes": ["ios", "mac"], "platform": "ios", "mac": "waiting", "mac_only": false},
        {"title_id": "010093801237C000", "name": "Metroid Dread", "reasons": ["shared"], "state": "queued",
         "makes": ["ios", "mac"], "platform": "ios", "mac": "waiting", "mac_only": false}
      ],
      "lines": [
        "Kirby and the Forgotten Land: IPA copied to the games folder (5.5 GB)",
        "Mario Kart 8 Deluxe: extracted",
        "Mario Kart 8 Deluxe: shaders 1412/2300"
      ]
    }
    """

    static let storageJSON = """
    {
      "workspace": "/Users/player/Library/Application Support/Cartouche Builder/Builds",
      "disks": {
        "workspace": {"path": "/", "free": 182000000000, "total": 994000000000, "present": true},
        "games": {"path": "/Volumes/Jeux", "free": 2310000000000, "total": 7990000000000, "present": true},
        "mac_apps": {"path": "/Users/player/Applications", "free": 182000000000, "total": 994000000000, "present": true}
      },
      "folders": [
        {"path": "/Builds/0100152000022000", "workspace": "/Builds", "title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe", "kind": "build",
         "size": 2140000000, "parts": {"shaders": 1310000000, "app": 830000000}, "used": "#-777600"},
        {"path": "/Builds/01007EF00011E000", "workspace": "/Builds", "title_id": "01007EF00011E000", "name": "The Legend of Zelda: Breath of the Wild", "kind": "build",
         "size": 15600000000, "parts": {"extracted": 13900000000, "shaders": 1100000000, "app": 600000000}, "used": "#-6400"},
        {"path": "/Builds/0100000000010000", "workspace": "/Builds", "title_id": "0100000000010000", "name": "Super Mario Odyssey", "kind": "build",
         "size": 1650000000, "parts": {"shaders": 1020000000, "app": 630000000}, "used": "#-7000"},
        {"path": "/Builds/01006A800016E000", "workspace": "/Builds", "title_id": "01006A800016E000", "name": "Super Smash Bros. Ultimate", "kind": "build",
         "size": 1270000000, "parts": {"shaders": 640000000, "app": 630000000}, "used": "#-95000"}
      ],
      "ipa_copies": [],
      "mac_apps": [
        {"path": "/Users/player/Applications/Mario Kart 8 Deluxe.app", "title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe", "size": 6620000000,
         "on": true, "built_at": "@-1900000", "shares_build": false, "packed": true},
        {"path": "/Users/player/Applications/Super Mario Odyssey.app", "title_id": "0100000000010000", "name": "Super Mario Odyssey", "size": 5510000000,
         "on": true, "built_at": "@-6500", "shares_build": false, "packed": true}
      ],
      "totals": {"extracted": 13900000000, "shaders": 4070000000, "app": 2690000000, "packages": 0, "temporary": 0, "other": 120000000,
                 "logs": 48000000, "ipa_copies": 0, "ipa_copies_freeable": 0, "engine": 410000000, "python": 260000000, "mac_apps": 12130000000},
      "settings": {"keep_extracted": false, "keep_ipa": false, "min_free_gb": 20, "workspace_limit_gb": 0}
    }
    """

    /// The storage of a player whose build folders are on their NAS: Breath
    /// of the Wild building on this Mac, three games' folders on the NAS.
    static let storageNASJSON = """
    {
      "workspace": "/Volumes/Jeux/Builds",
      "disks": {
        "workspace": {"path": "/Users/player/Library/Application Support/Cartouche Builder/Builds", "free": 182000000000, "total": 994000000000, "present": true},
        "shelf": {"path": "/Volumes/Jeux/Builds", "free": 2310000000000, "total": 7990000000000, "present": true},
        "games": {"path": "/Volumes/Jeux", "free": 2310000000000, "total": 7990000000000, "present": true},
        "mac_apps": {"path": "/Users/player/Applications", "free": 182000000000, "total": 994000000000, "present": true}
      },
      "folders": [
        {"path": "/Users/player/Library/Application Support/Cartouche Builder/Builds/01007EF00011E000_build",
         "workspace": "/Users/player/Library/Application Support/Cartouche Builder/Builds", "title_id": "01007EF00011E000",
         "name": "The Legend of Zelda: Breath of the Wild", "kind": "build",
         "size": 15600000000, "parts": {"extracted": 13900000000, "shaders": 1100000000, "app": 600000000}, "used": "#-600", "shelf": false},
        {"path": "/Volumes/Jeux/Builds/0100152000022000_build", "workspace": "/Volumes/Jeux/Builds", "title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe",
         "kind": "build", "size": 2140000000, "parts": {"shaders": 1310000000, "app": 830000000}, "used": "#-777600", "shelf": true},
        {"path": "/Volumes/Jeux/Builds/0100000000010000_build", "workspace": "/Volumes/Jeux/Builds", "title_id": "0100000000010000", "name": "Super Mario Odyssey",
         "kind": "build", "size": 1650000000, "parts": {"shaders": 1020000000, "app": 630000000}, "used": "#-7000", "shelf": true},
        {"path": "/Volumes/Jeux/Builds/01006A800016E000_build", "workspace": "/Volumes/Jeux/Builds", "title_id": "01006A800016E000",
         "name": "Super Smash Bros. Ultimate", "kind": "build", "size": 1270000000, "parts": {"shaders": 640000000, "app": 630000000}, "used": "#-95000", "shelf": true}
      ],
      "ipa_copies": [],
      "mac_apps": [
        {"path": "/Users/player/Applications/Mario Kart 8 Deluxe.app", "title_id": "0100152000022000", "name": "Mario Kart 8 Deluxe", "size": 6620000000,
         "on": true, "built_at": "@-1900000", "shares_build": false, "packed": true},
        {"path": "/Users/player/Applications/Super Mario Odyssey.app", "title_id": "0100000000010000", "name": "Super Mario Odyssey", "size": 5510000000,
         "on": true, "built_at": "@-6500", "shares_build": false, "packed": true}
      ],
      "totals": {"extracted": 13900000000, "shaders": 1100000000, "app": 600000000, "packages": 0, "temporary": 0, "other": 0, "shelf": 5060000000,
                 "logs": 48000000, "ipa_copies": 0, "ipa_copies_freeable": 0, "engine": 410000000, "python": 260000000, "mac_apps": 12130000000},
      "settings": {"keep_extracted": false, "keep_ipa": false, "min_free_gb": 20, "workspace_limit_gb": 0}
    }
    """

    static let configJSON = """
    {"sources": "/Volumes/Jeux/Switch", "games": "/Volumes/Jeux/iPhone", "keys": "/Users/player/Switch/prod.keys", "language": "fr",
     "schedule": true, "schedule_hour": 3, "schedule_minute": 30, "jobs": 1, "engine_policy": "weekly", "refresh_days": 7, "min_free_gb": 20,
     "ios": true, "mac": true, "skip_mac": ["01007EF00011E000"]}
    """

    static let infoJSON = """
    {"version": "0.2.0", "home": "/Users/player/Library/Application Support/Cartouche Builder",
     "workspace": "/Users/player/Library/Application Support/Cartouche Builder/Builds", "python": "/opt/homebrew/bin/python3.13", "scheduled": true,
     "mac_apps": "/Users/player/Applications", "default_mac_apps": "/Users/player/Applications", "mac_packed": true}
    """
}

/// The gallery's page being taken, watched from a thread of its own, since
/// a page that never ends holds the main thread: after LIMIT seconds on one
/// page, it says which on standard error and ends the gallery.
private final class GalleryWatchdog: @unchecked Sendable {
    private let limit: TimeInterval
    private let lock = NSLock()
    private var page: String?
    private var since = Date()

    init(limit: TimeInterval) {
        self.limit = limit
        Thread.detachNewThread { [self] in
            while true {
                Thread.sleep(forTimeInterval: 5)
                check()
            }
        }
    }

    /// PAGE is being taken from now on; nil once the pictures are.
    func watch(_ page: String?) {
        lock.lock()
        self.page = page
        since = Date()
        lock.unlock()
    }

    private func check() {
        lock.lock()
        let late = page.flatMap { Date().timeIntervalSince(since) > limit ? $0 : nil }
        lock.unlock()
        guard let late else { return }
        FileHandle.standardError.write(Data("gallery: \(late): not taken after \(Int(limit)) s, something holds the main thread; the gallery ends\n".utf8))
        _exit(1)
    }
}
