//
//  CartoucheSideStoreLink.swift
//  CartoucheCore
//
//  Cartouche installed by the player's own SideStore, from its source for
//  SideStore (app/scripts/sidestore_ipa.py, docs/decisions/147.md), asks
//  that SideStore for its pairing file with a link SideStore already
//  answers: sidestore://pairing?urlname=<scheme>. SideStore opens
//  <scheme>://pairingFile?data=<the file, in base64> in return
//  (ExportPairingFileHandler), which comes back to Cartouche's own scheme.
//  Foundation only, so that swift test checks it (launcher/Package.swift);
//  CartoucheSideStoreInstall.swift opens the link and takes the answer.
//

import Foundation

enum CartoucheSideStoreLink {
    /// The scheme the player's SideStore answers.
    static let storeScheme = "sidestore"
    /// The host of SideStore's answer, as ExportPairingFileHandler writes it.
    static let answerHost = "pairingfile"
    /// A pairing file is a few kilobytes: an answer far larger is no
    /// SideStore's.
    static let largestFile = 1_048_576

    /// The link that asks the player's SideStore for its pairing file, to
    /// be answered at SCHEME, Cartouche's own. Never "sidestore", which the
    /// player's SideStore would answer itself.
    static func pairingRequest(answeringTo scheme: String) -> URL? {
        guard !scheme.isEmpty, scheme.lowercased() != storeScheme else { return nil }
        var components = URLComponents()
        components.scheme = storeScheme
        components.host = "pairing"
        components.queryItems = [URLQueryItem(name: "urlname", value: scheme)]
        return components.url
    }

    /// The pairing file in URL, the answer of the player's SideStore at
    /// SCHEME: nil for any other link.
    static func pairingFile(in url: URL, scheme: String) -> Data? {
        guard !url.isFileURL, url.scheme?.lowercased() == scheme.lowercased(),
              url.host?.lowercased() == answerHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let value = items.first(where: { $0.name == "data" })?.value,
              value.count <= largestFile * 2 else { return nil }
        // SideStore escapes the base64 for the link; URLComponents has
        // undone that, but a "+" that reached Cartouche as a space is put
        // back, and the padding is added when it is missing.
        var base64 = value.replacingOccurrences(of: " ", with: "+")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64), !data.isEmpty, data.count <= largestFile else { return nil }
        return data
    }
}

/// What is left for Cartouche installed by the player's own SideStore,
/// once its setup is done: Increased Memory Limit, which the player's
/// SideStore leaves out on a free team. The built-in SideStore installs
/// Cartouche again once, signed by itself, which asks Apple for it.
enum CartoucheSideStoreMemory: Equatable, Sendable {
    /// iOS gives it to Cartouche: nothing is left.
    case granted
    /// The setup comes first: the built-in SideStore signs with the
    /// player's certificate, through LocalDevVPN and the pairing file, once
    /// signed in.
    case afterSetup
    /// Cartouche can install itself again, with it.
    case reinstall

    init(hasIncreasedMemoryLimit: Bool, setupComplete: Bool) {
        if hasIncreasedMemoryLimit {
            self = .granted
        } else {
            self = setupComplete ? .reinstall : .afterSetup
        }
    }
}
