//
//  GalleryGamesFolders.swift
//  CartoucheGallery
//
//  Two games folders at once (-GalleryWork games-folders): a NAS's, the
//  first, out of reach away from home, and a Google Drive's, which answers.
//  The player's games are in both; the sheet's game too, its newer build on
//  the NAS: Cartouche offers the Drive's copy, which it can reach
//  (CartoucheGameCopies.swift). Made-up servers and accounts.
//

import Foundation

enum GalleryGamesFolders {
    static let nas = CartoucheStorageServer(id: UUID(uuidString: "6E617364-6761-4D65-A000-000000000001")!, kind: .smb, name: "NAS",
                                            host: "nas.local", username: "joueur", share: "Partage")
    static let drive = CartoucheStorageServer(id: UUID(uuidString: "64726976-6567-4D65-A000-000000000002")!, kind: .drive,
                                              name: "Google Drive", host: "joueur@example.com",
                                              username: "123456789012-cartouchegallery.apps.googleusercontent.com")

    /// The NAS's folder and the Drive's as the games folders, the NAS's
    /// saves folder, the NAS offline; OWNED's IPAs in both, and SHEET's,
    /// a game the player does not have yet, newer on the NAS.
    @MainActor
    static func prepare(owned: [CartoucheNxGame], sheet: CartoucheNxGame?) {
        let nasGames = CartoucheStoragePlace(server: nas.id, path: "Jeux")
        let driveGames = CartoucheStoragePlace(server: drive.id, path: "Jeux")
        CartoucheStorageSettings.shared.showForGallery([nas, drive], games: [nasGames, driveGames],
                                                       saves: CartoucheStoragePlace(server: nas.id, path: "Sauvegardes"))
        CartoucheStorageReach.shared.showOfflineForGallery([nas.id])
        let built = Date().addingTimeInterval(-9 * 3_600)
        var stored: [CartoucheStoredGame] = []
        for game in owned {
            for place in [nasGames, driveGames] {
                stored.append(copy(of: game, in: place, version: "1.0.0", built: built))
            }
        }
        if let sheet {
            // Built again last night, copied to the NAS only so far.
            stored.append(copy(of: sheet, in: nasGames, version: "1.1.0", built: Date().addingTimeInterval(-5 * 3_600)))
            stored.append(copy(of: sheet, in: driveGames, version: "1.0.0", built: Date().addingTimeInterval(-3 * 86_400)))
        }
        CartoucheStoredGames.shared.showForGallery(stored, server: nas.name)
    }

    private static func copy(of game: CartoucheNxGame, in place: CartoucheStoragePlace, version: String,
                             built: Date) -> CartoucheStoredGame {
        CartoucheStoredGame(
            path: "\(place.path)/\(game.name) [\(game.titleId)].ipa", size: 21_474_836_480, modified: built,
            bundleId: "org.nxnative." + game.titleId.lowercased(), displayName: game.name, version: version,
            build: CartoucheGameBuild(version: version, commit: version == "1.0.0" ? "7bddb8c1e2f3" : "9c1d0e7a4b52",
                                      chain: "adec7d81d970", builtAt: built.addingTimeInterval(-120)),
            titleId: game.titleId, isGame: true, server: place.server, folder: place.path)
    }
}
