import XCTest
@testable import CartoucheCore

/// The links between Cartouche installed by the player's own SideStore and
/// that SideStore (CartoucheSideStoreLink.swift, docs/decisions/147.md).
final class CartoucheSideStoreLinkTests: XCTestCase {
    /// A pairing file as minimuxer reads one, with the characters base64
    /// escapes in a link: "+", "/" and "=".
    private let pairingFile = Data("<?xml version=\"1.0\"?><plist><dict><key>HostID</key><string>~?>~?>~</string></dict></plist>".utf8)

    /// The answer of SideStore's ExportPairingFileHandler: the file in
    /// base64, escaped with the query characters less ";/?:@&=+$, ".
    private func answer(_ data: Data, scheme: String = "cartouche") -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ";/?:@&=+$, ")
        let escaped = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: allowed)!
        return URL(string: "\(scheme)://pairingFile?data=\(escaped)")!
    }

    func testTheRequestIsTheOneSideStoreAnswers() {
        let request = CartoucheSideStoreLink.pairingRequest(answeringTo: "cartouche")
        XCTAssertEqual(request?.absoluteString, "sidestore://pairing?urlname=cartouche")
        // Never to SideStore's own scheme, which would answer itself.
        XCTAssertNil(CartoucheSideStoreLink.pairingRequest(answeringTo: "sidestore"))
        XCTAssertNil(CartoucheSideStoreLink.pairingRequest(answeringTo: "SideStore"))
        XCTAssertNil(CartoucheSideStoreLink.pairingRequest(answeringTo: ""))
    }

    func testTheAnswerGivesThePairingFileBack() {
        XCTAssertTrue(pairingFile.base64EncodedString().contains("+") || pairingFile.base64EncodedString().contains("/"))
        XCTAssertEqual(CartoucheSideStoreLink.pairingFile(in: answer(pairingFile), scheme: "cartouche"), pairingFile)
        // A "+" that came back as a space, and missing padding, still read.
        let base64 = pairingFile.base64EncodedString()
        let loose = base64.replacingOccurrences(of: "+", with: "%20").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(CartoucheSideStoreLink.pairingFile(in: URL(string: "cartouche://pairingFile?data=\(loose)")!,
                                                          scheme: "cartouche"), pairingFile)
    }

    func testAnyOtherLinkIsNotAnAnswer() {
        let links = [
            "cartouche://cloud/link?code=ABCD-EFGH",
            "cartouche://pairingFile",
            "cartouche://pairingFile?data=",
            "cartouche://pairingFile?data=!!!",
            "cartouche://somethingElse?data=\(pairingFile.base64EncodedString())",
        ]
        for link in links {
            XCTAssertNil(CartoucheSideStoreLink.pairingFile(in: URL(string: link)!, scheme: "cartouche"), link)
        }
        // Another app's scheme, or a file.
        XCTAssertNil(CartoucheSideStoreLink.pairingFile(in: answer(pairingFile, scheme: "other"), scheme: "cartouche"))
        XCTAssertNil(CartoucheSideStoreLink.pairingFile(in: URL(fileURLWithPath: "/tmp/ALTPairingFile.mobiledevicepairing"),
                                                        scheme: "cartouche"))
        // Far larger than a pairing file.
        let large = Data(repeating: 0x41, count: CartoucheSideStoreLink.largestFile + 1)
        XCTAssertNil(CartoucheSideStoreLink.pairingFile(in: answer(large), scheme: "cartouche"))
    }

    /// Increased Memory Limit: once iOS gives it, nothing is left; before
    /// the setup is done, the built-in SideStore cannot sign Cartouche.
    func testWhatIsLeftForIncreasedMemoryLimit() {
        XCTAssertEqual(CartoucheSideStoreMemory(hasIncreasedMemoryLimit: true, setupComplete: false), .granted)
        XCTAssertEqual(CartoucheSideStoreMemory(hasIncreasedMemoryLimit: true, setupComplete: true), .granted)
        XCTAssertEqual(CartoucheSideStoreMemory(hasIncreasedMemoryLimit: false, setupComplete: false), .afterSetup)
        XCTAssertEqual(CartoucheSideStoreMemory(hasIncreasedMemoryLimit: false, setupComplete: true), .reinstall)
    }
}
