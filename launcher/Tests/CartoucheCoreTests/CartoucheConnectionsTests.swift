//
//  CartoucheConnectionsTests.swift
//  CartoucheCoreTests
//
//  The player's connections as an iPhone and its Mac give them to each
//  other (Sources/CartoucheConnections.swift): of each one, the one changed
//  last, a removal that goes across and is forgotten after 180 days, a
//  secret the other side does not give kept, the same place added on both
//  sides made one under the ID that sorts first, what stays on its device
//  left out, and both sides ending with the same whichever asked; of the
//  folders its iPhones chose, those a Mac keeps.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheConnectionsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60

    /// IDs whose order is known: A before B before C.
    let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
    let b = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
    let c = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000003")!

    func nas(_ id: UUID, name: String = "NAS", host: String = "nas.local", share: String = "Games", user: String = "ad",
             secret: String? = "pw", at changed: Date) -> CartoucheConnection {
        CartoucheConnection(id: id, kind: "smb", name: name, host: host, username: user, share: share, secret: secret, changed: changed)
    }

    /// The connections by ID, whatever their order.
    func byID(_ connections: [CartoucheConnection]) -> [UUID: CartoucheConnection] {
        Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
    }

    /// What the Mac keeps and answers, then what the iPhone keeps of it:
    /// both the same.
    func exchanged(iPhone: [CartoucheConnection], mac: [CartoucheConnection]) -> [CartoucheConnection] {
        let onMac = CartoucheConnections.merged(mac, iPhone, now: now)
        let onIPhone = CartoucheConnections.merged(iPhone, onMac, now: now)
        XCTAssertEqual(byID(onIPhone), byID(onMac), "both sides end with the same")
        // Nothing changes when they meet again.
        XCTAssertEqual(byID(CartoucheConnections.merged(onMac, onIPhone, now: now)), byID(onMac))
        return onIPhone
    }

    // MARK: The one changed last

    func testEachSideEndsWithTheOneChangedLast() {
        let older = nas(a, name: "NAS", at: now.addingTimeInterval(-60))
        let newer = nas(a, name: "NAS du salon", secret: "new", at: now)
        XCTAssertEqual(exchanged(iPhone: [older], mac: [newer]), [newer])
        XCTAssertEqual(exchanged(iPhone: [newer], mac: [older]), [newer])
        // What only one side has goes to the other, in the order each had them.
        let drive = CartoucheConnection(id: c, kind: "drive", name: "Drive", host: "ad@example.com", username: "client.apps.googleusercontent.com",
                                        secret: "refresh", changed: now)
        let s3 = CartoucheConnection(id: b, kind: "s3", name: "Bucket", host: "s3.eu-west-3.amazonaws.com", username: "AKIA", share: "saves",
                                     region: "eu-west-3", secret: "secret", changed: now)
        XCTAssertEqual(CartoucheConnections.merged([drive], [s3, older], now: now).map(\.id), [c, b, a])
        XCTAssertEqual(exchanged(iPhone: [drive], mac: [s3]).count, 2)
    }

    func testAtTheSameTimeBothSidesChooseTheSame() {
        let one = nas(a, name: "NAS", at: now)
        let other = nas(a, name: "NAS du bureau", at: now)
        let chosen = CartoucheConnections.merged([one], [other], now: now)
        XCTAssertEqual(chosen, CartoucheConnections.merged([other], [one], now: now))
        XCTAssertEqual(chosen.first?.name, "NAS", "the fields that sort first")
        // A removal at the same time as a change wins.
        var gone = one
        gone.removed = true
        gone.secret = nil
        XCTAssertEqual(CartoucheConnections.merged([other], [gone], now: now), [gone])
        XCTAssertEqual(CartoucheConnections.merged([gone], [other], now: now), [gone])
    }

    // MARK: Removals

    func testARemovalGoesAcrossAndIsForgottenAfterHalfAYear() {
        let kept = nas(a, at: now.addingTimeInterval(-day))
        var gone = nas(a, secret: nil, at: now)
        gone.removed = true
        XCTAssertEqual(exchanged(iPhone: [kept], mac: [gone]), [gone])
        // Remembered for 180 days, then forgotten.
        XCTAssertEqual(CartoucheConnections.merged([gone], [], now: now.addingTimeInterval(179 * day)), [gone])
        XCTAssertEqual(CartoucheConnections.merged([gone], [], now: now.addingTimeInterval(181 * day)), [])
        // A change after the removal brings the connection back.
        let changed = nas(a, name: "NAS again", at: now.addingTimeInterval(day))
        XCTAssertEqual(exchanged(iPhone: [gone], mac: [changed]), [changed])
    }

    // MARK: Secrets

    func testASecretTheNewestDoesNotGiveStaysTheOthers() {
        let withSecret = nas(a, name: "NAS", secret: "pw", at: now.addingTimeInterval(-60))
        let renamed = nas(a, name: "NAS du salon", secret: nil, at: now)
        let merged = exchanged(iPhone: [withSecret], mac: [renamed])
        XCTAssertEqual(merged.first?.name, "NAS du salon")
        XCTAssertEqual(merged.first?.secret, "pw")
        // A removal takes no secret along.
        var gone = renamed
        gone.removed = true
        XCTAssertNil(CartoucheConnections.merged([withSecret], [gone], now: now).first?.secret)
    }

    // MARK: The same place on both sides

    func testTheSamePlaceAddedOnBothSidesBecomesOne() {
        // The iPhone's under B, the Mac's under A, typed otherwise.
        let iPhone = nas(b, name: "NAS", host: "NAS.local", share: "Games", user: "Ad", secret: "old", at: now.addingTimeInterval(-day))
        let mac = nas(a, name: "Le NAS", host: " nas.local", share: "games", user: "ad", secret: "new", at: now)
        let merged = exchanged(iPhone: [iPhone], mac: [mac])
        let found = byID(merged)
        // The newest, under the ID that sorts first.
        XCTAssertEqual(found[a]?.name, "Le NAS")
        XCTAssertEqual(found[a]?.secret, "new")
        XCTAssertEqual(found[a]?.removed, false)
        // The other removed for it, so that its folders move there.
        XCTAssertEqual(found[b]?.removed, true)
        XCTAssertEqual(found[b]?.replacedBy, a)
        XCTAssertNil(found[b]?.secret)
        XCTAssertEqual(found[b]?.changed, now)
        XCTAssertEqual(CartoucheConnections.current(b, in: merged), a)
        XCTAssertEqual(CartoucheConnections.current(a, in: merged), a)

        // The newest under the ID that sorts last: its content goes under
        // the first.
        let newerB = nas(b, name: "NAS (iPhone)", secret: "newest", at: now.addingTimeInterval(day))
        let both = exchanged(iPhone: [newerB], mac: [mac])
        XCTAssertEqual(byID(both)[a]?.name, "NAS (iPhone)")
        XCTAssertEqual(byID(both)[a]?.secret, "newest")
        XCTAssertEqual(byID(both)[a]?.changed, now.addingTimeInterval(day))
        XCTAssertEqual(byID(both)[b]?.replacedBy, a)

        // Three devices: each that meets the others ends with the one.
        let third = nas(c, name: "NAS (Duo)", at: now.addingTimeInterval(-2 * day))
        let onMac = CartoucheConnections.merged([mac], [iPhone], now: now)
        let onDuo = CartoucheConnections.merged([third], onMac, now: now)
        XCTAssertEqual(onDuo.filter { !$0.removed }.map(\.id), [a])
        XCTAssertEqual(CartoucheConnections.current(c, in: onDuo), a)
    }

    func testPlacesAreTheSameKindAddressAndAccount() {
        func place(_ kind: String, host: String = "h", port: Int? = nil, user: String = "u", share: String = "s") -> String {
            CartoucheConnection(id: UUID(), kind: kind, name: "", host: host, port: port, username: user, share: share, changed: now).place
        }
        // SMB: the server takes any case; its port by default.
        XCTAssertEqual(place("smb", host: "NAS.local", user: "Ad", share: "Games"), place("smb", host: "nas.local ", user: "ad", share: "games"))
        XCTAssertEqual(place("smb"), place("smb", port: 445))
        XCTAssertNotEqual(place("smb", user: "ad"), place("smb", user: "guest"))
        XCTAssertNotEqual(place("smb", share: "Games"), place("smb", share: "Saves"))
        // FTP and SFTP: an account's case matters there.
        XCTAssertEqual(place("ftp"), place("ftp", port: 21))
        XCTAssertEqual(place("sftp"), place("sftp", port: 22))
        XCTAssertNotEqual(place("sftp", user: "Ad"), place("sftp", user: "ad"))
        XCTAssertNotEqual(place("ftp"), place("sftp"))
        // S3: the bucket and the key as they are.
        XCTAssertNotEqual(place("s3", share: "Saves"), place("s3", share: "saves"))
        XCTAssertEqual(place("s3", host: "S3.eu-west-3.amazonaws.com"), place("s3", host: "s3.eu-west-3.amazonaws.com"))
        // The Drive: the player's client and their Google account.
        XCTAssertEqual(place("drive", host: "Ad@Example.com"), place("drive", host: "ad@example.com"))
        XCTAssertNotEqual(place("drive", user: "one"), place("drive", user: "two"))
        // A kind this side does not know is never the same as another.
        XCTAssertNotEqual(place("webdav"), place("webdav"))
    }

    // MARK: What stays on its device

    func testWhatStaysOnItsDeviceDoesNotGo() {
        let mac = CartoucheConnection(id: a, kind: "mac", name: "Mac", secret: "paired key", changed: now)
        let folder = CartoucheConnection(id: b, kind: "folder", name: "Dossier", changed: now)
        let newer = CartoucheConnection(id: c, kind: "webdav", name: "Plus tard", changed: now)
        XCTAssertEqual(CartoucheConnections.merged([], [mac, folder, newer], now: now), [])
        XCTAssertFalse(CartoucheConnections.kinds.contains("mac"))
        XCTAssertFalse(CartoucheConnections.kinds.contains("folder"))
        XCTAssertEqual(CartoucheConnections.kinds, ["smb", "s3", "ftp", "sftp", "drive"])
    }

    // MARK: Over the bridge

    func testTheConnectionsGoThereAndBack() throws {
        var gone = nas(b, secret: nil, at: now.addingTimeInterval(0.123_456))
        gone.removed = true
        gone.replacedBy = a
        let sent = [nas(a, at: now), gone,
                    CartoucheConnection(id: c, kind: "sftp", name: "Serveur", host: "10.0.0.2", port: 2222, username: "ad",
                                        hostKey: "ssh-ed25519 AAAA", secret: "pw", changed: now)]
        let back = try JSONDecoder().decode([CartoucheConnection].self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(back, sent)
    }

    func testWhatASideALittleOlderOrNewerLeavesOutTakesItsDefault() throws {
        let json = #"[{"id": "AAAAAAAA-0000-4000-8000-000000000001", "kind": "smb", "later": true}]"#
        let found = try XCTUnwrap(JSONDecoder().decode([CartoucheConnection].self, from: Data(json.utf8)).first)
        XCTAssertEqual(found.id, a)
        XCTAssertEqual(found.name, "")
        XCTAssertEqual(found.host, "")
        XCTAssertNil(found.secret)
        XCTAssertFalse(found.removed)
        XCTAssertNil(found.replacedBy)
        XCTAssertEqual(found.changed, Date(timeIntervalSince1970: 0))
    }

    // MARK: Replacements

    func testAReplacementLeadsToTheConnectionKept() {
        var first = nas(a, secret: nil, at: now)
        first.removed = true
        first.replacedBy = b
        var second = nas(b, secret: nil, at: now)
        second.removed = true
        second.replacedBy = c
        let kept = nas(c, at: now)
        XCTAssertEqual(CartoucheConnections.current(a, in: [first, second, kept]), c)
        // Removed for no other, or unknown here.
        var alone = kept
        alone.removed = true
        XCTAssertNil(CartoucheConnections.current(c, in: [alone]))
        XCTAssertNil(CartoucheConnections.current(a, in: [kept]))
        // A loop ends.
        var back = second
        back.replacedBy = a
        XCTAssertNil(CartoucheConnections.current(a, in: [first, back]))
    }

    // MARK: The folders chosen on the iPhones

    func testAMacKeepsTheFoldersChosenLast() {
        let nasSaves = CartoucheChosenFolders.Folder(connection: a, path: "Cartouche/Saves", chosen: now)
        let driveSaves = CartoucheChosenFolders.Folder(connection: b, path: "Saves", chosen: now + 60)
        let macGames = CartoucheChosenFolders.Folder(connection: nil, path: "", chosen: now)
        // Told of none yet: it takes what it is told.
        let first = CartoucheChosenFolders().taking(CartoucheChosenFolders(games: macGames, saves: nasSaves))
        XCTAssertEqual(first, CartoucheChosenFolders(games: macGames, saves: nasSaves))
        // Another iPhone chose its saves folder later: it wins; its games
        // folder, of none told, leaves the one kept.
        let second = first.taking(CartoucheChosenFolders(saves: driveSaves))
        XCTAssertEqual(second, CartoucheChosenFolders(games: macGames, saves: driveSaves))
        // The first iPhone, telling again what it chose before, changes
        // nothing; chosen at the same time, neither: no taking turns.
        XCTAssertEqual(second.taking(CartoucheChosenFolders(games: macGames, saves: nasSaves)), second)
        let same = CartoucheChosenFolders.Folder(connection: c, path: "Saves", chosen: now + 60)
        XCTAssertEqual(second.taking(CartoucheChosenFolders(saves: same)), second)
        // No folder, chosen later, wins too: the Mac's own again.
        let none = CartoucheChosenFolders.Folder(connection: nil, path: "", chosen: now + 120)
        XCTAssertEqual(second.taking(CartoucheChosenFolders(saves: none)).saves, none)
    }

    func testTheFoldersChosenGoThereAndBack() throws {
        let told = CartoucheChosenFolders(games: .init(connection: nil, path: "", chosen: now),
                                          saves: .init(connection: a, path: "Cartouche/Saves", chosen: now + 0.5))
        let request = CartoucheBridgeRequest(.connections, connections: [], places: told)
        let back = try JSONDecoder().decode(CartoucheBridgeRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(back.places, told)
        // From an iPhone a little older, which tells none.
        let older = try JSONDecoder().decode(CartoucheBridgeRequest.self, from: Data(#"{"op":"connections","connections":[]}"#.utf8))
        XCTAssertNil(older.places)
    }
}
