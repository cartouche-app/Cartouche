import Foundation
import Security

enum CartoucheImportedSigning {
    static let handoffName = "CartoucheSigning.plist"
    private static let account = "Cartouche.importedSigning.material"

    /// How Cartouche was signed: with the player's Apple ID, or with their
    /// own certificate, by the Cartouche Installer or on the iPhone
    /// (CartoucheOwnSignature.swift).
    static var mode: CartoucheSigningMode {
        #if CARTOUCHE_GALLERY
        return GalleryState.signing
        #else
        return CartoucheSigningMode(info: Bundle.main.infoDictionary ?? [:])
        #endif
    }
    static var isImportedInstall: Bool { mode.isImported }
    /// Signed by a signing app on the iPhone, from the IPA for the player's
    /// own certificate: the player gives Cartouche the certificate alone,
    /// and Cartouche reads the profile the signing app put in it.
    static var isSignedOnIPhone: Bool { mode == .iPhone }
    /// Cartouche's IPA for an Apple ID that a signing app signed, without
    /// its app group: the Apple ID's sign-in cannot work, and the setup and
    /// the guide say to sign the IPA for the player's own certificate
    /// instead (CartoucheOwnSignature.swift).
    static var isSignedElsewhere: Bool { mode.isSignedElsewhere(hasAppGroup: LCSharedUtils.appGroupPath() != nil) }
    /// Cartouche's version (app/config.env).
    static var cartoucheVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    /// The IPA for the player's own certificate of this version, among
    /// Cartouche's releases on GitHub.
    static var ownCertificateIPA: URL? { CartoucheRelease.ownCertificateIPA(version: cartoucheVersion) }
    /// The profile Cartouche was signed with, which iOS installed it with.
    static var ownProfile: Data? {
        #if CARTOUCHE_GALLERY
        return GalleryState.ownProfile
        #else
        return try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision"))
        #endif
    }
    static var isSelected: Bool {
        isImportedInstall
    }
    static var accountSigningDisabled: Bool { isImportedInstall }
    static var material: CartoucheSigningMaterial? {
        #if CARTOUCHE_GALLERY
        // The certificate in place once the gallery's setup is done.
        if GalleryState.setupDone { return CartoucheSigningMaterial(certificate: Data([0x30]), password: "", profile: Data()) }
        #endif
        return CartoucheStoreKeychain.data(account).flatMap {
            try? PropertyListDecoder().decode(CartoucheSigningMaterial.self, from: $0)
        }
    }

    /// Update atomically so a keychain failure preserves the previous import.
    private static func save(_ data: Data) -> Bool {
        guard let service = CartoucheStoreKeychain.service else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    /// Takes the certificate, its password and the profile it goes with
    /// into the keychain, once iOS has run what LiveContainer signs with
    /// them. Signed on the iPhone, the profile is Cartouche's own.
    @MainActor
    static func importMaterial(_ material: CartoucheSigningMaterial) async throws {
        let onIPhone = isSignedOnIPhone
        let reinstall = onIPhone ? CartoucheText.signingOtherCertificate : CartoucheText.signingReinstall
        guard isImportedInstall else { throw ImportError(message: reinstall, kind: "reinstall") }
        if #available(iOS 17.0, *) {
            guard CartoucheAccount.shared.phase == nil, CartoucheUpdates.shared.phase == nil else {
                throw ImportError(message: CartoucheText.signingWait, kind: "busy")
            }
        }
        // What the file is, then what iOS says of its password and its key,
        // each in words of its own (CartoucheSigningCheck.swift).
        if let trouble = CartoucheSigningTrouble.ofFile(material.certificate) {
            throw ImportError(trouble, onIPhone: onIPhone)
        }
        let (status, identities) = openPKCS12(material)
        if let trouble = CartoucheSigningTrouble.ofKey(status: status, identities: identities.count, password: material.password) {
            throw ImportError(trouble, onIPhone: onIPhone)
        }
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identities[0], &certificate) == errSecSuccess, let certificate else {
            throw ImportError(.noPrivateKey, onIPhone: onIPhone)
        }
        guard let team = LCUtils.getCertTeamId(withKeyData: material.certificate, password: material.password) else {
            throw ImportError(.signerRefused, onIPhone: onIPhone)
        }
        guard let hostProfile = ownProfile else { throw ImportError(.noOwnProfile, onIPhone: onIPhone) }
        #if CARTOUCHE_GALLERY
        let hostTeam = team
        #else
        let hostTeam = LCSharedUtils.teamIdentifier() ?? ""
        #endif
        do {
            try material.validate(certificateDER: SecCertificateCopyData(certificate) as Data,
                                  team: team, hostTeam: hostTeam, hostProfile: hostProfile)
        } catch CartoucheSigningMaterial.Problem.reinstall {
            throw ImportError(message: reinstall, kind: "reinstall")
        } catch CartoucheSigningMaterial.Problem.mismatch where onIPhone {
            // Cartouche's own profile does not list this certificate: it is
            // not the one the signing app signed Cartouche with.
            throw ImportError(message: reinstall, kind: "reinstall")
        } catch CartoucheSigningMaterial.Problem.mismatch {
            throw ImportError(.mismatch, onIPhone: onIPhone)
        } catch CartoucheSigningMaterial.Problem.expired {
            throw ImportError(.expired, onIPhone: onIPhone)
        } catch {
            throw ImportError(onIPhone ? .ownProfileUnreadable : .invalidProfile, onIPhone: onIPhone)
        }
        guard await CartoucheCertificate.works(candidate: material) else {
            throw ImportError(message: onIPhone ? CartoucheText.signingRefusedOnIPhone : CartoucheText.signingRefused,
                              kind: "refused")
        }
        guard save(try PropertyListEncoder().encode(material)) else {
            throw ImportError(message: CartoucheText.signInKeychainFailed, kind: "keychain")
        }
        LCSharedUtils.setCartoucheSigningCandidate(nil)
        // Only a timestamp is persisted in engine preferences. Credentials
        // are read directly from the keychain by the patched accessors.
        LCUtils.appGroupUserDefault.set(Date(), forKey: "LCCertificateUpdateDate")
    }

    /// What iOS answers MATERIAL's .p12 and password: its status, and the
    /// identities it holds, each a certificate with its private key.
    private static func openPKCS12(_ material: CartoucheSigningMaterial) -> (status: OSStatus, identities: [SecIdentity]) {
        #if CARTOUCHE_GALLERY
        // What iOS would answer the gallery's stand-in for a .p12 (work:
        // signing-wrong-password).
        if let status = GalleryState.pkcs12Status { return (status, []) }
        #endif
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: material.password] as CFDictionary
        let status = SecPKCS12Import(material.certificate as CFData, options, &items)
        let identities = (items as? [[String: Any]] ?? []).compactMap { item -> SecIdentity? in
            guard let value = item[kSecImportItemIdentity as String] else { return nil }
            return (value as! SecIdentity)
        }
        return (status, identities)
    }

    struct ImportError: LocalizedError {
        let message: String
        /// What went wrong, as a name for the telemetry: never the
        /// certificate, its password, its team or its profile.
        var kind = "other"
        var errorDescription: String? { message }
    }

    /// Says how an import of a certificate went: VIA, `installer` for the
    /// one the Cartouche Installer handed over, `setup` for one the player
    /// chose in Setup; and its outcome, `imported` or why not.
    @MainActor
    static func measure(via: String, error: Error?) {
        // The telemetry, as the console, needs iOS 17.
        guard #available(iOS 17.0, *) else { return }
        let outcome = error.map { ($0 as? ImportError)?.kind ?? "other" } ?? "imported"
        CartoucheTelemetry.shared.event("signing.imported", fields: ["via": .text(via), "outcome": .text(outcome)])
    }
}

extension CartoucheImportedSigning.ImportError {
    /// TROUBLE, in the setup's words (CartoucheSigningCheck.swift): signed
    /// on the iPhone (ON IPHONE), the player chose no profile, and signs
    /// Cartouche again in their signing app; installed from a computer, they
    /// chose the profile with the certificate.
    init(_ trouble: CartoucheSigningTrouble, onIPhone: Bool) {
        self.init(message: Self.words(for: trouble, onIPhone: onIPhone), kind: trouble.rawValue)
    }

    static func words(for trouble: CartoucheSigningTrouble, onIPhone: Bool) -> String {
        switch trouble {
        case .profileFile: return CartoucheText.signingProfileFile
        case .zipFile: return CartoucheText.signingZipFile
        case .notCertificate: return CartoucheText.signingNotCertificate
        case .passwordNeeded: return CartoucheText.signingPasswordNeeded
        case .wrongPassword: return onIPhone ? CartoucheText.signingWrongPasswordOnIPhone : CartoucheText.signingWrongPassword
        case .noPrivateKey: return CartoucheText.signingNoPrivateKey
        case .unreadableKey: return CartoucheText.signingUnreadableKey
        case .signerRefused: return CartoucheText.signingSignerRefused
        case .noOwnProfile, .ownProfileUnreadable:
            return onIPhone ? CartoucheText.signingOwnProfileUnreadable : CartoucheText.signingInvalidProfile
        case .expired: return onIPhone ? CartoucheText.signingOwnProfileExpired : CartoucheText.signingInvalidProfile
        case .invalidProfile, .mismatch: return CartoucheText.signingInvalidProfile
        }
    }
}
