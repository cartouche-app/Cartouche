//
//  BridgeController.swift
//  Cartouche Builder
//
//  The bridge as the window shows it: on or off, the folders it serves,
//  the iPhones paired, and the request of a new one, asked in a small
//  window of its own in front of everything, with the code to compare.
//  The builds a paired iPhone sees, and the build it asks for, are the
//  model's (IPhoneBuilds.swift); its connections to the player's storage
//  are those of the console's Storage page (ConsoleLink), both sides
//  keeping the same.
//

import AppKit
import BuilderKit
import CartoucheCore
import Network
import SwiftUI

/// An iPhone that asks to pair, until the player answers.
final class PairingRequest: Identifiable {
    let id = UUID()
    let name: String
    let code: String
    let asked = Date()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(name: String, code: String, continuation: CheckedContinuation<Bool, Never>) {
        self.name = name
        self.code = code
        self.continuation = continuation
    }

    func answer(_ allowed: Bool) {
        continuation?.resume(returning: allowed)
        continuation = nil
    }
}

@MainActor
final class BridgeController: ObservableObject, BridgeServerDelegate {
    let server: BridgeServer?
    let home: BuilderHome
    @Published private(set) var state: BridgeServer.State = .stopped
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var connected: Set<String> = []
    /// Those of them connected through the cable, plugged into this Mac.
    @Published private(set) var cabled: Set<String> = []
    @Published private(set) var request: PairingRequest?
    @Published private(set) var games: URL?
    /// This Mac's addresses in the player's tailnet, while Tailscale is on
    /// here (CartoucheTailscale.swift): the paired iPhones reach the Mac
    /// there away from home.
    @Published private(set) var tailnet: [String] = []
    /// The window's model, whose builds a paired iPhone sees.
    weak var model: AppModel?
    private var panel: NSPanel?
    /// The Mac's name and the saves folder the gallery shows (preview).
    private var sampleMac: (name: String, saves: URL)?
    /// The Mac's network, which Tailscale's tunnel joins and leaves.
    private var network: NWPathMonitor?

    init(home: BuilderHome, sample: Bool) {
        self.home = home
        if sample {
            server = nil
        } else {
            server = BridgeServer(devices: BridgeDevices(url: home.bridge), name: BridgeController.macName)
            tailnet = CartoucheTailscale.ownAddresses()
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] _ in
                let addresses = CartoucheTailscale.ownAddresses()
                Task { @MainActor in
                    if self?.tailnet != addresses { self?.tailnet = addresses }
                }
            }
            monitor.start(queue: DispatchQueue(label: "io.github.clabeuhtegrite.cartouche-builder.network"))
            network = monitor
        }
        server?.delegate = self
        devices = server?.devices.all ?? []
    }

    static var macName: String {
        Host.current().localizedName ?? "Mac"
    }

    /// The name Cartouche shows for this Mac under Macs nearby.
    var name: String {
        sampleMac?.name ?? BridgeController.macName
    }

    var enabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.bridgeKey)
    }

    /// Where the iPhone's saves go: the folder chosen, or the builder's own.
    var saves: URL {
        if let sampleMac { return sampleMac.saves }
        if let path = UserDefaults.standard.string(forKey: AppSettings.savesKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.saves
    }

    var savesIsDefault: Bool {
        sampleMac != nil || (UserDefaults.standard.string(forKey: AppSettings.savesKey) ?? "").isEmpty
    }

    func attach(model: AppModel) {
        self.model = model
        server?.builds = self
        server?.connections = self
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: AppSettings.bridgeKey)
        if on { start() } else { server?.stop() }
        objectWillChange.send()
    }

    func setSaves(_ url: URL?) {
        UserDefaults.standard.set(url?.path ?? "", forKey: AppSettings.savesKey)
        applyRoots()
        // The saves of the games played on this Mac are kept there too.
        model?.useMacSaves()
        objectWillChange.send()
    }

    /// The games folder of the settings, served as Games.
    func update(games path: String) {
        games = path.isEmpty ? nil : URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        applyRoots()
    }

    private func applyRoots() {
        let saves = self.saves
        try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        server?.roots = BridgeRoots(games: games, saves: saves)
        // The same folders, under This Mac on the console's Storage page.
        ConsoleLink.showFolders(games: games, saves: saves)
    }

    private func start() {
        applyRoots()
        server?.rename(BridgeController.macName)
        server?.start()
    }

    func forget(_ device: PairedDevice) {
        server?.devices.remove(device.id)
        devices = server?.devices.all ?? []
    }

    /// Shows sample iPhones, those connected now and those of them
    /// plugged into this Mac (CABLED), without a server, and a made-up Mac
    /// name, saves folder and addresses in the tailnet in place of this
    /// Mac's: the gallery's pictures.
    func preview(devices: [PairedDevice], connected: Set<String>, cabled: Set<String> = [], games: String, name: String, saves: URL,
                 tailnet: [String] = []) {
        self.devices = devices
        self.connected = connected
        self.cabled = cabled
        self.games = URL(fileURLWithPath: games, isDirectory: true)
        sampleMac = (name, saves)
        self.tailnet = tailnet
        state = .running(port: CartoucheBridge.port)
    }

    var address: String? {
        guard case let .running(port) = state else { return nil }
        let host = ProcessInfo.processInfo.hostName
        return port == CartoucheBridge.port ? host : "\(host):\(port)"
    }

    // MARK: BridgeServerDelegate

    func bridgeServerChanged(_ server: BridgeServer) {
        state = server.state
        devices = server.devices.all
        connected = server.connected
        cabled = server.connectedByCable
    }

    func bridgeServer(_ server: BridgeServer, allowPairing name: String, code: String) async -> Bool {
        let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let asked = PairingRequest(name: name, code: code, continuation: continuation)
            request = asked
            showPanel(asked)
            model?.notify(title: tr("“\(name)” asks to connect", "« \(name) » demande à se connecter"),
                          body: tr("Check that it shows \(CartoucheBridge.spaced(code)).", "Vérifiez qu’il affiche \(CartoucheBridge.spaced(code))."),
                          section: .iphone)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(CartoucheBridge.pairingTimeout * 1_000_000_000))
                if self?.request?.id == asked.id { self?.answer(false) }
            }
        }
        devices = server.devices.all
        // Whether Tailscale is on this Mac, as app.opened says it of the
        // iPhone: never the tailnet, its names or its addresses.
        model?.telemetry.event("builder.paired", fields: ["allowed": .flag(allowed), "tailscale": .flag(!tailnet.isEmpty)])
        return allowed
    }

    func answer(_ allowed: Bool) {
        request?.answer(allowed)
        request = nil
        panel?.close()
        panel = nil
    }

    private func showPanel(_ asked: PairingRequest) {
        panel?.close()
        let made = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        made.titleVisibility = .hidden
        made.titlebarAppearsTransparent = true
        made.isMovableByWindowBackground = true
        made.level = .floating
        made.isReleasedWhenClosed = false
        made.contentViewController = NSHostingController(rootView: PairingPrompt(request: asked) { [weak self] allowed in
            self?.answer(allowed)
        })
        made.center()
        NSApp.activate()
        made.makeKeyAndOrderFront(nil)
        panel = made
    }
}

// MARK: The player's storage

/// A paired iPhone's connections to the player's storage, and the Mac's,
/// those of the console's Storage page (BridgeServer's
/// BridgeConnectionsSource): the console takes them and gives its own, as
/// JSON from CartoucheCore's type to its own copy of it and back. The
/// folders the player chose on the iPhone come with them: of each, the one
/// chosen last on any iPhone, or on the console, is kept, and the Mac keeps
/// its games' saves in that saves folder when it is on one of the
/// connections, and sends its games to that games folder (IPhoneGames); the
/// iPhone is given them back.
extension BridgeController: BridgeConnectionsSource {
    func bridgeConnections(_ theirs: [CartoucheConnection], places: CartoucheChosenFolders?) throws -> [CartoucheConnection] {
        guard let given = try? JSONEncoder().encode(theirs),
              let kept = ConsoleLink.takeConnections(given),
              let mine = try? JSONDecoder().decode([CartoucheConnection].self, from: kept) else {
            throw CartoucheBridgeError(.failed, "connections")
        }
        if let places {
            let told = AppSettings.toldFolders.taking(places)
            if told != AppSettings.toldFolders { AppSettings.toldFolders = told }
        }
        // The connections may have changed too: a saves folder, or the
        // games folder, on one replaced or removed.
        model?.useMacSaves()
        model?.useIPhoneGames()
        objectWillChange.send()
        return mine
    }

    /// The folders kept, those chosen last on any iPhone or on the
    /// console's Storage page (AppModel.changeFolders): the iPhone takes
    /// them when they are later than its own.
    func bridgeFolders() -> CartoucheChosenFolders? {
        let kept = AppSettings.toldFolders
        return kept.games == nil && kept.saves == nil ? nil : kept
    }
}

/// The question, with the code the iPhone shows.
struct PairingPrompt: View {
    let request: PairingRequest
    let answer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.gradient)
            Text(tr("Allow “\(request.name)”?", "Autoriser « \(request.name) » ?"))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(tr("Cartouche on this iPhone asks to read and add games and saves on this Mac. Allow it only if the iPhone shows the same code:",
                    "Cartouche sur cet iPhone demande à lire et ajouter des jeux et des sauvegardes sur ce Mac. Autorisez-le seulement si l’iPhone affiche le même code :"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(CartoucheBridge.spaced(request.code))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .tracking(4)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button(tr("Refuse", "Refuser"), role: .cancel) { answer(false) }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button(tr("Allow", "Autoriser")) { answer(true) }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
