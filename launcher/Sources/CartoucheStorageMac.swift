//
//  CartoucheStorageMac.swift
//  Cartouche
//
//  The player's Mac as storage, through Cartouche Builder's bridge
//  (CartoucheBridge.swift): Cartouche finds the Mac on the Wi-Fi with
//  Bonjour, or through the cable when the iPhone is plugged into it
//  (CartoucheBridgeCable.swift), pairs with it once, the player checking
//  that both screens show the same six digits, and then reads and writes
//  the two folders the Mac shares, Games and Saves, as it would a shared
//  folder. The Mac's Games folder is where Cartouche Builder puts the games
//  it builds, on the Mac or on the NAS it reaches.
//
//  The Mac is known by its ID in Cartouche Builder. Plugged into it, the
//  iPhone reaches it through the cable first, whatever its network: no
//  Wi-Fi needed, and a long transfer does not depend on it. Without the
//  cable, Cartouche first tries the address it last reached the Mac at,
//  which also answers through the player's VPN, where Bonjour does not go,
//  and, while Tailscale is on here, the Mac's addresses in the player's
//  tailnet, which its Cartouche Builder tells (CartoucheTailscale.swift):
//  away from home, Tailscale reaches it. Then it looks for that ID on the
//  network, so a new address from the router changes nothing. A Mac
//  Bonjour cannot see pairs by its Tailscale name or address, typed on the
//  Storage page.
//
//  The paired key is the server's secret in the keychain, in base64. The
//  iPhone's ID for the Mac is the server's own UUID: two Macs cannot tell
//  they serve the same iPhone.
//
//  The player's connections to their storage go to the Mac, and its own
//  come back, so that both have the same (CartoucheConnectionsExchange):
//  after a pairing, after each change here, and when Cartouche comes to
//  the front. So do the folders chosen for the games and the saves: the
//  ones chosen last, here, on another iPhone or on the Mac's console, win.
//

import Combine
import Foundation
import Network

/// A Mac with Cartouche Builder on this network, as Bonjour lists it, or
/// linked through the cable.
struct CartoucheNearbyMac: Identifiable, Hashable {
    /// The Mac's name.
    let name: String
    /// Its ID in Cartouche Builder, from its Bonjour record or what it said
    /// through the cable.
    let macID: String?
    /// Where Bonjour found it; nil for a Mac seen through the cable alone.
    let endpoint: NWEndpoint?
    /// Whether the iPhone is plugged into it: pairing goes through the cable.
    let cabled: Bool

    init(name: String, macID: String?, endpoint: NWEndpoint?, cabled: Bool = false) {
        self.name = name
        self.macID = macID
        self.endpoint = endpoint
        self.cabled = cabled
    }

    var id: String { macID ?? name }
}

/// The Macs whose Cartouche Builder shares with Cartouche on this network
/// (_cartouche._tcp), and those linked through the cable, once each.
final class CartoucheMacBrowser: ObservableObject {
    @Published private(set) var found: [CartoucheNearbyMac] = []
    /// Whether iOS keeps Cartouche from looking: it may not reach the local
    /// network (Settings › Privacy & Security › Local Network).
    @Published private(set) var refused = false
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "Cartouche Mac browser")
    private let cable: CartoucheCableLinks
    private var cableWatch: NSObjectProtocol?
    /// What Bonjour found last.
    private var bonjour: [CartoucheNearbyMac] = []

    init(cable: CartoucheCableLinks = .shared) {
        self.cable = cable
    }

    #if CARTOUCHE_GALLERY
    /// What the launcher's gallery (launcher/Gallery) shows in place of
    /// Bonjour's answers: the Macs nearby, and whether iOS refuses Cartouche
    /// the local network.
    static var gallery: (found: [CartoucheNearbyMac], refused: Bool)?
    #endif

    func start() {
        #if CARTOUCHE_GALLERY
        if let gallery = Self.gallery {
            found = gallery.found
            refused = gallery.refused
            return
        }
        #endif
        guard browser == nil else { return }
        if cableWatch == nil {
            cableWatch = NotificationCenter.default.addObserver(forName: CartoucheCableLinks.changed, object: cable, queue: .main) { [weak self] _ in
                self?.merge()
            }
        }
        merge()
        let browser = NWBrowser(for: Self.descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = CartoucheMacBrowser.macs(in: results)
            DispatchQueue.main.async {
                self?.bonjour = macs
                self?.merge()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let refused = CartoucheMacBrowser.isRefused(state)
            DispatchQueue.main.async { self?.refused = refused }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        if let cableWatch { NotificationCenter.default.removeObserver(cableWatch) }
        cableWatch = nil
    }

    /// What Bonjour found and the Macs linked through the cable, once each.
    private func merge() {
        found = Self.merged(bonjour: bonjour, cable: cable.macs)
    }

    /// The Macs of BONJOUR and those linked through the CABLE, once each, by
    /// name: a Mac on both pairs through the cable, Bonjour's place kept.
    static func merged(bonjour: [CartoucheNearbyMac], cable: [CartoucheCableMac]) -> [CartoucheNearbyMac] {
        let cabled = Set(cable.map(\.id))
        let byID = Dictionary(bonjour.compactMap { mac in mac.macID.map { ($0, mac) } }, uniquingKeysWith: { first, _ in first })
        let plugged = cable.map { CartoucheNearbyMac(name: $0.name, macID: $0.id, endpoint: byID[$0.id]?.endpoint, cabled: true) }
        let others = bonjour.filter { mac in mac.macID.map { !cabled.contains($0) } ?? true }
        return (plugged + others).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var descriptor: NWBrowser.Descriptor {
        .bonjourWithTXTRecord(type: CartoucheBridge.serviceType, domain: nil)
    }

    static func macs(in results: Set<NWBrowser.Result>) -> [CartoucheNearbyMac] {
        results.compactMap { result -> CartoucheNearbyMac? in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            var macID: String?
            if case let .bonjour(record) = result.metadata, let id = record["id"], !id.isEmpty {
                macID = id
            }
            return CartoucheNearbyMac(name: name, macID: macID, endpoint: result.endpoint)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether STATE says iOS does not let Cartouche browse: the player
    /// refused it the local network (kDNSServiceErr_PolicyDenied), or the
    /// app does not declare the bridge's Bonjour type (kDNSServiceErr_NoAuth).
    static func isRefused(_ state: NWBrowser.State) -> Bool {
        let error: NWError
        switch state {
        case let .waiting(waiting): error = waiting
        case let .failed(failed): error = failed
        default: return false
        }
        guard case let .dns(code) = error else { return false }
        return code == -65570 || code == -65555
    }

    /// Where the Mac whose ID is MAC_ID is on this network, once Bonjour
    /// finds it within TIMEOUT, in seconds; nil when it does not.
    static func find(_ macID: String, timeout: TimeInterval) async -> NWEndpoint? {
        let browser = NWBrowser(for: descriptor, using: .tcp)
        let queue = DispatchQueue(label: "Cartouche Mac lookup")
        let once = CartoucheBridgeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<NWEndpoint?, Never>) in
            browser.browseResultsChangedHandler = { results, _ in
                guard let mac = CartoucheMacBrowser.macs(in: results).first(where: { $0.macID == macID }), once.claim() else { return }
                browser.cancel()
                continuation.resume(returning: mac.endpoint)
            }
            browser.stateUpdateHandler = { state in
                guard case .failed = state, once.claim() else { return }
                browser.cancel()
                continuation.resume(returning: nil)
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard once.claim() else { return }
                browser.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: Signing in

enum CartoucheMacStorage {
    /// How long the address the Mac was last reached at, and its addresses
    /// in the tailnet, have to answer, in seconds, before Cartouche looks
    /// for the Mac on the network.
    static let lastAddressPatience: TimeInterval = 3
    /// How long Bonjour has to find the Mac, in seconds.
    static let lookupPatience: TimeInterval = 4
    /// How long the address the Mac was last reached at is tried alone, in
    /// seconds, before its addresses in the tailnet are tried beside it: at
    /// home, where both answer, the Wi-Fi's goes first.
    static let tailnetHeadStart: TimeInterval = 0.3
    /// How often Cartouche asks a Mac its addresses in the tailnet, on the
    /// first connection after, in seconds: Tailscale gives a device the same
    /// ones for good.
    static let tailnetAskSpacing: TimeInterval = 3_600

    /// The iPhone's ID for the Mac of SERVER.
    static func deviceID(of server: CartoucheStorageServer) -> String {
        server.id.uuidString.lowercased()
    }

    /// The paired key SECRET holds, base64; nil for anything else.
    static func pairedKey(_ secret: String) -> Data? {
        guard let key = Data(base64Encoded: secret), key.count == 32 else { return nil }
        return key
    }

    /// The addresses Cartouche tries for SERVER's Mac before it looks for
    /// it with Bonjour, in order: where it was last reached, then, while
    /// Tailscale is on here (TAILSCALE), its addresses in the tailnet; all
    /// on the port it was last reached on, the Mac's one for all its
    /// networks. None before it was reached.
    static func addresses(of server: CartoucheStorageServer, tailscale: Bool) -> [(host: String, port: Int)] {
        let port = server.port ?? Int(CartoucheBridge.port)
        guard (1 ... 65535).contains(port) else { return [] }
        return CartoucheTailscale.addressesToTry(host: server.host, tailnet: server.tailnet ?? [], tailscaleOn: tailscale)
            .map { ($0, port) }
    }

    /// Signs in to the Mac of SERVER with the paired key, SECRET. TAILSCALE:
    /// whether Tailscale is on here, and the Mac's addresses in the tailnet
    /// are tried.
    static func connect(_ server: CartoucheStorageServer, secret: String, settings: CartoucheStorageSettings,
                        tailscale: Bool = CartoucheTailscale.isConnected) async throws -> CartoucheRemote {
        guard let key = pairedKey(secret), let macID = server.macID, !macID.isEmpty else {
            throw explained(CartoucheBridgeError(.notPaired), mac: server.name, path: "")
        }
        let device = deviceID(of: server)
        // The cable first: plugged into the Mac, the iPhone reaches it there
        // whatever its network.
        if let remote = try await throughCable(server, macID: macID, device: device, key: key, settings: settings) {
            return remote
        }
        // Where it was last, and where Tailscale reaches it: the Mac rarely
        // moves, and Bonjour crosses neither a VPN nor Tailscale.
        let endpoints = addresses(of: server, tailscale: tailscale).compactMap { address -> NWEndpoint? in
            NWEndpoint.Port(rawValue: UInt16(address.port)).map { .hostPort(host: NWEndpoint.Host(address.host), port: $0) }
        }
        if !endpoints.isEmpty {
            do {
                let client = try await CartoucheBridgeClient.connect(firstOf: endpoints, device: device, key: key, mac: macID,
                                                                    headStart: tailnetHeadStart, timeout: lastAddressPatience)
                return await remember(client, server: server, settings: settings)
            } catch let error as CartoucheBridgeError where [.notPaired, .protocolError].contains(error.kind) {
                // The Mac itself answered: it forgot this iPhone, or speaks
                // another version of the bridge.
                throw explained(error, mac: server.name, path: "")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Not there any more, or another Mac in its place.
            }
        }
        guard let endpoint = await CartoucheMacBrowser.find(macID, timeout: lookupPatience) else {
            // Away from home, or Cartouche Builder closed: offline, which
            // makes no report (CartoucheStorageReach).
            throw CartoucheStorageOffline(server, tailscale: tailscale)
        }
        do {
            let client = try await CartoucheBridgeClient.connect(endpoint, device: device, key: key, mac: macID)
            return await remember(client, server: server, settings: settings)
        } catch let error as CartoucheBridgeError {
            throw explained(error, mac: server.name, path: "")
        }
    }

    /// Signs in to the Mac of SERVER, MAC_ID, through the cable, when the
    /// iPhone is plugged into it: nil when it is not, or when the cable
    /// went meanwhile, for the network to be tried. The Mac's own refusal
    /// is thrown: its other ways would say the same.
    private static func throughCable(_ server: CartoucheStorageServer, macID: String, device: String, key: Data,
                                     settings: CartoucheStorageSettings, cable: CartoucheCableLinks = .shared) async throws -> CartoucheRemote? {
        guard let transport = await cable.session(with: macID) else { return nil }
        do {
            let channel = try await withTaskCancellationHandler {
                try await CartoucheBridgeHandshake.client(transport, device: device, key: key, mac: macID)
            } onCancel: {
                transport.close()
            }
            try Task.checkCancellation()
            // No address to keep: the cable has none.
            return await remember(CartoucheBridgeClient(channel: channel, address: nil), server: server, settings: settings)
        } catch let error as CartoucheBridgeError where [.notPaired, .protocolError].contains(error.kind) {
            transport.close()
            throw explained(error, mac: server.name, path: "")
        } catch {
            transport.close()
            if Task.isCancelled { throw CancellationError() }
            return nil
        }
    }

    /// Whether the Mac of SERVER answers from here, through the cable, at
    /// its last address, at one of the tailnet while Tailscale is on here
    /// (TAILSCALE), or found by Bonjour, without signing in: how Cartouche
    /// tries it again once it was offline.
    static func answers(_ server: CartoucheStorageServer, tailscale: Bool = CartoucheTailscale.isConnected) async -> Bool {
        if let macID = server.macID, !macID.isEmpty, CartoucheCableLinks.shared.isLinked(macID) { return true }
        let tried = Self.addresses(of: server, tailscale: tailscale)
        if !tried.isEmpty {
            let patience = UInt64(lastAddressPatience * 1_000_000_000)
            let answered = await withTaskGroup(of: Bool.self) { group -> Bool in
                for address in tried {
                    group.addTask {
                        await CartoucheStorageReach.knock(host: address.host, port: address.port, patience: patience)
                    }
                }
                for await answered in group where answered {
                    // The others give up at once.
                    group.cancelAll()
                    return true
                }
                return false
            }
            if answered { return true }
        }
        guard let macID = server.macID, !macID.isEmpty else { return false }
        return await CartoucheMacBrowser.find(macID, timeout: lookupPatience) != nil
    }

    /// When Cartouche last asked each Mac its addresses in the tailnet, by
    /// the server's ID, under its lock.
    private static let askedLock = NSLock()
    nonisolated(unsafe) private static var asked: [UUID: Date] = [:]

    /// Whether to ask the Mac of SERVER its addresses in the tailnet now:
    /// on the first connection since Cartouche started, then once in a
    /// while (tailnetAskSpacing).
    private static func asksTailnet(of server: UUID, at now: Date) -> Bool {
        askedLock.lock()
        defer { askedLock.unlock() }
        if let last = asked[server], last <= now, now.timeIntervalSince(last) < tailnetAskSpacing { return false }
        asked[server] = now
        return true
    }

    /// CLIENT as SERVER's remote, keeping where it reached the Mac for the
    /// next time, and the Mac's addresses in the tailnet, as its Cartouche
    /// Builder tells them now and then.
    private static func remember(_ client: CartoucheBridgeClient, server: CartoucheStorageServer,
                                 settings: CartoucheStorageSettings) async -> CartoucheRemote {
        // An older Cartouche Builder says nothing of them.
        let told = asksTailnet(of: server.id, at: Date()) ? (try? await client.info())?.tailscale : nil
        let known = CartoucheMacAddresses(host: server.host, port: server.port, tailnet: server.tailnet ?? [])
        let now = known.reached(usable(client.address), port: client.port, told: told)
        if now != known {
            await MainActor.run {
                // As the player has it now, unless they removed it meanwhile.
                guard var moved = settings.server(server.id) else { return }
                moved.host = now.host
                moved.port = now.port
                moved.tailnet = now.tailnet.isEmpty ? nil : now.tailnet
                settings.save(moved, secret: nil)
            }
        }
        return CartoucheMacRemote(client, mac: server.name)
    }

    /// ADDRESS, unless it is an IPv6 address of the link only, which
    /// cannot be reached again without its interface.
    static func usable(_ address: String?) -> String? {
        guard let address, !address.isEmpty, !address.lowercased().hasPrefix("fe80:") else { return nil }
        return address
    }

    // MARK: Pairing

    /// Pairs this iPhone, named DEVICE_NAME, with MAC, nearby: through the
    /// cable when the iPhone is plugged into it, else where Bonjour found
    /// it. As pair(_:at:) does.
    static func pair(_ server: CartoucheStorageServer, with mac: CartoucheNearbyMac, deviceName: String, cable: CartoucheCableLinks = .shared,
                     code: @escaping @Sendable (String) -> Void) async throws -> (server: CartoucheStorageServer, secret: String) {
        if mac.cabled, let macID = mac.macID, let transport = await cable.session(with: macID) {
            return try await pair(server, over: transport, address: nil, port: nil, name: mac.name, deviceName: deviceName, code: code)
        }
        try Task.checkCancellation()
        guard let endpoint = mac.endpoint else {
            // Unplugged meanwhile, and Bonjour does not see it.
            throw explained(CartoucheBridgeError(.closed), mac: mac.name, path: "")
        }
        return try await pair(server, at: endpoint, name: mac.name, deviceName: deviceName, code: code)
    }

    /// Pairs this iPhone, named DEVICE_NAME, with the Mac at ENDPOINT, for
    /// SERVER: CODE gets the six digits both screens show, while the player
    /// allows the iPhone on the Mac. Gives SERVER to save, with the Mac's
    /// ID, name and address, and the paired key, base64, its secret.
    /// Cancelling the task closes the connection.
    static func pair(_ server: CartoucheStorageServer, at endpoint: NWEndpoint, name: String, deviceName: String,
                     code: @escaping @Sendable (String) -> Void) async throws -> (server: CartoucheStorageServer, secret: String) {
        let connection: CartoucheBridgeConnection
        do {
            connection = try await CartoucheBridgeConnection.open(endpoint, timeout: 8)
        } catch let error as CartoucheBridgeError {
            throw explained(error, mac: name, path: "")
        }
        return try await pair(server, over: connection, address: connection.remoteAddress, port: connection.remotePort,
                              name: name, deviceName: deviceName, code: code)
    }

    /// Pairs on CONNECTION, which reached the Mac at ADDRESS and PORT (none
    /// through the cable), then closes it.
    private static func pair(_ server: CartoucheStorageServer, over connection: CartoucheBridgeTransport, address: String?, port: Int?,
                             name: String, deviceName: String,
                             code: @escaping @Sendable (String) -> Void) async throws -> (server: CartoucheStorageServer, secret: String) {
        defer { connection.close() }
        do {
            let paired = try await withTaskCancellationHandler {
                try await CartoucheBridgeHandshake.pair(connection, device: deviceID(of: server), name: deviceName, code: code)
            } onCancel: {
                connection.close()
            }
            try Task.checkCancellation()
            var made = server
            made.kind = .mac
            made.macID = paired.mac
            if made.name.trimmingCharacters(in: .whitespaces).isEmpty {
                made.name = paired.name.isEmpty ? name : paired.name
            }
            // Through Tailscale, the Mac's address in the tailnet, kept
            // beside the one of the player's network.
            let reached = CartoucheMacAddresses(host: made.host, port: made.port, tailnet: made.tailnet ?? [])
                .reached(usable(address), port: port, told: nil)
            made.host = reached.host
            made.port = reached.port
            made.tailnet = reached.tailnet.isEmpty ? nil : reached.tailnet
            return (made, paired.key.base64EncodedString())
        } catch let error as CartoucheBridgeError {
            if Task.isCancelled { throw CancellationError() }
            throw explained(error, mac: name, path: "")
        }
    }

    // MARK: What the Mac answers, in the player's words

    /// ERROR, from the Mac called MAC about PATH, as the player reads it;
    /// a report keeps its kind as its domain, "CartoucheBridge.notFound".
    static func explained(_ error: CartoucheBridgeError, mac: String, path: String) -> Error {
        let item = CartoucheStoragePath.name(path)
        let words: String
        switch error.kind {
        case .notFound: words = CartoucheText.storageMacNotFound(item.isEmpty ? mac : item)
        case .denied: words = CartoucheText.storageMacDenied(item.isEmpty ? mac : item)
        case .exists: words = CartoucheText.storageMacExists(item)
        case .closed, .timeout: words = CartoucheText.storageMacLost(mac)
        case .notPaired: words = CartoucheText.storageMacNotPaired(mac)
        case .refused: words = CartoucheText.storageMacRefused(mac)
        case .busy: words = CartoucheText.storageMacBusy(mac)
        case .protocolError: words = CartoucheText.storageMacUpdate
        case .notMac: words = CartoucheText.storageMacOffline(mac)
        case .failed: words = CartoucheText.storageMacFailed(mac, error.message)
        }
        return NSError(domain: "CartoucheBridge." + error.kind.rawValue, code: 0,
                       userInfo: [NSLocalizedDescriptionKey: words])
    }

    /// WORK, with what the Mac called MAC answers about PATH in the
    /// player's words.
    static func bridged<T>(_ mac: String, _ path: String, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as CartoucheBridgeError {
            throw explained(error, mac: mac, path: path)
        }
    }
}

// MARK: The connections the Mac takes

/// The player's connections to their storage, given to each paired Mac
/// with their secrets, and the Mac's taken, so that both have the same
/// (CartoucheConnections.swift), with the folders chosen here for the games
/// and the saves, which the Mac uses too when they are on one of them, and
/// those it keeps taken when they were chosen later, on its console or on
/// another iPhone (take(folders:)):
/// after a pairing, a moment after a server that goes over the bridge was
/// saved or removed here or a folder chosen, and when Cartouche comes to
/// the front, at most every ten minutes then. A Mac away, closed or too old
/// to take them is asked again the next time; none of it makes a report.
@MainActor
final class CartoucheConnectionsExchange: ObservableObject {
    static let shared = CartoucheConnectionsExchange()

    /// When each Mac last took the connections, by its server's ID.
    @Published private(set) var last: [UUID: Date] = [:]
    /// How long Cartouche coming to the front leaves them, after they last
    /// went to every Mac, in seconds.
    static let interval: TimeInterval = 10 * 60

    private let settings: CartoucheStorageSettings
    private var watching: AnyCancellable?
    private var running: Task<Void, Never>?
    private var again = false

    init(settings: CartoucheStorageSettings = .shared) {
        self.settings = settings
    }

    /// From now on, a moment after each change here.
    func start() {
        guard watching == nil else { return }
        watching = settings.connectionsChanged
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.exchange() }
    }

    /// Cartouche came to the front: unless every Mac took them within the
    /// interval.
    func cameForward(now: Date = Date()) {
        start()
        let macs = settings.servers.filter { $0.kind == .mac }
        guard macs.contains(where: { now.timeIntervalSince(last[$0.id] ?? .distantPast) >= Self.interval }) else { return }
        exchange()
    }

    /// With each paired Mac; once more after the exchange under way.
    func exchange() {
        guard running == nil else {
            again = true
            return
        }
        running = Task { [self] in
            repeat {
                again = false
                await exchangeOnce()
            } while again
            running = nil
        }
    }

    /// Whether an exchange is under way: the tests wait for its end.
    var isExchanging: Bool { running != nil }

    private func exchangeOnce() async {
        for mac in settings.servers where mac.kind == .mac {
            if await Self.exchange(with: mac, settings: settings) {
                last[mac.id] = Date()
            }
        }
    }

    /// Gives the Mac of SERVER the connections, and takes its own: whether
    /// the Mac took them. A Mac too old to take them leaves them as they
    /// are.
    static func exchange(with server: CartoucheStorageServer, settings: CartoucheStorageSettings) async -> Bool {
        let remote: CartoucheRemote
        do {
            remote = try await CartoucheStorage.connect(server, settings: settings)
        } catch {
            NSLog("[Cartouche] the connections wait for the Mac: %@", error.localizedDescription)
            return false
        }
        let took = await give(to: remote, settings: settings)
        await remote.disconnect()
        return took
    }

    /// The connections given to the Mac REMOTE, and its own taken. The
    /// journal says how many, never which.
    private static func give(to remote: CartoucheRemote, settings: CartoucheStorageSettings) async -> Bool {
        guard let mac = remote as? CartoucheMacRemote else { return false }
        do {
            guard try await mac.client.info().hasConnections == true else {
                NSLog("[Cartouche] the Mac takes no connections: its Cartouche Builder is older")
                return false
            }
            let (theirs, places) = try await mac.client.exchange(settings.connections(), places: settings.chosenFolders())
            let changed = settings.take(theirs)
            // The folders chosen last there, on a connection taken just now
            // too.
            let moved = places.map { settings.take(folders: $0) } ?? false
            NSLog("[Cartouche] the Mac took the connections and gave %ld, %@%@", theirs.filter { !$0.removed }.count,
                  changed ? "which changed some here" : "the same as here",
                  moved ? ", and folders chosen later there" : "")
            return true
        } catch {
            NSLog("[Cartouche] the Mac did not take the connections: %@", error.localizedDescription)
            return false
        }
    }
}

// MARK: The Mac's two folders

/// The Mac's Games and Saves folders, signed in to through the bridge,
/// one request at a time.
final class CartoucheMacRemote: CartoucheRemote {
    let client: CartoucheBridgeClient
    /// The Mac's name in Cartouche, for what it answers.
    private let mac: String

    init(_ client: CartoucheBridgeClient, mac: String) {
        self.client = client
        self.mac = mac
    }

    /// The Mac says folder by folder where Cartouche may write (canWrite).
    var isReadOnly: Bool { false }

    func list(_ path: String) async throws -> [CartoucheRemoteItem] {
        let items = try await CartoucheMacStorage.bridged(mac, path) { try await client.list(path) }
        return items.map { CartoucheRemoteItem(name: $0.name, isFolder: $0.folder, size: $0.size, modified: $0.modifiedDate) }
    }

    func open(_ path: String) async throws -> CartoucheByteSource {
        let found = try await CartoucheMacStorage.bridged(mac, path) { try await client.stat(path) }
        if found.folder == true {
            throw CartoucheMacStorage.explained(CartoucheBridgeError(.notFound), mac: mac, path: path)
        }
        let client = self.client
        let mac = self.mac
        return CartoucheReadAhead(size: found.size ?? 0) { offset, count in
            try await CartoucheMacStorage.bridged(mac, path) { try await client.read(path, at: offset, count: count) }
        }
    }

    func create(_ path: String, size: UInt64?) async throws -> CartoucheRemoteUpload {
        let upload = try await CartoucheMacStorage.bridged(mac, path) { try await client.create(path, size: size) }
        return CartoucheMacUpload(client: client, upload: upload, mac: mac, path: path)
    }

    func makeFolder(_ path: String) async throws {
        try await CartoucheMacStorage.bridged(mac, path) { try await client.makeFolder(path) }
    }

    func delete(_ path: String) async throws {
        try await CartoucheMacStorage.bridged(mac, path) { try await client.delete(path) }
    }

    func freeSpace() async throws -> UInt64? {
        try await CartoucheMacStorage.bridged(mac, "") { try await client.freeSpace() }
    }

    func canWrite(_ path: String) async throws -> Bool {
        try await CartoucheMacStorage.bridged(mac, path) { try await client.canWrite(path) }
    }

    func disconnect() async {
        client.close()
    }
}

/// A file being written on the Mac, which names it only once it is
/// finished: until then the file there, if any, stays as it was.
private final class CartoucheMacUpload: CartoucheRemoteUpload {
    private let client: CartoucheBridgeClient
    private let upload: String
    private let mac: String
    private let path: String

    init(client: CartoucheBridgeClient, upload: String, mac: String, path: String) {
        self.client = client
        self.upload = upload
        self.mac = mac
        self.path = path
    }

    func write(_ data: Data) async throws {
        try await CartoucheMacStorage.bridged(mac, path) { try await client.write(data, upload: upload) }
    }

    func finish() async throws {
        try await CartoucheMacStorage.bridged(mac, path) { try await client.finish(upload) }
    }

    func cancel() async {
        await client.cancel(upload)
    }
}
