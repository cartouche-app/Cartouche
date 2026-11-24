//
//  GameDetailView.swift
//  Cartouche Builder
//
//  A game's sheet, beside the library: why it is due, nxnative's commits
//  that touched it since its build, its build and its IPA, its app for this
//  Mac, and what can be done: rebuild it, follow it or not, build it for
//  the iPhone, for this Mac or for both, name it as nxnative's commits do,
//  play it on this Mac, its saves kept in step with the iPhone's.
//  nxnative writes its commits in English, a paragraph each: the sheet says
//  why in the player's words, and shows each commit's first lines, the
//  rest when asked.
//

import BuilderKit
import CartoucheCore
import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    let game: Game

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // Before its Build button: no Mac built it (Unbuilt.swift).
                if game.canBuild, game.build == nil, let never = model.unbuilt[game.titleID] {
                    UnbuiltCard(game: never)
                }
                actions
                if model.canPlay(game) {
                    MacPlayCard(game: game, games: model.macGames)
                }
                if game.canBuild {
                    platforms
                }
                if !whyLines.isEmpty {
                    why
                }
                if let progress = model.progress(game.titleID) {
                    ProgressCard(progress: progress)
                }
                if let attempt = game.attempt, game.onIOS, game.state == .failed || ["failed", "skipped"].contains(attempt.result) {
                    failure(attempt)
                }
                if let attempt = game.mac?.attempt, attempt.result == "failed", game.onMac {
                    failure(attempt, mac: true)
                }
                if !game.changes.isEmpty {
                    changes
                }
                build
                if game.onMac || game.mac?.build != nil {
                    macApp
                }
                if game.canBuild {
                    AliasesEditor(game: game)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(game: game)
                .frame(width: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.titleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                let look = GameLook(game, progress: model.progress(game.titleID))
                Label(look.text, systemImage: look.symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(look.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.selection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(tr("Close its sheet", "Fermer sa fiche", "Cerrar su ficha", "Seine Infoseite schließen"))
        }
    }

    @ViewBuilder private var actions: some View {
        if game.canBuild {
            HStack(spacing: 10) {
                if let progress = model.progress(game.titleID) {
                    if progress.state == "building" {
                        // This game alone: the batch goes on with the next.
                        let stopping = model.stopping(game.titleID)
                        Button(role: .destructive) {
                            model.stopBuild(game.titleID)
                        } label: {
                            Label(stopping ? tr("Stopping…", "Arrêt…", "Deteniendo…", "Wird gestoppt …") : tr("Stop", "Arrêter", "Detener", "Stoppen"), systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(stopping)
                        .help(tr("Stops this game’s build; the games waiting are built after it.",
                                 "Arrête la construction de ce jeu ; les jeux en attente se construisent ensuite.",
                                 "Detiene la compilación de este juego; los juegos en espera se compilan después.",
                                 "Stoppt den Build dieses Spiels; die wartenden Spiele werden danach erstellt."))
                    } else {
                        Button {
                            model.takeOut(game.titleID)
                        } label: {
                            Label(tr("Remove from the queue", "Retirer de la file", "Quitar de la cola", "Aus der Warteschlange entfernen"), systemImage: "minus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .disabled(!model.canTakeOut(game.titleID))
                    }
                } else if model.isBuilding {
                    // A build is running, or starting: this one waits its turn.
                    Button {
                        model.build([game.titleID], force: game.state != .due)
                    } label: {
                        Label(tr("Add to the queue", "Ajouter à la file", "Añadir a la cola", "Zur Warteschlange hinzufügen"), systemImage: "text.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canBuild)
                    .help(tr("A build is running: this game is built after it, and after the games waiting.",
                             "Une construction est en cours : ce jeu se construira après elle, et après les jeux en attente.",
                             "Hay una compilación en curso: este juego se compila después de ella y de los juegos en espera.",
                             "Ein Build läuft: Dieses Spiel wird danach erstellt, und nach den wartenden Spielen."))
                } else {
                    // A game never built, with no IPA yet, is built for the
                    // first time; one nxnative improved, rebuilt.
                    let first = game.build == nil && !game.hasIPA
                    Button {
                        model.build([game.titleID], force: game.state != .due)
                    } label: {
                        Label(first ? tr("Build", "Construire", "Compilar", "Erstellen") : game.state == .due ? tr("Rebuild", "Reconstruire", "Recompilar", "Neu erstellen") : tr("Build again", "Construire à nouveau", "Compilar de nuevo", "Erneut erstellen"),
                              systemImage: first ? "hammer.fill" : game.state == .due ? "sparkles" : "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canBuild)
                }
                Toggle(tr("Follow", "Suivre", "Seguir", "Folgen"), isOn: Binding(get: { game.followed }, set: { model.follow(game, $0) }))
                    .toggleStyle(.switch)
                    .help(tr("A followed game is rebuilt when nxnative improves it.", "Un jeu suivi est reconstruit quand nxnative l’améliore.", "Un juego seguido se recompila cuando nxnative lo mejora.", "Ein verfolgtes Spiel wird neu erstellt, wenn nxnative es verbessert."))
            }
        } else {
            Card(padding: 14) {
                Label(tr("Only its IPA is here: put its dump in the sources folder to rebuild it.",
                         "Seule son IPA est là : mettez son dump dans le dossier des sources pour le reconstruire.",
                         "Solo está su IPA: pon su dump en la carpeta de fuentes para recompilarlo.",
                         "Nur seine IPA ist hier: Lege seinen Dump in den Quellordner, um es neu zu erstellen."),
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the game is built for: its IPA for the iPhone, its app for this
    /// Mac, or both; never neither (the engine refuses it: a game built
    /// for neither is one no longer followed). One turned off for every
    /// game in the settings cannot be turned on here.
    private var platforms: some View {
        let config = model.config
        let ios = config?.ios ?? true
        let mac = config?.mac ?? true
        return SheetPart(title: tr("Built for", "Construit pour", "Compilado para", "Erstellt für")) {
            VStack(alignment: .leading, spacing: 10) {
                PlatformToggle(title: "iPhone", symbol: "iphone", detail: iosDetail, on: game.onIOS,
                               locked: !ios ? tr("Turned off for every game in the settings.", "Désactivé pour tous les jeux dans les réglages.", "Desactivado para todos los juegos en los ajustes.", "In den Einstellungen für alle Spiele ausgeschaltet.")
                                            : game.onIOS && !game.onMac ? lastOne : nil) { model.setPlatform(game, "ios", $0) }
                Divider()
                PlatformToggle(title: tr("This Mac", "Ce Mac", "Este Mac", "Dieser Mac"), symbol: "macbook", detail: macDetail, on: game.onMac,
                               locked: !mac ? tr("Turned off for every game in the settings.", "Désactivé pour tous les jeux dans les réglages.", "Desactivado para todos los juegos en los ajustes.", "In den Einstellungen für alle Spiele ausgeschaltet.")
                                            : game.onMac && !game.onIOS ? lastOne : nil) { model.setPlatform(game, "mac", $0) }
            }
        }
    }

    private var lastOne: String {
        tr("A game is built for at least one of the two: to build it for neither, stop following it.",
           "Un jeu se construit pour au moins l’un des deux : pour ne plus le construire du tout, ne le suivez plus.",
           "Un juego se compila para al menos uno de los dos: para no compilarlo para ninguno, deja de seguirlo.",
           "Ein Spiel wird für mindestens eines der beiden erstellt: Um es für keines zu erstellen, folge ihm nicht mehr.")
    }

    private var iosDetail: String {
        guard game.onIOS else { return tr("Its IPA is no longer built.", "Son IPA n’est plus construite.", "Su IPA ya no se compila.", "Seine IPA wird nicht mehr erstellt.") }
        return tr("Its IPA, in the games folder, for Cartouche.", "Son IPA, dans le dossier des jeux, pour Cartouche.", "Su IPA, en la carpeta de juegos, para Cartouche.", "Seine IPA, im Spieleordner, für Cartouche.")
    }

    /// Its Mac app as the engine says it (the next batch builds it, after
    /// its IPA or alone, or it is up to date), else where it goes.
    private var macDetail: String {
        guard game.onMac else {
            if game.hasMacApp { return tr("No longer built: its app stays on this Mac.", "Plus construit : son app reste sur ce Mac.", "Ya no se compila: su app se queda en este Mac.", "Nicht mehr erstellt: Seine App bleibt auf diesem Mac.") }
            if let mac = game.mac, mac.packed, mac.kept {
                return model.gamesOnShare ? tr("No longer built: its app stays on the NAS.", "Plus construit : son app reste sur le NAS.", "Ya no se compila: su app se queda en el NAS.", "Nicht mehr erstellt: Seine App bleibt auf dem NAS.")
                                          : tr("No longer built: its app stays in the games folder.", "Plus construit : son app reste dans le dossier des jeux.", "Ya no se compila: su app se queda en la carpeta de juegos.", "Nicht mehr erstellt: Seine App bleibt im Spieleordner.")
            }
            return tr("Its app for this Mac is not built.", "Son app pour ce Mac n’est pas construite.", "Su app para este Mac no se compila.", "Seine App für diesen Mac wird nicht erstellt.")
        }
        if let detail = game.mac?.detail, !detail.isEmpty { return detail }
        return tr("Its app, to play it on this Mac.", "Son app, pour y jouer sur ce Mac.", "Su app, para jugarlo en este Mac.", "Seine App, um es auf diesem Mac zu spielen.")
    }

    private var why: some View {
        SheetPart(title: tr("Why", "Pourquoi", "Por qué", "Warum")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(whyLines, id: \.self) { line in
                    Label {
                        Text(line)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "smallcircle.filled.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// Why the game is as it is, a line each. For a game to build, its
    /// reasons in the player's words: the engine's sentence quotes nxnative's
    /// commits, in English and cut short, which the list below shows whole.
    /// For a game up to date, the engine's sentence, which quotes none and
    /// says when nxnative's shared changes are due.
    private var whyLines: [String] {
        let reasons = game.reasons.filter { $0 != "up_to_date" }
        if reasons.isEmpty {
            return game.detail.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return reasons.map { whyText($0, counts: game.changeCounts) }
    }

    private func failure(_ attempt: GameAttempt, mac: Bool = false) -> some View {
        SheetPart(title: mac ? tr("Last attempt of its Mac app", "Dernière tentative de son app Mac", "Último intento de su app de Mac", "Letzter Versuch seiner Mac-App") : tr("Last attempt", "Dernière tentative", "Último intento", "Letzter Versuch")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(attempt.error ?? tr("The build failed.", "La construction a échoué.", "La compilación falló.", "Der Build ist fehlgeschlagen."))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let date = attempt.date {
                        Text(Format.relative(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let log = attempt.log, !log.isEmpty {
                        Button(tr("Open its log", "Ouvrir son journal", "Abrir su registro", "Sein Protokoll öffnen")) { model.open(log) }
                            .controlSize(.small)
                    }
                }
                // Skipped (no room, the Mac's Xcode): not the game's failure,
                // tried again at the next build.
                Text(attempt.result == "skipped" && game.state != .failed
                     ? tr("It is tried again at the next build.", "Il sera réessayé à la prochaine construction.", "Se vuelve a intentar en la próxima compilación.", "Es wird beim nächsten Build erneut versucht.")
                     : tr("It is tried again when nxnative changes it.", "Il sera réessayé quand nxnative le changera.", "Se vuelve a intentar cuando nxnative lo cambie.", "Es wird erneut versucht, wenn nxnative es ändert."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var changes: some View {
        SheetPart(title: tr("nxnative since its build", "nxnative depuis sa construction", "nxnative desde su compilación", "nxnative seit seinem Build"), trailing: counts) {
            ChangeList(changes: Array(game.changes.prefix(30)), engine: model.library?.engine)
                .id(game.titleID)
        }
    }

    private var counts: String {
        guard let counts = game.changeCounts else { return "" }
        return tr("\(counts.own) for it, \(counts.shared) shared", "\(counts.own) pour lui, \(counts.shared) communs", "\(counts.own) para él, \(counts.shared) compartidos", "\(counts.own) für es, \(counts.shared) gemeinsam")
    }

    private var build: some View {
        SheetPart(title: tr("Its build", "Sa construction", "Su compilación", "Sein Build")) {
            VStack(alignment: .leading, spacing: 8) {
                if let build = game.build {
                    Fact(tr("Built", "Construit", "Compilado", "Erstellt"), build.date.map { Format.date($0) } ?? build.builtAt)
                    Fact("nxnative", String(build.commit.prefix(12)), link: model.library?.engine?.page(of: build.commit))
                    if let duration = build.duration, duration > 0 { Fact(tr("Took", "Durée", "Duración", "Dauer"), Format.duration(duration)) }
                    if let version = build.version, !version.isEmpty { Fact(tr("Version", "Version", "Versión", "Version"), version) }
                    if let toolchain = build.toolchain, !toolchain.isEmpty { Fact(tr("With", "Avec", "Con", "Mit"), toolchain) }
                } else {
                    Text(tr("Never built by Cartouche.", "Jamais construit par Cartouche.", "Nunca compilado por Cartouche.", "Nie von Cartouche erstellt."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let ipa = game.ipa {
                    Divider()
                    Fact("IPA", ipa.present ? Format.size(ipa.size) : tr("missing", "absente", "no está", "fehlt"))
                    Text(ipa.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if ipa.present {
                        Button(tr("Show in the Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen")) { model.reveal(ipa.path) }
                            .controlSize(.small)
                    }
                }
                if let size = game.sourceSize, size > 0 {
                    Fact(tr("Its dump", "Son dump", "Su dump", "Sein Dump"), Format.size(size))
                }
            }
        }
    }

    /// Its app for this Mac: where it is, its build, or why it is not
    /// there (the engine's words). Kept in one file in a games folder on a
    /// NAS, it is played from this Mac's copy, installed from there.
    private var macApp: some View {
        SheetPart(title: tr("Its Mac app", "Son app Mac", "Su app de Mac", "Seine Mac-App")) {
            VStack(alignment: .leading, spacing: 8) {
                if let mac = game.mac, mac.packed {
                    packedMacApp(mac)
                } else if let app = game.mac?.app, app.present {
                    if let build = game.mac?.build {
                        Fact(tr("Built", "Construite", "Compilada", "Erstellt"), build.date.map { Format.date($0) } ?? build.builtAt)
                        Fact("nxnative", String(build.commit.prefix(12)), link: model.library?.engine?.page(of: build.commit))
                        if let duration = build.duration, duration > 0 { Fact(tr("Took", "Durée", "Duración", "Dauer"), Format.duration(duration)) }
                    }
                    Fact(tr("Size", "Taille", "Tamaño", "Größe"), Format.size(app.size))
                    Text(app.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button(tr("Show in the Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen")) { model.reveal(app.path) }
                        .controlSize(.small)
                } else if let app = game.mac?.app, !app.name.isEmpty {
                    Text(tr("\(app.name) is no longer in its folder: it is built again.", "\(app.name) n’est plus dans son dossier : elle sera reconstruite.", "\(app.name) ya no está en su carpeta: se vuelve a compilar.", "\(app.name) ist nicht mehr in ihrem Ordner: Sie wird erneut erstellt."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(tr("Not built yet.", "Pas encore construite.", "Aún no compilada.", "Noch nicht erstellt."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let folder = game.mac?.folder, !folder.isEmpty {
                    Fact(tr("Folder", "Dossier", "Carpeta", "Ordner"), (folder as NSString).abbreviatingWithTildeInPath)
                }
            }
        }
    }

    /// The app the games folder keeps in one file (a NAS's), and this
    /// Mac's copy of it: installed or not, of the newest build or not.
    @ViewBuilder
    private func packedMacApp(_ mac: GameMac) -> some View {
        if let kept = mac.library, kept.present {
            if let build = mac.build {
                Fact(tr("Built", "Construite", "Compilada", "Erstellt"), build.date.map { Format.date($0) } ?? build.builtAt)
                Fact("nxnative", String(build.commit.prefix(12)), link: model.library?.engine?.page(of: build.commit))
            }
            Fact(model.gamesOnShare ? tr("On the NAS", "Sur le NAS", "En el NAS", "Auf dem NAS") : tr("In the games folder", "Dans le dossier des jeux", "En la carpeta de juegos", "Im Spieleordner"), Format.size(kept.size))
            Text(kept.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button(tr("Show in the Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen")) { model.reveal(kept.path) }
                .controlSize(.small)
            Divider()
            let installing = model.installing == game.titleID
            if let app = mac.app, app.present {
                Fact(tr("On this Mac", "Sur ce Mac", "En este Mac", "Auf diesem Mac"), Format.size(app.size))
                Text(installing ? model.installMessage
                     : mac.behind ? tr("Of an older build: the newest takes its place when you play.",
                                       "D’une construction plus ancienne : la dernière prend sa place quand vous jouez.",
                                       "De una compilación más antigua: la más reciente ocupa su lugar cuando juegues.",
                                       "Von einem älteren Build: Der neueste tritt an seine Stelle, wenn du spielst.")
                     : tr("Of the newest build.", "De la dernière construction.", "De la compilación más reciente.", "Vom neuesten Build."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if mac.behind {
                        Button(tr("Update", "Mettre à jour", "Actualizar", "Aktualisieren")) { model.installOnThisMac(game) }
                            .disabled(model.installing != nil)
                    }
                    Button(tr("Show in the Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen")) { model.reveal(app.path) }
                    Button(tr("Remove from this Mac", "Retirer de ce Mac", "Quitar de este Mac", "Von diesem Mac entfernen"), role: .destructive) {
                        model.removeMacApp(MacAppCopy(path: app.path, titleID: game.titleID, name: game.name, size: app.size, on: game.onMac, packed: true))
                    }
                    .disabled(installing)
                }
                .controlSize(.small)
            } else {
                Fact(tr("On this Mac", "Sur ce Mac", "En este Mac", "Auf diesem Mac"), installing ? tr("installing…", "installation…", "instalando…", "wird installiert …") : tr("not installed", "pas installée", "no instalada", "nicht installiert"))
                Text(installing ? model.installMessage
                     : tr("Installed when you play it, or now: about \(Format.size(kept.size)) on this Mac.",
                          "Installée quand vous y jouez, ou dès maintenant : environ \(Format.size(kept.size)) sur ce Mac.",
                          "Se instala cuando juegues, o ahora: unos \(Format.size(kept.size)) en este Mac.",
                          "Wird installiert, wenn du spielst, oder jetzt: etwa \(Format.size(kept.size)) auf diesem Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Install on this Mac", "Installer sur ce Mac", "Instalar en este Mac", "Auf diesem Mac installieren")) { model.installOnThisMac(game) }
                    .controlSize(.small)
                    .disabled(model.installing != nil)
            }
            if !mac.installs.isEmpty {
                Fact(tr("Installed in", "Installée dans", "Instalada en", "Installiert in"), (mac.installs as NSString).abbreviatingWithTildeInPath)
            }
        } else if let kept = mac.library, !kept.name.isEmpty {
            Text(tr("\(kept.name) is no longer in its folder: it is built again.", "\(kept.name) n’est plus dans son dossier : elle sera reconstruite.", "\(kept.name) ya no está en su carpeta: se vuelve a compilar.", "\(kept.name) ist nicht mehr in ihrem Ordner: Sie wird erneut erstellt."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(tr("Not built yet.", "Pas encore construite.", "Aún no compilada.", "Noch nicht erstellt."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// A titled part of the sheet.
    struct SheetPart<Content: View>: View {
        let title: String
        var trailing: String = ""
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !trailing.isEmpty {
                        Text(trailing)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Card(padding: 14) { content }
            }
        }
    }
}

struct Fact: View {
    let label: String
    let value: String
    var link: URL?

    init(_ label: String, _ value: String, link: URL? = nil) {
        self.label = label
        self.value = value
        self.link = link
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let link {
                Link(value, destination: link)
                    .font(.callout.monospaced())
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
    }
}

/// nxnative's commits since the game's build, the newest first: the first
/// few, the others when asked.
struct ChangeList: View {
    static let shown = 4
    let changes: [Change]
    let engine: EngineCommit?
    @State private var all = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(all ? changes : Array(changes.prefix(ChangeList.shown))) { change in
                ChangeRow(change: change, link: engine?.page(of: change.sha))
            }
            if changes.count > ChangeList.shown {
                Button(all ? tr("Show fewer", "En montrer moins", "Mostrar menos", "Weniger zeigen")
                           : tr("Show the \(changes.count - ChangeList.shown) others", "Voir les \(changes.count - ChangeList.shown) autres", "Ver los otros \(changes.count - ChangeList.shown)", "Die anderen \(changes.count - ChangeList.shown) zeigen")) {
                    withAnimation(.snappy) { all.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }
}

/// A commit of nxnative: its first lines, all of it when asked, its kind,
/// its link and when it was made.
struct ChangeRow: View {
    /// Longer than this, a commit's text is cut to its first lines.
    static let long = 80
    let change: Change
    let link: URL?
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.subject)
                .font(.callout)
                .lineLimit(open ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(changeKindText(change.kind))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(change.kind == "shared" ? Color.secondary.opacity(0.15) : Theme.indigo.opacity(0.15)))
                if let link {
                    Link(change.short.prefix(7), destination: link)
                        .font(.caption.monospaced())
                } else {
                    Text(change.short.prefix(7))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(Format.relative(change.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if change.subject.count > ChangeRow.long {
                    Button(open ? tr("Less", "Moins", "Menos", "Weniger") : tr("More", "Plus", "Más", "Mehr")) {
                        withAnimation(.snappy) { open.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }
}

/// The names nxnative's commits give the game, besides its own.
struct AliasesEditor: View {
    @EnvironmentObject private var model: AppModel
    let game: Game
    @State private var text = ""
    @State private var editing = false

    var body: some View {
        DisclosureGroup(isExpanded: $editing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Other names of the game in nxnative’s commits, one per line: a fix that names it rebuilds it.",
                        "Autres noms du jeu dans les commits de nxnative, un par ligne : un correctif qui le nomme le reconstruit.",
                        "Otros nombres del juego en los commits de nxnative, uno por línea: una corrección que lo nombre lo recompila.",
                        "Andere Namen des Spiels in den Commits von nxnative, einer pro Zeile: Eine Korrektur, die ihn nennt, erstellt es neu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $text)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                HStack {
                    Spacer()
                    Button(tr("Save", "Enregistrer", "Guardar", "Sichern")) {
                        let names = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        model.update { config in
                            if names.isEmpty {
                                config.aliases.removeValue(forKey: game.titleID)
                            } else {
                                config.aliases[game.titleID] = names
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(tr("Names in nxnative’s commits", "Noms dans les commits de nxnative", "Nombres en los commits de nxnative", "Namen in den Commits von nxnative"))
                .font(.callout.weight(.medium))
        }
        .onAppear { text = (model.config?.aliases[game.titleID] ?? game.aliases).joined(separator: "\n") }
        .onChange(of: game.titleID) { _, _ in
            text = (model.config?.aliases[game.titleID] ?? game.aliases).joined(separator: "\n")
        }
    }
}

/// A game's app on this Mac: Play, straight into the game, or Game
/// settings, nxnative's own window first; the game playing comes to the
/// front. Below, what its saves did last.
struct MacPlayCard: View {
    @EnvironmentObject private var model: AppModel
    let game: Game
    @ObservedObject var games: MacGames

    var body: some View {
        let playing = games.playing[game.titleID]
        let preparing = games.preparing.contains(game.titleID)
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // Play above Game settings, both as wide as the card, as on
                // the iPhone's sheet (CartoucheGameSheetView).
                VStack(spacing: 8) {
                    playButton(playing: playing, preparing: preparing)
                    settingsButton(playing: playing, preparing: preparing)
                }
                if let line = installLine(playing: playing) {
                    Label {
                        Text(line)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.down.app")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Label {
                    Text(savesLine(playing: playing))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: savesSymbol)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func playButton(playing: MacGameRun?, preparing: Bool) -> some View {
        let installing = model.installing == game.titleID
        return Button {
            model.play(game)
        } label: {
            Label(playing != nil ? tr("Show the game", "Afficher le jeu", "Mostrar el juego", "Spiel zeigen")
                                 : installing ? tr("Installing…", "Installation…", "Instalando…", "Wird installiert …")
                                 : preparing ? tr("Getting its saves…", "Arrivée des sauvegardes…", "Recibiendo sus partidas guardadas…", "Spielstände werden geholt …") : tr("Play on this Mac", "Jouer sur ce Mac", "Jugar en este Mac", "Auf diesem Mac spielen"),
                  systemImage: playing != nil ? "macwindow" : installing ? "arrow.down.app" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(preparing || installing)
    }

    /// The app the games folder keeps in one file (a NAS's): installed on
    /// this Mac before the game starts, or how far that is.
    private func installLine(playing: MacGameRun?) -> String? {
        guard let mac = game.mac, mac.packed, playing == nil else { return nil }
        if model.installing == game.titleID { return model.installMessage }
        guard mac.needsInstall, let kept = mac.library else { return nil }
        if mac.hasApp {
            return model.gamesOnShare
                ? tr("A newer build is on the NAS: Play puts it in place of this Mac’s copy first.",
                     "Une construction plus récente est sur le NAS : Jouer la met d’abord à la place de la copie de ce Mac.",
                     "Hay una compilación más reciente en el NAS: Jugar la pone primero en lugar de la copia de este Mac.",
                     "Ein neuerer Build ist auf dem NAS: „Spielen“ setzt ihn zuerst an die Stelle der Kopie dieses Mac.")
                : tr("A newer build is in the games folder: Play puts it in place of this Mac’s copy first.",
                     "Une construction plus récente est dans le dossier des jeux : Jouer la met d’abord à la place de la copie de ce Mac.",
                     "Hay una compilación más reciente en la carpeta de juegos: Jugar la pone primero en lugar de la copia de este Mac.",
                     "Ein neuerer Build ist im Spieleordner: „Spielen“ setzt ihn zuerst an die Stelle der Kopie dieses Mac.")
        }
        return model.gamesOnShare
            ? tr("Its app is on the NAS: Play installs it on this Mac first (\(Format.size(kept.size))).",
                 "Son app est sur le NAS : Jouer l’installe d’abord sur ce Mac (\(Format.size(kept.size))).",
                 "Su app está en el NAS: Jugar la instala primero en este Mac (\(Format.size(kept.size))).",
                 "Seine App ist auf dem NAS: „Spielen“ installiert sie zuerst auf diesem Mac (\(Format.size(kept.size))).")
            : tr("Its app is kept in one file in the games folder: Play installs it on this Mac first (\(Format.size(kept.size))).",
                 "Son app est rangée en un seul fichier dans le dossier des jeux : Jouer l’installe d’abord sur ce Mac (\(Format.size(kept.size))).",
                 "Su app se guarda en un solo archivo en la carpeta de juegos: Jugar la instala primero en este Mac (\(Format.size(kept.size))).",
                 "Seine App liegt als eine Datei im Spieleordner: „Spielen“ installiert sie zuerst auf diesem Mac (\(Format.size(kept.size))).")
    }

    private func settingsButton(playing: MacGameRun?, preparing: Bool) -> some View {
        Button {
            model.play(game, settings: true)
        } label: {
            Label(tr("Game settings", "Réglages du jeu", "Ajustes del juego", "Einstellungen des Spiels"), systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(playing != nil || preparing || model.installing == game.titleID)
        .help(tr("Starts the game with nxnative’s own window first: graphics, controls, performance.",
                 "Démarre le jeu avec d’abord la fenêtre de nxnative : graphismes, commandes, performances.",
                 "Inicia el juego primero con la ventana de nxnative: gráficos, controles, rendimiento.",
                 "Startet das Spiel zuerst mit dem Fenster von nxnative: Grafik, Steuerung, Leistung."))
    }

    private var savesSymbol: String {
        let event = games.last[game.titleID]
        if games.cloud[game.titleID] != nil { return "icloud" }
        if event?.failed == true || event?.offline == true, games.keepsSaves(game.titleID) { return "exclamationmark.triangle" }
        if event?.step == MacSaveEvent.heldBack, games.keepsSaves(game.titleID) { return "arrow.up.circle" }
        return "arrow.triangle.2.circlepath"
    }

    /// Where its saves are and what they did last, in the player's words.
    private func savesLine(playing: MacGameRun?) -> String {
        if games.cloud[game.titleID] != nil {
            return tr("Its saves go through nxnative’s own cloud saves, chosen in its settings: Cartouche leaves them to it.",
                      "Ses sauvegardes passent par le cloud de nxnative, choisi dans ses réglages : Cartouche les lui laisse.",
                      "Sus partidas guardadas pasan por la nube de nxnative, elegida en sus ajustes: Cartouche se las deja.",
                      "Seine Spielstände laufen über die Cloud-Spielstände von nxnative, in dessen Einstellungen gewählt: Cartouche überlässt sie ihm.")
        }
        guard games.folder != nil else {
            return tr("Its saves stay on this Mac: keeping them with the iPhone’s is off (iPhone page).",
                      "Ses sauvegardes restent sur ce Mac : leur mise en phase avec l’iPhone est désactivée (page iPhone).",
                      "Sus partidas guardadas se quedan en este Mac: mantenerlas al día con las del iPhone está desactivado (página iPhone).",
                      "Seine Spielstände bleiben auf diesem Mac: Der Abgleich mit denen des iPhones ist ausgeschaltet (iPhone-Seite).")
        }
        if let playing {
            // What went since it started, as it saved.
            if let event = games.last[game.titleID], event.when == .during, event.at >= playing.started,
               event.step == "send" || event.step == "keep" {
                return tr("Playing since \(Format.clock(playing.started)). Its saves went to the saves folder \(Format.relative(event.at)), a few seconds after it saved.",
                          "En jeu depuis \(Format.clock(playing.started)). Ses sauvegardes sont parties dans le dossier des sauvegardes \(Format.relative(event.at)), quelques secondes après qu’il a sauvegardé.",
                          "Jugando desde las \(Format.clock(playing.started)). Sus partidas guardadas fueron a la carpeta de partidas guardadas \(Format.relative(event.at)), unos segundos después de que guardara.",
                          "Im Spiel seit \(Format.clock(playing.started)). Seine Spielstände gingen \(Format.relative(event.at)) in den Spielstandordner, wenige Sekunden nach dem Speichern.")
            }
            return tr("Playing since \(Format.clock(playing.started)). Its saves go to the saves folder a few seconds after it saves.",
                      "En jeu depuis \(Format.clock(playing.started)). Ses sauvegardes partent dans le dossier des sauvegardes quelques secondes après chaque sauvegarde.",
                      "Jugando desde las \(Format.clock(playing.started)). Sus partidas guardadas van a la carpeta de partidas guardadas unos segundos después de que guarde.",
                      "Im Spiel seit \(Format.clock(playing.started)). Seine Spielstände gehen wenige Sekunden nach jedem Speichern in den Spielstandordner.")
        }
        guard let event = games.last[game.titleID] else {
            // Whichever device played last, an iPhone, an iPad or another
            // Mac, the newest copy comes: none is named.
            return tr("Its saves are kept in step through the saves folder, before each game and as it saves.",
                      "Ses sauvegardes sont mises en phase par le dossier des sauvegardes, avant chaque partie et dès qu’il sauvegarde.",
                      "Sus partidas guardadas se mantienen al día a través de la carpeta de partidas guardadas, antes de cada partida y en cuanto guarda.",
                      "Seine Spielstände werden über den Spielstandordner abgeglichen, vor jedem Spiel und sobald es speichert.")
        }
        let when = Format.relative(event.at)
        switch event.step {
        case "send":
            return tr("This Mac’s saves went to the saves folder \(when).", "Les sauvegardes de ce Mac sont parties dans le dossier des sauvegardes \(when).", "Las partidas guardadas de este Mac fueron a la carpeta de partidas guardadas \(when).", "Die Spielstände dieses Mac gingen \(when) in den Spielstandordner.")
        case "keep":
            return tr("This Mac’s saves went to the saves folder \(when), under a newer copy, which comes to this Mac next.",
                      "Les sauvegardes de ce Mac sont parties dans le dossier des sauvegardes \(when), sous une copie plus récente, qui arrive ensuite sur ce Mac.",
                      "Las partidas guardadas de este Mac fueron a la carpeta de partidas guardadas \(when), bajo una copia más reciente, que llega después a este Mac.",
                      "Die Spielstände dieses Mac gingen \(when) in den Spielstandordner, unter eine neuere Kopie, die als Nächstes auf diesen Mac kommt.")
        case "fetch":
            return tr("The newest saves came from the saves folder \(when).", "Les sauvegardes les plus récentes sont arrivées du dossier des sauvegardes \(when).", "Las partidas guardadas más recientes llegaron de la carpeta de partidas guardadas \(when).", "Die neuesten Spielstände kamen \(when) aus dem Spielstandordner.")
        case "keepAndFetch":
            return tr("Newer saves came from the saves folder \(when); this Mac’s were kept as a copy.",
                      "Des sauvegardes plus récentes sont arrivées du dossier des sauvegardes \(when) ; celles de ce Mac ont été gardées en copie.",
                      "Llegaron partidas guardadas más recientes de la carpeta de partidas guardadas \(when); las de este Mac se guardaron como copia.",
                      "Neuere Spielstände kamen \(when) aus dem Spielstandordner; die dieses Mac wurden als Kopie behalten.")
        case MacSaveEvent.heldBack:
            let copy = event.newer ?? "?", app = event.game ?? "?"
            return tr("The newest copy in the saves folder comes from version \(copy) of the game, newer than this Mac’s (\(app)): it comes once the game is updated here. Meanwhile, this Mac’s saves go there as a copy of their own.",
                      "La copie la plus récente du dossier des sauvegardes vient de la version \(copy) du jeu, plus récente que celle de ce Mac (\(app)) : elle viendra une fois le jeu mis à jour ici. D’ici là, les sauvegardes de ce Mac y partent comme une copie à part.",
                      "La copia más reciente de la carpeta de partidas guardadas viene de la versión \(copy) del juego, más nueva que la de este Mac (\(app)): llega en cuanto el juego se actualice aquí. Mientras tanto, las partidas guardadas de este Mac van allí como una copia aparte.",
                      "Die neueste Kopie im Spielstandordner stammt von Version \(copy) des Spiels, neuer als die dieses Mac (\(app)): Sie kommt, sobald das Spiel hier aktualisiert ist. Bis dahin gehen die Spielstände dieses Mac als eigene Kopie dorthin.")
        case MacSaveEvent.putBack:
            return tr("A copy was put back \(when), from Cartouche’s console: it is the newest one in the saves folder now.",
                      "Une copie a été remise \(when), depuis la console de Cartouche : c’est maintenant la plus récente du dossier des sauvegardes.",
                      "Se restauró una copia \(when), desde la consola de Cartouche: ahora es la más reciente de la carpeta de partidas guardadas.",
                      "Eine Kopie wurde \(when) über die Konsole von Cartouche zurückgelegt: Sie ist jetzt die neueste im Spielstandordner.")
        case "offline":
            return tr("The saves folder could not be reached \(when): this Mac’s saves stay as they are until it can be.",
                      "Le dossier des sauvegardes était injoignable \(when) : celles de ce Mac restent telles quelles en attendant.",
                      "No se pudo llegar a la carpeta de partidas guardadas \(when): las partidas guardadas de este Mac se quedan como están hasta que se pueda.",
                      "Der Spielstandordner war \(when) nicht erreichbar: Die Spielstände dieses Mac bleiben, wie sie sind, bis er es ist.")
        default:
            return event.failure ?? tr("Its saves could not be kept in step \(when).", "Ses sauvegardes n’ont pas pu être mises en phase \(when).", "Sus partidas guardadas no se pudieron sincronizar \(when).", "Seine Spielstände konnten \(when) nicht abgeglichen werden.")
        }
    }
}

/// A platform of a game's sheet: built for it, or not.
struct PlatformToggle: View {
    let title: String
    let symbol: String
    let detail: String
    let on: Bool
    /// Why it cannot be changed here, when it cannot.
    let locked: String?
    let change: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { change($0) })) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(on ? Theme.indigo : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The whole width, so that each platform's switch is at the
            // card's edge, under the other's, whatever its words' length.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .disabled(locked != nil)
        .help(locked ?? "")
    }
}

/// A game no Mac built yet, and this one neither: how many Macs tried it,
/// how long, and that building it may keep the Mac busy for nothing.
struct UnbuiltCard: View {
    let game: UnbuiltGame

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("No Mac has built this game yet", "Aucun Mac n’a encore construit ce jeu", "Ningún Mac ha compilado aún este juego", "Noch kein Mac hat dieses Spiel erstellt"))
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(UnbuiltGames.words(game, named: { stageText($0) }))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A game building now, or waiting its turn: what its build makes, its
/// IPA, for the iPhone, then its app for this Mac, or one of the two, and
/// the part it makes now (decision 127).
struct ProgressCard: View {
    @EnvironmentObject private var model: AppModel
    let progress: GameProgress

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if let targets = model.targets(progress) {
                    TargetLabel(targets: targets)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(progress.state == "building" ? stageText(progress.stage) : tr("Waiting its turn", "En attente de son tour", "Esperando su turno", "Wartet, bis es dran ist"))
                        .font(.callout.weight(.medium))
                    Spacer()
                    if let eta = progress.eta, eta > 0 {
                        Text(tr("about \(Format.duration(eta)) left", "encore \(Format.duration(eta)) environ", "quedan unos \(Format.duration(eta))", "noch etwa \(Format.duration(eta))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if progress.state == "building" {
                    ProgressView(value: progress.overall ?? progress.frac ?? 0)
                    if let step = progress.step, !step.isEmpty {
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
