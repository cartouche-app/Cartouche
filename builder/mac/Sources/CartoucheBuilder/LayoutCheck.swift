//
//  LayoutCheck.swift
//  Cartouche Builder
//
//  `Cartouche Builder --layout-check`, for CI (Builder workflow): the app
//  as the player opens it, on sample games whose nxnative commits are as
//  long as nxnative's own, taken through what the player does: a game
//  chosen and its sheet beside, nxnative checked, a message above the page,
//  of one line and of several, the window from wide to its smallest, the
//  sidebar hidden and shown, each page, the pages chosen with the arrow
//  keys, a build asked for while nxnative is checked. After each step every
//  scrolling column must lie in the window, across and down, and the
//  sidebar must list its pages. Any exception AppKit raises ends the app
//  (NSApplicationCrashOnExceptions), as one did on a player's Mac on
//  11 November: the game's sheet, then the system's inspector, made the
//  page wider than the window at each update, until AppKit's constraint
//  passes went round in a loop. The same day a message above the page made
//  the pages three times the window's height, their tops out of reach, which
//  this check did not look at. And SwiftUI must never have said that a
//  change was published while it updated the window, after which its
//  behaviour is undefined: the sidebar did, at each page chosen. Last, the
//  console and back to the builder, the Mac in light mode, then in dark:
//  the builder must look as it did before the console, and the console the
//  same in both (on 17 November, in light mode, the builder came back with
//  words white on white). Nothing of the Mac's is read or kept: no engine,
//  no bridge, no settings written.
//

import AppKit
import BuilderKit
import OSLog
import ScreenCaptureKit
import SwiftUI

@MainActor
enum LayoutCheck {
    static let requested = CommandLine.arguments.contains("--layout-check")

    /// The widths the window is taken through, from wide to below its
    /// smallest, which AppKit keeps it at.
    static let widths: [CGFloat] = [1600, 1400, 1220, 1100, 1024, 1000, 980, 960, 940, 900]

    /// Before the app starts.
    static func prepare() {
        UserDefaults.standard.setVolatileDomain([
            // An exception ends the app, instead of being logged and leaving
            // a broken window behind.
            "NSApplicationCrashOnExceptions": true,
            // The window at its default size, not at one a run left.
            "ApplePersistenceIgnoreState": true,
            AppSettings.bridgeKey: false,
        ], forName: UserDefaults.argumentDomain)
        NSSetUncaughtExceptionHandler(sayException)
        L10n.use("fr")
    }

    // MARK: The games

    /// The gallery's games and nine more, fourteen of them improved, with
    /// nxnative's commits and the engine's reasons as long as a player's.
    static func model() -> AppModel {
        let samples: Gallery.Samples
        do {
            samples = try Gallery.Samples()
        } catch {
            say("✗ the samples do not decode: \(error)")
            exit(1)
        }
        var library = samples.library
        library.issues = Gallery.issues
        let more = ["Hades II", "Luigi’s Mansion 3", "Donkey Kong Bananza", "Mario Kart World", "Mario Tennis Fever",
                    "Pokémon Pokopia", "Splatoon Raiders", "Star Fox", "Super Mario Party Jamboree"]
        let model = library.games[0]
        for (index, name) in more.enumerated() {
            var game = model
            game.titleID = String(format: "0100F000000%05X", index)
            game.name = name
            game.source = "/Volumes/Jeux/Switch/\(name)"
            library.games.append(game)
        }
        for index in library.games.indices where [GameState.due, .upToDate].contains(library.games[index].state) {
            lengthen(&library.games[index])
        }
        let app = AppModel.sampled(library: library, status: nil, storage: samples.storage, config: samples.config, info: samples.info)
        app.setup.preview([
            .mac: .ready("macOS 27.0"),
            .xcode: .ready("Xcode 27.2"),
            .iosPlatform: .ready("iOS 27.2"),
            .homebrew: .ready("Homebrew 5.0.4"),
            .tools: .ready("Python 3.13, XcodeGen, zstd, glslang"),
            .nxnative: .ready("6c3aeb3"),
        ], xcode: "/Applications/Xcode-27.2.app")
        app.updater.preview(.upToDate)
        return app
    }

    /// A game nxnative improved, with commits of a paragraph each, as
    /// nxnative writes them, and the engine's reasons quoting them (also the
    /// gallery's game-narrow page).
    static func lengthen(_ game: inout Game) {
        let now = Date().timeIntervalSince1970
        let paragraphs = [
            "Graphics: the picture's size follows the console mode the game asks for at run time instead of a size fixed per build, so a game that draws below the display's size in handheld mode gets the larger picture when it switches, and the games that scale their frame buffer by a tier get the tier the handheld mode reports. Checked on three games over twenty minutes each: the GPU time stays within a millisecond of before, at the same frame rate, with the same four warnings in the log and none new; not run on the iPhone, where the larger picture leaves less room, nor on a slower Mac.",
            "Input: a change of console mode at run time is signalled to the game the way the console does it, with the style update events of the controllers it moves, so that a game which waits for them before it draws its menus no longer stops on a black screen after the first switch; the events go between the two queues in the order the console sends them, and a game that never asks for them sees nothing new.",
            "Port \(game.name): its profile, its shaders' cache and the size of its picture in handheld mode",
            "Shader cache: the pipelines are compiled in parallel, eight at a time, and a pipeline that fails is compiled again alone before the build gives up on it, which keeps a build that used to take forty minutes under twenty-five on a Mac with ten cores.",
            "Audio: fewer underruns when the iPhone is busy, the mixer's buffer growing by a quarter when two in a row come late and shrinking back after a minute without one.",
        ]
        game.state = .due
        game.due = true
        game.reasons = ["profile", "named", "shared"]
        let changes: [[String: Any]] = paragraphs.enumerated().map { index, subject in
            let sha = String(format: "%08x", 0x8fb5_ffeb &+ UInt32(index * 7919)) + String(repeating: "c", count: 32)
            return ["sha": sha, "short": String(sha.prefix(12)), "subject": subject, "time": now - Double(index + 1) * 9_000,
                    "kind": index < 2 ? "profile" : index == 2 ? "named" : "shared"]
        }
        if let data = try? JSONSerialization.data(withJSONObject: changes) {
            game.changes = (try? JSONDecoder().decode([Change].self, from: data)) ?? []
        }
        game.changeCounts = ChangeCounts(profile: 3, named: 2, shared: 12)
        game.detail = "nxnative a modifié son profil (3 commits ; dernier : \(paragraphs[0].prefix(107))…) ; "
            + "2 commits de nxnative le nomment (dernier : \(paragraphs[1].prefix(107))…) ; "
            + "Le code commun de nxnative a changé (12 commits) et sa construction date de 9 jours"
    }

    // MARK: The steps

    /// Takes the window through the steps once the app has started, then
    /// ends the app: 0 when every step passed.
    static func start() {
        Task { @MainActor in
            let failures = await run()
            say(failures == 0 ? "every step passed" : "✗ \(failures) step\(failures == 1 ? "" : "s") failed")
            exit(failures == 0 ? 0 : 1)
        }
    }

    private static func run() async -> Int {
        let model = AppModel.shared
        let began = Date()
        guard let window = await mainWindow() else {
            say("✗ the window never opened; windows: " + NSApp.windows.map { "\($0.title) [\($0.identifier?.rawValue ?? "")]" }.joined(separator: ", "))
            return 1
        }
        let chosen = model.library?.games.first { $0.name == "Hades II" }?.titleID
        let other = model.library?.games.first { $0.state == .failed }?.titleID
        var failures = measure(model, chosen: chosen)

        func step(_ name: String, _ action: () -> Void) async {
            action()
            try? await Task.sleep(for: .milliseconds(900))
            let found = inspect(window)
            say("\(found.isEmpty ? "✓" : "✗") \(name): window \(Int(window.frame.width))×\(Int(window.frame.height)), \(columns(window))")
            for problem in found { say("    \(problem)") }
            if !found.isEmpty { failures += 1 }
        }

        func resize(_ width: CGFloat) {
            let height = min(780, (window.screen?.visibleFrame.height ?? 740) - 20)
            window.setFrame(NSRect(x: 0, y: 20, width: width, height: height), display: true)
        }

        await step("opened") {}
        say("    views: " + scrollViews(window))
        await step("a game chosen, its sheet beside") { model.selection = chosen }
        say("    views: " + scrollViews(window))
        await step("nxnative checked") { model.preview(checking: true) }
        await step("nxnative checked, done") { model.preview(checking: false) }
        await step("a message above the page") {
            model.banner = Banner(kind: .error, text: "La vérification de nxnative a échoué : fatal: unable to access 'https://github.com/seedds/nxnative/': Could not resolve host: github.com. Cartouche Builder réessaiera dans six heures.")
        }
        await step("the message closed") { model.banner = nil }
        // A build that did not start, as the app says it: the last lines of
        // its log, one under the other.
        await step("a message of several lines above the page") {
            model.banner = Banner(kind: .error, text: "La construction n’a pas démarré : Un lot tourne déjà sur ce Mac (la fenêtre ou le lancement de la nuit).\n"
                                  + "Un lot tourne déjà sur ce Mac (la fenêtre ou le lancement de la nuit).\nUn lot tourne déjà sur ce Mac (la fenêtre ou le lancement de la nuit).")
        }
        await step("that message closed") { model.banner = nil }
        for width in widths {
            await step("the window at \(Int(width)) points, with the game's sheet") { resize(width) }
        }
        say("    views: " + scrollViews(window))
        await step("the sidebar hidden") { splitController(window)?.toggleSidebar(nil) }
        await step("the sidebar shown") { splitController(window)?.toggleSidebar(nil) }
        await step("another game chosen") { model.selection = other }
        await step("a message above the narrow page") {
            model.banner = Banner(kind: .info, text: "Déplacez d’abord Cartouche Builder dans le dossier Applications : il pourra alors se mettre à jour tout seul.")
        }
        await step("the message closed again") { model.banner = nil }
        for section in AppSection.allCases where section != .library {
            await step("the page \(section.rawValue)") { model.section = section }
        }
        await step("the library again") { model.section = .library }
        for (down, name) in [(true, "down"), (false, "up")] {
            for _ in 1..<AppSection.allCases.count {
                await step("the next page with the \(name) arrow key") { arrowKey(window, down: down) }
                if let problem = followed(window, model) {
                    say("    ✗ \(problem)")
                    failures += 1
                }
            }
        }
        await step("the sheet closed") { model.selection = nil }
        await step("the sheet opened at the smallest width") { model.selection = chosen }
        // The game asked for waits its turn while nxnative is checked, on its
        // sheet and on the builds' page, until the batch runs.
        await step("a build asked for while nxnative is checked") { model.preview(starting: [chosen].compactMap { $0 }, checking: true) }
        await step("the builds' page meanwhile") { model.section = .activity }
        await step("the library again meanwhile") { model.section = .library }
        await step("nxnative checked, the batch gone") { model.preview(starting: [], checking: false) }
        for width in widths.reversed() {
            await step("the window at \(Int(width)) points again") { resize(width) }
        }
        failures += await theBuilderAfterTheConsole(window, model, chosen: chosen)
        let published = publishedInUpdates(since: began)
        if let published, published > 0 {
            say("✗ SwiftUI said \(published) time\(published == 1 ? "" : "s") that a change was published while it updated the window")
            failures += 1
        } else {
            say(published == nil ? "· SwiftUI's warnings could not be read from the log" : "✓ no change published while SwiftUI updated the window")
        }
        return failures
    }

    // MARK: The console and back

    /// The builder after the console, the Mac in light mode, then in dark:
    /// what the window server shows of the builder once the player went to
    /// the console and came back must be what it showed before, each word
    /// where it was, in the colours of the Mac's appearance; and the
    /// console, dark whatever the Mac's, must look the same in both. On a
    /// player's Mac in light mode, on 17 November, the builder came back
    /// from the console with its pages light again but words still in the
    /// console's colours, white on white, until something else had the
    /// window drawn again: a right click on the app's icon in the Dock.
    /// The number of checks that failed.
    private static func theBuilderAfterTheConsole(_ window: NSWindow, _ model: AppModel, chosen: String?) async -> Int {
        // The gallery's games in the console, their covers loaded before
        // (ConsoleGallery.swift): no question to Cartouche's server, nothing
        // of the Mac's read.
        await ConsoleGallery.prepareInTask(language: L10n.code)
        defer { ConsoleGallery.cleanUp() }
        var failures = 0
        var consoles: [(mode: String, picture: CGImage)] = []
        let modes: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (mode, appearance) in modes {
            NSApp.appearance = NSAppearance(named: appearance)
            model.section = .library
            model.selection = chosen
            // No list holding the keyboard, which the builder's new list
            // would not either.
            window.makeFirstResponder(nil)
            try? await Task.sleep(for: .seconds(2))
            let before = await picture(of: window)
            let chosenBefore = chosenPage(window)
            model.show(.console)
            try? await Task.sleep(for: .seconds(2.5))
            if let console = await picture(of: window) { consoles.append((mode, console)) }
            model.show(.builder)
            try? await Task.sleep(for: .seconds(2))
            let after = await picture(of: window)
            guard let before, let after else {
                say("✗ the builder after the console, in \(mode) mode: the window could not be taken")
                failures += 1
                continue
            }
            // The sidebar's chosen page, which its list draws brighter while
            // it holds the keyboard, as a list made anew may not: the rest
            // of the window is compared.
            let scale = CGFloat(before.width) / max(window.frame.width, 1)
            let rows = [chosenBefore, chosenPage(window)].compactMap { $0 }.map { row in
                CGRect(x: row.minX * scale, y: (window.frame.height - row.maxY) * scale,
                       width: row.width * scale, height: row.height * scale).insetBy(dx: -2, dy: -2)
            }
            let change = WindowPicture.change(from: before, to: after, apart: rows)
            let same = change.share <= WindowPicture.alike
            say("\(same ? "✓" : "✗") the builder after the console, in \(mode) mode, against the builder before it: \(change)")
            if !same { failures += 1 }
        }
        NSApp.appearance = nil
        if consoles.count == 2 {
            let change = WindowPicture.change(from: consoles[0].picture, to: consoles[1].picture)
            let same = change.share <= WindowPicture.alike
            say("\(same ? "✓" : "✗") the console in dark mode, against the console in light mode: \(change)")
            if !same { failures += 1 }
        } else {
            say("✗ the console could not be taken in both modes")
            failures += 1
        }
        return failures
    }

    /// The window as the window server shows it, as the player sees it:
    /// what SwiftUI drew last, not drawn again for the picture; nil, said,
    /// when ScreenCaptureKit cannot take it within twenty seconds.
    private static func picture(of window: NSWindow) async -> CGImage? {
        let number = CGWindowID(window.windowNumber)
        return await withCheckedContinuation { (answer: CheckedContinuation<CGImage?, Never>) in
            let once = Once(answer)
            Task { @MainActor in
                do {
                    // The app's own windows, which need no permission to
                    // record the screen.
                    let content = try await SCShareableContent.currentProcess
                    guard let shown = content.windows.first(where: { $0.windowID == number }) else {
                        say("    ScreenCaptureKit does not list the window")
                        once.give(nil)
                        return
                    }
                    let filter = SCContentFilter(desktopIndependentWindow: shown)
                    let configuration = SCStreamConfiguration()
                    let scale = CGFloat(filter.pointPixelScale)
                    configuration.width = Int((filter.contentRect.width * scale).rounded())
                    configuration.height = Int((filter.contentRect.height * scale).rounded())
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    once.give(image)
                } catch {
                    say("    ScreenCaptureKit: \(error.localizedDescription)")
                    once.give(nil)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if once.give(nil) { say("    ScreenCaptureKit did not answer within twenty seconds") }
            }
        }
    }

    /// Where the sidebar's chosen page is, in the window's points from its
    /// bottom left.
    private static func chosenPage(_ window: NSWindow) -> CGRect? {
        guard let root = window.contentView,
              let list = descendants(of: root).compactMap({ $0 as? NSOutlineView }).first(where: { !$0.isHiddenOrHasHiddenAncestor }),
              list.selectedRow >= 0 else { return nil }
        return list.convert(list.rect(ofRow: list.selectedRow), to: nil)
    }

    /// An answer given once, the first that comes.
    @MainActor
    private final class Once {
        private var answer: CheckedContinuation<CGImage?, Never>?

        init(_ answer: CheckedContinuation<CGImage?, Never>) {
            self.answer = answer
        }

        /// Whether it was the first.
        @discardableResult
        func give(_ picture: CGImage?) -> Bool {
            guard let answer else { return false }
            self.answer = nil
            answer.resume(returning: picture)
            return true
        }
    }

    /// An arrow key in the sidebar, as the player presses it: the window
    /// sends it to the list, which SwiftUI follows.
    private static func arrowKey(_ window: NSWindow, down: Bool) {
        guard let root = window.contentView, let list = descendants(of: root).compactMap({ $0 as? NSOutlineView }).first else { return }
        window.makeFirstResponder(list)
        let character = down ? String(UnicodeScalar(NSDownArrowFunctionKey)!) : String(UnicodeScalar(NSUpArrowFunctionKey)!)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                           characters: character, charactersIgnoringModifiers: character, isARepeat: false,
                                           keyCode: down ? 125 : 126) else { return }
        window.sendEvent(event)
    }

    /// What is wrong when the page shown is not the one the sidebar chose.
    private static func followed(_ window: NSWindow, _ model: AppModel) -> String? {
        guard let root = window.contentView, let list = descendants(of: root).compactMap({ $0 as? NSOutlineView }).first else {
            return "the sidebar has no list"
        }
        let row = list.selectedRow
        guard AppSection.allCases.indices.contains(row) else { return "the sidebar chose no page (row \(row))" }
        let chosen = AppSection.allCases[row]
        return chosen == model.section ? nil : "the sidebar chose \(chosen.rawValue), the page shown is \(model.section.rawValue)"
    }

    /// How many times SwiftUI wrote in this process's log, since BEGAN, that
    /// a change was published while it updated the views; nil when the log
    /// cannot be read.
    private static func publishedInUpdates(since began: Date) -> Int? {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: began),
                                                  matching: NSPredicate(format: "subsystem == %@", "com.apple.runtime-issues")) else { return nil }
        return entries.compactMap { $0 as? OSLogEntryLog }.filter { $0.composedMessage.contains("from within view updates") }.count
    }

    /// The window the app opens, once it is on the screen.
    private static func mainWindow() async -> NSWindow? {
        for _ in 0..<150 {
            if let window = NSApp.windows.first(where: { $0.isVisible && ($0.identifier?.rawValue.hasPrefix(AppModel.mainWindow) == true || $0.title == "Cartouche Builder") }) {
                try? await Task.sleep(for: .seconds(2))
                return window
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    // MARK: What is checked

    /// What does not fit: a scrolling column (the sidebar's list, a page,
    /// the game's sheet) out of the window, or a sidebar with no pages.
    private static func inspect(_ window: NSWindow) -> [String] {
        guard let root = window.contentView else { return ["the window has no content"] }
        var found: [String] = []
        let width = root.bounds.width
        let height = root.bounds.height
        for scroll in descendants(of: root).compactMap({ $0 as? NSScrollView }) where !scroll.isHiddenOrHasHiddenAncestor && scroll.bounds.width > 0 {
            let frame = scroll.convert(scroll.bounds, to: root)
            if frame.minX < -1 || frame.maxX > width + 1 {
                found.append("\(name(scroll)) spans \(Int(frame.minX))…\(Int(frame.maxX)), out of the window's 0…\(Int(width))")
            }
            if frame.minY < -1 || frame.maxY > height + 1 {
                found.append("\(name(scroll)) spans \(Int(frame.minY))…\(Int(frame.maxY)) in height, out of the window's 0…\(Int(height))")
            }
        }
        if let sidebar = splitController(window)?.splitViewItems.first, sidebar.behavior == .sidebar, !sidebar.isCollapsed {
            let lists = descendants(of: sidebar.viewController.view).compactMap { $0 as? NSTableView }
            let rows = lists.map(\.numberOfRows).max() ?? 0
            let shown = sidebar.viewController.view.bounds.width
            if rows < AppSection.allCases.count || shown < 1 {
                found.append("the sidebar shows \(rows) page\(rows == 1 ? "" : "s") in \(Int(shown)) points")
            }
        }
        return found
    }

    /// Each column of the split view: its kind, its width, its least and
    /// most, and whether it is folded.
    private static func columns(_ window: NSWindow) -> String {
        guard let controller = splitController(window) else { return "no split view" }
        return controller.splitViewItems.map { item in
            let kind: String
            switch item.behavior {
            case .sidebar: kind = "sidebar"
            case .inspector: kind = "inspector"
            default: kind = "content"
            }
            if item.isCollapsed { return "\(kind) folded" }
            let most = item.maximumThickness == NSSplitViewItem.unspecifiedDimension ? "-" : "\(Int(item.maximumThickness))"
            return "\(kind) \(Int(item.viewController.view.frame.width)) [\(Int(item.minimumThickness))…\(most)]"
        }.joined(separator: " | ")
    }

    /// The scrolling views of the window and where they are, to read in the
    /// log.
    private static func scrollViews(_ window: NSWindow) -> String {
        guard let root = window.contentView else { return "" }
        return descendants(of: root).compactMap { $0 as? NSScrollView }.filter { !$0.isHiddenOrHasHiddenAncestor }.map { scroll in
            let frame = scroll.convert(scroll.bounds, to: root)
            return "\(name(scroll)) \(Int(frame.minX))…\(Int(frame.maxX))"
        }.joined(separator: ", ")
    }

    /// The least width of the sidebar, each page and the game's sheet, as
    /// SwiftUI lays them out, against what their columns leave them
    /// (Columns): the number of them that need more. A page that scrolls
    /// needs only what its scroll view does: what does not fit in it, the
    /// gallery's game-narrow page shows.
    private static func measure(_ model: AppModel, chosen: String?) -> Int {
        func least<Content: View>(_ content: Content) -> CGFloat {
            let controller = NSHostingController(rootView: content
                .environmentObject(model)
                .environmentObject(model.setup)
                .environmentObject(model.bridge)
                .environmentObject(model.covers)
                .environmentObject(model.updater)
                .environmentObject(model.telemetry))
            return controller.sizeThatFits(in: CGSize(width: 0, height: 700)).width.rounded(.up)
        }
        // Beside the sidebar at its widest, a page has the rest of the
        // window; the library, with the game's sheet, less.
        let page = Columns.window.width - Columns.sidebar.most
        var parts: [(String, CGFloat, CGFloat)] = [
            ("sidebar", least(Sidebar()), Columns.sidebar.least),
            ("library", least(LibraryView()), Columns.page),
            ("builds", least(ActivityView()), page),
            ("storage", least(StorageView()), page),
            ("iPhone", least(BridgeView()), page),
            ("tools", least(SetupView()), page),
        ]
        if let game = model.game(chosen) {
            parts.append(("game's sheet", least(GameDetailView(game: game)), Columns.sheet))
            model.selection = chosen
            parts.append(("library with the game's sheet", least(LibraryView()), page))
            model.selection = nil
        }
        var failures = 0
        for (name, width, room) in parts {
            let fits = width <= room
            if !fits { failures += 1 }
            say("\(fits ? "✓" : "✗") \(name) needs \(Int(width)) points, its column leaves it \(Int(room))")
        }
        return failures
    }

    // MARK: Helpers

    private static func splitController(_ window: NSWindow) -> NSSplitViewController? {
        func search(_ controller: NSViewController?) -> NSSplitViewController? {
            guard let controller else { return nil }
            if let split = controller as? NSSplitViewController { return split }
            for child in controller.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        if let found = search(window.contentViewController) { return found }
        guard let root = window.contentView else { return nil }
        for view in descendants(of: root) {
            if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController { return controller }
        }
        return nil
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func name(_ view: NSView) -> String {
        let kind = String(describing: Swift.type(of: view))
        if let document = (view as? NSScrollView)?.documentView {
            return "\(kind)(\(String(describing: Swift.type(of: document))))"
        }
        return kind
    }

    static func say(_ text: String) {
        FileHandle.standardError.write(Data("layout-check: \(text)\n".utf8))
    }
}

/// An exception that ends the app, said before it does.
private func sayException(_ exception: NSException) {
    FileHandle.standardError.write(Data("layout-check: ✗ \(exception.name.rawValue): \(exception.reason ?? "")\n".utf8))
}

/// How far one picture of the window is from another of the same window.
enum WindowPicture {
    /// The share of the pixels that may change between two pictures of the
    /// same page, once it has settled: none should, but a word that says
    /// how long ago something happened may tick over between them. A word
    /// of a dozen letters in the system's font is about 0.03 % of a window
    /// of 1024 × 700 points.
    static let alike = 0.001

    /// The pixels whose lightness changed by more than a quarter between two
    /// pictures, and where they are.
    struct Change: CustomStringConvertible {
        /// Their share of the picture's pixels.
        let share: Double
        /// Their bounds, in the picture's pixels from its top left.
        let area: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        let width: Int
        let height: Int

        var description: String {
            let percent = String(format: "%.3f %%", share * 100)
            guard let area else { return "\(percent) of its pixels changed" }
            return "\(percent) of its pixels changed, within x \(area.minX)…\(area.maxX) and y \(area.minY)…\(area.maxY) of \(width) × \(height)"
        }
    }

    /// The change from FIRST to SECOND, but in the rectangles APART, in the
    /// pictures' pixels from their top left.
    static func change(from first: CGImage, to second: CGImage, apart: [CGRect] = []) -> Change {
        let width = first.width
        let height = first.height
        guard second.width == width, second.height == height, width > 0, height > 0 else {
            return Change(share: 1, area: nil, width: second.width, height: second.height)
        }
        let a = lightness(first)
        let b = lightness(second)
        var changed = 0
        var area: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in 0..<height {
            for x in 0..<width where abs(Int(a[y * width + x]) - Int(b[y * width + x])) > 64 {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                if apart.contains(where: { $0.contains(point) }) { continue }
                changed += 1
                if let found = area {
                    area = (min(found.minX, x), min(found.minY, y), max(found.maxX, x), max(found.maxY, y))
                } else {
                    area = (x, y, x, y)
                }
            }
        }
        return Change(share: Double(changed) / Double(width * height), area: area, width: width, height: height)
    }

    /// Each pixel's lightness, 0 to 255, from the top left, row by row.
    private static func lightness(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (0..<(width * height)).map { index in
            let pixel = index * 4
            return UInt8((Int(rgba[pixel]) * 54 + Int(rgba[pixel + 1]) * 183 + Int(rgba[pixel + 2]) * 19) >> 8)
        }
    }
}

