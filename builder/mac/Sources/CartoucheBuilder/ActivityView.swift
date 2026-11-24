//
//  ActivityView.swift
//  Cartouche Builder
//
//  The builds: the game building now, its step and how far it is, the
//  games waiting their turn, and what the last batch did; what each build
//  makes, for the iPhone, for this Mac or both, and the part it makes now
//  (decision 127). A game asked for while a batch runs waits its turn at
//  the end of it, and each game can be taken out of it, the one building
//  too: the batch goes on with the next. A batch goes on when the window,
//  or the app, is closed; the Mac stays awake for it.
//

import BuilderKit
import CartoucheCore
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLines: Bool

    /// SHOWINGDETAILS: what the batch said open, as the gallery shows it.
    init(showingDetails: Bool = false) {
        _showLines = State(initialValue: showingDetails)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: tr("Builds", "Constructions", "Compilaciones", "Builds"), subtitle: subtitle) {
                    if model.isBuilding {
                        HStack(spacing: 10) {
                            if model.status?.running == true, !model.dueOutsideBatch.isEmpty {
                                Button {
                                    model.build()
                                } label: {
                                    Label(tr("Add what is due", "Ajouter ce qui est dû", "Añadir lo pendiente", "Fälliges hinzufügen"), systemImage: "text.badge.plus")
                                }
                                .controlSize(.large)
                                .disabled(!model.canBuild)
                                .help(tr("The games nxnative improved that this batch does not have, built after the games waiting.",
                                         "Les jeux que nxnative a améliorés et que cette série n’a pas, construits après les jeux en attente.",
                                         "Los juegos que nxnative mejoró y que esta tanda no tiene, compilados después de los juegos en espera.",
                                         "Die Spiele, die nxnative verbessert hat und die dieser Durchlauf nicht enthält, erstellt nach den wartenden Spielen."))
                            }
                            Button(role: .destructive) {
                                model.stop()
                            } label: {
                                Label(model.stopsSeveral ? tr("Stop all", "Tout arrêter", "Detener todo", "Alle stoppen") : tr("Stop", "Arrêter", "Detener", "Stoppen"), systemImage: "stop.fill")
                            }
                            .controlSize(.large)
                            .help(tr("Stops the game building and every game waiting.", "Arrête le jeu en construction et tous les jeux en attente.", "Detiene el juego que se está compilando y todos los juegos en espera.", "Stoppt das Spiel, das gerade erstellt wird, und alle wartenden Spiele."))
                        }
                    } else {
                        Button {
                            model.build()
                        } label: {
                            Label(tr("Build what is due", "Construire ce qui est dû", "Compilar lo pendiente", "Fälliges erstellen"), systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canBuild || model.dueOutsideBatch.isEmpty)
                    }
                }
                if let status = model.status {
                    if status.running == true {
                        ForEach(status.current, id: \.titleID) { game in
                            CurrentCard(progress: game, alone: status.current.count == 1 && model.waiting.isEmpty)
                        }
                        if status.current.isEmpty {
                            Card {
                                HStack(spacing: 12) {
                                    ProgressView().controlSize(.small)
                                    Text(status.message ?? tr("Getting ready: checking nxnative and the games…", "Préparation : vérification de nxnative et des jeux…", "Preparando: comprobando nxnative y los juegos…", "Vorbereitung: nxnative und die Spiele werden geprüft …"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if model.starting != nil {
                        StartingCard()
                    } else {
                        LastBatchCard(status: status)
                    }
                    if status.running == true {
                        if !model.waiting.isEmpty {
                            GameList(title: tr("Queue", "File d’attente", "Cola", "Warteschlange"), games: model.waiting) { model.takeOut($0) }
                        }
                    } else if model.starting != nil {
                        if !model.waiting.isEmpty {
                            GameList(title: tr("Queue", "File d’attente", "Cola", "Warteschlange"), games: model.waiting)
                        }
                    } else if !status.queued.isEmpty {
                        GameList(title: tr("Waiting their turn", "En attente", "Esperando su turno", "Warten, bis sie dran sind"), games: status.queued)
                    }
                    if !status.finished.isEmpty {
                        GameList(title: status.running == true ? tr("Done in this batch", "Faits dans cette série", "Hechos en esta tanda", "In diesem Durchlauf erledigt") : tr("Last batch", "Dernière série", "Última tanda", "Letzter Durchlauf"),
                                 games: status.finished)
                    }
                    if !status.lines.isEmpty {
                        DisclosureGroup(isExpanded: $showLines) {
                            ScrollView {
                                Text(status.lines.suffix(80).joined(separator: "\n"))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(maxHeight: 260)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                        } label: {
                            Text(tr("Details", "Détails", "Detalles", "Details"))
                                .font(.callout.weight(.medium))
                        }
                    }
                } else if model.starting != nil {
                    StartingCard()
                    if !model.waiting.isEmpty {
                        GameList(title: tr("Queue", "File d’attente", "Cola", "Warteschlange"), games: model.waiting)
                    }
                } else {
                    ContentUnavailableView(tr("No build yet", "Pas encore de construction", "Aún no hay compilaciones", "Noch kein Build"), systemImage: "hammer",
                                           description: Text(tr("Builds show here while they run, and what they did after.",
                                                                "Les constructions s’affichent ici pendant qu’elles tournent, et ce qu’elles ont fait ensuite.",
                                                                "Las compilaciones aparecen aquí mientras se ejecutan, y lo que hicieron después.",
                                                                "Builds erscheinen hier, während sie laufen, und danach, was sie getan haben.")))
                        .frame(minHeight: 300)
                }
                NightlyCard()
            }
            .padding(28)
        }
    }

    private var subtitle: String {
        guard let status = model.status else { return tr("Nothing running", "Rien en cours", "Nada en curso", "Nichts läuft") }
        if status.running == true {
            let left = model.waiting.count + status.current.count
            return tr("\(left) game\(left == 1 ? "" : "s") to go", "\(left) jeu\(left == 1 ? "" : "x") à faire", "Quedan \(left) juego\(left == 1 ? "" : "s")", "Noch \(left) Spiel\(left == 1 ? "" : "e")")
                + tr(" · the Mac stays awake", " · le Mac reste éveillé", " · el Mac se mantiene activo", " · der Mac bleibt wach")
        }
        if let ended = status.endedDate { return tr("Last batch ", "Dernière série ", "Última tanda ", "Letzter Durchlauf ") + Format.relative(ended) }
        return tr("Nothing running", "Rien en cours", "Nada en curso", "Nichts läuft")
    }
}

/// The game building now, with a button that stops it alone when other
/// games are in the batch.
struct CurrentCard: View {
    @EnvironmentObject private var model: AppModel
    let progress: GameProgress
    /// The batch's only game left: the page's Stop stops it.
    var alone = true

    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 20) {
                if let game = model.game(progress.titleID) {
                    CoverView(game: game)
                        .frame(width: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(progress.name)
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !alone {
                            let stopping = model.stopping(progress.titleID)
                            Button {
                                model.takeOut(progress.titleID)
                            } label: {
                                Label(stopping ? tr("Stopping…", "Arrêt…", "Deteniendo…", "Wird gestoppt …") : tr("Stop this game", "Arrêter ce jeu", "Detener este juego", "Dieses Spiel stoppen"), systemImage: "stop.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(stopping)
                            .help(tr("Stops this game’s build: the games waiting are built after it.",
                                     "Arrête la construction de ce jeu : les jeux en attente se construisent ensuite.",
                                     "Detiene la compilación de este juego: los juegos en espera se compilan después.",
                                     "Stoppt den Build dieses Spiels: Die wartenden Spiele werden danach erstellt."))
                        }
                    }
                    // What it makes, and the part it makes now.
                    if let targets = model.targets(progress) {
                        TargetLabel(targets: targets)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                    Text(stageText(progress.stage) + (progress.k.flatMap { k in progress.n.map { " · \(k)/\($0)" } } ?? ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress.overall ?? progress.frac ?? 0)
                        .progressViewStyle(.linear)
                        .tint(Theme.indigo)
                    HStack {
                        Text(Format.percent(progress.overall ?? progress.frac ?? 0))
                            .font(.callout.monospacedDigit().weight(.semibold))
                        Spacer()
                        if let eta = progress.eta, eta > 0 {
                            Text(tr("about \(Format.duration(eta)) left", "encore \(Format.duration(eta)) environ", "quedan unos \(Format.duration(eta))", "noch etwa \(Format.duration(eta))"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if let started = progress.startedDate {
                            Text(tr("started ", "commencé ", "iniciada ", "gestartet ") + Format.relative(started))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let step = progress.step, !step.isEmpty {
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let note = progress.note ?? progress.message, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

/// A batch asked for, until it runs: a moment, or as long as the app's look
/// at nxnative, or a clean, holds the batch lock, which the batch waits for.
struct StartingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var text: String {
        if model.checking {
            return tr("Checking nxnative and your games first: the batch starts as soon as that is done…",
                      "Vérification de nxnative et de vos jeux d’abord : la série démarre dès qu’elle est finie…",
                      "Primero se comprueban nxnative y tus juegos: la tanda empieza en cuanto termine…",
                      "Zuerst werden nxnative und deine Spiele geprüft: Der Durchlauf beginnt, sobald das erledigt ist …")
        }
        if model.cleaning {
            return tr("Freeing space first: the batch starts as soon as that is done…",
                      "Libération d’espace d’abord : la série démarre dès qu’elle est finie…",
                      "Primero se libera espacio: la tanda empieza en cuanto termine…",
                      "Zuerst wird Platz freigegeben: Der Durchlauf beginnt, sobald das erledigt ist …")
        }
        return tr("Starting…", "Démarrage…", "Iniciando…", "Wird gestartet …")
    }
}

/// What the last batch did, in one line.
struct LastBatchCard: View {
    let status: BatchStatus

    var body: some View {
        let built = status.games.filter { $0.state == "built" }.count
        let failed = status.games.filter { $0.state == "failed" }.count
        // A batch whose games were all stopped one by one stopped too.
        let stopped = status.state == "stopped" || (built == 0 && failed == 0 && status.games.contains { $0.state == "stopped" })
        Card {
            HStack(spacing: 14) {
                Image(systemName: failed > 0 ? "exclamationmark.triangle.fill" : stopped ? "stop.circle.fill" : "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(failed > 0 ? Color.orange : stopped ? Color.secondary : Color.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(built: built, failed: failed, stopped: stopped))
                        .font(.headline)
                    if let error = status.error, !error.isEmpty {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if let ended = status.endedDate {
                        Text(Format.date(ended))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func headline(built: Int, failed: Int, stopped: Bool) -> String {
        if status.state == "failed" { return tr("The batch could not run", "La série n’a pas pu tourner", "No se pudo ejecutar la tanda", "Der Durchlauf konnte nicht laufen") }
        if stopped { return tr("Stopped", "Arrêtée", "Detenida", "Gestoppt") + (built > 0 ? tr(" after \(built) game\(built == 1 ? "" : "s")", " après \(built) jeu\(built == 1 ? "" : "x")", " tras \(built) juego\(built == 1 ? "" : "s")", " nach \(built) Spiel\(built == 1 ? "" : "en")") : "") }
        if built == 0 && failed == 0 { return tr("Nothing was due", "Rien n’était à faire", "No había nada pendiente", "Nichts war fällig") }
        var parts: [String] = []
        if built > 0 { parts.append(tr("\(built) built", "\(built) construit\(built == 1 ? "" : "s")", "\(built) compilado\(built == 1 ? "" : "s")", "\(built) erstellt")) }
        if failed > 0 { parts.append(tr("\(failed) failed", "\(failed) échec\(failed == 1 ? "" : "s")", "\(failed) fallido\(failed == 1 ? "" : "s")", "\(failed) fehlgeschlagen")) }
        return parts.joined(separator: ", ")
    }
}

/// Games of a batch, with how each went, and a button that takes each out
/// of the queue when REMOVE is given.
struct GameList: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let games: [GameProgress]
    var remove: (@MainActor (String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(games.enumerated()), id: \.element.titleID) { index, game in
                        if index > 0 { Divider().padding(.leading, 52) }
                        row(game)
                    }
                }
            }
        }
    }

    private func row(_ game: GameProgress) -> some View {
        HStack(spacing: 12) {
            if let found = model.game(game.titleID) {
                CoverView(game: found)
                    .frame(width: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Theme.gradient).frame(width: 32, height: 43)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.callout.weight(.medium))
                // Waiting its turn: what its build makes.
                if game.state == "queued", let targets = model.targets(game) {
                    TargetLabel(targets: targets)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Why it failed, or was skipped (a full disk, no room, no keys).
                if let error = game.shownError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                // Its IPA built, its app for this Mac not.
                if let error = game.shownMacError {
                    Text(tr("Mac app: ", "App Mac : ", "App de Mac: ", "Mac-App: ") + error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
                if let commit = game.splitCommit {
                    // This game alone, the others from the newest (decision 133).
                    Text(tr("From nxnative \(commit.prefix(8)), from before nxnative changed how it reads shaders: the newest reads this game’s otherwise than its profile for now",
                            "Avec nxnative \(commit.prefix(8)), d’avant le changement de sa lecture des shaders : le plus récent lit ceux de ce jeu autrement que son profil pour l’instant",
                            "Con nxnative \(commit.prefix(8)), de antes de que nxnative cambiara su lectura de los shaders: la más reciente lee los de este juego de otra forma que su perfil por ahora",
                            "Mit nxnative \(commit.prefix(8)), von bevor nxnative änderte, wie es Shader liest: Die neueste liest die dieses Spiels vorerst anders als sein Profil"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if let commit = game.fallbackCommit {
                    Text(tr("From nxnative \(commit.prefix(8)), the last commit that built: the newest does not build for now",
                            "Avec nxnative \(commit.prefix(8)), le dernier commit qui a construit : le plus récent ne construit pas pour l’instant",
                            "Con nxnative \(commit.prefix(8)), el último commit que compiló: el más reciente no compila por ahora",
                            "Mit nxnative \(commit.prefix(8)), dem letzten Commit, der erstellt hat: Der neueste erstellt vorerst nicht"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(stateText(game))
                .font(.callout)
                .foregroundStyle(stateColor(game))
            if let log = game.log, !log.isEmpty, game.state == "failed" {
                Button {
                    model.open(log)
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(tr("Open its log", "Ouvrir son journal", "Abrir su registro", "Sein Protokoll öffnen"))
            } else if let log = game.macLog, !log.isEmpty, game.mac == "failed" {
                Button {
                    model.open(log)
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(tr("Open the log of its Mac app", "Ouvrir le journal de son app Mac", "Abrir el registro de su app de Mac", "Das Protokoll seiner Mac-App öffnen"))
            }
            if let remove, game.state == "queued" {
                Button {
                    remove(game.titleID)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canTakeOut(game.titleID))
                .help(tr("Remove from the queue", "Retirer de la file", "Quitar de la cola", "Aus der Warteschlange entfernen"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// How it went, and what for (decision 127): its IPA, for the iPhone,
    /// its app for this Mac, or both; the IPA built and its Mac app not, the
    /// line under its name says why.
    private func stateText(_ game: GameProgress) -> String {
        switch game.state {
        case "built" where game.mac == "built":
            // Its IPA and its Mac app, or its Mac app alone.
            let seconds = (game.macOnly == true ? 0 : game.duration ?? 0) + (game.macDuration ?? 0)
            return (game.macOnly == true ? tr("Built for this Mac", "Construit pour ce Mac", "Compilado para este Mac", "Für diesen Mac erstellt")
                : tr("Built for the iPhone and this Mac", "Construit pour l’iPhone et ce Mac", "Compilado para el iPhone y este Mac", "Für das iPhone und diesen Mac erstellt"))
                + (seconds > 0 ? " · " + Format.duration(seconds) : "")
        case "built": return tr("Built for the iPhone", "Construit pour l’iPhone", "Compilado para el iPhone", "Für das iPhone erstellt") + (game.duration.map { " · " + Format.duration($0) } ?? "")
        // Its IPA, or its app for this Mac alone: its Mac app is built after
        // its IPA, never without it.
        case "failed": return game.macOnly == true ? tr("Failed for this Mac", "Échec pour ce Mac", "Falló para este Mac", "Für diesen Mac fehlgeschlagen") : tr("Failed for the iPhone", "Échec pour l’iPhone", "Falló para el iPhone", "Für das iPhone fehlgeschlagen")
        case "stopped": return tr("Stopped", "Arrêté", "Detenido", "Gestoppt")
        case "skipped": return tr("Skipped", "Passé", "Omitido", "Übersprungen")
        case "queued": return tr("Waiting", "En attente", "En espera", "Wartet")
        case "building": return tr("Building", "Construction", "Compilando", "Wird erstellt")
        default: return game.state
        }
    }

    private func stateColor(_ game: GameProgress) -> Color {
        switch game.state {
        case "built": return .green
        case "failed": return .red
        default: return .secondary
        }
    }
}

/// The nightly run, on or off, and its hour.
struct NightlyCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let config = model.config {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.gradient)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Build at night", "Construire la nuit", "Compilar por la noche", "Nachts erstellen"))
                            .font(.headline)
                        Text(config.schedule
                             ? tr("Every night at \(Format.time(hour: config.scheduleHour, minute: config.scheduleMinute)), what is due is built, even with the app closed.",
                                  "Chaque nuit à \(Format.time(hour: config.scheduleHour, minute: config.scheduleMinute)), ce qui est dû se construit, même app fermée.",
                                  "Cada noche a las \(Format.time(hour: config.scheduleHour, minute: config.scheduleMinute)), se compila lo pendiente, incluso con la app cerrada.",
                                  "Jede Nacht um \(Format.time(hour: config.scheduleHour, minute: config.scheduleMinute)) wird Fälliges erstellt, auch bei geschlossener App.")
                             : tr("Off: games are built when you ask.", "Désactivé : les jeux se construisent quand vous le demandez.", "Desactivado: los juegos se compilan cuando lo pides.", "Aus: Spiele werden erstellt, wenn du es verlangst."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { config.schedule }, set: { on in model.update { $0.schedule = on } }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}
