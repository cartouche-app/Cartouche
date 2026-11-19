//
//  CartoucheResetPlanTests.swift
//  CartoucheCoreTests
//
//  What System › Reset Cartouche erases and keeps
//  (Sources/CartoucheResetPlan.swift), on a home laid out as Cartouche's
//  on an iPhone: the games and their data folders, the built-in
//  SideStore's home with the pairing file, the preferences, the
//  telemetry's file, the caches, a folder of the player's storage in
//  Cartouche's own Documents, a link out of the home, and an app group
//  that other apps share, or one in the home, as an install with the
//  player's own certificate has.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheResetPlanTests: XCTestCase {
    /// A folder of its own, removed after the test.
    private func folder(_ name: String = UUID().uuidString) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.resolvingSymlinksInPath()
    }

    private func write(_ text: String, at path: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func makeFolder(_ path: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(path, isDirectory: true),
                                                withIntermediateDirectories: true)
    }

    /// Every file and folder under FOLDER, by its path there, a link as
    /// "path@", never followed.
    private func tree(_ folder: URL) -> [String] {
        var found: [String] = []
        func walk(_ url: URL, _ prefix: String) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            for name in names.sorted() {
                let item = url.appendingPathComponent(name)
                let path = prefix.isEmpty ? name : prefix + "/" + name
                let type = (try? FileManager.default.attributesOfItem(atPath: item.path))?[.type] as? FileAttributeType
                if type == .typeSymbolicLink {
                    found.append(path + "@")
                } else if type == .typeDirectory {
                    found.append(path + "/")
                    walk(item, path)
                } else {
                    found.append(path)
                }
            }
        }
        walk(folder, "")
        return found
    }

    // MARK: The keychain

    func testTheCertificateAndAnisetteStayNeverTheAppleID() {
        for account in ["signingCertificate", "signingCertificatePassword", "signingCertificatePrivateKey",
                        "signingCertificateSerialNumber", "identifier", "adiPb", "cartoucheAnisette",
                        "Cartouche.importedSigning.material", "importedCert_3A2F00C1"] {
            XCTAssertTrue(CartoucheResetPlan.keepsStoreItem(account: account), account)
        }
        for account in ["appleIDEmailAddress", "appleIDPassword", "appleIDAdsid", "appleIDXcodeToken", "deviceUDID",
                        "cartoucheSignIn.credentials", "cartoucheSignIn.request", "cartoucheSignIn.response",
                        "cartouche.outcome", "importedCert", "signingCertificateBackup", ""] {
            XCTAssertFalse(CartoucheResetPlan.keepsStoreItem(account: account), account)
        }
    }

    // MARK: Preferences

    func testOnlyCartouchesOwnKeysLeaveTheAppGroup() {
        XCTAssertTrue(CartoucheResetPlan.isCartouches(appGroupKey: "CartoucheSignInRequested"))
        for key in ["LCCertificateData", "LCCertificatePassword", "LCCertificateUpdateDate", "LCGuestURLSchemes",
                    "LCBundleID.cartouche", "hasCompletedOnboarding"] {
            XCTAssertFalse(CartoucheResetPlan.isCartouches(appGroupKey: key), key)
        }
    }

    func testAppleLimitOnSignInsStaysWhileItCounts() throws {
        let now = Date(timeIntervalSince1970: 1_794_600_000)
        func data(until: TimeInterval, last: TimeInterval) throws -> Data {
            try JSONEncoder().encode(CartoucheSignInPause(until: now.addingTimeInterval(until), inARow: 2,
                                                          last: now.addingTimeInterval(last)))
        }
        // Holding: a sign-in now would make it last longer.
        XCTAssertTrue(CartoucheResetPlan.keepsSignInPause(try data(until: 600, last: -1_200), at: now))
        // Over, but it makes the next pause longer for a day.
        XCTAssertTrue(CartoucheResetPlan.keepsSignInPause(try data(until: -3_600, last: -5_400), at: now))
        // A day after it: nothing left of it.
        XCTAssertFalse(CartoucheResetPlan.keepsSignInPause(try data(until: -80_000, last: -86_401), at: now))
        XCTAssertFalse(CartoucheResetPlan.keepsSignInPause(Data("{".utf8), at: now))
        XCTAssertFalse(CartoucheResetPlan.keepsSignInPause(nil, at: now))
    }

    func testCartouchesKeysAreRemovedOneByOneTheOthersStay() throws {
        let domain = "io.github.clabeuhtegrite.cartouche.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        addTeardownBlock { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data([1, 2, 3]), forKey: "LCCertificateData")
        defaults.set("secret", forKey: "LCCertificatePassword")
        defaults.set(true, forKey: "CartoucheSignInRequested")
        defaults.set("x", forKey: "Cartouche.other")
        let keys = CartoucheResetPlan.cartouchesKeys(in: defaults, domain: domain)
        XCTAssertEqual(keys, ["Cartouche.other", "CartoucheSignInRequested"])
        CartoucheResetPlan.remove(keys, from: defaults)
        XCTAssertNil(defaults.object(forKey: "CartoucheSignInRequested"))
        XCTAssertNil(defaults.object(forKey: "Cartouche.other"))
        XCTAssertEqual(defaults.data(forKey: "LCCertificateData"), Data([1, 2, 3]))
        XCTAssertEqual(defaults.string(forKey: "LCCertificatePassword"), "secret")
    }

    func testWhatTheAppGroupLostOfLiveContainersComesBack() {
        let before: [String: Any] = ["LCCertificateData": Data([1, 2, 3]), "LCGuestURLSchemes": ["mkw"],
                                     "CartoucheSignInRequested": true, "LCMultiLaunchPriority": 2]
        let lost = CartoucheResetPlan.lostSharedPreferences(before: before, after: ["LCMultiLaunchPriority": 2])
        XCTAssertEqual(lost.keys.sorted(), ["LCCertificateData", "LCGuestURLSchemes"])
        XCTAssertEqual(lost["LCCertificateData"] as? Data, Data([1, 2, 3]))
        XCTAssertEqual(lost["LCGuestURLSchemes"] as? [String], ["mkw"])
        // Nothing lost, nothing to put back.
        XCTAssertTrue(CartoucheResetPlan.lostSharedPreferences(before: before, after: before).isEmpty)
        XCTAssertTrue(CartoucheResetPlan.lostSharedPreferences(before: [:], after: [:]).isEmpty)
    }

    func testSideStoresPreferencesAreFoundByTheirFiles() throws {
        let documents = try folder()
        XCTAssertEqual(CartoucheResetPlan.storePreferenceDomains(documents: documents), [])
        let preferences = CartoucheResetPlan.storePreferences(documents: documents)
        XCTAssertEqual(preferences.path, documents.appendingPathComponent("SideStore/Library/Preferences").path)
        let values: [String: Any] = ["hasCompletedOnboarding": true, "customAnisetteURL": "https://example.org"]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try data.write(to: preferences.appendingPathComponent("io.github.clabeuhtegrite.cartouche.plist"))
        try write("", at: "group.com.SideStore.SideStore.ABCDE12345.plist", in: preferences)
        try write("notes", at: "notes.txt", in: preferences)
        try write("", at: ".plist", in: preferences)
        XCTAssertEqual(CartoucheResetPlan.storePreferenceDomains(documents: documents),
                       ["group.com.SideStore.SideStore.ABCDE12345", "io.github.clabeuhtegrite.cartouche"])
        XCTAssertEqual(CartoucheResetPlan.keys(ofPreferences: preferences.appendingPathComponent("io.github.clabeuhtegrite.cartouche.plist")),
                       ["customAnisetteURL", "hasCompletedOnboarding"])
        // Not a property list, or none: no key.
        XCTAssertEqual(CartoucheResetPlan.keys(ofPreferences: preferences.appendingPathComponent("notes.txt")), [])
        XCTAssertEqual(CartoucheResetPlan.keys(ofPreferences: preferences.appendingPathComponent("none.plist")), [])
    }

    func testSideStoreKeepsTheProtocolItReadsThePairingFileBy() {
        let keys = ["activePairingProtocol", "customAnisetteURL", "firstLaunch", "isPairingReset", "preferredPairingProtocol"]
        // Before iOS 26.4, a Lockdown pairing file is read by the protocol
        // SideStore noted alone; the rest goes, firstLaunch among them.
        XCTAssertEqual(CartoucheResetPlan.erasedStorePreferences(keys, domain: "com.SideStore.SideStore"),
                       ["customAnisetteURL", "firstLaunch", "isPairingReset"])
        // In any other domain, everything goes.
        XCTAssertEqual(CartoucheResetPlan.erasedStorePreferences(keys, domain: "group.com.SideStore.SideStore"), keys)
        XCTAssertEqual(CartoucheResetPlan.erasedStorePreferences(keys, domain: "io.github.clabeuhtegrite.cartouche"), keys)
        XCTAssertEqual(CartoucheResetPlan.erasedStorePreferences([], domain: "com.SideStore.SideStore"), [])
    }

    // MARK: Files

    func testTheGamesDataFoldersAreFoundEachOne() throws {
        let documents = try folder()
        XCTAssertEqual(CartoucheResetPlan.gameDataFolders(documents: documents), [])
        try makeFolder("Data/Application/B2C1", in: documents)
        try makeFolder("Data/Application/A0F3", in: documents)
        try write("", at: "Data/Application/.DS_Store", in: documents)
        let elsewhere = try folder()
        try FileManager.default.createSymbolicLink(at: documents.appendingPathComponent("Data/Application/C4D5"),
                                                   withDestinationURL: elsewhere)
        XCTAssertEqual(CartoucheResetPlan.gameDataFolders(documents: documents), ["A0F3", "B2C1"])
    }

    func testThePlayersFoldersStayWhereverThePlayerPickedThem() throws {
        let home = try folder()
        try makeFolder("Documents/Applications", in: home)
        try makeFolder("Documents/SideStore", in: home)
        try makeFolder("Documents/Jeux", in: home)
        try write("ipa", at: "Documents/Kart.ipa", in: home)
        func kept(_ path: String) -> [String] {
            CartoucheResetPlan.keptPlayerItems(home.appendingPathComponent(path), home: home)
                .map { $0.path.replacingOccurrences(of: home.path + "/", with: "") }
        }
        // In Cartouche's own space in Files.
        XCTAssertEqual(kept("Documents/Jeux"), ["Documents/Jeux"])
        XCTAssertEqual(kept("Documents/Jeux/Saves"), ["Documents/Jeux/Saves"])
        // That space itself: what the player put there, but LiveContainer's
        // and SideStore's own folders.
        XCTAssertEqual(kept("Documents"), ["Documents/Jeux", "Documents/Kart.ipa"])
        // In LiveContainer's or SideStore's own folders: they go.
        XCTAssertEqual(kept("Documents/Applications"), [])
        XCTAssertEqual(kept("Documents/SideStore/Documents"), [])
        // No picker shows Library or tmp: a folder there stays, as the
        // harness's player folders do.
        XCTAssertEqual(kept("Library/HarnessStorage/Jeux"), ["Library/HarnessStorage/Jeux"])
        XCTAssertEqual(kept("Library"), [])
        XCTAssertEqual(kept("tmp"), [])
        // The home itself, or outside it, which the reset never touches.
        XCTAssertEqual(CartoucheResetPlan.keptPlayerItems(home, home: home), [])
        XCTAssertEqual(CartoucheResetPlan.keptPlayerItems(try folder(), home: home), [])
        XCTAssertEqual(kept(".com.apple.mobile_container_manager.metadata.plist"), [])
    }

    func testWhatStays() throws {
        let home = try folder()
        let appGroup = try folder()
        let kept = CartoucheResetPlan.kept(home: home, appGroup: appGroup,
                                           playerFolders: [home.appendingPathComponent("Documents/Jeux")],
                                           also: [home.appendingPathComponent("Library/Logs/console.txt")])
            .map { $0.path.replacingOccurrences(of: home.path + "/", with: "") }
        XCTAssertEqual(kept, [
            "Documents/SideStore/Documents/PairingFile_RemoteRP.plist",
            "Documents/SideStore/Documents/PairingFile_Lockdown.plist",
            "Documents/SideStore/Documents/ALTPairingFile.mobiledevicepairing",
            "Library/Preferences",
            "Documents/SideStore/Library/Preferences/com.SideStore.SideStore.plist",
            "Library/Application Support/Cartouche/Telemetry.json",
            "Documents/Jeux",
            "Library/Logs/console.txt",
        ])
        // An app group in the home stays, as with the player's own
        // certificate, which has none of iOS.
        let inHome = home.appendingPathComponent("Library/Application Support/CartoucheShared", isDirectory: true)
        XCTAssertTrue(CartoucheResetPlan.kept(home: home, appGroup: inHome, playerFolders: []).contains(inHome))
    }

    /// Cartouche's home and app group as on an iPhone, with a bit of
    /// everything: what the reset leaves.
    func testEverythingGoesButWhatStays() throws {
        let home = try folder()
        let appGroup = try folder()
        let outside = try folder()
        try write("player", at: "precious.txt", in: outside)
        let files = [
            // The games, their data folders and what LiveContainer keeps.
            "Documents/Applications/Kart.app/Info.plist",
            "Documents/Data/Application/A0F3/Documents/save/0000000001",
            "Documents/Data/Application/A0F3/Library/Preferences/org.nxnative.kart.plist",
            "Documents/Data/AppGroup/group.org.nxnative/x",
            "Documents/Tweaks/x",
            "Documents/Inbox/Kart.ipa",
            // SideStore's home: the pairing file stays, and the file of its
            // own preferences, whose keys go through cfprefsd; the rest goes.
            "Documents/SideStore/Documents/ALTPairingFile.mobiledevicepairing",
            "Documents/SideStore/Documents/Logs/log.txt",
            "Documents/SideStore/Library/Preferences/com.SideStore.SideStore.plist",
            "Documents/SideStore/Library/Preferences/io.github.clabeuhtegrite.cartouche.plist",
            "Documents/SideStore/Library/Caches/x",
            // The player's storage in Cartouche's own space, and a file of
            // theirs beside it.
            "Documents/Jeux/Kart.ipa",
            "Documents/Jeux/Saves/Kart/2026-11-13.zip",
            "Documents/stray.txt",
            // Cartouche's own files.
            "Library/Preferences/io.github.clabeuhtegrite.cartouche.plist",
            "Library/Application Support/Cartouche/Telemetry.json",
            "Library/Application Support/Cartouche/Journal.txt",
            "Library/Application Support/Cartouche/Reports.json",
            "Library/Application Support/Cartouche/GameInfo/x.json",
            "Library/Caches/Covers/x.jpg",
            "Library/SplashBoard/Snapshots/x",
            "tmp/CartoucheInstall/x",
            // What iOS keeps of the container, in the home itself.
            ".com.apple.mobile_container_manager.metadata.plist",
        ]
        for file in files { try write("x", at: file, in: home) }
        // The app group: SideStore's database and LiveContainer's own stay,
        // Cartouche's folder goes.
        try write("db", at: "Apps.sqlite", in: appGroup)
        try write("x", at: "LiveContainer/Applications/Other.app/Info.plist", in: appGroup)
        try write("x", at: "Cartouche/GameMemory.json", in: appGroup)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Documents/Outside"), withDestinationURL: outside)

        let kept = CartoucheResetPlan.kept(home: home, appGroup: appGroup,
                                           playerFolders: [home.appendingPathComponent("Documents/Jeux")])
        let failures = CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: kept)
        XCTAssertEqual(failures, [])
        XCTAssertEqual(tree(home), [
            ".com.apple.mobile_container_manager.metadata.plist",
            "Documents/",
            "Documents/Jeux/",
            "Documents/Jeux/Kart.ipa",
            "Documents/Jeux/Saves/",
            "Documents/Jeux/Saves/Kart/",
            "Documents/Jeux/Saves/Kart/2026-11-13.zip",
            "Documents/SideStore/",
            "Documents/SideStore/Documents/",
            "Documents/SideStore/Documents/ALTPairingFile.mobiledevicepairing",
            "Documents/SideStore/Library/",
            "Documents/SideStore/Library/Preferences/",
            "Documents/SideStore/Library/Preferences/com.SideStore.SideStore.plist",
            "Library/",
            "Library/Application Support/",
            "Library/Application Support/Cartouche/",
            "Library/Application Support/Cartouche/Telemetry.json",
            "Library/Preferences/",
            "Library/Preferences/io.github.clabeuhtegrite.cartouche.plist",
            "tmp/",
        ])
        XCTAssertEqual(tree(appGroup), ["Apps.sqlite", "LiveContainer/", "LiveContainer/Applications/",
                                        "LiveContainer/Applications/Other.app/", "LiveContainer/Applications/Other.app/Info.plist"])
        // The link went, never what it led to.
        XCTAssertEqual(tree(outside), ["precious.txt"])
        // Again, nothing left to erase.
        XCTAssertEqual(CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: kept), [])
        XCTAssertEqual(tree(home).count, 20)
    }

    /// The player picked Cartouche's own space in Files itself: what they
    /// put there stays, LiveContainer's and SideStore's own folders go.
    func testThePlayersFilesStayInCartouchesOwnSpace() throws {
        let home = try folder()
        for file in ["Documents/Applications/Kart.app/Info.plist", "Documents/Kart.ipa", "Documents/Saves/Kart/a.zip",
                     "Documents/SideStore/Library/x"] {
            try write("x", at: file, in: home)
        }
        let kept = CartoucheResetPlan.kept(home: home, appGroup: nil,
                                           playerFolders: [home.appendingPathComponent("Documents", isDirectory: true)])
        XCTAssertEqual(CartoucheResetPlan.eraseFiles(home: home, appGroup: nil, keeping: kept), [])
        XCTAssertEqual(tree(home), ["Documents/", "Documents/Kart.ipa", "Documents/Saves/", "Documents/Saves/Kart/",
                                    "Documents/Saves/Kart/a.zip", "Documents/SideStore/", "Documents/SideStore/Library/"])
    }

    /// An install with the player's own certificate keeps LiveContainer's
    /// shared folder in its home: it stays, but for Cartouche's own folder.
    func testAnAppGroupInTheHomeStaysButCartouchesFolder() throws {
        let home = try folder()
        let appGroup = home.appendingPathComponent("Library/Application Support/CartoucheShared", isDirectory: true)
        try write("x", at: "Library/Application Support/CartoucheShared/LiveContainer/Tweaks/x", in: home)
        try write("x", at: "Library/Application Support/CartoucheShared/Cartouche/GameMemory.json", in: home)
        try write("x", at: "Library/Application Support/Cartouche/Journal.txt", in: home)
        let kept = CartoucheResetPlan.kept(home: home, appGroup: appGroup, playerFolders: [])
        XCTAssertEqual(CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: kept), [])
        XCTAssertEqual(tree(home), ["Library/", "Library/Application Support/",
                                    "Library/Application Support/Cartouche/",
                                    "Library/Application Support/CartoucheShared/",
                                    "Library/Application Support/CartoucheShared/LiveContainer/",
                                    "Library/Application Support/CartoucheShared/LiveContainer/Tweaks/",
                                    "Library/Application Support/CartoucheShared/LiveContainer/Tweaks/x"])
    }

    /// A file manager that refuses to remove the files STUCK, and any
    /// folder that holds one, as a folder that does not go as a whole; and
    /// the folders KEPTBYIOS, once it removed what they hold, as iOS does
    /// with Documents/Inbox on an iPhone.
    private final class StubbornFileManager: FileManager {
        var stuck: Set<String> = []
        var keptByIOS: Set<String> = []

        private func refusal(_ url: URL) -> NSError {
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteNoPermission.rawValue,
                    userInfo: [NSFilePathErrorKey: url.path,
                               NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        }

        override func removeItem(at url: URL) throws {
            let path = url.standardizedFileURL.path
            if stuck.contains(path) || stuck.contains(where: { $0.hasPrefix(path + "/") }) {
                throw refusal(url)
            }
            if keptByIOS.contains(path) {
                for name in try contentsOfDirectory(atPath: path) {
                    try removeItem(at: url.appendingPathComponent(name))
                }
                throw refusal(url)
            }
            try super.removeItem(at: url)
        }
    }

    /// What cannot go says where, by its domain and code, and the rest goes:
    /// a folder that does not go as a whole goes item by item, down to what
    /// could not.
    func testWhatCannotGoComesBackAndTheRestGoes() throws {
        let home = try folder()
        let appGroup = try folder()
        try write("x", at: "Documents/Applications/Kart.app/Info.plist", in: home)
        try write("x", at: "Documents/Applications/Kart.app/Kart", in: home)
        try write("x", at: "Documents/Applications/Zelda.app/Info.plist", in: home)
        try write("x", at: "Documents/Data/Application/A0F3/x", in: home)
        try write("x", at: "Cartouche/x", in: appGroup)
        try write("x", at: "Cartouche/GameMemory.plist", in: appGroup)
        let fileManager = StubbornFileManager()
        fileManager.stuck = [home.appendingPathComponent("Documents/Applications/Kart.app/Info.plist").standardizedFileURL.path,
                             appGroup.appendingPathComponent("Cartouche/x").standardizedFileURL.path]
        let failures = CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: [], fileManager: fileManager)
        XCTAssertEqual(failures, [
            CartoucheResetPlan.Failure(path: "Documents/Applications/Kart.app/Info.plist", reason: "NSCocoaErrorDomain 513"),
            CartoucheResetPlan.Failure(path: "AppGroup/Cartouche/x", reason: "NSCocoaErrorDomain 513"),
        ])
        XCTAssertEqual(failures.map(\.description), ["Documents/Applications/Kart.app/Info.plist: NSCocoaErrorDomain 513",
                                                      "AppGroup/Cartouche/x: NSCocoaErrorDomain 513"])
        XCTAssertEqual(tree(home), ["Documents/", "Documents/Applications/", "Documents/Applications/Kart.app/",
                                    "Documents/Applications/Kart.app/Info.plist"])
        XCTAssertEqual(tree(appGroup), ["Cartouche/", "Cartouche/x"])
    }

    /// iOS keeps Documents/Inbox for itself, where it puts what another app
    /// opens Cartouche with, as a game's IPA from Files: the app may empty
    /// it, never remove it. Emptied, it is not an item left, and Cartouche
    /// starts again; as are other folders iOS would keep so.
    func testAFolderIOSKeepsForItselfIsEmptiedAndStays() throws {
        let home = try folder()
        let appGroup = try folder()
        try makeFolder("Documents/Inbox", in: home)
        try write("x", at: "Documents/Applications/Kart.app/Info.plist", in: home)
        try write("x", at: "tmp/io.github.clabeuhtegrite.cartouche-Inbox/Kart.ipa", in: home)
        try write("x", at: "Cartouche/GameMemory.plist", in: appGroup)
        let fileManager = StubbornFileManager()
        fileManager.keptByIOS = [home.appendingPathComponent("Documents/Inbox").standardizedFileURL.path,
                                 home.appendingPathComponent("tmp/io.github.clabeuhtegrite.cartouche-Inbox").standardizedFileURL.path]
        XCTAssertEqual(CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: [], fileManager: fileManager), [])
        XCTAssertEqual(tree(home), ["Documents/", "Documents/Inbox/", "tmp/", "tmp/io.github.clabeuhtegrite.cartouche-Inbox/"])
        XCTAssertEqual(tree(appGroup), [])

        // Not when something of the player's stays in it.
        try write("x", at: "Documents/Inbox/Kart.ipa", in: home)
        fileManager.stuck = [home.appendingPathComponent("Documents/Inbox/Kart.ipa").standardizedFileURL.path]
        XCTAssertEqual(CartoucheResetPlan.eraseFiles(home: home, appGroup: appGroup, keeping: [], fileManager: fileManager),
                       [CartoucheResetPlan.Failure(path: "Documents/Inbox/Kart.ipa", reason: "NSCocoaErrorDomain 513")])
    }

    /// The token that links this iPhone to a Cartouche Cloud account goes
    /// with the storage's items, every item of its service, and a failure
    /// to remove it says where by the place of its service, as the
    /// storage's does: never by its account, nor by the token.
    func testTheLinkToCartoucheCloudGoesAndIsMeasuredByItsPlace() {
        let erased = CartoucheResetPlan.erasedServices
        XCTAssertEqual(erased.map { $0.service }, [CartoucheResetPlan.storageService, CartoucheCloud.keychainService])
        XCTAssertEqual(erased.map { $0.place }, ["storage", "Cloud"])
        XCTAssertEqual(CartoucheResetPlan.measured([CartoucheResetPlan.Failure(path: "Keychain/Cloud", reason: "OSStatus -25308")]),
                       "Keychain/Cloud OSStatus -25308")
    }

    /// The telemetry says where what could not go lay, and why, by
    /// Cartouche's own folders and iOS's: never a file's name, nor the
    /// bundle ID an Inbox of iOS's is named after, which may hold the team's.
    func testWhatWasLeftIsMeasuredWithoutAFilesName() {
        func left(_ path: String, _ reason: String = "NSCocoaErrorDomain 513") -> CartoucheResetPlan.Failure {
            CartoucheResetPlan.Failure(path: path, reason: reason)
        }
        XCTAssertNil(CartoucheResetPlan.measured([]))
        XCTAssertEqual(CartoucheResetPlan.measured([left("Documents/Inbox")]), "Documents/Inbox NSCocoaErrorDomain 513")
        XCTAssertEqual(CartoucheResetPlan.measured([left("Documents/Mes notes de Zelda.txt"),
                                                    left("Documents/Applications/Kart.app/Info.plist")]),
                       "Documents/… NSCocoaErrorDomain 513; Documents/Applications/… NSCocoaErrorDomain 513")
        XCTAssertEqual(CartoucheResetPlan.measured([left("Library/Caches/com.apple.dyld"),
                                                    left("Library/com.apple.dyld", "NSCocoaErrorDomain 512")]),
                       "Library/Caches/… NSCocoaErrorDomain 513; Library/com.apple.dyld NSCocoaErrorDomain 512")
        XCTAssertEqual(CartoucheResetPlan.measured([left("tmp/io.github.clabeuhtegrite.cartouche.ABCDE12345-Inbox/Kart.ipa"),
                                                    left("Keychain/SideStore/appleIDPassword", "OSStatus -25308"),
                                                    left("AppGroup/Cartouche")]),
                       "tmp/…-Inbox/… NSCocoaErrorDomain 513; Keychain/SideStore/… OSStatus -25308; "
                       + "AppGroup/Cartouche NSCocoaErrorDomain 513")
        // Each place once, at most four, within what the telemetry's server
        // takes of a text.
        let many = (0..<9).map { left("Documents/Data/Application/\($0)/x") } + ["Inbox", "Tweaks", "SideStore", "Applications", "Data"]
            .map { left("Documents/" + $0) }
        let measured = CartoucheResetPlan.measured(many) ?? ""
        XCTAssertEqual(measured.components(separatedBy: "; ").count, 4)
        XCTAssertTrue(measured.hasPrefix("Documents/Data/… NSCocoaErrorDomain 513; Documents/Inbox"))
        XCTAssertLessThanOrEqual(measured.count, 160)
    }
}
