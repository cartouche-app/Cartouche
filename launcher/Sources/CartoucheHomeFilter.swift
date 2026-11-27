//
//  CartoucheHomeFilter.swift
//  Cartouche
//
//  Which of the player's games the home's shelf shows (CartoucheHomeView),
//  on the iPhone and on the Mac's console: all of them, those installed,
//  or those not installed, whose IPA waits on the player's Mac, in a games
//  folder or in Cartouche Cloud for Install. A player asked for it on
//  Discord: their Mac keeps more games than the iPhone holds, and the shelf
//  mixed the games they play with those they could install.
//
//  The player chooses it in the menu beside the shelf's title, or with a
//  controller's shoulder buttons, and Cartouche keeps it. The home offers
//  it only while the player has games of both kinds: otherwise the shelf
//  shows them all, whatever was chosen, as there is nothing to sort.
//
//  The shelf takes no game away from under the player: a game installed,
//  or uninstalled, while the shelf shows it stays there until the player
//  chooses a filter again or the home opens again, as the one just
//  installed from Not installed, to play it. The game paused behind the
//  console always shows, with Resume. The focus stays on its game as the
//  shelf changes around it.
//

import Foundation

/// The home's filter, the player's choice: a `home.filtered` event each
/// time they choose one, on the iPhone and on the Mac's console.
enum CartoucheHomeFilter: String, CaseIterable, Sendable {
    /// Every game of the player's.
    case all
    /// The games installed: on this iPhone, or on this Mac.
    case installed
    /// The games whose IPA is on the player's Mac, in a games folder or in
    /// Cartouche Cloud, not installed here: Install brings them.
    case notInstalled

    /// Where Cartouche keeps the player's choice.
    static let defaultsKey = "Cartouche.homeFilter"

    /// The filter the player chose last, all when none.
    static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .all
    }

    /// Keeps it as the player's choice; all, the home as it always was,
    /// keeps nothing.
    func save(in defaults: UserDefaults = .standard) {
        if self == .all {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    /// Whether it takes a game installed, or not (ISINSTALLED).
    func includes(isInstalled: Bool) -> Bool {
        switch self {
        case .all: return true
        case .installed: return isInstalled
        case .notInstalled: return !isInstalled
        }
    }

    /// The next filter, as the controller's right shoulder button goes
    /// (FORWARD), or the one before, as its left one does: from the last
    /// round to the first.
    func moved(forward: Bool) -> Self {
        let filters = Self.allCases
        let index = filters.firstIndex(of: self) ?? 0
        return filters[(index + (forward ? 1 : -1) + filters.count) % filters.count]
    }

    static let event = "home.filtered"

    /// The fields of its event: the filter chosen, and whether by the
    /// controller's shoulder buttons rather than the menu.
    func fields(byController: Bool) -> [String: CartoucheTelemetryValue] {
        ["filter": .text(rawValue), "controller": .flag(byController)]
    }
}

/// One of the player's games, as the home's filter reads it.
struct CartoucheHomeShelfGame: Hashable, Sendable {
    /// What tells the game apart, the same installed or not: its title ID,
    /// else its bundle ID.
    let key: String
    let isInstalled: Bool
    /// Paused behind the console: on the shelf whatever the filter.
    var isRunning = false
}

enum CartoucheHomeShelf {
    /// Whether the home offers the filter: the player has games installed
    /// and games not installed.
    static func offersFilter(_ games: [CartoucheHomeShelfGame]) -> Bool {
        games.contains { $0.isInstalled } && games.contains { !$0.isInstalled }
    }

    /// The games the shelf shows, by their places in GAMES, in its order:
    /// those FILTER takes, those it showed since the player chose the
    /// filter or the home opened (KEPT, by key), and the game paused behind
    /// the console; every game while the home does not offer the filter.
    static func shown(_ games: [CartoucheHomeShelfGame], filter: CartoucheHomeFilter, kept: Set<String>) -> [Int] {
        guard offersFilter(games) else { return Array(games.indices) }
        return games.indices.filter { index in
            let game = games[index]
            return filter.includes(isInstalled: game.isInstalled) || game.isRunning || kept.contains(game.key)
        }
    }

    /// Where the focus goes from COLUMN as the shelf's games change from
    /// BEFORE to AFTER, by key, the covers that import a game and open
    /// every game after them: on the same game where it is still there;
    /// where its game went away, on the game that took its place, else the
    /// last; on the same cover after the games; on the first game when the
    /// shelf had none, as the player's first game comes.
    static func column(_ column: Int, from before: [String], to after: [String]) -> Int {
        if before.isEmpty { return 0 }
        guard column < before.count else {
            return max(column - before.count + after.count, 0)
        }
        if let index = after.firstIndex(of: before[column]) { return index }
        return max(min(column, after.count - 1), 0)
    }
}
