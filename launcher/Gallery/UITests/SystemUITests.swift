//
//  SystemUITests.swift
//  CartoucheGalleryUITests
//
//  The System page and every page it opens, each of which must come and go
//  with the console answering throughout; the builds of the player's Mac,
//  driven from there; the other apps installed, near its end, opened and
//  uninstalled from there; Reset Cartouche, at its end, which asks twice
//  before it erases; and Cartouche's own update, on offer over the console,
//  which Later puts off.
//

import XCTest

/// The words of the page of all the Mac's builds, from System (decision
/// 96).
extension Words {
    static let macBuildsOn = "Builds on %@"                 // mac.builds.title
    static let buildWhatIsDue = "Build what is due"         // mac.builds.due
    static let addWhatIsDue = "Add what is due"             // mac.builds.due.add
    static let stopAll = "Stop all"                         // mac.builds.stopAll
    static let macGameActions = "What to do with %@"        // mac.builds.game.actions
    static let follow = "Follow"                            // mac.build.follow
    static let stopFollowing = "Stop following"             // mac.build.unfollow
    static let macNotFollowed = "Not followed"              // mac.game.notFollowed
    static let nightly = "Build what is due every night"    // mac.builds.nightly
    static let nightlyAt = "Every night at "                // mac.builds.nightly.footer
    static let macTooOld = "The app on %@ no longer finds its updates by itself" // mac.builds.tooOld
    static let macToDownload = "To download again"         // mac.builds.toDownload
    static let macSendLink = "Send the link to %@"          // mac.builds.sendLink
}

/// The words of the automation of Shortcuts that renews Cartouche every
/// night, the setup's last step (decision 149).
extension Words {
    static let makeTheAutomation = "Make the automation"    // daily.action.make
    static let seeTheSteps = "See the steps"                // daily.action.see
    static let madeTheAutomation = "I made the automation"  // daily.made
    static let madeOn = "Made on "                          // daily.state.waiting
    static let setupStepDone = "%@, done"                   // setup.step.done
    static let hideNightlyReminder = "Hide this reminder"   // setup.banner.nightly.hide
}

/// The apps installed that are not nxnative games, near the end of the
/// System page (decision 154).
extension Words {
    static let openApp = "Open"                             // action.open
    static let uninstall = "Uninstall"                      // action.uninstall
}

/// Reset Cartouche's words (CartoucheTextReset.swift).
extension Words {
    static let resetCartouche = "Reset Cartouche"           // reset.title
    static let eraseAndRestart = "Erase everything and restart" // reset.erase
    static let eraseEverything = "Erase everything"         // reset.confirm.erase
    static let erasing = "Erasing…"                         // reset.erasing
}

final class SystemUITests: ConsoleTestCase {
    /// Setup, Storage, Renew every night, Game measurements and Report a
    /// problem each open from the System page, with what they are for, and
    /// come back to it; Done closes it.
    @MainActor
    func testEveryPageOfTheSystemPageOpensAndComesBack() {
        let app = openConsole()
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        // Each row, and what its page shows, if it is to be told apart by
        // more than its title.
        let pages: [(row: String, shows: String?)] = [
            (Words.setup, nil),
            (Words.storage, Words.storageIntro),
            (Words.renewEveryNight, Words.openShortcuts),
            (Words.telemetry, Words.sendMeasurements),
            (Words.report, nil),
        ]
        for page in pages {
            // In the page's list: the home under it, with a game installed,
            // has Renew every night too, as its banner (decision 159).
            let row = element(in: app.collectionViews.buttons, beginningWith: page.row)
            scrollTo(row, "\(page.row) on the System page", in: app)
            tap(row, "\(page.row) on the System page", in: app)
            expect(app.navigationBars[page.row].waitForExistence(timeout: 15), "\(page.row) did not open", in: app)
            // A list draws its rows only as they come on the screen: down
            // to it, once the page is there.
            if let shows = page.shows {
                let shown = element(beginningWith: shows, in: app)
                _ = shown.waitForExistence(timeout: 5)
                scrollTo(shown, "\(shows) on \(page.row)", in: app)
            }
            back(from: page.row, in: app)
            expect(app.navigationBars[Words.system].waitForExistence(timeout: 10),
                   "Back from \(page.row) did not come back to the System page", in: app)
        }
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// The setup's last step opens Renew every night, the automation of
    /// Shortcuts still to make: once the player says they made it, the page
    /// goes back up to say it waits for its first night, where the player
    /// sees it without scrolling, and the step is done, its button opening
    /// the steps again (decision 149). Up to 0.15.1, nothing in the setup
    /// said to make it, and nothing told whether it was made.
    @MainActor
    func testTheSetupsLastStepWaitsForTheAutomationOnceMade() {
        let app = openConsole()
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        let row = element(in: app.buttons, beginningWith: Words.setup)
        scrollTo(row, "Setup on the System page", in: app)
        tap(row, "Setup on the System page", in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 15), "Setup did not open", in: app)

        scrollAndTap(element(in: app.buttons, beginningWith: Words.makeTheAutomation),
                     "Make the automation, the setup's last step", in: app)
        expect(app.navigationBars[Words.renewEveryNight].waitForExistence(timeout: 15),
               "Make the automation did not open Renew every night", in: app)
        let made = element(in: app.buttons, beginningWith: Words.madeTheAutomation)
        scrollAndTap(made, "I made the automation", in: app)
        expect(element(beginningWith: Words.madeOn, in: app).waitForExistence(timeout: 10),
               "Once made, the page does not show at its top that it waits for the automation's first night", in: app)
        expect(waitForGone(made), "I made the automation is still offered once made", in: app)

        back(from: Words.renewEveryNight, in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 10),
               "Back from Renew every night did not come back to the setup", in: app)
        let done = String(format: Words.setupStepDone, Words.renewEveryNight)
        expect(element(labelled: done, in: app).waitForExistence(timeout: 10), "The setup does not say \(done)", in: app)
        scrollAndTap(element(in: app.buttons, beginningWith: Words.seeTheSteps), "See the steps, the last step done", in: app)
        expect(app.navigationBars[Words.renewEveryNight].waitForExistence(timeout: 15),
               "See the steps did not open Renew every night", in: app)
        back(from: Words.renewEveryNight, in: app)
        back(from: Words.setup, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// Once the first game is installed, the home's banner says Renew every
    /// night is left while the automation is still to make: a tap opens the
    /// setup on that step, and its × takes the banner off the home for good
    /// (decision 159). Up to 0.15.1, nothing on the home said it, and a
    /// player who left Cartouche closed for a week lost it.
    @MainActor
    func testWithAGameTheHomeSaysTheAutomationIsLeftUntilTakenOff() {
        let app = openConsole()
        let banner = element(in: app.buttons, beginningWith: Words.renewEveryNight)
        expect(banner.waitForExistence(timeout: 15), "The home does not say Renew every night is left", in: app)
        tap(banner, "Renew every night, on the home", in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 15),
               "Renew every night, on the home, did not open the setup", in: app)
        let make = element(in: app.buttons, beginningWith: Words.makeTheAutomation)
        expect(make.waitForExistence(timeout: 10) && waitUntil(5) { make.isHittable },
               "The setup did not open on its last step, Make the automation out of sight", in: app)
        tap(app.navigationBars[Words.setup].buttons[Words.done], "Done of the setup", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)

        tap(app.buttons[Words.hideNightlyReminder], "the × of Renew every night, on the home", in: app)
        expect(waitForGone(banner), "Renew every night stayed on the home once taken off", in: app)
        expectMainThreadAnswered(app)
    }

    /// Reset Cartouche, at the end of the System page, asks twice before it
    /// erases anything: its button, then its confirmation, which, cancelled,
    /// leaves everything as it was: by its Cancel, or, on an iPhone from
    /// iOS 26, which shows it in a popover without one, by a tap outside it.
    /// Erase everything covers the page while Cartouche erases, then
    /// restarts: the gallery's reset only shows it, and comes back to the
    /// page (CartoucheReset.swift).
    @MainActor
    func testResetCartoucheAsksTwiceBeforeItErases() {
        let app = openConsole()
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        scrollAndTap(element(in: app.buttons, beginningWith: Words.resetCartouche), "Reset Cartouche on the System page", in: app)
        expect(app.navigationBars[Words.resetCartouche].waitForExistence(timeout: 15), "Reset Cartouche did not open", in: app)
        let erase = element(in: app.buttons, beginningWith: Words.eraseAndRestart)
        let erasing = element(labelled: Words.erasing, in: app)
        // Once, then cancelled: nothing happens.
        scrollAndTap(erase, "Erase everything and restart", in: app)
        cancelConfirmation("The confirmation", in: app)
        expect(!erasing.waitForExistence(timeout: 3), "The confirmation, cancelled, erased all the same", in: app)
        // Then Erase everything.
        scrollAndTap(erase, "Erase everything and restart, again", in: app)
        tapButtonOnTop(Words.eraseEverything, "Erase everything, in the confirmation", in: app)
        expect(erasing.waitForExistence(timeout: 10), "Erase everything did not cover the page while Cartouche erases", in: app)
        expect(waitForGone(erasing, timeout: 15), "The gallery's reset did not end", in: app)
        back(from: Words.resetCartouche, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// The apps installed that are not nxnative games are near the end of
    /// the System page, under Other installed apps (decision 154): Open
    /// closes the page and starts the app, as Play starts a game; Uninstall
    /// asks first, then closes the page and uninstalls it, which the page
    /// then no longer lists. Up to 0.15.1, Cartouche said they were in
    /// Apps, LiveContainer's tab, which it never shows: nothing opened them.
    @MainActor
    func testAnotherInstalledAppOpensAndUninstallsFromTheSystemPage() {
        let app = openConsole(Launch(work: "other-apps"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        // Pocket Notes, the first by name (GalleryScenario.otherApps).
        let open = app.buttons[Words.openApp].firstMatch
        scrollTo(open, "Open, under Other installed apps", in: app)
        expect(element(labelled: "Pocket Notes", in: app).exists, "Pocket Notes is not under Other installed apps", in: app)
        tap(open, "Open of Pocket Notes", in: app)
        expectPlay(of: "Pocket Notes", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Open did not leave the console on the screen", in: app)

        tap(app.buttons[Words.system], "System in the dock, again", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open again", in: app)
        let uninstall = app.buttons[Words.uninstall].firstMatch
        // Once, then cancelled: nothing happens.
        scrollAndTap(uninstall, "Uninstall of Pocket Notes", in: app)
        cancelConfirmation("The question before Pocket Notes is uninstalled", in: app)
        expect(!app.alerts[GalleryWords.uninstall].waitForExistence(timeout: 3),
               "The question, cancelled, uninstalled Pocket Notes all the same", in: app)
        // Then Uninstall.
        scrollAndTap(uninstall, "Uninstall of Pocket Notes, again", in: app)
        tapButtonOnTop(Words.uninstall, "Uninstall, in the question", in: app)
        let alert = app.alerts[GalleryWords.uninstall]
        expect(alert.waitForExistence(timeout: 15), "Pocket Notes was not uninstalled", in: app)
        expect(alert.staticTexts["Uninstall 1: Pocket Notes"].exists,
               "The uninstall was not Pocket Notes': \(alert.debugDescription)", in: app)
        tap(alert.buttons[Words.done], "Done of the uninstall", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The uninstall did not leave the console on the screen", in: app)

        // Sky Radar alone is left.
        tap(app.buttons[Words.system], "System in the dock, once more", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open once more", in: app)
        scrollTo(element(labelled: "Sky Radar", in: app), "Sky Radar, under Other installed apps", in: app)
        expect(!element(labelled: "Pocket Notes", in: app).exists, "Pocket Notes is still listed once uninstalled", in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// The builds of the player's Mac, from the System page, while Cartouche
    /// Builder builds a game and another waits its turn: what is due joins
    /// the queue, Stop all stops every game, a game the Mac does not follow
    /// is followed then left again from its menu, and the nightly build is
    /// turned off; back on the System page, Done closes it.
    @MainActor
    func testTheMacsBuildsAreDrivenFromTheSystemPage() {
        let app = openConsole(Launch(work: "mac-builds"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        // The Mac paired in Storage, by its name (GalleryMac.paired).
        let row = element(in: app.buttons, beginningWith: String(format: Words.macBuildsOn, "MacBook Air"))
        scrollTo(row, "the Mac's builds on the System page", in: app)
        tap(row, "the Mac's builds on the System page", in: app)
        expect(app.navigationBars[Words.macBuildsPage].waitForExistence(timeout: 15), "The Mac's builds did not open", in: app)

        // Pikmin 4, which nxnative improved, after the game waiting.
        let list = app.collectionViews.descendants(matching: .any)
        tap(app.buttons[Words.addWhatIsDue], "Add what is due", in: app)
        scrollTo(element(in: list, beginningWith: "2. Pikmin 4"), "the game due, second in the queue", in: app)

        // Every game of the batch stops: nothing waits, and what is due can
        // be built again.
        scrollAndTap(app.buttons[Words.stopAll], "Stop all", in: app)
        expect(waitForGone(element(in: list, beginningWith: "1. ")), "A game still waits its turn once all stopped", in: app)
        expect(app.buttons[Words.buildWhatIsDue].waitForExistence(timeout: 10), "No Build what is due once all stopped", in: app)

        // Super Mario Odyssey, which the Mac does not follow: followed, then
        // not again.
        let menu = app.buttons[String(format: Words.macGameActions, "Super Mario Odyssey")]
        scrollAndTap(menu, "the menu of the game the Mac does not follow", in: app)
        tap(app.buttons[Words.follow], "Follow, in the game's menu", in: app)
        expect(waitForGone(element(in: list, beginningWith: Words.macNotFollowed)), "The game followed still says it is not", in: app)
        scrollAndTap(menu, "the menu of the game followed", in: app)
        tap(app.buttons[Words.stopFollowing], "Stop following, in the game's menu", in: app)
        expect(element(in: list, beginningWith: Words.macNotFollowed).waitForExistence(timeout: 10),
               "The game left does not say it is not followed", in: app)

        // The nightly build, on at 3:30: off, its time no longer said.
        let nightly = app.switches[Words.nightly].firstMatch
        scrollTo(nightly, "the nightly build", in: app)
        expect((nightly.value as? String) == "1", "The nightly build is not on", in: app)
        expect(element(beginningWith: Words.nightlyAt, in: app).exists, "The nightly build does not say when", in: app)
        // The switch itself, at the row's end: a tap on its words does not
        // turn it.
        nightly.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expect(waitUntil(10) { (nightly.value as? String) == "0" }, "The nightly build did not turn off", in: app)
        expect(waitForGone(element(beginningWith: Words.nightlyAt, in: app)), "The nightly build off still says when", in: app)

        back(from: Words.macBuildsPage, in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 10),
               "Back from the Mac's builds did not come back to the System page", in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// The builds of a Mac whose app is 0.5.0 or older, too old to share
    /// them, and which no longer finds its updates by itself: the page says
    /// to download the app again, and offers to send the Mac its link
    /// (decision 118); back on the System page, Done closes it.
    @MainActor
    func testAMacWhoseAppNoLongerUpdatesItselfIsSentItsLink() {
        let app = openConsole(Launch(work: "mac-too-old"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        let row = element(in: app.buttons, beginningWith: String(format: Words.macBuildsOn, "MacBook Air"))
        scrollTo(row, "the Mac's builds on the System page", in: app)
        tap(row, "the Mac's builds on the System page", in: app)
        expect(app.navigationBars[Words.macBuildsPage].waitForExistence(timeout: 15), "The Mac's builds did not open", in: app)

        expect(element(beginningWith: Words.macToDownload, in: app).waitForExistence(timeout: 10),
               "The Mac does not say its app is to download again", in: app)
        expect(element(beginningWith: String(format: Words.macTooOld, "MacBook Air"), in: app).exists,
               "The page does not say why the Mac's app is to download again", in: app)
        expect(app.buttons[String(format: Words.macSendLink, "MacBook Air")].exists,
               "No way to send the Mac the link to its app", in: app)

        back(from: Words.macBuildsPage, in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 10),
               "Back from the Mac's builds did not come back to the System page", in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// A newer Cartouche on offer shows over the console, with Update and
    /// Later; Later puts it off, and the console answers again.
    @MainActor
    func testANewVersionOnOfferIsPutOffByLater() {
        let app = launchGallery(Launch(work: "update"))
        // The gallery's version is 0.3.0 (project.yml), the one on offer
        // 0.4.0 (GalleryApp.swift).
        let offer = element(labelled: String(format: Words.updateOffer, "0.4.0"), in: app)
        expect(offer.waitForExistence(timeout: Self.firstLaunch), "No update on offer over the console", in: app)
        expect(app.buttons[Words.update].exists, "The update on offer has no Update", in: app)
        tap(app.buttons[Words.later], "Later, on the update on offer", in: app)
        expect(waitForGone(offer), "Later did not put the update off", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the update was put off", in: app)
        expectMainThreadAnswered(app)
    }
}
