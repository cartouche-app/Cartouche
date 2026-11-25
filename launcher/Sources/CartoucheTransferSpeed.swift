//
//  CartoucheTransferSpeed.swift
//  Cartouche
//
//  How fast a game comes as it installs from the player's storage, and how
//  it comes: the install's screen says so, from the Mac the way the iPhone
//  reaches it, the cable, Tailscale or the local network, with the band of
//  the Mac's Wi-Fi as Cartouche on the Mac tells it (CartoucheMacNetwork),
//  and what to do when it is slow: plug the iPhone into the Mac, or put
//  them on a 5 GHz Wi-Fi. A game of 20 GB takes over an hour on a 2.4 GHz
//  Wi-Fi, a quarter of an hour on 5 GHz or through the cable (decision
//  151). The Builder's iPhone page says the same of what it sends. A game
//  of a NAS the Mac passes on through the cable, read on its Ethernet,
//  says so too (relayed, decision 162).
//
//  The speed is measured on the bytes read, over the last seconds
//  (CartoucheTransferMeter): what the network gives, whatever the archive.
//
//  Platform-independent: tested on its own by launcher/Package.swift.
//

import Foundation

/// How a connection reaches the Mac, as the Builder sees it on its
/// side, which its info tells the iPhone (CartoucheBridgeResponse.network):
/// the Mac's Wi-Fi, with its band; its Ethernet; the cable; or another way,
/// Tailscale's or a VPN's. Text, not a closed list, so that a newer Mac's
/// other words leave an older iPhone's answer readable.
public struct CartoucheMacNetwork: Codable, Equatable, Hashable, Sendable {
    /// "wifi", "ethernet", "cable" or "other".
    public var medium: String
    /// The band of the Mac's Wi-Fi, in GHz: "2.4", "5" or "6"; nil when the
    /// Mac does not know it, or the connection is not on its Wi-Fi.
    public var band: String?

    public static let wifi = "wifi"
    public static let ethernet = "ethernet"
    public static let cable = "cable"
    public static let other = "other"

    public init(medium: String, band: String? = nil) {
        self.medium = medium
        self.band = medium == Self.wifi ? band : nil
    }

    /// On the Mac's Wi-Fi in its 2.4 GHz band: the slow one.
    public var isSlowBand: Bool { medium == Self.wifi && band == "2.4" }

    /// The band the Mac's Wi-Fi channel is in, by CoreWLAN's numbers
    /// (CWChannelBand: 1, 2.4 GHz; 2, 5 GHz; 3, 6 GHz); nil for another.
    public static func band(ofChannelBand raw: Int) -> String? {
        switch raw {
        case 1: return "2.4"
        case 2: return "5"
        case 3: return "6"
        default: return nil
        }
    }
}

/// The way a game comes as it installs: from the Mac through the cable,
/// through Tailscale, or on the local network, with what the Mac said of
/// its side (nil from a Cartouche for Mac older than this); or from a NAS,
/// which the Mac reads on its Ethernet and passes on through the cable.
public enum CartoucheTransferWay: Equatable, Sendable {
    case cable
    case tailnet
    case network(mac: CartoucheMacNetwork?)
    case relayed

    /// The way to a Mac CARTOUCHE reached through the cable, at an address
    /// of the tailnet or on the network ("cable", "tailnet", "network", as
    /// CartoucheMacLink says), the Mac having told NETWORK; nil for a link
    /// Cartouche does not know.
    public static func toMac(link: String?, network: CartoucheMacNetwork?) -> CartoucheTransferWay? {
        switch link {
        case "cable": return .cable
        case "tailnet": return .tailnet
        case "network": return .network(mac: network)
        default: return nil
        }
    }
}

/// What the install's screen tells the player to do about the speed.
public enum CartoucheTransferAdvice: Equatable, Sendable {
    /// The Mac is on its 2.4 GHz Wi-Fi: the cable, or the 5 GHz.
    case macOnSlowBand
    /// Slow on the network to the Mac: the cable, or a 5 GHz Wi-Fi.
    case slowToMac
    /// Slow through Tailscale, which goes through the internet: at home,
    /// the same Wi-Fi or the cable.
    case slowTailnet
    /// Slow from a server of the local network, a NAS: a 5 GHz Wi-Fi.
    case slowNetwork

    /// The advice for a game coming WAY, from a server of the local network
    /// when LOCAL, SLOW as CartoucheTransferMeter says: none through the
    /// cable, the fastest, the Mac's own or a NAS's it passes on; the Mac on
    /// its 2.4 GHz band at once, before any speed is measured; else only
    /// once it is slow. Nil for nothing to say.
    public static func of(way: CartoucheTransferWay?, local: Bool, slow: Bool) -> CartoucheTransferAdvice? {
        switch way {
        case .cable, .relayed:
            return nil
        case .tailnet:
            return slow ? .slowTailnet : nil
        case .network(let mac):
            if mac?.isSlowBand == true { return .macOnSlowBand }
            return slow ? .slowToMac : nil
        case nil:
            return slow && local ? .slowNetwork : nil
        }
    }
}

/// The bytes a transfer read, and when: its speed over the last seconds.
/// Fed from the task that reads, read from the one that shows it. Each
/// run of reads, the first one or one after a pause, starts at the end of
/// its first read, whose bytes came before: they count in neither.
public final class CartoucheTransferMeter: @unchecked Sendable {
    /// The seconds the speed is measured over.
    public static let window: TimeInterval = 8
    /// The seconds of reading before a speed is said.
    public static let settle: TimeInterval = 3
    /// Below this, in bytes a second, a transfer is slow: a game of 20 GB
    /// takes over 40 minutes. A 2.4 GHz Wi-Fi gives 2 to 6 MB/s, a 5 GHz
    /// one 20 to 60, the cable 30 or more.
    public static let slowBelow: Double = 8_000_000
    /// Above this, a transfer said slow is no longer: a speed about the
    /// limit does not take the advice off and on.
    public static let fastAbove: Double = 12_000_000

    private let lock = NSLock()
    /// Each read of the run in the window: when it ended, and its bytes.
    private var reads: [(at: Date, bytes: Int)] = []
    /// When the run of reads under way started; nil before the first read,
    /// and while paused.
    private var since: Date?
    private var paused = true
    /// The bytes and seconds of the runs over, for the average.
    private var ranBytes: UInt64 = 0
    private var ranSeconds: TimeInterval = 0
    /// Those of the run under way, up to its last read.
    private var runBytes: UInt64 = 0
    private var runSeconds: TimeInterval = 0

    public init() {}

    /// A read of BYTES ended NOW.
    public func add(_ bytes: Int, at now: Date = Date()) {
        guard bytes > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let since, !paused else {
            // A run starts: its first read's bytes came before now.
            self.since = now
            paused = false
            reads.removeAll()
            runBytes = 0
            runSeconds = 0
            return
        }
        runBytes += UInt64(bytes)
        runSeconds = max(0, now.timeIntervalSince(since))
        reads.append((now, bytes))
        reads.removeAll { now.timeIntervalSince($0.at) > Self.window }
    }

    /// The reads stop for a while (the connection made again, the image of
    /// the game files opened): the time until they start again counts
    /// neither in the speed nor in the average.
    public func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard !paused else { return }
        paused = true
        ranBytes += runBytes
        ranSeconds += runSeconds
        runBytes = 0
        runSeconds = 0
        reads.removeAll()
    }

    /// The bytes a second over the last seconds, NOW; nil before the run
    /// under way has read for a few seconds, and while paused.
    public func speed(at now: Date = Date()) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard !paused, let since else { return nil }
        let ran = now.timeIntervalSince(since)
        guard ran >= Self.settle else { return nil }
        let start = now.addingTimeInterval(-Self.window)
        let bytes = reads.filter { $0.at > start }.reduce(0) { $0 + $1.bytes }
        return Double(bytes) / min(Self.window, ran)
    }

    /// The bytes a second over the whole transfer, its pauses left out:
    /// game.installed's speed. Nil before a few seconds of it.
    public func average() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let seconds = ranSeconds + runSeconds
        guard seconds >= Self.settle else { return nil }
        return Double(ranBytes + runBytes) / seconds
    }

    /// Whether a transfer at SPEED is slow, it being so before (WAS_SLOW):
    /// below slowBelow, and once said slow, until above fastAbove. Nil, no
    /// speed yet, keeps what was said.
    public static func isSlow(_ speed: Double?, wasSlow: Bool) -> Bool {
        guard let speed else { return wasSlow }
        return wasSlow ? speed <= fastAbove : speed < slowBelow
    }

    /// SPEED in megabytes a second, as the screen writes it: one decimal
    /// below 10, none above; 3.1, 31.
    public static func megabytes(_ speed: Double) -> (value: Double, decimals: Int) {
        let value = max(0, speed) / 1_000_000
        let tenths = (value * 10).rounded() / 10
        return tenths < 10 ? (tenths, 1) : (value.rounded(), 0)
    }
}
