//
//  CartoucheTailscale.swift
//  Cartouche
//
//  Tailscale, which the player installs apart, from the App Store, on the
//  iPhone and on their Mac or NAS: it puts them in one private network of
//  theirs, a tailnet, wherever each one is, each device with an address of
//  its own there, in 100.64.0.0/10 and fd7a:115c:a1e0::/48, and a name,
//  <machine>.<tailnet>.ts.net, which MagicDNS answers. Cartouche neither
//  installs nor drives it: it reads whether its tunnel is up, from the
//  device's interfaces, as it reads LocalDevVPN's (CartoucheVPN.swift),
//  without connecting to anything.
//
//  With it, Cartouche reaches the player's Mac away from its Wi-Fi, where
//  Bonjour does not go: Cartouche Builder tells the iPhone its addresses in
//  the tailnet (CartoucheBridge.swift, info), the iPhone keeps them with the
//  Mac (CartoucheStorageServer.tailnet) and tries them beside the last
//  address while Tailscale is on (CartoucheStorageMac.swift); a Mac never
//  met on a Wi-Fi pairs by its Tailscale name or address. A NAS or another
//  server is reached by the name or the address the player types, as ever.
//
//  iOS keeps one VPN at a time: LocalDevVPN, which Cartouche connects for
//  what the built-in SideStore does (CartoucheLocalDevVPN.swift), turns
//  Tailscale off until the player turns it on again. So Cartouche does not
//  renew itself by itself while Tailscale is on, until its last days
//  (CartoucheAutomaticRenewal), says to turn Tailscale on when a server
//  that only answers through it does not answer (CartoucheStorageOffline),
//  and, once what needed LocalDevVPN is done, that LocalDevVPN turned it
//  off (CartoucheTailscaleReminder).
//
//  This file is shared: Cartouche compiles it with the launcher, Cartouche
//  Builder through the CartoucheCore package (launcher/Package.swift), and
//  the console of the Mac links it. It needs only Foundation.
//

import Foundation

/// An interface of this device that is up, and one of its addresses, as
/// getnameinfo writes it: "100.101.102.103", "fd7a:115c:a1e0::1".
public struct CartoucheNetworkInterface: Equatable, Sendable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public enum CartoucheTailscale {
    /// Tailscale on the App Store, where the player installs it.
    public static let appStore = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!
    /// Tailscale for the Mac, on its site, which leads to the Mac App Store
    /// and to its own download: Cartouche Builder's iPhone page links it.
    public static let macDownload = URL(string: "https://tailscale.com/download/mac")!

    // MARK: Addresses and names of a tailnet

    /// Whether TEXT is an address Tailscale gives a device of a tailnet:
    /// IPv4 in 100.64.0.0/10, the shared address space of RFC 6598, or IPv6
    /// in fd7a:115c:a1e0::/48, Tailscale's own. Brackets and an interface
    /// after "%" may go with it.
    public static func isTailnetAddress(_ text: String) -> Bool {
        var address = text.trimmingCharacters(in: .whitespaces).lowercased()
        if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        if let zone = address.firstIndex(of: "%") { address = String(address[..<zone]) }
        if address.contains(":") {
            // The first three groups are not zero: no "::" stands for them,
            // and none is written with leading zeros.
            return address.hasPrefix("fd7a:115c:a1e0:")
        }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let bytes = parts.compactMap { part -> Int? in
            guard (1 ... 3).contains(part.count), part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber) else { return nil }
            return Int(part).flatMap { $0 <= 255 ? $0 : nil }
        }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 100 && (64 ... 127).contains(bytes[1])
    }

    /// Whether HOST is a MagicDNS name, "nas.tail1234.ts.net": a name of a
    /// device of a tailnet, which only Tailscale answers. Tailnets made
    /// before 2022 had their names under beta.tailscale.net.
    public static func isMagicDNSName(_ host: String) -> Bool {
        var name = host.trimmingCharacters(in: .whitespaces).lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        return [".ts.net", ".beta.tailscale.net"].contains { suffix in
            name.hasSuffix(suffix) && name.count > suffix.count && !name.dropLast(suffix.count).hasSuffix(".")
        }
    }

    /// Whether HOST, an address or a name, is reached through Tailscale
    /// alone.
    public static func isTailnetHost(_ host: String) -> Bool {
        isTailnetAddress(host) || isMagicDNSName(host)
    }

    // MARK: Whether Tailscale is on

    /// The addresses in a tailnet among INTERFACES: those of a tunnel,
    /// utun<n>, as Tailscale's is on iOS and macOS, IPv4 first. A carrier's
    /// network may give the iPhone an address in 100.64.0.0/10 too, on its
    /// own interface (pdp_ip<n>), which is not Tailscale's.
    public static func addresses(in interfaces: [CartoucheNetworkInterface]) -> [String] {
        var seen = Set<String>()
        let found = interfaces.filter { $0.name.lowercased().hasPrefix("utun") && isTailnetAddress($0.address) }
            .map { interface -> String in
                let address = interface.address
                return address.firstIndex(of: "%").map { String(address[..<$0]) } ?? address
            }
            .filter { seen.insert($0).inserted }
        return found.filter { !$0.contains(":") } + found.filter { $0.contains(":") }
    }

    /// Whether these interfaces hold Tailscale's tunnel.
    public static func isConnected(_ interfaces: [CartoucheNetworkInterface]) -> Bool {
        !addresses(in: interfaces).isEmpty
    }

    #if CARTOUCHE_GALLERY
    /// Whether Tailscale is on, in the launcher's gallery (launcher/Gallery):
    /// as its scenario says, never as the Mac under the simulator has it.
    public static var galleryConnected = false
    #endif

    /// Whether Tailscale is connected on this device now.
    public static var isConnected: Bool {
        #if CARTOUCHE_GALLERY
        return galleryConnected
        #else
        return isConnected(interfaces())
        #endif
    }

    /// This device's own addresses in its tailnet: none without Tailscale.
    public static func ownAddresses() -> [String] {
        addresses(in: interfaces())
    }

    /// This device's interfaces that are up, with their IPv4 and IPv6
    /// addresses.
    public static func interfaces() -> [CartoucheNetworkInterface] {
        #if canImport(Darwin)
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var found: [CartoucheNetworkInterface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0, let address = entry.ifa_addr else { continue }
            let family = address.pointee.sa_family
            guard family == sa_family_t(AF_INET) || family == sa_family_t(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            found.append(CartoucheNetworkInterface(name: String(cString: entry.ifa_name), address: text))
        }
        return found
        #else
        return []
        #endif
    }

    // MARK: The player's Mac in the tailnet

    /// The addresses Cartouche tries for a Mac, in order, before it looks
    /// for it with Bonjour: the one it last reached it at, HOST, then, while
    /// Tailscale is on here (TAILSCALE_ON), the Mac's addresses in the
    /// tailnet, TAILNET. Without Tailscale, an address of the tailnet
    /// answers nowhere: none is tried.
    public static func addressesToTry(host: String, tailnet: [String], tailscaleOn: Bool) -> [String] {
        var addresses: [String] = []
        let last = host.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty, tailscaleOn || !isTailnetHost(last) { addresses.append(last) }
        if tailscaleOn {
            for address in tailnet.map({ $0.trimmingCharacters(in: .whitespaces) }) where !address.isEmpty && !addresses.contains(address) {
                addresses.append(address)
            }
        }
        return addresses
    }
}

/// Whether Cartouche says, on the console's top bar, to turn Tailscale on
/// again: LocalDevVPN, which Cartouche connected for the built-in SideStore,
/// turned it off, iOS keeping one VPN at a time, and Tailscale has no link
/// Cartouche could open to turn it on itself.
public enum CartoucheTailscaleReminder {
    /// Where Cartouche keeps when LocalDevVPN turned Tailscale off, across
    /// launches: an update of Cartouche starts it again.
    public static let key = "Cartouche.tailscale.turnedOff"
    /// How long Cartouche says so at most, in seconds: the player may keep
    /// Tailscale off.
    public static let lasts: TimeInterval = 12 * 3_600
    /// How long after Cartouche opened LocalDevVPN, Tailscale on, Tailscale
    /// seen off is LocalDevVPN's doing rather than the player's, in seconds:
    /// LocalDevVPN connects and brings Cartouche back within seconds
    /// (decision 98), and Tailscale stays on until it has connected.
    public static let opening: TimeInterval = 10 * 60

    /// Whether Tailscale, seen off at NOW, went off for the LocalDevVPN
    /// Cartouche opened at OPENED with Tailscale on.
    public static func turnedOff(byOpeningAt opened: Date, seenOffAt now: Date) -> Bool {
        let since = now.timeIntervalSince(opened)
        return since >= 0 && since < opening
    }

    /// Whether to say it now: LocalDevVPN turned Tailscale off at
    /// TURNED_OFF, Tailscale is still off (TAILSCALE_ON), and nothing that
    /// needs LocalDevVPN is under way (BUSY), which turning Tailscale on
    /// would stop.
    public static func shows(turnedOff: Date?, tailscaleOn: Bool, busy: Bool, at now: Date) -> Bool {
        guard let turnedOff, !tailscaleOn, !busy else { return false }
        let since = now.timeIntervalSince(turnedOff)
        return since >= 0 && since < lasts
    }
}

/// Where Cartouche keeps a Mac it reaches: the address and the port it
/// last reached it at, on the player's network, and its addresses in their
/// tailnet, as the Mac's app tells them (CartoucheStorageServer's host, port
/// and tailnet).
public struct CartoucheMacAddresses: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var tailnet: [String]

    public init(host: String, port: Int?, tailnet: [String]) {
        self.host = host
        self.port = port
        self.tailnet = tailnet
    }

    /// These addresses once Cartouche reached the Mac at REACHED, on PORT,
    /// and the Mac's app told it TOLD, its addresses in the tailnet: nil
    /// when it said nothing, as a Cartouche Builder older than this one.
    /// An address of the tailnet stays beside the one of the player's
    /// network, which the iPhone tries first at home, where the Wi-Fi goes
    /// faster than through Tailscale; it takes its place only when there
    /// is none, as for a Mac paired through Tailscale. The Mac listens on
    /// one port for all its networks: the one reached is kept. A Mac that
    /// says it has no address in the tailnet keeps those it had: its
    /// Tailscale may be off a moment.
    public func reached(_ reached: String?, port reachedPort: Int?, told: [String]?) -> CartoucheMacAddresses {
        var kept = self
        if let reached, !reached.isEmpty {
            if let reachedPort { kept.port = reachedPort }
            if !CartoucheTailscale.isTailnetHost(reached) {
                kept.host = reached
            } else {
                if kept.host.isEmpty || CartoucheTailscale.isTailnetHost(kept.host) { kept.host = reached }
                if !kept.tailnet.contains(reached) { kept.tailnet.insert(reached, at: 0) }
            }
        }
        if let told {
            var seen = Set<String>()
            let addresses = told.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { CartoucheTailscale.isTailnetAddress($0) && seen.insert($0).inserted }
            if !addresses.isEmpty { kept.tailnet = addresses }
        }
        return kept
    }
}

/// An address the player types for their Mac: a name, "macbook-air" or
/// "macbook-air.tail1234.ts.net", or an address, "100.101.102.103",
/// "fd7a:115c:a1e0::1", with or without a port after it, ":47920" or
/// "[fd7a:115c:a1e0::1]:47920".
public struct CartoucheTypedAddress: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    /// TEXT as a host and a port, PORT when it gives none; nil for what is
    /// neither a name nor an address: spaces, a scheme, a path.
    public static func parse(_ text: String, port: UInt16) -> CartoucheTypedAddress? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains(" "), !typed.contains("/"), !typed.contains("@") else { return nil }
        var host = typed
        var given: UInt16?
        if typed.hasPrefix("[") {
            // [IPv6]:port
            guard let close = typed.firstIndex(of: "]") else { return nil }
            host = String(typed[typed.index(after: typed.startIndex) ..< close])
            let rest = typed[typed.index(after: close)...]
            if !rest.isEmpty {
                guard rest.hasPrefix(":"), let number = UInt16(rest.dropFirst()), number > 0 else { return nil }
                given = number
            }
        } else if typed.filter({ $0 == ":" }).count == 1, let colon = typed.firstIndex(of: ":") {
            // name:port or IPv4:port; more colons make an IPv6 address.
            host = String(typed[..<colon])
            guard let number = UInt16(typed[typed.index(after: colon)...]), number > 0 else { return nil }
            given = number
        }
        guard !host.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:%")
        guard host.unicodeScalars.allSatisfy(allowed.contains), !host.hasPrefix("."), !host.hasPrefix("-") else { return nil }
        if host.contains(":") {
            guard host.filter({ $0 == ":" }).count >= 2 else { return nil }
        } else if host.contains("%") {
            return nil
        }
        return CartoucheTypedAddress(host: host, port: given ?? port)
    }
}
