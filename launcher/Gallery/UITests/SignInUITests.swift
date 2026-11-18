//
//  SignInUITests.swift
//  CartoucheGalleryUITests
//
//  The Apple ID sign-in, from the System page's setup, with the built-in
//  SideStore stood in for (GallerySideStore in GalleryTesting.swift): it
//  reads the Apple ID and password Cartouche leaves in their keychain, and
//  answers by the Apple ID. "code" in it: Apple asks for a verification code,
//  123456; "limit": Apple refuses more sign-ins for now, with its page of
//  HTTP 429; "nogroup": SideStore finds no app group for its database;
//  "othercert": the Apple ID already has a certificate SideStore does not
//  hold; "noliveprocess": LiveProcess, which SideStore runs in, is missing
//  from the app; "provisioning-refused", "session-expired" and
//  "cannot-complete": Apple's answers that SideStore passes on in English
//  (GalleryAppleAnswer).
//

import XCTest

extension Words {
    static let noLiveProcess = "This copy of Cartouche is missing the part of the app the built-in SideStore runs in" // app.noLiveProcess
    static let provisioningRefused = "Apple is refusing, for now, to set up a new sign-in on this iPhone" // signIn.provisioningRefused
    static let sessionExpired = "Apple says this iPhone’s sign-in has expired" // signIn.sessionExpired
    static let cannotComplete = "Apple refused this sign-in without saying why" // signIn.cannotComplete
}

final class SignInUITests: ConsoleTestCase {
    /// A wrong code gets a new request that says so; the right one signs the
    /// player in, and the setup shows the Apple ID.
    @MainActor
    func testSignInWithAVerificationCode() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "code@example.com")

        type("111111", inCodeOf: app)
        expect(app.staticTexts[GalleryWords.wrongCode].waitForExistence(timeout: 20),
               "No new request saying the code was wrong", in: app)
        type("123456", inCodeOf: app)

        let signedIn = element(in: app.staticTexts, beginningWith: Words.signedIn)
        expect(signedIn.waitForExistence(timeout: 30), "The setup does not say the Apple ID is signed in", in: app)
        expect(signedIn.label == Words.signedIn + GalleryWords.signedInAs, "The setup says \(signedIn.label)", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "The sign-in stayed open once signed in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// Apple refusing more sign-ins for now: Cartouche says so in its own
    /// words, counts the wait down in Sign In's place, and its report can be
    /// copied.
    @MainActor
    func testSignInRefusedForTooManyRequests() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "limit@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        let everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.tooManyRequests).exists,
               "The failure does not say Apple refuses more sign-ins for now", in: app)
        expect(!element(in: everything, containing: "<html").exists, "Apple's page shows as it came", in: app)
        let wait = element(in: app.buttons, beginningWith: Words.tryAgainIn)
        expect(wait.exists, "No countdown in Sign In's place", in: app)
        expect(!wait.isEnabled, "The countdown can be tapped: \(wait.label)", in: app)

        tap(app.buttons[Words.copyReport], "Copy the report", in: app)
        expect(app.buttons[Words.reportCopied].waitForExistence(timeout: 5), "The report does not say it is copied", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// The built-in SideStore finding no app group for its database, as when
    /// a signing app signed the IPA for an Apple ID: the failure says why
    /// signing in cannot work there, as the setup says it of that IPA, in
    /// the place of SideStore's words, and offers the IPA for the player's
    /// own certificate of this version.
    @MainActor
    func testSignInWithoutTheAppGroupOffersTheIPAForTheOwnCertificate() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "nogroup@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        let everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.signedElsewhere).exists,
               "The failure does not say why signing in cannot work with this IPA", in: app)
        expect(!element(in: everything, containing: "App Group Container").exists, "SideStore's words show as they came", in: app)
        // The gallery's version is 0.3.0 (project.yml).
        expect(app.buttons[String(format: Words.downloadVersion, "0.3.0")].exists,
               "The failure does not offer the IPA for the player's own certificate", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        // The sign-in stopped before anything went to Apple: its password
        // stayed in its field (CartoucheSignInMessage.keepsPassword), which
        // iOS offers to save as the sign-in closes.
        turnDownSavingThePassword(in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// The Apple ID already having a certificate the built-in SideStore does
    /// not hold, made by another app or computer: the failure says what to
    /// do in Cartouche's words, in the place of SideStore's, which are in
    /// English and end with the certificates' serial numbers.
    @MainActor
    func testSignInRefusedForACertificateMadeElsewhereSaysWhatToDo() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "othercert@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        let everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.otherCertificate).exists,
               "The failure does not say what to do about the Apple ID's certificate", in: app)
        expect(!element(in: everything, containing: "This SideStore never revokes").exists, "SideStore's words show as they came", in: app)
        expect(!element(in: everything, containing: "Certificate named by the app").exists, "The serial numbers show", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// LiveProcess, which the built-in SideStore runs in, missing from the
    /// app: LiveContainer's bridge cannot start SideStore, and up to 0.13.1
    /// its words showed, in English, sending the player to the settings of
    /// other sideloaders. The failure says, in Cartouche's words, to install
    /// it again over itself with the Cartouche Installer.
    @MainActor
    func testSignInWithoutLiveProcessSaysToInstallAgain() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "noliveprocess@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        let everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.noLiveProcess).exists,
               "The failure does not say to install Cartouche again", in: app)
        expect(!element(in: everything, containing: "Unable to locate LiveProcess bundle").exists,
               "LiveContainer's words show as they came", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// Apple refusing, for now, a new machine for the sign-in, before the
    /// Apple ID went to it (app/patches/sidestore/0024): up to 0.14.0,
    /// AnisetteKit's English words showed, naming one of Apple's endpoints.
    /// Cartouche says so in its own words and counts the wait down in Sign
    /// In's place, as for Apple's limit.
    @MainActor
    func testSignInWhoseNewMachineAppleRefusedSaysToWait() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "provisioning-refused@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        let everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.provisioningRefused).exists,
               "The failure does not say Apple refuses a new sign-in on this iPhone for now", in: app)
        expect(!element(in: everything, containing: "endpoint returned").exists, "AnisetteKit's words show as they came", in: app)
        let wait = element(in: app.buttons, beginningWith: Words.tryAgainIn)
        expect(wait.exists, "No countdown in Sign In's place", in: app)
        expect(!wait.isEnabled, "The countdown can be tapped: \(wait.label)", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    /// Apple saying the sign-in's session has expired, then refusing a
    /// sign-in without saying why: up to 0.14.0, Apple's English words
    /// showed, with its code. Cartouche says what to do in its own words,
    /// and the player can sign in again at once.
    @MainActor
    func testApplesRefusalsInEnglishSayWhatToDo() {
        let app = openConsole(Launch(setupDone: false, pairingOnly: true, typing: true))
        openSignIn(in: app)
        signIn(in: app, appleID: "session-expired@example.com")

        expect(app.staticTexts[Words.signInFailed].waitForExistence(timeout: 30), "No failure of the sign-in", in: app)
        var everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.sessionExpired).exists,
               "The failure does not say Apple's sign-in has expired", in: app)
        expect(!element(in: everything, containing: "Please log in").exists, "Apple's words show as they came", in: app)
        expect(!element(in: app.buttons, beginningWith: Words.tryAgainIn).exists, "A countdown keeps the player from signing in again", in: app)

        replaceText(in: app.textFields[Words.appleID], with: "cannot-complete@example.com", "the Apple ID field", in: app)
        type("not-a-password\n", into: app.secureTextFields[Words.password], "the password field", in: app)
        everything = app.descendants(matching: .any)
        expect(element(in: everything, beginningWith: Words.cannotComplete).waitForExistence(timeout: 30),
               "The failure does not say Apple refused the sign-in without a reason", in: app)
        expect(!element(in: everything, containing: "This Action Cannot Be Completed").exists, "Apple's words show as they came", in: app)
        expect(!element(in: everything, beginningWith: Words.sessionExpired).exists, "The first failure stayed", in: app)

        tap(app.buttons[Words.cancel], "Cancel of the sign-in", in: app)
        expect(waitForGone(app.staticTexts[Words.signInTitle]), "Cancel did not close the sign-in", in: app)
        closeSetup(in: app)
        expectMainThreadAnswered(app)
    }

    // MARK: Steps

    /// System, Setup, then Sign In: the sign-in's screen.
    @MainActor
    private func openSignIn(in app: XCUIApplication) {
        tap(app.buttons[Words.system], "System in the dock", in: app)
        tap(element(in: app.buttons, beginningWith: Words.setup), "Setup on the System page", in: app)
        tap(app.buttons[Words.signIn].firstMatch, "Sign In of the setup's Apple ID step", in: app)
        expect(app.staticTexts[Words.signInTitle].waitForExistence(timeout: 15), "The sign-in did not open", in: app)
    }

    /// Types the Apple ID and the password, then Go.
    @MainActor
    private func signIn(in app: XCUIApplication, appleID: String) {
        type(appleID, into: app.textFields[Words.appleID], "the Apple ID field", in: app)
        type("not-a-password\n", into: app.secureTextFields[Words.password], "the password field", in: app)
    }

    /// Types CODE in the field of Apple's request, which sends it at the
    /// sixth digit.
    @MainActor
    private func type(_ code: String, inCodeOf app: XCUIApplication) {
        type(code, into: app.textFields[Words.code], "the field of the verification code", in: app, timeout: 30)
    }

    /// Not Now on iOS's offer to save the password typed in the sign-in, as
    /// a player turns it down, should iOS make it: it shows over the setup,
    /// which nothing can be tapped behind.
    @MainActor
    private func turnDownSavingThePassword(in app: XCUIApplication) {
        let notNow = app.sheets.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 10) else { return }
        tap(notNow, "Not Now on iOS's offer to save the password", in: app)
        expect(waitForGone(notNow), "iOS's offer to save the password stayed", in: app)
    }

    /// From the setup, back to the System page, then Done: the console.
    @MainActor
    private func closeSetup(in app: XCUIApplication) {
        tap(app.navigationBars.buttons.firstMatch, "Back from the setup", in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
    }
}
