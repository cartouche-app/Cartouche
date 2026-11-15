//
//  CartoucheGameSettingList.swift
//  Cartouche
//
//  A game's settings list, as nxnative writes it into the game
//  (dm/launcher.json, from its dm/games/settings.tsv; nxnative's
//  docs/frontends.md, "The settings list"): its rows, the variables the
//  game's env files set, which nxnative keeps over the player's choices,
//  and where those choices are kept, the game's preferences
//  ("launcher.<variable>"). Cartouche's settings page shows them
//  (CartoucheGameSettings.swift), and Cartouche chooses the game's
//  language with them before each start (CartoucheGameLanguage.swift): on
//  the iPhone (CartoucheGameActions.swift), and on the Mac, where Cartouche
//  Builder starts the games nxnative built for it (builder/mac, MacPlay.swift)
//  and reads this file through CartoucheCore.
//
//  Foundation only: tested on its own by launcher/Package.swift.
//

import Foundation

/// One row of nxnative's settings screen, as dm/launcher.json lists it
/// (nxnative's LauncherSettings.swift, Setting).
public struct CartoucheGameSetting: Decodable, Identifiable, Hashable {
    struct Base: Decodable, Hashable {
        let docked: [Int]
        let handheld: [Int]
    }

    public let env: String
    /// choice, range or toggle.
    public let kind: String
    let label: String
    let note: String
    public let def: String
    let section: String?
    /// "<variable>=<value>": shown only while that setting has that value.
    let needs: String?
    /// The render scale's 3D size at 1.0, docked and handheld.
    let base: Base?
    /// A choice's [value, label] pairs.
    let options: [[String]]?
    let min: Double?
    let max: Double?
    let step: Double?
    /// A toggle's two values, 1 and 0 when not given.
    let on: String?
    let off: String?

    public var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }
    /// A choice's options that have a value and a label.
    var choices: [[String]] { (options ?? []).filter { $0.count >= 2 } }
    /// Their values: for the game's language, the codes of its languages.
    public var optionValues: [String] { choices.map { $0[0] } }

    /// A range compares as numbers: a slider writes 1.00 for 1.0.
    func isDefault(_ value: String) -> Bool {
        kind == "range" ? abs((Double(value) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : value == def
    }

    /// Whether the game still offers a saved choice.
    public func accepts(_ value: String) -> Bool {
        switch kind {
        case "choice":
            return choices.contains { $0[0] == value }
        case "range":
            guard !value.contains(where: { $0 == "x" || $0 == "X" }), let number = Double(value), number.isFinite,
                  let low = min, let high = max else { return false }
            return number >= low && number <= high
        case "toggle":
            return value == onValue || value == offValue
        default:
            return true
        }
    }

    enum CodingKeys: String, CodingKey {
        case env, kind, label, note, def = "default", section, needs, base, options, min, max, step, on, off
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        env = try values.decode(String.self, forKey: .env)
        kind = try values.decode(String.self, forKey: .kind)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? env
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        def = try values.decode(String.self, forKey: .def)
        section = try values.decodeIfPresent(String.self, forKey: .section)
        needs = try values.decodeIfPresent(String.self, forKey: .needs)
        base = try? values.decodeIfPresent(Base.self, forKey: .base)
        options = try values.decodeIfPresent([[String]].self, forKey: .options)
        min = try values.decodeIfPresent(Double.self, forKey: .min)
        max = try values.decodeIfPresent(Double.self, forKey: .max)
        step = try values.decodeIfPresent(Double.self, forKey: .step)
        on = try values.decodeIfPresent(String.self, forKey: .on)
        off = try values.decodeIfPresent(String.self, forKey: .off)
    }

    /// SETTING with another default: the one Cartouche starts the game
    /// with where it does not start it as nxnative would, as the console
    /// on the Mac fills the screen with a game where nxnative opens a
    /// window.
    public init(_ setting: CartoucheGameSetting, default value: String) {
        env = setting.env
        kind = setting.kind
        label = setting.label
        note = setting.note
        def = value
        section = setting.section
        needs = setting.needs
        base = setting.base
        options = setting.options
        min = setting.min
        max = setting.max
        step = setting.step
        on = setting.on
        off = setting.off
    }

    /// The rows of a settings list such as dm/launcher.json.
    public static func rows(in data: Data) -> [CartoucheGameSetting]? {
        struct File: Decodable { let settings: [CartoucheGameSetting] }
        return (try? JSONDecoder().decode(File.self, from: data))?.settings
    }

    /// The rows of a game's dm/launcher.json; a game of several programs
    /// keeps the first program's in dm/p0.
    public static func rows(inBundle bundle: URL) -> [CartoucheGameSetting]? {
        let dm = bundle.appendingPathComponent("dm", isDirectory: true)
        for file in [dm.appendingPathComponent("launcher.json"), dm.appendingPathComponent("p0/launcher.json")] {
            if let data = try? Data(contentsOf: file), let rows = rows(in: data) {
                return rows
            }
        }
        return nil
    }

    /// The variables an env file sets (Documents/env.txt, then the bundle's
    /// dm/env.txt), which nxnative keeps over the player's choices.
    static func fixedValues(home: URL?, bundle: URL) -> [String: String] {
        let files = [home?.appendingPathComponent("Documents/env.txt"), bundle.appendingPathComponent("dm/env.txt")]
        return fixedValues(files: files.compactMap { $0 })
    }

    /// The variables the env files FILES set, the first file that sets one
    /// winning, as nxnative reads them: a Mac app's are the player's env.txt
    /// in its Application Support folder, then its bundle's dm/env.txt.
    public static func fixedValues(files: [URL]) -> [String: String] {
        var found: [String: String] = [:]
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("#"), let equal = line.firstIndex(of: "="), equal != line.startIndex else { continue }
                let key = String(line[..<equal])
                if found[key] == nil { found[key] = String(line[line.index(after: equal)...]) }
            }
        }
        return found
    }
}

/// Where a game keeps the player's choices: its preferences.
public protocol CartoucheGameChoices: AnyObject {
    /// A string only, as nxnative reads a choice: never a number turned
    /// into one.
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    /// nil removes the key.
    func set(_ value: Any?, forKey key: String)
}

extension CartoucheGameChoices {
    /// What the game's preferences hold of its language
    /// (CartoucheGameLanguage).
    public var languageRecord: CartoucheGameLanguage.Record {
        CartoucheGameLanguage.Record(
            saved: string(forKey: CartoucheGameLanguage.savedKey),
            source: string(forKey: CartoucheGameLanguage.sourceKey).flatMap { CartoucheGameLanguage.Source(rawValue: $0) },
            iPhone: string(forKey: CartoucheGameLanguage.iPhoneKey))
    }

    /// Keeps RECORD, writing only what changed: on the iPhone, each write
    /// goes to cfprefsd at once.
    public func keepLanguage(_ record: CartoucheGameLanguage.Record) {
        let old = languageRecord
        if record.saved != old.saved { set(record.saved, forKey: CartoucheGameLanguage.savedKey) }
        if record.source != old.source { set(record.source?.rawValue, forKey: CartoucheGameLanguage.sourceKey) }
        if record.iPhone != old.iPhone { set(record.iPhone, forKey: CartoucheGameLanguage.iPhoneKey) }
    }
}
