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

    /// Where the player tapped it.
    enum Place: String, CaseIterable, Sendable {
        case home, sheet, guide
    }

    static let event = "offer.tapped"

    /// The fields of its event, tapped at PLACE.
    func fields(at place: Place) -> [String: CartoucheTelemetryValue] {
        ["offer": .text(rawValue), "place": .text(place.rawValue)]
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
