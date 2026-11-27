//
//  GalleryCloud.swift
//  CartoucheGallery
//
//  Cartouche Cloud as the gallery shows it (screen cloud, works cloud-*):
//  what the service tells anyone, and the account this iPhone is linked
//  to, with a game at each stage, in place of the platform's answers, which
//  the gallery never asks (CartoucheCloudLink.showForGallery). Made-up IDs
//  and code; the games are nxnative's.
//

import Foundation

enum GalleryCloud {
    /// What the service tells anyone: an account by invitation, builds
    /// under way, $2.50 a build.
    static let service = CartoucheCloudService(signup: .invitation, idle: nil, price: 250)

    /// The code of the account's page, as its Open in Cartouche gives it.
    static let code = "K7QM4XPA"

    /// The account, $12.50 of credits, $2.50 of them held for the game
    /// being built: 13 Sentinels built, its IPA there for 45 hours more;
    /// Mario Kart World built yesterday, and installed on this iPhone since,
    /// one of the player's games;
    /// Ocarina of Time being built, at its fifth step of six, 25 minutes
    /// into a build that usually takes 40, its Mac compiling its shaders
    /// for the iPhone, 42% of them, 25 minutes left of it as the builder
    /// says, its files ready in 5 minutes 30; Animal Crossing waiting for it,
    /// one build at a time for an account; and Balatro, which nxnative did
    /// not manage to build, to start again on the site within two days.
    /// 13 Sentinels built from ENGINE: nxnative, unless the work says
    /// nxnative-nobc, for an iPhone 11 to 15 (cloud-gpu-no-bc-converted).
    static func account(now: Date = Date(), engine: String = "nxnative") -> CartoucheCloudAccount {
        let hour: TimeInterval = 3_600
        let games = [
            CartoucheCloudGame(id: "a3f1c9e27b4d4e18a6c05d9f3e7b2c41", title: "0400486024dec000",
                               name: "The Legend of Zelda: Ocarina of Time", state: .building, price: 250,
                               expiresAt: now.addingTimeInterval(47 * hour), stage: 4, usual: 2_400,
                               step: "build", launchedAt: now.addingTimeInterval(-25 * 60),
                               phase: "shaders", phasedAt: now.addingTimeInterval(-12 * 60), phaseDone: 0.42,
                               phaseLeft: 1_520, reportedAt: now.addingTimeInterval(-20), phases: ["files": 330]),
            CartoucheCloudGame(id: "c81e4b07f2a94d3c9e6b5a1d0f8c7e23", title: "01006f8002326000",
                               name: "Animal Crossing: New Horizons", state: .queued, price: 250,
                               expiresAt: now.addingTimeInterval(47 * hour), stage: 0, usual: 1_800, behind: true),
            CartoucheCloudGame(id: "5d2a7f9c1e3b4a6d8c0e2f4a6b8d0c1e", title: "01003fc01670c000",
                               name: "13 Sentinels: Aegis Rim", state: .built, price: 250,
                               expiresAt: now.addingTimeInterval(45 * hour), bytes: 6_812_495_872,
                               file: "13 Sentinels Aegis Rim [01003FC01670C000].ipa", builtAt: now.addingTimeInterval(-3 * hour),
                               engine: engine),
            CartoucheCloudGame(id: "9b4e2c7a0d1f4b8e93a6c5d2e1f0a7b4", title: "0400c3f00006e000",
                               name: "Mario Kart World", state: .built, price: 250,
                               expiresAt: now.addingTimeInterval(20 * hour), bytes: 24_418_369_536,
                               file: "Mario Kart World [0400C3F00006E000].ipa", builtAt: now.addingTimeInterval(-28 * hour)),
            CartoucheCloudGame(id: "e47b0a3d9c2f4e1a8b6d5c3f2a1e0d9b", title: "0100cd801ce5e000",
                               name: "Balatro", state: .failed, price: 250,
                               expiresAt: now.addingTimeInterval(44 * hour), cause: "build", left: "again",
                               until: now.addingTimeInterval(44 * hour)),
        ]
        return CartoucheCloudAccount(games: games,
                                     credits: CartoucheCloudCredits(balance: 1_250, held: 250, available: 1_000, price: 250),
                                     idle: nil)
    }

    /// What WORK shows of Cartouche Cloud, or the page of SCREEN cloud: the
    /// account's games (cloud-games), on an iPhone whose GPU reads no
    /// BC-compressed texture (cloud-gpu-no-bc), 13 Sentinels built from
    /// nxnative-nobc there (cloud-gpu-no-bc-converted), one of them being
    /// installed from it (cloud-installing), the code of the account's page linking this
    /// iPhone (cloud-linking) or refused (cloud-refused); what the service
    /// tells an iPhone not linked yet, on the page, or wherever the page
    /// opens from (cloud-service), as from the guide.
    @MainActor
    static func show(screen: String, work: String?) {
        let link = CartoucheCloudLink.shared
        switch work {
        case "cloud-games", "cloud-installing", "cloud-gpu-no-bc":
            link.showForGallery(linked: true, service: service, account: account())
        case "cloud-gpu-no-bc-converted":
            link.showForGallery(linked: true, service: service, account: account(engine: "nxnative-nobc"))
        case "cloud-linking":
            link.showForGallery(linked: false, service: service, account: nil, pendingCode: code, busy: .linking)
        case "cloud-refused":
            link.showForGallery(linked: false, service: service, account: nil, pendingCode: code,
                                refusal: CartoucheCloudError(.code))
        case "cloud-service":
            link.showForGallery(linked: false, service: service, account: nil)
        default:
            guard screen == "cloud" else { return }
            link.showForGallery(linked: false, service: service, account: nil)
        }
        if work == "cloud-installing", let built = link.builtGames.first {
            // As from iOS 26, which goes on with it outside Cartouche.
            let place = CartoucheText.cloudName
            CartoucheGameActions.shared.work = CartoucheGameWork(kind: .installing, name: built.name,
                                                                 step: CartoucheText.installFromStorageStep(place),
                                                                 fraction: 0.42, stage: "unpacking", place: place,
                                                                 outside: true)
        }
    }
}
