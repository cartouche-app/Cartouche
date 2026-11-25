//
//  OwnCertificateUITests.swift
//  CartoucheGalleryUITests
//
//  Cartouche signed with the player's own certificate
//  (docs/imported-signing.md). Signed on the iPhone by a signing app: the
//  guide's first step is the certificate, whose import asks for the
//  certificate and its password, never a profile; the setup says what the
//  signature lacks; a new version is one to download, never to install from
//  Cartouche. Signed by the Cartouche Installer: a new version is one to
//  install from the Installer. The IPA for an Apple ID, signed by a signing
//  app without its app group, which cannot sign in: the guide and the setup
//  offer the IPA for the player's own certificate in the place of the
//  Apple ID.
//

import XCTest

/// The words of these tests, as enum Words has the others
/// (ConsoleTestCase.swift): each is the English of the key beside it, or
/// its beginning, which app/tests/test_launcher_ui_tests.py checks.
extension Words {
    static let importCertificate = "Import signing certificate" // signing.title
    static let certificateStep = "Import your certificate"  // guide.certificate.title
    static let howOnIPhone = "Choose the certificate (.p12) your signing app signed Cartouche with" // signing.howOnIPhone
    static let chooseCertificate = "Choose the certificate (.p12)" // signing.chooseCertificate
    static let chooseProfile = "Choose its profile (.mobileprovision)" // signing.chooseProfile
    static let certificatePassword = "Certificate password" // signing.password
    static let useCertificate = "Use this certificate"      // signing.use
    static let signature = "Your signature"                 // signature.check.title
    static let memoryLeftOut = "Your signing app left out Increased Memory Limit" // signature.memory.leftOut
    static let keychainsLeftOut = "Your signing app did not sign in the games’ keychain groups" // signature.keychains.leftOut
    static let download = "Download"                        // updates.download
    static let offerOnIPhone = "You have version %@. Download the new one" // updates.offer.onIPhone
    static let offerOnComputer = "You have version %@. Install the new one from the Cartouche Installer" // updates.offer.onComputer
    static let signedElsewhereStep = "Sign the IPA for your own certificate" // signing.elsewhere.title
    static let signedElsewhere = "A signing app signed the IPA of Cartouche made for an Apple ID" // signing.elsewhere
    static let signedElsewhereSideStore = "The IPA of Cartouche made for SideStore was installed without the app group" // signing.elsewhere.sideStore
    static let downloadVersion = "Download Cartouche %@"    // system.updates.download
    static let profileFile = "This file is a profile (.mobileprovision), not the certificate" // signing.profileFile
    static let wrongPasswordOnIPhone = "This password does not open this certificate. Type the one that came with the .p12, which your signing app asked for too" // signing.wrongPasswordOnIPhone
    static let ownProfileUnreadable = "Cartouche cannot read the profile your signing app signed it with" // signing.ownProfileUnreadable
}

final class OwnCertificateUITests: ConsoleTestCase {
    /// The guide opens by itself with the certificate's step open, in the
    /// place of LocalDevVPN's and the Apple ID's; its import asks for the
    /// certificate and its password alone; the card on the home says that
    /// step, the first of four.
    @MainActor
    func testSignedOnTheIPhoneTheGuideAsksForTheCertificateAlone() {
        let app = launchGallery(Launch(setupDone: false, owned: [], signing: "iphone"))
        let guide = app.navigationBars[Words.guide]
        expect(guide.waitForExistence(timeout: Self.firstLaunch), "The guide did not open by itself on the first launch", in: app)
        expect(app.buttons[Words.importCertificate].waitForExistence(timeout: 10),
               "The guide's first step, the certificate, is not open", in: app)
        expect(element(beginningWith: Words.howOnIPhone, in: app).exists,
               "The certificate's step does not ask for the certificate the signing app used", in: app)
        for step in [Words.certificateStep, Words.buildStep, Words.folderStep, Words.playStep] {
            expect(element(labelled: step, in: app).exists, "The guide shows no step \(step)", in: app)
        }
        for step in [Words.vpnStep, Words.accountStep] {
            expect(!element(labelled: step, in: app).exists, "The guide shows \(step), which only an Apple ID needs", in: app)
        }

        tap(app.buttons[Words.importCertificate], "Import signing certificate, in the guide", in: app)
        expect(app.navigationBars[Words.importCertificate].waitForExistence(timeout: 15),
               "Import signing certificate did not open", in: app)
        expect(app.buttons[Words.chooseCertificate].exists, "No button to choose the certificate", in: app)
        expect(!app.buttons[Words.chooseProfile].exists, "Signed on the iPhone, Cartouche asks for a profile", in: app)
        expect(app.secureTextFields[Words.certificatePassword].exists, "No field for the certificate's password", in: app)
        expect(!app.buttons[Words.useCertificate].isEnabled, "Use this certificate works without a certificate", in: app)
        back(from: Words.importCertificate, in: app)
        expect(guide.waitForExistence(timeout: 10), "Back from the import did not come back to the guide", in: app)

        tap(guide.buttons[Words.done], "Done of the guide", in: app)
        expect(waitForGone(guide), "Done did not close the guide", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the guide closed", in: app)
        let card = element(in: app.buttons, containing: Words.guide)
        expect(card.waitForExistence(timeout: 10), "No guide's card on the home", in: app)
        let step = String(format: Words.guideCard, 1, 4, Words.certificateStep)
        expect(card.label.contains(step), "The guide's card does not say \(step): \(card.label)", in: app)
        expectMainThreadAnswered(app)
    }

    /// The setup, from the System page, has the certificate's step without
    /// the Apple ID's, and says what the signature lacks: Increased Memory
    /// Limit, which the signing app left out, and the games' keychain
    /// groups.
    @MainActor
    func testSignedOnTheIPhoneTheSetupSaysWhatTheSignatureLacks() {
        let app = openConsole(Launch(setupDone: false, work: "iml-left-out", signing: "iphone"))
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        let row = element(in: app.buttons, beginningWith: Words.setup)
        scrollTo(row, "Setup on the System page", in: app)
        tap(row, "Setup on the System page", in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 15), "Setup did not open", in: app)
        expect(app.buttons[Words.importCertificate].waitForExistence(timeout: 10), "The setup has no import of the certificate",
               in: app)
        expect(!app.buttons[Words.signIn].exists, "Signed with the player's own certificate, the setup asks for an Apple ID", in: app)
        for words in [Words.signature, Words.memoryLeftOut, Words.keychainsLeftOut] {
            let shown = element(beginningWith: words, in: app)
            _ = shown.waitForExistence(timeout: 5)
            scrollTo(shown, "\(words) in the setup", in: app)
        }
        back(from: Words.setup, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// A certificate the setup refused says why, in words of its own, on the
    /// guide's step: a profile chosen in the certificate's place; a
    /// password that does not open the .p12; a Cartouche its signing app
    /// put no profile in, which no file chosen here makes up for. Up to
    /// 0.13.1, the first two said "This certificate does not open. Check
    /// its password, and that the .p12 holds its private key", and the
    /// third that the profile, which the player does not choose, was
    /// invalid.
    @MainActor
    func testSignedOnTheIPhoneACertificateRefusedSaysWhy() {
        for (work, words) in [("signing-profile-file", Words.profileFile),
                              ("signing-wrong-password", Words.wrongPasswordOnIPhone),
                              ("signing-no-own-profile", Words.ownProfileUnreadable)] {
            let app = launchGallery(Launch(setupDone: false, owned: [], work: work, signing: "iphone"))
            expect(app.navigationBars[Words.guide].waitForExistence(timeout: Self.firstLaunch),
                   "The guide did not open by itself (\(work))", in: app)
            expect(element(beginningWith: words, in: app).waitForExistence(timeout: 15),
                   "The guide's certificate step does not say \(words) (\(work))", in: app)
            expectMainThreadAnswered(app)
        }
    }

    /// A newer Cartouche on offer, signed on the iPhone: its IPA to
    /// download, which the signing app signs, or Later, which puts it off.
    @MainActor
    func testSignedOnTheIPhoneANewVersionIsOneToDownload() {
        let app = launchGallery(Launch(work: "update", signing: "iphone"))
        // The gallery's version is 0.3.0 (project.yml), the one on offer
        // 0.4.0 (GalleryApp.swift).
        let offer = element(labelled: String(format: Words.updateOffer, "0.4.0"), in: app)
        expect(offer.waitForExistence(timeout: Self.firstLaunch), "No update on offer over the console", in: app)
        expect(element(beginningWith: String(format: Words.offerOnIPhone, "0.3.0"), in: app).exists,
               "The update on offer does not say to download it and sign it", in: app)
        expect(app.buttons[Words.download].exists, "The update on offer has no Download", in: app)
        tap(app.buttons[Words.later], "Later, on the update on offer", in: app)
        expect(waitForGone(offer), "Later did not put the update off", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the update was put off", in: app)
        expectMainThreadAnswered(app)
    }

    /// The IPA for an Apple ID that a signing app signed without its app
    /// group, which cannot sign in: the guide opens by itself on the step
    /// that offers the IPA for the player's own certificate, of this
    /// version, in the place of LocalDevVPN's and the Apple ID's, and the
    /// home's card says that step; the setup, from the System page, offers
    /// the same IPA and asks for neither an Apple ID nor a certificate.
    @MainActor
    func testSignedElsewhereTheGuideAndTheSetupOfferTheIPAForTheOwnCertificate() {
        let app = launchGallery(Launch(setupDone: false, owned: [], work: "signed-elsewhere"))
        let guide = app.navigationBars[Words.guide]
        expect(guide.waitForExistence(timeout: Self.firstLaunch), "The guide did not open by itself on the first launch", in: app)
        // The gallery's version is 0.3.0 (project.yml).
        let download = String(format: Words.downloadVersion, "0.3.0")
        expect(app.buttons[download].waitForExistence(timeout: 10),
               "The guide's first step does not offer the IPA for the player's own certificate", in: app)
        expect(element(beginningWith: Words.signedElsewhere, in: app).exists,
               "The guide's first step does not say why the Apple ID cannot sign in", in: app)
        for step in [Words.signedElsewhereStep, Words.buildStep, Words.folderStep, Words.playStep] {
            expect(element(labelled: step, in: app).exists, "The guide shows no step \(step)", in: app)
        }
        for step in [Words.vpnStep, Words.accountStep, Words.certificateStep] {
            expect(!element(labelled: step, in: app).exists, "The guide shows \(step), which this IPA cannot take", in: app)
        }

        tap(guide.buttons[Words.done], "Done of the guide", in: app)
        expect(waitForGone(guide), "Done did not close the guide", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the guide closed", in: app)
        let card = element(in: app.buttons, containing: Words.guide)
        expect(card.waitForExistence(timeout: 10), "No guide's card on the home", in: app)
        let step = String(format: Words.guideCard, 1, 4, Words.signedElsewhereStep)
        expect(card.label.contains(step), "The guide's card does not say \(step): \(card.label)", in: app)

        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        let row = element(in: app.buttons, beginningWith: Words.setup)
        scrollTo(row, "Setup on the System page", in: app)
        tap(row, "Setup on the System page", in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 15), "Setup did not open", in: app)
        expect(app.buttons[download].waitForExistence(timeout: 10),
               "The setup does not offer the IPA for the player's own certificate", in: app)
        expect(!app.buttons[Words.signIn].exists, "The setup asks for an Apple ID this IPA cannot sign in with", in: app)
        expect(!app.buttons[Words.importCertificate].exists, "The setup asks for a certificate this IPA cannot use", in: app)
        back(from: Words.setup, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// The IPA for the player's own SideStore, installed without its app
    /// group, as both copies of 0.16.0 installed from it were on 25
    /// November 2026: it cannot sign in either, and its setup asked for the
    /// Apple ID all the same. The guide and the setup offer the IPA for the
    /// player's own certificate, in words of the IPA for SideStore, and ask
    /// for no Apple ID.
    @MainActor
    func testTheIPAForSideStoreWithoutItsAppGroupOffersTheIPAForTheOwnCertificate() {
        var launch = Launch(setupDone: false, owned: [], work: "signed-elsewhere")
        launch.signing = "sidestore"
        let app = launchGallery(launch)
        let guide = app.navigationBars[Words.guide]
        expect(guide.waitForExistence(timeout: Self.firstLaunch), "The guide did not open by itself on the first launch", in: app)
        // The gallery's version is 0.3.0 (project.yml).
        let download = String(format: Words.downloadVersion, "0.3.0")
        expect(app.buttons[download].waitForExistence(timeout: 10),
               "The guide's first step does not offer the IPA for the player's own certificate", in: app)
        expect(element(beginningWith: Words.signedElsewhereSideStore, in: app).exists,
               "The guide's first step does not say why the IPA for SideStore cannot sign in", in: app)
        expect(!element(beginningWith: Words.signedElsewhere, in: app).exists,
               "The guide speaks of the IPA for an Apple ID to the IPA for SideStore", in: app)
        for step in [Words.vpnStep, Words.accountStep, Words.certificateStep] {
            expect(!element(labelled: step, in: app).exists, "The guide shows \(step), which this IPA cannot take", in: app)
        }

        tap(guide.buttons[Words.done], "Done of the guide", in: app)
        expect(waitForGone(guide), "Done did not close the guide", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the guide closed", in: app)
        tap(app.buttons[Words.system], "System in the dock", in: app)
        expect(app.navigationBars[Words.system].waitForExistence(timeout: 15), "The System page did not open", in: app)
        let row = element(in: app.buttons, beginningWith: Words.setup)
        scrollTo(row, "Setup on the System page", in: app)
        tap(row, "Setup on the System page", in: app)
        expect(app.navigationBars[Words.setup].waitForExistence(timeout: 15), "Setup did not open", in: app)
        expect(app.buttons[download].waitForExistence(timeout: 10),
               "The setup does not offer the IPA for the player's own certificate", in: app)
        expect(!app.buttons[Words.signIn].exists, "The setup asks for an Apple ID this IPA cannot sign in with", in: app)
        back(from: Words.setup, in: app)
        tap(app.buttons[Words.done], "Done of the System page", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "Done did not bring the console back", in: app)
        expectMainThreadAnswered(app)
    }

    /// A newer Cartouche on offer, signed by the Cartouche Installer: the
    /// Installer on the computer installs it, and Done puts it off.
    @MainActor
    func testSignedByTheInstallerANewVersionIsOneForTheInstaller() {
        let app = launchGallery(Launch(work: "update", signing: "installer"))
        let offer = element(labelled: String(format: Words.updateOffer, "0.4.0"), in: app)
        expect(offer.waitForExistence(timeout: Self.firstLaunch), "No update on offer over the console", in: app)
        expect(element(beginningWith: String(format: Words.offerOnComputer, "0.3.0"), in: app).exists,
               "The update on offer does not send to the Cartouche Installer", in: app)
        expect(!app.buttons[Words.download].exists, "The Installer's install offers a download", in: app)
        tapButtonOnTop(Words.done, "Done, on the update on offer", in: app)
        expect(waitForGone(offer), "Done did not put the update off", in: app)
        expect(waitUntil(10) { isOnConsole(app) }, "The console did not come back once the update was put off", in: app)
        expectMainThreadAnswered(app)
    }
}
