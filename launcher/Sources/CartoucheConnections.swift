//
//  CartoucheConnections.swift
//  Cartouche
//
//  The player's connections to their own storage, as an iPhone and the Mac
//  it is paired with give them to each other over the bridge
//  (CartoucheBridge.swift), so that both reach the same places: a shared
//  folder of a NAS, an S3 bucket, an FTP or SFTP server, a Google Drive,
//  each with its password, secret key or Google sign-in, which the bridge
//  carries encrypted. A Mac's pairing stays on its iPhone, the key being
//  theirs alone, and so does a folder picked on a device, which only that
//  device can open again.
//
//  Each side sends all it has, with when the player last changed each
//  connection there, or removed it, and keeps, of a connection both have,
//  the one changed last: both end with the same, whichever side asked. The
//  same place added on both sides, the same kind at the same address with
//  the same account, becomes one connection: the one changed last, under
//  the ID that sorts first, the other removed for it, so that the folders
//  chosen on it move to the one kept. A removal is remembered for 180
//  days, for a device that has not met the other since.
//
//  This file is shared: Cartouche compiles it with the launcher, Cartouche
//  Builder through the CartoucheCore package (launcher/Package.swift). It
//  needs only Foundation.
//

import Foundation

/// One of the player's connections, as it goes over the bridge.
public struct CartoucheConnection: Codable, Equatable, Sendable {
    public var id: UUID
    /// The kind of place, as the storage's servers name it
    /// (CartoucheStorageServer.Kind): smb, s3, ftp, sftp or drive.
    public var kind: String
    /// What the player calls it.
    public var name: String
    public var host: String
    public var port: Int?
    public var username: String
    public var share: String
    public var region: String?
    /// SFTP: the server's key, kept when it was first reached.
    public var hostKey: String?
    /// The password, secret key or Google sign-in; nil when the side that
    /// sends it has none, which leaves the other's as it is.
    public var secret: String?
    /// When the player last changed it, or removed it, on either side.
    public var changed: Date
    /// Removed: what stays of it, so that the other side removes it too.
    public var removed: Bool
    /// Removed for another connection of the same place: the folders chosen
    /// on this one go to that one.
    public var replacedBy: UUID?

    public init(id: UUID, kind: String, name: String, host: String = "", port: Int? = nil, username: String = "", share: String = "",
                region: String? = nil, hostKey: String? = nil, secret: String? = nil, changed: Date, removed: Bool = false,
                replacedBy: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.share = share
        self.region = region
        self.hostKey = hostKey
        self.secret = secret
        self.changed = changed
        self.removed = removed
        self.replacedBy = replacedBy
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, host, port, username, share, region, hostKey, secret, changed, removed, replacedBy
    }

    /// What a side a little older or newer leaves out takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        share = try c.decodeIfPresent(String.self, forKey: .share) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region)
        hostKey = try c.decodeIfPresent(String.self, forKey: .hostKey)
        secret = try c.decodeIfPresent(String.self, forKey: .secret)
        changed = try c.decodeIfPresent(Date.self, forKey: .changed) ?? Date(timeIntervalSince1970: 0)
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        replacedBy = try c.decodeIfPresent(UUID.self, forKey: .replacedBy)
    }

    /// What makes two connections the same place: the kind, the address
    /// and the account, whatever case or spaces the player typed them in
    /// where the server takes either, and the port it uses when none is
    /// given.
    public var place: String {
        func folded(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch kind {
        case "smb":
            return ["smb", folded(host), String(port ?? 445), folded(share), folded(username)].joined(separator: "|")
        case "s3":
            return ["s3", folded(host), trimmed(share), trimmed(username)].joined(separator: "|")
        case "ftp":
            return ["ftp", folded(host), String(port ?? 21), trimmed(username)].joined(separator: "|")
        case "sftp":
            return ["sftp", folded(host), String(port ?? 22), trimmed(username)].joined(separator: "|")
        case "drive":
            return ["drive", trimmed(username), folded(host)].joined(separator: "|")
        default:
            // A kind of place this side does not know is never another's.
            return kind + "|" + id.uuidString
        }
    }

    /// Its fields in one line, to choose the same of two that differ but
    /// were changed at the same time, on either side.
    var fields: String {
        [id.uuidString, kind, name, host, port.map(String.init) ?? "", username, share, region ?? "", hostKey ?? "",
         secret ?? "", removed ? "1" : "0", replacedBy?.uuidString ?? ""].joined(separator: "\u{1F}")
    }
}

/// The folders the player chose on an iPhone for the games and the saves,
/// as the paired Mac is told them with the connections: the Mac keeps the
/// saves of the games played on it in the same saves folder, and sends its
/// builds to the same games folder, when they are on a connection both
/// have. Of what its iPhones told it, a Mac keeps, for each, the folder
/// chosen last (taking).
public struct CartoucheChosenFolders: Codable, Equatable, Sendable {
    public struct Folder: Codable, Equatable, Sendable {
        /// The connection it is on; nil for none the Mac has: a folder
        /// picked on the iPhone, the Mac's own through the bridge, or no
        /// folder at all.
        public var connection: UUID?
        /// From the connection's root, folders joined by "/".
        public var path: String
        /// When the player chose it on the iPhone.
        public var chosen: Date

        public init(connection: UUID?, path: String, chosen: Date) {
            self.connection = connection
            self.path = path
            self.chosen = chosen
        }
    }

    public var games: Folder?
    public var saves: Folder?

    public init(games: Folder? = nil, saves: Folder? = nil) {
        self.games = games
        self.saves = saves
    }

    /// These, with the folders TOLD gives that were chosen later, as a Mac
    /// keeps what its iPhones tell it: one chosen at the same time as the
    /// one kept leaves it, so that two iPhones never take turns.
    public func taking(_ told: CartoucheChosenFolders) -> CartoucheChosenFolders {
        func later(_ kept: Folder?, _ told: Folder?) -> Folder? {
            guard let told else { return kept }
            guard let kept else { return told }
            return told.chosen > kept.chosen ? told : kept
        }
        return CartoucheChosenFolders(games: later(games, told.games), saves: later(saves, told.saves))
    }
}

public enum CartoucheConnections {
    /// The kinds of place that go over the bridge.
    public static let kinds: Set<String> = ["smb", "s3", "ftp", "sftp", "drive"]
    /// How long a removal is remembered, in seconds.
    public static let remembered: TimeInterval = 180 * 24 * 60 * 60

    /// MINE and THEIRS as one list: of each connection, the one changed
    /// last; of two of the same place, one. In MINE's order, then THEIRS's
    /// new ones. Kinds this side does not know (KNOWN), and removals
    /// older than they are remembered at NOW, are left out.
    public static func merged(_ mine: [CartoucheConnection], _ theirs: [CartoucheConnection],
                              known: Set<String> = kinds, now: Date = Date()) -> [CartoucheConnection] {
        var order: [UUID] = []
        var chosen: [UUID: CartoucheConnection] = [:]
        for connection in mine + theirs where known.contains(connection.kind) {
            if let held = chosen[connection.id] {
                chosen[connection.id] = later(held, connection)
            } else {
                order.append(connection.id)
                chosen[connection.id] = connection
            }
        }
        // One connection of each place.
        var places: [String: [UUID]] = [:]
        var placeOrder: [String] = []
        for id in order {
            guard let connection = chosen[id], !connection.removed else { continue }
            if places[connection.place] == nil { placeOrder.append(connection.place) }
            places[connection.place, default: []].append(id)
        }
        for place in placeOrder {
            guard let ids = places[place], ids.count > 1,
                  let kept = ids.min(by: { $0.uuidString < $1.uuidString }) else { continue }
            let same = ids.compactMap { chosen[$0] }
            guard let first = same.first, let when = same.map(\.changed).max() else { continue }
            var one = same.dropFirst().reduce(first, later)
            if one.secret == nil {
                // The secret of another, when the newest gives none.
                one.secret = same.sorted { $0.changed > $1.changed }.lazy.compactMap(\.secret).first
            }
            one.id = kept
            one.changed = when
            one.replacedBy = nil
            chosen[kept] = one
            for id in ids where id != kept {
                guard var gone = chosen[id] else { continue }
                gone.removed = true
                gone.secret = nil
                gone.changed = when
                gone.replacedBy = kept
                chosen[id] = gone
            }
        }
        return order.compactMap { chosen[$0] }.filter { !$0.removed || now.timeIntervalSince($0.changed) < remembered }
    }

    /// Of A and B, the same connection, the one changed last: at the same
    /// time, the removal, then the one whose fields sort first, so that
    /// both sides choose the same. A secret the winner does not give stays
    /// the other's.
    static func later(_ a: CartoucheConnection, _ b: CartoucheConnection) -> CartoucheConnection {
        var winner: CartoucheConnection
        let loser: CartoucheConnection
        if a.changed != b.changed {
            (winner, loser) = a.changed > b.changed ? (a, b) : (b, a)
        } else if a.removed != b.removed {
            (winner, loser) = a.removed ? (a, b) : (b, a)
        } else {
            (winner, loser) = a.fields <= b.fields ? (a, b) : (b, a)
        }
        if !winner.removed, winner.secret == nil {
            winner.secret = loser.secret
        }
        return winner
    }

    /// The connection ID stands for now: itself, or the one it was
    /// replaced by, and that one's, in CONNECTIONS; nil when it was removed
    /// for no other, or is not there.
    public static func current(_ id: UUID, in connections: [CartoucheConnection]) -> UUID? {
        var byID: [UUID: CartoucheConnection] = [:]
        for connection in connections { byID[connection.id] = connection }
        var at = id
        // A chain longer than the list is a loop.
        for _ in 0...connections.count {
            guard let connection = byID[at] else { return nil }
            guard connection.removed else { return at }
            guard let next = connection.replacedBy else { return nil }
            at = next
        }
        return nil
    }
}
