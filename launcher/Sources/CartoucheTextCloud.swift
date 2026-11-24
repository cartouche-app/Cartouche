//
//  CartoucheTextCloud.swift
//  Cartouche
//
//  The words of Cartouche Cloud (CartoucheCloudPage.swift,
//  CartoucheCloudLink.swift, CartoucheCloud.swift), in Cartouche.xcstrings
//  with the others (CartoucheText.swift), which says the few the console
//  shares with the Mac: a game built, in the library and on its sheet. What
//  the platform says in codes, Cartouche says in the words the site's pages
//  say it in (build.cartouche.cloud), and a price as the site writes it, in
//  dollars: "$2.50", "2,50 $".
//
//  The iPhone's alone, as Cartouche Cloud is.
//

import Foundation

extension CartoucheText {
    // MARK: System

    static var cloudNotLinked: String { s("cloud.state.notLinked", "Not linked") }
    static var cloudLinked: String { s("cloud.state.linked", "Linked") }
    static var cloudUnderWay: String { s("cloud.state.underWay", "Building") }
    static func cloudBuiltCount(_ count: Int) -> String {
        count == 1 ? s("cloud.state.built.one", "1 game to install") : f("cloud.state.built", "%lld games to install", count)
    }

    // MARK: What it is

    static var cloudHeadline: String { s("cloud.headline", "Your game, built for you, without a Mac.") }
    static var cloudIntro: String { s("cloud.intro", "Cartouche Cloud takes a game you own, builds it on a Mac in the cloud, and gives you back the app Cartouche installs on your iPhone. It provides no game: you send your own copy from a computer, on its site, and it is built for you alone.") }
    static func cloudPrice(_ price: String) -> String { f("cloud.price", "%@ per game built, nothing for a build that fails.", price) }
    static var cloudInvitation: String { s("cloud.invitation", "Cartouche Cloud is in a closed trial: for now, only invited players can use it.") }
    static var cloudReaching: String { s("cloud.reaching", "Reaching Cartouche Cloud…") }
    static var cloudSignUp: String { s("cloud.signUp", "Make an account on the site") }
    static var cloudSignIn: String { s("cloud.signIn", "Sign in on the site") }
    static var cloudUnlinkedElsewhere: String { s("cloud.unlinkedElsewhere", "Cartouche Cloud no longer knows this iPhone: it was unlinked on the site, or its account deleted. Link it again with a new code.") }

    /// Why no build starts now, whatever the queue holds.
    static func cloudIdle(_ idle: CartoucheCloudIdle) -> String {
        switch idle {
        case .paused: return s("cloud.idle.paused", "Builds are paused for now: the games in the queue wait.")
        case .unset: return s("cloud.idle.unset", "This copy of Cartouche Cloud builds no game yet: a game you send waits in the queue.")
        }
    }

    // MARK: Linking this iPhone

    static var cloudLinkHeader: String { s("cloud.link.header", "Link this iPhone") }
    static var cloudCodePlaceholder: String { s("cloud.code.placeholder", "Code from your account’s page") }
    static var cloudLink: String { s("cloud.link", "Link") }
    static var cloudGetCode: String { s("cloud.getCode", "Get a code on the site") }
    static var cloudLinkFooter: String { s("cloud.link.footer", "On the site, Link Cartouche on your account’s page gives a code valid ten minutes: type it here. Opened on this iPhone, that page fills it in for you with Open in Cartouche.") }

    /// Why the platform said no, or could not be heard: to a code, to the
    /// account's games, to an IPA, or to Unlink.
    static func cloudRefused(_ kind: CartoucheCloudError.Kind) -> String {
        switch kind {
        case .code: return s("cloud.refused.code", "This code links nothing: it may be mistyped, past its ten minutes, or used already. Your account’s page gives another.")
        case .full: return s("cloud.refused.full", "Your account has as many devices linked as it can: unlink one on its page, then try again.")
        case .unlinked: return s("cloud.refused.unlinked", "This iPhone is no longer linked to your Cartouche Cloud account: link it again in System › Cartouche Cloud.")
        case .missing: return s("cloud.refused.missing", "Cartouche Cloud no longer has this game: it deletes a game two days after building it.")
        case .storage: return s("cloud.refused.storage", "Cartouche Cloud cannot hand out its games for now: try again later.")
        case .expired: return s("cloud.refused.expired", "The download address of this game expired: install it again.")
        case .offline: return s("cloud.refused.offline", "This iPhone is offline: connect it to the internet, then try again.")
        case .network: return s("cloud.refused.network", "Cartouche Cloud could not be reached: try again in a moment.")
        case .server: return s("cloud.refused.server", "Cartouche Cloud did not answer as expected: try again in a moment.")
        }
    }

    // MARK: The account

    static var cloudAccountHeader: String { s("cloud.account.header", "Your account") }
    static var cloudCredits: String { s("cloud.credits", "Credits") }
    static func cloudHeld(_ held: String, _ available: String) -> String {
        f("cloud.credits.held", "%1$@ of them are held for your games under way: you have %2$@ left to send others.", held, available)
    }
    static func cloudPriceFooter(_ price: String) -> String { f("cloud.price.footer", "A build costs %@: held while it runs, taken if it succeeds, given back otherwise.", price) }

    /// CENTS of a dollar, as the site writes them: "$2.50", "2,50 $".
    static func cloudMoney(_ cents: Int) -> String {
        let amount = (Double(cents.magnitude) / 100).formatted(.number.precision(.fractionLength(2)).locale(locale))
        return (cents < 0 ? "−" : "") + f("cloud.dollars", "$%@", amount)
    }

    // MARK: The account's games

    static var cloudGamesHeader: String { s("cloud.games.header", "Your games") }
    static var cloudGamesReading: String { s("cloud.games.reading", "Reading your games…") }
    static var cloudGamesNone: String { s("cloud.games.none", "You have sent no game yet: send one from a computer, on the site.") }
    static var cloudGamesFooter: String { s("cloud.games.footer", "You get an email as soon as a game is built, and it shows in your library: install it from there or from here.") }
    static var cloudGameInstall: String { s("cloud.game.install", "Install") }
    static var cloudGameOnIPhone: String { s("cloud.game.onIPhone", "On this iPhone") }

    /// Where a game is, in a word or two, as the site's list says it.
    static func cloudGameState(_ state: CartoucheCloudGame.State) -> String {
        switch state {
        case .open: return s("cloud.game.state.open", "Sending")
        case .queued: return s("cloud.game.state.queued", "In the queue")
        case .building: return s("cloud.game.state.building", "Being built")
        case .built: return s("cloud.game.state.built", "Built")
        case .failed: return s("cloud.game.state.failed", "Not built")
        case .other: return s("cloud.game.state.other", "On the site")
        }
    }

    static func cloudGameOpen(_ moment: String) -> String { f("cloud.game.open", "Give the same file again on the site before %@ to go on sending it.", moment) }
    static func cloudGamePlace(_ place: Int) -> String { f("cloud.game.place", "Place %lld in the queue.", place) }
    static var cloudGameBehind: String { s("cloud.game.behind", "It is built after your game being built now: one build at a time for an account.") }
    static func cloudGameUsual(_ time: String) -> String { f("cloud.game.usual", "A build of this game usually takes about %@.", time) }
    static func cloudGameLeft(_ time: String) -> String { f("cloud.game.left", "About %@ to go.", time) }
    static var cloudGameLonger: String { s("cloud.game.longer", "It is taking longer than usual.") }
    static func cloudGameKept(_ moment: String) -> String { f("cloud.game.kept", "Kept until %@, then deleted.", moment) }
    static var cloudGameElsewhere: String { s("cloud.game.elsewhere", "Cartouche does not know this state yet: the site says where the game is.") }

    /// The step of a build, as the track names it, from 0
    /// (CartoucheCloud.trackSteps).
    static func cloudTrackStep(_ number: Int, _ count: Int, _ name: String) -> String {
        f("cloud.track.step", "Step %1$lld of %2$lld · %3$@", number, count, name)
    }
    static func cloudTrackName(_ stage: Int) -> String {
        switch stage {
        case ...0: return s("cloud.track.wait", "Waiting")
        case 1: return s("cloud.track.ready", "Getting ready")
        case 2: return s("cloud.track.fetch", "Fetching")
        case 3: return s("cloud.track.unpack", "Unpacking")
        case 4: return s("cloud.track.build", "Building")
        default: return s("cloud.track.back", "Sending back")
        }
    }

    /// Why a game was not built, by the platform's code: a code this
    /// Cartouche does not know reads as the Mac's, as on the site.
    static func cloudCause(_ cause: String?) -> String {
        switch cause {
        case "unpack": return s("cloud.cause.unpack", "The Mac could not unpack the game you sent. Send it again from your game’s files.")
        case "plan": return s("cloud.cause.plan", "Cartouche Cloud cannot build this game as it was sent: its dump may be incomplete, or its version may be one nxnative does not build yet.")
        case "build": return s("cloud.cause.build", "nxnative did not manage to build this game. This happens with some games and some of their versions: it may build after an update of nxnative.")
        case "ipa": return s("cloud.cause.ipa", "The build ended without the app it should have made.")
        case "late": return s("cloud.cause.late", "Cartouche Cloud did not get to build it before the time it deletes it.")
        case "stopped": return s("cloud.cause.stopped", "Cartouche Cloud stopped this build before its end. Your game has nothing to do with it.")
        default: return s("cloud.cause.mac", "The Mac that was building it stopped before the end. Your game has nothing to do with it.")
        }
    }

    /// What is left to the player of a build that failed, until MOMENT.
    static func cloudLeft(_ left: String?, _ moment: String) -> String? {
        switch left {
        case "again": return f("cloud.left.again", "You can start the build again on the site until %@.", moment)
        case "mended": return f("cloud.left.mended", "Cartouche Cloud now builds with another version of nxnative: you can start the build again on the site until %@.", moment)
        case "held": return f("cloud.left.held", "What you sent is kept until %@, then deleted.", moment)
        case "over": return f("cloud.left.over", "What you sent is kept until %@, then deleted. To try again, send it again.", moment)
        default: return nil
        }
    }

    // MARK: The site, and Unlink

    static var cloudSiteGames: String { s("cloud.site.games", "Your games on the site") }
    static var cloudSiteAccount: String { s("cloud.site.account", "Your account on the site") }
    static var cloudSiteFooter: String { s("cloud.site.footer", "You send a game from a computer, on the site, where your credits and your account are too.") }
    static var cloudUnlink: String { s("cloud.unlink", "Unlink this iPhone") }
    static var cloudUnlinkQuestion: String { s("cloud.unlink.question", "Unlink this iPhone?") }
    static var cloudUnlinkMessage: String { s("cloud.unlink.message", "Cartouche no longer follows your account’s games here, and your account’s page no longer lists this iPhone. The games installed stay.") }
    static var cloudUnlinkConfirm: String { s("cloud.unlink.confirm", "Unlink") }
    static var cloudUnlinkFooter: String { s("cloud.unlink.footer", "Linked, this iPhone reads your account’s games and fetches those built, nothing more: sending a game, your credits and your account stay on the site.") }
}
