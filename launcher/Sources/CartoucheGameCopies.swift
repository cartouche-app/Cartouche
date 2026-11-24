//
//  CartoucheGameCopies.swift
//  Cartouche
//
//  The player's games folders, several at once (CartoucheStorageSettings),
//  and the copies of a game they hold (CartoucheStoredGames): a game in
//  more than one folder shows once in the library, and Cartouche offers the
//  copy it can reach. A copy on a server that answers comes before one on
//  a server that does not, as a NAS away from home; between two that
//  answer, or two that do not, the newer build; of the same build, the
//  copy of the folder listed first; of copies whose builds Cartouche could
//  not read, the one written there last, then the first folder's.
//
//  The first games folder is the one Cartouche copies a game to before it
//  is uninstalled, and the one the paired Mac sends its builds to; the
//  others it reads too. Stop using the first, and the next takes its
//  place.
//
//  Platform-independent: tested on its own by launcher/Package.swift.
//

import Foundation

/// What tells one of a game's copies from another, to choose among them.
struct CartoucheCopyRank: Equatable {
    /// Whether its folder's server does not answer from here.
    var offline = false
    /// Its folder's place in the list of games folders, 0 for the first.
    var folder = 0
    /// The build it is, from its Info.plist, when Cartouche read it.
    var build: CartoucheGameBuild?
    /// When it was written in its folder.
    var modified: Date?
}

enum CartoucheGameCopies {
    /// Whether the copy of rank A is the one to offer rather than the copy
    /// of rank B: on a server that answers, then the newer build, the same
    /// build in the folder listed first; without both builds, the one
    /// written last, then the one of the folder listed first.
    static func prefers(_ a: CartoucheCopyRank, over b: CartoucheCopyRank) -> Bool {
        if a.offline != b.offline { return !a.offline }
        if let build = a.build, let other = b.build {
            if build.isNewerCopy(than: other) { return true }
            if other.isNewerCopy(than: build) { return false }
            // The same build, whenever each was copied there.
            return a.folder < b.folder
        }
        let written = a.modified ?? .distantPast
        let otherWritten = b.modified ?? .distantPast
        if written != otherWritten { return written > otherWritten }
        return a.folder < b.folder
    }

    /// COPIES, the one to offer first, then the others in the order to try
    /// them in.
    static func ordered<Copy>(_ copies: [Copy], by rank: (Copy) -> CartoucheCopyRank) -> [Copy] {
        copies.enumerated()
            .sorted { first, second in
                let a = rank(first.element)
                let b = rank(second.element)
                if prefers(a, over: b) { return true }
                if prefers(b, over: a) { return false }
                return first.offset < second.offset
            }
            .map(\.element)
    }
}

/// The player's games folders, in their order: the first, which Cartouche
/// copies a game to and the paired Mac sends its builds to, then the
/// others, which Cartouche reads too. Never the same folder twice.
struct CartoucheGamesFolderList<Place: Hashable> {
    private(set) var first: Place?
    private(set) var others: [Place]

    init(first: Place?, others: [Place] = []) {
        self.first = first
        self.others = []
        for place in others { add(place) }
    }

    /// The folders, the first one first.
    var all: [Place] { (first.map { [$0] } ?? []) + others }

    var isEmpty: Bool { first == nil }

    /// Adds PLACE after the others, or as the first when there is none:
    /// whether it was not there already.
    @discardableResult
    mutating func add(_ place: Place) -> Bool {
        guard !all.contains(place) else { return false }
        if first == nil {
            first = place
        } else {
            others.append(place)
        }
        return true
    }

    /// Makes PLACE the first folder, in the place of the one there, as the
    /// player changes it: one of the others leaves its place among them.
    mutating func choose(_ place: Place) {
        others.removeAll { $0 == place }
        first = place
    }

    /// Stops using PLACE: the next one takes the first one's place. Whether
    /// the first one changed.
    @discardableResult
    mutating func remove(_ place: Place) -> Bool {
        if place == first {
            first = others.isEmpty ? nil : others.removeFirst()
            return true
        }
        others.removeAll { $0 == place }
        return false
    }

    /// Each folder as MOVE gives it, on another server, or none for one
    /// whose server is gone, in the same order, without the same folder
    /// twice: the next one takes the place of a first one gone. Whether the
    /// first one changed.
    @discardableResult
    mutating func move(_ move: (Place) -> Place?) -> Bool {
        let before = first
        let moved = all.compactMap(move)
        self = CartoucheGamesFolderList(first: moved.first, others: Array(moved.dropFirst()))
        return first != before
    }
}
