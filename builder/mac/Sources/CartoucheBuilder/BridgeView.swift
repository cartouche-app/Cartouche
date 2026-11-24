//
//  BridgeView.swift
//  Cartouche Builder
//
//  The bridge to Cartouche on the iPhone: on, this Mac is a storage place
//  Cartouche can add, its games folder (on the Mac or the NAS) and a saves
//  folder. An iPhone pairs once, with a code shown on both screens. The
//  games played on this Mac keep their saves in step with the iPhone's in
//  that saves folder, or in Cartouche's saves folder on a share, which the
//  page finds on the shares mounted here; or in the saves folder the player
//  chose on the iPhone, when it is on one of their connections, which the
//  page then shows in its place. The games folder chosen on the iPhone,
//  when it is on one of their connections, the page shows too: the
//  Builder sends its games there (IPhoneGames.swift), how many went, the
//  one going, or why none goes. With Tailscale, which the player
//  installs apart on this Mac and on the iPhone, the paired iPhones reach
//  this Mac away from home too: the page says whether it is on, and this
//  Mac's address there, by which an iPhone pairs when Bonjour cannot see
//  the Mac (CartoucheTailscale.swift).
//

import BuilderKit
import CartoucheCore
import SwiftUI

struct BridgeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bridge: BridgeController
    /// Cartouche's saves folders on the shares mounted on this Mac.
    @State private var found: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "iPhone", subtitle: tr("Cartouche reads its games from this Mac", "Cartouche lit ses jeux depuis ce Mac", "Cartouche lee sus juegos desde este Mac", "Cartouche liest seine Spiele von diesem Mac"))
                switchCard
                if bridge.enabled {
                    howTo
                    tailscale
                    folders
                    devices
                }
                macSaves
                IPhoneGamesSection(games: model.iPhoneGames)
            }
            .padding(28)
        }
        .task {
            guard !model.sample else { return }
            // A share that does not answer must not hold the window.
            found = await Task.detached(priority: .utility) { MacSavesFolder.found() }.value
        }
    }

    /// The saves of the games played on this Mac: kept in step with the
    /// iPhone's, or not, and where.
    private var macSaves: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Games played on this Mac", "Jeux joués sur ce Mac", "Juegos jugados en este Mac", "Auf diesem Mac gespielte Spiele").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Card(padding: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: Binding(get: { AppSettings.macSaves }, set: { model.setMacSaves($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Keep their saves with the iPhone’s", "Garder leurs sauvegardes en phase avec l’iPhone", "Mantener sus partidas guardadas al día con las del iPhone", "Ihre Spielstände mit denen des iPhones abgleichen"))
                                .font(.callout.weight(.medium))
                            Text(tr("Before each game, the newest copy comes from the saves folder; this Mac’s go there a few seconds after the game saves, as Cartouche does on the iPhone.",
                                    "Avant chaque partie, la copie la plus récente arrive du dossier des sauvegardes ; celles de ce Mac y partent quelques secondes après chaque sauvegarde du jeu, comme le fait Cartouche sur l’iPhone.",
                                    "Antes de cada partida, la copia más reciente llega de la carpeta de partidas guardadas; las de este Mac van allí unos segundos después de que el juego guarde, como hace Cartouche en el iPhone.",
                                    "Vor jedem Spiel kommt die neueste Kopie aus dem Spielstandordner; die dieses Mac gehen wenige Sekunden nach jedem Speichern des Spiels dorthin, wie es Cartouche auf dem iPhone tut."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Divider().padding(.leading, 12)
                    if let place = model.macGames.folder, let connection = place.connection {
                        // The iPhone's, on one of the player's connections:
                        // chosen there, or on the console's Storage page.
                        let name = ConsoleLink.connectionName(connection) ?? tr("its connection", "sa connexion", "su conexión", "seine Verbindung")
                        FolderRow(symbol: "externaldrive.connected.to.line.below", title: tr("Saves folder", "Dossier des sauvegardes", "Carpeta de partidas guardadas", "Spielstandordner"),
                                  path: place.path.isEmpty ? name : name + " › " + place.path.split(separator: "/").joined(separator: " › "),
                                  note: tr("The iPhone’s, chosen on it or on the console’s Storage page: this Mac reaches it through the same connection, “\(name)”.",
                                           "Celui de l’iPhone, choisi sur lui ou dans la page Stockage de la console : ce Mac l’atteint par la même connexion, « \(name) ».",
                                           "La del iPhone, elegida en él o en la página Almacenamiento de la consola: este Mac llega a ella por la misma conexión, “\(name)”.",
                                           "Der des iPhones, auf ihm oder auf der Seite „Speicher“ der Konsole gewählt: Dieser Mac erreicht ihn über dieselbe Verbindung, „\(name)“.")) {
                            EmptyView()
                        }
                    } else {
                        FolderRow(symbol: "externaldrive.badge.icloud", title: tr("Saves folder", "Dossier des sauvegardes", "Carpeta de partidas guardadas", "Spielstandordner"), path: bridge.saves.path,
                                  note: bridge.savesIsDefault ? tr("In Cartouche’s folder", "Dans le dossier de Cartouche", "En la carpeta de Cartouche", "Im Ordner von Cartouche") : nil) {
                            Button(tr("Change…", "Changer…", "Cambiar…", "Ändern …")) {
                                if let url = FolderPicker.choose(title: tr("Where the saves go", "Où vont les sauvegardes", "Adónde van las partidas guardadas", "Wohin die Spielstände gehen"), directory: bridge.saves) {
                                    bridge.setSaves(url)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    if model.macGames.folder?.connection == nil,
                       let share = found.first(where: { $0.standardizedFileURL != bridge.saves.standardizedFileURL }) {
                        Divider().padding(.leading, 48)
                        let volume = share.pathComponents.count > 2 ? share.pathComponents[2] : share.lastPathComponent
                        FolderRow(symbol: "server.rack", title: tr("Cartouche’s saves found on “\(volume)”", "Sauvegardes de Cartouche trouvées sur « \(volume) »", "Partidas guardadas de Cartouche encontradas en “\(volume)”", "Spielstände von Cartouche auf „\(volume)“ gefunden"),
                                  path: share.path,
                                  note: tr("The iPhone keeps its copies there: use it, for this Mac’s saves to meet them.",
                                           "L’iPhone y garde ses copies : utilisez-le, pour que les sauvegardes de ce Mac les retrouvent.",
                                           "El iPhone guarda allí sus copias: úsala, para que las partidas guardadas de este Mac se encuentren con ellas.",
                                           "Das iPhone bewahrt dort seine Kopien auf: Verwende ihn, damit die Spielstände dieses Mac sie finden.")) {
                            Button(tr("Use it", "L’utiliser", "Usarla", "Verwenden")) { bridge.setSaves(share) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var switchCard: some View {
        Card(padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.gradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Share with Cartouche on the iPhone", "Partager avec Cartouche sur l’iPhone", "Compartir con Cartouche en el iPhone", "Mit Cartouche auf dem iPhone teilen"))
                        .font(.headline)
                    Text(stateText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { bridge.enabled }, set: { bridge.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }
        }
    }

    private var stateText: String {
        guard bridge.enabled else {
            return tr("Off. On, the iPhone finds this Mac on your Wi-Fi or through its cable, and installs games from it, encrypted on the way, once paired.",
                      "Désactivé. Activé, l’iPhone trouve ce Mac sur votre Wi-Fi ou par son câble, et y installe ses jeux, chiffrés en chemin, une fois associé.",
                      "Desactivado. Activado, el iPhone encuentra este Mac en tu Wi-Fi o por su cable, e instala juegos desde él, cifrados por el camino, una vez emparejado.",
                      "Aus. Eingeschaltet findet das iPhone diesen Mac in deinem WLAN oder über sein Kabel und installiert Spiele von ihm, unterwegs verschlüsselt, sobald es gekoppelt ist.")
        }
        switch bridge.state {
        case .stopped, .starting: return tr("Starting…", "Démarrage…", "Iniciando…", "Wird gestartet …")
        case .running:
            return tr("Visible on your network as “\(bridge.name)”, and to an iPhone plugged into this Mac.",
                      "Visible sur votre réseau sous « \(bridge.name) », et par un iPhone branché à ce Mac.",
                      "Visible en tu red como “\(bridge.name)”, y para un iPhone conectado a este Mac.",
                      "In deinem Netzwerk als „\(bridge.name)“ sichtbar, und für ein an diesen Mac angeschlossenes iPhone.")
                + (bridge.connected.isEmpty ? "" : tr(" An iPhone is connected: the Mac stays awake.", " Un iPhone est connecté : le Mac reste éveillé.", " Hay un iPhone conectado: el Mac se mantiene activo.", " Ein iPhone ist verbunden: Der Mac bleibt wach."))
        case let .failed(error):
            return tr("Could not start: ", "Démarrage impossible : ", "No se pudo iniciar: ", "Start nicht möglich: ") + error
        }
    }

    private var howTo: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("On the iPhone", "Sur l’iPhone", "En el iPhone", "Auf dem iPhone"))
                    .font(.headline)
                Step(number: 1, text: tr("Open Cartouche, then System › Storage › Add your Mac.", "Ouvrez Cartouche, puis Système › Stockage › Ajouter votre Mac.", "Abre Cartouche y luego Sistema › Almacenamiento › Añadir tu Mac.", "Öffne Cartouche, dann System › Speicher › Deinen Mac hinzufügen."))
                Step(number: 2, text: tr("Choose “\(bridge.name)” under Macs nearby, with the iPhone plugged into this Mac by a cable, or on the same Wi-Fi.",
                                         "Choisissez « \(bridge.name) » sous Macs à proximité, l’iPhone branché à ce Mac par un câble, ou sur le même Wi-Fi.",
                                         "Elige “\(bridge.name)” en Mac cercanos, con el iPhone conectado a este Mac por un cable, o en la misma red Wi-Fi.",
                                         "Wähle „\(bridge.name)“ unter „Macs in der Nähe“, mit dem iPhone per Kabel an diesen Mac angeschlossen oder im selben WLAN."))
                Step(number: 3, text: tr("A code shows on both screens: allow the iPhone here if they are the same.",
                                         "Un code s’affiche sur les deux écrans : autorisez l’iPhone ici s’ils sont identiques.",
                                         "Aparece un código en ambas pantallas: permite el iPhone aquí si son iguales.",
                                         "Auf beiden Bildschirmen erscheint ein Code: Erlaube das iPhone hier, wenn sie gleich sind."))
            }
        }
    }

    /// Tailscale on this Mac: on, its address in the player's tailnet,
    /// which the paired iPhones learn and try away from home, and by which
    /// one pairs from afar; off, where to get it.
    private var tailscale: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "network")
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(bridge.tailnet.isEmpty ? Theme.indigo : Color.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Away from home, with Tailscale", "Hors de chez vous, avec Tailscale", "Fuera de casa, con Tailscale", "Unterwegs, mit Tailscale"))
                        .font(.headline)
                    if let address = bridge.tailnet.first {
                        Text(tr("Tailscale is on here: the paired iPhones learn this Mac’s Tailscale address, and reach it there away from home when Tailscale is on. An iPhone away from home pairs by this address, under Add your Mac.",
                                "Tailscale est allumé ici : les iPhone associés apprennent l’adresse Tailscale de ce Mac et l’y joignent hors de chez vous quand Tailscale est allumé. Un iPhone hors de chez vous s’associe par cette adresse, sous Ajouter votre Mac.",
                                "Tailscale está activado aquí: los iPhone emparejados conocen la dirección Tailscale de este Mac y llegan a él por ella fuera de casa cuando Tailscale está activado. Un iPhone fuera de casa se empareja por esta dirección, en Añadir tu Mac.",
                                "Tailscale ist hier eingeschaltet: Die gekoppelten iPhones erfahren die Tailscale-Adresse dieses Mac und erreichen ihn darüber unterwegs, wenn Tailscale eingeschaltet ist. Ein iPhone unterwegs koppelt über diese Adresse, unter „Deinen Mac hinzufügen“."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(address)
                            .font(.callout.monospaced().weight(.medium))
                            .textSelection(.enabled)
                    } else {
                        Text(tr("Install Tailscale on this Mac and on the iPhone, signed in to the same account: the iPhone then reaches this Mac away from home too.",
                                "Installez Tailscale sur ce Mac et sur l’iPhone, connectés au même compte : l’iPhone joint alors ce Mac même hors de chez vous.",
                                "Instala Tailscale en este Mac y en el iPhone, con la sesión iniciada en la misma cuenta: el iPhone llega entonces a este Mac también fuera de casa.",
                                "Installiere Tailscale auf diesem Mac und auf dem iPhone, mit demselben Account angemeldet: Dann erreicht das iPhone diesen Mac auch unterwegs."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link(tr("Download Tailscale for Mac", "Télécharger Tailscale pour Mac", "Descargar Tailscale para Mac", "Tailscale für Mac laden"), destination: CartoucheTailscale.macDownload)
                            .font(.callout)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("What the iPhone sees", "Ce que voit l’iPhone", "Lo que ve el iPhone", "Was das iPhone sieht").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Card(padding: 6) {
                VStack(spacing: 0) {
                    FolderRow(symbol: "gamecontroller", title: tr("Games", "Jeux", "Juegos", "Spiele"),
                              path: bridge.games?.path ?? tr("Choose a games folder in the settings", "Choisissez un dossier des jeux dans les réglages", "Elige una carpeta de juegos en los ajustes", "Wähle einen Spieleordner in den Einstellungen"),
                              note: model.library?.folders?.games?.isShare == true ? tr("On your NAS, through this Mac", "Sur votre NAS, à travers ce Mac", "En tu NAS, a través de este Mac", "Auf deinem NAS, über diesen Mac") : nil) {
                        EmptyView()
                    }
                    Divider().padding(.leading, 48)
                    FolderRow(symbol: "externaldrive.badge.icloud", title: tr("Saves", "Sauvegardes", "Partidas guardadas", "Spielstände"), path: bridge.saves.path,
                              note: bridge.savesIsDefault ? tr("In Cartouche’s folder", "Dans le dossier de Cartouche", "En la carpeta de Cartouche", "Im Ordner von Cartouche") : nil) {
                        Button(tr("Change…", "Changer…", "Cambiar…", "Ändern …")) {
                            if let url = FolderPicker.choose(title: tr("Where the iPhone’s saves go", "Où vont les sauvegardes de l’iPhone", "Adónde van las partidas guardadas del iPhone", "Wohin die Spielstände des iPhones gehen"), directory: bridge.saves) {
                                bridge.setSaves(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Paired iPhones", "iPhone associés", "iPhone emparejados", "Gekoppelte iPhones").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Card(padding: 6) {
                if bridge.devices.isEmpty {
                    Text(tr("None yet.", "Aucun pour l’instant.", "Ninguno por ahora.", "Noch keines."))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(bridge.devices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { Divider().padding(.leading, 48) }
                            HStack(spacing: 14) {
                                Image(systemName: "iphone")
                                    .font(.title3)
                                    .frame(width: 24)
                                    .foregroundStyle(bridge.connected.contains(device.id) ? Color.green : Theme.indigo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.callout.weight(.medium))
                                    Text(bridge.cabled.contains(device.id)
                                         ? tr("Connected now, by cable", "Connecté maintenant, par câble", "Conectado ahora, por cable", "Jetzt verbunden, per Kabel")
                                         : bridge.connected.contains(device.id)
                                         ? tr("Connected now", "Connecté maintenant", "Conectado ahora", "Jetzt verbunden")
                                         : tr("Paired ", "Associé ", "Emparejado ", "Gekoppelt ") + Format.relative(device.paired) + (device.seen.map { tr(", seen ", ", vu ", ", visto ", ", gesehen ") + Format.relative($0) } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(tr("Remove", "Retirer", "Quitar", "Entfernen"), role: .destructive) { bridge.forget(device) }
                                    .controlSize(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }
}

struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.indigo))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The iPhone's games folder, on one of the player's connections: the
/// Builder sends its games there, the file going, how many went, or why
/// none goes; nothing when the iPhone chose none there.
private struct IPhoneGamesSection: View {
    @ObservedObject var games: IPhoneGames

    var body: some View {
        if let folder = games.folder {
            let name = ConsoleLink.connectionName(folder.connection) ?? tr("its connection", "sa connexion", "su conexión", "seine Verbindung")
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("The iPhone’s games folder", "Dossier des jeux de l’iPhone", "Carpeta de juegos del iPhone", "Spieleordner des iPhones").uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Card(padding: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        FolderRow(symbol: "externaldrive.connected.to.line.below", title: tr("Games folder", "Dossier des jeux", "Carpeta de juegos", "Spieleordner"),
                                  path: folder.path.isEmpty ? name : name + " › " + folder.path.split(separator: "/").joined(separator: " › "),
                                  note: tr("The iPhone’s, chosen on it or on the console’s Storage page: this Mac sends its IPAs and its Mac apps there too, through the same connection, “\(name)”, the newest first, and never removes anything there.",
                                           "Celui de l’iPhone, choisi sur lui ou dans la page Stockage de la console : ce Mac y envoie aussi ses IPA et ses apps Mac, par la même connexion, « \(name) », les plus récentes d’abord, et n’y supprime jamais rien.",
                                           "La del iPhone, elegida en él o en la página Almacenamiento de la consola: este Mac también envía allí sus IPA y sus apps de Mac, por la misma conexión, “\(name)”, las más recientes primero, y nunca borra nada allí.",
                                           "Der des iPhones, auf ihm oder auf der Seite „Speicher“ der Konsole gewählt: Dieser Mac sendet auch seine IPAs und seine Mac-Apps dorthin, über dieselbe Verbindung, „\(name)“, die neuesten zuerst, und löscht dort nie etwas.")) {
                            Button(tr("Send now", "Envoyer maintenant", "Enviar ahora", "Jetzt senden")) { games.round() }
                                .controlSize(.small)
                                .disabled(games.progress != nil)
                        }
                        Divider().padding(.leading, 48)
                        status(name: name)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        if !games.offers.isEmpty {
                            Divider().padding(.leading, 48)
                            line(symbol: "arrow.down.circle",
                                 games.offers.count == 1
                                     ? tr("1 Mac app another Mac sent there: install it from the console’s library.",
                                          "1 app Mac envoyée par un autre Mac : installez-la depuis la bibliothèque de la console.",
                                          "1 app de Mac que otro Mac envió allí: instálala desde la biblioteca de la consola.",
                                          "1 Mac-App, die ein anderer Mac dorthin gesendet hat: Installiere sie aus der Bibliothek der Konsole.")
                                     : tr("\(games.offers.count) Mac apps another Mac sent there: install them from the console’s library.",
                                          "\(games.offers.count) apps Mac envoyées par un autre Mac : installez-les depuis la bibliothèque de la console.",
                                          "\(games.offers.count) apps de Mac que otro Mac envió allí: instálalas desde la biblioteca de la consola.",
                                          "\(games.offers.count) Mac-Apps, die ein anderer Mac dorthin gesendet hat: Installiere sie aus der Bibliothek der Konsole."))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    /// The file going, why none goes, or how many went.
    @ViewBuilder
    private func status(name: String) -> some View {
        if let going = games.progress {
            VStack(alignment: .leading, spacing: 6) {
                line(symbol: "arrow.up.circle",
                     going.packing
                         ? tr("Packing the Mac app of “\(going.game)” in one file, as a NAS keeps it (\(going.index) of \(going.count))…",
                              "Mise en un seul fichier de l’app Mac de « \(going.game) », comme la garde un NAS (\(going.index) sur \(going.count))…",
                              "Empaquetando la app de Mac de “\(going.game)” en un solo archivo, como la guarda un NAS (\(going.index) de \(going.count))…",
                              "Die Mac-App von „\(going.game)“ wird in eine Datei gepackt, wie ein NAS sie aufbewahrt (\(going.index) von \(going.count)) …")
                         : tr("Sending “\(going.game)” (\(going.index) of \(going.count)): \(Format.size(going.done)) of \(Format.size(going.total))",
                              "Envoi de « \(going.game) » (\(going.index) sur \(going.count)) : \(Format.size(going.done)) sur \(Format.size(going.total))",
                              "Enviando “\(going.game)” (\(going.index) de \(going.count)): \(Format.size(going.done)) de \(Format.size(going.total))",
                              "„\(going.game)“ wird gesendet (\(going.index) von \(going.count)): \(Format.size(going.done)) von \(Format.size(going.total))"))
                if going.packing {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.leading, 38)
                } else {
                    ProgressView(value: Double(min(going.done, going.total)), total: Double(max(going.total, 1)))
                        .padding(.leading, 38)
                }
            }
        } else if let stopped = games.stopped {
            switch stopped {
            case .offline:
                line(symbol: "wifi.slash", tr("“\(name)” does not answer from this Mac: its games go there once it does.",
                                              "« \(name) » ne répond pas depuis ce Mac : ses jeux y partiront dès qu’il répondra.",
                                              "“\(name)” no responde desde este Mac: sus juegos irán allí en cuanto responda.",
                                              "„\(name)“ antwortet nicht von diesem Mac aus: Seine Spiele gehen dorthin, sobald es antwortet."), warning: true)
            case .readOnly:
                line(symbol: "lock", tr("Your account may only read this folder: this Mac’s games cannot go there.",
                                        "Votre compte ne peut que lire ce dossier : les jeux de ce Mac ne peuvent pas y aller.",
                                        "Tu cuenta solo puede leer esta carpeta: los juegos de este Mac no pueden ir allí.",
                                        "Dein Account darf diesen Ordner nur lesen: Die Spiele dieses Mac können nicht dorthin."), warning: true)
            case let .noRoom(needed, free):
                line(symbol: "externaldrive.badge.exclamationmark",
                     tr("Not enough room there for the next game: \(Format.size(needed)) needed, \(Format.size(free)) left.",
                        "Pas assez de place pour le jeu suivant : \(Format.size(needed)) nécessaires, \(Format.size(free)) libres.",
                        "No hay espacio suficiente allí para el siguiente juego: se necesitan \(Format.size(needed)), quedan \(Format.size(free)).",
                        "Dort ist nicht genug Platz für das nächste Spiel: \(Format.size(needed)) benötigt, \(Format.size(free)) frei."), warning: true)
            }
        } else if let failure = games.failure {
            line(symbol: "exclamationmark.triangle", tr("The last sending stopped, and starts again at the next look: \(failure)",
                                                        "Le dernier envoi s’est arrêté, et reprendra au prochain passage : \(failure)",
                                                        "El último envío se detuvo y se reanuda en la próxima revisión: \(failure)",
                                                        "Der letzte Versand wurde gestoppt und beginnt bei der nächsten Prüfung erneut: \(failure)"), warning: true)
        } else if let checked = games.lastRound {
            line(symbol: games.sentCount == games.total ? "checkmark.circle" : "arrow.up.circle",
                 games.total == 0
                     ? tr("No game of this Mac to send yet · looked \(Format.relative(checked))",
                          "Aucun jeu de ce Mac à envoyer pour l’instant · vérifié \(Format.relative(checked))",
                          "Aún no hay ningún juego de este Mac que enviar · revisado \(Format.relative(checked))",
                          "Noch kein Spiel dieses Mac zu senden · geprüft \(Format.relative(checked))")
                     : tr("\(games.sentCount) of this Mac’s \(games.total) files are there · looked \(Format.relative(checked))",
                          "\(games.sentCount) des \(games.total) fichiers de ce Mac y sont · vérifié \(Format.relative(checked))",
                          "\(games.sentCount) de los \(games.total) archivos de este Mac están allí · revisado \(Format.relative(checked))",
                          "\(games.sentCount) der \(games.total) Dateien dieses Mac sind dort · geprüft \(Format.relative(checked))"))
        } else {
            line(symbol: "clock", tr("Looking at the folder…", "Vérification du dossier…", "Revisando la carpeta…", "Ordner wird geprüft …"))
        }
    }

    private func line(symbol: String, _ text: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(warning ? Color.orange : Theme.indigo)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(warning ? Color.orange : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct FolderRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let path: String
    let note: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
