//
//  CartoucheTextNaming.swift
//  Cartouche
//
//  The words of the help on naming what the games folder, the saves folder
//  and Cartouche Builder's dumps folder hold (CartoucheNamingView.swift,
//  CartoucheNaming.swift), in Cartouche.xcstrings with the others
//  (CartoucheText.swift).
//

import Foundation

extension CartoucheText {
    // MARK: Naming the games

    static var namingTitle: String { s("naming.title", "Naming your games") }
    static var namingOpen: String { s("naming.open", "How to name your games") }
    static var namingIntro: String { s("naming.intro", "Cartouche and Cartouche Builder know a game by its title ID: the 16 letters and digits in square brackets in its name, as they name what they write. A game’s sheet shows its title ID.") }
    static var namingFound: String { s("naming.found", "Found") }
    static var namingLeftAside: String { s("naming.leftAside", "Left aside") }

    /// The header of PLACE's examples.
    static func namingPlace(_ place: CartoucheNaming.Place) -> String {
        switch place {
        case .games: return storageGamesFolder
        case .saves: return storageSavesFolder
        case .dumps: return s("naming.dumps", "Dumps folder, for Cartouche Builder")
        }
    }

    /// Below PLACE's examples.
    static func namingFooter(_ place: CartoucheNaming.Place) -> String {
        switch place {
        case .games: return s("naming.games.footer", "Cartouche Builder puts each game’s IPA here, named so; a game copied here from its sheet is named the same way.")
        case .saves: return s("naming.saves.footer", "Cartouche names these itself: leave their names as they are.")
        case .dumps: return f("naming.dumps.footer", "Loose or each in its folder, up to %lld folders down. A name without its title ID works too: Cartouche Builder then reads it inside, which takes your prod.keys for a package.", CartoucheNaming.dumpsDepth)
        }
    }

    /// What an example's place makes of it.
    static func namingWhy(_ meaning: CartoucheNaming.Meaning) -> String {
        switch meaning {
        case .namedIPA: return s("naming.namedIPA", "An IPA, named as Cartouche and Cartouche Builder name it: the game, then its title ID.")
        case .unnamedIPA: return s("naming.unnamedIPA", "Any other name ending in .ipa: Cartouche then reads the game inside, a little slower.")
        case .gameFiles: return s("naming.gameFiles", "The image of a game’s files, for an IPA built without them: any name ending in romfs.img, beside its IPA or elsewhere in the folder.")
        case .macApp: return s("naming.macApp", "A game built for the Mac, which Cartouche Builder keeps beside its IPA on a NAS: leave it there.")
        case .tooDeep: return s("naming.tooDeep", "Two folders down: Cartouche reads the folder and the folders right in it, no deeper.")
        case .gameFolder: return s("naming.gameFolder", "A folder per game, which Cartouche makes: any name, as long as it ends with the game’s title ID.")
        case .copy: return f("naming.copy", "A copy of the game’s saves, named after when it was made, in UTC. The %lld newest are kept.", CartoucheSaveSync.kept)
        case .unnamedFolder: return s("naming.unnamedFolder", "Without the game’s title ID: Cartouche makes the game’s own folder beside it.")
        case .notACopy: return s("naming.notACopy", "Not a copy Cartouche made: it stays as it is, never put back.")
        case .package: return s("naming.package", "A game’s package: .nsp, .xci, .nsz or .xcz, read with your prod.keys.")
        case .update: return s("naming.update", "Its update, beside it: an update’s title ID is its game’s with 800 at its end instead of 000. Its DLC go beside it too.")
        case .nup: return s("naming.nup", "A Switch 2 game, in its .nup.")
        case .dump: return s("naming.dump", "A dump, as nxnative lays it out (base/exefs and base/romfs, or exefs and romfs, then updates and dlc), or zipped: any name, its title ID is read inside.")
        case .buildFolder: return s("naming.buildFolder", "A folder ending in _build, where nxnative builds, or in _dump, and the Finder’s __MACOSX: never a game.")
        case .built: return s("naming.built", "An IPA or a romfs.img is no dump: put them in the games folder.")
        }
    }
}
