//
//  CartoucheSigningCheck.swift
//  CartoucheCore
//
//  Why a certificate the player chose does not go into a Cartouche signed
//  with their own certificate (docs/imported-signing.md), told apart so
//  that the setup says what to do about it: the file chosen is not the
//  .p12, the password is not its own, the .p12 holds no private key, or,
//  signed on the iPhone, Cartouche has no profile it reads. Up to 0.13.1,
//  one message said all of the key's ("Check its password, and that the
//  .p12 holds its private key"), another all of the profile's ("invalid,
//  expired or does not match this certificate"): the first tour of the IPA
//  for the player's own certificate (17 November) saw a copy try its
//  certificate 23 times under the first, and two copies 19 times in all
//  under the second, which a player signed on the iPhone, who chooses no
//  profile, cannot follow. Foundation only, so that swift test checks it
//  (launcher/Package.swift); CartoucheImportedSigning asks iOS, and says
//  each in the setup's words.
//

import Foundation

/// Why a certificate did not go in, as signing.imported measures it, its
/// outcome: never the certificate, its password, its team or its profile.
enum CartoucheSigningTrouble: String, Equatable, Sendable {
    // The file chosen as the certificate, from its first bytes.

    /// A provisioning profile (.mobileprovision), chosen in its place.
    case profileFile
    /// A .zip, as a certificate often comes, with its profile and its
    /// password.
    case zipFile
    /// Anything else that is not a .p12: a .cer without its key, a PEM, a
    /// text file.
    case notCertificate

    // Its password and its key, as iOS opens the .p12 (SecPKCS12Import),
    // then LiveContainer's signer (zsign, LCUtils.getCertTeamId).

    /// No password typed, and the .p12 has one.
    case passwordNeeded
    /// The password typed does not open the .p12.
    case wrongPassword
    /// The .p12 opens, without the private key that signs.
    case noPrivateKey
    /// iOS does not read the .p12: damaged, or cut short.
    case unreadableKey
    /// iOS opens the .p12, LiveContainer's signer does not.
    case signerRefused

    // The profile: signed on the iPhone, Cartouche's own, the one its
    // signing app put in it (embedded.mobileprovision); installed from a
    // computer, the one the player chose.

    /// Signed on the iPhone, Cartouche has no profile in it.
    case noOwnProfile
    /// Signed on the iPhone, the profile in Cartouche does not read.
    case ownProfileUnreadable
    /// The profile has expired.
    case expired
    /// The profile chosen does not read.
    case invalidProfile
    /// The profile chosen does not list this certificate, or is another
    /// team's.
    case mismatch
}

extension CartoucheSigningTrouble {
    /// What DATA, chosen as the certificate, is instead of a .p12, from its
    /// first bytes: nil for a PKCS#12, a SEQUENCE, in DER or BER, whose
    /// first value is the INTEGER 3, its version (RFC 7292).
    static func ofFile(_ data: Data) -> CartoucheSigningTrouble? {
        let start = [UInt8](data.prefix(16))
        if isPKCS12(start) { return nil }
        // A local file's header, or the end of an empty archive's directory.
        if start.starts(with: [0x50, 0x4B, 0x03, 0x04]) || start.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return .zipFile
        }
        // Apple profiles wrap their XML property list in a CMS envelope.
        if data.range(of: Data("<plist".utf8)) != nil { return .profileFile }
        return .notCertificate
    }

    private static func isPKCS12(_ start: [UInt8]) -> Bool {
        guard start.count >= 5, start[0] == 0x30 else { return false }
        let header: Int
        switch start[1] {
        // A length of one byte, or BER's indefinite one.
        case 0x00...0x80: header = 2
        // A length of up to four more.
        case 0x81...0x84: header = 2 + Int(start[1] & 0x7F)
        default: return false
        }
        return start.count >= header + 3 && start[header ..< header + 3].elementsEqual([0x02, 0x01, 0x03])
    }

    /// What iOS answers a password that does not open the .p12
    /// (errSecAuthFailed), or says it so (errSecPkcs12VerifyFailure, "MAC
    /// verification failed during PKCS12 import (wrong password?)";
    /// errSecPassphraseRequired).
    static let passwordStatuses: Set<Int32> = [-25293, -25264, -25260]

    /// Why the .p12 does not open, from what iOS answered: STATUS, the
    /// OSStatus of SecPKCS12Import, and IDENTITIES, how many certificates
    /// with their private key it found in it; PASSWORD, the one typed. Nil
    /// when it opens, with a key. iOS reads the PKCS#12 of OpenSSL 3, AES
    /// and PBKDF2, from iOS 18, and those before it, RC2 and 3DES, always:
    /// on the iPhones Cartouche runs on, a password it refuses is not the
    /// .p12's.
    static func ofKey(status: Int32, identities: Int, password: String) -> CartoucheSigningTrouble? {
        if status == 0 { return identities > 0 ? nil : .noPrivateKey }
        if passwordStatuses.contains(status) { return password.isEmpty ? .passwordNeeded : .wrongPassword }
        return .unreadableKey
    }
}

/// What signing.imported tells of an import (telemetry/README.md): VIA,
/// `installer` or `setup`; OUTCOME, `imported` or why not; and STATUS, the
/// number iOS answered when it did not open the .p12 (SecPKCS12Import's
/// OSStatus, such as -26275), which tells apart the causes ofKey says in
/// one word: the tour of 27 November saw 8 imports on 3 new copies in iOS
/// 27.0 refused as unreadableKey, none of them through, without it. A
/// number alone: never the certificate, its password, its team or its
/// profile.
enum CartoucheSigningMeasure {
    static let event = "signing.imported"

    static func fields(via: String, outcome: String, status: Int32?) -> [String: CartoucheTelemetryValue] {
        var fields: [String: CartoucheTelemetryValue] = ["via": .text(via), "outcome": .text(outcome)]
        if let status, status != 0 { fields["status"] = .number(Double(status)) }
        return fields
    }
}
