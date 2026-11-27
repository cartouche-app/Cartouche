//
//  StorageUITests.swift
//  CartoucheGalleryUITests
//
//  The Storage page, from the System page: every kind of place it adds,
//  each form opening and closing; the player's NAS out of reach away from
//  home, which the page says without an error, with the saves waiting for
//  it and Try again; the player's Google Drive once Google ended its
//  sign-in, as after 7 days for a project in testing, which the page says
//  without an error, with Sign in to Google again in place of Try again;
//  the player's Mac, paired, as the games folder; and Add your Mac, with
//  the Macs nearby, the digits to check on both screens, and iOS refusing
//  the local network; how to name the games, from the page; and the home's
//  offer of a saves folder once the first game is over, which opens the
//  page (decision 178). The
//  gallery stands in for the servers, Google and the Macs
//  (GalleryApp.swift): nothing here reaches a real one, but the NAS's Try
//  again, which knocks on its address, as the app does, and finds no one.
//

import XCTest

/// The words of how to name the games (CartoucheTextNaming.swift).
extension Words {
    static let namingOpen = "How to name your games"        // naming.open
    static let namingTitle = "Naming your games"            // naming.title
}

/// The words of the home's offer of a saves folder (CartoucheText.swift).
extension Words {
    static let savesOfferTitle = "Keep your saves safe"     // home.savesOffer.title
    static let hideSavesOffer = "Hide this suggestion"      // home.savesOffer.hide
}

final class StorageUITests: ConsoleTestCase {
    /// With no place yet, the page says to add one first and offers each
    /// kind, whose forms open and close: S3, Google Drive, FTP, and a folder
    /// in Files, with the Files picker.
    @MainActor
    func testTheStoragePageOffersEveryKindOfPlace() {
        let app = openConsole()
        openStorage(in: app)
        expect(element(beginningWith: Words.addFirst, in: app).waitForExistence(timeout: 10),
               "The Storage page does not say to add a place first", in: app)
        for form in [Words.addS3, Words.addDrive, Words.addFTP] {
            let row = app.buttons[form]
            scrollTo(row, "\(form) on the Storage page", in: app)
            tap(row, "\(form) on the Storage page", in: app)
            let bar = app.navigationBars[form]
            expect(bar.waitForExistence(timeout: 15), "\(form) did not open its form", in: app)
            tap(bar.buttons[Words.cancel], "Cancel of \(form)", in: app)
            expect(waitForGone(bar), "Cancel did not close \(form)", in: app)
        }
        expect(app.buttons[Words.addMac].exists, "The Storage page does not offer \(Words.addMac)", in: app)

        let folder = app.buttons[Words.addFolder]
        scrollTo(folder, "\(Words.addFolder) on the Storage page", in: app)
        tap(folder, "\(Words.addFolder) on the Storage page", in: app)
        let picker = FilesPicker(app: app, test: self)
        expect(picker.waitForIt(), "\(Words.addFolder) did not show the Files picker", in: app)
        picker.close()
        expect(picker.waitForItToGo(), "The Files picker of \(Words.addFolder) did not close", in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 10),
               "The Storage page did not come back once the Files picker closed", in: app)
        closeStorage(in: app)
        expectMainThreadAnswered(app)
    }

    /// The player's NAS, out of reach away from home: the System page says
    /// it is offline; the Storage page says it does not answer, without an
    /// error, with the games it listed and two games' saves waiting for it;
    /// Try again knocks on it, finds no one, and says so the same way.
    @MainActor
    func testANASOutOfReachSaysSoAndTriesAgainWithoutAnError() {
        let app = openConsole(Launch(work: "offline"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        let row = element(in: app.buttons, beginningWith: Words.storage)
        expect(row.waitForExistence(timeout: 15), "No Storage on the System page", in: app)
        let offlineShort = String(format: Words.offlineShort, "NAS")
        expect(row.label.contains(offlineShort) || (row.value as? String)?.contains(offlineShort) == true,
               "The System page does not say \(offlineShort): \(row.label)", in: app)
        tap(row, "Storage on the System page", in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 15), "The Storage page did not open", in: app)

        let offline = String(format: Words.offline, "NAS")
        expect(element(beginningWith: offline, in: app).waitForExistence(timeout: 10),
               "The Storage page does not say \(offline)", in: app)
        let waiting = String(format: Words.savesWaiting, 2)
        let saves = element(beginningWith: waiting, in: app)
        scrollTo(saves, "\(waiting) on the Storage page", in: app)
        let tryAgain = app.buttons[Words.tryAgain]
        scrollTo(tryAgain, "Try again for the saves", in: app)
        tap(tryAgain, "Try again for the saves", in: app)
        // The knock gives up within six seconds, and Try again comes back.
        Thread.sleep(forTimeInterval: 6)
        expect(waitUntil(15) { app.buttons[Words.tryAgain].exists && app.buttons[Words.tryAgain].isEnabled },
               "Try again did not come back once the NAS did not answer", in: app)
        expect(element(beginningWith: offline, in: app).exists, "The Storage page no longer says \(offline)", in: app)
        expect(app.alerts.count == 0, "Trying the NAS again showed an error: \(app.alerts.firstMatch.debugDescription)",
               in: app)
        closeStorage(in: app)
        expectMainThreadAnswered(app)
    }

    /// The player's Google Drive, once Google ended its sign-in, as it does
    /// after 7 days for a project in testing: the System page says to sign
    /// in again; the Storage page says why, without an error, with two
    /// games' saves waiting for it, and offers Sign in to Google again,
    /// never Try again, which would knock on Google for nothing.
    @MainActor
    func testADriveWhoseSignInEndedOffersToSignInAgainWithoutAnError() {
        let app = openConsole(Launch(work: "drive-signed-out"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        let row = element(in: app.buttons, beginningWith: Words.storage)
        expect(row.waitForExistence(timeout: 15), "No Storage on the System page", in: app)
        let signedOutShort = String(format: Words.driveSignedOutShort, "Google Drive")
        expect(row.label.contains(signedOutShort) || (row.value as? String)?.contains(signedOutShort) == true,
               "The System page does not say \(signedOutShort): \(row.label)", in: app)
        tap(row, "Storage on the System page", in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 15), "The Storage page did not open", in: app)

        let signedOut = String(format: Words.driveSignedOut, "Google Drive")
        expect(element(beginningWith: signedOut, in: app).waitForExistence(timeout: 10),
               "The Storage page does not say \(signedOut)", in: app)
        // Sign in to Google again, on the games folder's lines, above the
        // saves folder's.
        let again = app.buttons[Words.driveSignInAgain]
        scrollTo(again, "\(Words.driveSignInAgain) on the Storage page", in: app)
        expect(again.isEnabled, "\(Words.driveSignInAgain) is not enabled", in: app)
        let waiting = String(format: Words.savesWaiting, 2)
        let saves = element(beginningWith: waiting, in: app)
        scrollTo(saves, "\(waiting) on the Storage page", in: app)
        expect(!app.buttons[Words.tryAgain].exists,
               "The Storage page offers \(Words.tryAgain) for a Drive whose sign-in ended", in: app)
        expect(app.alerts.count == 0,
               "The Drive whose sign-in ended showed an error: \(app.alerts.firstMatch.debugDescription)", in: app)
        closeStorage(in: app)
        expectMainThreadAnswered(app)
    }

    /// The player's Mac, paired: the System page says the games folder is
    /// on it, and the Storage page lists it among the places, with nothing
    /// left to add first.
    @MainActor
    func testTheMacPairedHoldsTheGames() {
        let app = openConsole(Launch(work: "mac"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        let row = element(in: app.buttons, beginningWith: Words.storage)
        expect(row.waitForExistence(timeout: 15), "No Storage on the System page", in: app)
        expect(row.label.contains("MacBook Air") || (row.value as? String)?.contains("MacBook Air") == true,
               "The System page does not say the games folder is on the Mac: \(row.label)", in: app)
        tap(row, "Storage on the System page", in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 15), "The Storage page did not open", in: app)
        let place = element(in: app.buttons, beginningWith: "MacBook Air")
        scrollTo(place, "the Mac among the places", in: app)
        expect(!element(beginningWith: Words.addFirst, in: app).exists, "The Storage page says to add a place first", in: app)
        closeStorage(in: app)
        expectMainThreadAnswered(app)
    }

    /// Add your Mac lists the Macs whose Cartouche Builder shares with
    /// Cartouche, on this network.
    @MainActor
    func testAddYourMacListsTheMacsNearby() {
        let app = openAddYourMac(Launch(work: "mac-nearby"))
        for mac in ["MacBook Air", "Mac mini"] {
            expect(element(in: app.buttons, beginningWith: mac).waitForExistence(timeout: 15),
                   "Add your Mac does not list \(mac)", in: app)
        }
        closeAddYourMac(in: app)
        expectMainThreadAnswered(app)
    }

    /// Plugged into a Mac by a cable, Add your Mac lists it with no Wi-Fi to
    /// find it on, and says it is by cable.
    @MainActor
    func testAddYourMacListsTheMacPluggedInByCable() {
        let app = openAddYourMac(Launch(work: "mac-cable"))
        let plugged = element(in: app.buttons, beginningWith: "MacBook Air")
        expect(plugged.waitForExistence(timeout: 15), "Add your Mac does not list the Mac plugged in", in: app)
        // The row reads as one button, its label joining its lines.
        expect(plugged.label.contains(Words.byCable) || element(beginningWith: Words.byCable, in: app).exists,
               "Add your Mac does not say it is by cable", in: app)
        expect(element(in: app.buttons, beginningWith: "Mac mini").exists, "Add your Mac does not list the Mac on the Wi-Fi",
               in: app)
        closeAddYourMac(in: app)
        expectMainThreadAnswered(app)
    }

    /// Pairing with a Mac, Add your Mac shows the six digits the Mac shows
    /// too, to check on both screens.
    @MainActor
    func testAddYourMacShowsTheDigitsToCheck() {
        let app = openAddYourMac(Launch(work: "mac-code"))
        // Read out one by one.
        expect(element(labelled: "4 8 2 9 1 5", in: app).waitForExistence(timeout: 15), "Add your Mac shows no digits",
               in: app)
        expect(element(beginningWith: Words.checkDigits, in: app).exists, "Add your Mac does not say to check the digits",
               in: app)
        closeAddYourMac(in: app)
        expectMainThreadAnswered(app)
    }

    /// iOS refusing Cartouche the local network, Add your Mac says where to
    /// allow it, and looks for no Mac.
    @MainActor
    func testAddYourMacWithoutTheLocalNetwork() {
        let app = openAddYourMac(Launch(work: "mac-refused"))
        expect(element(beginningWith: Words.noLocalNetwork, in: app).waitForExistence(timeout: 15),
               "Add your Mac does not say iOS refuses the local network", in: app)
        closeAddYourMac(in: app)
        expectMainThreadAnswered(app)
    }

    /// How to name the games opens from the Storage page, no folder chosen
    /// yet: the games folder's examples, the saves folder's, then the
    /// dumps Cartouche Builder reads on a Mac, each found or left aside;
    /// Back brings the page again.
    @MainActor
    func testHowToNameTheGamesShowsEachFoldersExamples() {
        let app = openConsole()
        openStorage(in: app)
        let row = app.buttons[Words.namingOpen]
        scrollTo(row, "\(Words.namingOpen) on the Storage page", in: app)
        tap(row, "\(Words.namingOpen) on the Storage page", in: app)
        expect(app.navigationBars[Words.namingTitle].waitForExistence(timeout: 15),
               "\(Words.namingOpen) did not open \(Words.namingTitle)", in: app)
        // Down the page, in its order (CartoucheNamingView.swift).
        for example in ["naming.games.namedIPA", "naming.games.tooDeep", "naming.saves.copy", "naming.dumps.package",
                        "naming.dumps.built"] {
            scrollTo(app.descendants(matching: .any)[example], "The example \(example) of \(Words.namingTitle)", in: app)
        }
        back(from: Words.namingTitle, in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 10),
               "Back from \(Words.namingTitle) did not bring the Storage page", in: app)
        closeStorage(in: app)
        expectMainThreadAnswered(app)
    }

    // MARK: Steps

    /// Once the first game is over, the saves on this iPhone alone, the
    /// home offers a saves folder: a tap opens the Storage page over the
    /// console, where the player chooses one as from System; Done brings the
    /// console back, the offer still there while no folder is chosen; its ×
    /// takes it off the home for good. Up to 0.16.2, nothing offered one:
    /// 57 of the 135 copies that had a game on November 26 had no saves
    /// folder.
    @MainActor
    func testTheHomeOffersASavesFolderOnceTheFirstGameIsOver() {
        let app = openConsole(Launch(work: "saves-offer"))
        let banner = element(in: app.buttons, beginningWith: Words.savesOfferTitle)
        expect(banner.waitForExistence(timeout: 15), "The home does not offer a saves folder", in: app)
        tap(banner, "the offer of a saves folder, on the home", in: app)
        let bar = app.navigationBars[Words.storage]
        expect(bar.waitForExistence(timeout: 15), "The offer of a saves folder did not open the Storage page", in: app)
        expect(element(beginningWith: Words.addFirst, in: app).waitForExistence(timeout: 10),
               "The Storage page from the offer does not say to add a place first", in: app)
        tap(bar.buttons[Words.done], "Done of the Storage page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expect(banner.waitForExistence(timeout: 10), "The offer went with no saves folder chosen", in: app)

        tap(app.buttons[Words.hideSavesOffer], "the × of the offer of a saves folder", in: app)
        expect(waitForGone(banner), "The offer of a saves folder stayed on the home once taken off", in: app)
        expectMainThreadAnswered(app)
    }

    /// System, then Storage.
    @MainActor
    private func openStorage(in app: XCUIApplication) {
        tap(app.buttons[Words.system], "System in the dock", in: app)
        tap(element(in: app.buttons, beginningWith: Words.storage), "Storage on the System page", in: app)
        expect(app.navigationBars[Words.storage].waitForExistence(timeout: 15), "The Storage page did not open", in: app)
    }

    /// Back to the System page, then Done: the console.
    @MainActor
    private func closeStorage(in app: XCUIApplication) {
        back(from: Words.storage, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
    }

    /// The gallery opened as LAUNCH says, then the Storage page's Add your
    /// Mac.
    @MainActor
    private func openAddYourMac(_ launch: Launch) -> XCUIApplication {
        let app = openConsole(launch)
        openStorage(in: app)
        let add = app.buttons[Words.addMac]
        scrollTo(add, "\(Words.addMac) on the Storage page", in: app)
        tap(add, "\(Words.addMac) on the Storage page", in: app)
        expect(app.navigationBars[Words.yourMac].waitForExistence(timeout: 15), "Add your Mac did not open", in: app)
        return app
    }

    /// Cancel of Add your Mac, then back to the console.
    @MainActor
    private func closeAddYourMac(in app: XCUIApplication) {
        let bar = app.navigationBars[Words.yourMac]
        tap(bar.buttons[Words.cancel], "Cancel of Add your Mac", in: app)
        expect(waitForGone(bar), "Cancel did not close Add your Mac", in: app)
        closeStorage(in: app)
    }
}
