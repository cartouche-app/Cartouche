//
//  GameSwitches.swift
//  BuilderKit
//
//  The switches of a game's sheet (built for the iPhone, for this Mac,
//  followed), shown as soon as the player flips them. The engine answers a
//  switch in a moment, but the library it is shown in is read again after
//  it, which takes tens of seconds with a games folder on a NAS: a switch
//  that waited for that read stayed as it was for half a minute. A read
//  that began before the engine answered says the game as it was, so each
//  switch is kept over the reads until one that began after its answer.
//  Platform-independent: Foundation only.
//

import Foundation

public struct GameSwitches: Equatable {
    /// What a game was switched to, over what the library read says.
    struct Switch: Equatable {
        var platforms: GamePlatforms?
        var followed: Bool?
        /// The number of its last flip: an answer to an earlier one comes
        /// late, and does not undo it.
        var flip: Int
        /// The engine's answers counted when it answered the last flip;
        /// nil while it has not.
        var answered: Int?
        /// What the engine said last of the game, for a flip it refuses:
        /// the game shows that again.
        var said: GamePlatforms?
        var saidFollowed: Bool?
        var saidAt: Int?
    }

    private var switches: [String: Switch] = [:]
    private var flips = 0
    private var answers = 0

    public init() {}

    /// Whether no switch waits for a library read.
    public var isEmpty: Bool { switches.isEmpty }

    /// Taken when a read of the library begins, and given back when it
    /// ends (read(since:)): the switches answered before it began are in it.
    public var mark: Int { answers }

    /// TITLE_ID's switches flipped to PLATFORMS or FOLLOWED (nil: as they
    /// were), shown at once: the number of the flip, for the engine's answer.
    @discardableResult
    public mutating func flip(_ titleID: String, platforms: GamePlatforms? = nil, followed: Bool? = nil) -> Int {
        flips += 1
        let key = titleID.uppercased()
        var made = switches[key] ?? Switch(flip: flips)
        if let platforms { made.platforms = platforms }
        if let followed { made.followed = followed }
        made.flip = flips
        made.answered = nil
        switches[key] = made
        return flips
    }

    /// The engine answered TITLE_ID's flip FLIP: what the game is built for
    /// and whether it is followed now, as it says it (nil: as flipped).
    public mutating func answered(_ titleID: String, flip: Int, platforms: GamePlatforms? = nil, followed: Bool? = nil) {
        let key = titleID.uppercased()
        guard var made = switches[key] else { return }
        answers += 1
        if let platforms { made.said = platforms }
        if let followed { made.saidFollowed = followed }
        made.saidAt = answers
        // A later flip is on its way: it shows, and its own answer comes.
        if made.flip == flip {
            if let platforms { made.platforms = platforms }
            if let followed { made.followed = followed }
            made.answered = answers
        }
        switches[key] = made
    }

    /// The engine refused TITLE_ID's flip FLIP: the game shows again what
    /// the engine said last of it, or what the library says.
    public mutating func refused(_ titleID: String, flip: Int) {
        let key = titleID.uppercased()
        guard var made = switches[key], made.flip == flip else { return }
        guard made.said != nil || made.saidFollowed != nil, let saidAt = made.saidAt else {
            switches.removeValue(forKey: key)
            return
        }
        made.platforms = made.said
        made.followed = made.saidFollowed
        made.answered = saidAt
        switches[key] = made
    }

    /// LIBRARY, read from MARK on (the mark taken as its read began), with
    /// the switches it does not say yet; those the engine answered before
    /// the read began are in it, and are forgotten.
    public mutating func read(_ library: Library, since mark: Int) -> Library {
        switches = switches.filter { _, made in
            guard let answered = made.answered else { return true }
            return answered > mark
        }
        return applied(to: library)
    }

    /// LIBRARY with every switch shown.
    public func applied(to library: Library) -> Library {
        guard !switches.isEmpty else { return library }
        var shown = library
        for index in shown.games.indices {
            guard let made = switches[shown.games[index].titleID.uppercased()] else { continue }
            if let platforms = made.platforms { shown.games[index].platforms = platforms }
            if let followed = made.followed { shown.games[index].followed = followed }
        }
        return shown
    }
}
