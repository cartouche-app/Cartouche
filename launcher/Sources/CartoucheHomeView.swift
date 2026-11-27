//
//  CartoucheHomeView.swift
//  Cartouche
//
//  The console's home: the player's games on one shelf, installed or in
//  their games folder, then the covers that import a game and open every
//  game; the game in focus described with its main action, and a dock to
//  the rest of Cartouche. The stage takes the colours of the game in focus.
//  The games nxnative plays on the iPhone are in All games, not here.
//
//  Touch and a game controller both drive it. A tap puts a game in focus,
//  a second tap opens its sheet; with a controller, the D-pad moves, A
//  does the main action of the game in focus, X opens its sheet, Y every
//  game and Menu the system page. While a controller is connected, the
//  buttons on screen show the controller's button that does the same.
//  VoiceOver says which cover, or which item of the dock, is in focus.
//
//  The layout follows the space the screen gives it, never the iPhone
//  model: one column when the screen is taller than wide (an iPhone, the
//  iPhone Duo folded or unfolded upright), with the dock at the bottom;
//  the shelf beside the game in focus when it is wider, with the dock in
//  the top bar. The covers take the size that lets it all fit the screen,
//  down to a size under which the home scrolls instead, and the shelf and
//  the game in focus stand in the middle of the room left, as a console's.
//
//  Beside the sheet of the game in focus, on an iPhone Duo unfolded
//  (CartoucheGamesView), the home leaves out the game in focus, which the
//  sheet describes in full, and its shelf takes the room.
//
//  While the player has games installed and games not installed, whose
//  IPA is on their Mac, in a games folder or in Cartouche Cloud, a menu
//  beside the shelf's title shows them all, those installed or those not
//  installed, and the controller's shoulder buttons go from one to the
//  next (CartoucheHomeFilter.swift).
//
//  A game paused behind the console (CartoucheGameHost) has a pause badge
//  on its cartridge, Resume as its main action and Quit beside it; the
//  focus goes to it each time the console comes back over it.
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheHomeView: View {
    let entries: CartoucheCatalog.Entries
    let gameCount: Int
    /// Whether the home is on screen, with nothing over it, so that it
    /// takes the controller.
    let isActive: Bool
    let onPlay: (LCAppModel) -> Void
    let onImport: () -> Void
    /// Installs a game from the player's games folder.
    let onInstall: (CartoucheStoredGame) -> Void
    /// Installs a game Cartouche Cloud built for the player.
    let onInstallCloud: (CartoucheCloudBuilt) -> Void
    let onUninstall: (LCAppModel) -> Void
    let onSheet: (CartoucheEntry) -> Void
    let onLibrary: () -> Void
    let onSetup: () -> Void
    /// Opens the first game's guide (CartoucheGuideView).
    let onGuide: () -> Void
    let onTab: (LCTabIdentifier) -> Void
    /// Where a game's sheet grows out of its cartridge.
    let zoom: Namespace.ID?
    /// Whether the game in focus is described with its buttons between the
    /// shelves, or beside them: not when its sheet stands beside the home.
    let showsHero: Bool
    /// Tells which cover of the shelf is in focus, each time another one
    /// is: a game's, the one that imports a game or the one for every game.
    let onFocus: (Item) -> Void

    /// The game in focus as the home opens, by its entry's ID, when it is
    /// not the first: the Mac's gallery opens the console on a game's sheet
    /// (builder/mac, ConsoleView.swift).
    let focusing: String?

    // Written out: before Swift 6.4 (SE-0502), the private state below made
    // the synthesized initializer private.
    init(entries: CartoucheCatalog.Entries, gameCount: Int, isActive: Bool,
         onPlay: @escaping (LCAppModel) -> Void, onImport: @escaping () -> Void,
         onInstall: @escaping (CartoucheStoredGame) -> Void = { _ in },
         onInstallCloud: @escaping (CartoucheCloudBuilt) -> Void = { _ in },
         onUninstall: @escaping (LCAppModel) -> Void, onSheet: @escaping (CartoucheEntry) -> Void,
         onLibrary: @escaping () -> Void, onSetup: @escaping () -> Void, onGuide: @escaping () -> Void = {},
         onTab: @escaping (LCTabIdentifier) -> Void, zoom: Namespace.ID? = nil,
         showsHero: Bool = true, focusing: String? = nil, onFocus: @escaping (Item) -> Void = { _ in }) {
        self.entries = entries
        self.gameCount = gameCount
        self.isActive = isActive
        self.onPlay = onPlay
        self.onImport = onImport
        self.onInstall = onInstall
        self.onInstallCloud = onInstallCloud
        self.onUninstall = onUninstall
        self.onSheet = onSheet
        self.onLibrary = onLibrary
        self.onSetup = onSetup
        self.onGuide = onGuide
        self.onTab = onTab
        self.zoom = zoom
        self.showsHero = showsHero
        self.focusing = focusing
        self.onFocus = onFocus
    }

    @ObservedObject private var setup = CartoucheSetup.shared
    @ObservedObject private var guide = CartoucheGuide.shared
    @ObservedObject private var gamepad = CartoucheGamepad.shared
    @ObservedObject private var actions = CartoucheGameActions.shared
    @ObservedObject private var reach = CartoucheStorageReach.shared
    /// A renewal, as Cartouche renews itself in its last days: the days
    /// left go once it ends.
    @ObservedObject private var renewals = CartoucheRenewals.shared
    @Environment(\.openURL) private var openURL
    @State private var row = CartoucheHomeView.shelfRow
    @State private var columns = [0, 0]
    @State private var signature = CartoucheSignature.current()
    /// Whether the shelf stands beside the game in focus, with the dock in
    /// the top bar, so that the D-pad goes up to the dock.
    @State private var isWide = false
    /// The height of the banner over the shelf, the guide's card or the
    /// setup banner, as last laid out: its detail can take one line or two,
    /// as the guide's does on an iPhone upright (Metrics).
    @State private var bannerHeight: CGFloat?
    /// Which of the player's games the shelf shows, as they chose last, and
    /// the games it keeps there, changed together.
    @State private var choice = CartoucheHomeShelfChoice(filter: CartoucheHomeFilter.saved())

    enum Item: Hashable {
        case game(CartoucheEntry)
        case importGame
        case allGames
        case dock(Dock)
    }

    /// Cartouche's own pages only: LiveContainer's and the built-in
    /// SideStore's never show (docs/decisions.md, 24).
    enum Dock: CaseIterable, Hashable {
        case allGames, importGame, system
    }

    /// The signature's days left from which the top bar shows them: before,
    /// renewals take care of it and the System page says when it expires.
    static let expirySoonDays = 3
    /// The width from which the top bar names a server that is offline:
    /// an upright iPhone shows its symbol alone.
    private static let offlineNameWidth: CGFloat = 600

    /// The rows the focus moves along: the shelf, then the dock.
    private static let shelfRow = 0
    private static let dockRow = 1

    /// The player's games, installed or in their games folder, those the
    /// filter shows, then the covers that import one and open every game.
    /// The games nxnative plays on the iPhone are in All games, under their
    /// filter.
    private var libraryShelf: [Item] {
        shelfGames.map(Item.game) + [.importGame, .allGames]
    }

    /// The player's games as the filter reads them.
    private var filterGames: [CartoucheHomeShelfGame] {
        entries.owned.map { entry in
            CartoucheHomeShelfGame(key: Self.shelfKey(entry), isInstalled: entry.isInstalled,
                                   isRunning: actions.isRunning(entry.app))
        }
    }

    /// The player's games the shelf shows.
    private var shelfGames: [CartoucheEntry] {
        CartoucheHomeShelf.shown(filterGames, filter: filter, kept: choice.kept).map { entries.owned[$0] }
    }

    /// The filter the player chose.
    private var filter: CartoucheHomeFilter { choice.filter }

    /// Whether the home offers the filter: the player has games installed
    /// and games not installed.
    private var offersFilter: Bool { CartoucheHomeShelf.offersFilter(filterGames) }

    /// What tells a game apart on the shelf, the same once it is installed
    /// or uninstalled, as its entry's ID is not: its title ID, else its
    /// bundle ID.
    static func shelfKey(_ entry: CartoucheEntry) -> String {
        entry.titleId ?? entry.app?.appInfo.bundleIdentifier() ?? entry.stored?.bundleId ?? entry.id
    }

    private var rows: [[Item]] {
        [libraryShelf, Dock.allCases.map(Item.dock)]
    }

    /// The rows from the top of the screen to the bottom: the dock is in
    /// the top bar when the shelf stands beside the game in focus.
    private var visualRows: [Int] {
        isWide ? [Self.dockRow, Self.shelfRow] : [Self.shelfRow, Self.dockRow]
    }

    private func item(row: Int) -> Item? {
        let items = rows[row]
        guard !items.isEmpty else { return nil }
        return items[min(columns[row], items.count - 1)]
    }

    private var focused: Item? { item(row: row) }

    /// What the description of the game in focus shows: the shelf's, which
    /// stays when the focus is on the dock.
    private var hero: Item? { item(row: Self.shelfRow) }

    var body: some View {
        GeometryReader { proxy in
            // Until the first game is installed, the guide's card stands in
            // the setup banner's place, whose steps it begins with.
            let guideProgress = guide.progress(entries)
            let showsGuide = guide.showsCard(guideProgress)
            let metrics = Metrics(size: proxy.size, hasBanner: showsGuide || setup.showsBanner, hasHero: showsHero,
                                  measuredBanner: bannerHeight, hasFilter: offersFilter)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: metrics.spacing) {
                    topBar(metrics)
                    Group {
                        if showsGuide {
                            CartoucheGuideCard(progress: guideProgress, action: onGuide)
                        } else if setup.showsBanner {
                            CartoucheHomeSetupBanner(action: onSetup)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bannerHeight = $0 }
                    shelfAndHero(metrics)
                        // In the middle of the room the screen leaves them.
                        .padding(.top, metrics.slack / 2)
                }
                .padding(.horizontal, metrics.margin)
                .padding(.vertical, metrics.verticalPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // Upright, the dock stays at the bottom; the shelf scrolls under
            // it only where the screen is too short for its smallest size.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !metrics.isWide {
                    dock(compact: false, labels: true)
                        .padding(.horizontal, metrics.margin)
                        .padding(.top, Metrics.dockTopPadding)
                        .padding(.bottom, Metrics.dockBottomPadding)
                        .background {
                            LinearGradient(colors: [CartoucheTheme.stage.opacity(0), CartoucheTheme.stage.opacity(0.88)],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                                .ignoresSafeArea(edges: .bottom)
                        }
                }
            }
            .onAppear { isWide = metrics.isWide }
            .onChange(of: metrics.isWide) { _, wide in isWide = wide }
        }
        .background(CartoucheStage(key: heroKey, art: heroBackdrop))
        // The game it opens on, the shelf scrolled to it.
        .onAppear {
            if let focusing, let column = shelfGames.firstIndex(where: { $0.id == focusing }) {
                focus(row: Self.shelfRow, column: column)
            }
        }
        // The games the shelf shows while the filter leaves some out stay
        // there, installed or uninstalled, until the player chooses a
        // filter again; the focus stays on its game, or on its cover after
        // the games, as the shelf changes.
        .onChange(of: shelfGames.map(Self.shelfKey), initial: true) { before, after in
            var next = choice
            next.shelfShows(after, offersFilter: offersFilter)
            if next != choice { choice = next }
            guard before != after else { return }
            columns[Self.shelfRow] = CartoucheHomeShelf.column(columns[Self.shelfRow], from: before, to: after)
        }
        .onChange(of: hero) { _, hero in
            if let hero { onFocus(hero) }
        }
        // Back from the game behind the console: the focus on it, with
        // Resume under A.
        .onChange(of: actions.running?.isInFront) { _, inFront in
            guard inFront == false, let column = libraryShelf.firstIndex(where: { item in
                if case .game(let entry) = item { return actions.isRunning(entry.app) }
                return false
            }) else { return }
            focus(row: Self.shelfRow, column: column)
        }
        .onReceive(gamepad.inputs) { input in
            if isActive { handle(input) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            signature = CartoucheSignature.current()
        }
        .onChange(of: renewals.isRenewing) { _, renewing in
            if !renewing { signature = CartoucheSignature.current() }
        }
    }

    private var heroKey: String? {
        if case .game(let entry) = hero { return entry.tileKey }
        return nil
    }

    private var heroBackdrop: CartoucheArt? {
        if case .game(let entry) = hero { return entry.backdrop }
        return nil
    }

    // MARK: Top bar

    private func topBar(_ metrics: Metrics) -> some View {
        HStack(spacing: 10) {
            CartoucheWordmark(size: metrics.isShort ? 22 : 24)
            Spacer(minLength: 8)
            if gamepad.isConnected {
                Image(systemName: "gamecontroller.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CartoucheTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .cartoucheGlass(in: Capsule())
                    .accessibilityLabel(Text(CartoucheText.controllerConnected))
            }
            // A server of the player's that does not answer from here, as
            // their NAS away from home: the System page says which, and its
            // Storage page tries it again. Its name shows where the bar has
            // room for it beside the wordmark; on an upright iPhone, the
            // symbol alone, as the controller's.
            if let offline = reach.offlineInUse.first {
                // A Google Drive whose sign-in Google ended says so, the
                // same way: its Storage page signs in again. One that only
                // Tailscale reaches says to turn it on.
                let away = CartoucheStorageOffline(offline, tailscale: reach.tailscaleConnected)
                Button {
                    onTab(.system)
                } label: {
                    Group {
                        if metrics.size.width >= Self.offlineNameWidth {
                            Label(away.short, systemImage: away.symbol)
                                .labelStyle(CartoucheTightLabelStyle())
                        } else {
                            Image(systemName: away.symbol)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .cartoucheGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(away.title))
            } else if CartoucheTailscaleReminder.shows(turnedOff: reach.tailscaleTurnedOff, tailscaleOn: reach.tailscaleConnected,
                                                       busy: renewals.isRenewing, at: Date()) {
                // LocalDevVPN, which Cartouche connected for a renewal, a
                // sign-in or an update, turned Tailscale off: once that is
                // done, until Tailscale is on again. Tailscale's page of the
                // App Store opens it, as it has no link of its own. Its
                // words where the bar has room for them, as a server
                // offline; on an upright iPhone, the symbol alone.
                Button {
                    openURL(CartoucheTailscale.appStore)
                } label: {
                    Group {
                        if metrics.size.width >= Self.offlineNameWidth {
                            Label(CartoucheText.tailscaleTurnedOffShort, systemImage: "network")
                                .labelStyle(CartoucheTightLabelStyle())
                        } else {
                            Image(systemName: "network")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .cartoucheGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(CartoucheText.tailscaleTurnedOff))
            }
            // Renewals keep Cartouche signed: its expiry shows here only
            // when it comes close, and leads to the System page.
            if let days = signature.daysLeft, days <= Self.expirySoonDays {
                Button {
                    onTab(.system)
                } label: {
                    Label(CartoucheText.daysLeftShort(max(days, 0)), systemImage: "hourglass")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .labelStyle(CartoucheTightLabelStyle())
                        .foregroundStyle(days <= 1 ? CartoucheTheme.danger : Color.orange)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .cartoucheGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(CartoucheText.expires))
                .accessibilityValue(Text(CartoucheText.daysLeftShort(max(days, 0))))
            }
            if metrics.isWide {
                dock(compact: true, labels: metrics.size.width >= 700)
            }
        }
        .frame(minHeight: Metrics.topBarHeight)
    }

    // MARK: Shelf

    /// The shelf and the game in focus: side by side on a wide screen, the
    /// game under the shelf on an upright one, and the shelf alone beside a
    /// game's sheet.
    @ViewBuilder
    private func shelfAndHero(_ metrics: Metrics) -> some View {
        let library = shelf(title: CartoucheText.homeLibrary, width: metrics.tile)
        if !showsHero {
            library
        } else if metrics.isWide {
            HStack(alignment: .top, spacing: metrics.columnGap) {
                library
                    .frame(width: metrics.shelfWidth, alignment: .leading)
                    // The shelf ends at its column, the covers past it fading
                    // out in the gap rather than running under the game in
                    // focus; above, below and on the left, the focused
                    // cover's ring and glow still show.
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: metrics.shelfFadeStart),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .padding(.vertical, -metrics.tile * 0.5)
                            .padding(.leading, -metrics.margin)
                            .padding(.trailing, -metrics.columnGap)
                    }
                heroView(metrics)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: metrics.spacing) {
                library
                heroView(metrics)
            }
        }
    }

    private func shelf(title: String, width: CGFloat) -> some View {
        let index = Self.shelfRow
        let items = rows[index]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(CartoucheTheme.secondaryText)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if offersFilter {
                    Spacer(minLength: 8)
                    filterMenu
                }
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: max(10, width * 0.12)) {
                        ForEach(Array(items.enumerated()), id: \.element) { column, item in
                            let isFocused = row == index && columns[index] == column
                            tile(item, width: width, isFocused: isFocused)
                                .id(item)
                                // VoiceOver says which cover is in focus: the
                                // one A, Play and Details act on.
                                .accessibilityAddTraits(isFocused ? .isSelected : [])
                                .onTapGesture { tapped(item, row: index, column: column) }
                        }
                    }
                    // Room for the focused game's ring and glow.
                    .padding(.vertical, width * 0.1)
                    .padding(.horizontal, width * 0.06)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // The height Metrics counts for the shelf: its covers and the
                // room for the focused one's ring, which a horizontal scroll
                // view did not always keep beside the game in focus.
                .frame(height: width * Metrics.tileHeight)
                .onChange(of: columns[index]) { _, column in
                    guard row == index, column < items.count else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        reader.scrollTo(items[column], anchor: .center)
                    }
                }
            }
            .padding(.horizontal, -width * 0.06)
        }
    }

    /// The filter: the one chosen, in the brand's colours when it leaves
    /// games out, with the controller's shoulder buttons around it while one
    /// is connected; a tap opens the menu of the three.
    private var filterMenu: some View {
        Menu {
            Picker(CartoucheText.hintFilter, selection: Binding(get: { filter }, set: { choose($0, byController: false) })) {
                ForEach(CartoucheHomeFilter.allCases, id: \.self) { item in
                    Label(Self.title(item), systemImage: Self.symbol(item))
                        .tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: gamepad.isConnected ? gamepad.symbol(for: .previous) : "line.3.horizontal.decrease")
                Text(Self.title(filter))
                    .lineLimit(1)
                if gamepad.isConnected {
                    Image(systemName: gamepad.symbol(for: .next))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(filter == .all ? CartoucheTheme.secondaryText : Color.white)
            .padding(.horizontal, 10)
            .frame(height: Metrics.filterHeight)
            .background {
                if filter != .all {
                    Capsule().fill(CartoucheTheme.brand)
                }
            }
            .cartoucheGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(CartoucheText.hintFilter))
        .accessibilityValue(Text(Self.title(filter)))
    }

    static func title(_ filter: CartoucheHomeFilter) -> String {
        switch filter {
        case .all: return CartoucheText.filterAll
        case .installed: return CartoucheText.homeFilterInstalled
        case .notInstalled: return CartoucheText.homeFilterNotInstalled
        }
    }

    static func symbol(_ filter: CartoucheHomeFilter) -> String {
        switch filter {
        case .all: return "square.stack.fill"
        case .installed: return "checkmark.circle.fill"
        case .notInstalled: return "arrow.down.circle"
        }
    }

    /// The player chose FILTER, from the menu or with the controller's
    /// shoulder buttons: kept, and the shelf shows its games from now on,
    /// the focus staying on its game where it is still there.
    private func choose(_ new: CartoucheHomeFilter, byController: Bool) {
        guard new != filter else { return }
        new.save()
        // What it shows from now on, which stays there, in the same change
        // as the filter.
        var chosen = choice
        chosen.choose(new, among: filterGames)
        withAnimation(.easeInOut(duration: 0.2)) { choice = chosen }
        CartoucheTelemetry.shared.event(CartoucheHomeFilter.event, fields: new.fields(byController: byController))
    }

    @ViewBuilder
    private func tile(_ item: Item, width: CGFloat, isFocused: Bool) -> some View {
        switch item {
        case .game(let entry):
            CartoucheGameCartridge(entry: entry, width: width, isFocused: isFocused, isPaused: actions.isRunning(entry.app))
                .cartoucheZoomSource(entry.id, in: zoom)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text(CartoucheText.details)) { onSheet(entry) }
                .contextMenu { gameMenu(entry) }
        case .importGame:
            CartoucheImportCartridge(width: width, isFocused: isFocused)
        case .allGames:
            CartoucheAllGamesCartridge(width: width, count: gameCount, isFocused: isFocused)
        case .dock:
            EmptyView()
        }
    }

    /// A long press on a game: what its sheet offers, the game's settings
    /// being in the sheet.
    @ViewBuilder
    private func gameMenu(_ entry: CartoucheEntry) -> some View {
        if let app = entry.app, actions.isRunning(app) {
            Button { onPlay(app) } label: { Label(CartoucheText.resume, systemImage: "play.fill") }
            Button(role: .destructive) { actions.askToQuit() } label: { Label(CartoucheText.quit, systemImage: "stop.circle") }
        } else if let app = entry.app {
            Button { onPlay(app) } label: { Label(CartoucheText.play, systemImage: "play.fill") }
            if let update = entry.update {
                Button { onInstall(update) } label: { Label(updateTitle(update), systemImage: "arrow.down.circle.fill") }
            }
        } else if let stored = entry.stored {
            Button { onInstall(stored) } label: { Label(installTitle(stored), systemImage: "arrow.down.circle.fill") }
        } else if let cloud = entry.cloud {
            Button { onInstallCloud(cloud) } label: { Label(CartoucheText.cloudInstall, systemImage: "icloud.and.arrow.down.fill") }
        } else {
            Button(action: onImport) { Label(CartoucheText.importCopy, systemImage: "square.and.arrow.down") }
        }
        Button { onSheet(entry) } label: { Label(CartoucheText.details, systemImage: "info.circle") }
        if let app = entry.app, !actions.isRunning(app) {
            Divider()
            Button(role: .destructive) { onUninstall(app) } label: { Label(CartoucheText.uninstall, systemImage: "trash") }
        }
    }

    // MARK: The game in focus

    /// The game in focus, at the same height whatever it is, so that the
    /// home stays in place as the focus moves.
    @ViewBuilder
    private func heroView(_ metrics: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch hero {
            case .game(let entry):
                gameHero(entry, metrics: metrics)
            case .importGame:
                heroText(CartoucheText.importTile, CartoucheText.emptyMessage, metrics: metrics)
                // Side by side where they fit, the one over the other
                // otherwise.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { importActions }
                    VStack(alignment: .leading, spacing: 10) { importActions }
                }
            case .allGames:
                heroText(CartoucheText.allGames, CartoucheText.allGamesDetail(gameCount), metrics: metrics)
                actionButton(CartoucheText.allGames, systemImage: "square.grid.2x2.fill", primary: true,
                             input: .a, action: onLibrary)
            case .dock, nil:
                EmptyView()
            }
        }
        .frame(maxWidth: 560, minHeight: metrics.isWide ? nil : metrics.heroHeight, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: hero)
    }

    /// Import a game's buttons: Files, and, while the player has no game,
    /// the guide, for a player with no IPA to import, who opens Files and
    /// finds nothing there.
    @ViewBuilder
    private var importActions: some View {
        actionButton(CartoucheText.importCopy, systemImage: "square.and.arrow.down", primary: true,
                     input: .a, action: onImport)
        if hasNoGame {
            actionButton(CartoucheText.howToGetGame, systemImage: "questionmark.circle", primary: false, input: .x) {
                CartoucheOffer.howToGetGame.tapped(at: .home)
                onGuide()
            }
        }
    }

    /// No game installed, in the games folders or built by Cartouche
    /// Cloud.
    private var hasNoGame: Bool { entries.owned.isEmpty }

    private func heroTitle(_ title: String, metrics: Metrics) -> some View {
        Text(title)
            .font(.system(size: metrics.titleSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    private func heroText(_ title: String, _ detail: String, metrics: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heroTitle(title, metrics: metrics)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(CartoucheTheme.secondaryText)
                .lineLimit(metrics.detailLines)
        }
    }

    private func gameHero(_ entry: CartoucheEntry, metrics: Metrics) -> some View {
        let status = CartouchePlayStatus.of(entry, in: actions)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                heroTitle(entry.name, metrics: metrics)
                CartoucheMetaLine(entry: entry, isPaused: actions.isRunning(entry.app))
                CartoucheGameStatsLine(entry: entry)
                if let detail = heroDetail(status, entry: entry) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(CartoucheTheme.secondaryText)
                        .lineLimit(metrics.detailLines)
                }
            }
            // With an update besides, the other buttons show only their
            // symbols when their names do not fit.
            ViewThatFits(in: .horizontal) {
                gameActions(entry, compact: 0)
                gameActions(entry, compact: 1)
                gameActions(entry, compact: 2)
            }
        }
    }

    /// The line under the badges: what stops the game, or what the player
    /// can do with it. A game ready to play needs none: its badge says so.
    /// A game of the games folders whose copy offered is on a server that
    /// does not answer from here, as every copy of it is: it installs once
    /// one does.
    private func heroDetail(_ status: CartouchePlayStatus, entry: CartoucheEntry) -> String? {
        let stored = CartoucheStoredGames.shared
        let copy = entry.update ?? entry.stored
        let offline = copy?.isOffline ?? false
        let signedOut = copy.map { stored.isSignedOut($0) } ?? false
        let serverName = stored.place(of: copy)
        switch status {
        case .ready, .update:
            if !setup.canPlay {
                return setup.bannerDetail(signingInAgain: CartoucheAccount.shared.isAutomatic)
            }
            guard status == .update else { return nil }
            guard offline else { return status.long }
            return signedOut ? CartoucheText.statusUpdateSignedOut(serverName) : CartoucheText.statusUpdateOffline(serverName)
        case .stored where offline:
            return signedOut ? CartoucheText.statusStoredSignedOut(serverName) : CartoucheText.statusStoredOffline(serverName)
        case .paused where actions.running?.pausedForController == true:
            // It lost its last controller (CartoucheControllerPause).
            return CartoucheText.pausedForController
        default:
            return status.long
        }
    }

    /// The buttons of the game in focus; with COMPACT, its last ones show
    /// only their symbols: Details at 1, Update or Quit and Details at 2.
    /// Quit's symbol is a stop sign: a cross would read as a controller's
    /// button, the X that opens Details or a PlayStation's ✕ that resumes.
    private func gameActions(_ entry: CartoucheEntry, compact: Int) -> some View {
        HStack(spacing: 10) {
            if let app = entry.app, actions.isRunning(app) {
                actionButton(CartoucheText.resume, systemImage: "play.fill", primary: true, input: .a) { onPlay(app) }
                actionButton(CartoucheText.quit, systemImage: "stop.circle", primary: false,
                             iconOnly: compact >= 2) { actions.askToQuit() }
            } else if let app = entry.app {
                actionButton(CartoucheText.play, systemImage: "play.fill", primary: true, input: .a) { onPlay(app) }
                if let update = entry.update {
                    actionButton(CartoucheText.updateGame, systemImage: "arrow.down.circle.fill", primary: false,
                                 iconOnly: compact >= 2) { onInstall(update) }
                }
            } else if let stored = entry.stored {
                actionButton(installTitle(stored), systemImage: "arrow.down.circle.fill", primary: true, input: .a) { onInstall(stored) }
            } else if let cloud = entry.cloud {
                actionButton(CartoucheText.cloudInstall, systemImage: "icloud.and.arrow.down.fill", primary: true,
                             input: .a) { onInstallCloud(cloud) }
            } else {
                actionButton(CartoucheText.importCopy, systemImage: "square.and.arrow.down", primary: true,
                             input: .a, action: onImport)
            }
            actionButton(CartoucheText.details, systemImage: "info.circle", primary: false,
                         iconOnly: compact >= 1, input: .x) { onSheet(entry) }
        }
    }

    /// Install from the player's games folder, naming the server of the
    /// copy offered: one that answers, of a game in several folders.
    private func installTitle(_ copy: CartoucheStoredGame) -> String {
        CartoucheText.installFrom(CartoucheStoredGames.shared.place(of: copy))
    }

    /// Update from the player's games folder, naming the server of the copy.
    private func updateTitle(_ copy: CartoucheStoredGame) -> String {
        CartoucheText.updateFrom(CartoucheStoredGames.shared.place(of: copy))
    }

    /// A button of the game in focus. While a controller is connected, it
    /// shows the controller's button that does the same, in place of its
    /// symbol. With its symbol alone (ICONONLY), it is round.
    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, primary: Bool, iconOnly: Bool = false,
                              input: CartoucheGamepad.Input? = nil, action: @escaping () -> Void) -> some View {
        let symbol = gamepad.isConnected ? (input.map { gamepad.symbol(for: $0) } ?? systemImage) : systemImage
        let button = Button(action: action) {
            if iconOnly {
                Label(title, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(minWidth: 30, minHeight: 30)
            } else {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .lineLimit(1)
                    // A long name, such as the server's of Install from,
                    // shrinks a little before it is cut.
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 30)
            }
        }
        .controlSize(.large)
        .buttonBorderShape(iconOnly ? .circle : .automatic)
        if primary {
            button.cartouchePrimaryButton()
        } else {
            button.cartoucheSecondaryButton()
        }
    }

    // MARK: Dock

    /// Every game, import and the System page: a bar at the bottom of an
    /// upright screen, a row of buttons in the top bar of a wide one, with
    /// their names where they fit (LABELS).
    private func dock(compact: Bool, labels: Bool) -> some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(Array(Dock.allCases.enumerated()), id: \.element) { column, item in
                let isFocused = row == Self.dockRow && columns[Self.dockRow] == column
                Button {
                    activate(.dock(item))
                } label: {
                    dockLabel(item, compact: compact, labels: labels, isFocused: isFocused)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Self.title(item)))
                // As on the shelf: the one in focus, which A opens.
                .accessibilityAddTraits(isFocused ? .isSelected : [])
            }
        }
        .padding(compact ? 3 : 5)
        .frame(maxWidth: compact ? nil : CGFloat(440))
        .cartoucheGlass(in: Capsule())
        .frame(maxWidth: compact ? nil : CGFloat.infinity)
    }

    @ViewBuilder
    private func dockLabel(_ item: Dock, compact: Bool, labels: Bool, isFocused: Bool) -> some View {
        let glyph = gamepad.isConnected ? Self.input(item).map { gamepad.symbol(for: $0) } : nil
        Group {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: glyph ?? Self.symbol(item))
                        .font(.subheadline.weight(.semibold))
                    if labels {
                        Text(Self.title(item))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, labels ? 12 : 10)
                .frame(minWidth: 38, minHeight: 34)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: Self.symbol(item))
                        .font(.system(size: 19, weight: .semibold))
                        .frame(height: 24)
                    HStack(spacing: 3) {
                        if let glyph {
                            Image(systemName: glyph)
                                .font(.caption2.weight(.bold))
                        }
                        Text(Self.title(item))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        .foregroundStyle(isFocused ? Color.white : Color.white.opacity(0.82))
        .background {
            if isFocused {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Capsule().stroke(Color.white, lineWidth: 2))
            }
        }
        .contentShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }

    static func symbol(_ item: Dock) -> String {
        switch item {
        case .allGames: return "square.grid.2x2.fill"
        case .importGame: return "square.and.arrow.down"
        case .system: return "cpu"
        }
    }

    static func title(_ item: Dock) -> String {
        switch item {
        case .allGames: return CartoucheText.allGames
        case .importGame: return CartoucheText.dockImport
        case .system: return CartoucheText.systemTab
        }
    }

    /// The controller's button that does what a button of the dock does,
    /// from anywhere on the home.
    static func input(_ item: Dock) -> CartoucheGamepad.Input? {
        switch item {
        case .allGames: return .y
        case .importGame: return nil
        case .system: return .menu
        }
    }

    // MARK: Actions

    private func tapped(_ item: Item, row tappedRow: Int, column: Int) {
        switch item {
        case .game(let entry):
            if row == tappedRow && columns[tappedRow] == column {
                onSheet(entry)
            } else {
                focus(row: tappedRow, column: column)
            }
        default:
            focus(row: tappedRow, column: column)
            activate(item)
        }
    }

    private func focus(row newRow: Int, column: Int) {
        row = newRow
        columns[newRow] = column
    }

    /// A's action, the main button of the game in focus: Play, Install from
    /// the games folder, or Import.
    private func activate(_ item: Item) {
        switch item {
        case .game(let entry):
            if let app = entry.app {
                onPlay(app)
            } else if let stored = entry.stored {
                onInstall(stored)
            } else if let cloud = entry.cloud {
                onInstallCloud(cloud)
            } else {
                onImport()
            }
        case .importGame, .dock(.importGame):
            onImport()
        case .allGames, .dock(.allGames):
            onLibrary()
        case .dock(.system):
            onTab(.system)
        }
    }

    private func handle(_ input: CartoucheGamepad.Input) {
        switch input {
        case .left:
            if columns[row] > 0 { focus(row: row, column: columns[row] - 1) }
        case .right:
            if columns[row] < rows[row].count - 1 { focus(row: row, column: columns[row] + 1) }
        case .up, .down:
            let order = visualRows
            guard let position = order.firstIndex(of: row) else { return }
            let next = position + (input == .up ? -1 : 1)
            guard order.indices.contains(next) else { return }
            let target = order[next]
            focus(row: target, column: min(columns[target], rows[target].count - 1))
        case .a:
            if let focused { activate(focused) }
        case .x:
            if case .game(let entry) = focused {
                onSheet(entry)
            } else if focused == .importGame, hasNoGame {
                CartoucheOffer.howToGetGame.tapped(at: .home)
                onGuide()
            }
        case .y:
            onLibrary()
        case .menu:
            onTab(.system)
        case .b:
            if row == Self.dockRow { focus(row: Self.shelfRow, column: columns[Self.shelfRow]) }
        case .previous, .next:
            if offersFilter { choose(filter.moved(forward: input == .next), byController: true) }
        }
    }

    // MARK: Layout

    /// The sizes of the home for the space the screen gives it.
    struct Metrics {
        let size: CGSize
        /// The setup banner, or the guide's card, is over the shelf.
        var hasBanner = false
        /// The game in focus is under the shelf, or beside it.
        var hasHero = true
        /// The banner's height as the home laid it out; bannerHeight until
        /// it has.
        var measuredBanner: CGFloat? = nil
        /// The filter beside the shelf's title, taller than the title.
        var hasFilter = false

        static let topBarHeight: CGFloat = 44
        static let bannerHeight: CGFloat = 72
        /// The shelf's title and the space under it.
        static let shelfTitleHeight: CGFloat = 26
        /// The filter beside it, and what it adds to the title's height.
        static let filterHeight: CGFloat = 28
        static let filterExtraHeight: CGFloat = 12
        /// The dock's bar (dockLabel, 50, and 5 around it) and the space
        /// around it at the bottom of the screen.
        static let dockHeight: CGFloat = 60
        static let dockTopPadding: CGFloat = 10
        static let dockBottomPadding: CGFloat = 6
        /// A cover's height for its width, with the room above and below it
        /// for the focused one's ring (shelf(title:width:)).
        static let tileHeight: CGFloat = CartoucheTheme.cartridgeAspect + 0.2

        /// Wider than tall: the shelf beside the game in focus, the dock in
        /// the top bar.
        var isWide: Bool { size.width > size.height * 1.15 }
        /// Too short for the roomy layout: the iPhone Duo folded, an iPhone
        /// sideways.
        var isShort: Bool { size.height < 720 }
        var margin: CGFloat { size.width >= 600 ? 28 : 18 }
        var spacing: CGFloat { isShort ? 12 : 20 }
        var verticalPadding: CGFloat { isShort ? 8 : 12 }
        /// The narrowest the game in focus gets beside the shelf: its name,
        /// its badges, and Play with its other buttons round beside it.
        static let heroMinWidth: CGFloat = 250
        /// Beside the game in focus, 0.6 of the width, or less where the game
        /// would get under heroMinWidth, as on the Duo folded and sideways,
        /// but never under half of it.
        var shelfWidth: CGFloat {
            let width = size.width - 2 * margin
            guard hasHero else { return width }
            return max(min(width * 0.6, width - columnGap - Self.heroMinWidth), width * 0.5)
        }
        /// Beside the game in focus, the space between it and the shelf.
        var columnGap: CGFloat { spacing * 1.5 }
        /// Where the shelf starts to fade, from the screen's margin to the
        /// end of the gap: at the end of its column.
        var shelfFadeStart: CGFloat {
            (margin + shelfWidth) / (margin + shelfWidth + columnGap)
        }
        var titleSize: CGFloat { isWide || isShort ? 26 : (size.width >= 600 ? 34 : 30) }
        /// The lines of what the game in focus says. Under the shelf, whose
        /// room counts them (heroHeight): one on a short screen, two on a
        /// taller one. Beside the shelf, which leaves room below it: three,
        /// the whole of what Import a game says on an iPhone Duo unfolded
        /// sideways before the player's first game.
        var detailLines: Int { isWide ? 3 : (isShort ? 1 : 2) }

        /// The height of the game in focus, upright: its name, its badges,
        /// its play time and size (CartoucheGameStatsLine), two lines about
        /// it (one on a short screen) and its buttons.
        var heroHeight: CGFloat {
            let detail: CGFloat = isShort ? 20 : 40
            return titleSize * 1.2 + 6 + 22 + 6 + 16 + 6 + detail + 12 + 52
        }

        /// The height left to the shelf's covers once the top bar, the
        /// banner, the shelf's title, the game in focus and the dock have
        /// theirs.
        private var shelfSpace: CGFloat {
            // The shelf under the top bar.
            var fixed = 2 * verticalPadding + Self.topBarHeight + spacing + Self.shelfTitleHeight
            if hasFilter { fixed += Self.filterExtraHeight }
            if hasBanner { fixed += (measuredBanner ?? Self.bannerHeight) + spacing }
            if !isWide {
                // The game in focus under the shelf, the dock under them.
                fixed += Self.dockTopPadding + Self.dockHeight + Self.dockBottomPadding
                if hasHero { fixed += spacing + heroHeight }
            }
            return max(size.height - fixed, 0)
        }

        /// A cover's width: as tall as the room allows, up to about two
        /// covers and a third across the shelf.
        var tile: CGFloat {
            let byHeight = shelfSpace / Self.tileHeight
            let byWidth = isWide ? shelfWidth * 0.4 : size.width * 0.36
            let smallest: CGFloat = isWide ? 60 : 78
            return min(max(min(byHeight, byWidth), smallest), 200)
        }

        /// The height the shelf leaves of the room the screen gives it, half
        /// of which goes over it, so that the shelf and the game in focus
        /// stand in the middle.
        var slack: CGFloat { max(shelfSpace - tile * Self.tileHeight, 0) }
    }
}

/// The platform, the genre and where a game plays.
@available(iOS 17.0, *)
struct CartoucheMetaLine: View {
    let entry: CartoucheEntry
    /// Off where a badge under the line says it already.
    var showsStatus = true
    /// The game runs behind the console, paused there.
    var isPaused = false
    /// The game's sheet can give the genre a line of its own.
    var wraps = false

    var body: some View {
        if wraps {
            ViewThatFits(in: .horizontal) {
                line
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        platform
                        status
                    }
                    genre
                }
            }
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: 8) {
            platform
            genre
            status
        }
    }

    @ViewBuilder
    private var platform: some View {
        if let platform = entry.platform {
            Text(CartoucheText.platform(platform).uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.16), in: Capsule())
        }
    }

    @ViewBuilder
    private var genre: some View {
        if let genre = entry.genre, let name = CartoucheText.genre(genre) {
            Label(name, systemImage: CartoucheTheme.symbol(genre: genre))
                .font(.caption.weight(.semibold))
                .labelStyle(CartoucheTightLabelStyle())
                .foregroundStyle(CartoucheTheme.secondaryText)
                .lineLimit(wraps ? nil : 1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if showsStatus {
            CartoucheStatusLabel(status: isPaused ? .paused : CartouchePlayStatus.of(entry))
        }
    }
}

/// Buttons of the controller and what they do here.
@available(iOS 17.0, *)
struct CartoucheHint: View {
    let inputs: [CartoucheGamepad.Input]
    let title: String
    @ObservedObject private var gamepad = CartoucheGamepad.shared

    init(input: CartoucheGamepad.Input, title: String) {
        self.inputs = [input]
        self.title = title
    }

    init(inputs: [CartoucheGamepad.Input], title: String) {
        self.inputs = inputs
        self.title = title
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(inputs, id: \.self) { input in
                Image(systemName: gamepad.symbol(for: input))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CartoucheTheme.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The banner over the home while Cartouche is not set up, or, once the
/// first game is installed, while the automation of every night is still
/// to make: that one has a ×, as the guide's card has, which takes it off
/// the home for good (CartoucheSetup.bannerHides).
@available(iOS 17.0, *)
struct CartoucheHomeSetupBanner: View {
    let action: () -> Void
    @ObservedObject private var setup = CartoucheSetup.shared
    @ObservedObject private var account = CartoucheAccount.shared

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if setup.bannerHides { CartoucheOffer.nightlyBanner.tapped(at: .home) }
                action()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: setup.bannerIcon)
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setup.bannerTitle)
                            .font(.headline)
                        Text(setup.bannerDetail(signingInAgain: account.isAutomatic,
                                                registeringDevice: account.phase == .registeringDevice))
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    if !setup.bannerHides {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .opacity(0.7)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if setup.bannerHides {
                Button {
                    CartoucheOffer.nightlyHidden.tapped(at: .home)
                    withAnimation(.easeInOut(duration: 0.25)) { setup.hideBanner() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.2), in: Circle())
                        // As tall as the icon, so that the banner keeps its height.
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CartoucheText.setupBannerNightlyHide)
            }
        }
        .foregroundStyle(Color.white)
        .padding(14)
        .background(
            LinearGradient(colors: [CartoucheTheme.indigo, CartoucheTheme.pink.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension CartoucheOffer {
    /// Tells the game measurements the player tapped it at PLACE
    /// (CartoucheOffers.swift): here, as the home, the game sheet and the
    /// guide each have it, on the iPhone and on the Mac's console.
    @MainActor
    func tapped(at place: Place) {
        if #available(iOS 17.0, *) {
            CartoucheTelemetry.shared.event(Self.event, fields: fields(at: place))
        }
    }
}
