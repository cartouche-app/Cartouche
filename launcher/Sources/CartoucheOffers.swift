//
//  CartoucheOffers.swift
//  Cartouche
//
//  What the console offers a new player on the way to a first game, and
//  what the player made of it, as the game measurements tell it
//  (telemetry/README.md): How to get a game beside Import my copy while
//  the player has no game (#315), the home's banner on Renew every night
//  once the first game is installed, and the question to warn before
//  Cartouche expires (#317, decision 159), Cartouche Cloud and the IPAs
//  the player has already in the guide's Mac step (#307). 0.16.0 brought
//  them with no measure, and its first tour could not tell whether anyone
//  used them. Names a programmer gave only: never a game, a file or what
//  the player wrote.
//
//  Once the player's first game ended, the home offers a saves folder, a
//  banner of its own, while the games' saves are on this device alone
//  (decision 178): 57 of the 135 copies of Cartouche that had a game on
//  November 26 had no saves folder, and an uninstall, a reset or a lost
//  iPhone took their progress with it. When it shows, when the player
//  takes it up or takes it off, and the kind of storage they then chose
//  are measured, never a folder's name or an address.
//

import Foundation

/// A button of the way to a first game the player tapped: an
/// `offer.tapped` event, on the iPhone and on the Mac's console, whose home
/// and game sheet are the iPhone's.
enum CartoucheOffer: String, CaseIterable, Sendable {
    /// How to get a game, beside Import my copy while the player has no
    /// game: it opens the guide.
    case howToGetGame
    /// The home's banner on Renew every night: the setup, at its last step.
    case nightlyBanner
    /// The banner's ×, which takes it off the home for good.
    case nightlyHidden
    /// The guide's Mac step: No Mac: Cartouche Cloud, its page.
    case buildCloud
    /// The guide's Mac step: I have my own IPAs already, the Files picker.
    case buildHaveIPA
    /// The guide's Mac step: No thanks.
    case buildSkip
    /// The home's banner on a saves folder, once the first game ended with
    /// the saves on this device alone (decision 178): the Storage page.
    case savesBanner
    /// Its ×, which takes it off the home for good.
    case savesHidden

    /// Where the player tapped it.
    enum Place: String, CaseIterable, Sendable {
        case home, sheet, guide
    }

    static let event = "offer.tapped"
    /// An `offer.shown` event: the offer came on screen, once for each copy
    /// of Cartouche, as the home's banner on a saves folder tells it.
    static let shownEvent = "offer.shown"
    /// An `offer.taken` event: what the player chose once the offer showed,
    /// as the kind of storage of the saves folder chosen after the home's
    /// banner on one.
    static let takenEvent = "offer.taken"

    /// The fields of its event, tapped at PLACE, or shown there.
    func fields(at place: Place) -> [String: CartoucheTelemetryValue] {
        ["offer": .text(rawValue), "place": .text(place.rawValue)]
    }

    /// The fields of its `offer.taken` event: the player chose a folder on
    /// a storage of KIND (CartoucheStorageKind: smb, folder, s3, ftp, sftp,
    /// mac, drive), never which.
    func takenFields(kind: String) -> [String: CartoucheTelemetryValue] {
        ["offer": .text(rawValue), "kind": .text(kind)]
    }
}

/// When the home offers a saves folder (decision 178): once the player's
/// first game is over, back on the console, while the games' saves are on
/// this device alone and the player never chose where they go, until the
/// player takes the offer off, for good. On the iPhone, with no saves
/// folder, none ever chosen nor stopped (CartoucheStorageSettings.chosen);
/// on the Mac, with the saves of its games in the folder the Builder took
/// by itself, in its own folder on this Mac's disk (Mac/ConsoleSaves.swift).
/// Its banner leads to the Storage page, where the player chooses one as
/// before: iCloud Drive in Files, their Mac, their NAS or another storage.
enum CartoucheSavesOfferRule {
    /// How long the player's games must have been played, every game's
    /// time together, for their first game to be over: a minute, so that a
    /// game that stopped as it started is not one.
    static let playedSeconds: Double = 60

    /// Whether the home offers it: PLAYED seconds of play on this device,
    /// no game PLAYING (behind the console, or its app on the Mac), the
    /// saves without a folder of their own (NEEDSFOLDER), and the offer
    /// not taken off (HIDDEN).
    static func shows(played: Double, playing: Bool, needsFolder: Bool, hidden: Bool) -> Bool {
        played >= playedSeconds && !playing && needsFolder && !hidden
    }

    /// On the iPhone: the saves have no folder (HASFOLDER), and the player
    /// never chose one, nor stopped using one (CHOSEONCE), which they did
    /// knowing what it does.
    static func needsFolder(hasFolder: Bool, choseOnce: Bool) -> Bool {
        !hasFolder && !choseOnce
    }
}

/// Cartouche asked for the permission to warn before its signature
/// expires: an `alerts.asked` event, with what the player answered.
enum CartoucheAlertsAsk: String, CaseIterable, Sendable {
    /// By itself, right after the first game was installed (decision 159).
    case firstGame
    /// The player's Turn on, on the System page.
    case system

    static let event = "alerts.asked"

    /// The fields of its event: whether the player allowed them.
    func fields(granted: Bool) -> [String: CartoucheTelemetryValue] {
        ["place": .text(rawValue), "granted": .flag(granted)]
    }
}
