//
//  ConsoleSettings.swift
//  Cartouche on the Mac
//
//  A game's settings in the console, on the iPhone's own page
//  (CartoucheGameSettings.swift): the rows of the game's app, its
//  Contents/Resources/dm/launcher.json, as nxnative's settings window draws
//  them, and the player's choices in the app's preferences domain, where
//  nxnative's launcher reads them at every start, from Cartouche, the
//  Finder or the Dock (nxnative's docs/frontends.md, "Saved choices"), so
//  that its window is no longer needed. A setting the player's env.txt (in
//  nxnative's folder of the game) or the app's own sets shows, fixed.
//  Display mode is Fullscreen unless the player chose a window: Cartouche
//  starts its games filling the screen (MacPlay.swift in BuilderKit), where
//  nxnative's default is a window. The game's language follows the Mac's
//  until the player chooses one, which the Builder chooses again before
//  each start (MacGameLanguage).
//
//  Also the Mac's own words, those of what the iPhone does not have
//  (builder/mac/console/strings.json, "strings").
//

import Foundation

/// A game's preferences on this Mac: its app's domain, through cfprefsd,
/// which nxnative's launcher reads as the game starts and its settings
/// window writes. Neither side reads a stale copy.
final class CartoucheMacGamePreferences: CartoucheGameChoices {
    let domain: String

    init(domain: String) {
        self.domain = domain
        // What the game's window or its in-game menu changed since.
        CFPreferencesAppSynchronize(domain as CFString)
    }

    func string(forKey key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }

    func data(forKey key: String) -> Data? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Data
    }

    /// A string or data, as nxnative keeps them; nil removes the key.
    func set(_ value: Any?, forKey key: String) {
        let object: CFPropertyList? = (value as? String).map { $0 as NSString } ?? (value as? Data).map { $0 as NSData }
        CFPreferencesSetAppValue(key as CFString, object, domain as CFString)
        // The next start, from here or from the Dock, reads it.
        CFPreferencesAppSynchronize(domain as CFString)
    }
}

/// Choices kept in memory, by domain: the gallery's, which reads nothing of
/// the player's and keeps nothing.
final class CartoucheMemoryGamePreferences: CartoucheGameChoices {
    private static var domains: [String: [String: Any]] = [:]
    let domain: String

    init(domain: String) {
        self.domain = domain
    }

    func string(forKey key: String) -> String? { Self.domains[domain]?[key] as? String }
    func data(forKey key: String) -> Data? { Self.domains[domain]?[key] as? Data }

    func set(_ value: Any?, forKey key: String) {
        Self.domains[domain, default: [:]][key] = value
    }
}

extension CartoucheGameSetting {
    /// nxnative's variable for a Mac app's Display mode: 0, a window, its
    /// default; 1, fullscreen.
    static let displayMode = "DM_FULLSCREEN"

    /// SETTING as Cartouche starts the game on this Mac: Display mode is
    /// Fullscreen unless the player chose a window, so that a choice of a
    /// window is kept, a choice equal to the default not being.
    static func onThisMac(_ setting: CartoucheGameSetting) -> CartoucheGameSetting {
        guard setting.env == displayMode, setting.kind == "choice", setting.accepts("1") else { return setting }
        return CartoucheGameSetting(setting, default: "1")
    }
}

extension CartoucheGameActions {
    /// The game's settings page: the rows of its app's launcher.json, the
    /// variables its env files set, and the choices in its preferences.
    func settings(for app: LCAppModel, tileKey: String) -> CartoucheGameSettingsModel {
        let resources = app.appInfo.url.appendingPathComponent("Contents/Resources", isDirectory: true)
        // The player's env.txt, in nxnative's folder of the game, then the
        // app's own: the first that sets a variable wins.
        var files: [URL] = []
        if let titleId = titleId(of: app) {
            files.append(dataRoot.appendingPathComponent(titleId, isDirectory: true).appendingPathComponent("env.txt"))
        }
        files.append(resources.appendingPathComponent("dm/env.txt"))
        let domain = app.appInfo.bundleIdentifier()
        let choices: CartoucheGameChoices? = domain.map { domain -> CartoucheGameChoices in
            keepsChoicesInMemory ? CartoucheMemoryGamePreferences(domain: domain) : CartoucheMacGamePreferences(domain: domain)
        }
        return CartoucheGameSettingsModel(
            name: app.displayName,
            tileKey: tileKey,
            settings: (CartoucheGameSetting.rows(inBundle: resources) ?? []).map(CartoucheGameSetting.onThisMac),
            fixed: CartoucheGameSetting.fixedValues(files: files),
            choices: choices)
    }

    /// The game's title ID: its app's DMTitleID, else its bundle ID's.
    func titleId(of app: LCAppModel) -> String? {
        if let own = app.appInfo.titleId { return own }
        guard let found = CartoucheCatalog.shared.gameTitle(of: app), !found.isEmpty else { return nil }
        return found.uppercased()
    }
}

// MARK: The Mac's own words

extension CartoucheText {
    /// What a game built for this Mac needs, an Apple chip and macOS
    /// VERSION, where the iPhone's sheet says the iOS a game needs.
    static func macRequirement(_ version: String) -> String {
        f("mac.requirement", "Apple chip, macOS %@ or later", version)
    }

    /// This Mac's chip and macOS.
    static func macCurrent(_ chip: String, _ version: String) -> String {
        f("mac.current", "This Mac: %1$@, macOS %2$@", chip, version)
    }

    /// The bar over a game's settings page in the console's pane: back to
    /// the game's sheet.
    static var backToSheet: String { s("mac.settings.back", "Back to the game") }
}
