//
//  ConsoleStorage.swift
//  Cartouche on the Mac
//
//  The player's storage in Cartouche's console on the Mac: the iPhone's
//  Storage page (Shared/CartoucheStorageView.swift), whose connections, a
//  NAS, a bucket, an FTP or SFTP server or a Google Drive with their
//  passwords, are the same as the paired iPhones' (CartoucheConnections.swift).
//  The app gives the console what a paired iPhone gives its bridge, as
//  JSON, its CartoucheCore having a type of a connection of its own, and
//  has the console keep their secrets in a file of the Builder's folder,
//  readable by the player's account only, never in the Mac's keychain
//  (CartoucheStorageSettings). In place of the iPhone's games folder and
//  saves folder, This Mac: the Builder's own, where the console takes the
//  games it shows and the Builder keeps the saves of the games played
//  here, which the player changes in the Builder; unless the saves folder
//  chosen on the iPhone is on one of the connections, where the Builder
//  keeps them then, and which the page shows as the iPhone does. The games
//  folder chosen on the iPhone, when it is on one of the connections, the
//  page shows under This Mac: the Builder sends its games there, how many
//  went, the one going, or why none goes.
//

import Combine
import SwiftUI

/// The Builder's games folder and saves folder, as This Mac shows them.
public struct CartoucheMacFolders: Equatable, Sendable {
    public var games: URL?
    public var saves: URL?

    public init(games: URL?, saves: URL?) {
        self.games = games
        self.saves = saves
    }
}

/// The iPhone's games folder, on one of the player's connections, as the
/// Builder sends its games there.
public struct CartoucheMacGamesFolder: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Not looked at yet.
        case waiting
        /// GAME's file going, DONE of TOTAL bytes, the INDEX of COUNT: its
        /// Mac app PACKING in one file first.
        case sending(game: String, packing: Bool, done: UInt64, total: UInt64, index: Int, count: Int)
        /// SENT of the Builder's TOTAL files there, as the last look found.
        case sent(Int, of: Int)
        /// Its server does not answer from here.
        case offline
        /// The player's account may only read it.
        case readOnly
        /// Without the room for the next file.
        case noRoom(needed: UInt64, free: UInt64)
        /// What failed, in the player's words.
        case failed(String)
    }

    public var connection: UUID
    public var path: String
    public var state: State
    /// The Mac apps another Mac sent there, to install from the library.
    public var offers: Int

    public init(connection: UUID, path: String, state: State, offers: Int = 0) {
        self.connection = connection
        self.path = path
        self.state = state
        self.offers = offers
    }
}

extension CartoucheMacConsole {
    /// Keeps the passwords, secret keys and Google sign-ins of the player's
    /// connections in FILE from now on, the Builder's connections.json:
    /// once, as the app starts, before its bridge first gives the console
    /// a paired iPhone's.
    public static func keepConnectionSecrets(in file: URL) {
        CartoucheStorageSettings.keepSecrets(in: file)
    }

    /// Takes THEIRS, a paired iPhone's connections as its bridge gives them
    /// (JSON), and gives this Mac's once it took them, the same JSON: both
    /// keep the same from then on. Nil for what is no list of connections,
    /// which changes nothing.
    public func takeConnections(_ theirs: Data) -> Data? {
        Self.takeConnections(theirs, in: .shared)
    }

    static func takeConnections(_ theirs: Data, in settings: CartoucheStorageSettings) -> Data? {
        guard let connections = try? JSONDecoder().decode([CartoucheConnection].self, from: theirs) else { return nil }
        settings.take(connections)
        return try? JSONEncoder().encode(settings.connections())
    }

    /// A moment after the player adds, changes or removes one of their
    /// connections here, on the Storage page: the iPhone's saves folder,
    /// where the Builder keeps this Mac's games' saves, may be on it.
    public var connectionsChanged: AnyPublisher<Void, Never> {
        CartoucheStorageSettings.shared.connectionsChanged
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// The gallery's NAS, among the made-up connections of
    /// showStorageForGallery(language:).
    public static let galleryNAS = UUID(uuidString: "6E617364-7520-4073-A000-000000000001")!

    /// Made-up connections on the Storage page, a NAS, a bucket and a
    /// Google Drive, named in LANGUAGE, for the app's gallery: kept in
    /// memory only, nothing of the player's read or written from then on.
    public func showStorageForGallery(language: String) {
        let french = language == "fr"
        let changed = Date()
        CartoucheStorageSettings.shared.showForGallery([
            CartoucheStorageServer(id: Self.galleryNAS, kind: .smb, name: french ? "NAS du salon" : "Living room NAS", host: "192.168.1.20",
                                   username: french ? "joueur" : "player", share: french ? "Jeux" : "Games", changed: changed),
            CartoucheStorageServer(kind: .s3, name: french ? "Sauvegardes" : "Saves", host: "s3.eu-west-3.amazonaws.com",
                                   username: "AKIAIOSFODNN7EXAMPLE", share: "cartouche-saves", region: "eu-west-3", changed: changed),
            CartoucheStorageServer(kind: .drive, name: "Google Drive", host: french ? "joueur@example.com" : "player@example.com",
                                   username: "123456789012-example.apps.googleusercontent.com", changed: changed),
        ])
    }
}

/// This Mac, on the Storage page in place of the iPhone's games folder and
/// saves folder: the Builder's own, which the player changes in the
/// Builder, and the row of those sections that opens how to name the
/// games.
struct CartoucheMacFoldersSection: View {
    @ObservedObject private var console = CartoucheMacConsole.shared
    @ObservedObject private var settings = CartoucheStorageSettings.shared

    // Written out, as the private state above makes the synthesized
    // initializer private.
    init() {}

    var body: some View {
        thisMac
        // The iPhone's games folder, on a connection: the Builder sends its
        // games there.
        if let folder = console.iPhoneGames, let server = settings.server(folder.connection) {
            CartoucheMacIPhoneGamesSection(folder: folder, server: server) { console.onSendGames() }
        }
    }

    private var thisMac: some View {
        CartoucheSection {
            row(CartoucheText.storageGamesFolder, symbol: "square.stack.3d.up.fill", folder: console.folders.games)
            // The iPhone's, on a connection, in its own section below.
            if !settings.keepsMacSavesOnConnection {
                row(CartoucheText.storageSavesFolder, symbol: "clock.arrow.circlepath", folder: console.folders.saves)
            }
            // How to name the games, their saves and the dumps: under the
            // games folder on the iPhone, under This Mac's folders here.
            NavigationLink(value: CartoucheMacConsoleView.Route.naming) {
                Label(CartoucheText.namingOpen, systemImage: "text.badge.checkmark")
            }
            .accessibilityIdentifier(CartoucheStorageView.namingRow)
            Button {
                console.onFolders()
            } label: {
                Label(CartoucheText.macStorageChangeInBuilder, systemImage: "folder")
            }
        } header: {
            Text(CartoucheText.macStorageThisMac)
        } footer: {
            Text(settings.keepsMacSavesOnConnection ? CartoucheText.macStorageThisMacGamesFooter : CartoucheText.macStorageThisMacFooter)
        }
    }

    private func row(_ title: String, symbol: String, folder: URL?) -> some View {
        LabeledContent {
            Text(folder.map(Self.name) ?? CartoucheText.storageNotSet)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    /// FOLDER as the player knows it: "Jeux › Switch" for a folder of the
    /// NAS mounted as Jeux, "~/Jeux" for one of their own.
    static func name(_ folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        if path.hasPrefix("/Volumes/") {
            return path.dropFirst("/Volumes/".count).split(separator: "/").joined(separator: " › ")
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

/// The iPhone's games folder, on the connection SERVER, as the Builder
/// sends its games there: the folder, how many of its files went, the one
/// going, or why none goes; the Mac apps another Mac sent there; and Send
/// now, SEND.
struct CartoucheMacIPhoneGamesSection: View {
    let folder: CartoucheMacGamesFolder
    let server: CartoucheStorageServer
    let send: () -> Void

    var body: some View {
        CartoucheSection {
            LabeledContent {
                Text(CartoucheStorageView.placeName(server: server, path: folder.path))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label(CartoucheText.storageGamesFolder, systemImage: "square.stack.3d.up.fill")
            }
            state
            if folder.offers > 0 {
                Label(CartoucheText.macIPhoneGamesOffers(folder.offers), systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(CartoucheText.macIPhoneGamesSendNow, systemImage: "arrow.up.circle", action: send)
                .disabled(sending)
        } header: {
            Text(CartoucheText.macIPhoneGamesHeader)
        } footer: {
            Text(CartoucheText.macIPhoneGamesFooter)
        }
    }

    private var sending: Bool {
        if case .sending = folder.state { return true }
        return false
    }

    @ViewBuilder
    private var state: some View {
        switch folder.state {
        case .waiting:
            LabeledContent(CartoucheText.macIPhoneGamesSent) {
                ProgressView().controlSize(.small)
            }
        case let .sending(game, packing, done, total, index, count):
            VStack(alignment: .leading, spacing: 6) {
                Text(CartoucheText.macIPhoneGamesSending(game, index, count))
                if packing {
                    Text(CartoucheText.macIPhoneGamesPacking)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
                    Text(CartoucheText.macIPhoneGamesBytes(CartoucheText.size(bytes: done), CartoucheText.size(bytes: total)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        case let .sent(sent, total):
            LabeledContent(CartoucheText.macIPhoneGamesSent) {
                Text(CartoucheText.macIPhoneGamesCount(sent, total))
                    .monospacedDigit()
            }
        case .offline:
            problem(CartoucheText.macIPhoneGamesOffline(server.name), symbol: "wifi.slash")
        case .readOnly:
            problem(CartoucheText.macIPhoneGamesReadOnly, symbol: "lock")
        case let .noRoom(needed, free):
            problem(CartoucheText.macIPhoneGamesNoRoom(CartoucheText.size(bytes: needed), CartoucheText.size(bytes: free)),
                    symbol: "externaldrive.badge.exclamationmark")
        case let .failed(reason):
            problem(CartoucheText.macIPhoneGamesFailed(reason), symbol: "exclamationmark.triangle")
        }
    }

    private func problem(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(Color.orange)
    }
}

extension CartoucheText {
    static var macStorageThisMac: String { s("mac.storage.thisMac", "This Mac") }
    static var macStorageThisMacFooter: String {
        s("mac.storage.thisMac.footer",
          "Cartouche Builder’s folders, which your iPhones reach through it: its games folder keeps the games it builds, and its saves folder the saves of your games.")
    }
    static var macStorageChangeInBuilder: String { s("mac.storage.change", "Change in Cartouche Builder") }
    static var macStorageThisMacGamesFooter: String {
        s("mac.storage.thisMac.games.footer",
          "Cartouche Builder’s games folder, which your iPhones reach through it, keeps the games it builds.")
    }

    /// Under the iPhone's saves folder, on a connection.
    static func macStorageIPhoneSavesFooter(_ kept: Int) -> String {
        f("mac.storage.iPhoneSaves.footer",
          "The saves folder chosen on your iPhone: Cartouche Builder keeps the saves of the games played on this Mac there too, through the same connection, before and after each game, as the iPhone does. The %lld newest copies are kept. To change it, choose another on the iPhone.",
          kept)
    }

    /// The iPhone's games folder, on a connection, where the Builder sends
    /// its games: named apart from This Mac's games folder above it.
    static var macIPhoneGamesHeader: String { s("mac.storage.iPhoneGames.header", "The iPhone’s games folder") }
    static var macIPhoneGamesSent: String { s("mac.storage.iPhoneGames.sent", "Sent from this Mac") }
    static func macIPhoneGamesCount(_ sent: Int, _ total: Int) -> String {
        f("mac.storage.iPhoneGames.count", "%1$lld of %2$lld", sent, total)
    }
    static func macIPhoneGamesSending(_ game: String, _ index: Int, _ count: Int) -> String {
        f("mac.storage.iPhoneGames.sending", "Sending: %1$@ (%2$lld of %3$lld)", game, index, count)
    }
    static var macIPhoneGamesPacking: String {
        s("mac.storage.iPhoneGames.packing", "Its Mac app is first packed in one file, as a NAS keeps it.")
    }
    static func macIPhoneGamesBytes(_ done: String, _ total: String) -> String {
        f("mac.storage.iPhoneGames.bytes", "%1$@ of %2$@", done, total)
    }
    static func macIPhoneGamesOffline(_ server: String) -> String {
        f("mac.storage.iPhoneGames.offline", "%@ does not answer from this Mac: this Mac’s games go there once it does.", server)
    }
    static var macIPhoneGamesReadOnly: String {
        s("mac.storage.iPhoneGames.readOnly", "Your account may only read this folder: this Mac’s games cannot go there.")
    }
    static func macIPhoneGamesNoRoom(_ needed: String, _ free: String) -> String {
        f("mac.storage.iPhoneGames.noRoom", "Not enough room there for the next game: %1$@ needed, %2$@ left. Once there is, this Mac’s games go on.", needed, free)
    }
    static func macIPhoneGamesFailed(_ reason: String) -> String {
        f("mac.storage.iPhoneGames.failed", "The last sending stopped, and starts again at the next look: %@", reason)
    }
    static func macIPhoneGamesOffers(_ count: Int) -> String {
        count == 1 ? s("mac.storage.iPhoneGames.offers.one", "1 Mac app another Mac sent there, to install from the library")
            : f("mac.storage.iPhoneGames.offers.many", "%lld Mac apps another Mac sent there, to install from the library", count)
    }
    static var macIPhoneGamesSendNow: String { s("mac.storage.iPhoneGames.sendNow", "Send now") }
    static var macIPhoneGamesFooter: String {
        s("mac.storage.iPhoneGames.footer",
          "The games folder chosen on your iPhone: Cartouche Builder sends it each IPA and each Mac app of its own games folder too, through the same connection, the newest first, and never removes anything there. The Mac apps another Mac sent there install from the library. To change it, choose another on the iPhone.")
    }

    /// Under the connections of the console's Storage page.
    static var storageConnectionsFooter: String {
        s("mac.storage.connections.footer",
          "Only storage of your own, with your own account. The iPhones paired with this Mac have the same connections, passwords included, over the bridge’s encryption: they take the changes made here when Cartouche opens on them, and send theirs here as they make them. Cartouche Builder keeps the passwords and keys in a file of its folder that only your account can read, never in the Mac’s keychain.")
    }
}
