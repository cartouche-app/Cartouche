//
//  CartoucheSetupView.swift
//  Cartouche
//
//  The setup, once per iPhone: the pairing file the installer places, the Apple ID
//  the built-in SideStore signs in with, given here (CartoucheSignInView), then
//  the certificate, which Cartouche hands to LiveContainer on its own
//  (CartoucheSetup.swift). Each step shows
//  where it stands, read again whenever Cartouche comes back to the front.
//  The Apple ID's step stays open while this iPhone is left to register,
//  and while the sign-in stopped before the certificate, with why it
//  stopped. Installed by the player's own SideStore
//  (CartoucheSideStoreInstall), the pairing file is asked of that SideStore,
//  the sign-in takes the certificate it signed Cartouche with, and a fourth
//  step has Cartouche install itself again, once, for Increased Memory
//  Limit (CartoucheUpdates.reinstallForMemory).
//

import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct CartoucheSetupView: View {
    @ObservedObject private var setup = CartoucheSetup.shared
    @ObservedObject private var account = CartoucheAccount.shared
    @ObservedObject private var renewals = CartoucheRenewals.shared
    @ObservedObject private var updates = CartoucheUpdates.shared
    /// The automation of Shortcuts that renews Cartouche every night: the
    /// last step, which Cartouche plays without (needsSetup).
    @ObservedObject private var nightly = CartoucheNightly.shared
    @State private var choosingPairingFile = false
    @State private var signingIn = false
    /// Opened from the home's banner on the automation of every night, the
    /// only step left: the setup shows its end, where that step is.
    @State private var opensOnNightly = CartoucheSetup.shared.nightlyLeft
    @Environment(\.openURL) private var openURL

    static let localDevVPN = URL(string: "localdevvpn://")!
    static let localDevVPNAppStore = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!

    /// Whether the setup opens scrolled down to its end, on Renew every
    /// night, whatever is left: the launcher's gallery (launcher/Gallery);
    /// in Cartouche, only from the home's banner on it (opensOnNightly).
    #if CARTOUCHE_GALLERY
    static var opensAtEnd = false
    #else
    static let opensAtEnd = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if CartoucheImportedSigning.isSignedElsewhere {
                    signedElsewhereStep
                } else if !setup.usesImportedSigning {
                    step(
                        number: 1,
                        done: setup.hasPairingFile,
                        title: CartoucheText.setupPairingTitle,
                        detail: pairingDetail
                    ) {
                        // The player's own SideStore has this iPhone's.
                        if sideStoreInstall && !setup.hasPairingFile {
                            Button {
                                CartoucheSideStoreInstall.askForPairingFile()
                            } label: {
                                Label(CartoucheText.sideStorePairingAsk, systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button {
                            choosingPairingFile = true
                        } label: {
                            Label(setup.hasPairingFile ? CartoucheText.setupPairingReplace : CartoucheText.setupPairingChoose,
                                  systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        if let pairingReport = setup.pairingReport {
                            Label(pairingReport.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                            CartoucheReportButton(report: pairingReport)
                                .font(.footnote)
                                .buttonStyle(.bordered)
                        }
                    }
                    step(
                        number: 2,
                        done: setup.signInStep == .done && !setup.needsDevice && !renewals.sessionExpired,
                        title: CartoucheText.setupAppleIDTitle,
                        detail: appleIDDetail
                    ) {
                        // Once set up, only while Apple says that the session
                        // SideStore renews with has expired, which a sign-in
                        // mends: any other sign-in counts against Apple's
                        // limit on them, and may cost the player a code.
                        if setup.appleID == nil || !setup.hasCertificate || setup.certificateRefused || setup.needsDevice
                            || renewals.sessionExpired {
                            // SideStore registers this iPhone at sign-in, through
                            // the pairing file.
                            Button {
                                signingIn = true
                            } label: {
                                Label(appleIDButton, systemImage: setup.needsDevice ? "iphone.gen3" : "person.crop.circle.badge.checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!setup.hasPairingFile || account.phase == .registeringDevice)
                        }
                        // Why the sign-in stopped, once its screen has gone.
                        if setup.signInStep == .unfinished, account.phase == nil, let report = account.lastProblem {
                            Label(report.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                            CartoucheReportButton(report: report)
                                .font(.footnote)
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if !CartoucheImportedSigning.isSignedElsewhere {
                    step(
                        number: setup.usesImportedSigning ? 1 : 3,
                        done: setup.hasCertificate && setup.certificateWorks == true,
                        title: CartoucheText.setupCertificateTitle,
                        detail: certificateDetail
                    ) {
                        if CartoucheImportedSigning.isImportedInstall {
                            NavigationLink {
                                CartoucheSigningView()
                            } label: {
                                Label(CartoucheText.signingTitle, systemImage: "signature")
                            }
                            .buttonStyle(.bordered)
                        }
                        if let problem = setup.signingProblem {
                            Text(problem).font(.footnote).foregroundStyle(.red)
                        }
                        if setup.isImportingSigning { ProgressView(CartoucheText.setupCertificateChecking) }
                        if setup.usesImportedSigning {
                            Text(CartoucheImportedSigning.isSignedOnIPhone ? CartoucheText.signingUpdateOnIPhone
                                 : CartoucheText.signingUpdateOnComputer)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        // A sign-in that stopped: signing in again brings it.
                        if !setup.hasCertificate && setup.signInStep != .unfinished {
                            Button(CartoucheText.setupCheckAgain, systemImage: "arrow.clockwise") {
                                setup.refresh()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                // Not for the IPA for SideStore installed without its app
                // group: never set up, the player installs another IPA.
                if sideStoreInstall && !CartoucheImportedSigning.isSignedElsewhere { memoryStep }
                if setup.usesImportedSigning, let signature = CartoucheOwnSignature.current {
                    CartoucheOwnSignatureBox(signature: signature)
                }
                if renewsItself {
                    renewalNote
                    // After LocalDevVPN, whose action the automation runs
                    // before Refresh All Apps; after Increased Memory Limit
                    // for the IPA of the player's own SideStore.
                    step(
                        number: sideStoreInstall ? 5 : 4,
                        done: nightly.state.isDone,
                        title: CartoucheText.renewEveryNight,
                        detail: nightly.detail
                    ) {
                        NavigationLink {
                            CartoucheNightlyRenewalView()
                        } label: {
                            Label(nightly.action, systemImage: "moon.zzz")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(Self.opensAtEnd || opensOnNightly ? .bottom : nil)
        .background(CartoucheStage(key: nil))
        .navigationTitle(CartoucheText.setupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(CartoucheSetupRefresh())
        .sheet(isPresented: $signingIn) {
            CartoucheSignInView()
        }
        // Apple asks for a code while Cartouche signs in again by itself.
        .onAppear { if account.needsCode { signingIn = true } }
        .onChange(of: account.needsCode) { _, needsCode in
            if needsCode { signingIn = true }
        }
        .fileImporter(isPresented: $choosingPairingFile, allowedContentTypes: CartouchePairing.contentTypes) { result in
            switch result {
            case .success(let url):
                setup.importPairingFile(url)
            case .failure(let error):
                setup.pairingFailed(error)
            }
        }
    }

    /// Cartouche's IPA for an Apple ID, signed by a signing app without its
    /// app group: its sign-in cannot work, and the IPA for the player's own
    /// certificate is the one to sign (CartoucheImportedSigning).
    private var signedElsewhereStep: some View {
        let version = CartoucheImportedSigning.cartoucheVersion
        return step(number: 1, done: false, title: CartoucheText.signedElsewhereTitle,
                    detail: CartoucheText.signedElsewhere(version)) {
            if let ipa = CartoucheImportedSigning.ownCertificateIPA {
                Button {
                    openURL(ipa)
                } label: {
                    Label(CartoucheText.updateDownloadVersion(version), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Installed by the player's own SideStore, from its source for
    /// SideStore.
    private var sideStoreInstall: Bool { CartoucheSideStoreInstall.isSideStoreInstall }

    private var pairingDetail: String {
        if setup.hasPairingFile { return CartoucheText.setupPairingDone }
        return sideStoreInstall ? CartoucheText.sideStorePairingHow : CartoucheText.setupPairingHow
    }

    /// Increased Memory Limit, which the player's own SideStore leaves out
    /// on a free team: Cartouche installs itself again, once, through the
    /// built-in SideStore, which asks Apple for it.
    private var memoryStep: some View {
        let memory = CartoucheSideStoreInstall.memory
        let reinstalling = updates.kind == .memory ? updates.phase : nil
        return step(number: 4, done: memory == .granted, title: CartoucheText.sideStoreMemoryTitle,
                    detail: memoryDetail(memory)) {
            if let phase = reinstalling {
                VStack(alignment: .leading, spacing: 6) {
                    Label(updates.stepTitle(phase, version: CartoucheUpdates.runningVersion), systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                    if phase == .preparing, let progress = updates.progress {
                        // SideStore reports its progress from another
                        // thread: read it twice a second.
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            ProgressView(value: progress.fractionCompleted)
                        }
                    } else {
                        ProgressView()
                    }
                    Text(updates.stepMessage(phase))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if memory == .reinstall {
                Button {
                    updates.reinstallForMemory()
                } label: {
                    Label(CartoucheText.sideStoreMemoryButton, systemImage: "memorychip")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updates.canReinstallForMemory || account.phase != nil)
                // Why the last reinstall did not go through.
                if updates.kind == .memory, let report = updates.problemReport {
                    Label(report.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    CartoucheReportButton(report: report)
                        .font(.footnote)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func memoryDetail(_ memory: CartoucheSideStoreMemory) -> String {
        switch memory {
        case .granted: return CartoucheText.sideStoreMemoryGranted
        case .afterSetup: return CartoucheText.sideStoreMemoryAfterSetup
        case .reinstall: return CartoucheText.sideStoreMemoryReinstall
        }
    }

    private var appleIDDetail: String {
        guard let appleID = setup.appleID else {
            return sideStoreInstall ? CartoucheText.sideStoreAppleIDHow : CartoucheText.setupAppleIDHow
        }
        // The sign-in stopped before the certificate: signing in again
        // brings it.
        if setup.signInStep == .unfinished {
            let working = account.phase == .signingIn || account.needsCode
            return working ? CartoucheText.signInWorking : CartoucheText.setupAppleIDUnfinished(appleID)
        }
        if renewals.sessionExpired, !setup.needsDevice {
            let working = account.phase == .signingIn || account.needsCode
            return working ? CartoucheText.signInWorking : CartoucheText.setupAppleIDSessionExpired(appleID)
        }
        guard setup.needsDevice else { return CartoucheText.setupAppleIDDone(appleID) }
        return account.phase == .registeringDevice ? CartoucheText.setupBannerDeviceWorking : CartoucheText.setupAppleIDDevice(appleID)
    }

    private var appleIDButton: String {
        if setup.needsDevice { return CartoucheText.signInDeviceButton }
        return setup.appleID == nil ? CartoucheText.setupSignIn : CartoucheText.signInAgain
    }

    private var certificateDetail: String {
        if setup.usesImportedSigning {
            let onIPhone = CartoucheImportedSigning.isSignedOnIPhone
            if setup.certificateRefused { return onIPhone ? CartoucheText.signingRefusedOnIPhone : CartoucheText.signingRefused }
            if !setup.hasCertificate { return onIPhone ? CartoucheText.signingHowOnIPhone : CartoucheText.signingHow }
        }
        guard setup.hasCertificate else { return CartoucheText.setupCertificateHow }
        switch setup.certificateWorks {
        case true?: return CartoucheText.setupCertificateDone
        case nil: return CartoucheText.setupCertificateChecking
        case false?: return account.isAutomatic ? CartoucheText.setupCertificateRenewing : CartoucheText.setupCertificateRefused
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(headerDetail)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var headerTitle: String {
        if setup.needsSetup { return CartoucheText.setupIntroTitle }
        if setup.memoryLeft { return CartoucheText.sideStoreMemoryLeftTitle }
        return sessionExpired ? CartoucheText.setupSessionExpiredTitle : CartoucheText.setupAllDone
    }

    /// With the player's own certificate, Cartouche renews nothing: the
    /// certificate is the only step. Installed by the player's own
    /// SideStore, Increased Memory Limit is a fourth.
    private var headerDetail: String {
        if CartoucheImportedSigning.isSignedElsewhere { return CartoucheText.setupIntroSignedElsewhere }
        if sideStoreInstall {
            if setup.needsSetup { return CartoucheText.sideStoreIntro }
            if setup.memoryLeft { return CartoucheText.sideStoreMemoryLeft }
        }
        if setup.usesImportedSigning {
            return setup.needsSetup ? CartoucheText.setupIntroOwnCertificate : CartoucheText.setupAllDoneOwnCertificate
        }
        if setup.needsSetup { return CartoucheText.setupIntro }
        if sessionExpired { return CartoucheText.setupSessionExpiredDetail }
        return nightly.state.isDone ? CartoucheText.setupAllDoneDetail : CartoucheText.setupAllDoneButNightly
    }

    /// Whether the built-in SideStore renews Cartouche with the player's
    /// Apple ID: LocalDevVPN and the automation of every night serve it
    /// alone. A certificate of the player's own is never renewed here.
    private var renewsItself: Bool {
        !setup.usesImportedSigning && !CartoucheImportedSigning.isSignedElsewhere
    }

    /// Set up, once Apple has said that the session SideStore renews with
    /// has expired: the Apple ID's step is to do again, and nothing is all
    /// set until it is.
    private var sessionExpired: Bool {
        renewals.sessionExpired && renewsItself
    }

    private func step<Actions: View>(
        number: Int, done: Bool, title: String, detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : CartoucheTheme.indigo)
                if done {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.heavy))
                } else {
                    Text(String(number))
                        .font(.headline.monospacedDigit().weight(.heavy))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(done ? CartoucheText.setupStepDone(title) : title)
    }

    private var renewalNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(CartoucheText.setupVPNTitle, systemImage: "network.badge.shield.half.filled")
                .font(.headline)
            Text(CartoucheText.setupVPNHow)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                UIApplication.shared.open(Self.localDevVPN) { opened in
                    if !opened { UIApplication.shared.open(Self.localDevVPNAppStore) }
                }
            } label: {
                Label(CartoucheText.setupVPNOpen, systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The banner over the games while Cartouche is not set up.
@available(iOS 17.0, *)
struct CartoucheSetupBanner: View {
    @ObservedObject private var setup = CartoucheSetup.shared
    @ObservedObject private var account = CartoucheAccount.shared

    var body: some View {
        if setup.showsBanner {
            NavigationLink {
                CartoucheSetupView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: setup.bannerIcon)
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(setup.bannerTitle)
                            .font(.headline)
                        Text(setup.bannerDetail(signingInAgain: account.isAutomatic,
                                                registeringDevice: account.phase == .registeringDevice))
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// What the setup banners say, over the home and the games.
@available(iOS 17.0, *)
extension CartoucheSetup {
    /// Installed by the player's own SideStore and set up, without
    /// Increased Memory Limit: Cartouche installs itself again for it.
    var memoryLeft: Bool {
        CartoucheSideStoreInstall.isSideStoreInstall && CartoucheSideStoreInstall.memory == .reinstall
    }

    /// Whether the built-in SideStore renews Cartouche with the player's
    /// Apple ID: a certificate of the player's own is never renewed here.
    var renewsWithAppleID: Bool {
        !usesImportedSigning && !CartoucheImportedSigning.isSignedElsewhere
    }

    /// Set up with an Apple ID, once the player's first game is installed,
    /// while the automation that renews Cartouche every night is still to
    /// make, and the player has not taken its banner off: the home says this
    /// last step is left, which Cartouche plays without (decision 159).
    var nightlyLeft: Bool {
        let nightly = CartoucheNightly.shared
        return !needsSetup && !memoryLeft && renewsWithAppleID && CartoucheGuide.shared.isFinishedOnce
            && nightly.state == .toMake && !nightly.isBannerHidden
    }

    /// Whether the banners show: the setup is left, Increased Memory
    /// Limit, or the automation of every night.
    var showsBanner: Bool { needsSetup || memoryLeft || nightlyLeft }

    /// Whether the setup's banner goes before the offer of a saves folder
    /// (CartoucheSavesOffer): what Cartouche needs to play, or to play its
    /// games whole, not the automation of every night, which waits for it.
    var bannerGoesFirst: Bool { needsSetup || memoryLeft }

    /// Whether the banner has a × that takes it off the home: the
    /// automation's alone, since Cartouche plays without it.
    var bannerHides: Bool { nightlyLeft }

    func hideBanner() {
        CartoucheNightly.shared.hideBanner()
    }

    var bannerIcon: String {
        if !needsSetup && memoryLeft { return "memorychip" }
        if nightlyLeft { return "moon.zzz" }
        return certificateRefused ? "exclamationmark.shield.fill" : canPlay ? "arrow.triangle.2.circlepath" : "checklist"
    }

    var bannerTitle: String {
        if !needsSetup && memoryLeft { return CartoucheText.sideStoreMemoryBannerTitle }
        if nightlyLeft { return CartoucheText.renewEveryNight }
        if CartoucheImportedSigning.isSignedElsewhere { return CartoucheText.signedElsewhereTitle }
        if certificateRefused { return CartoucheText.setupBannerCertificate }
        return canPlay ? CartoucheText.setupBannerRenewal : CartoucheText.setupBannerTitle
    }

    func bannerDetail(signingInAgain: Bool, registeringDevice: Bool = false) -> String {
        if !needsSetup && memoryLeft { return CartoucheText.sideStoreMemoryBannerDetail }
        if nightlyLeft { return CartoucheText.setupBannerNightlyDetail }
        if CartoucheImportedSigning.isSignedElsewhere { return CartoucheText.setupBannerSignedElsewhere }
        if usesImportedSigning {
            if CartoucheImportedSigning.isSignedOnIPhone {
                return certificateRefused ? CartoucheText.signingRefusedOnIPhone : CartoucheText.signingHowOnIPhone
            }
            return certificateRefused ? CartoucheText.signingRefused : CartoucheText.signingHow
        }
        if certificateRefused {
            return signingInAgain ? CartoucheText.setupBannerCertificateRenewing : CartoucheText.setupBannerCertificateDetail
        }
        if signInStep == .unfinished {
            return signingInAgain ? CartoucheText.setupBannerCertificateRenewing : CartoucheText.setupBannerUnfinishedDetail
        }
        guard canPlay else { return CartoucheText.setupBannerDetail }
        guard hasPairingFile else { return CartoucheText.setupBannerRenewalDetail }
        guard needsDevice else { return CartoucheText.setupBannerSignInDetail }
        // Signed in, with this iPhone left to register.
        return registeringDevice ? CartoucheText.setupBannerDeviceWorking : CartoucheText.setupBannerDeviceDetail
    }
}

/// What Cartouche's signature gives it, signed with the player's own
/// certificate (CartoucheOwnSignature): Increased Memory Limit, without
/// which iOS gives Cartouche about 3 GB, and the games' keychains, with how
/// a missing one comes back.
@available(iOS 17.0, *)
struct CartoucheOwnSignatureBox: View {
    let signature: CartoucheOwnSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(CartoucheText.signatureCheckTitle, systemImage: "signature")
                .font(.headline)
            row(CartoucheText.imlRequirement, granted: signature.increasedMemoryLimit == .granted,
                detail: memoryDetail, warning: true)
            row(CartoucheText.signatureKeychains, granted: signature.gameKeychains == .granted,
                detail: keychainDetail, warning: false)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var memoryDetail: String? {
        switch signature.increasedMemoryLimit {
        case .granted: return nil
        case .leftOut: return CartoucheText.signatureMemoryLeftOut
        case .notInProfile: return CartoucheText.signatureMemoryNotInProfile
        }
    }

    private var keychainDetail: String? {
        switch signature.gameKeychains {
        case .granted: return CartoucheText.signatureKeychainsGranted
        case .leftOut: return CartoucheText.signatureKeychainsLeftOut
        case .notInProfile: return CartoucheText.signatureKeychainsNotInProfile
        }
    }

    /// A grant: ticked, or, missing, in orange when Cartouche needs it and
    /// in grey when the games seldom do.
    private func row(_ title: String, granted: Bool, detail: String?, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Label(granted ? CartoucheText.imlOn : CartoucheText.imlOff,
                      systemImage: granted ? "checkmark.circle.fill" : warning ? "exclamationmark.triangle.fill" : "info.circle")
                    .labelStyle(CartoucheTightLabelStyle())
                    .foregroundStyle(granted ? Color.green : warning ? Color.orange : Color.secondary)
            }
            .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
