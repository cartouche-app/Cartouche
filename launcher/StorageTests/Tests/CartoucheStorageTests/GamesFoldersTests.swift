//
//  GamesFoldersTests.swift
//  CartoucheStorageTests
//
//  The player's games folders, several at once (CartoucheStorageSettings,
//  CartoucheGameCopies.swift): another one added is read too, after the
//  games folder, never the same twice; stop using the games folder and the
//  next takes its place; a server removed takes its folders with it, here
//  or on the paired Mac, and one the Mac replaced moves them to the new
//  one; choosing another games folder takes it from the others; the paired
//  Mac is told them all, the games folder first, those it can reach. The
//  rule for the order and for the copy offered is tested on its own
//  (launcher/Tests, CartoucheGameCopiesTests). It needs no server, so it
//  always runs.
//

import Foundation
import XCTest
@testable import CartoucheStorage

final class GamesFoldersTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites {
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// Settings of their own, in preferences the test removes.
    private func settings() -> CartoucheStorageSettings {
        let suite = "GamesFoldersTests." + UUID().uuidString
        suites.append(suite)
        return CartoucheStorageSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    private let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "192.168.1.2", username: "joueur", share: "Jeux")
    private let drive = CartoucheStorageServer(kind: .drive, name: "Google Drive", username: "joueur")
    private let s3 = CartoucheStorageServer(kind: .s3, name: "S3", host: "s3.example", username: "cle", share: "cartouche")

    private func servers(in settings: CartoucheStorageSettings) {
        for server in [nas, drive, s3] { settings.save(server, secret: "secret") }
    }

    private func place(_ server: CartoucheStorageServer, _ path: String = "Jeux") -> CartoucheStoragePlace {
        CartoucheStoragePlace(server: server.id, path: path)
    }

    func testAnotherFolderIsReadAfterTheGamesFolderNeverTwice() {
        let settings = settings()
        servers(in: settings)
        settings.addGamesFolder(place(nas))
        XCTAssertEqual(settings.places[.games], place(nas), "the first one added is the games folder")
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(s3, "jeux"))
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(nas))
        XCTAssertEqual(settings.places[.games], place(nas))
        XCTAssertEqual(settings.otherGames, [place(drive), place(s3, "jeux")])
        XCTAssertEqual(settings.gamesLocations.map(\.server.id), [nas.id, drive.id, s3.id])
        XCTAssertEqual(settings.gamesLocations.map(\.path), ["Jeux", "Jeux", "jeux"])
    }

    func testStoppingTheGamesFolderGivesItsPlaceToTheNext() {
        let settings = settings()
        servers(in: settings)
        settings.addGamesFolder(place(nas))
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(s3))
        let before = settings.chosen[.games]
        settings.removeGamesFolder(place(s3))
        XCTAssertEqual(settings.gamesFolders.all, [place(nas), place(drive)])
        settings.removeGamesFolder(place(nas))
        XCTAssertEqual(settings.places[.games], place(drive), "the next is the folder games are copied to")
        XCTAssertEqual(settings.otherGames, [])
        XCTAssertNotNil(settings.chosen[.games])
        XCTAssertNotEqual(settings.chosen[.games], before, "chosen anew, for the paired Mac")
        settings.removeGamesFolder(place(drive))
        XCTAssertNil(settings.places[.games])
        XCTAssertTrue(settings.gamesLocations.isEmpty)
    }

    func testChoosingAnotherGamesFolderTakesItFromTheOthers() {
        let settings = settings()
        servers(in: settings)
        settings.addGamesFolder(place(nas))
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(s3))
        settings.setPlace(place(s3), for: .games)
        XCTAssertEqual(settings.gamesFolders.all, [place(s3), place(drive)], "the NAS's folder changed for the S3's")
        settings.setPlace(nil, for: .games)
        XCTAssertTrue(settings.gamesFolders.all.isEmpty, "none: no games folder at all")
    }

    func testARemovedServerTakesItsFoldersWithIt() {
        let settings = settings()
        servers(in: settings)
        settings.addGamesFolder(place(nas))
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(nas, "Autres"))
        settings.addGamesFolder(place(s3))
        settings.setPlace(place(nas, "Sauvegardes"), for: .saves)
        settings.remove(nas)
        XCTAssertEqual(settings.gamesFolders.all, [place(drive), place(s3)])
        XCTAssertNil(settings.places[.saves])
    }

    /// The paired Mac replaced the NAS by another of the same place, and
    /// removed the S3 bucket.
    func testWhatThePairedMacReplacedOrRemovedMovesTheFolders() {
        let settings = settings()
        servers(in: settings)
        settings.addGamesFolder(place(drive))
        settings.addGamesFolder(place(nas))
        settings.addGamesFolder(place(s3))
        let later = Date().addingTimeInterval(60)
        let newNAS = CartoucheConnection(id: UUID(), kind: "smb", name: "NAS", host: "192.168.1.3", username: "joueur",
                                         share: "Jeux", secret: "secret", changed: later)
        var oldNAS = nas.connection(secret: "secret")
        oldNAS.removed = true
        oldNAS.changed = later
        oldNAS.replacedBy = newNAS.id
        var goneS3 = s3.connection(secret: "secret")
        goneS3.removed = true
        goneS3.changed = later
        XCTAssertTrue(settings.take([newNAS, oldNAS, goneS3]))
        XCTAssertEqual(settings.gamesFolders.all, [place(drive), CartoucheStoragePlace(server: newNAS.id, path: "Jeux")])
    }

    func testThePairedMacIsToldThemAllWithTheGamesFolder() {
        let settings = settings()
        servers(in: settings)
        let picked = CartoucheStorageServer(kind: .folder, name: "Jeux")
        settings.save(picked, secret: nil)
        settings.addGamesFolder(place(nas))
        settings.addGamesFolder(place(picked, ""))
        settings.addGamesFolder(place(drive))
        let told = settings.chosenFolders()
        XCTAssertEqual(told.games?.connection, nas.id)
        XCTAssertEqual(told.otherGames?.map(\.connection), [drive.id], "a folder picked here goes to no Mac")
        XCTAssertEqual(told.otherGames?.map(\.path), ["Jeux"])
        XCTAssertEqual(told.otherGames?.first?.chosen, told.games?.chosen, "chosen with the games folder")
        // Another one added: chosen again, for the Mac to take.
        let before = told.games?.chosen ?? .distantPast
        settings.addGamesFolder(place(s3))
        XCTAssertGreaterThan(settings.chosenFolders().games?.chosen ?? .distantPast, before)
        XCTAssertEqual(settings.chosenFolders().otherGames?.map(\.connection), [drive.id, s3.id])
    }
}
