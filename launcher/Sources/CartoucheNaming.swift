//
//  CartoucheNaming.swift
//  Cartouche
//
//  How the player's files are named for Cartouche and Cartouche Builder to
//  find them: the IPAs of the games folder and the images of their game
//  files, the saves folder's games and their copies, and the dumps of the
//  Builder's dumps folder, on the Mac. A game is known by its title ID, the
//  16 letters and digits in square brackets of its name, as Cartouche and
//  the Builder name what they write: "<game> [<title ID>]".
//
//  The Storage page shows how, with the examples below
//  (CartoucheNamingView.swift), on the iPhone and from the Builder's
//  settings, its setup assistant and its library on the Mac. Their games
//  are made up, as are their title IDs. The tests check each example
//  against the rules the names are read by, here or those these call
//  (CartoucheNamingTests), and the dumps against the Builder's own
//  (builder/tests/test_naming.py): the help says what both do.
//
//  Platform-independent: tested on its own by launcher/Package.swift.
//

import Foundation

enum CartoucheNaming {
    // MARK: The rules

    /// The title ID in a name such as "Example Quest [0100F00D0BAD0000].ipa":
    /// 16 hexadecimal digits in square brackets, in any letter case.
    static func titleId(inName name: String) -> String? {
        guard let range = name.range(of: #"\[[0-9A-Fa-f]{16}\]"#, options: .regularExpression) else { return nil }
        return String(name[range].dropFirst().dropLast()).uppercased()
    }

    /// Whether NAME is an IPA's, in any letter case: the games folder's
    /// games, at its top and in the folders right in it.
    static func isIPA(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".ipa")
    }

    /// Whether NAME is the saves folder's folder of the game TITLEID's
    /// copies: its name ends with the game's "[<title ID>]", whatever is
    /// before it, which a Mac gives after the game's app for the Mac.
    static func isSavesFolder(_ name: String, of titleId: String) -> Bool {
        name.uppercased().hasSuffix("[\(titleId.uppercased())]")
    }

    /// How many folders down Cartouche Builder looks for dumps in its dumps
    /// folder (builder/cartouche_builder/library.py, MAX_DEPTH).
    static let dumpsDepth = 4

    // MARK: The examples

    /// Where an example is.
    enum Place: String, CaseIterable, Identifiable {
        /// The games folder, where Cartouche finds the games to install and
        /// Cartouche Builder puts the IPAs it builds.
        case games
        /// The saves folder, where Cartouche keeps each game's saves.
        case saves
        /// Cartouche Builder's dumps folder, on the Mac, which the Builder
        /// only reads.
        case dumps

        var id: String { rawValue }
    }

    /// What an example's place makes of it, each said by one example.
    enum Meaning: String, CaseIterable {
        // The games folder.
        case namedIPA, unnamedIPA, gameFiles, macApp, tooDeep
        // The saves folder.
        case gameFolder, copy, unnamedFolder, notACopy
        // The dumps folder.
        case package, update, nup, dump, buildFolder, built
    }

    /// A name, whether its place finds it or leaves it aside, and why.
    struct Example: Hashable, Identifiable {
        enum Verdict { case found, leftAside }

        let place: Place
        /// Its path in its place, a folder's ending with "/".
        let path: String
        let verdict: Verdict
        let meaning: Meaning

        init(_ place: Place, _ path: String, _ verdict: Verdict, _ meaning: Meaning) {
            self.place = place
            self.path = path
            self.verdict = verdict
            self.meaning = meaning
        }

        var id: String { place.rawValue + "/" + path }
        var isFound: Bool { verdict == .found }
        var isFolder: Bool { path.hasSuffix("/") }
        /// The folders above it in its place, none at its top.
        var folders: [String] { Array(path.split(separator: "/").map(String.init).dropLast()) }
        /// Its own name, without the folders above it.
        var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    }

    /// The made-up game most examples are of.
    static let exampleTitleId = "0100F00D0BAD0000"

    /// By place, in the order the page shows them: what each place finds,
    /// then what it leaves aside.
    static let examples: [Example] = [
        Example(.games, "Example Quest [0100F00D0BAD0000].ipa", .found, .namedIPA),
        Example(.games, "Example Quest.ipa", .found, .unnamedIPA),
        Example(.games, "Example Racer/romfs.img", .found, .gameFiles),
        Example(.games, "Example Quest [0100F00D0BAD0000].app.zip", .found, .macApp),
        Example(.games, "Switch/Adventure/Example Quest.ipa", .leftAside, .tooDeep),
        Example(.saves, "Example Quest [0100F00D0BAD0000]/", .found, .gameFolder),
        Example(.saves, "Example Quest [0100F00D0BAD0000]/2026-11-17T08-30-00Z.zip", .found, .copy),
        Example(.saves, "Example Quest/", .leftAside, .unnamedFolder),
        Example(.saves, "Example Quest [0100F00D0BAD0000]/My save.zip", .leftAside, .notACopy),
        Example(.dumps, "Example Quest [0100F00D0BAD0000][v0].nsp", .found, .package),
        Example(.dumps, "Example Quest [0100F00D0BAD0800][v65536].nsp", .found, .update),
        Example(.dumps, "Example Racer [0400F00D0BAD0000].nup", .found, .nup),
        Example(.dumps, "Example Golf/", .found, .dump),
        Example(.dumps, "Example Quest_build/", .leftAside, .buildFolder),
        Example(.dumps, "Example Quest [0100F00D0BAD0000].ipa", .leftAside, .built),
    ]

    /// PLACE's examples.
    static func examples(in place: Place) -> [Example] {
        examples.filter { $0.place == place }
    }
}
