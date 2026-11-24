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
//  site's games page shows them, each with its cover, in the queue with
//  their place, being built on the track of six steps with the time left,
//  and at the Mac's build step the phases of the build of the game itself
//  (CartoucheCloudPhases), built with the day the service deletes them and
//  Install, which brings the game here as a game of the games folder comes
//  (CartoucheGameActions.install(cloud:)), or On this iPhone for a game
//  installed already, or not built, and why. While the page shows, the
//  account is read every few seconds (CartoucheCloud.pause). Sending a
//  game, the credits and the account stay on the site, which the page opens
//  in Safari; Unlink, last, undoes the link, here and on the site.
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
                    let installed = CartoucheCatalog.shared.installedTitles(among: sharedModel.apps)
                    ForEach(account.games) { game in
                        gameRows(game, installed: installed)
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

    /// A game: its cover, its name and state, its build's track while it is
    /// on its way, with the phases of the build of the game itself at the
    /// Mac's build step, what there is to know of it now, and Install once
    /// built, or On this iPhone when its title is one of INSTALLED, the
    /// games on this iPhone.
    @ViewBuilder
    private func gameRows(_ game: CartoucheCloudGame, installed: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                CartoucheCloudCover(game: game)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(CartoucheText.cloudGameState(game.state))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Self.color(of: game.state))
                }
            }
            if let stage = game.stage, game.state == .queued || game.state == .building {
                CartoucheCloudTrack(stage: stage)
            }
            if !game.phaseMarks.isEmpty {
                CartoucheCloudPhases(game: game)
            }
            ForEach(Array(Self.lines(of: game).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        if game.isToInstall(installed: installed) {
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
        } else if game.isBuilt() {
            Label(CartoucheText.cloudGameOnIPhone, systemImage: "checkmark.circle.fill")
                .foregroundStyle(CartouchePlayStatus.ready.color)
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
            // Once the Mac says the phase of the build of the game itself,
            // its phases say what is left.
            if game.currentPhase != nil { return [] }
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

/// The cover of a game of the account, as the library shows it, or the
/// first letter of its name where Cartouche has none.
@available(iOS 17.0, *)
struct CartoucheCloudCover: View {
    let game: CartoucheCloudGame

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        CartoucheCoverImage(art: CartoucheCatalog.shared.cover(titleId: game.titleId).map { CartoucheArt.igdb($0.cover, .cover) }) {
            ZStack {
                LinearGradient(colors: [CartoucheTheme.indigo.opacity(0.75), CartoucheTheme.pink.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(game.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 46, height: 65)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.14)))
        .accessibilityHidden(true)
    }
}

/// The phases of the build of the game itself, under the track while the
/// Mac is at its build step, as the site's list draws them: a dot each,
/// green once done with how long it took, lit while under way with how much
/// of it is done and what the builder says is left of it, dim until then;
/// and since when a Mac that went quiet said nothing.
@available(iOS 17.0, *)
struct CartoucheCloudPhases: View {
    let game: CartoucheCloudGame
    var now = Date()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Text(CartoucheText.cloudPhasesHeader)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(game.phaseMarks, id: \.phase) { mark in
                row(mark)
            }
            if let quiet = game.quiet(at: now) {
                Text(CartoucheText.cloudPhaseQuiet(CartoucheText.duration(seconds: quiet)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
    }

    private func row(_ mark: CartoucheCloudPhaseMark) -> some View {
        let name = CartoucheText.cloudPhaseName(mark.phase)
        let facts = Self.facts(of: mark, game: game, at: now)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Self.dot(mark.at))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(mark.at == .now ? .semibold : .regular))
                    .foregroundStyle(mark.at == .next ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let facts {
                    Text(facts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if mark.at == .now, let share = game.phaseShare {
                    ProgressView(value: share)
                        .tint(CartoucheTheme.pink)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([CartoucheText.cloudPhaseSaid(mark.at, name), facts].compactMap { $0 }.joined(separator: ", "))
    }

    /// What the page says of a phase besides its name, as the site's list
    /// says it: how long it took, once done; how much of it is done and
    /// what is left of it, under way.
    static func facts(of mark: CartoucheCloudPhaseMark, game: CartoucheCloudGame, at now: Date) -> String? {
        switch mark.at {
        case .done:
            return mark.seconds.map { CartoucheText.duration(seconds: Double($0)) }
        case .now:
            let parts = [
                game.phaseShare.map { CartoucheText.percent(($0 * 100).rounded(.down) / 100) },
                game.phaseTimeLeft(at: now).map { CartoucheText.cloudPhaseLeft(CartoucheText.duration(seconds: $0)) },
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .next:
            return nil
        }
    }

    private static func dot(_ at: CartoucheCloudPhaseMark.At) -> AnyShapeStyle {
        switch at {
        case .done: return AnyShapeStyle(CartouchePlayStatus.ready.color)
        case .now: return AnyShapeStyle(CartoucheTheme.brand)
        case .next: return AnyShapeStyle(Color.white.opacity(0.18))
        }
    }
}
