//
//  Theme.swift
//  Cartouche Builder
//
//  Cartouche's colours (app/icon/make_icon.py: indigo to pink), the cards
//  the pages are made of, and a game's state as the library shows it.
//

import BuilderKit
import CartoucheCore
import SwiftUI

enum Theme {
    static let indigo = Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255)
    static let pink = Color(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255)
    static let gradient = LinearGradient(colors: [indigo, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let corner: CGFloat = 14
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

/// The window's columns: the sidebar, the page, and the game's sheet beside
/// the library. The sheet is a column of the library's own, of one width,
/// not the system's inspector: on macOS 27 the inspector, inside the split
/// view's page, made the page wider than the window at each update, the
/// page and the sidebar spilled past both edges, and AppKit went round its
/// constraint passes until it ended the app (11 November). The window's
/// least width holds the sidebar at its widest, a page and the sheet; each
/// page lays itself out to fit (PageHeader, DueCard), and the layout check
/// (LayoutCheck.swift) holds them to it.
enum Columns {
    static let sidebar: (least: CGFloat, ideal: CGFloat, most: CGFloat) = (200, 220, 280)
    static let page: CGFloat = 340
    static let sheet: CGFloat = 320
    static let window = CGSize(width: sidebar.most + page + sheet, height: 620)
}

/// A page's title and what it is about, above its cards, with its button
/// or its picker beside it, or under it when the page is too narrow.
struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titles
                Spacer(minLength: 12)
                accessory
            }
            VStack(alignment: .leading, spacing: 14) {
                titles
                accessory
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String = "") {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// How a game is, in the library: its words, its colour and its symbol.
struct GameLook {
    let text: String
    let color: Color
    let symbol: String

    init(_ game: Game, progress: GameProgress?) {
        if let progress {
            if progress.state == "building" {
                let percent = (progress.overall ?? progress.frac).map { " " + Format.percent($0) } ?? ""
                // What it makes now: its IPA, for the iPhone, or its app for
                // this Mac, after its IPA or alone (decision 127).
                switch progress.targets?.now {
                case .mac?:
                    text = tr("Building for this Mac", "Construction pour ce Mac", "Compilando para este Mac", "Wird für diesen Mac erstellt") + percent
                    symbol = "macbook"
                case .iPhone?:
                    text = tr("Building for the iPhone", "Construction pour l’iPhone", "Compilando para el iPhone", "Wird für das iPhone erstellt") + percent
                    symbol = "iphone"
                case nil:
                    text = tr("Building", "Construction", "Compilando", "Wird erstellt") + percent
                    symbol = "hammer.fill"
                }
                color = Theme.indigo
            } else {
                text = tr("Waiting its turn", "En attente", "En espera", "Wartet")
                color = .secondary
                symbol = "clock.fill"
            }
            return
        }
        switch game.state {
        case .due:
            let own = game.changeCounts?.own ?? 0
            if game.reasons == ["new"] {
                text = tr("Never built", "Jamais construit", "Nunca compilado", "Nie erstellt")
            } else if game.dueForMacAppAlone {
                // Its IPA up to date, its app for this Mac to build.
                text = tr("To build for this Mac", "À construire pour ce Mac", "Por compilar para este Mac", "Für diesen Mac zu erstellen")
                color = .orange
                symbol = "macbook"
                return
            } else if own > 0 {
                text = tr("Improved: \(own) change\(own == 1 ? "" : "s")", "Amélioré : \(own) changement\(own == 1 ? "" : "s")", "Mejorado: \(own) cambio\(own == 1 ? "" : "s")", "Verbessert: \(own) Änderung\(own == 1 ? "" : "en")")
            } else {
                text = tr("To rebuild", "À reconstruire", "Por recompilar", "Neu zu erstellen")
            }
            color = .orange
            symbol = "sparkles"
        case .upToDate where game.mac?.failed == true:
            // Its IPA up to date, its Mac app failed at this nxnative commit.
            text = tr("Mac app failed", "Échec de l’app Mac", "App de Mac fallida", "Mac-App fehlgeschlagen")
            color = .orange
            symbol = "exclamationmark.triangle.fill"
        case .upToDate:
            text = tr("Up to date", "À jour", "Al día", "Aktuell")
            color = .green
            symbol = "checkmark.circle.fill"
        case .failed:
            text = tr("Build failed", "Échec de construction", "Compilación fallida", "Build fehlgeschlagen")
            color = .red
            symbol = "exclamationmark.triangle.fill"
        case .notFollowed:
            text = tr("Not followed", "Pas suivi", "Sin seguir", "Nicht verfolgt")
            color = .secondary
            symbol = "pause.circle.fill"
        case .noProfile:
            text = tr("No nxnative profile", "Sans profil nxnative", "Sin perfil de nxnative", "Ohne Profil von nxnative")
            color = .secondary
            symbol = "questionmark.circle.fill"
        case .noSource:
            text = tr("IPA only", "IPA seule", "Solo IPA", "Nur IPA")
            color = .teal
            symbol = "shippingbox.fill"
        case .building:
            text = tr("Building", "Construction", "Compilando", "Wird erstellt")
            color = Theme.indigo
            symbol = "hammer.fill"
        case .queued:
            text = tr("Waiting its turn", "En attente", "En espera", "Wartet")
            color = .secondary
            symbol = "clock.fill"
        case .unknown:
            text = "—"
            color = .secondary
            symbol = "circle"
        }
    }
}

/// A reason a game is due, in the player's words.
func reasonText(_ reason: String) -> String {
    switch reason {
    case "new": return tr("Never built", "Jamais construit", "Nunca compilado", "Nie erstellt")
    case "missing": return tr("Its IPA is missing", "Son IPA a disparu", "Falta su IPA", "Seine IPA fehlt")
    case "source": return tr("New files in its folder", "Nouveaux fichiers dans son dossier", "Archivos nuevos en su carpeta", "Neue Dateien in seinem Ordner")
    case "profile": return tr("nxnative changed its profile", "nxnative a changé son profil", "nxnative cambió su perfil", "nxnative hat sein Profil geändert")
    case "named": return tr("A fix of nxnative names it", "Un correctif de nxnative le nomme", "Una corrección de nxnative lo nombra", "Eine Korrektur von nxnative nennt es")
    case "shared": return tr("nxnative’s shared code changed", "Le code commun de nxnative a changé", "El código compartido de nxnative cambió", "Der gemeinsame Code von nxnative hat sich geändert")
    case "toolchain": return tr("Xcode changed", "Xcode a changé", "Xcode cambió", "Xcode hat sich geändert")
    case "unknown_base": return tr("Built from a commit main no longer has", "Construit depuis un commit absent de main", "Compilado desde un commit que main ya no tiene", "Von einem Commit erstellt, den main nicht mehr hat")
    case "failed_here": return tr("Failed at this commit of nxnative", "Échec à ce commit de nxnative", "Falló en este commit de nxnative", "Bei diesem Commit von nxnative fehlgeschlagen")
    case "up_to_date": return tr("Up to date", "À jour", "Al día", "Aktuell")
    case "forced": return tr("Asked for", "Demandé", "Solicitado", "Angefordert")
    case "not_selected": return tr("Not followed: rebuilt only when asked", "Pas suivi : reconstruit seulement à la demande", "Sin seguir: se recompila solo cuando se pide", "Nicht verfolgt: Nur auf Anfrage neu erstellt")
    case "no_profile": return tr("nxnative has no profile for it yet: built once it has one", "nxnative n’a pas encore de profil pour lui : construit dès qu’il en aura un", "nxnative aún no tiene perfil para él: se compila en cuanto lo tenga", "nxnative hat noch kein Profil dafür: Wird erstellt, sobald es eines hat")
    case "no_source": return tr("Its dump is not in the sources folder: its IPA is shown, and rebuilt once the dump is back",
                                "Son dump n’est pas dans le dossier des sources : son IPA est montrée, et reconstruite quand il reviendra",
                                "Su dump no está en la carpeta de fuentes: se muestra su IPA, y se recompila cuando el dump vuelva",
                                "Sein Dump ist nicht im Quellordner: Seine IPA wird gezeigt und neu erstellt, sobald der Dump zurück ist")
    case "mac_new": return tr("Not on this Mac yet: its Mac app is built", "Pas encore sur ce Mac : son app Mac est construite", "Aún no está en este Mac: se compila su app de Mac", "Noch nicht auf diesem Mac: Seine Mac-App wird erstellt")
    case "mac_missing": return tr("Its Mac app is missing", "Son app Mac a disparu", "Falta su app de Mac", "Seine Mac-App fehlt")
    case "mac_behind": return tr("Its Mac app is older than its IPA", "Son app Mac est plus ancienne que son IPA", "Su app de Mac es más antigua que su IPA", "Seine Mac-App ist älter als seine IPA")
    case "no_platform": return tr("Built neither for the iPhone nor for this Mac: turn one of the two on below",
                                  "Construit ni pour l’iPhone ni pour ce Mac : activez l’un des deux ci-dessous",
                                  "No se compila ni para el iPhone ni para este Mac: activa uno de los dos abajo",
                                  "Weder für das iPhone noch für diesen Mac erstellt: Schalte unten eines der beiden ein")
    default: return reason
    }
}

/// A reason a game is due, with how many of nxnative's commits it comes
/// from: never a commit's own words, which are English and long (the
/// sheet lists the commits below).
func whyText(_ reason: String, counts: ChangeCounts?) -> String {
    switch reason {
    case "profile":
        let count = counts?.profile ?? 0
        guard count > 1 else { return reasonText(reason) }
        return tr("nxnative changed its profile (\(count) commits)", "nxnative a changé son profil (\(count) commits)", "nxnative cambió su perfil (\(count) commits)", "nxnative hat sein Profil geändert (\(count) Commits)")
    case "named":
        let count = counts?.named ?? 0
        guard count > 1 else { return reasonText(reason) }
        return tr("\(count) fixes of nxnative name it", "\(count) correctifs de nxnative le nomment", "\(count) correcciones de nxnative lo nombran", "\(count) Korrekturen von nxnative nennen es")
    case "shared":
        let count = counts?.shared ?? 0
        guard count > 1 else { return reasonText(reason) }
        return tr("nxnative’s shared code changed (\(count) commits)", "Le code commun de nxnative a changé (\(count) commits)", "El código compartido de nxnative cambió (\(count) commits)", "Der gemeinsame Code von nxnative hat sich geändert (\(count) Commits)")
    default:
        return reasonText(reason)
    }
}

/// A commit's kind, as a small label.
func changeKindText(_ kind: String) -> String {
    switch kind {
    case "profile": return tr("Profile", "Profil", "Perfil", "Profil")
    case "named": return tr("Fix", "Correctif", "Corrección", "Korrektur")
    default: return tr("Shared", "Commun", "Compartido", "Gemeinsam")
    }
}

/// A batch step's name, in the player's words: ON_IPHONE, as an iPhone
/// shows it, which names "the Mac", not "this Mac". What the build makes,
/// the iPhone's IPA, this Mac's app or both, its own line says (TargetLabel).
func stageText(_ stage: String?, onIPhone: Bool = false) -> String {
    if onIPhone, let mac = macStageOnIPhone(stage ?? "") { return mac }
    switch stage ?? "" {
    case "": return tr("Getting ready", "Préparation", "Preparando", "Vorbereitung")
    case "unpack": return tr("Unpacking the game", "Décompression du jeu", "Descomprimiendo el juego", "Spiel wird entpackt")
    case "extract": return tr("Extracting the game", "Extraction du jeu", "Extrayendo el juego", "Spiel wird extrahiert")
    case "shaders", "shader": return tr("Compiling shaders for the iPhone", "Compilation des shaders pour l’iPhone", "Compilando los shaders para el iPhone", "Shader für das iPhone werden kompiliert")
    case "build", "xcode": return tr("Building the app", "Construction de l’app", "Compilando la app", "App wird erstellt")
    case "pack", "package", "ipa": return tr("Packing the IPA", "Empaquetage de l’IPA", "Empaquetando la IPA", "IPA wird gepackt")
    case "deliver": return tr("Copying to the games folder", "Copie dans le dossier des jeux", "Copiando a la carpeta de juegos", "Wird in den Spieleordner kopiert")
    // Its app for this Mac (nxnative's --platform mac-app, then macapps.py).
    case "Mac shaders": return tr("Compiling shaders for this Mac", "Compilation des shaders pour ce Mac", "Compilando los shaders para este Mac", "Shader für diesen Mac werden kompiliert")
    case "Mac host": return tr("Building the game for this Mac", "Construction du jeu pour ce Mac", "Compilando el juego para este Mac", "Spiel wird für diesen Mac erstellt")
    case "Pipeline prebuild", "Pipeline archive", "Prewarm pipelines":
        return tr("Preparing its graphics for this Mac", "Préparation de ses graphismes pour ce Mac", "Preparando sus gráficos para este Mac", "Grafik wird für diesen Mac vorbereitet")
    case "Mac app": return tr("Packing the Mac app", "Assemblage de l’app Mac", "Empaquetando la app de Mac", "Mac-App wird gepackt")
    case "mac_deliver": return tr("Putting the app on this Mac", "Mise en place de l’app sur ce Mac", "Instalando la app en este Mac", "App wird auf diesem Mac abgelegt")
    default: return stage ?? ""
    }
}

/// The steps of its app for the Mac whose words name this Mac, as an iPhone
/// shows them: "the Mac".
private func macStageOnIPhone(_ stage: String) -> String? {
    switch stage {
    case "Mac shaders": return tr("Compiling shaders for the Mac", "Compilation des shaders pour le Mac", "Compilando los shaders para el Mac", "Shader für den Mac werden kompiliert")
    case "Mac host": return tr("Building the game for the Mac", "Construction du jeu pour le Mac", "Compilando el juego para el Mac", "Spiel wird für den Mac erstellt")
    case "Pipeline prebuild", "Pipeline archive", "Prewarm pipelines":
        return tr("Preparing its graphics for the Mac", "Préparation de ses graphismes pour le Mac", "Preparando sus gráficos para el Mac", "Grafik wird für den Mac vorbereitet")
    case "mac_deliver": return tr("Putting the app on the Mac", "Mise en place de l’app sur le Mac", "Instalando la app en el Mac", "App wird auf dem Mac abgelegt")
    default: return nil
    }
}

/// What a build makes, the iPhone's IPA, this Mac's app or both, and the
/// part it makes now, in this window's words (decision 127): on the
/// activity page, the queue, a game's sheet and the menu bar.
struct TargetLabel: View {
    let targets: CartoucheBuildTargets

    var body: some View {
        Label(targetText(targets.line), systemImage: targetSymbol(targets.line))
    }
}

func targetText(_ line: CartoucheBuildTargets.Line) -> String {
    switch line {
    case .iPhone: return tr("For the iPhone", "Pour l’iPhone", "Para el iPhone", "Für das iPhone")
    case .mac: return tr("For this Mac", "Pour ce Mac", "Para este Mac", "Für diesen Mac")
    case .both: return tr("For the iPhone and this Mac", "Pour l’iPhone et ce Mac", "Para el iPhone y este Mac", "Für das iPhone und diesen Mac")
    case .iPhoneThenMac: return tr("For the iPhone, then this Mac", "Pour l’iPhone, puis ce Mac", "Para el iPhone, luego este Mac", "Für das iPhone, dann diesen Mac")
    case .macAfterIPhone: return tr("Done for the iPhone, now for this Mac", "Fait pour l’iPhone, maintenant pour ce Mac", "Hecho para el iPhone, ahora para este Mac", "Fertig für das iPhone, jetzt für diesen Mac")
    }
}

func targetSymbol(_ line: CartoucheBuildTargets.Line) -> String {
    switch line {
    case .iPhone, .iPhoneThenMac: return "iphone"
    case .mac, .macAfterIPhone: return "macbook"
    case .both: return "macbook.and.iphone"
    }
}
