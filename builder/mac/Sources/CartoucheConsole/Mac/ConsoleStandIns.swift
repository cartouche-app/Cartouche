//
//  ConsoleStandIns.swift
//  Cartouche on the Mac
//
//  What the console's screens (Shared/) ask of the iPhone's Cartouche, as
//  a Mac answers: its game actions (CartoucheGameActions.swift, which
//  installs and starts games with LiveContainer), the game running, its
//  setup (a certificate and a pairing file), its Apple ID, the game behind
//  the console, the iPhone's model, memory limit, signature and its
//  renewals, how a game fits it, where a game keeps its saves and writes
//  its logs. The saves themselves, which the Builder keeps in step, are in
//  ConsoleSaves.swift, and its measurements, which the Builder sends, in
//  ConsoleTelemetry.swift; the first game's guide, the Mac's own steps, in
//  ConsoleGuide.swift; the reports and their journal are the iPhone's
//  (CartoucheReporting.swift), in the Builder's folder.
//  A Mac plays the games nxnative built for it, each in its own app: the
//  console has nothing to set up, no limit of memory from iOS, no signature
//  that expires, nothing behind it. A game fits it by the iPhone's rule
//  (CartoucheGameFit.swift), against what this Mac has: its chip and macOS,
//  which nxnative's apps for the Mac need, its GPU, and the memory Metal
//  says a game may use here. Each stand-in keeps the names and the calls of
//  the iPhone's, so that the screens are the same files.
//

import AppKit
import Foundation
import Metal
import SwiftUI

// MARK: The game actions

/// What the console does with a game: the app it is in does it (Play
/// starts the game's own app, Quit asks it to end), and says which game
/// runs (CartoucheMacConsole).
@MainActor
final class CartoucheGameActions: ObservableObject {
    static let shared = CartoucheGameActions()

    /// The game running, started from this Mac.
    @Published var running: CartoucheRunningGame?
    /// A game the Builder installs on this Mac from its games folder, and
    /// how far it is, over the console as the iPhone shows an install
    /// (CartoucheMacConsole.showInstall).
    @Published var work: CartoucheGameWork?
    /// What the app does when the console asks it.
    var onQuit: (LCAppModel) -> Void = { _ in }
    /// The player asked to quit the running game, from the console: a
    /// pause for its controller then ends as quit (CartoucheControllerPause).
    var quitAsked = false

    /// Whether APP is the game running.
    func isRunning(_ app: LCAppModel?) -> Bool {
        guard let app, let running else { return false }
        return running.app === app
    }

    /// The running game ends: its app is asked to quit, as its own Quit
    /// does, so that the game saves as it ends.
    func askToQuit() {
        guard let running else { return }
        quitAsked = true
        onQuit(running.app)
    }

    /// Where nxnative's apps keep each game's data on this Mac, by its title
    /// ID (dm/mac/launcher.c in nxnative).
    var dataRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/nxnative", isDirectory: true)
    /// Whether the games' settings pages keep the choices in memory rather
    /// than in the games' preferences: the gallery's, which reads nothing
    /// of the player's and keeps nothing (ConsoleSettings.swift).
    var keepsChoicesInMemory = false
    /// Where nxnative's apps for the Mac write each game's logs, which its
    /// sheet's Share the log reads.
    var logsRoot = CartoucheMacSessions.nxnativeLogs

    /// The game's saves on this Mac, in nxnative's folder of the game's,
    /// dataRoot/<title ID>, whose save and save_device hold them, as the
    /// iPhone's game's Documents do; keyed by the game's title ID, as the
    /// Builder keeps them in step (ConsoleSaves.swift). Nil for an app that
    /// is not an nxnative game, or a game that never started here, which
    /// has no folder yet.
    func saves(of app: LCAppModel) -> CartoucheSaveTarget? {
        guard let titleId = titleId(of: app) else { return nil }
        let documents = dataRoot.appendingPathComponent(titleId, isDirectory: true)
        guard FileManager.default.fileExists(atPath: documents.path) else { return nil }
        return CartoucheSaveTarget(key: CartoucheSaveBackups.key(titleId), name: app.displayName, titleId: titleId,
                                   documents: documents)
    }

    /// Where the game keeps its saves, its folder made now if it never
    /// started here, as nxnative makes it at the game's first start: for a
    /// save the player brings from their Switch before then
    /// (CartoucheSwitchSaveView).
    func savesToImport(of app: LCAppModel) -> CartoucheSaveTarget? {
        guard let titleId = titleId(of: app) else { return nil }
        try? FileManager.default.createDirectory(at: dataRoot.appendingPathComponent(titleId, isDirectory: true),
                                                 withIntermediateDirectories: true)
        return saves(of: app)
    }

    /// Where the game's app writes its logs, for Share the log on its sheet
    /// (CartoucheGameLogView): logsRoot/<title ID>.log of its last session
    /// and <title ID>.prev.log of the one before, which nxnative's launcher
    /// renames it to at the game's next start (dm/mac/launcher.c). Nil for
    /// an app that is not an nxnative game.
    func logs(of app: LCAppModel) -> CartoucheGameLogFolder? {
        guard let titleId = titleId(of: app)?.uppercased() else { return nil }
        return CartoucheGameLogFolder(game: app.displayName, titleId: titleId,
                                      build: CartoucheInstalledBuilds.installedBuild(of: app),
                                      documents: logsRoot, names: [titleId + ".log", titleId + ".prev.log"])
    }

    /// The game's app and its data folder, for its size and its play time
    /// (CartoucheGameStats), which the Builder counts there as the iPhone's
    /// game does in its own (MacPlayTime.swift in BuilderKit). Nil for an
    /// app that is not an nxnative game.
    func folders(of app: LCAppModel) -> CartoucheGameFolders? {
        guard app.appInfo.titleId != nil || CartoucheCatalog.shared.gameTitle(of: app) != nil,
              let contents = app.appInfo.bundlePath(), let bundleId = CartoucheGameStats.bundleId(of: app) else { return nil }
        let titleId = titleId(of: app)
        var data: [String: URL] = [:]
        if let titleId {
            let folder = dataRoot.appendingPathComponent(titleId, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) { data[titleId] = folder }
        }
        // The app's Contents, which hold all of it and its Info.plist.
        return CartoucheGameFolders(bundleId: bundleId, titleId: titleId,
                                    bundle: URL(fileURLWithPath: contents, isDirectory: true), data: data)
    }
}

/// The game running, in its own app.
struct CartoucheRunningGame: Equatable {
    let app: LCAppModel
    let started: Date
    /// Its app is the Mac's active app.
    var isInFront: Bool
    /// Paused as it lost its last controller, its app stopped, the console
    /// in front, which says so (CartoucheControllerPause,
    /// docs/decisions/166.md).
    var pausedForController = false

    var name: String { app.displayName }

    static func == (lhs: CartoucheRunningGame, rhs: CartoucheRunningGame) -> Bool {
        lhs.app === rhs.app && lhs.started == rhs.started && lhs.isInFront == rhs.isInFront
            && lhs.pausedForController == rhs.pausedForController
    }
}

/// Where a game runs: on the Mac, always in its own app, never behind the
/// console, and with all the Mac's memory.
@MainActor
final class CartoucheGameKeeping: ObservableObject {
    static let shared = CartoucheGameKeeping()

    static var isAvailable: Bool { false }

    @Published var keepsConsoleOpen = false
    @Published private(set) var limitMiB: Int?

    func startsInPlace(bundleId: String?, ownLimitMiB: Int?) -> Bool { false }
    /// The memory a game may use here: what Metal says this Mac's GPU can
    /// hold without slowing down, the Mac's memory being the GPU's.
    func gameLimitMiB(ownLimitMiB: Int?) -> Int? { ownLimitMiB ?? CartoucheDevice.gameMemoryMiB }
    func startBehind(bundleId: String) {}
    func sendsGamesInPlace(ownLimitMiB: Int?) -> Bool { false }
    func tryBehindAgain() {}
    func fitsBehind(needsIML: Bool, peakMiB: Int?, limitMiB limit: Int? = nil, ownLimitMiB: Int?) -> Bool { true }
}

// MARK: Setup, sign-in and the first game's guide

/// A Mac plays the games it built: no certificate, pairing file or Apple ID
/// to set up first.
@MainActor
final class CartoucheSetup: ObservableObject {
    static let shared = CartoucheSetup()

    var canPlay: Bool { true }
    var needsSetup: Bool { false }
    var showsBanner: Bool { false }
    var bannerHides: Bool { false }
    var bannerIcon: String { "checkmark.circle.fill" }
    var bannerTitle: String { "" }

    func hideBanner() {}

    func refresh() {}
    func bannerDetail(signingInAgain: Bool, registeringDevice: Bool = false) -> String { "" }
}

/// No Apple ID signs in on the Mac.
@MainActor
final class CartoucheAccount: ObservableObject {
    static let shared = CartoucheAccount()

    typealias Phase = CartoucheSignInPhase

    @Published private(set) var phase: Phase?
    @Published private(set) var isAutomatic = false
}

// MARK: This Mac

/// What this Mac gives a game, under the iPhone's names.
enum CartoucheDevice {
    /// The symbol of the device a game is on, beside its size and its
    /// build.
    static let symbol = "laptopcomputer"

    /// The model identifier, such as "Mac16,13".
    static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }()

    /// The Mac's chip, such as "Apple M4 Pro".
    static let chip: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let text = String(cString: brand).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "?" : text
    }()

    /// The memory a game may use on this Mac, in MiB: Metal's
    /// recommendedMaxWorkingSetSize, about three quarters of the Mac's
    /// memory on an Apple chip; nil when Metal does not say.
    static let gameMemoryMiB: Int? = {
        guard let bytes = MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize, bytes > 0 else { return nil }
        return Int(bytes / 1_048_576)
    }()

    /// macOS's version, where the iPhone says iOS's.
    static var iOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { text += ".\(version.patchVersion)" }
        return text
    }

    /// The macOS nxnative's apps for the Mac need, which their Info.plist
    /// says (LSMinimumSystemVersion): nxnative's README, dm/mac/min_os.mk.
    static let macMinimum = "26.6"

    /// Whether this Mac runs macOS MINIMUM or later, such as "26.6".
    static func runsAtLeast(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(
            majorVersion: parts.count > 0 ? parts[0] : 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0))
    }

    static let supportsBCTextureCompression: Bool = MTLCreateSystemDefaultDevice()?.supportsBCTextureCompression ?? false

    /// The GPU and the iOS an iPhone tells its paired Mac, which a game's
    /// pipeline archive is made for (decision 174): none for a Mac, whose
    /// GPU and macOS no IPA's archive is for.
    static let gpuArchitecture: String? = nil
    static let iOSMajorVersion: Int? = nil

    /// Increased Memory Limit is iOS's: a Mac's app has its memory without it.
    static let hasIncreasedMemoryLimit = true
}

/// The memory iOS lets an app use: a Mac sets no such limit.
struct CartoucheMemoryReading {
    let footprintBytes: UInt64
    let availableBytes: UInt64

    var limitBytes: UInt64 { footprintBytes + availableBytes }
    var limitMiB: Int { Int(limitBytes / 1_048_576) }
    var footprintMiB: Int { Int(footprintBytes / 1_048_576) }
    var availableMiB: Int { Int(availableBytes / 1_048_576) }

    static func now() -> CartoucheMemoryReading? { nil }
}

/// A signature that expires is the iPhone's: the Mac's app has none.
struct CartoucheSignature {
    let expirationDate: Date?
    let teamName: String?

    var daysLeft: Int? { nil }

    static func current() -> CartoucheSignature {
        CartoucheSignature(expirationDate: nil, teamName: nil)
    }
}

/// Cartouche renews its signature on the iPhone, by itself in its last
/// days (CartoucheRenewal.swift): the Mac's app has none to renew, so no
/// renewal is ever under way.
@MainActor
final class CartoucheRenewals: ObservableObject {
    static let shared = CartoucheRenewals()

    var isRenewing: Bool { false }
}

/// How a game fits this Mac, from its sheet and what this Mac has, by the
/// iPhone's rule (CartoucheGameFit), in words. A game nxnative built for
/// the Mac needs its macOS, not the iOS the sheet names, and no Increased
/// Memory Limit; the testers' results on this Mac's model count, as an
/// iPhone's on its own.
enum CartoucheFit: Hashable {
    case recommended
    case untested
    case notRecommended([String])
    case unsupported([String])

    var reasons: [String] {
        switch self {
        case .recommended, .untested: return []
        case .notRecommended(let reasons), .unsupported(let reasons): return reasons
        }
    }

    var title: String {
        switch self {
        case .recommended: return CartoucheText.fitRecommended
        case .untested: return CartoucheText.fitUntested
        case .notRecommended: return CartoucheText.fitNotRecommended
        case .unsupported: return CartoucheText.fitUnsupported
        }
    }

    var isPlayable: Bool {
        switch self {
        case .recommended, .untested: return true
        case .notRecommended, .unsupported: return false
        }
    }

    /// LIMITMIB is the memory a game may use here
    /// (CartoucheGameKeeping.gameLimitMiB); CONVERTSBCTEXTURES, whether the
    /// player's build of the game converts its BC textures for a GPU
    /// without them, as on the iPhone: a Mac's always reads them.
    static func of(_ sheet: CartoucheGameSheet, limitMiB: Int?, convertsBCTextures: Bool = false) -> CartoucheFit {
        let latest = sheet.results.filter { $0.device == CartoucheDevice.modelIdentifier }.max { $0.date < $1.date }
        // The macOS of nxnative's apps for the Mac, where the iPhone's sheet
        // says the iOS a game needs.
        return CartoucheFit(CartoucheGameFit.verdict(
            minimumIOS: CartoucheDevice.macMinimum, runsMinimumIOS: CartoucheDevice.runsAtLeast(CartoucheDevice.macMinimum),
            readsBCTextures: CartoucheDevice.supportsBCTextureCompression, convertsBCTextures: convertsBCTextures,
            needsIML: false, hasIML: true,
            peakMiB: sheet.peakMemoryMiB, limitMiB: limitMiB, latestHere: latest?.status))
    }

    /// How a game without a sheet fits: nil, unless this Mac's GPU is one
    /// nxnative refuses for every game, and the player's build does not
    /// convert its textures for it, CONVERTSBCTEXTURES.
    static func withoutSheet(convertsBCTextures: Bool = false) -> CartoucheFit? {
        CartoucheGameFit.verdictWithoutSheet(readsBCTextures: CartoucheDevice.supportsBCTextureCompression,
                                             convertsBCTextures: convertsBCTextures)
            .map { CartoucheFit($0) }
    }

    private init(_ verdict: CartoucheGameFit.Verdict) {
        switch verdict {
        case .recommended: self = .recommended
        case .untested: self = .untested
        case .notRecommended(let reasons): self = .notRecommended(reasons.map(Self.text))
        case .unsupported(let reasons): self = .unsupported(reasons.map(Self.text))
        }
    }

    private static func text(_ reason: CartoucheGameFit.Reason) -> String {
        switch reason {
        case .iOS(let minimum): return CartoucheText.reasonIOS(minimum)
        case .gpu: return CartoucheText.reasonGPU
        case .increasedMemoryLimit: return CartoucheText.reasonIML
        case .memory(let needed, let limit):
            return CartoucheText.reasonMemory(needed: CartoucheText.mebibytes(needed), limit: CartoucheText.mebibytes(limit))
        case .doesNotRun: return CartoucheText.reasonDoesNotRun
        }
    }
}
