//
//  CartoucheGameWorkView.swift
//  Cartouche
//
//  What Cartouche is doing with a game (CartoucheGameActions), over the
//  console: installing the player's copy, from Files or from the player's
//  games folder, starting a game, uninstalling one or copying it to the
//  games folder, how far it has gone, and whether the player can leave
//  Cartouche meanwhile; and an install it asks about first. A game that
//  comes from a server shows how fast, and, from the Mac, how: by cable,
//  through Tailscale or on the local network, with the band of the Mac's
//  Wi-Fi, and what would go faster when it is slow (decision 151).
//

import SwiftUI

/// A step Cartouche takes with a game, and how far it has gone.
struct CartoucheGameWork: Equatable {
    enum Kind: Equatable {
        case installing, starting, uninstalling, exporting
    }

    var kind: Kind
    /// The game's name, or its IPA's until the IPA is read.
    var name: String
    /// What happens now.
    var step: String
    /// From 0 to 1, or nil while there is nothing to measure.
    var fraction: Double?
    /// What happens now, as a key that stays the same in every language,
    /// for the measurements: "unpacking", "signing".
    var stage = ""
    /// The name of the server the game comes from or goes to; nil for a
    /// file on this iPhone.
    var place: String? = nil
    /// Whether iOS goes on with it once the player leaves Cartouche, and
    /// shows how far it has gone on the Lock Screen and in the Dynamic
    /// Island (CartoucheContinuedWork).
    var outside = false
    /// When it started.
    var started = Date()
    /// How the game comes, from the player's Mac, or from a NAS through it
    /// (CartoucheTransferWay); nil from another place.
    var way: CartoucheTransferWay? = nil
    /// Whether it comes from a server of the local network, a NAS, whose
    /// Wi-Fi may be the slow one; not a bucket nor Cartouche Cloud, which
    /// the internet brings.
    var local = false
    /// The bytes a second it comes at now (CartoucheTransferMeter); nil
    /// while nothing is measured.
    var speed: Double? = nil
    /// Whether it comes slowly (CartoucheTransferMeter.isSlow).
    var slow = false

    /// "Installing Mario Kart World".
    var title: String {
        switch kind {
        case .installing: return CartoucheText.installTitle(name)
        case .starting: return CartoucheText.startTitle(name)
        case .uninstalling: return CartoucheText.uninstallTitle(name)
        case .exporting: return CartoucheText.exportTitle(name)
        }
    }

    /// Whether the game is on its way from its server: not once it is in
    /// place, being signed, nor while the connection is made again.
    var isComing: Bool {
        kind == .installing && ["reading", "unpacking", "gameFiles"].contains(stage)
    }

    /// How the game comes, and how fast: "By cable · 31 MB/s"; nil for
    /// nothing to say.
    var transferLine: String? {
        guard isComing else { return nil }
        let how = way.map(CartoucheText.transferWay)
        let fast = speed.map(CartoucheText.transferSpeed)
        switch (how, fast) {
        case let (how?, fast?): return CartoucheText.transferLine(how, fast)
        case let (how?, nil): return how
        case let (nil, fast?): return fast
        case (nil, nil): return nil
        }
    }

    /// The symbol beside it: the cable, Tailscale's network, the Wi-Fi, a
    /// Wi-Fi with a warning for a Mac on its 2.4 GHz band.
    var transferSymbol: String {
        switch way {
        case .cable, .relayed: return "cable.connector"
        case .tailnet: return "point.3.connected.trianglepath.dotted"
        case .network(let mac):
            if mac?.isSlowBand == true { return "wifi.exclamationmark" }
            return mac?.medium == CartoucheMacNetwork.ethernet ? "network" : "wifi"
        case nil: return "speedometer"
        }
    }

    /// What would go faster: the cable, the 5 GHz Wi-Fi
    /// (CartoucheTransferAdvice); nil for nothing to say.
    var transferAdvice: String? {
        guard isComing else { return nil }
        return CartoucheTransferAdvice.of(way: way, local: local, slow: slow).map(CartoucheText.transferAdvice)
    }

    /// What the player may do meanwhile, for a step that takes minutes:
    /// leave Cartouche, once iOS goes on with it outside, or else keep it
    /// open.
    var advice: String? {
        switch kind {
        case .installing, .exporting: return outside ? CartoucheText.workCanLeave : CartoucheText.workKeepOpen
        case .starting, .uninstalling: return nil
        }
    }
}

/// What the player should know once a step is over: why it failed, or what
/// came of it.
struct CartoucheGameNotice: Equatable {
    var title: String
    var message: String
    /// The report on what failed, which the player can copy; nil when
    /// nothing failed.
    var report: CartoucheReport? = nil
    /// The bundle identifier of a game the player may sign again, whole,
    /// and start, from the notice: LiveContainer did not sign it whole, or
    /// iOS refused its signature as it started (CartoucheGameActions
    /// signAgain).
    var signAgain: String? = nil
    /// The bundle identifier of a game the player may start all the same,
    /// from the notice: Cartouche warned that it may close for lack of
    /// space (CartoucheGameActions playAnyway).
    var playAnyway: String? = nil
}

/// An install the console asks about before it starts, on an iPhone whose
/// GPU nxnative refuses (CartoucheGameActions.installQuestion).
struct CartoucheInstallQuestion: Equatable {
    enum Source: Equatable {
        /// An IPA on this iPhone, from Files or another app.
        case file(URL)
        /// A game in the player's games folder.
        case stored(CartoucheStoredGame)
        /// A game Cartouche Cloud built for the player.
        case cloud(CartoucheCloudBuilt)
    }

    let source: Source

    /// The game's name, or its IPA's.
    var name: String {
        switch source {
        case .file(let url): return url.deletingPathExtension().lastPathComponent
        case .stored(let game): return game.name
        case .cloud(let game): return game.name
        }
    }
}

@available(iOS 17.0, *)
struct CartoucheGameWorkView: View {
    let work: CartoucheGameWork

    private var symbol: String {
        switch work.kind {
        case .installing: return "square.and.arrow.down.fill"
        case .starting: return "play.fill"
        case .uninstalling: return "trash.fill"
        case .exporting: return "externaldrive.fill.badge.plus"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 72, height: 72)
                    .background(
                        LinearGradient(colors: [CartoucheTheme.indigo, CartoucheTheme.pink],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
                    .symbolEffect(.pulse, options: .repeating, isActive: work.fraction == nil)
                VStack(spacing: 6) {
                    Text(work.title)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(work.step)
                        .font(.subheadline)
                        .foregroundStyle(CartoucheTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line = work.transferLine {
                        Label(line, systemImage: work.transferSymbol)
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    if let advice = work.transferAdvice {
                        Label(advice, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    if let advice = work.advice {
                        Label(advice, systemImage: work.outside ? "lock.iphone" : "iphone")
                            .font(.footnote)
                            .foregroundStyle(work.outside ? Color.white : CartoucheTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                if let fraction = work.fraction {
                    VStack(spacing: 6) {
                        ProgressView(value: min(max(fraction, 0), 1))
                            .tint(Color.white)
                        Text(CartoucheText.percent(min(max(fraction, 0), 1)))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(CartoucheTheme.secondaryText)
                    }
                } else {
                    ProgressView()
                        .tint(Color.white)
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            .cartoucheGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
