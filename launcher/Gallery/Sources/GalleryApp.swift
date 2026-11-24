//
//  GalleryApp.swift
//  CartoucheGallery
//
//  Shows one scenario of scenarios.json, which capture.sh passes as launch
//  arguments: a launcher screen at the scenario's size, in the top left
//  corner of the screen, with that iPhone's safe area; or, without a size,
//  the whole screen of the simulator it runs on, such as the iPhone Duo's,
//  with its own safe area, size classes and system bars.
//
//  Each value of -GalleryScreen, -GalleryWork and -GalleryCategory is on a
//  line of its own, in the order of their names, which a pull request that
//  adds one adds at its place; the gallery's own types for a new scenario go
//  in a file of their own in Sources/. Pull requests that each add one then
//  do not meet, as they did in one line or at the end of this file.
//
//      -GalleryScreen <screen>           the screen, one of these, the home
//                                        when none:
//        cloud                           Cartouche Cloud, as System opens
//                                        it: for an iPhone not linked yet,
//                                        or with a work cloud-* below
//                                        (GalleryCloud)
//        gameinfo                        what the player says of the sheet's
//                                        game
//        gamelog                         the log of the sheet's game, with
//                                        -GalleryWork log
//        gamelog-sent                    what Send to Cartouche sends of that
//                                        log, cleaned
//        games                           the home
//        guide                           Your first game
//        library                         every game, open over the home
//        mac-builds                      all the Mac's builds, as System
//                                        opens them (work: mac-builds, or
//                                        mac-too-old)
//        nightly                         Renew every night, its steps, from
//                                        the System page
//        release-notes                   the System page's What's new, the
//                                        notes of the last versions the
//                                        gallery carries
//        report                          Report a problem
//        reset                           Reset Cartouche's page, as the
//                                        System page opens it
//        reset-end                       the same, at its end, on its button
//        settings                        the settings of the sheet's game,
//                                        open at -GalleryCategory
//        setup                           the setup
//        sheet                           the sheet of -GallerySheet's game
//        sheet-mac                       the sheet, scrolled to the game's
//                                        build on the player's Mac (work:
//                                        mac-builds, or mac-too-old)
//        sheet-saves                     the sheet, further down, at its
//                                        saves
//        shortcuts                       Siri and Home Screen, from the
//                                        sheet of the player's game
//        signin                          the Apple ID sign-in
//        signing                         the import of the player's own
//                                        certificate
//        storage                         the Storage page
//        storage-drive                   Add Google Drive, with the player's
//                                        own client
//        storage-drive-guide             the steps that make that client
//        storage-mac                     Add your Mac, the form that pairs
//                                        this iPhone with a Mac nearby
//        storage-names                   How to name your games, as the
//                                        Storage page opens it, at its top
//                                        or down to -GalleryCategory
//        storage-smb                     Add a shared folder, with a NAS
//                                        nearby (GallerySMB)
//        switch-save                     the saves of the sheet's game
//                                        between the Switch and this iPhone,
//                                        with -GalleryWork saves the save
//                                        JKSV exported, read
//        system                          the System page, down to
//                                        -GalleryCategory
//        telemetry                       Game measurements
//        tv                              the TV while the sheet's game, or
//                                        the first of the player's, runs
//                                        behind the console, its card where
//                                        the game leaves its own scene on
//                                        the TV empty (CartoucheTV.swift)
//      -GallerySigning <signing>         Cartouche signed with the player's
//                                        own certificate, one of these (none:
//                                        with the player's Apple ID):
//        installer                       by the Cartouche Installer, with
//                                        every entitlement
//        iphone                          by a signing app on the iPhone,
//                                        which kept the profile's keychain
//                                        pattern as it is
//                                        (GalleryScenario.ownSignature)
//        sidestore                       the IPA for the player's own
//                                        SideStore, which signed it with
//                                        the player's Apple ID and left
//                                        Increased Memory Limit out
//                                        (CartoucheSideStoreInstall)
//      -GalleryWidth 402 -GalleryHeight 874     (none: the whole screen)
//      -GalleryInsets 62,0,34,0          top, leading, bottom, trailing
//      -GalleryWidthClass compact        the width class at a scenario's
//                                        size, where iOS gives another one
//                                        than its width says: an iPhone 17
//                                        Pro sideways is compact
//      -GalleryOwned 0400C3F00006E000,…  the player's games; TITLEID:Name
//                                        for one nxnative.json does not
//                                        have, which IGDB has by its name
//                                        when the catalogue has a game of
//                                        that name (showFound)
//      -GallerySetup 1 -GalleryController 1
//      -GalleryModel iPad15,3            the device of catalog/devices.json
//                                        the screen is drawn as, whose words
//                                        call an iPad the iPad (none: the
//                                        iPhone, iPhone19,4, CartoucheDevice)
//      -GallerySheet <title ID>          the game of the sheet, of its
//                                        settings, or being installed
//      -GalleryWork <work>               what goes on, one of these:
//        build-skipped                   No thanks said to the guide's Mac
//                                        step
//        cannot-complete                 a sign-in Apple refused without
//                                        saying why, before any code,
//                                        LocalDevVPN connected
//                                        (GalleryAppleAnswer)
//        certificate                     a certificate iOS no longer accepts
//        cloud-games                     this iPhone linked to a Cartouche
//                                        Cloud account, a game of it built,
//                                        one being built, one waiting for it
//                                        and one not built, as the page of
//                                        Cartouche Cloud, System, the
//                                        library and the built game's sheet
//                                        show them (GalleryCloud)
//        cloud-installing                the same, its game built being
//                                        installed from Cartouche Cloud,
//                                        over the console
//        cloud-linking                   on Cartouche Cloud (screen cloud),
//                                        the code of the account's page
//                                        linking this iPhone, as the page's
//                                        link opened Cartouche with it
//        cloud-refused                   the same code, which the service
//                                        refused
//        code                            Apple asks for a verification code,
//                                        on the sign-in
//        confirm                         on Reset Cartouche's page, its
//                                        confirmation, at the page's end,
//                                        from its button
//        device-handshake                a sign-in that stopped at the check
//                                        of this iPhone, LocalDevVPN
//                                        connected: a pairing file this
//                                        iPhone refused (deviceChecks)
//        device-no-ipsec                 the same: a Lockdown pairing file
//                                        from iOS 26.4
//        device-port-closed              the same: minimuxer could not reach
//                                        this iPhone on its port
//        drive-signed-out                the player's Google Drive as the
//                                        games folder and the saves folder,
//                                        whose sign-in Google ended, as after
//                                        7 days for a project in testing,
//                                        with two games' saves waiting for it
//        erasing                         on Reset Cartouche's page, the reset
//                                        under way
//        games-folders                   two games folders, a NAS's, out of
//                                        reach away from home, and a Google
//                                        Drive's, the player's games in
//                                        both, the sheet's game newer on the
//                                        NAS (GalleryGamesFolders)
//        game-mode-later                 Game Mode coming 1.5 s after
//                                        Cartouche first measures its
//                                        memory: its own limit 6,144 MiB
//                                        until then, 8,192 after, as on an
//                                        iPhone with 12 GB
//                                        (GalleryState.ownLimitMiB)
//        gpu-no-bc                       an iPhone whose GPU reads no
//                                        BC-compressed texture, an A16's,
//                                        the sheet's game built by nxnative,
//                                        which refuses it
//                                        (GalleryBCConversion)
//        gpu-no-bc-converted             the same, the sheet's game built by
//                                        a fork of nxnative that converts
//                                        those textures for it, a game drawn
//                                        with NVN's, as on 18 November
//        gpu-no-bc-converted-vulkan      the same, built by that fork as
//                                        since 22 November, which converts
//                                        a Vulkan game's too
//        iml-left-out                    signed by a signing app on the
//                                        iPhone (-GallerySigning iphone),
//                                        without Increased Memory Limit,
//                                        which the profile allows
//        iml-not-in-profile              the same, with a profile that allows
//                                        neither Increased Memory Limit nor
//                                        the games' keychain groups
//        install-failed                  the install of the sheet's game,
//                                        which the network dropped halfway,
//                                        with its report to copy
//        installed                       the word an update leaves when
//                                        What's new has no notes to show
//        installed-not-a-game            the same two apps (other-apps), and
//                                        what Cartouche says once it has
//                                        installed the first: where it is
//        installing                      a game being installed, over the
//                                        console
//        installing-cable                the same from the MacBook Air, by
//                                        cable, at 31 MB/s
//        installing-mac                  the same on the Wi-Fi, the MacBook
//                                        Air on its 2.4 GHz band, at 3.1 MB/s,
//                                        with what would go faster
//        iphone-step                     a sign-in Apple accepted that
//                                        stopped at the step that registers
//                                        this iPhone, LocalDevVPN being off
//        log                             the logs of the sheet's game's last
//                                        two sessions, the last ended in a
//                                        crash (GalleryLogs.swift)
//        mac                             the player's Mac, paired, as the
//                                        games folder and the saves folder
//        mac-builds                      that Mac building one game and
//                                        another waiting its turn, as the
//                                        games' sheets, System and the
//                                        Mac's builds show them
//                                        (GalleryMac.builds)
//        mac-cable                       two Macs nearby: the MacBook Air
//                                        through the cable this iPhone is
//                                        plugged into it by, the Mac mini
//                                        on the Wi-Fi
//        mac-code                        two Macs nearby, pairing with the
//                                        first, with the six digits on both
//                                        screens
//        mac-nearby                      two Macs nearby whose Cartouche
//                                        Builder shares with Cartouche
//        mac-offline                     the player's Mac out of reach, away
//                                        from home, with two games' saves
//                                        waiting for it
//        mac-refused                     no Mac nearby, iOS refusing
//                                        Cartouche the local network
//        mac-tailscale                   the player's Mac, paired, as the
//                                        games folder and the saves folder,
//                                        with its addresses in the tailnet,
//                                        Tailscale connected on this iPhone;
//                                        on Add your Mac (screen
//                                        storage-mac), that Mac's own form
//        mac-tailscale-off               the same Mac out of reach, away
//                                        from home, Tailscale off on this
//                                        iPhone, with two games' saves
//                                        waiting for it
//        mac-too-old                     the player's Mac, paired, whose
//                                        app is 0.5.0 or older: too old to
//                                        share its builds, and no longer
//                                        finding its updates by itself
//        newer-build                     a newer build of the sheet's game,
//                                        or of the first of the player's, in
//                                        the games folder
//        nightly-no-vpn                  the automation of Shortcuts that
//                                        renews Cartouche every night,
//                                        whose Refresh All Apps ran at 4:00
//                                        this night without LocalDevVPN
//                                        connected (CartoucheNightly)
//        nightly-renewed                 the same, which renewed Cartouche
//                                        at 4:00 this night
//        no-app-group                    a sign-in whose built-in SideStore
//                                        found no app group, as when a
//                                        signing app signed the IPA for an
//                                        Apple ID, LocalDevVPN connected
//        not-signed-install              the sheet's game installed but not
//                                        signed whole, with Sign again and
//                                        play
//        not-signed-start                the same, as Play signed it again
//        other-apps                      two apps installed that are not
//                                        nxnative games, an IPA the player
//                                        tried, which the System page lists
//                                        under Other installed apps
//        offline                         the player's NAS, out of reach, with
//                                        a newer build of that game in its
//                                        games folder and two games' saves
//                                        waiting for it
//        own-cover                       the sheet's game, or the first of
//                                        the player's, with a cover of the
//                                        player's own
//        paused                          the sheet's game, or the first of
//                                        the player's, paused behind the
//                                        console; on the TV (screen tv), the
//                                        game paused behind the console
//        provisioning-refused            a sign-in for which Apple refused a
//                                        new machine for now, LocalDevVPN
//                                        connected, with the wait under way
//                                        (GalleryAppleAnswer)
//        renewal-failed                  Cartouche's renewal in its last 3
//                                        days, which failed, the network gone
//        renewal-no-liveprocess          Cartouche in its last 3 days,
//                                        LiveProcess missing from the app:
//                                        no renewal by itself, and what to
//                                        do on the System page
//        renewal-revoked                 Cartouche's renewal in its last 3
//                                        days, which failed as Apple had
//                                        revoked its certificate
//        renewal-session-expired         Cartouche's renewal in its last 3
//                                        days, which failed as Apple said
//                                        that the session SideStore renews
//                                        with had expired: the System page
//                                        and the setup ask to sign in again
//        renewal-unanswered              Cartouche's renewal in its last 3
//                                        days, which failed as this iPhone
//                                        did not answer through LocalDevVPN
//        renewing                        Cartouche renewing itself in its
//                                        last 3 days, as it came to the front
//        saves                           the saves of the sheet's game, or of
//                                        the first of the player's, and a
//                                        folder in Files as the saves folder,
//                                        which Cartouche's own sync uses
//                                        (GallerySaves)
//        saves-newer                     the same, the newest copy of the
//                                        game's saves waiting for its update,
//                                        version 1.2.0 of the game having
//                                        written it, and this iPhone's being
//                                        1.0.0
//        session-expired                 a sign-in whose session Apple says
//                                        has expired, before any code,
//                                        LocalDevVPN connected
//                                        (GalleryAppleAnswer)
//        sidestore-quit                  a sign-in whose built-in SideStore
//                                        quit as it launched, LocalDevVPN
//                                        connected
//        sign-in-no-liveprocess          a sign-in whose built-in SideStore
//                                        could not start, LiveProcess missing
//                                        from the app, LocalDevVPN connected
//        sign-in-unfinished              the setup after a sign-in that
//                                        stopped before the certificate,
//                                        the Apple ID having one made
//                                        elsewhere, with why and its report
//                                        to copy
//        signature-refused               the sheet's game's process ended as
//                                        iOS refused its signature
//                                        (CartoucheGameActions failSigning)
//        signed-elsewhere                the IPA for an Apple ID, signed by a
//                                        signing app without its app group,
//                                        which cannot sign in
//        signing-no-own-profile          signed on the iPhone (-GallerySigning
//                                        iphone) by a signing app that put no
//                                        profile in Cartouche: the import of
//                                        a certificate, which the setup
//                                        refused
//        signing-profile-file            the same, Cartouche's profile in
//                                        it, for a profile (.mobileprovision)
//                                        chosen in the certificate's place
//        signing-wrong-password          the same, for a .p12 whose password
//                                        is not the one typed
//        smb-no-guests                   on Add a shared folder (screen
//                                        storage-smb), the NAS refusing a
//                                        guest, without a user name
//        smb-refused                     on Add a shared folder (screen
//                                        storage-smb), the NAS refusing the
//                                        user name or the password the
//                                        player signed in with
//        starting                        on the TV (screen tv), the game
//                                        starting
//        tailscale                       Tailscale connected on this iPhone,
//                                        away from home: no Mac nearby on
//                                        Add your Mac (screen storage-mac)
//        tailscale-turned-off            Tailscale turned off half an hour
//                                        ago by LocalDevVPN, which Cartouche
//                                        connected to renew itself: the
//                                        console's top bar says so
//        stopped-on-error                the sheet's game's process ended on
//                                        another error (CartoucheGameActions
//                                        stoppedOnError)
//        too-many                        Apple refused the sign-in for too
//                                        many requests, with the wait under
//                                        way
//        update                          a new version of Cartouche on offer,
//                                        over the console, or on the System
//                                        page (screen system)
//        update-no-liveprocess           the update of Cartouche to 0.4.0,
//                                        failed as LiveProcess is missing
//                                        from the app
//        update-revoked                  the update of Cartouche to 0.4.0,
//                                        failed as Apple had revoked the
//                                        certificate of its signature
//        update-session-expired          the update of Cartouche to 0.4.0,
//                                        failed as Apple said that the
//                                        session SideStore asks it with had
//                                        expired
//        updated                         Cartouche opening after an update
//                                        started from it, from 0.2.0 to the
//                                        gallery's own version (project.yml),
//                                        which What's new shows as Cartouche
//                                        does
//        vpn-wait                        the sign-in waiting for LocalDevVPN
//        whats-new                       What's new over the console, as
//                                        after an update to the newest
//                                        version the gallery carries notes
//                                        for (app/releases)
//        whats-new-several               the same, to the newest two,
//                                        scrolled to where the older one's
//                                        notes begin
//      -GalleryOrientation landscape     the gallery turns itself sideways,
//                                        as a game does; the simulator
//                                        stays upright
//      -GalleryReady <scenario>          once the screen has settled, the
//                                        gallery writes
//                                        tmp/ready-<scenario>.json in its
//                                        container (Ready below)
//      -GalleryCategory <category>       where the screen opens, one of these:
//        <a section of nxnative's>       on a game's settings, that section,
//                                        such as Controls
//        cartouche.saves                 on a game's settings, its cloud
//                                        saves
//        cloud                           on the System page, the page
//                                        scrolled down to Cartouche Cloud
//        dumps                           on how to name the games (screen
//                                        storage-names), the page down to
//                                        Cartouche Builder's dumps folder
//        manage                          on the sheet, the sheet opened on
//                                        the game's management
//        otherApps                       on the System page, the page
//                                        scrolled down to Other installed
//                                        apps (work other-apps)
//        nightly                         on the Mac's builds (screen
//                                        mac-builds), down to the nightly
//                                        build; on the System page, the
//                                        page scrolled down to Renew every
//                                        night; on the setup, the page at
//                                        its end, on that step
//        requirements                    on a game's sheet, what the game
//                                        needs, opened on each need
//        reset                           on the System page, the page at its
//                                        end, on Reset Cartouche
//        results                         on a game's sheet, the testers'
//                                        results, what they wrote in French
//                                        as the iPhone translates it
//        saves                           on how to name the games (screen
//                                        storage-names), the page down to
//                                        the saves folder
//        signature                       on the System page, the page
//                                        scrolled down to its signature
//        tailscale                       on the Storage page or Renew every
//                                        night (screen nightly), the page
//                                        scrolled down to Tailscale
//        update                          on the System page, the page
//                                        scrolled down to its updates
//
//  The UI tests (launcher/Gallery/UITests) open the whole console, as
//  Cartouche shows it, and drive it (GalleryTesting.swift):
//
//      -GalleryScreen root               the console with the System page
//                                        over it, as Cartouche's root view
//      -GalleryTest 1                    a clean start, the IPA the Files
//                                        picker offers, and the watch on
//                                        the main thread
//      -GalleryPairing 1                 the pairing file without the rest
//                                        of the setup, to sign in
//      -GalleryHoldMainThread 1.5        the main thread held once, for
//                                        that many seconds, which the
//                                        watch must see
//      -GalleryKeyboard 1                for a test that types: the
//                                        keyboard shown and put away once,
//                                        before the watch counts
//      -GalleryShortcut <title ID>       Siri asks for that game as the
//                                        gallery opens, before its console
//                                        shows
//      -GalleryShortcutOnPost <title ID> Siri asks for that game each time
//                                        a test posts GalleryShortcut.posted
//      -GalleryTestName <name>           the test's, which the watch writes
//                                        down as the gallery starts
//

import Network
import SwiftUI
import UIKit

struct GalleryScenario {
    var screen = "games"
    /// nil: the whole screen of the simulator.
    var size: CGSize?
    var insets = EdgeInsets()
    /// nil: regular from 600 points wide, as an unfolded Duo is.
    var widthClass: UserInterfaceSizeClass?
    var owned: [String] = []
    var setupDone = false
    var controller = false
    var sheet: String?
    var work: String?
    var landscape = false
    /// The name of the file that says the screen has settled.
    var ready: String?
    var category: String?
    /// "iphone" or "installer": signed with the player's own certificate.
    var signing: String?

    static func fromArguments() -> GalleryScenario {
        let defaults = UserDefaults.standard
        var scenario = GalleryScenario()
        if let screen = defaults.string(forKey: "GalleryScreen") { scenario.screen = screen }
        let width = defaults.double(forKey: "GalleryWidth")
        let height = defaults.double(forKey: "GalleryHeight")
        if width > 0, height > 0 { scenario.size = CGSize(width: width, height: height) }
        let insets = (defaults.string(forKey: "GalleryInsets") ?? "").split(separator: ",").compactMap { Double($0) }
        if insets.count == 4 {
            scenario.insets = EdgeInsets(top: insets[0], leading: insets[1], bottom: insets[2], trailing: insets[3])
        }
        switch defaults.string(forKey: "GalleryWidthClass") {
        case "compact": scenario.widthClass = .compact
        case "regular": scenario.widthClass = .regular
        default: break
        }
        scenario.owned = (defaults.string(forKey: "GalleryOwned") ?? "").split(separator: ",").map(String.init)
        scenario.setupDone = defaults.bool(forKey: "GallerySetup")
        scenario.controller = defaults.bool(forKey: "GalleryController")
        scenario.sheet = defaults.string(forKey: "GallerySheet")
        scenario.work = defaults.string(forKey: "GalleryWork")
        scenario.landscape = defaults.string(forKey: "GalleryOrientation") == "landscape"
        scenario.ready = defaults.string(forKey: "GalleryReady")
        scenario.category = defaults.string(forKey: "GalleryCategory")
        scenario.signing = defaults.string(forKey: "GallerySigning")
        return scenario
    }

    /// The title IDs of the player's games.
    var ownedTitles: [String] { owned.map { item in String(item.prefix { $0 != ":" }) } }

    /// The certificate the player chose and the password they typed, in a
    /// Cartouche signed on the iPhone, for an import that the setup refused
    /// as the scenario's work says (works signing-…): the import's page, and
    /// the guide's and the setup's step, say why.
    var signingTrial: (certificate: Data, password: String)? {
        switch work {
        case "signing-wrong-password", "signing-no-own-profile": return (Self.standInPKCS12, "cartouche")
        case "signing-profile-file": return (Self.standInProfile, "cartouche")
        default: return nil
        }
    }

    /// The first bytes of a .p12, as iOS reads them: a SEQUENCE whose first
    /// value is the INTEGER 3, its version (RFC 7292); no key, no
    /// certificate.
    static let standInPKCS12 = Data([0x30, 0x82, 0x01, 0x00, 0x02, 0x01, 0x03] + [UInt8](repeating: 0, count: 253))

    /// A provisioning profile for the gallery's team, a year from expiring:
    /// its property list, in the CMS envelope's place.
    static let standInProfile: Data = {
        let plist: [String: Any] = ["Name": "Gallery", "TeamIdentifier": ["GALLERY123"],
                                    "ExpirationDate": Date(timeIntervalSinceNow: 365 * 86_400), "DeveloperCertificates": [Data]()]
        let xml = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
        // A CMS envelope's first bytes: a SEQUENCE, then signedData's OID.
        return Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]) + xml
    }()

    /// The checks of this iPhone that minimuxer failed, LocalDevVPN
    /// connected, by work: SideStore's
    /// kind of error, minimuxer's reason and the library's words behind it,
    /// the kind of pairing file minimuxer loaded (app/patches/sidestore/0022)
    /// and minimuxer's sentence.
    static let deviceChecks: [String: (kind: String, reason: String, detail: String?, pairingKind: String, sentence: String)] = [
        // A Lockdown pairing file, from iOS 26.4, without an IPsec interface.
        "device-no-ipsec": ("invalidVPN", "noIPsec", nil, "lockdown",
                            "utun is present but no ipsec/IKEv2 interface found — LocalDevVPN may not support the lockdown protocol on iOS 26.4+"),
        // A pairing file this iPhone refused at the handshake.
        "device-handshake": ("invalidPairingFile", "handshake", "reset", "rppairing",
                             "Handshake failed: Connection reset by peer (os error 54)"),
        // The tunnel up, and this iPhone not answering on its port.
        "device-port-closed": ("invalidVPN", "portClosed", nil, "rppairing",
                               "VPN tunnel iface is up and tunnel peer IP 10.7.0.1 is known, but TCP port poll failed — device may be unreachable on this interface"),
    ]

    /// The player's games that nxnative.json does not have: title ID and
    /// name.
    var unknownGames: [(titleId: String, name: String)] {
        owned.compactMap { item in
            guard let colon = item.firstIndex(of: ":") else { return nil }
            return (String(item[..<colon]), String(item[item.index(after: colon)...]))
        }
    }

    /// The name of the player's game of TITLEID.
    func name(of titleId: String) -> String? {
        unknownGames.first { $0.titleId == titleId }?.name ?? CartoucheCatalog.shared.game(titleId: titleId)?.name
    }

    /// What the signature of the player's own certificate gives Cartouche,
    /// as a signing app on the iPhone signs it: every entitlement of the
    /// profile, its keychain pattern as it is, which gives the games no
    /// keychain group; work iml-left-out: without Increased Memory Limit,
    /// which the profile allows; iml-not-in-profile: a profile that allows
    /// neither. The Cartouche Installer signs every group in.
    var ownSignature: CartoucheOwnSignature? {
        let team = "GALLERY123"
        let memory = CartoucheOwnSignature.memoryEntitlement
        let keychain = CartoucheOwnSignature.keychainEntitlement
        let profile: [String: Any] = [memory: true, keychain: [team + ".*"]]
        switch (signing, work) {
        case ("iphone"?, "iml-left-out"?):
            return CartoucheOwnSignature(signed: [keychain: [team + ".*"]], profile: profile, team: team)
        case ("iphone"?, "iml-not-in-profile"?):
            return CartoucheOwnSignature(signed: [keychain: [team + ".io.github.clabeuhtegrite.cartouche"]],
                                         profile: [keychain: [team + ".io.github.clabeuhtegrite.cartouche"]], team: team)
        case ("iphone"?, _):
            return CartoucheOwnSignature(signed: profile, profile: profile, team: team)
        case ("installer"?, _):
            return CartoucheOwnSignature(signed: [memory: true, keychain: CartoucheOwnSignature.gameKeychainGroups(team: team)],
                                         profile: profile, team: team)
        default:
            return nil
        }
    }

    /// Puts the files the stand-ins read where the launcher looks for them.
    func prepare() {
        GalleryState.setupDone = setupDone
        GalleryState.signing = signing == "iphone" ? .iPhone : signing == "installer" ? .installer
            : signing == "sidestore" ? .sideStore : .account
        GalleryState.sideStoreMemory = signing == "sidestore" ? (setupDone ? .reinstall : .afterSetup) : nil
        GalleryState.ownSignature = ownSignature
        GalleryState.ownProfile = signingTrial != nil && work != "signing-no-own-profile" ? Self.standInProfile : nil
        // errSecAuthFailed, as iOS answers a password that does not open a
        // .p12.
        GalleryState.pkcs12Status = work == "signing-wrong-password" ? -25293 : nil
        GalleryState.certificateRefused = work == "certificate"
        GalleryState.appGroupMissing = work == "signed-elsewhere"
        GalleryState.liveProcessMissing = work?.hasSuffix("-no-liveprocess") == true
        GalleryState.readsBCTextures = !GalleryBCConversion.isWithoutBC(work)
        GalleryState.gameModeLater = work == "game-mode-later"
        // Cartouche's first launch on this iPhone and this iOS: no limit of
        // its own measured before Game Mode comes (CartoucheOwnLimitRecord).
        if GalleryState.gameModeLater {
            UserDefaults.standard.removeObject(forKey: CartoucheOwnLimitRecord.key)
            UserDefaults.standard.removeObject(forKey: CartoucheOwnLimitRecord.systemKey)
        }
        GalleryState.signInUnfinished = work == "sign-in-unfinished"
        GalleryState.sheetSection = screen == "sheet" ? category : nil
        GalleryState.vpnConnected = work.map {
            Self.deviceChecks[$0] != nil || ["sidestore-quit", "no-app-group", "sign-in-no-liveprocess"].contains($0)
                || GalleryAppleAnswer(rawValue: $0) != nil
        } ?? false
        let pairing = GalleryState.documents.appendingPathComponent("SideStore/Documents", isDirectory: true)
        try? FileManager.default.removeItem(at: pairing)
        if setupDone || GalleryState.signInUnfinished {
            try? FileManager.default.createDirectory(at: pairing, withIntermediateDirectories: true)
            try? Data("gallery".utf8).write(to: pairing.appendingPathComponent("ALTPairingFile.mobiledevicepairing"))
        }
        // The built-in SideStore's record of its last renewal: six days left,
        // or, as Cartouche renews itself, two and a bit.
        if work == "renewing" || work == "renewal-failed" || work == "renewal-revoked"
            || work == "renewal-unanswered" || work == "renewal-no-liveprocess" || work == "renewal-session-expired" {
            GalleryState.recordSignature(expiringIn: 2 * 86_400 + 5 * 3_600, renewedAgo: 4 * 86_400 + 19 * 3_600)
        } else {
            GalleryState.recordSignature(expiringIn: 6 * 86_400 + 3_600, renewedAgo: 86_400)
        }
        MainActor.assumeIsolated {
            // What an earlier scenario noted of Apple's session stays out of
            // this one.
            UserDefaults.standard.removeObject(forKey: CartoucheRenewals.sessionExpiredKey)
            UserDefaults.standard.removeObject(forKey: CartoucheRenewals.sessionSignInKey)
            showTranslations()
            if work == "updated" {
                // What an update started from Cartouche leaves as it opens
                // again, before Cartouche reads it: the version it
                // installed, and the version whose notes the player saw.
                UserDefaults.standard.set("0.2.0", forKey: CartoucheWhatsNewRecord.seenKey)
                CartoucheUpdates.leavePendingForGallery(CartoucheUpdates.runningVersion)
                // The UI tests' start decides as Cartouche does already.
                if !GalleryTest.isOn { CartoucheWhatsNew.shared.decideForGallery() }
            }
            CartoucheMacBuildsWatch.galleryScrolls = screen == "sheet-mac"
            // The System page down to the scenario's section, or on the
            // Mac's builds, down to theirs.
            CartoucheSystemView.openingSection = screen == "system" ? category : nil
            CartoucheStorageView.opensOnTailscale = screen == "storage" && category == "tailscale"
            CartoucheNightlyRenewalView.opensOnTailscale = screen == "nightly" && category == "tailscale"
            CartoucheSetupView.opensAtEnd = screen == "setup" && category == "nightly"
            // Tailscale as the scenario has it, never as the Mac the
            // simulator runs on does.
            CartoucheStorageReach.shared.showTailscaleForGallery(["mac-tailscale", "tailscale"].contains(work))
            if work == "tailscale-turned-off" {
                CartoucheStorageReach.shared.showTailscaleTurnedOffForGallery()
            }
            CartoucheSystemView.opensMacBuilds = screen == "mac-builds"
            CartoucheMacBuildsPage.openingRow = screen == "mac-builds" && category == "nightly" ? CartoucheMacBuildsPage.nightlyRow : nil
            if work == "renewing" {
                CartoucheRenewals.shared.showRenewingForGallery(at: 0.4)
            }
            if work == "renewal-failed" {
                CartoucheRenewals.shared.showFailedForGallery(URLError(.notConnectedToInternet))
            }
            if work == "renewal-revoked" {
                CartoucheRenewals.shared.showRevokedForGallery()
            }
            if work == "renewal-unanswered" {
                CartoucheRenewals.shared.showUnansweredForGallery()
            }
            if work == "renewal-session-expired" {
                CartoucheRenewals.shared.showSessionExpiredForGallery()
            }
            // The automation of every night as the work has it, never as a
            // scenario before this one left it.
            CartoucheNightly.shared.showForGallery(work)
            CartoucheSetup.shared.refresh()
            if let trial = signingTrial {
                // The import the setup refused, as the player tried it.
                Task { await CartoucheSetup.shared.importSigning(certificate: trial.certificate, password: trial.password, profile: nil) }
            }
            CartoucheGuide.shared.startOverForGallery()
            if work == "build-skipped" { CartoucheGuide.shared.skipBuild() }
            if controller { CartoucheGamepad.shared.showHints() }
            showStats()
            showFound()
            if work == "own-cover", let titleId = sheet ?? ownedTitles.first {
                showOwnCover(of: titleId)
            }
            if work == "installing" {
                let name = sheet.flatMap { CartoucheCatalog.shared.game(titleId: $0)?.name } ?? "Game"
                // As from iOS 26, which goes on with it outside Cartouche.
                CartoucheGameActions.shared.work = CartoucheGameWork(kind: .installing, name: name,
                                                                     step: CartoucheText.installUnpacking, fraction: 0.42,
                                                                     outside: true)
            }
            if work == "installing-cable" || work == "installing-mac" {
                // From the player's Mac, how it comes and how fast
                // (CartoucheTransferSpeed.swift), as from iOS 26.
                let name = sheet.flatMap { CartoucheCatalog.shared.game(titleId: $0)?.name } ?? "Game"
                var shown = CartoucheGameWork(kind: .installing, name: name, step: CartoucheText.installFromStorageStep("MacBook Air"),
                                              fraction: 0.42, stage: "unpacking", place: "MacBook Air", outside: true)
                if work == "installing-cable" {
                    shown.way = .cable
                    shown.speed = 31_400_000
                } else {
                    shown.way = .network(mac: CartoucheMacNetwork(medium: CartoucheMacNetwork.wifi, band: "2.4"))
                    shown.speed = 3_140_000
                    shown.slow = true
                }
                CartoucheGameActions.shared.work = shown
            }
            if work == "installed-not-a-game" {
                // The first of the other apps, just installed: Cartouche
                // says where it is (CartoucheGameActions.finishInstall).
                CartoucheGameActions.shared.notice = CartoucheGameNotice(
                    title: CartoucheText.installDone, message: CartoucheText.installNotAGame(Self.otherApps[0].name))
            }
            if work == "install-failed" {
                // An install the network dropped halfway, with its report.
                let name = sheet.flatMap { CartoucheCatalog.shared.game(titleId: $0)?.name } ?? "Game"
                let error = URLError(.networkConnectionLost)
                let report = CartoucheReports.make(.install, CartoucheText.installFailed, message: error.localizedDescription,
                                                   error: error, step: CartoucheText.installTitle(name) + ": " + CartoucheText.installUnpacking,
                                                   fraction: 0.42, facts: [.init("IPA", name + " [" + (sheet ?? "") + "].ipa")])
                CartoucheGameActions.shared.notice = CartoucheGameNotice(title: report.title, message: report.message, report: report)
            }
            // Cartouche Cloud's answers, never asked of the platform.
            GalleryCloud.show(screen: screen, work: work)
            if let notice = signingNotice() {
                CartoucheGameActions.shared.notice = notice
            }
            if work == "update" {
                // A higher version than the gallery's own (project.yml): on
                // offer over the console, or on the System page, which opens
                // on its updates.
                let release = CartoucheRelease(
                    version: "0.4.0", notes: "", size: 36_802_806,
                    ownCertificateURL: URL(string: "https://github.com/clabeuhtegrite/Cartouche/releases/download/v0.4.0/Cartouche-0.4.0-Own-Certificate.ipa"))
                if screen == "system" {
                    CartoucheUpdates.shared.showOnSystemPageForGallery(release)
                } else {
                    CartoucheUpdates.shared.offerForGallery(release)
                }
            }
            if work == "whats-new" || work == "whats-new-several" {
                let newest = Array(CartoucheWhatsNew.carried.prefix(work == "whats-new" ? 1 : 2))
                // After two versions, scrolled to the last item of the newer
                // one, the older one's name under it.
                let scrolled = work == "whats-new-several" ? max((newest.first?.items.count ?? 0) - 1, 0) : 0
                CartoucheWhatsNew.shared.showForGallery(newest, scrolledTo: scrolled)
            }
            if work == "installed" {
                CartoucheUpdates.shared.showInstalledForGallery()
            }
            if work == "update-revoked" {
                CartoucheUpdates.shared.showRevokedForGallery("0.4.0")
            }
            if work == "update-no-liveprocess" {
                CartoucheUpdates.shared.showNoLiveProcessForGallery("0.4.0")
            }
            if work == "update-session-expired" {
                CartoucheUpdates.shared.showSessionExpiredForGallery("0.4.0")
            }
            if work == "code" {
                CartoucheAccount.shared.requestCodeForGallery(.init(
                    id: "gallery", mode: .sms, phone: "+33 •• •• •• •• 78", canTextMessage: false, error: nil))
            }
            if work == "too-many" {
                CartoucheAccount.shared.showTooManyRequestsForGallery()
            }
            if work == "vpn-wait" {
                CartoucheAccount.shared.waitForVPNForGallery()
            }
            if work == "iphone-step" {
                CartoucheAccount.shared.showDeviceStepForGallery()
            }
            if let check = work.flatMap({ Self.deviceChecks[$0] }) {
                CartoucheAccount.shared.showDeviceCheckForGallery(kind: check.kind, reason: check.reason, detail: check.detail,
                                                                  pairingKind: check.pairingKind, sentence: check.sentence)
            }
            if work == "sidestore-quit" {
                CartoucheAccount.shared.showSideStoreQuitForGallery()
            }
            if work == "no-app-group" {
                CartoucheAccount.shared.showNoAppGroupForGallery()
            }
            if work == "sign-in-no-liveprocess" {
                CartoucheAccount.shared.showNoLiveProcessForGallery()
            }
            if let answer = work.flatMap(GalleryAppleAnswer.init(rawValue:)) {
                CartoucheAccount.shared.showAppleAnswerForGallery(answer.outcome, message: answer.message)
            }
            if work == "sign-in-unfinished" {
                CartoucheAccount.shared.showUnfinishedForGallery()
            }
            if let titleId = updatedTitle, let game = CartoucheCatalog.shared.game(titleId: titleId) {
                // Cartouche Builder built the game again last night.
                let stored = CartoucheStoredGame(
                    path: "/Jeux/\(game.name) [\(titleId)].ipa", size: 21_474_836_480, modified: Date().addingTimeInterval(-5 * 3_600),
                    bundleId: "org.nxnative." + titleId.lowercased(), displayName: game.name, version: "1.0.0",
                    build: CartoucheGameBuild(version: "1.0.0", commit: "7bddb8c1e2f3", chain: "adec7d81d970",
                                              builtAt: Date().addingTimeInterval(-5 * 3_600 - 120)),
                    titleId: titleId, isGame: true)
                CartoucheStoredGames.shared.showForGallery([stored], server: "NAS")
            }
            if work == "offline" {
                // Away from home: the NAS does not answer, and the saves of
                // two games wait for it.
                let nas = CartoucheStorageServer(kind: .smb, name: "NAS", host: "nas.local", username: "joueur", share: "Partage")
                CartoucheStorageSettings.shared.showForGallery(nas, games: "Jeux", saves: "Sauvegardes")
                CartoucheStorageReach.shared.showOfflineForGallery([nas.id])
                CartoucheSaveBackups.shared.showWaitingForGallery(2)
            }
            // The servers Add a shared folder finds nearby: made-up ones,
            // never those of the network the gallery runs on.
            CartoucheSMBBrowser.gallery = screen == "storage-smb" ? GallerySMB.nearby : []
            if screen == "storage-smb" {
                CartoucheStorageServerForm.gallery = GallerySMB.signIn(work)
            }
            if work == "tailscale" {
                // Away from home: Bonjour finds no Mac, and nothing refuses
                // it the local network.
                CartoucheMacBrowser.gallery = (found: [], refused: false)
            }
            if ["mac-nearby", "mac-code", "mac-refused", "mac-cable"].contains(work) {
                let refused = work == "mac-refused"
                CartoucheMacBrowser.gallery = (found: refused ? [] : work == "mac-cable" ? GalleryMac.cabled : GalleryMac.nearby,
                                               refused: refused)
                if work == "mac-code" {
                    CartoucheMacPairing.gallery = (mac: GalleryMac.nearby[0], code: "482915")
                }
            }
            if work == "saves" || work == "saves-newer", let titleId = sheet ?? ownedTitles.first {
                GallerySaves.prepare(titleId: titleId)
                if work == "saves-newer" {
                    CartoucheSaveBackups.shared.showNewerForGallery("org.nxnative." + titleId.lowercased() + "|gallery",
                                                                    CartoucheSaveNewer(copy: "1.2.0", game: "1.0.0"))
                }
                if screen == "switch-save" {
                    // The save JKSV exported, picked as the page opens.
                    CartoucheSwitchSaveView.galleryPick = { await GallerySaves.switchExport() }
                }
            }
            if screen == "sheet-saves" {
                GallerySaves.bringingDown = true
                CartoucheGameSheetView.galleryToSaves = { scrollTo in await GallerySaves.bringDown(scrollTo) }
            }
            if work == "log", let titleId = sheet ?? ownedTitles.first {
                GalleryLogs.prepare(titleId: titleId)
            }
            if work == "erasing" {
                CartoucheReset.shared.showForGallery(.erasing)
            }
            if ["mac", "mac-offline", "mac-builds", "mac-too-old", "mac-tailscale", "mac-tailscale-off"].contains(work) {
                // The player's Mac, paired, with the games Cartouche Builder
                // built in its Games folder; offline, away from home, the
                // saves of two games wait for it; builds, Cartouche Builder
                // at work, which the games' sheets and System show; too
                // old, a Cartouche Builder 0.5.0, which shares no builds;
                // Tailscale, its addresses in the tailnet known.
                var mac = GalleryMac.paired()
                if work == "mac-tailscale" || work == "mac-tailscale-off" {
                    mac.tailnet = GalleryMac.tailnet
                }
                CartoucheStorageSettings.shared.showForGallery(mac, games: CartoucheBridge.gamesFolder,
                                                               saves: CartoucheBridge.savesFolder)
                CartoucheStoredGames.shared.showForGallery(storedGames(in: CartoucheBridge.gamesFolder), server: mac.name)
                if work == "mac-offline" || work == "mac-tailscale-off" {
                    CartoucheStorageReach.shared.showOfflineForGallery([mac.id])
                    CartoucheSaveBackups.shared.showWaitingForGallery(2)
                }
                if work == "mac-builds" {
                    CartoucheMacBuildsWatch.gallery = (mac: mac.name, builds: GalleryMac.builds())
                }
                if work == "mac-too-old" {
                    CartoucheMacBuildsWatch.galleryTooOld = mac.name
                }
            }
            if work == "games-folders" {
                let catalog = CartoucheCatalog.shared
                GalleryGamesFolders.prepare(owned: ownedTitles.compactMap { catalog.game(titleId: $0) },
                                            sheet: sheet.flatMap { ownedTitles.contains($0) ? nil : catalog.game(titleId: $0) })
            }
            if work == "drive-signed-out" {
                // The player's Google Drive, seven days after the sign-in:
                // Google ended it, and the saves of two games wait for it.
                let drive = CartoucheStorageServer(kind: .drive, name: "Google Drive", host: "joueur@example.com",
                                                   username: "123456789012-cartouchegallery.apps.googleusercontent.com")
                CartoucheStorageSettings.shared.showForGallery(drive, games: "Jeux", saves: "Sauvegardes")
                CartoucheStoredGames.shared.showForGallery(storedGames(in: "Jeux"), server: drive.name)
                CartoucheDriveSessions.shared.end(drive.id)
                CartoucheStorageReach.shared.showOfflineForGallery([drive.id])
                CartoucheSaveBackups.shared.showWaitingForGallery(2)
            }
        }
    }

    /// The notice of the sheet's game, which LiveContainer did not sign
    /// whole, zsign failing on one of its libraries, or whose process ended
    /// as iOS refused its signature or a library it needs was missing, as
    /// CartoucheGameActions shows it (failSigning, stoppedOnError), with the
    /// report to copy.
    @MainActor
    private func signingNotice() -> CartoucheGameNotice? {
        let titleId = sheet ?? ownedTitles.first ?? ""
        let name = CartoucheCatalog.shared.game(titleId: titleId)?.name ?? "Game"
        let bundleId = "org.nxnative." + titleId.lowercased()
        let unsigned = CartoucheGameSigning.Failure(reason: .filesNotSigned, fileKind: "framework", files: 1, signedAnyway: true)
        let title: String
        let message: String
        let failure: CartoucheFailure
        var signAgain = true
        switch work ?? "" {
        case "not-signed-install":
            title = CartoucheText.installSignWarning
            message = CartoucheText.notSignedFiles + " " + CartoucheText.notSignedAtInstall
            failure = CartoucheFailure(.notSigned, stage: "signing", details: unsigned.details)
        case "not-signed-start":
            title = CartoucheText.notSignedTitle(name)
            message = CartoucheText.notSignedFiles + " " + CartoucheText.notSignedAtStart
            failure = CartoucheFailure(.notSigned, stage: "signing", details: unsigned.details)
        case "signature-refused":
            let stopped = CartoucheGameSigning.StartFailure(kind: .codeSignature)
            title = CartoucheText.gameStoppedTitle(name)
            message = CartoucheText.gameSignatureRefused
            failure = CartoucheFailure(stopped.cause, stage: "gameProcess", seconds: 1.4, details: stopped.details)
        case "stopped-on-error":
            let stopped = CartoucheGameSigning.StartFailure(kind: .libraryMissing)
            title = CartoucheText.gameStoppedTitle(name)
            message = CartoucheText.gameStoppedOnError
            failure = CartoucheFailure(stopped.cause, stage: "gameProcess", seconds: 1.4, details: stopped.details)
            signAgain = false
        default:
            return nil
        }
        let origin: CartoucheReport.Origin = work == "not-signed-install" ? .install : .start
        let report = CartoucheReports.make(origin, title, message: message, failure: failure)
        return CartoucheGameNotice(title: title, message: message, report: report, signAgain: signAgain ? bundleId : nil)
    }

    /// The player's games as IPAs in FOLDER, as Cartouche Builder leaves
    /// them there: built last night.
    @MainActor
    private func storedGames(in folder: String) -> [CartoucheStoredGame] {
        ownedTitles.compactMap { titleId in
            guard let game = CartoucheCatalog.shared.game(titleId: titleId) else { return nil }
            let built = Date().addingTimeInterval(-9 * 3_600)
            return CartoucheStoredGame(
                path: "/\(folder)/\(game.name) [\(titleId)].ipa", size: 21_474_836_480, modified: built,
                bundleId: "org.nxnative." + titleId.lowercased(), displayName: game.name, version: "1.0.0",
                build: CartoucheGameBuild(version: "1.0.0", commit: "7bddb8c1e2f3", chain: "adec7d81d970",
                                          builtAt: built.addingTimeInterval(-120)),
                titleId: titleId, isGame: true)
        }
    }

    /// What Cartouche's server would answer about the player's games that
    /// nxnative.json does not have: what IGDB has of the catalogue's game
    /// of the same name, if there is one, as the server finds a game by its
    /// name.
    @MainActor
    private func showFound() {
        let catalog = CartoucheCatalog.shared
        var found: [String: CartoucheFoundGame] = [:]
        for game in unknownGames {
            let platform = CartoucheGameWanted.platform(titleId: game.titleId)
            guard let wanted = CartoucheGameWanted(name: game.name, platform: platform),
                  let known = catalog.titleId(matchingName: game.name), let cover = catalog.cover(titleId: known) else { continue }
            let profile = catalog.game(titleId: known)
            found[wanted.key] = CartoucheFoundGame(
                igdb: cover.igdb, name: profile?.name ?? game.name, cover: cover.cover, artwork: cover.artwork,
                genre: profile.flatMap { $0.genre == "other" ? nil : $0.genre } ?? cover.genre,
                platform: platform ?? profile?.platform, summary: cover.summary)
        }
        catalog.showFoundForGallery(found)
    }

    /// A cover of the player's own for the game of TITLEID, as one drawn by
    /// hand: never a game's own art.
    @MainActor
    private func showOwnCover(of titleId: String) {
        let catalog = CartoucheCatalog.shared
        guard let entry = catalog.entries(for: self.apps()).owned.first(where: { $0.titleId == titleId }),
              let picture = GalleryIcon.cover(name: entry.name, key: titleId).jpegData(compressionQuality: 0.9) else { return }
        do {
            try catalog.setPlayerInfo(nil, cover: CartouchePlayerInfoStore.jpeg(from: picture), for: entry)
        } catch {
            NSLog("[Gallery] cannot keep the player's cover: %@", String(describing: error))
        }
    }

    /// The size and the play time of the player's games: the first played
    /// for hours, until yesterday, the second for a while this morning, the
    /// third not yet.
    @MainActor
    private func showStats() {
        let sizes: [CartoucheGameSize] = [CartoucheGameSize(bundle: 21_474_836_480, data: 327_155_712),
                                          CartoucheGameSize(bundle: 14_173_392_076, data: 48_234_496),
                                          CartoucheGameSize(bundle: 3_113_851_290, data: 6_291_456)]
        let times: [CartouchePlayTime] = [
            CartouchePlayTime(seconds: 45_240, sessions: 23, firstPlayed: Date().addingTimeInterval(-9 * 86_400),
                              lastPlayed: Date().addingTimeInterval(-86_400)),
            CartouchePlayTime(seconds: 2_820, sessions: 2, firstPlayed: Date().addingTimeInterval(-4 * 3_600),
                              lastPlayed: Date().addingTimeInterval(-3 * 3_600)),
        ]
        var shownSizes: [String: CartoucheGameSize] = [:]
        var shownTimes: [String: CartouchePlayTime] = [:]
        for (index, titleId) in ownedTitles.enumerated() {
            let bundleId = "org.nxnative." + titleId.lowercased()
            if index < sizes.count { shownSizes[bundleId] = sizes[index] }
            if index < times.count { shownTimes[bundleId] = times[index] }
        }
        CartoucheGameStats.shared.showForGallery(sizes: shownSizes, playTimes: shownTimes)
    }

    /// The game a newer build is in the games folder of (work: newer-build,
    /// and offline, away from the games folder): the sheet's, or the first
    /// of the player's.
    private var updatedTitle: String? { work == "newer-build" || work == "offline" ? sheet ?? ownedTitles.first : nil }

    /// The sheet's game, or the first of the player's, paused behind the
    /// console (work: paused).
    @MainActor
    func pause(among apps: [LCAppModel]) {
        guard work == "paused", let titleId = sheet ?? ownedTitles.first,
              let app = apps.first(where: { $0.appInfo.relativeBundlePath == titleId + ".app" }) else { return }
        CartoucheGameActions.shared.showRunningForGallery(app)
    }

    /// The iPhone's translations of what testers wrote on the sheet of the
    /// testers' results, as it makes them in French, which the simulator
    /// cannot; none kept for the other scenarios.
    @MainActor
    private func showTranslations() {
        try? FileManager.default.removeItem(at: CartoucheTranslations.defaultFile)
        guard screen == "sheet", category == "results",
              let language = CartoucheGameSummaryView.language?.minimalIdentifier, language == "fr" else { return }
        for (text, translation) in GalleryTranslations.french {
            CartoucheTranslations.shared.keep(translation, of: text, into: language)
        }
    }

    /// What capture.sh needs to cut the screen out of the simulator's
    /// screenshot, or to turn it the right way up (screenshot.swift).
    struct Ready: Encodable {
        let scale: Double
        /// The size of the window's screen in pixels, upright: on a simulator
        /// with more than one display, such as the iPhone Duo with its outer
        /// and inner ones, capture.sh takes the display of this size.
        let pixels: [Double]
        /// The window's top left corner on the screen, in points.
        let origin: [Double]
        let window: [Double]
        let orientation: String
    }

    /// Turns the gallery sideways if the scenario asks, upright on a
    /// device's simulator otherwise, then, once the layout, the stage's
    /// colours and the cartridges have settled, says so.
    @MainActor
    func settle() {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        if landscape, let scene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                NSLog("[Gallery] cannot turn sideways: %@", String(describing: error))
            }
        }
        guard let ready else { return }
        // Upright on a device's simulator, for a scenario that does not turn
        // sideways: iOS opens the gallery turned as it was before, after
        // duo-sim-home-landscape too. On Ad's Mac, in run 43536103765, seven
        // scenarios of the iPhone Duo came out sideways, the first of them
        // duo-sim-home, then the next ones white or faded as iOS turned the
        // gallery upright again.
        let upright = !landscape && size == nil
        if upright, let scene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                NSLog("[Gallery] cannot turn upright: %@", String(describing: error))
            }
        }
        Task { @MainActor in
            // Turned first, for up to 30 s: on the iPhone Duo of run
            // 43275681933, beside two builds of the app on Ad's Mac, the
            // simulator had not turned the scene by the time the gallery
            // said it had settled, upright.
            if landscape || upright, let scene {
                for _ in 0..<120 {
                    let now = scene.effectiveGeometry.interfaceOrientation
                    if landscape ? now.isLandscape : now == .portrait { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            try? await Task.sleep(for: .seconds(3))
            // Game Mode, which comes 1.5 s after Cartouche first measured its
            // memory, and the next measurement after, 2 s later at most
            // (work: game-mode-later), for up to 10 s more.
            for _ in 0..<40 where !GalleryState.gameModeSettled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            // The sheet on its way down to its saves, for up to 15 s more.
            for _ in 0..<60 where GallerySaves.bringingDown {
                try? await Task.sleep(for: .milliseconds(250))
            }
            // The covers the screen shows, from IGDB, for up to 20 s more.
            for _ in 0..<40 {
                let pending = await CartoucheCoverStore.shared.pending
                if pending == 0 { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let scene, let window = scene.windows.first else {
                NSLog("[Gallery] no window to measure")
                return
            }
            let frame = window.convert(window.bounds, to: scene.screen.coordinateSpace)
            let orientation = switch scene.effectiveGeometry.interfaceOrientation {
            case .landscapeLeft: "landscapeLeft"
            case .landscapeRight: "landscapeRight"
            case .portraitUpsideDown: "portraitUpsideDown"
            default: "portrait"
            }
            let pixels = scene.screen.nativeBounds.size
            let report = Ready(scale: Double(scene.screen.scale),
                               pixels: [Double(pixels.width), Double(pixels.height)],
                               origin: [Double(frame.minX), Double(frame.minY)],
                               window: [Double(frame.width), Double(frame.height)],
                               orientation: orientation)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ready-\(ready).json")
            do {
                try JSONEncoder().encode(report).write(to: url, options: .atomic)
            } catch {
                NSLog("[Gallery] cannot write %@: %@", url.path, String(describing: error))
            }
        }
    }

    /// The apps that are not nxnative games (works other-apps and
    /// installed-not-a-game): a name, a bundle identifier of no nxnative
    /// game, and a key for the colours of their icon.
    static let otherApps: [(name: String, identifier: String)] = [
        ("Pocket Notes", "com.example.pocketnotes"),
        ("Sky Radar", "com.example.skyradar"),
    ]

    func apps() -> [LCAppModel] {
        let others = work == "other-apps" || work == "installed-not-a-game" ? Self.otherApps.map { app in
            LCAppModel(appInfo: LCAppInfo(name: app.name, identifier: app.identifier, folder: app.identifier + ".app",
                                          icon: GalleryIcon.make(name: app.name, key: app.identifier)))
        } : []
        return games() + others
    }

    /// The player's games.
    private func games() -> [LCAppModel] {
        ownedTitles.compactMap { titleId in
            guard let name = name(of: titleId) else { return nil }
            let info = LCAppInfo(name: name, identifier: "org.nxnative." + titleId.lowercased(),
                                 folder: titleId + ".app", icon: GalleryIcon.make(name: name, key: titleId))
            if titleId == sheet { GalleryBCConversion.install(info, work: work) }
            if titleId == updatedTitle {
                // Installed four days ago, from an older commit of nxnative.
                info.infoPlist = NSMutableDictionary(dictionary: ["CFBundleShortVersionString": "1.0.0", "DMCommit": "52124866a1b2",
                                                                  "DMChain": "844bf1a5ea8f"])
                info.installationDate = Date().addingTimeInterval(-4 * 86_400)
            }
            return LCAppModel(appInfo: info)
        }
    }
}

@main
struct CartoucheGalleryApp: App {
    private let scenario: GalleryScenario
    /// LiveContainer's model, as the gallery stands it in.
    @ObservedObject private var model = DataManager.shared.model

    init() {
        GalleryTest.start()
        scenario = GalleryScenario.fromArguments()
        scenario.prepare()
        // The player's games before any screen, as LiveContainer lists them
        // as it starts: Siri may ask for one before the console shows.
        DataManager.shared.model.apps = scenario.apps()
        MainActor.assumeIsolated {
            GalleryTest.prepared()
            GalleryShortcut.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            content
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .overlay(alignment: .bottomLeading) {
                    if GalleryTest.isOn {
                        GalleryWatchReadout()
                            .frame(width: 2, height: 2)
                            .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    scenario.pause(among: model.apps)
                    scenario.settle()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let size = scenario.size {
            ZStack(alignment: .topLeading) {
                Color.black
                screen
                    .safeAreaPadding(scenario.insets)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .environment(\.horizontalSizeClass, scenario.widthClass ?? (size.width >= 600 ? .regular : .compact))
            .environment(\.verticalSizeClass, size.height >= 600 ? .regular : .compact)
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        } else {
            screen
        }
    }

    @ViewBuilder
    private var screen: some View {
        let entries = CartoucheCatalog.shared.entries(for: model.apps, stored: CartoucheStoredGames.shared.games,
                                                      cloud: CartoucheCloudLink.shared.builtGames)
        switch scenario.screen {
        case "library":
            // Every game, open over the home as the player opens it, beside
            // the sheet of the game in focus on an iPhone Duo unfolded once
            // the player has a game.
            CartoucheGamesView(showingLibrary: true)
        case "sheet", "sheet-mac", "sheet-saves":
            if let entry = entries.all.first(where: { $0.titleId == scenario.sheet }) {
                GallerySheetScreen(entry: entry, opensOnManagement: scenario.category == "manage")
            }
        case "gameinfo":
            if let entry = entries.owned.first(where: { $0.titleId == scenario.sheet }) {
                NavigationStack {
                    CartoucheGameInfoView(entry: entry, onClose: {})
                }
            }
        case "gamelog", "gamelog-sent":
            if let entry = entries.owned.first(where: { $0.titleId == scenario.sheet }), let app = entry.app,
               let folder = CartoucheGameActions.shared.logs(of: app) {
                NavigationStack {
                    if scenario.screen == "gamelog" {
                        CartoucheGameLogView(folder: folder, tileKey: entry.tileKey)
                    } else {
                        CartoucheGameLogSentView(share: GalleryLogs.share(of: folder), tileKey: entry.tileKey)
                    }
                }
            }
        case "shortcuts":
            if let entry = entries.owned.first(where: { $0.titleId == scenario.sheet }),
               let id = entry.app?.appInfo.bundleIdentifier() {
                NavigationStack {
                    CartoucheGameShortcutsView(id: id, name: entry.name)
                }
            }
        case "settings":
            if let entry = entries.all.first(where: { $0.titleId == scenario.sheet }), let app = entry.app {
                NavigationStack {
                    CartoucheGameSettingsView(model: settings(for: app, entry: entry), onNxnativeScreen: {})
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(CartoucheText.done) {}
                            }
                        }
                }
            }
        case "setup":
            NavigationStack {
                CartoucheSetupView()
            }
        case "signin":
            CartoucheSignInView()
        case "signing":
            NavigationStack {
                CartoucheSigningView(certificate: scenario.signingTrial?.certificate)
            }
        case "guide":
            NavigationStack {
                CartoucheGuideView(entries: entries, onInstall: { _ in }, onImport: { _ in }, onPlay: { _ in })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(CartoucheText.done) {}
                        }
                    }
            }
        case "system", "mac-builds":
            CartoucheSystemView()
        case "cloud":
            // As System opens it.
            NavigationStack {
                CartoucheCloudPage()
            }
            .preferredColorScheme(.dark)
        case "nightly":
            NavigationStack {
                CartoucheNightlyRenewalView()
            }
        case "storage":
            NavigationStack {
                CartoucheStorageView()
            }
        case "storage-smb":
            // As the Storage page opens it, once the player signed in to
            // list the shared folders of a NAS nearby.
            NavigationStack {
                CartoucheStorageServerForm(server: GallerySMB.server(scenario.work))
            }
        case "storage-mac":
            // As the Storage page opens it, for a Mac not paired yet, or for
            // the player's Mac (work mac-tailscale).
            NavigationStack {
                CartoucheStorageMacForm(server: scenario.work == "mac-tailscale"
                                        ? CartoucheStorageSettings.shared.servers.first(where: { $0.kind == .mac }) ?? GalleryMac.paired()
                                        : CartoucheStorageServer(kind: .mac, name: ""))
            }
        case "storage-drive":
            // As the Storage page opens it, to add a Google Drive.
            NavigationStack {
                CartoucheStorageDriveForm(server: CartoucheStorageServer(kind: .drive, name: ""))
            }
        case "storage-drive-guide":
            NavigationStack {
                CartoucheDriveGuideView()
            }
        case "storage-names":
            // As the Storage page opens it.
            NavigationStack {
                CartoucheNamingView(opening: scenario.category.flatMap(CartoucheNaming.Place.init(rawValue:)))
            }
        case "telemetry":
            NavigationStack {
                CartoucheTelemetryView()
            }
            .preferredColorScheme(.dark)
        case "report":
            NavigationStack {
                CartoucheReportView()
            }
        case "release-notes":
            // As the System page opens it.
            NavigationStack {
                CartoucheReleaseNotesView(notes: Array(CartoucheWhatsNew.carried.prefix(CartoucheWhatsNew.listed)))
            }
            .preferredColorScheme(.dark)
        case "reset", "reset-end":
            // As the System page opens it, or at its end.
            NavigationStack {
                CartoucheResetView(confirming: scenario.work == "confirm", showsEnd: scenario.screen == "reset-end")
            }
        case "switch-save":
            // The game's saves between the Switch and this iPhone, from its
            // sheet: with work: saves, the save JKSV exported, read.
            if let entry = entries.owned.first(where: { $0.titleId == (scenario.sheet ?? scenario.ownedTitles.first) }),
               let app = entry.app {
                NavigationStack {
                    CartoucheSwitchSaveView(game: CartoucheSwitchSaveGame(name: entry.name, titleId: entry.titleId, version: "1.0.0",
                                                                          isSwitch2: entry.platform == "switch2",
                                                                          target: GallerySaves.target(of: app),
                                                                          makeTarget: { GallerySaves.target(of: app) },
                                                                          isRunningNow: { false }),
                                            isRunning: false)
                }
            }
        case "root":
            CartoucheRootView()
        case "tv":
            if #available(iOS 18.0, *) {
                if let entry = entries.owned.first(where: { $0.titleId == (scenario.sheet ?? scenario.ownedTitles.first) }) {
                    CartoucheTVCard(model: tvCard(for: entry))
                }
            }
        default:
            CartoucheGamesView()
        }
    }

    /// The TV's card for ENTRY's game, as the scenario has it: on screen,
    /// paused or starting.
    @available(iOS 18.0, *)
    @MainActor
    private func tvCard(for entry: CartoucheEntry) -> CartoucheTVCardModel {
        let card = CartoucheTVCardModel()
        card.show(name: entry.name, cover: entry.coverArt, backdrop: entry.backdrop, colorKey: entry.tileKey)
        switch scenario.work {
        case "paused": card.status = .paused
        case "starting": card.status = .starting
        default: card.status = .playing
        }
        return card
    }

    /// The game's settings, on the scenario's category.
    private func settings(for app: LCAppModel, entry: CartoucheEntry) -> CartoucheGameSettingsModel {
        let settings = CartoucheGameActions.shared.settings(for: app, tileKey: entry.tileKey)
        settings.category = scenario.category
        return settings
    }
}

/// A game's sheet, with Cartouche's own memory as the console has it
/// (CartoucheGamesView): measured as it opens, and again for a while
/// after (CartoucheOwnMemoryWatch).
struct GallerySheetScreen: View {
    let entry: CartoucheEntry
    let opensOnManagement: Bool
    @State private var memory = CartoucheMemoryReading.now()

    var body: some View {
        NavigationStack {
            CartoucheGameSheetView(entry: entry, memory: memory, onPlay: { _ in },
                                   onSettings: { _ in }, onImport: {}, onUninstall: { _ in },
                                   opensOnManagement: opensOnManagement)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(CartoucheText.done) {}
                    }
                }
        }
        .modifier(CartoucheOwnMemoryWatch(memory: $memory))
    }
}

/// The player's Mac with Cartouche Builder, as the gallery shows it: found
/// by Bonjour beside another Mac of the house, then paired. Made-up names,
/// ID and address.
enum GalleryMac {
    static let id = "6f1c2b9e-4d3a-4c8e-9b71-2a5d8e0f3c47"

    static let nearby = [
        CartoucheNearbyMac(name: "MacBook Air", macID: id, endpoint: service("MacBook Air")),
        CartoucheNearbyMac(name: "Mac mini", macID: "c2e7a4d1-8b5f-4e3a-a6d9-1f4b7c0e9a28", endpoint: service("Mac mini")),
    ]

    /// The same Macs with this iPhone plugged into the MacBook Air by a
    /// cable, which Bonjour does not find on this network (work: mac-cable).
    static let cabled = [
        CartoucheNearbyMac(name: "MacBook Air", macID: id, endpoint: nil, cabled: true),
        nearby[1],
    ]

    /// The Mac's addresses in the player's tailnet, as its Cartouche Builder
    /// tells them with Tailscale on: made up, never the project's.
    static let tailnet = ["100.101.102.103", "fd7a:115c:a1e0::1"]

    /// The Mac as Cartouche keeps it once paired, at the address it last
    /// reached it at.
    static func paired() -> CartoucheStorageServer {
        CartoucheStorageServer(kind: .mac, name: "MacBook Air", host: "192.168.1.20", port: Int(CartoucheBridge.port), macID: id)
    }

    /// Cartouche Builder at work on the Mac, as it tells Cartouche (work:
    /// mac-builds): Mario Kart World building, its IPA for the iPhone, then
    /// its app for the Mac; Donkey Kong Bananza waiting its turn, for both;
    /// Link's Awakening built for the iPhone this morning; and games the
    /// player has not installed: one whose last build failed yesterday,
    /// one nxnative improved since its last build, one the Mac does not
    /// follow, one whose app for the Mac failed since its IPA was built,
    /// one whose app for the Mac is to build, its IPA up to date, and one
    /// built for the Mac alone (decision 127). What is due built every
    /// night at 3:30. Its words in the gallery's language, as a Mac in
    /// that language says them (stageText in the Mac's Theme.swift).
    static func builds(now: Date = Date()) -> CartoucheBridgeBuilds {
        let hour: TimeInterval = 3_600
        let french = CartoucheText.bundle.preferredLocalizations.first == "fr"
        let both = ["ios", "mac"]
        return CartoucheBridgeBuilds(running: true, games: [
            .init(id: "0400C3F00006E000", name: "Mario Kart World", state: "building", reasons: ["changes"],
                  progress: 0.42, step: french ? "Compilation des shaders pour l’iPhone" : "Compiling shaders for the iPhone",
                  left: 21 * 60, built: now.addingTimeInterval(-3 * 24 * hour), followed: true, stoppable: true, stopping: false,
                  platforms: both, makes: both, now: "ios",
                  mac: CartoucheBridgeBuilds.MacApp(built: now.addingTimeInterval(-3 * 24 * hour + 1_800))),
            .init(id: "040074A01BF12000", name: "Donkey Kong Bananza", state: "queued", reasons: ["changes"], turn: 1,
                  built: now.addingTimeInterval(-6 * 24 * hour), followed: true, stoppable: true, stopping: false,
                  platforms: both, makes: both, mac: CartoucheBridgeBuilds.MacApp(built: now.addingTimeInterval(-6 * 24 * hour + 2_400))),
            .init(id: "01006BB00C6F0000", name: "The Legend of Zelda: Link's Awakening", state: "up_to_date",
                  built: now.addingTimeInterval(-9 * hour), followed: true, platforms: ["ios"]),
            .init(id: "01003FC01670C000", name: "13 Sentinels: Aegis Rim", state: "failed",
                  failed: now.addingTimeInterval(-26 * hour),
                  error: french ? "La construction de l’app s’est arrêtée\u{00A0}: Xcode n’a trouvé aucun SDK iOS."
                                : "Building the app stopped: Xcode found no iOS SDK.",
                  followed: true, platforms: ["ios"]),
            .init(id: "0100B7C00933A000", name: "Pikmin 4", state: "due", reasons: ["changes"],
                  built: now.addingTimeInterval(-12 * 24 * hour), followed: true,
                  platforms: both, mac: CartoucheBridgeBuilds.MacApp(built: now.addingTimeInterval(-12 * 24 * hour + 1_500))),
            .init(id: "0100000000010000", name: "Super Mario Odyssey", state: "not_followed",
                  built: now.addingTimeInterval(-20 * 24 * hour), followed: false, platforms: ["ios"]),
            .init(id: "01004D300C5AE000", name: "Kirby and the Forgotten Land", state: "up_to_date",
                  built: now.addingTimeInterval(-20 * hour), followed: true, platforms: both,
                  mac: CartoucheBridgeBuilds.MacApp(built: now.addingTimeInterval(-8 * 24 * hour), failed: now.addingTimeInterval(-19 * hour),
                             error: french ? "Les shaders pour le Mac n’ont pas pu être compilés\u{00A0}: Metal a refusé un pipeline."
                                           : "The shaders for the Mac could not be compiled: Metal refused a pipeline.")),
            .init(id: "010093801237C000", name: "Metroid Dread", state: "up_to_date",
                  built: now.addingTimeInterval(-2 * 24 * hour), followed: true, platforms: both, mac: CartoucheBridgeBuilds.MacApp(due: true)),
            .init(id: "0400380020056000", name: "Splatoon Raiders", state: "up_to_date",
                  built: now.addingTimeInterval(-4 * 24 * hour), followed: true, platforms: ["mac"]),
        ], due: 2, nightly: CartoucheBridgeBuilds.Nightly(on: true, hour: 3, minute: 30))
    }

    private static func service(_ name: String) -> NWEndpoint {
        .service(name: name, type: CartoucheBridge.serviceType, domain: "local.", interface: nil)
    }
}

/// The saves of a game of the player's and the saves folder they are kept
/// in step with, a folder in Files as the player picks one, both in the
/// gallery's Application Support (work: saves): Cartouche's own sync and
/// copies run on them, as on an iPhone, with nothing stood in for but the
/// game's data folder, which LiveContainer gives a game.
enum GallerySaves {
    /// The folder's name, as the Storage page and the sheet show it: a
    /// name a player gives theirs, rather than the gallery's own.
    static let folderName = "NAS"

    /// Whether the sheet is on its way down to its saves, which the
    /// screenshot waits for (GalleryScenario.settle).
    @MainActor static var bringingDown = false

    /// Brings the sheet down to the row of the Switch saves, in the middle
    /// of the screen, with SCROLLTO, SwiftUI's scroll to it: a few times, as
    /// the gallery's first seconds can hold the main thread for a second or
    /// more; else by hand, down the list until it has laid the row out, then
    /// to the row. A single scroll half a second after the sheet showed left
    /// it at its top (run 43548937064).
    @MainActor
    static func bringDown(_ scrollTo: @escaping @MainActor () -> Void) async {
        defer { bringingDown = false }
        for _ in 0..<5 where !rowInTheMiddle {
            try? await Task.sleep(for: .milliseconds(300))
            scrollTo()
        }
        for _ in 0..<40 where !rowInTheMiddle {
            guard let list = collectionView(), list.bounds.height > 0 else { break }
            let shown = list.convert(list.bounds, to: nil)
            let by = CartoucheSavesSection.galleryRowFrame.map { $0.midY - shown.midY } ?? list.bounds.height * 0.6
            let end = max(0, list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height)
            let y = min(end, max(-list.adjustedContentInset.top, list.contentOffset.y + by))
            guard abs(y - list.contentOffset.y) >= 1 else { break }
            list.setContentOffset(CGPoint(x: list.contentOffset.x, y: y), animated: false)
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .milliseconds(300))
        if !rowInTheMiddle {
            NSLog("[Gallery] the sheet did not come down to the row of the Switch saves")
        }
    }

    /// Whether the row of the Switch saves is in the middle three fifths of
    /// the list on the screen.
    @MainActor
    private static var rowInTheMiddle: Bool {
        guard let row = CartoucheSavesSection.galleryRowFrame, let list = collectionView() else { return false }
        let shown = list.convert(list.bounds, to: nil)
        return row.minY >= shown.minY + shown.height / 5 && row.maxY <= shown.maxY - shown.height / 5
    }

    /// The collection view of the list on the screen, a SwiftUI list's.
    @MainActor
    private static func collectionView() -> UICollectionView? {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first else { return nil }
        return collectionView(in: window)
    }

    @MainActor
    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        for subview in view.subviews {
            if let list = collectionView(in: subview) { return list }
        }
        return nil
    }

    /// The game whose saves these are, once the scenario has them.
    @MainActor private static var titleId: String?

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GallerySaves", isDirectory: true)
    }

    /// The game's Documents, where nxnative keeps its saves.
    private static var documents: URL { root.appendingPathComponent("Game/Documents", isDirectory: true) }

    /// Puts a save in the Documents of the game of TITLEID, as nxnative
    /// writes one, and the folder in Files in its place as the saves folder,
    /// with nothing in it yet.
    @MainActor
    static func prepare(titleId: String) {
        let manager = FileManager.default
        try? manager.removeItem(at: root)
        let save = documents.appendingPathComponent("save/0000000000000001", isDirectory: true)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        do {
            try manager.createDirectory(at: save, withIntermediateDirectories: true)
            try manager.createDirectory(at: folder.appendingPathComponent("Saves", isDirectory: true),
                                        withIntermediateDirectories: true)
            // Two MiB of a game's progress, which compresses as little as a
            // real save.
            var progress = Data(count: 2 << 20)
            progress.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
            try progress.write(to: save.appendingPathComponent("progress.bin"))
            let server = CartoucheStorageServer(kind: .folder, name: folderName, bookmark: try CartoucheFolder.bookmark(of: folder))
            CartoucheStorageSettings.shared.showForGallery(server, games: "", saves: "Saves")
            self.titleId = titleId
            switchExportWritten = Task { await writeSwitchExport(titleId: titleId) }
        } catch {
            NSLog("[Gallery] cannot make the saves and their folder: %@", String(describing: error))
        }
    }

    /// The save JKSV exported on the Switch that the gallery offers, a ZIP
    /// archive of the scenario's game's in its Documents, which the Files
    /// picker shows under On My iPhone › Gallery; the UI tests pick the same
    /// that uitests.sh puts in On My iPhone itself. Named as JKSV names its
    /// exports, the player and the time: no label of the page under the
    /// picker begins as it does, which the UI tests would tap for the file
    /// (FilesPicker.pick), as they tapped the page's title, Switch saves,
    /// for "Switch save.zip".
    static let switchExportName = "Player - 2026-11-13_15-20-00.zip"
    @MainActor private static var switchExportWritten: Task<URL?, Never>?

    /// The save JKSV exported, once written.
    @MainActor
    static func switchExport() async -> URL? {
        await switchExportWritten?.value
    }

    /// Writes a save of the game TITLEID as JKSV exports one: its fiche, a
    /// file and a folder with a file.
    private static func writeSwitchExport(titleId: String) async -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent(switchExportName)
        var fiche = [UInt8](repeating: 0, count: CartoucheSwitchSaveMeta.size)
        let id = UInt64(titleId, radix: 16) ?? 0
        for index in 0 ..< 4 { fiche[index] = UInt8(truncatingIfNeeded: CartoucheSwitchSaveMeta.magic >> (8 * UInt32(index))) }
        fiche[4] = 1
        for index in 0 ..< 8 { fiche[5 + index] = UInt8(truncatingIfNeeded: id >> (8 * UInt64(index))) }
        fiche[37] = 1   // a player's save
        do {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            let sink = try CartoucheFileSink(url)
            let writer = CartoucheZipWriter(sink: sink)
            try await writer.addData(CartoucheSwitchSaveMeta.fileName, Data(fiche))
            var progress = Data(count: 1 << 20)
            progress.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
            try await writer.addData("progress.bin", progress)
            try await writer.addFolder("slots/")
            try await writer.addData("slots/1.bin", Data("slot 1".utf8))
            try await writer.finish()
            try sink.close()
            return url
        } catch {
            NSLog("[Gallery] cannot write %@: %@", switchExportName, String(describing: error))
            return nil
        }
    }

    /// The saves of APP, if it is the scenario's game.
    @MainActor
    static func target(of app: LCAppModel) -> CartoucheSaveTarget? {
        guard let titleId, app.appInfo.relativeBundlePath == titleId + ".app",
              let bundleId = app.appInfo.bundleIdentifier() else { return nil }
        return CartoucheSaveTarget(key: bundleId + "|gallery", name: app.displayName, titleId: titleId, documents: documents)
    }
}
