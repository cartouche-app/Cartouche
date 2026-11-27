//
//  CartoucheRunningGame.swift
//  Cartouche
//
//  A game that runs behind the console instead of in Cartouche's place
//  (CartoucheGameHost, docs/decisions.md, 38): which one, whether it is on
//  screen or paused behind the console, and what its own process writes of
//  its memory (launcher/LiveProcessSupport/CartoucheGuest.m). Also the
//  player's choice of starting games that way, and the games that start in
//  Cartouche's place anyway because they need more memory than a game gets
//  behind the console.
//

import Foundation
import SwiftUI

/// The game running behind the console.
struct CartoucheRunningGame: Equatable {
    let app: LCAppModel
    /// The data folder it runs with: its process is named after it.
    let dataFolder: String
    let started: Date
    /// On screen, rather than paused behind the console.
    var isInFront: Bool
    /// Paused behind the console as it lost its last controller, which
    /// the console says (CartoucheControllerPause, docs/decisions/166.md).
    var pausedForController = false

    var name: String { app.displayName }

    static func == (lhs: CartoucheRunningGame, rhs: CartoucheRunningGame) -> Bool {
        lhs.app === rhs.app && lhs.dataFolder == rhs.dataFolder && lhs.started == rhs.started
            && lhs.isInFront == rhs.isInFront && lhs.pausedForController == rhs.pausedForController
    }
}

extension CartoucheGameActions {
    /// Whether APP is the game running behind the console.
    func isRunning(_ app: LCAppModel?) -> Bool {
        guard let app, let running else { return false }
        return running.app === app
    }
}

/// Another game the player asked for while one runs behind the console:
/// the console asks before it quits the one for the other.
struct CartoucheGameSwitch {
    let running: CartoucheRunningGame
    let next: LCAppModel
    /// The next game opens on nxnative's settings screen.
    let showingSettings: Bool
}

extension Notification.Name {
    /// Posted on the main thread, with the game's LCAppModel as its object,
    /// as Cartouche starts a game, behind the console or in its own place,
    /// before the game's process does. Its user info holds, under
    /// "dataFolder", the data folder the game runs with, under "started"
    /// when it started, and under "behind" whether it runs behind the
    /// console. A game in Cartouche's place takes Cartouche's process: an
    /// observer that keeps something of it does so before it returns.
    static let cartoucheGameStarts = Notification.Name("CartoucheGameStarts")
    /// Posted on the main thread, with the game's LCAppModel as its object,
    /// when the game running behind the console goes behind it: the player
    /// opened the console, and the game is paused.
    static let cartoucheGameDidPause = Notification.Name("CartoucheGameDidPause")
    /// Posted on the main thread, with the game's LCAppModel as its object,
    /// when the game running behind the console has ended: the player quit
    /// it, or iOS stopped it. Its user info holds, under "quit", whether the
    /// player quit it, under "dataFolder" the data folder it ran with,
    /// under "started" when it started, as cartoucheGameStarts said, and
    /// under "reading", when there is one, the last reading of its memory
    /// its own process wrote (CartoucheGameMemoryReading).
    static let cartoucheGameDidEnd = Notification.Name("CartoucheGameDidEnd")
}

/// What a game's own process last wrote of its memory, every two seconds,
/// in Cartouche/GameMemory.plist of the app group (CartoucheGuest.m lists
/// the keys). A game that iOS stops for its memory leaves its last reading.
struct CartoucheGameMemoryReading {
    /// A size the game's screen took, and the memory it used then.
    struct Size {
        let time: Date
        /// In points.
        let width: Double
        let height: Double
        let footprintBytes: UInt64
    }

    /// The game's data folder.
    let container: String
    /// The game's bundle folder, as LiveContainer names it.
    let bundle: String
    let pid: Int
    let started: Date?
    let updated: Date?
    let footprintBytes: UInt64
    /// The most it used since it started.
    let peakBytes: UInt64
    let availableBytes: UInt64
    /// The limit iOS set for the game's process.
    let limitBytes: UInt64
    /// Whether the game's process has Increased Memory Limit, as its
    /// signature gives it; nil when it could not tell.
    let hasIncreasedMemoryLimit: Bool?
    /// Each size its screen took, the first one included: the last 100.
    let sizes: [Size]
    /// The last press of a controller's button that reached the game's
    /// process, nil until one has: iOS hands the presses to the process
    /// that has the keyboard (CartoucheGuestControllers.m).
    let lastControllerPress: Date?
    /// Whether the game's picture is on its scene on a TV, as its process
    /// sees that scene; nil without one (CartoucheGuest.m).
    let pictureOnTV: Bool?
    /// nxnative's Rotation of the game, as its process has it now
    /// (DM_ROTATION: auto, landscape or portrait); nil when it has none.
    let rotation: String?

    var footprintMiB: Int { Int(footprintBytes / 1_048_576) }
    var peakMiB: Int { Int(peakBytes / 1_048_576) }
    var limitMiB: Int { Int(limitBytes / 1_048_576) }

    /// Close to the limit, now or at its peak, as the last reading of a game
    /// iOS stopped for its memory is: the game writes every two seconds.
    var wasNearLimit: Bool {
        let margin = UInt64(CartoucheGamePlace.roomMiB(under: limitMiB)) << 20
        return availableBytes < margin || peakBytes + margin > limitBytes
    }

    static var file: URL? {
        LCSharedUtils.appGroupPath()?.appendingPathComponent("Cartouche/GameMemory.plist")
    }

    /// The last reading of any game.
    static func last() -> CartoucheGameMemoryReading? {
        guard let file, let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return CartoucheGameMemoryReading(plist: plist)
    }

    /// The last reading of the game whose process is PID.
    static func last(pid: Int) -> CartoucheGameMemoryReading? {
        guard pid > 0, let reading = last(), reading.pid == pid else { return nil }
        return reading
    }

    init?(plist: [String: Any]) {
        func bytes(_ key: String) -> UInt64? { (plist[key] as? NSNumber)?.uint64Value }
        guard let container = plist["container"] as? String, let footprint = bytes("footprint"),
              let available = bytes("available") else { return nil }
        self.container = container
        bundle = plist["bundle"] as? String ?? ""
        pid = (plist["pid"] as? NSNumber)?.intValue ?? 0
        started = plist["started"] as? Date
        updated = plist["updated"] as? Date
        footprintBytes = footprint
        availableBytes = available
        peakBytes = max(bytes("peak") ?? footprint, footprint)
        limitBytes = bytes("limit") ?? footprint + available
        hasIncreasedMemoryLimit = (plist["increasedMemoryLimit"] as? NSNumber)?.boolValue
        sizes = (plist["sizes"] as? [[String: Any]] ?? []).compactMap { size in
            guard let time = size["time"] as? Date, let width = (size["width"] as? NSNumber)?.doubleValue,
                  let height = (size["height"] as? NSNumber)?.doubleValue else { return nil }
            return Size(time: time, width: width, height: height,
                        footprintBytes: (size["footprint"] as? NSNumber)?.uint64Value ?? 0)
        }
        lastControllerPress = plist["controllerPress"] as? Date
        pictureOnTV = (plist["tvPicture"] as? NSNumber)?.boolValue
        rotation = plist["rotation"] as? String
    }
}

/// Whether Play keeps the console open behind the game, and the games that
/// start in Cartouche's place anyway.
///
/// Behind the console, a game runs in a process of its own, with the
/// memory iOS gives that process: 6,144 MiB on an iPhone where Game Mode
/// gives Cartouche itself 8,192. While Cartouche has more, a game that
/// needs more than that process has starts in Cartouche's place, with all
/// of Cartouche's memory: one whose peak leaves it too little room there,
/// one that needs Increased Memory Limit when its sheet has no peak, and
/// one iOS stopped there near its limit. When that process ran without
/// Increased Memory Limit, with 3,376 MiB, every game but one whose peak
/// fits there starts in Cartouche's place, until another install of
/// Cartouche signs that process again or the player tries again. When
/// that process has as much as Cartouche or more, every game goes behind
/// the console (CartoucheGamePlace.swift). Cartouche's own limit is the
/// highest Cartouche measured on this system, or the one it measures now
/// when higher: Game Mode gives Cartouche its 8,192 MiB a moment after it
/// comes to the front, and the console reads 6,144 as it opens.
@MainActor
final class CartoucheGameKeeping: ObservableObject {
    static let shared = CartoucheGameKeeping()

    private static let keepsKey = "Cartouche.keepConsoleOpen"
    private static let inPlaceKey = "Cartouche.keepConsoleOpen.inPlace"
    private static let limitKey = "Cartouche.keepConsoleOpen.limitMiB"
    /// Whether the game's process ran without Increased Memory Limit, kept
    /// with this install of Cartouche.
    private let imlRecord: CartoucheBehindIMLRecord

    /// Whether games can run behind the console here: with iOS 18 or later,
    /// whose scene hosting shows the game's scene in Cartouche's window, and
    /// LiveContainer's LiveProcess extension, which games run in there.
    static var isAvailable: Bool {
        #if CARTOUCHE_GALLERY
        return true
        #else
        guard #available(iOS 18.0, *), let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return Bundle(url: plugins.appendingPathComponent("LiveProcess.appex"))?.bundleIdentifier != nil
        #endif
    }

    /// On unless the player turns it off on the System page.
    @Published var keepsConsoleOpen: Bool {
        didSet { UserDefaults.standard.set(keepsConsoleOpen, forKey: Self.keepsKey) }
    }
    /// The bundle IDs of the games that start in Cartouche's place.
    @Published private(set) var inPlace: Set<String>
    /// The limit iOS set for the last game behind the console.
    @Published private(set) var limitMiB: Int?
    /// Whether the last game behind the console ran without Increased
    /// Memory Limit, as its process said, with this install of Cartouche.
    @Published private(set) var behindLacksIML: Bool
    /// The highest limit Cartouche measured itself with, on this iPhone,
    /// this iOS and this signature.
    private let ownRecord: CartoucheOwnLimitRecord
    /// The highest limit Cartouche measured itself with, as ownRecord keeps
    /// it: what a game has in Cartouche's place, once Game Mode came.
    @Published private(set) var highestOwnMiB: Int?

    private init() {
        let defaults = UserDefaults.standard
        keepsConsoleOpen = defaults.object(forKey: Self.keepsKey) as? Bool ?? true
        inPlace = Set(defaults.stringArray(forKey: Self.inPlaceKey) ?? [])
        let limit = defaults.integer(forKey: Self.limitKey)
        limitMiB = limit > 0 ? limit : nil
        // After another install, which signed the game's process again, the
        // next game tries behind the console, and says whether it has the
        // capability.
        imlRecord = CartoucheBehindIMLRecord(defaults: defaults, install: Self.install)
        behindLacksIML = imlRecord.load()
        ownRecord = CartoucheOwnLimitRecord(defaults: defaults, system: Self.system)
        highestOwnMiB = ownRecord.load()
    }

    /// The system Cartouche's own limit was measured on: the iPhone's
    /// model, its iOS, and whether Cartouche's signature has Increased
    /// Memory Limit, which each change that limit.
    private static var system: String {
        [CartoucheDevice.modelIdentifier, CartoucheDevice.iOSVersion,
         CartoucheDevice.hasIncreasedMemoryLimit ? "iml" : "no-iml"].joined(separator: " ")
    }

    /// Cartouche's own limit, as a game in its place has it: OWNLIMITMIB,
    /// as Cartouche measured it, or the highest it measured on this system,
    /// when that is higher.
    func placeLimitMiB(_ ownLimitMiB: Int?) -> Int? {
        CartoucheOwnLimitRecord.placeMiB(measured: ownLimitMiB, highest: highestOwnMiB)
    }

    /// What Cartouche measured of its own memory, READING: its limit is
    /// kept when it is the highest yet. Cartouche's own limit, as a game
    /// in its place has it (placeLimitMiB).
    @discardableResult
    func measuredOwn(_ reading: CartoucheMemoryReading?) -> Int? {
        let highest = ownRecord.record(reading?.limitMiB, highest: highestOwnMiB)
        if highest != highestOwnMiB { highestOwnMiB = highest }
        return placeLimitMiB(reading?.limitMiB)
    }

    /// This install of Cartouche, which signed the games' process with the
    /// rest of Cartouche: its version, its build and its bundle folder,
    /// which iOS moves at each install.
    private static var install: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = [info["CFBundleShortVersionString"], info["CFBundleVersion"]].compactMap { $0 as? String }
        return (version + [Bundle.main.bundleURL.path]).joined(separator: " ")
    }

    /// Whether the game with BUNDLEID starts in Cartouche's place: it ran
    /// short of memory behind the console, and Cartouche's place has more
    /// than the limit last measured there, by Cartouche's own, OWNLIMITMIB.
    /// Once it has no more, the game goes behind the console again.
    func startsInPlace(bundleId: String?, ownLimitMiB: Int?) -> Bool {
        guard let bundleId, inPlace.contains(bundleId) else { return false }
        return CartoucheGamePlace.staysInPlace(behindMiB: limitMiB, ownMiB: placeLimitMiB(ownLimitMiB))
    }

    /// The most memory Play can give a game here, against Cartouche's own,
    /// OWNLIMITMIB, or the highest Cartouche measured (placeLimitMiB): in
    /// Cartouche's place, Cartouche's own; while games run behind the
    /// console, the limit iOS gave the last one there, or Cartouche's own
    /// when that is higher, for a game short of memory there.
    func gameLimitMiB(ownLimitMiB: Int?) -> Int? {
        let own = placeLimitMiB(ownLimitMiB)
        guard Self.isAvailable, keepsConsoleOpen else { return own }
        return CartoucheGamePlace.gameLimitMiB(behindMiB: limitMiB, ownMiB: own)
    }

    /// The game starts in Cartouche's place from now on.
    func startInPlace(bundleId: String) {
        inPlace.insert(bundleId)
        UserDefaults.standard.set(Array(inPlace).sorted(), forKey: Self.inPlaceKey)
    }

    /// The game tries behind the console again.
    func startBehind(bundleId: String) {
        inPlace.remove(bundleId)
        UserDefaults.standard.set(Array(inPlace).sorted(), forKey: Self.inPlaceKey)
    }

    /// What the game's process wrote of its memory: the limit iOS set
    /// there, and whether that process has Increased Memory Limit.
    func measured(_ reading: CartoucheGameMemoryReading) {
        let limit = reading.limitMiB
        if limit > 0, limit != limitMiB {
            limitMiB = limit
            UserDefaults.standard.set(limit, forKey: Self.limitKey)
        }
        let lacks = imlRecord.record(has: reading.hasIncreasedMemoryLimit, lacked: behindLacksIML)
        if lacks != behindLacksIML { behindLacksIML = lacks }
    }

    /// Whether every game starts in Cartouche's place, but one whose peak
    /// fits behind the console: the process there ran without Increased
    /// Memory Limit, and Cartouche's place has more, by its own limit,
    /// OWNLIMITMIB.
    func sendsGamesInPlace(ownLimitMiB: Int?) -> Bool {
        CartoucheGamePlace.sendsGamesInPlace(behindMiB: limitMiB, behindLacksIML: behindLacksIML,
                                             ownMiB: placeLimitMiB(ownLimitMiB))
    }

    /// The games try behind the console again, where the next one says
    /// whether its process has Increased Memory Limit now.
    func tryBehindAgain() {
        behindLacksIML = false
        imlRecord.clear()
    }

    /// Whether a game that needs NEEDSIML, or PEAKMIB at its most, starts
    /// behind the console, by the limit measured there, LIMITMIB or the last
    /// one, against Cartouche's own, OWNLIMITMIB: unless it needs more memory
    /// than it has there, and Cartouche's place has more.
    func fitsBehind(needsIML: Bool, peakMiB: Int?, limitMiB limit: Int? = nil, ownLimitMiB: Int?) -> Bool {
        CartoucheGamePlace.startsBehind(needsIML: needsIML, peakMiB: peakMiB, behindMiB: limit ?? limitMiB,
                                        behindLacksIML: behindLacksIML, ownMiB: placeLimitMiB(ownLimitMiB))
    }
}

/// Measures Cartouche's own memory into MEMORY every 2 s, for half a minute
/// after the view appears and each time Cartouche comes back to the front:
/// Game Mode raises Cartouche's limit a moment after that, from 6,144 MiB
/// to 8,192 on an iPhone with 12 GB, and a game's sheet says what a game
/// has in Cartouche's place. Cartouche keeps the highest it measured, for
/// the next time it opens (CartoucheGameKeeping.measuredOwn).
struct CartoucheOwnMemoryWatch: ViewModifier {
    @Binding var memory: CartoucheMemoryReading?
    /// Each time Cartouche comes back to the front, the watch starts again.
    @State private var watch = 0

    // Written out: the private state above would make the synthesized
    // initializer private.
    init(memory: Binding<CartoucheMemoryReading?>) {
        _memory = memory
    }

    func body(content: Content) -> some View {
        content
            .task(id: watch) { await measure() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                watch += 1
            }
    }

    @MainActor
    private func measure() async {
        for _ in 0..<15 {
            let reading = CartoucheMemoryReading.now()
            CartoucheGameKeeping.shared.measuredOwn(reading)
            if reading?.limitMiB != memory?.limitMiB { memory = reading }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
        }
    }
}

/// The questions about the game running behind the console: whether to quit
/// it, and whether to quit it for another game. Attached to the console and
/// to a game's sheet: SHOWN says which of them is in front.
@available(iOS 17.0, *)
struct CartoucheRunningGameQuestions: ViewModifier {
    let shown: Bool
    /// Before the other game starts: the sheet goes.
    var onSwitch: () -> Void = {}
    @ObservedObject private var actions = CartoucheGameActions.shared

    init(shown: Bool, onSwitch: @escaping () -> Void = {}) {
        self.shown = shown
        self.onSwitch = onSwitch
    }

    private var asking: Binding<Bool> {
        Binding(
            get: { shown && (actions.switching != nil || actions.quitQuestion != nil) },
            set: { asked in
                if !asked {
                    actions.switching = nil
                    actions.quitQuestion = nil
                }
            })
    }

    private var title: String {
        if let change = actions.switching { return CartoucheText.quitQuestion(change.running.name) }
        return actions.quitQuestion.map { CartoucheText.quitQuestion($0.name) } ?? ""
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: asking, titleVisibility: .visible) {
            if let change = actions.switching {
                Button(CartoucheText.quitAndStart(change.next.displayName), role: .destructive) {
                    onSwitch()
                    actions.confirmSwitch(change)
                }
            } else if actions.quitQuestion != nil {
                Button(CartoucheText.quitGame, role: .destructive) {
                    actions.quitQuestion = nil
                    actions.quitRunningGame()
                }
            }
            Button(CartoucheText.cancel, role: .cancel) {}
        } message: {
            if let change = actions.switching {
                Text(CartoucheText.quitAndStartMessage(change.next.displayName))
            } else {
                Text(CartoucheText.quitMessage)
            }
        }
    }
}
