//
//  ConsoleGuide.swift
//  Cartouche on the Mac
//
//  The first game's guide in the console on the Mac, as the iPhone's
//  (CartoucheGuide.swift, CartoucheGuideView.swift) is in Cartouche: three
//  steps from a new Cartouche Builder to a game played on this Mac, each
//  ticked from what the app sees, in any order: this Mac made ready by the
//  Builder's setup assistant, a game built for this Mac in the games
//  folder, a game started from the console. Its card shows at the top of
//  the console's home until the first game is played there, unless the
//  player takes it off (CartoucheGuideCard.swift, the iPhone's); System ›
//  Your first game opens it at any time.
//

import SwiftUI

@MainActor
final class CartoucheGuide: ObservableObject {
    static let shared = CartoucheGuide()

    enum Step: Int, CaseIterable, Identifiable {
        case setup, build, play

        var id: Int { rawValue }
        var number: Int { rawValue + 1 }
    }

    /// What the steps read: the Builder's setup, the games built for this
    /// Mac, and whether one was played.
    struct Progress: Equatable {
        /// The setup assistant gone through to its end.
        var isSetUp = false
        /// A game built for this Mac, in the games folder.
        var hasGame = false
        /// A game started from the console, or with play time on this Mac.
        var hasPlayed = false

        /// The steps, in their order: the Mac's guide leaves none out.
        var steps: [Step] { Step.allCases }

        /// STEP's number among them.
        func number(of step: Step) -> Int { step.number }

        func isDone(_ step: Step) -> Bool {
            switch step {
            // A game built here, or played, says this Mac was made ready.
            case .setup: return isSetUp || hasGame || hasPlayed
            case .build: return hasGame || hasPlayed
            case .play: return hasPlayed
            }
        }

        /// The first step left, nil once every step is done.
        var current: Step? { steps.first { !isDone($0) } }
        var isFinished: Bool { current == nil }
    }

    /// Whether a game was started from the console once: the guide's last
    /// step, and the card leaves the home for good.
    @Published private(set) var hasPlayed: Bool
    /// Whether the player took the guide's card off the home.
    @Published private(set) var isCardHidden: Bool

    private let defaults: UserDefaults
    private static let playedKey = "Console.guide.played"
    private static let cardHiddenKey = "Console.guide.cardHidden"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasPlayed = defaults.bool(forKey: Self.playedKey)
        isCardHidden = defaults.bool(forKey: Self.cardHiddenKey)
    }

    /// Whether a game's play time on this Mac says it was played: not in
    /// the gallery's pictures of the guide, whose sheets show made-up time.
    private var countsPlayTime = true

    /// Where the player is: the home passes its games, which the Mac's
    /// guide reads in the console itself.
    func progress(_ entries: CartoucheCatalog.Entries? = nil) -> Progress {
        let console = CartoucheMacConsole.shared
        return Progress(isSetUp: console.isSetUp, hasGame: !console.apps.isEmpty,
                        hasPlayed: hasPlayed || (countsPlayTime && !CartoucheGameStats.shared.record.games.isEmpty))
    }

    /// The card stays at the top of the home until the first game is
    /// played, unless the player took it off.
    func showsCard(_ progress: Progress) -> Bool {
        !isCardHidden && !progress.hasPlayed
    }

    /// The card's ×: the System page opens the guide from then on.
    func hideCard() {
        isCardHidden = true
        defaults.set(true, forKey: Self.cardHiddenKey)
    }

    /// The console's Play started a game.
    func notePlayed() {
        guard !hasPlayed else { return }
        hasPlayed = true
        defaults.set(true, forKey: Self.playedKey)
    }

    /// For the gallery: the guide of a player who has played a game here
    /// (PLAYED), or none yet, whose card is on the home; nothing kept.
    func showForGallery(played: Bool) {
        hasPlayed = played
        isCardHidden = false
        countsPlayTime = played
    }
}

/// The guide's page in the console, from System › Your first game or from
/// the card on the home: its steps, the one left first with its action,
/// those done ticked.
struct CartoucheGuideView: View {
    typealias Step = CartoucheGuide.Step

    @ObservedObject private var guide = CartoucheGuide.shared
    @ObservedObject private var console = CartoucheMacConsole.shared
    @ObservedObject private var stats = CartoucheGameStats.shared
    /// Back to the console's home, for the step of the first game played.
    let onConsole: () -> Void

    init(onConsole: @escaping () -> Void) {
        self.onConsole = onConsole
    }

    var body: some View {
        let progress = guide.progress()
        List {
            Section {
                Text(progress.isFinished ? CartoucheText.macGuideFinished : CartoucheText.macGuideIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(progress.steps) { step in
                Section {
                    row(step, progress: progress)
                }
            }
        }
        .tint(.primary)
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.guideTitle)
    }

    private func row(_ step: Step, progress: CartoucheGuide.Progress) -> some View {
        let done = progress.isDone(step)
        let current = progress.current == step
        return HStack(alignment: .top, spacing: 14) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.green)
                } else {
                    Text(String(step.number))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(current ? CartoucheTheme.indigo : Color.white.opacity(0.18), in: Circle())
                }
            }
            .frame(width: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.title(step))
                    .font(.headline)
                    .foregroundStyle(done ? .secondary : .primary)
                Text(Self.detail(step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if current {
                    Button(Self.action(step)) { act(step) }
                        .controlSize(.large)
                        .cartouchePrimaryButton()
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide.mac." + String(step.number))
    }

    private func act(_ step: Step) {
        switch step {
        case .setup: console.onSetup()
        case .build: console.onImport()
        case .play: onConsole()
        }
    }

    /// The step's title, on its row and on the home's card.
    static func title(_ step: Step) -> String {
        switch step {
        case .setup: return CartoucheText.macGuideSetupTitle
        case .build: return CartoucheText.macGuideBuildTitle
        case .play: return CartoucheText.macGuidePlayTitle
        }
    }

    static func detail(_ step: Step) -> String {
        switch step {
        case .setup: return CartoucheText.macGuideSetupDetail
        case .build: return CartoucheText.macGuideBuildDetail
        case .play: return CartoucheText.macGuidePlayDetail
        }
    }

    static func action(_ step: Step) -> String {
        switch step {
        case .setup: return CartoucheText.macGuideSetupAction
        case .build: return CartoucheText.macGuideBuildAction
        case .play: return CartoucheText.macGuidePlayAction
        }
    }
}

extension CartoucheText {
    static var macGuideIntro: String {
        s("mac.guide.intro", "Three steps to a first game on this Mac. Each ticks itself once done, in any order.")
    }
    static var macGuideFinished: String {
        s("mac.guide.finished", "This Mac is ready, and your first game played: the games you build next come to the console by themselves.")
    }
    static var macGuideSetupTitle: String { s("mac.guide.setup.title", "Make this Mac ready") }
    static var macGuideSetupDetail: String {
        s("mac.guide.setup.detail",
          "Cartouche Builder’s assistant installs what nxnative needs, then asks where your dumps are and where your games go.")
    }
    static var macGuideSetupAction: String { s("mac.guide.setup.action", "Open the assistant") }
    static var macGuideBuildTitle: String { s("mac.guide.build.title", "Build a game for this Mac") }
    static var macGuideBuildDetail: String {
        s("mac.guide.build.detail",
          "In Cartouche Builder’s library, build one of your games for this Mac: it comes to the console once built.")
    }
    static var macGuideBuildAction: String { s("mac.guide.build.action", "Open the library") }
    static var macGuidePlayTitle: String { s("mac.guide.play.title", "Play it") }
    static var macGuidePlayDetail: String {
        s("mac.guide.play.detail", "Pick your game in the console, then Play.")
    }
    static var macGuidePlayAction: String { s("mac.guide.play.action", "Back to the console") }
}
