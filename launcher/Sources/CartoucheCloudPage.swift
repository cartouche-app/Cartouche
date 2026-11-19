//
//  CartoucheCloudPage.swift
//  Cartouche
//
//  System › Cartouche Cloud (decision 136). For a player whose iPhone is
//  not linked: what Cartouche Cloud is, the price of a build as the service
//  says it, and the way to its site, where an account is made or signed in
//  to; then the code of the account's page, typed here, or filled in by the
//  link that page opens Cartouche with, which links this iPhone at once
//  (CartoucheCloudLink). Linked: the account's credits, and its games as the
//  site's games page shows them, in the queue with their place, being built
//  on the track of six steps with the time left, built with the day the
//  service deletes them and Install, which brings the game here as a game
//  of the games folder comes (CartoucheGameActions.install(cloud:)), or not
//  built, and why. While the page shows, the account is read every few
//  seconds (CartoucheCloud.pause). Sending a game, the credits and the
//  account stay on the site, which the page opens in Safari; Unlink, last,
//  undoes the link, here and on the site.
//
//  The iPhone's alone: a Mac builds its own games with Cartouche Builder.
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheCloudPage: View {
    @ObservedObject private var link = CartoucheCloudLink.shared
    @ObservedObject private var actions = CartoucheGameActions.shared
    @EnvironmentObject private var sharedModel: SharedModel
    @Environment(\.openURL) private var openURL
    /// The code as typed: its own letters, in capitals (CartoucheCloudCode).
    @State private var code = ""
    @State private var confirmingUnlink = false
    @FocusState private var typing: Bool

    var body: some View {
        List {
            if link.isLinked {
                accountSection
                gamesSection
                siteSection
                unlinkSection
            } else {
                aboutSection
                linkSection
            }
        }
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.cloudName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await link.refresh() }
        .onAppear {
            link.start()
            if let pending = link.pendingCode { code = pending }
        }
        .onDisappear { link.stop() }
        // The link of the account's page, opened while the page shows.
        .onChange(of: link.pendingCode) { _, pending in
            if let pending { code = pending }
        }
    }

    // MARK: Not linked

    /// What Cartouche Cloud is, its price, and the way to its site.
    private var aboutSection: some View {
        Section {
            if link.unlinkedElsewhere {
                note(CartoucheText.cloudUnlinkedElsewhere, systemImage: "link", color: .orange)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(CartoucheText.cloudHeadline)
                    .font(.headline)
                Text(CartoucheText.cloudIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            if let service = link.service {
                Label(CartoucheText.cloudPrice(CartoucheText.cloudMoney(service.price)), systemImage: "creditcard")
                if service.signup == .invitation {
                    note(CartoucheText.cloudInvitation, systemImage: "envelope")
                }
                if let idle = service.idle {
                    note(CartoucheText.cloudIdle(idle), systemImage: "pause.circle")
                }
            } else if let problem = link.problem {
                note(CartoucheText.cloudRefused(problem.kind), systemImage: "wifi.slash", color: .orange)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(CartoucheText.cloudReaching)
                        .foregroundStyle(.secondary)
                }
            }
            Button(link.service?.signup == .open ? CartoucheText.cloudSignUp : CartoucheText.cloudSignIn,
                   systemImage: "safari") {
                openURL(CartoucheCloud.signInPage)
            }
        }
    }

    /// The code of the account's page, which links this iPhone.
    private var linkSection: some View {
        Section {
            TextField(CartoucheText.cloudCodePlaceholder, text: $code)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .focused($typing)
                .disabled(link.busy != nil)
                .onChange(of: code) { _, typed in
                    // Pasted with its dash, or typed in small letters.
                    let kept = CartoucheCloudCode.entered(typed)
                    if kept != typed { code = kept }
                }
                .onSubmit(linkNow)
            Button(action: linkNow) {
                HStack(spacing: 10) {
                    Label(CartoucheText.cloudLink, systemImage: "link")
                    if link.busy == .linking {
                        Spacer(minLength: 0)
                        ProgressView()
                    }
                }
            }
            .disabled(CartoucheCloudCode.typed(code) == nil || link.busy != nil)
            if let refusal = link.refusal, link.busy == nil {
                note(CartoucheText.cloudRefused(refusal.kind), systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
            Button(CartoucheText.cloudGetCode, systemImage: "safari") {
                openURL(CartoucheCloud.accountPage)
            }
        } header: {
            Text(CartoucheText.cloudLinkHeader)
        } footer: {
            Text(CartoucheText.cloudLinkFooter)
        }
    }

    private func linkNow() {
        guard CartoucheCloudCode.typed(code) != nil else { return }
        typing = false
        link.link(code: code)
    }

    // MARK: Linked

    /// The account's credits, and why no build starts, when none does.
    @ViewBuilder
    private var accountSection: some View {
        if link.account != nil || link.problem != nil {
            Section {
                if let account = link.account {
                    LabeledContent(CartoucheText.cloudCredits, value: CartoucheText.cloudMoney(account.credits.balance))
                    if account.credits.held > 0 {
                        Text(CartoucheText.cloudHeld(CartoucheText.cloudMoney(account.credits.held),
                                                     CartoucheText.cloudMoney(account.credits.available)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let idle = account.idle {
                        note(CartoucheText.cloudIdle(idle), systemImage: "pause.circle")
                    }
                }
                if let problem = link.problem {
                    note(CartoucheText.cloudRefused(problem.kind), systemImage: "wifi.slash", color: .orange)
                }
            } header: {
                Text(CartoucheText.cloudAccountHeader)
            } footer: {
                if let account = link.account {
                    Text(CartoucheText.cloudPriceFooter(CartoucheText.cloudMoney(account.credits.price)))
                }
            }
        }
    }

    /// The account's games, the latest first, as the site's games page
    /// shows them.
    private var gamesSection: some View {
        Section {
            if let account = link.account {
                if account.games.isEmpty {
                    Text(CartoucheText.cloudGamesNone)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.games) { game in
                        gameRows(game)
                    }
                }
            } else if link.problem == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(CartoucheText.cloudGamesReading)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(CartoucheText.cloudGamesHeader)
        } footer: {
            Text(CartoucheText.cloudGamesFooter)
        }
    }

    /// A game: its name and state, its build's track while it is on its
    /// way, what there is to know of it now, and Install once built.
    @ViewBuilder
    private func gameRows(_ game: CartoucheCloudGame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(CartoucheText.cloudGameState(game.state))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.color(of: game.state))
            }
            if let stage = game.stage, game.state == .queued || game.state == .building {
                CartoucheCloudTrack(stage: stage)
            }
            ForEach(Array(Self.lines(of: game).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        if game.isBuilt() {
            Button {
                install(game)
            } label: {
                LabeledContent {
                    Text(CartoucheText.size(bytes: game.bytes ?? 0))
                } label: {
                    Label(CartoucheText.cloudGameInstall, systemImage: "icloud.and.arrow.down.fill")
                }
            }
            .disabled(actions.work != nil)
        }
    }

    /// Installs GAME, built, as the library does: the console shows the
    /// install, and what it asks first, as System closes.
    private func install(_ game: CartoucheCloudGame) {
        actions.install(cloud: CartoucheCloudBuilt(game))
        sharedModel.selectedTab = .games
    }

    /// What there is to know of GAME at NOW, as the site says it
    /// (games.js): where it waits, the time it has left, the day its IPA
    /// goes, or why it was not built and what is left to do.
    static func lines(of game: CartoucheCloudGame, at now: Date = Date()) -> [String] {
        let kept = CartoucheText.dateAndTime(game.expiresAt)
        switch game.state {
        case .open:
            return [CartoucheText.cloudGameOpen(kept)]
        case .queued:
            var lines: [String] = []
            if game.behind == true {
                lines.append(CartoucheText.cloudGameBehind)
            } else if let place = game.place {
                lines.append(CartoucheText.cloudGamePlace(place))
            }
            if let usual = game.usual {
                lines.append(CartoucheText.cloudGameUsual(CartoucheText.duration(seconds: Double(usual))))
            }
            return lines
        case .building:
            // A minute at the least, until the usual time has passed.
            if let left = game.timeLeft(at: now) {
                return [CartoucheText.cloudGameLeft(CartoucheText.duration(seconds: max(60, left)))]
            }
            return game.usual != nil && game.launchedAt != nil ? [CartoucheText.cloudGameLonger] : []
        case .built:
            return [CartoucheText.cloudGameKept(kept)]
        case .failed:
            let until = game.until.map(CartoucheText.dateAndTime) ?? kept
            return [CartoucheText.cloudCause(game.cause), CartoucheText.cloudLeft(game.left, until)].compactMap { $0 }
        case .other:
            return [CartoucheText.cloudGameElsewhere]
        }
    }

    private static func color(of state: CartoucheCloudGame.State) -> Color {
        switch state {
        case .built: return CartouchePlayStatus.ready.color
        case .failed: return CartoucheTheme.danger
        case .open, .queued, .building: return CartouchePlayStatus.cloud.color
        case .other: return CartoucheTheme.secondaryText
        }
    }

    /// The site's pages, where a game is sent and the account kept.
    private var siteSection: some View {
        Section {
            Button(CartoucheText.cloudSiteGames, systemImage: "safari") {
                openURL(CartoucheCloud.gamesPage)
            }
            Button(CartoucheText.cloudSiteAccount, systemImage: "person.crop.circle") {
                openURL(CartoucheCloud.accountPage)
            }
        } footer: {
            Text(CartoucheText.cloudSiteFooter)
        }
    }

    /// Unlink, once the player said so twice.
    private var unlinkSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingUnlink = true
            } label: {
                HStack(spacing: 10) {
                    Label(CartoucheText.cloudUnlink, systemImage: "minus.circle")
                        .foregroundStyle(CartoucheTheme.danger)
                    if link.busy == .unlinking {
                        Spacer(minLength: 0)
                        ProgressView()
                    }
                }
            }
            .disabled(link.busy != nil)
            .confirmationDialog(CartoucheText.cloudUnlinkQuestion, isPresented: $confirmingUnlink, titleVisibility: .visible) {
                Button(CartoucheText.cloudUnlinkConfirm, role: .destructive) {
                    link.unlink()
                }
                Button(CartoucheText.cancel, role: .cancel) {}
            } message: {
                Text(CartoucheText.cloudUnlinkMessage)
            }
            if let refusal = link.refusal, link.busy == nil {
                note(CartoucheText.cloudRefused(refusal.kind), systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        } footer: {
            Text(CartoucheText.cloudUnlinkFooter)
        }
    }

    // MARK: Parts

    private func note(_ text: String, systemImage: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The track of a build, as the site draws it (track.js): a bar a step,
/// those before the step it is at done, its own lit, then which step it is,
/// by its number and its name.
@available(iOS 17.0, *)
struct CartoucheCloudTrack: View {
    /// From 0.
    let stage: Int

    var body: some View {
        let at = min(max(stage, 0), CartoucheCloud.trackSteps - 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<CartoucheCloud.trackSteps, id: \.self) { step in
                    Capsule()
                        .fill(Self.fill(step, at: at))
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
            Text(CartoucheText.cloudTrackStep(at + 1, CartoucheCloud.trackSteps, CartoucheText.cloudTrackName(at)))
                .font(.footnote.weight(.semibold))
        }
    }

    private static func fill(_ step: Int, at: Int) -> AnyShapeStyle {
        if step < at { return AnyShapeStyle(CartoucheTheme.indigo) }
        if step == at { return AnyShapeStyle(CartoucheTheme.brand) }
        return AnyShapeStyle(Color.white.opacity(0.15))
    }
}
