//
//  BridgeNetwork.swift
//  Cartouche Builder
//
//  How a paired iPhone's connection reaches this Mac, which the bridge's
//  info tells the iPhone (CartoucheMacNetwork, CartoucheTransferSpeed.swift):
//  the cable; the Mac's Wi-Fi, with the band its channel is in, which
//  CoreWLAN reads without asking the player anything (only the network's
//  name needs Location Services); its Ethernet; or another way, Tailscale's
//  tunnel or a VPN's. A Mac on its 2.4 GHz Wi-Fi sends a game three to ten
//  times slower than on 5 GHz: the install's screen on the iPhone and the
//  iPhone page here say so (decision 151).
//
//  Never the network's name nor an address.
//

import CartoucheCore
import Foundation
import Network
#if canImport(CoreWLAN)
import CoreWLAN
#endif

enum BridgeNetwork {
    /// How the network connection CONNECTION reaches this Mac now; nil
    /// before it is ready. BAND: the band of the Wi-Fi interface it names,
    /// CoreWLAN's on the Mac.
    static func of(_ connection: NWConnection,
                   band: (String) -> String? = BridgeNetwork.wifiBand) -> CartoucheMacNetwork? {
        guard let path = connection.currentPath else { return nil }
        let interface = path.availableInterfaces.first
        return network(type: interface?.type, name: interface?.name, band: band)
    }

    /// The network of a connection through an interface of TYPE named
    /// NAME: Tailscale's tunnel, a utun, is "other", whatever it rides on.
    static func network(type: NWInterface.InterfaceType?, name: String?,
                        band: (String) -> String?) -> CartoucheMacNetwork {
        switch type {
        case .wifi:
            return CartoucheMacNetwork(medium: CartoucheMacNetwork.wifi, band: name.flatMap(band))
        case .wiredEthernet:
            return CartoucheMacNetwork(medium: CartoucheMacNetwork.ethernet)
        default:
            return CartoucheMacNetwork(medium: CartoucheMacNetwork.other)
        }
    }

    /// The band of the Wi-Fi interface NAME's channel now, "2.4", "5" or
    /// "6"; nil when CoreWLAN does not say.
    static func wifiBand(of name: String) -> String? {
        #if canImport(CoreWLAN)
        guard let channel = CWWiFiClient.shared().interface(withName: name)?.wlanChannel() else { return nil }
        return CartoucheMacNetwork.band(ofChannelBand: channel.channelBand.rawValue)
        #else
        return nil
        #endif
    }
}

/// What the iPhone page says of a game an iPhone reads now: how fast and
/// how, and, when it is slow or the Mac on its 2.4 GHz Wi-Fi, what would
/// go faster, as the install's screen says it on the iPhone
/// (CartoucheTransferAdvice).
public struct BridgeSendingWords: Equatable {
    /// "Sending a game: 3.1 MB/s, on this Mac's 2.4 GHz Wi-Fi".
    public let line: String
    public let advice: String?

    public init(_ sending: BridgeSending, slow: Bool) {
        let network = sending.network
        var way: String?
        switch network?.medium ?? "" {
        case CartoucheMacNetwork.cable:
            way = tr("by cable", "par câble", "por cable", "per Kabel")
        case CartoucheMacNetwork.wifi:
            if let band = network?.band {
                let shown = L10n.decimalComma ? band.replacingOccurrences(of: ".", with: ",") : band
                way = tr("on this Mac’s \(shown)\u{00A0}GHz Wi-Fi", "par le Wi-Fi \(shown)\u{00A0}GHz de ce Mac",
                         "por la Wi-Fi de \(shown)\u{00A0}GHz de este Mac", "über das \(shown)-GHz-WLAN dieses Mac")
            } else {
                way = tr("on this Mac’s Wi-Fi", "par le Wi-Fi de ce Mac", "por la Wi-Fi de este Mac", "über das WLAN dieses Mac")
            }
        case CartoucheMacNetwork.ethernet:
            way = tr("on this Mac’s Ethernet", "par l’Ethernet de ce Mac", "por el Ethernet de este Mac", "über das Ethernet dieses Mac")
        case CartoucheMacNetwork.other:
            way = tr("through Tailscale or a VPN", "par Tailscale ou un VPN", "a través de Tailscale o una VPN", "über Tailscale oder ein VPN")
        default:
            way = nil
        }
        var line = tr("Sending a game", "Envoie un jeu", "Enviando un juego", "Sendet ein Spiel")
        if let speed = sending.speed { line += tr(": ", "\u{00A0}: ", ": ", ": ") + Format.speed(speed) }
        if let way { line += ", " + way }
        self.line = line

        let travel: CartoucheTransferWay
        switch network?.medium ?? "" {
        case CartoucheMacNetwork.cable: travel = .cable
        case CartoucheMacNetwork.other: travel = .tailnet
        default: travel = .network(mac: network)
        }
        switch CartoucheTransferAdvice.of(way: travel, local: true, slow: slow) {
        case .macOnSlowBand?:
            advice = tr("This Mac is on its 2.4\u{00A0}GHz Wi-Fi, the slowest: a cable between the iPhone and this Mac, or the 5\u{00A0}GHz Wi-Fi, would be much faster.",
                        "Ce Mac est sur le Wi-Fi 2,4\u{00A0}GHz, le plus lent\u{00A0}: un câble entre l’iPhone et ce Mac, ou le Wi-Fi 5\u{00A0}GHz, irait bien plus vite.",
                        "Este Mac está en su Wi-Fi de 2,4\u{00A0}GHz, la más lenta: un cable entre el iPhone y este Mac, o la Wi-Fi de 5\u{00A0}GHz, iría mucho más rápido.",
                        "Dieser Mac ist in seinem 2,4-GHz-WLAN, dem langsamsten: Ein Kabel zwischen dem iPhone und diesem Mac oder das 5-GHz-WLAN wäre viel schneller.")
        case .slowToMac?, .slowNetwork?:
            advice = tr("It is slow: a cable between the iPhone and this Mac, or a 5\u{00A0}GHz Wi-Fi for both, would be much faster.",
                        "C’est lent\u{00A0}: un câble entre l’iPhone et ce Mac, ou un Wi-Fi 5\u{00A0}GHz pour les deux, irait bien plus vite.",
                        "Va lento: un cable entre el iPhone y este Mac, o una Wi-Fi de 5\u{00A0}GHz para ambos, iría mucho más rápido.",
                        "Es ist langsam: Ein Kabel zwischen dem iPhone und diesem Mac oder ein 5-GHz-WLAN für beide wäre viel schneller.")
        case .slowTailnet?:
            advice = tr("It is slow: through Tailscale, the game goes over the internet. At home, on the same Wi-Fi or by cable, it would be much faster.",
                        "C’est lent\u{00A0}: par Tailscale, le jeu passe par internet. À la maison, sur le même Wi-Fi ou par câble, il irait bien plus vite.",
                        "Va lento: a través de Tailscale, el juego pasa por internet. En casa, en la misma Wi-Fi o por cable, iría mucho más rápido.",
                        "Es ist langsam: Über Tailscale geht das Spiel durchs Internet. Zu Hause, im selben WLAN oder per Kabel, wäre es viel schneller.")
        case nil:
            advice = nil
        }
    }
}
