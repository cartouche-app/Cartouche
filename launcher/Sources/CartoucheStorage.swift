//
//  CartoucheStorage.swift
//  Cartouche
//
//  The player's own storage, off the iPhone: the servers, S3 buckets and
//  Google Drive they sign in to in Cartouche and the folders of theirs that
//  iOS lets it keep, and the two places Cartouche uses there, kept apart:
//  one for the games' IPAs, one for the backups of their saves.
//
//  Cartouche reaches only what the player signs in to with their own
//  account or keys, or a folder they picked: there is no link to paste or
//  follow, no public bucket, no file someone shared. It is where the player
//  keeps their own copies, never a way to download games.
//
//  The servers and places are in Cartouche's preferences; each server's
//  password, secret key or Google sign-in is in the keychain, never in the
//  preferences. On the Mac, in a file of Cartouche Builder's folder that
//  only the player's session reads, never in the Mac's keychain.
//
//  The servers that go over the bridge, all but a Mac paired and a folder
//  picked, are the same on the iPhone and the Mac it is paired with: each
//  gives the other its own with their secrets, and when the player last
//  changed or removed each (CartoucheConnections.swift).
//

import Combine
import Foundation
import Security

/// A server or a folder of the player's.
struct CartoucheStorageServer: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// A shared folder of a Mac, a PC or a NAS (SMB 2 and 3).
        case smb
        /// A folder of the iPhone, of iCloud Drive or of a disk, picked once.
        case folder
        /// A private bucket on Amazon S3 or on a server of one's own, with
        /// the player's keys.
        case s3
        /// An FTP server of the player's network, with their account.
        case ftp
        /// An SFTP server of the player's, with their account, whose key
        /// Cartouche keeps.
        case sftp
        /// The player's Mac with Cartouche Builder, paired once: the Games
        /// and Saves folders it shares (CartoucheStorageMac.swift).
        case mac
        /// The player's Google Drive, My Drive alone, signed in to with
        /// their own OAuth client and Google account
        /// (CartoucheStorageDrive.swift).
        case drive

        var id: String { rawValue }
    }

    var id = UUID()
    var kind: Kind
    /// What the player calls it.
    var name: String
    /// SMB, FTP and SFTP: the server's name or address. S3: its address, with
    /// http:// before it for a server of the player's network without
    /// HTTPS. A Mac: the address it was last reached at, and its port.
    /// Google Drive: the address of the Google account signed in to.
    var host: String = ""
    var port: Int?
    /// S3: the access key ID. Google Drive: the ID of the player's OAuth
    /// client, whose refresh token is the secret in the keychain.
    var username: String = ""
    /// SMB: the shared folder. S3: the bucket.
    var share: String = ""
    /// A picked folder: iOS's bookmark of it.
    var bookmark: Data?
    /// S3: the bucket's region, when the player gave one.
    var region: String?
    /// SFTP: the server's key, as OpenSSH writes it, kept when the player
    /// saved the server.
    var hostKey: String?
    /// A Mac: its ID in Cartouche Builder, which Bonjour finds it by. Its
    /// paired key is the secret in the keychain.
    var macID: String?
    /// A Mac: its addresses in the player's tailnet, as its Cartouche
    /// Builder last told them, which Cartouche tries away from home while
    /// Tailscale is on here (CartoucheTailscale.swift); nil until it told
    /// some.
    var tailnet: [String]?
    /// When the player last changed it here, or on the device that gave it:
    /// of the same server on the iPhone and its Mac, both keep the one
    /// changed last. Nil for one an older Cartouche kept.
    var changed: Date?
}

extension CartoucheStorageServer {
    /// Whether it is the same on the iPhone and the Mac it is paired with:
    /// all but a Mac paired, whose key is theirs alone, and a folder
    /// picked, which only its device opens.
    var travels: Bool { CartoucheConnections.kinds.contains(kind.rawValue) }

    /// As it goes over the bridge, with SECRET.
    func connection(secret: String?) -> CartoucheConnection {
        CartoucheConnection(id: id, kind: kind.rawValue, name: name, host: host, port: port, username: username, share: share,
                            region: region, hostKey: hostKey, secret: secret, changed: changed ?? Date(timeIntervalSince1970: 0))
    }

    /// CONNECTION as a server, unless it was removed, or is of a kind that
    /// does not go over the bridge.
    init?(_ connection: CartoucheConnection) {
        guard !connection.removed, let kind = Kind(rawValue: connection.kind),
              CartoucheConnections.kinds.contains(kind.rawValue) else { return nil }
        self.init(id: connection.id, kind: kind, name: connection.name, host: connection.host, port: connection.port,
                  username: connection.username, share: connection.share, region: connection.region,
                  hostKey: connection.hostKey, changed: connection.changed)
    }
}

/// A folder on one of the player's servers.
struct CartoucheStoragePlace: Codable, Hashable {
    var server: UUID
    /// From the server's root, folders joined by "/"; "" for the root.
    var path: String
}

enum CartoucheStorageRole: String, CaseIterable, Identifiable {
    /// The games' IPAs.
    case games
    /// The backups of the games' saves.
    case saves

    var id: String { rawValue }
}

/// Why the player's storage failed: its message, as the player reads it,
/// its kind, a key that stays the same in every language, for the
/// measurements, and the error behind it, whose domains and codes reports
/// and measurements take along.
struct CartoucheStorageError: LocalizedError, CustomNSError {
    enum Kind: String {
        /// Not enough space on this iPhone, or on the server.
        case noSpaceHere, noSpaceThere
        case readOnly
        /// The installed game, a file larger than Cartouche expects, a
        /// folder's listing too long, a copy of saves that cannot be read.
        case gameUnreadable, tooLarge, listingTooLong, copyUnreadable
        case notInBuild, noPassword, notAnApp
        /// An S3 address or bucket, an FTP name Cartouche cannot use.
        case badAddress, badBucket, badName
        /// What the place needs: keys, an account, a saves folder.
        case keysNeeded, accountNeeded, noSavesFolder
        case signInFailed, badAnswer, folderGone
        /// The SFTP server's key: none shown, or another than the one kept.
        case noHostKey, hostKeyChanged
        case noSubsystem
        /// Google Drive: not a client ID, a client Google refuses, the Drive
        /// API off in the player's project, the Drive not allowed on
        /// Google's page or no lasting sign-in, a sign-in that page did not
        /// give, a file or folder no longer there, another refusal.
        case badClient, clientRefused, driveOff, driveScope, noLastingSignIn, webSignIn, notThere, driveFailed
    }

    let kind: Kind
    let message: String
    let underlyingError: Error?
    var errorDescription: String? { message }

    var errorUserInfo: [String: Any] {
        guard let underlyingError else { return [:] }
        return [NSUnderlyingErrorKey: underlyingError as NSError]
    }

    init(_ kind: Kind, _ message: String, underlying: Error? = nil) {
        self.kind = kind
        self.message = message
        underlyingError = underlying
    }
}

// MARK: Servers and places

final class CartoucheStorageSettings: ObservableObject {
    #if os(macOS)
    /// On the Mac, the player's servers are those of the console's Storage
    /// page, the same as the paired iPhones'; its games folder and saves
    /// folder are the Builder's (CartoucheMacConsole). Nothing of it goes
    /// to the Mac's keychain, whose item an app signed again by its next
    /// update reads only once the player allows it, in a window macOS
    /// shows and waits on: the secrets are in a file (secretsFile).
    static let shared = CartoucheStorageSettings(keepsInKeychain: false)
    #else
    static let shared = CartoucheStorageSettings(keepsInKeychain: true)
    #endif

    @Published private(set) var servers: [CartoucheStorageServer] = []
    @Published private(set) var places: [CartoucheStorageRole: CartoucheStoragePlace] = [:]
    /// The servers whose shared folder lets the player's account read only,
    /// and the folders it cannot add a file to, "<server>|<path>", as
    /// Cartouche last found: it offers none of them for the saves, and
    /// copies no game there.
    @Published private(set) var readOnlyServers: Set<UUID> = []
    @Published private(set) var readOnlyFolders: Set<String> = []
    /// The servers the player removed that went over the bridge, as their
    /// paired Mac or iPhone is told, for 180 days.
    @Published private(set) var removed: [CartoucheConnection] = []
    /// A server that goes over the bridge was saved or removed here: the
    /// paired Mac takes it (CartoucheConnectionsExchange).
    let connectionsChanged = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults
    /// Whether the keychain keeps the settings too (Kept).
    let keepsInKeychain: Bool
    private static let serversKey = "Cartouche.storage.servers"
    private static let readOnlyServersKey = "Cartouche.storage.readOnly.servers"
    private static let readOnlyFoldersKey = "Cartouche.storage.readOnly.folders"
    private static let removedKey = "Cartouche.storage.removed"
    private static let keychainService = "Cartouche storage"

    /// KEEPSINKEYCHAIN: the settings go to the keychain too, and come from
    /// there when the preferences have none, as after Cartouche was
    /// installed again: the player's own settings, not the tests'.
    init(defaults: UserDefaults = .standard, keepsInKeychain: Bool = false) {
        self.defaults = defaults
        self.keepsInKeychain = keepsInKeychain
        if keepsInKeychain, defaults.object(forKey: Self.serversKey) == nil, let kept = Self.keptInKeychain() {
            kept.write(to: defaults)
            NSLog("[Cartouche] storage settings found in the keychain: %ld servers", kept.servers.count)
        }
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Self.serversKey),
           let servers = try? decoder.decode([CartoucheStorageServer].self, from: data) {
            self.servers = servers
        }
        for role in CartoucheStorageRole.allCases {
            if let data = defaults.data(forKey: Self.placeKey(role)),
               let place = try? decoder.decode(CartoucheStoragePlace.self, from: data),
               servers.contains(where: { $0.id == place.server }) {
                places[role] = place
            }
        }
        readOnlyServers = Set((defaults.stringArray(forKey: Self.readOnlyServersKey) ?? []).compactMap(UUID.init(uuidString:)))
        readOnlyFolders = Set(defaults.stringArray(forKey: Self.readOnlyFoldersKey) ?? [])
        if let data = defaults.data(forKey: Self.removedKey),
           let removed = try? decoder.decode([CartoucheConnection].self, from: data) {
            self.removed = removed
        }
        // The servers an older Cartouche kept, as changed now: one the
        // paired Mac changed since wins over them.
        if servers.contains(where: { $0.changed == nil }) {
            let now = Date()
            servers = servers.map { server in
                var dated = server
                if dated.changed == nil { dated.changed = now }
                return dated
            }
            persist()
        }
        // Settings an older Cartouche kept in the preferences only.
        if keepsInKeychain, Self.keptInKeychain() != kept {
            Self.keepInKeychain(kept)
        }
    }

    private static func placeKey(_ role: CartoucheStorageRole) -> String {
        "Cartouche.storage.\(role.rawValue)"
    }

    func server(_ id: UUID) -> CartoucheStorageServer? {
        servers.first { $0.id == id }
    }

    func place(_ role: CartoucheStorageRole) -> CartoucheStoragePlace? {
        places[role]
    }

    /// The server of ROLE's place, with that place.
    func location(_ role: CartoucheStorageRole) -> (server: CartoucheStorageServer, path: String)? {
        guard let place = places[role], let server = self.server(place.server) else { return nil }
        return (server, place.path)
    }

    /// Adds SERVER, or changes it, as changed now; a SECRET of nil keeps
    /// the one it has.
    func save(_ server: CartoucheStorageServer, secret: String?) {
        var saved = server
        saved.changed = Date()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = saved
        } else {
            servers.append(saved)
        }
        if let secret {
            Self.storeSecret(secret, for: server.id)
        }
        // Another account may write where this one could not.
        forgetAccess(of: server.id)
        if saved.travels {
            removed.removeAll { $0.id == server.id }
        }
        persist()
        if saved.travels {
            connectionsChanged.send()
        }
    }

    func remove(_ server: CartoucheStorageServer) {
        servers.removeAll { $0.id == server.id }
        for (role, place) in places where place.server == server.id {
            places[role] = nil
        }
        Self.storeSecret(nil, for: server.id)
        forgetAccess(of: server.id)
        if server.travels {
            // For the paired Mac or iPhone, which removes it too.
            removed.removeAll { $0.id == server.id }
            removed.append(CartoucheConnection(id: server.id, kind: server.kind.rawValue, name: server.name, changed: Date(), removed: true))
        }
        persist()
        if server.travels {
            connectionsChanged.send()
        }
    }

    // MARK: The same on the iPhone and its Mac

    /// The servers that go over the bridge, with their secrets, and those
    /// removed (CartoucheConnections.swift).
    func connections() -> [CartoucheConnection] {
        servers.filter(\.travels).map { $0.connection(secret: secret(of: $0)) } + removed
    }

    /// Takes THEIRS, the connections the paired Mac or iPhone keeps, as
    /// the ones changed last: added, changed or removed here, with their
    /// secrets, and the folders chosen on one removed for another moved to
    /// that one. A change made here meanwhile stays, as changed after.
    /// Whether anything changed.
    @discardableResult
    func take(_ theirs: [CartoucheConnection]) -> Bool {
        let merged = CartoucheConnections.merged(connections(), theirs)
        var servers = self.servers
        var places = self.places
        var moved = false
        var secrets: [(UUID, String?)] = []
        for connection in merged {
            if connection.removed {
                guard let index = servers.firstIndex(where: { $0.id == connection.id && $0.travels }) else { continue }
                servers.remove(at: index)
                secrets.append((connection.id, nil))
            } else if let server = CartoucheStorageServer(connection) {
                if let index = servers.firstIndex(where: { $0.id == server.id }) {
                    var kept = servers[index]
                    let before = kept
                    kept.name = server.name
                    kept.host = server.host
                    kept.port = server.port
                    kept.username = server.username
                    kept.share = server.share
                    kept.region = server.region
                    kept.hostKey = server.hostKey
                    kept.changed = server.changed
                    if kept != before {
                        servers[index] = kept
                    }
                } else {
                    servers.append(server)
                }
                if let secret = connection.secret, secret != self.secret(of: server) {
                    secrets.append((server.id, secret))
                }
            }
        }
        for (role, place) in places where !servers.contains(where: { $0.id == place.server }) {
            if let now = CartoucheConnections.current(place.server, in: merged) {
                places[role] = CartoucheStoragePlace(server: now, path: place.path)
            } else {
                places[role] = nil
            }
            moved = true
        }
        let removed = merged.filter(\.removed)
        guard servers != self.servers || places != self.places || removed != self.removed || !secrets.isEmpty || moved else {
            return false
        }
        // What the player's account may write, found with the address or
        // the account a server had before.
        for server in servers where self.server(server.id).map({ $0.host != server.host || $0.share != server.share || $0.username != server.username }) ?? false {
            forgetAccess(of: server.id)
        }
        for (id, secret) in secrets {
            Self.storeSecret(secret, for: id)
        }
        for gone in self.servers where !servers.contains(where: { $0.id == gone.id }) {
            forgetAccess(of: gone.id)
        }
        self.servers = servers
        self.places = places
        self.removed = removed
        persist()
        return true
    }

    // MARK: What the player's account may write

    private static func folderKey(_ server: UUID, _ path: String) -> String {
        server.uuidString + "|" + path
    }

    /// Whether the player's account cannot add a file to PATH on SERVER, as
    /// Cartouche last found.
    func isReadOnly(_ server: UUID, path: String) -> Bool {
        readOnlyServers.contains(server) || readOnlyFolders.contains(Self.folderKey(server, path))
    }

    /// Whether the folder of ROLE is read-only for the player's account.
    func isReadOnly(_ role: CartoucheStorageRole) -> Bool {
        guard let place = places[role] else { return false }
        return isReadOnly(place.server, path: place.path)
    }

    /// Keeps what Cartouche found on SERVER: whether its shared folder lets
    /// the account read only, and, when it asked, whether the account can
    /// add a file to the folder at PATH.
    func noteAccess(server: UUID, shareReadOnly: Bool, path: String? = nil, writable: Bool? = nil) {
        var servers = readOnlyServers
        if shareReadOnly { servers.insert(server) } else { servers.remove(server) }
        var folders = readOnlyFolders
        if let path, let writable {
            if writable {
                folders.remove(Self.folderKey(server, path))
            } else {
                folders.insert(Self.folderKey(server, path))
            }
        }
        guard servers != readOnlyServers || folders != readOnlyFolders else { return }
        readOnlyServers = servers
        readOnlyFolders = folders
        persistAccess()
    }

    /// Asks REMOTE, connected to SERVER, whether the account can add a file
    /// to the folder at PATH, and keeps the answer; nil when the server did
    /// not give one.
    @MainActor
    @discardableResult
    func checkAccess(_ remote: CartoucheRemote, server: UUID, path: String) async -> Bool? {
        let writable: Bool?
        do {
            writable = try await remote.canWrite(path)
        } catch {
            NSLog("[Cartouche] cannot tell whether %@ is writable: %@", path, error.localizedDescription)
            writable = nil
        }
        noteAccess(server: server, shareReadOnly: remote.isReadOnly, path: path, writable: writable)
        return writable
    }

    /// Signs in to SERVER, to keep whether its shared folder lets the
    /// account write, as its root does.
    @MainActor
    func checkAccess(of server: CartoucheStorageServer) async {
        guard let remote = try? await CartoucheStorage.connect(server, settings: self) else { return }
        await checkAccess(remote, server: server.id, path: "")
        await remote.disconnect()
    }

    private func forgetAccess(of server: UUID) {
        let prefix = Self.folderKey(server, "")
        guard readOnlyServers.contains(server) || readOnlyFolders.contains(where: { $0.hasPrefix(prefix) }) else { return }
        readOnlyServers.remove(server)
        readOnlyFolders = readOnlyFolders.filter { !$0.hasPrefix(prefix) }
        persistAccess()
    }

    private func persistAccess() {
        defaults.set(readOnlyServers.map(\.uuidString).sorted(), forKey: Self.readOnlyServersKey)
        defaults.set(readOnlyFolders.sorted(), forKey: Self.readOnlyFoldersKey)
        if keepsInKeychain {
            Self.keepInKeychain(kept)
        }
    }

    func setPlace(_ place: CartoucheStoragePlace?, for role: CartoucheStorageRole) {
        places[role] = place
        persist()
    }

    #if os(macOS)
    /// The Mac's saves folder, as Cartouche Builder keeps the saves of the
    /// games played on this Mac in step with it, for a game's sheet in
    /// Cartouche's console (Mac/ConsoleSaves.swift): a folder named NAME,
    /// at PATH, kept in memory only, beside the player's servers; nil for
    /// none, the saves staying on this Mac.
    func showMacSaves(name: String?, path: String) {
        var servers = self.servers.filter { $0.id != Self.macSavesID }
        var places = self.places
        if let name {
            servers.insert(CartoucheStorageServer(id: Self.macSavesID, kind: .folder, name: name), at: 0)
            places[.saves] = CartoucheStoragePlace(server: Self.macSavesID, path: path)
        } else if places[.saves]?.server == Self.macSavesID {
            places[.saves] = nil
        }
        guard servers != self.servers || places != self.places else { return }
        self.servers = servers
        self.places = places
    }

    /// The Mac's saves folder's ID, the same each time.
    static let macSavesID = UUID(uuidString: "6D616373-6176-4573-A000-000000000001")!
    #endif

    #if CARTOUCHE_GALLERY
    /// Whether the settings are the gallery's, kept in memory only.
    private var showsGallery = false

    /// SERVER, with the games folder and the saves folder on it, for the
    /// launcher's gallery (launcher/Gallery): kept in memory only.
    func showForGallery(_ server: CartoucheStorageServer, games: String, saves: String) {
        showsGallery = true
        servers = [server]
        places = [.games: CartoucheStoragePlace(server: server.id, path: games),
                  .saves: CartoucheStoragePlace(server: server.id, path: saves)]
    }
    #endif

    #if os(macOS)
    /// Whether the settings are kept in memory only, nothing of the
    /// player's read or written: the Builder's gallery's (showForGallery).
    private(set) var keepsInMemory = false

    /// SERVERS, the Mac's own for the Builder's gallery, with their
    /// SECRETS, kept in memory only from then on.
    func showForGallery(_ servers: [CartoucheStorageServer], secrets: [UUID: String] = [:]) {
        keepsInMemory = true
        Self.secretsLock.lock()
        Self.secretsFile = nil
        Self.memorySecrets = Dictionary(uniqueKeysWithValues: secrets.map { ($0.key.uuidString, $0.value) })
        Self.secretsLock.unlock()
        let saves = self.servers.filter { $0.id == Self.macSavesID }
        self.servers = saves + servers
        removed = []
    }
    #endif

    private func persist() {
        #if CARTOUCHE_GALLERY
        // The gallery's servers, kept in memory only.
        guard !showsGallery else { return }
        #endif
        let encoder = JSONEncoder()
        #if os(macOS)
        // On the Mac, the player's servers; its folders are the Builder's,
        // which the app shows the console.
        guard !keepsInMemory else { return }
        defaults.set(try? encoder.encode(servers.filter(\.travels)), forKey: Self.serversKey)
        #else
        defaults.set(try? encoder.encode(servers), forKey: Self.serversKey)
        for role in CartoucheStorageRole.allCases {
            if let place = places[role] {
                defaults.set(try? encoder.encode(place), forKey: Self.placeKey(role))
            } else {
                defaults.removeObject(forKey: Self.placeKey(role))
            }
        }
        #endif
        defaults.set(try? encoder.encode(removed), forKey: Self.removedKey)
        if keepsInKeychain {
            Self.keepInKeychain(kept)
        }
    }

    // MARK: Keychain

    /// The settings as the keychain keeps them: iOS removes an app's
    /// preferences with it, not its keychain items, so that Cartouche
    /// installed again finds the player's servers, their secrets and
    /// folders as they were, and the games' saves come back.
    struct Kept: Codable, Equatable {
        var servers: [CartoucheStorageServer]
        /// By role.
        var places: [String: CartoucheStoragePlace]
        var readOnlyServers: [String]
        var readOnlyFolders: [String]
        /// The servers removed that the paired Mac is told of; none for
        /// what an older Cartouche kept.
        var removed: [CartoucheConnection]?

        /// Puts them in the preferences, where the settings read them.
        func write(to defaults: UserDefaults) {
            let encoder = JSONEncoder()
            defaults.set(try? encoder.encode(servers), forKey: CartoucheStorageSettings.serversKey)
            for role in CartoucheStorageRole.allCases {
                if let place = places[role.rawValue] {
                    defaults.set(try? encoder.encode(place), forKey: CartoucheStorageSettings.placeKey(role))
                }
            }
            defaults.set(readOnlyServers, forKey: CartoucheStorageSettings.readOnlyServersKey)
            defaults.set(readOnlyFolders, forKey: CartoucheStorageSettings.readOnlyFoldersKey)
            if let removed {
                defaults.set(try? encoder.encode(removed), forKey: CartoucheStorageSettings.removedKey)
            }
        }
    }

    private var kept: Kept {
        Kept(servers: servers,
             places: Dictionary(uniqueKeysWithValues: places.map { ($0.key.rawValue, $0.value) }),
             readOnlyServers: readOnlyServers.map(\.uuidString).sorted(),
             readOnlyFolders: readOnlyFolders.sorted(),
             removed: removed)
    }

    /// The keychain item of the settings, beside the servers' secrets.
    private static let keptAccount = "settings"

    private static func keptInKeychain() -> Kept? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keptAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Kept.self, from: data)
    }

    private static func keepInKeychain(_ kept: Kept) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keptAccount,
        ]
        SecItemDelete(item as CFDictionary)
        guard let data = try? JSONEncoder().encode(kept) else { return }
        var added = item
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(added as CFDictionary, nil)
    }

    func secret(of server: CartoucheStorageServer) -> String? {
        #if os(macOS)
        return Self.macSecret(server.id)
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: server.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
        #endif
    }

    private static func storeSecret(_ secret: String?, for id: UUID) {
        #if os(macOS)
        storeMacSecret(secret, for: id)
        #else
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(item as CFDictionary)
        guard let secret, !secret.isEmpty else { return }
        var added = item
        added[kSecValueData as String] = Data(secret.utf8)
        // Readable after the first unlock, so that a backup after a game
        // can reach the server while the iPhone is locked.
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(added as CFDictionary, nil)
        #endif
    }

    #if os(macOS)
    // MARK: The Mac's secrets

    /// The file of the servers' secrets on the Mac, in Cartouche Builder's
    /// folder beside the bridge's keys: readable by the player's session
    /// only (0600), never in a report. The app sets it (keepSecrets) before
    /// the console first reads the storage; without it, as for the app's
    /// gallery and the tests, the secrets are kept in memory.
    nonisolated(unsafe) private static var secretsFile: URL?
    nonisolated(unsafe) private static var memorySecrets: [String: String] = [:]
    private static let secretsLock = NSLock()

    /// Keeps the servers' secrets in FILE from now on, as Cartouche
    /// Builder's folder has it (connections.json).
    static func keepSecrets(in file: URL?) {
        secretsLock.lock()
        secretsFile = file
        secretsLock.unlock()
    }

    /// The file's contents: the secrets by server ID.
    private struct SecretsFile: Codable {
        var secrets: [String: String]
    }

    private static func macSecrets() -> [String: String] {
        guard let url = secretsFile else { return memorySecrets }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SecretsFile.self, from: data) else { return [:] }
        return file.secrets
    }

    static func macSecret(_ id: UUID) -> String? {
        secretsLock.lock()
        defer { secretsLock.unlock() }
        return macSecrets()[id.uuidString]
    }

    /// Keeps SECRET for the server ID, or none, in the file written whole,
    /// readable by the player only from its first byte.
    private static func storeMacSecret(_ secret: String?, for id: UUID) {
        secretsLock.lock()
        defer { secretsLock.unlock() }
        var secrets = macSecrets()
        if let secret, !secret.isEmpty {
            secrets[id.uuidString] = secret
        } else {
            secrets[id.uuidString] = nil
        }
        guard let url = secretsFile else {
            memorySecrets = secrets
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(SecretsFile(secrets: secrets)) else { return }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let written = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8))")
        guard manager.createFile(atPath: written.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            NSLog("[Cartouche] cannot keep the storage's secrets in %@", folder.path)
            return
        }
        if rename(written.path, url.path) != 0 {
            NSLog("[Cartouche] cannot keep the storage's secrets in %@: %d", url.path, errno)
            try? manager.removeItem(at: written)
        }
    }
    #endif
}

// MARK: Reaching a server

/// A folder or a file on the player's storage.
struct CartoucheRemoteItem: Hashable {
    let name: String
    let isFolder: Bool
    let size: UInt64
    let modified: Date?
}

/// One of the player's servers, signed in to.
protocol CartoucheRemote: AnyObject {
    /// The folders and files in PATH, without hidden ones.
    func list(_ path: String) async throws -> [CartoucheRemoteItem]
    /// The file at PATH, to read.
    func open(_ path: String) async throws -> CartoucheByteSource
    /// A new file at PATH, which replaces the one there, if any, only once
    /// it is finished. SIZE, when known, lets some servers take it in one go.
    func create(_ path: String, size: UInt64?) async throws -> CartoucheRemoteUpload
    func makeFolder(_ path: String) async throws
    func delete(_ path: String) async throws
    /// The room left, when the server says.
    func freeSpace() async throws -> UInt64?
    /// Whether this account can write nowhere here: a shared folder whose
    /// permissions let it read only.
    var isReadOnly: Bool { get }
    /// Whether this account can add a file to the folder at PATH. Asking
    /// leaves the folder as it was.
    func canWrite(_ path: String) async throws -> Bool
    func disconnect() async
}

/// A file being written to the player's storage.
protocol CartoucheRemoteUpload: CartoucheByteSink {
    /// Puts the file in place.
    func finish() async throws
    /// Gives it up, and removes what was written.
    func cancel() async
}

extension CartoucheRemote {
    /// Makes PATH and the folders above it that are missing.
    func makeFolders(_ path: String) async throws {
        var made = ""
        for part in path.split(separator: "/") {
            made = CartoucheStoragePath.join(made, String(part))
            let parent = CartoucheStoragePath.parent(made)
            let items = try await list(parent)
            if !items.contains(where: { $0.isFolder && $0.name == String(part) }) {
                try await makeFolder(made)
            }
        }
    }

    /// Writes DATA to PATH.
    func write(_ data: Data, to path: String) async throws {
        let upload = try await create(path, size: UInt64(data.count))
        do {
            try await upload.write(data)
            try await upload.finish()
        } catch {
            await upload.cancel()
            throw error
        }
    }

    /// The whole file at PATH, for a small one.
    func read(_ path: String, limit: Int = 16 << 20) async throws -> Data {
        let source = try await open(path)
        guard source.size <= UInt64(limit) else {
            throw CartoucheStorageError(.tooLarge, CartoucheText.storageTooLarge(CartoucheStoragePath.name(path)))
        }
        return try await source.read(at: 0, count: Int(source.size))
    }
}

enum CartoucheStorage {
    /// Whether this build reaches shared folders over SMB.
    static var hasSMB: Bool {
        #if canImport(SMBClient)
        return true
        #else
        return false
        #endif
    }

    /// Signs in to SERVER with PASSWORD, as a form holds them, before it is
    /// saved; for SFTP, with the key it keeps, if any, and gives the key the
    /// server showed.
    static func check(_ server: CartoucheStorageServer, password: String) async throws -> (remote: CartoucheRemote, hostKey: String?) {
        switch server.kind {
        case .ftp:
            let remote = try await CartoucheFTP.connect(server, password: password)
            return (remote, nil)
        case .sftp:
            #if canImport(NIOSSH)
            let remote = try await CartoucheSFTPServer.connect(server, password: password, knownKey: server.hostKey)
            return (remote, remote.hostKey)
            #else
            throw CartoucheStorageError(.notInBuild, "SFTP is not in this build")
            #endif
        case .smb, .folder, .s3, .mac, .drive:
            throw CartoucheStorageError(.noPassword, "Not a server signed in to with a password here")
        }
    }

    /// Whether this build reaches servers over SFTP.
    static var hasSFTP: Bool {
        #if canImport(NIOSSH)
        return true
        #else
        return false
        #endif
    }

    /// Signs in to SERVER, and keeps whether it answers from here
    /// (CartoucheStorageReach): a server that takes no connection within
    /// the patience throws CartoucheStorageOffline.
    static func connect(_ server: CartoucheStorageServer,
                        settings: CartoucheStorageSettings = .shared) async throws -> CartoucheRemote {
        do {
            let remote = try await signIn(server, settings: settings)
            await MainActor.run { CartoucheStorageReach.shared.noteAnswered(server) }
            return remote
        } catch let offline as CartoucheStorageOffline {
            await MainActor.run { CartoucheStorageReach.shared.noteOffline(server) }
            throw offline
        }
    }

    private static func signIn(_ server: CartoucheStorageServer,
                               settings: CartoucheStorageSettings) async throws -> CartoucheRemote {
        let secret = settings.secret(of: server) ?? ""
        switch server.kind {
        case .smb:
            #if canImport(SMBClient)
            return try await CartoucheSMB.connect(server, password: secret)
            #else
            throw CartoucheStorageError(.notInBuild, "SMB is not in this build")
            #endif
        case .folder:
            return try CartoucheFolder(server)
        case .s3:
            return try await CartoucheS3.connect(server, secretKey: secret)
        case .ftp:
            return try await CartoucheFTP.connect(server, password: secret)
        case .sftp:
            #if canImport(NIOSSH)
            let remote = try await CartoucheSFTPServer.connect(server, password: secret, knownKey: server.hostKey)
            if server.hostKey == nil {
                // Kept from now on: another key will be refused.
                var kept = server
                kept.hostKey = remote.hostKey
                await MainActor.run {
                    // Unless the player removed the server meanwhile.
                    if settings.servers.contains(where: { $0.id == kept.id }) {
                        settings.save(kept, secret: nil)
                    }
                }
            }
            return remote
            #else
            throw CartoucheStorageError(.notInBuild, "SFTP is not in this build")
            #endif
        case .mac:
            return try await CartoucheMacStorage.connect(server, secret: secret, settings: settings)
        case .drive:
            return try await CartoucheDrive.connect(server, refreshToken: secret)
        }
    }
}

enum CartoucheStoragePath {
    /// PARTS joined by "/", without empty ones or slashes at the ends.
    static func join(_ parts: String...) -> String {
        parts.flatMap { $0.split(separator: "/").map(String.init) }.joined(separator: "/")
    }

    static func parent(_ path: String) -> String {
        var parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return "" }
        parts.removeLast()
        return parts.joined(separator: "/")
    }

    static func name(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    /// TEXT as a file name every server takes: without / \ : * ? " < > |
    /// or control characters, nor a dot or a space at its ends.
    static func fileName(_ text: String) -> String {
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = String(text.unicodeScalars.map { refused.contains($0) ? " " : Character($0) })
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "Game" : String(cleaned.prefix(120))
    }
}
