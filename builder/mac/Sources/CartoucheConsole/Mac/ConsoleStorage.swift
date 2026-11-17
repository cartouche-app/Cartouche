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
//  here, which the player changes in the Builder.
//

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

    /// Made-up connections on the Storage page, a NAS, a bucket and a
    /// Google Drive, named in LANGUAGE, for the app's gallery: kept in
    /// memory only, nothing of the player's read or written from then on.
    public func showStorageForGallery(language: String) {
        let french = language == "fr"
        let changed = Date()
        CartoucheStorageSettings.shared.showForGallery([
            CartoucheStorageServer(kind: .smb, name: french ? "NAS du salon" : "Living room NAS", host: "192.168.1.20",
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

    // Written out, as the private state above makes the synthesized
    // initializer private.
    init() {}

    var body: some View {
        CartoucheSection {
            row(CartoucheText.storageGamesFolder, symbol: "square.stack.3d.up.fill", folder: console.folders.games)
            row(CartoucheText.storageSavesFolder, symbol: "clock.arrow.circlepath", folder: console.folders.saves)
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
            Text(CartoucheText.macStorageThisMacFooter)
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

extension CartoucheText {
    static var macStorageThisMac: String { s("mac.storage.thisMac", "This Mac") }
    static var macStorageThisMacFooter: String {
        s("mac.storage.thisMac.footer",
          "Cartouche Builder’s folders, which your iPhones reach through it: its games folder keeps the games it builds, and its saves folder the saves of your games.")
    }
    static var macStorageChangeInBuilder: String { s("mac.storage.change", "Change in Cartouche Builder") }

    /// Under the connections of the console's Storage page.
    static var storageConnectionsFooter: String {
        s("mac.storage.connections.footer",
          "Only storage of your own, with your own account. The iPhones paired with this Mac have the same connections, passwords included, over the bridge’s encryption: they take the changes made here when Cartouche opens on them, and send theirs here as they make them. Cartouche Builder keeps the passwords and keys in a file of its folder that only your account can read, never in the Mac’s keychain.")
    }
}
