import XCTest
@testable import CartoucheCore

/// Why a certificate the player chose does not go in, told apart
/// (CartoucheSigningCheck.swift): up to 0.13.1, all of the key's said the
/// same, "Check its password, and that the .p12 holds its private key".
final class CartoucheSigningCheckTests: XCTestCase {
    /// The first bytes of a PKCS#12, a SEQUENCE whose first value is the
    /// INTEGER 3, with a length of LENGTH, as encoded.
    private func pkcs12(length: [UInt8]) -> Data {
        Data([0x30] + length + [0x02, 0x01, 0x03, 0x30, 0x80] + [UInt8](repeating: 0, count: 32))
    }

    func testAPKCS12IsOneWhateverItsLengthsEncoding() {
        // A length of one byte, of two (as most are), of three, and BER's
        // indefinite length, which Java's keytool writes.
        for length: [UInt8] in [[0x7F], [0x82, 0x0A, 0x52], [0x83, 0x01, 0x00, 0x00], [0x80], [0x81, 0xF0]] {
            XCTAssertNil(CartoucheSigningTrouble.ofFile(pkcs12(length: length)), "length \(length)")
        }
    }

    func testAProfileChosenAsTheCertificateIsSaidSo() {
        // A CMS envelope, signedData's OID, then the property list.
        let profile = Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80])
            + Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Name</key><string>Kart</string></dict></plist>"#.utf8)
        XCTAssertEqual(CartoucheSigningTrouble.ofFile(profile), .profileFile)
    }

    func testAZipIsSaidSo() {
        // As a certificate seller sends one, with the profile and the
        // password beside the .p12.
        XCTAssertEqual(CartoucheSigningTrouble.ofFile(Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00])), .zipFile)
        XCTAssertEqual(CartoucheSigningTrouble.ofFile(Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))), .zipFile)
    }

    func testAnythingElseIsNotACertificate() {
        // A certificate alone (.cer): a SEQUENCE of a SEQUENCE, no INTEGER 3.
        let cer = Data([0x30, 0x82, 0x05, 0xD0, 0x30, 0x82, 0x04, 0xB8, 0xA0, 0x03, 0x02, 0x01, 0x02])
        let pem = Data("-----BEGIN CERTIFICATE-----\nMIIF0DCCBLigAwIBAgIQ\n".utf8)
        let password = Data("password: cartouche\n".utf8)
        let version2 = Data([0x30, 0x82, 0x01, 0x00, 0x02, 0x01, 0x02, 0x30])
        for data in [cer, pem, password, version2, Data([0x30]), Data([0x30, 0x85, 0, 0, 0, 0, 0x02, 0x01, 0x03])] {
            XCTAssertEqual(CartoucheSigningTrouble.ofFile(data), .notCertificate, "\(Array(data.prefix(8)))")
        }
    }

    func testWhatIOSAnswersThePasswordAndTheKey() {
        XCTAssertNil(CartoucheSigningTrouble.ofKey(status: 0, identities: 1, password: "cartouche"))
        XCTAssertNil(CartoucheSigningTrouble.ofKey(status: 0, identities: 1, password: ""), "a .p12 without a password")
        XCTAssertEqual(CartoucheSigningTrouble.ofKey(status: 0, identities: 0, password: "cartouche"), .noPrivateKey)
        // errSecAuthFailed, errSecPkcs12VerifyFailure, errSecPassphraseRequired.
        for status: Int32 in [-25293, -25264, -25260] {
            XCTAssertEqual(CartoucheSigningTrouble.ofKey(status: status, identities: 0, password: "Cartouche"), .wrongPassword)
            XCTAssertEqual(CartoucheSigningTrouble.ofKey(status: status, identities: 0, password: ""), .passwordNeeded)
        }
        // errSecDecode, errSecUnknownFormat: damaged, or cut short.
        for status: Int32 in [-26275, -25257, -50] {
            XCTAssertEqual(CartoucheSigningTrouble.ofKey(status: status, identities: 0, password: "cartouche"), .unreadableKey)
        }
    }

    func testTheOutcomesAreTheTelemetrysNames() {
        // signing.imported's outcome (telemetry/README.md): a name a
        // programmer gave, as the server takes one.
        let all: [CartoucheSigningTrouble] = [.profileFile, .zipFile, .notCertificate, .passwordNeeded, .wrongPassword,
                                             .noPrivateKey, .unreadableKey, .signerRefused, .noOwnProfile,
                                             .ownProfileUnreadable, .expired, .invalidProfile, .mismatch]
        for trouble in all {
            XCTAssertNotNil(trouble.rawValue.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,31}$", options: .regularExpression), trouble.rawValue)
        }
        XCTAssertEqual(Set(all.map(\.rawValue)).count, all.count)
    }

    func testSigningImportedSaysTheNumberIOSAnswered() throws {
        // The tour of 27 November: 8 imports refused as unreadableKey on 3
        // new copies in iOS 27.0, without what iOS answered. Up to 0.16.2,
        // signing.imported sent only `via` and `outcome`.
        XCTAssertEqual(CartoucheSigningMeasure.fields(via: "setup", outcome: "unreadableKey", status: -26275),
                       ["via": .text("setup"), "outcome": .text("unreadableKey"), "status": .number(-26275)])
        XCTAssertEqual(CartoucheSigningMeasure.fields(via: "setup", outcome: "wrongPassword", status: -25293)["status"], .number(-25293))
        // iOS opened it (0), or the import never asked it: no number.
        XCTAssertEqual(CartoucheSigningMeasure.fields(via: "setup", outcome: "noPrivateKey", status: 0),
                       ["via": .text("setup"), "outcome": .text("noPrivateKey")])
        XCTAssertEqual(CartoucheSigningMeasure.fields(via: "installer", outcome: "imported", status: nil),
                       ["via": .text("installer"), "outcome": .text("imported")])
        // The server takes it, and telemetry/README.md tells it.
        let context = CartoucheTelemetryContext(install: "8c1f6c2e-7a2f-4e19-8c3d-2f6a9b0e1d7c", cartouche: "0.16.2",
                                                device: "iPhone18,2", ios: "27.0", language: "en")
        let fields = CartoucheSigningMeasure.fields(via: "setup", outcome: "unreadableKey", status: -26275)
        let report = CartoucheEventReport(id: "3d9b2f5e-0000-4000-8000-000000000001", seq: 1, context: context,
                                          name: CartoucheSigningMeasure.event, fields: fields)
        XCTAssertEqual(report?.fields, fields)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../telemetry/README.md").standardizedFileURL
        let readme = try String(contentsOf: url, encoding: .utf8)
        let row = try XCTUnwrap(readme.components(separatedBy: "\n").first { $0.hasPrefix("| `\(CartoucheSigningMeasure.event)` |") })
        XCTAssertTrue(row.contains("`status`"), "signing.imported's row should tell status")
    }
}
