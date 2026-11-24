//
//  BuildFor.swift
//  Cartouche Builder
//
//  Whom the games are built for, and so which nxnative builds them, as the
//  engine decides it (cartouche_builder/build_for.py), for the settings' Build
//  for and its words. nxnative refuses a GPU that reads no BC-compressed
//  texture, the A16's and older: nxnative-nobc, a separate fork of nxnative
//  by mianmuhammadse, stores those textures otherwise there, and takes nxnative's own path on
//  a GPU that reads them. The games are built from it when the model chosen
//  reads no BC, or, with none chosen, when one of the paired iPhones says it
//  reads none; from nxnative otherwise. A repository chosen under Advanced
//  wins over both. BuildForTests checks these against the engine's own
//  answers (Fixtures/build-for.json, written by test_app_contract.py).
//

import Foundation

public enum BuildFor {
    public static let forkURL = "https://github.com/mianmuhammadse/nxnative-nobc.git"
    public static let forkBranch = "no-bc"
    /// Its repository, which says what it does and who makes it. Its author
    /// asks that the Builder say it is a separate fork, and link to it.
    public static let forkPage = URL(string: "https://github.com/mianmuhammadse/nxnative-nobc")!

    /// A model Build for offers.
    public struct Model: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String

        public var readsBC: Bool { BuildFor.readsBC(id) }
    }

    /// The models Build for offers, newest first: iPhones, then iPads. One
    /// identifier for each name (the engine needs only whether it reads BC).
    public static var models: [Model] {
        [
            Model(id: "iPhone19,4", name: "iPhone Duo"),
            Model(id: "iPhone18,2", name: "iPhone 17 Pro Max"),
            Model(id: "iPhone18,1", name: "iPhone 17 Pro"),
            Model(id: "iPhone18,4", name: "iPhone Air"),
            Model(id: "iPhone18,3", name: "iPhone 17"),
            Model(id: "iPhone17,2", name: "iPhone 16 Pro Max"),
            Model(id: "iPhone17,1", name: "iPhone 16 Pro"),
            Model(id: "iPhone17,4", name: "iPhone 16 Plus"),
            Model(id: "iPhone17,3", name: "iPhone 16"),
            Model(id: "iPhone17,5", name: "iPhone 16e"),
            Model(id: "iPhone16,2", name: "iPhone 15 Pro Max"),
            Model(id: "iPhone16,1", name: "iPhone 15 Pro"),
            Model(id: "iPhone15,5", name: "iPhone 15 Plus"),
            Model(id: "iPhone15,4", name: "iPhone 15"),
            Model(id: "iPhone15,3", name: "iPhone 14 Pro Max"),
            Model(id: "iPhone15,2", name: "iPhone 14 Pro"),
            Model(id: "iPhone14,8", name: "iPhone 14 Plus"),
            Model(id: "iPhone14,7", name: "iPhone 14"),
            Model(id: "iPhone14,3", name: "iPhone 13 Pro Max"),
            Model(id: "iPhone14,2", name: "iPhone 13 Pro"),
            Model(id: "iPhone14,5", name: "iPhone 13"),
            Model(id: "iPhone14,4", name: "iPhone 13 mini"),
            Model(id: "iPhone14,6", name: tr("iPhone SE (3rd generation)", "iPhone SE (3e génération)", "iPhone SE (3.ª generación)", "iPhone SE (3. Generation)")),
            Model(id: "iPhone13,4", name: "iPhone 12 Pro Max"),
            Model(id: "iPhone13,3", name: "iPhone 12 Pro"),
            Model(id: "iPhone13,2", name: "iPhone 12"),
            Model(id: "iPhone13,1", name: "iPhone 12 mini"),
            Model(id: "iPhone12,5", name: "iPhone 11 Pro Max"),
            Model(id: "iPhone12,3", name: "iPhone 11 Pro"),
            Model(id: "iPhone12,1", name: "iPhone 11"),
            Model(id: "iPhone12,8", name: tr("iPhone SE (2nd generation)", "iPhone SE (2e génération)", "iPhone SE (2.ª generación)", "iPhone SE (2. Generation)")),
            Model(id: "iPad16,5", name: "iPad Pro (M4)"),
            Model(id: "iPad15,5", name: "iPad Air (M3)"),
            Model(id: "iPad14,10", name: "iPad Air (M2)"),
            Model(id: "iPad14,5", name: "iPad Pro (M2)"),
            Model(id: "iPad13,16", name: "iPad Air (M1)"),
            Model(id: "iPad13,8", name: "iPad Pro (M1)"),
            Model(id: "iPad16,1", name: "iPad mini (A17 Pro)"),
            Model(id: "iPad15,7", name: "iPad (A16)"),
            Model(id: "iPad14,1", name: tr("iPad mini (6th generation)", "iPad mini (6e génération)", "iPad mini (6.ª generación)", "iPad mini (6. Generation)")),
            Model(id: "iPad13,18", name: tr("iPad (10th generation)", "iPad (10e génération)", "iPad (10.ª generación)", "iPad (10. Generation)")),
            Model(id: "iPad13,1", name: tr("iPad Air (4th generation)", "iPad Air (4e génération)", "iPad Air (4.ª generación)", "iPad Air (4. Generation)")),
        ]
    }

    /// The name of MODEL, nil for one Build for does not offer.
    public static func name(of model: String) -> String? {
        models.first { $0.id == model }?.name
    }

    // MARK: The engine's rule

    /// The iPhones up to iPhone15,x read no BC; iPhone16,1, the iPhone 15
    /// Pro's A17 Pro, is the first that does.
    static let lastIPhoneWithoutBC = 15
    /// From iPad13,x on, the iPads with an A chip older than the A17 Pro:
    /// those with an M chip read BC, and all those before have an older A
    /// chip.
    static let iPadsWithoutBC: Set<String> = ["iPad13,1", "iPad13,2", "iPad13,18", "iPad13,19", "iPad14,1", "iPad14,2", "iPad15,7", "iPad15,8"]
    static let firstIPad = 13

    /// Whether MODEL ("iPhone15,4") is a model identifier Build for takes.
    public static func isModel(_ model: String) -> Bool { parts(model) != nil }

    /// Whether the GPU of MODEL reads BC textures. Any other device, a Mac
    /// or one this does not know, is taken to read them.
    public static func readsBC(_ model: String) -> Bool {
        guard let (kind, major) = parts(model) else { return true }
        if kind == "iPhone" { return major > lastIPhoneWithoutBC }
        return major >= firstIPad && !iPadsWithoutBC.contains(model)
    }

    private static func parts(_ model: String) -> (String, Int)? {
        for kind in ["iPhone", "iPad"] where model.hasPrefix(kind) {
            let numbers = model.dropFirst(kind.count).split(separator: ",", omittingEmptySubsequences: false)
            guard numbers.count == 2, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
                  let major = Int(numbers[0]) else { return nil }
            return (kind, major)
        }
        return nil
    }

    /// Whether the paired DEVICE reads BC, nil while it has not said its
    /// model (an older Cartouche).
    public static func readsBC(_ device: PairedDevice) -> Bool? {
        if let said = device.readsBC { return said }
        guard let model = device.model, isModel(model) else { return nil }
        return readsBC(model)
    }

    /// Which nxnative builds the games, and for whom.
    public struct Choice: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case nxnative
            case noBC = "no-bc"
            case custom
        }

        public var kind: Kind
        /// The model chosen, or the paired iPhone's that needs the variant.
        public var model: String?
        /// The paired iPhone that needs the variant, by its name.
        public var device: String?
    }

    /// Which nxnative builds the games with CONFIG and the paired DEVICES,
    /// as the engine decides it (targets.source).
    public static func choice(_ config: BuilderConfig, devices: [PairedDevice]) -> Choice {
        if custom(config) { return Choice(kind: .custom) }
        if !config.buildFor.isEmpty {
            return Choice(kind: readsBC(config.buildFor) ? .nxnative : .noBC, model: config.buildFor)
        }
        if let without = devices.first(where: { readsBC($0) == false }) {
            return Choice(kind: .noBC, model: without.model, device: without.name)
        }
        return Choice(kind: .nxnative)
    }

    /// The repository and branch the games are built from with CONFIG and
    /// the paired DEVICES, as the engine fetches them (targets.source): what
    /// the setup assistant's tools step downloads.
    public static func repository(_ config: BuilderConfig, devices: [PairedDevice]) -> (url: String, branch: String) {
        switch choice(config, devices: devices).kind {
        case .custom: return (config.engineURL, config.engineBranch)
        case .noBC: return (forkURL, forkBranch)
        case .nxnative: return (BuilderConfig.engineURL, BuilderConfig.engineBranch)
        }
    }

    /// URL as the player reads it: "github.com/seedds/nxnative".
    public static func address(_ url: String) -> String {
        var address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where address.hasPrefix(scheme) { address.removeFirst(scheme.count) }
        if address.hasPrefix("git@") { address = String(address.dropFirst(4)).replacingOccurrences(of: ":", with: "/") }
        while address.hasSuffix("/") { address.removeLast() }
        if address.hasSuffix(".git") { address.removeLast(4) }
        return address
    }

    /// Whether the player chose another repository or branch under Advanced.
    public static func custom(_ config: BuilderConfig) -> Bool {
        key(config.engineURL, config.engineBranch) != key(BuilderConfig.engineURL, BuilderConfig.engineBranch)
    }

    static func key(_ url: String, _ branch: String) -> String {
        var address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.hasSuffix(".git") { address.removeLast(4) }
        while address.hasSuffix("/") { address.removeLast() }
        return address + "#" + branch.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
