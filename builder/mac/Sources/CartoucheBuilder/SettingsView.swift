//
//  SettingsView.swift
//  Cartouche Builder
//
//  Every setting, without a Terminal: the folders, what is built and when,
//  what is kept on the disk, the bridge, the updates and the measures, and
//  the app's own (language, menu bar, opening at login).
//

import AppKit
import BuilderKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                tab.content
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
            }
        }
        .frame(width: SettingsTab.size.width, height: SettingsTab.size.height)
    }
}

/// The settings' tabs, in order: the Settings scene's toolbar, and the
/// gallery's picture of it (Gallery.swift).
enum SettingsTab: CaseIterable, Identifiable {
    case general, folders, builds, storage, advanced

    static let size = CGSize(width: 600, height: 520)

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return tr("General", "Général", "General", "Allgemein")
        case .folders: return tr("Folders", "Dossiers", "Carpetas", "Ordner")
        case .builds: return tr("Builds", "Constructions", "Compilaciones", "Builds")
        case .storage: return tr("Storage", "Stockage", "Almacenamiento", "Speicher")
        case .advanced: return tr("Advanced", "Avancé", "Avanzado", "Erweitert")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .folders: return "folder"
        case .builds: return "hammer"
        case .storage: return "internaldrive"
        case .advanced: return "slider.horizontal.3"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettings()
        case .folders: FolderSettings()
        case .builds: BuildSettings()
        case .storage: StorageSettings()
        case .advanced: AdvancedSettings()
        }
    }
}

/// A setting of the engine, as a binding that saves it.
@MainActor
func setting<Value>(_ model: AppModel, _ key: WritableKeyPath<BuilderConfig, Value>, _ fallback: Value) -> Binding<Value> {
    Binding(get: { model.config?[keyPath: key] ?? fallback },
            set: { value in model.update { $0[keyPath: key] = value } })
}

struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var telemetry: BuilderTelemetry
    @AppStorage(AppSettings.menuBarKey) private var menuBar = true
    @State private var askErase = false
    @State private var erased: Bool?

    var body: some View {
        Form {
            Section {
                Picker(tr("Language", "Langue", "Idioma", "Sprache"), selection: setting(model, \.language, "")) {
                    Text(tr("The Mac’s", "Celle du Mac", "El del Mac", "Die des Mac")).tag("")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Deutsch").tag("de")
                }
                Toggle(tr("Notifications when a build ends or nxnative improves a game", "Notifications quand une construction finit ou que nxnative améliore un jeu", "Notificaciones cuando termina una compilación o nxnative mejora un juego", "Mitteilungen, wenn ein Build endet oder nxnative ein Spiel verbessert"),
                       isOn: setting(model, \.notifications, true))
                Toggle(tr("Icon in the menu bar", "Icône dans la barre des menus", "Icono en la barra de menús", "Symbol in der Menüleiste"), isOn: $menuBar)
                Toggle(tr("Open at login", "Ouvrir à l’ouverture de session", "Abrir al iniciar sesión", "Beim Anmelden öffnen"), isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
            }
            Section(tr("Updates", "Mises à jour", "Actualizaciones", "Updates")) {
                Toggle(tr("Install updates by itself", "Installer les mises à jour toute seule", "Instalar las actualizaciones automáticamente", "Updates selbst installieren"), isOn: Binding(get: { updater.automatic }, set: { updater.automatic = $0 }))
                LabeledContent(tr("Version", "Version", "Versión", "Version")) {
                    HStack {
                        Text(updater.current)
                        UpdateStateText()
                    }
                }
                HStack {
                    Button(tr("Check for an update", "Rechercher une mise à jour", "Buscar una actualización", "Nach Update suchen")) {
                        Task { await updater.check(force: true) }
                    }
                    .disabled(updater.busy || !updater.enabled)
                    Spacer()
                    UpdateActions()
                }
            }
            Section {
                Toggle(tr("Send usage measures", "Envoyer des mesures d’utilisation", "Enviar mediciones de uso", "Nutzungsmessungen senden"), isOn: Binding(get: { telemetry.isOn }, set: { telemetry.setOn($0) }))
                Text(tr("Builds, their times and failures, this Mac’s model and tools: never a file name, a path, a game’s content or your Apple account.",
                        "Les constructions, leurs durées et leurs échecs, le modèle du Mac et ses outils : jamais un nom de fichier, un chemin, le contenu d’un jeu ni votre compte Apple.",
                        "Las compilaciones, sus tiempos y fallos, el modelo de este Mac y sus herramientas: nunca un nombre de archivo, una ruta, el contenido de un juego ni tu cuenta de Apple.",
                        "Builds, ihre Dauer und Fehler, Modell und Werkzeuge dieses Mac: nie ein Dateiname, ein Pfad, der Inhalt eines Spiels oder dein Apple Account."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Link(tr("What is sent", "Ce qui est envoyé", "Lo que se envía", "Was gesendet wird"), destination: BuilderTelemetry.privacy)
                    Spacer()
                    if let erased {
                        Text(erased ? tr("Erased.", "Effacé.", "Borrado.", "Gelöscht.") : tr("The server did not answer: try again later.", "Le serveur n’a pas répondu : réessayez plus tard.", "El servidor no respondió: vuelve a intentarlo más tarde.", "Der Server hat nicht geantwortet: Versuche es später erneut."))
                            .foregroundStyle(.secondary)
                    }
                    Button(tr("Erase what this Mac sent…", "Effacer ce que ce Mac a envoyé…", "Borrar lo que envió este Mac…", "Löschen, was dieser Mac gesendet hat …")) { askErase = true }
                        .disabled(telemetry.isErasing)
                }
                .font(.caption)
            } header: {
                Text(tr("Measures", "Mesures", "Mediciones", "Messungen"))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(tr("Erase what this Mac sent?", "Effacer ce que ce Mac a envoyé ?", "¿Borrar lo que envió este Mac?", "Löschen, was dieser Mac gesendet hat?"), isPresented: $askErase) {
            Button(tr("Erase", "Effacer", "Borrar", "Löschen"), role: .destructive) {
                Task { erased = await telemetry.erase() }
            }
        } message: {
            Text(tr("The server deletes every report of this Mac; the app then takes a new number.",
                    "Le serveur supprime tous les rapports de ce Mac ; l’app prend ensuite un nouveau numéro.",
                    "El servidor borra todos los informes de este Mac; la app toma luego un número nuevo.",
                    "Der Server löscht alle Berichte dieses Mac; die App nimmt danach eine neue Nummer."))
        }
    }
}

/// What can be done with the update found: download it, or restart for it.
struct UpdateActions: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.state {
        case let .available(release):
            Link(tr("What’s new", "Nouveautés", "Novedades", "Neuigkeiten"), destination: release.page)
            Button(tr("Download \(release.version)", "Télécharger la \(release.version)", "Descargar la \(release.version)", "Version \(release.version) laden")) {
                Task { await updater.download(release) }
            }
            .buttonStyle(.borderedProminent)
        case let .ready(release):
            Link(tr("What’s new", "Nouveautés", "Novedades", "Neuigkeiten"), destination: release.page)
            Button(tr("Restart to update", "Redémarrer pour mettre à jour", "Reiniciar para actualizar", "Zum Aktualisieren neu starten")) {
                Task { await updater.install(relaunch: true) }
            }
            .buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }
}

struct UpdateStateText: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .upToDate:
            Text(tr("up to date", "à jour", "al día", "aktuell"))
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
        case let .available(release):
            Text(tr("\(release.version) available", "\(release.version) disponible", "\(release.version) disponible", "\(release.version) verfügbar"))
                .foregroundStyle(Theme.indigo)
        case let .downloading(release):
            Text(tr("downloading \(release.version)…", "téléchargement de la \(release.version)…", "descargando la \(release.version)…", "\(release.version) wird geladen …"))
                .foregroundStyle(.secondary)
        case let .ready(release):
            Text(tr("\(release.version) ready: it installs when the app quits", "\(release.version) prête : elle s’installe quand l’app quitte", "\(release.version) lista: se instala cuando la app se cierre", "\(release.version) bereit: Wird installiert, wenn die App beendet wird"))
                .foregroundStyle(Theme.indigo)
        case .installing:
            Text(tr("installing…", "installation…", "instalando…", "wird installiert …"))
                .foregroundStyle(.secondary)
        case let .failed(text):
            Text(text)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }
}

struct FolderSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                FolderField(title: tr("Game sources", "Sources des jeux", "Fuentes de los juegos", "Quellen der Spiele"),
                            help: tr("Your games: packages, .nup files, dumps or zipped dumps, loose or in folders.", "Vos jeux : paquets, fichiers .nup, dumps ou dumps zippés, en vrac ou dans des dossiers.", "Tus juegos: paquetes, archivos .nup, dumps o dumps comprimidos, sueltos o en carpetas.", "Deine Spiele: Pakete, .nup-Dateien, Dumps oder gezippte Dumps, lose oder in Ordnern."),
                            path: model.config?.sources ?? "") { path in model.update { $0.sources = path } }
                FolderField(title: tr("Games folder", "Dossier des jeux", "Carpeta de juegos", "Spieleordner"),
                            help: tr("Where the IPAs go: the folder Cartouche reads, on this Mac or on your NAS.", "Où vont les IPA : le dossier que lit Cartouche, sur ce Mac ou sur votre NAS.", "Adónde van las IPA: la carpeta que lee Cartouche, en este Mac o en tu NAS.", "Wohin die IPAs gehen: der Ordner, den Cartouche liest, auf diesem Mac oder auf deinem NAS."),
                            path: model.config?.games ?? "") { path in model.update { $0.games = path } }
                KeysField()
                NamingField()
            } header: {
                Text(tr("Your games", "Vos jeux", "Tus juegos", "Deine Spiele"))
            } footer: {
                Text(tr("A folder on your NAS works: connect its share in the Finder once; Cartouche connects it again by itself.",
                        "Un dossier sur votre NAS convient : connectez son partage dans le Finder une fois, Cartouche le reconnecte ensuite tout seul.",
                        "Sirve una carpeta en tu NAS: conecta su recurso compartido en el Finder una vez; Cartouche lo vuelve a conectar solo.",
                        "Ein Ordner auf deinem NAS geht: Verbinde seine Freigabe einmal im Finder; Cartouche verbindet sie danach von selbst."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(tr("Builds", "Constructions", "Compilaciones", "Builds")) {
                FolderField(title: tr("Build folders", "Dossiers de construction", "Carpetas de compilación", "Build-Ordner"),
                            help: tr("Where games are built; empty for Cartouche’s own folder.", "Où les jeux se construisent ; vide pour le dossier de Cartouche.", "Donde se compilan los juegos; vacío para la carpeta propia de Cartouche.", "Wo die Spiele erstellt werden; leer für den eigenen Ordner von Cartouche."),
                            path: model.config?.workspace ?? "", clearable: true) { path in model.update { $0.workspace = path } }
            }
        }
        .formStyle(.grouped)
    }
}

struct FolderField: View {
    let title: String
    let help: String
    let path: String
    var clearable = false
    /// What an empty PATH stands for, when it stands for a folder.
    var placeholder: String?
    let choose: (String) -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Text(path.isEmpty ? placeholder ?? tr("Not chosen", "Pas choisi", "Sin elegir", "Nicht gewählt") : (path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
                if clearable && !path.isEmpty {
                    Button {
                        choose("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                Button(tr("Choose…", "Choisir…", "Elegir…", "Auswählen …")) {
                    if let url = FolderPicker.choose(title: title, directory: path.isEmpty ? nil : URL(fileURLWithPath: path)) {
                        choose(url.path)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// How to name what the folders hold, the dumps, the games' IPAs and their
/// saves: the help Cartouche shows under its Storage page (NamingHelp.swift).
struct NamingField: View {
    var body: some View {
        LabeledContent {
            NamingHelpButton(title: tr("Show…", "Afficher…", "Mostrar…", "Zeigen …"))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(NamingHelp.title)
                Text(tr("What Cartouche finds in each folder, on this Mac and on the iPhone, with examples.",
                        "Ce que Cartouche trouve dans chaque dossier, sur ce Mac et sur l’iPhone, avec des exemples.",
                        "Lo que Cartouche encuentra en cada carpeta, en este Mac y en el iPhone, con ejemplos.",
                        "Was Cartouche in jedem Ordner findet, auf diesem Mac und auf dem iPhone, mit Beispielen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// prod.keys: whether it is chosen, never where it is.
struct KeysField: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let chosen = !(model.config?.keys ?? "").isEmpty
        let present = model.library?.folders?.keys?.present ?? chosen
        LabeledContent {
            HStack {
                Label(chosen ? (present ? tr("Chosen", "Choisi", "Elegido", "Gewählt") : tr("Not found", "Introuvable", "No encontrado", "Nicht gefunden")) : tr("Not chosen", "Pas choisi", "Sin elegir", "Nicht gewählt"),
                      systemImage: chosen && present ? "checkmark.seal.fill" : "key")
                    .foregroundStyle(chosen && present ? Color.green : Color.secondary)
                Button(tr("Choose…", "Choisir…", "Elegir…", "Auswählen …")) {
                    if let url = FolderPicker.chooseFile(title: "prod.keys") {
                        model.update { $0.keys = url.path }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("prod.keys")
                Text(tr("Your console’s keys, for games given as packages. They stay on this Mac.", "Les clés de votre console, pour les jeux en paquets. Elles restent sur ce Mac.", "Las claves de tu consola, para los juegos en paquetes. Se quedan en este Mac.", "Die Schlüssel deiner Konsole, für Spiele als Pakete. Sie bleiben auf diesem Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BuildSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            platforms
            Section {
                Picker(tr("When nxnative’s shared code changes", "Quand le code commun de nxnative change", "Cuando cambia el código compartido de nxnative", "Wenn sich der gemeinsame Code von nxnative ändert"), selection: setting(model, \.enginePolicy, "weekly")) {
                    Text(tr("Rebuild, at most every few days", "Reconstruire, au plus tous les quelques jours", "Recompilar, como mucho cada pocos días", "Neu erstellen, höchstens alle paar Tage")).tag("weekly")
                    Text(tr("Rebuild each time", "Reconstruire à chaque fois", "Recompilar cada vez", "Jedes Mal neu erstellen")).tag("always")
                    Text(tr("Do not rebuild", "Ne pas reconstruire", "No recompilar", "Nicht neu erstellen")).tag("never")
                }
                if model.config?.enginePolicy == "weekly" {
                    Stepper(value: setting(model, \.refreshDays, 7), in: 1...60) {
                        Text(tr("At most every \(model.config?.refreshDays ?? 7) days", "Au plus tous les \(model.config?.refreshDays ?? 7) jours", "Como mucho cada \(model.config?.refreshDays ?? 7) días", "Höchstens alle \(model.config?.refreshDays ?? 7) Tage"))
                    }
                }
            } header: {
                Text(tr("Rebuilds", "Reconstructions", "Recompilaciones", "Neu-Builds"))
            } footer: {
                Text(tr("A change to a game’s own profile, or a fix that names it, always rebuilds it.",
                        "Un changement du profil d’un jeu, ou un correctif qui le nomme, le reconstruit toujours.",
                        "Un cambio en el propio perfil de un juego, o una corrección que lo nombre, siempre lo recompila.",
                        "Eine Änderung am eigenen Profil eines Spiels oder eine Korrektur, die es nennt, erstellt es immer neu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(tr("At night", "La nuit", "Por la noche", "Nachts")) {
                Toggle(tr("Build what is due every night", "Construire ce qui est dû chaque nuit", "Compilar lo pendiente cada noche", "Fälliges jede Nacht erstellen"), isOn: setting(model, \.schedule, false))
                DatePicker(tr("At", "À", "A las", "Um"), selection: Binding(get: { nightlyDate }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    model.update {
                        $0.scheduleHour = parts.hour ?? 3
                        $0.scheduleMinute = parts.minute ?? 30
                    }
                }), displayedComponents: .hourAndMinute)
                .disabled(!(model.config?.schedule ?? false))
            }
            Section {
                Picker(tr("Games built at once", "Jeux construits en même temps", "Juegos compilados a la vez", "Gleichzeitig erstellte Spiele"), selection: setting(model, \.jobs, 1)) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(tr("Language of the games", "Langue des jeux", "Idioma de los juegos", "Sprache der Spiele"), selection: setting(model, \.gameLanguage, "")) {
                    ForEach(GameLanguages.all, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Toggle(tr("Also build games nxnative has no profile for (they may not start)", "Construire aussi les jeux sans profil nxnative (ils peuvent ne pas démarrer)", "Compilar también los juegos sin perfil de nxnative (puede que no arranquen)", "Auch Spiele ohne Profil von nxnative erstellen (sie starten vielleicht nicht)"),
                       isOn: setting(model, \.unprofiled, false))
            } header: {
                Text(tr("Games", "Jeux", "Juegos", "Spiele"))
            } footer: {
                Text(tr("Cartouche starts each game in the language of the iPhone or of this Mac when the game has it; this one otherwise.",
                        "Cartouche lance chaque jeu dans la langue de l’iPhone ou de ce Mac quand le jeu l’a ; sinon dans celle-ci.",
                        "Cartouche inicia cada juego en el idioma del iPhone o de este Mac cuando el juego lo tiene; si no, en este.",
                        "Cartouche startet jedes Spiel in der Sprache des iPhones oder dieses Mac, wenn das Spiel sie hat; sonst in dieser."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Each game built for the iPhone and for this Mac, unless one of the
    /// two is turned off, for every game here or for one on its sheet; one
    /// of the two stays on.
    private var platforms: some View {
        let ios = model.config?.ios ?? true
        let mac = model.config?.mac ?? true
        let defaultFolder = ((model.info?.defaultMacApps ?? "~/Applications") as NSString).abbreviatingWithTildeInPath
        return Section {
            Toggle(isOn: setting(model, \.ios, true)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone")
                    Text(tr("Each game’s IPA, in the games folder, for Cartouche.", "L’IPA de chaque jeu, dans le dossier des jeux, pour Cartouche.", "La IPA de cada juego, en la carpeta de juegos, para Cartouche.", "Die IPA jedes Spiels, im Spieleordner, für Cartouche."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(ios && !mac)
            Toggle(isOn: setting(model, \.mac, true)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("This Mac", "Ce Mac", "Este Mac", "Dieser Mac"))
                    Text(tr("Each game’s app, beside its IPA, to play it on this Mac.", "L’app de chaque jeu, à côté de son IPA, pour y jouer sur ce Mac.", "La app de cada juego, junto a su IPA, para jugarlo en este Mac.", "Die App jedes Spiels, neben seiner IPA, um es auf diesem Mac zu spielen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(mac && !ios)
            if mac {
                FolderField(title: tr("Installed from a NAS in", "Installées depuis un NAS dans", "Instaladas desde un NAS en", "Von einem NAS installiert in"),
                            help: tr("A games folder on a NAS keeps each game’s app in one file: it is installed here when you play the game. Empty for the Applications folder of your session, where Launchpad finds them.",
                                     "Un dossier des jeux sur un NAS garde l’app de chaque jeu en un seul fichier : elle s’installe ici quand vous jouez au jeu. Vide pour le dossier Applications de votre session, où Launchpad les trouve.",
                                     "Una carpeta de juegos en un NAS guarda la app de cada juego en un solo archivo: se instala aquí cuando juegues al juego. Vacío para la carpeta Aplicaciones de tu sesión, donde Launchpad las encuentra.",
                                     "Ein Spieleordner auf einem NAS bewahrt die App jedes Spiels als eine Datei auf: Sie wird hier installiert, wenn du das Spiel spielst. Leer für den Ordner „Programme“ deiner Sitzung, wo Launchpad sie findet."),
                            path: model.config?.macApps ?? "", clearable: true, placeholder: defaultFolder) { path in model.update { $0.macApps = path } }
            }
        } header: {
            Text(tr("Built for", "Construire pour", "Compilar para", "Erstellen für"))
        } footer: {
            Text(tr("A game’s sheet turns one of the two off for that game alone. One of the two stays on.",
                    "La fiche d’un jeu désactive l’un des deux pour ce jeu seul. L’un des deux reste activé.",
                    "La ficha de un juego desactiva uno de los dos solo para ese juego. Uno de los dos sigue activado.",
                    "Die Infoseite eines Spiels schaltet eines der beiden nur für dieses Spiel aus. Eines der beiden bleibt an."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nightlyDate: Date {
        let config = model.config
        return Calendar.current.date(bySettingHour: config?.scheduleHour ?? 3, minute: config?.scheduleMinute ?? 30, second: 0, of: Date()) ?? Date()
    }
}

/// The languages nxnative's -l takes (its nacp.py's codes).
enum GameLanguages {
    struct Language {
        let code: String
        let name: String
    }

    static var all: [Language] {
        [
            Language(code: "", name: tr("nxnative’s (English)", "Celle de nxnative (anglais)", "El de nxnative (inglés)", "Die von nxnative (Englisch)")),
            Language(code: "fr", name: "Français"),
            Language(code: "fr-CA", name: "Français (Canada)"),
            Language(code: "en-US", name: "English (US)"),
            Language(code: "en-GB", name: "English (UK)"),
            Language(code: "de", name: "Deutsch"),
            Language(code: "it", name: "Italiano"),
            Language(code: "es", name: "Español"),
            Language(code: "es-419", name: "Español (Latinoamérica)"),
            Language(code: "nl", name: "Nederlands"),
            Language(code: "pt", name: "Português"),
            Language(code: "pt-BR", name: "Português (Brasil)"),
            Language(code: "ja", name: "日本語"),
            Language(code: "ko", name: "한국어"),
            Language(code: "zh-Hans", name: "简体中文"),
            Language(code: "zh-Hant", name: "繁體中文"),
            Language(code: "ru", name: "Русский"),
        ]
    }
}

struct StorageSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Stepper(value: setting(model, \.minFreeGB, 20), in: 0...500, step: 5) {
                    Text(tr("Keep at least \(model.config?.minFreeGB ?? 20) GB free", "Garder au moins \(model.config?.minFreeGB ?? 20) Go libres", "Mantener al menos \(model.config?.minFreeGB ?? 20) GB libres", "Mindestens \(model.config?.minFreeGB ?? 20) GB frei lassen"))
                }
                Stepper(value: setting(model, \.workspaceLimitGB, 0), in: 0...2000, step: 10) {
                    let limit = model.config?.workspaceLimitGB ?? 0
                    Text(limit == 0 ? tr("No limit to the build folders", "Pas de limite aux dossiers de construction", "Sin límite para las carpetas de compilación", "Keine Grenze für die Build-Ordner")
                                    : tr("Build folders: at most \(limit) GB", "Dossiers de construction : \(limit) Go au plus", "Carpetas de compilación: \(limit) GB como máximo", "Build-Ordner: höchstens \(limit) GB"))
                }
            } footer: {
                Text(tr("When the disk fills, the build folders used the longest ago go first.", "Quand le disque se remplit, les dossiers de construction utilisés il y a le plus longtemps partent d’abord.", "Cuando el disco se llena, las carpetas de compilación usadas hace más tiempo se van primero.", "Wenn die Festplatte voll wird, gehen die am längsten nicht genutzten Build-Ordner zuerst."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(tr("Keep the extracted game files", "Garder les fichiers extraits des jeux", "Conservar los archivos extraídos de los juegos", "Extrahierte Spieldateien behalten"), isOn: setting(model, \.keepExtracted, false))
                Toggle(tr("Keep each IPA in its build folder, even on another disk", "Garder chaque IPA dans son dossier de construction, même sur un autre disque", "Conservar cada IPA en su carpeta de compilación, incluso en otro disco", "Jede IPA in ihrem Build-Ordner behalten, auch auf einer anderen Festplatte"),
                       isOn: setting(model, \.keepIPA, false))
            } footer: {
                Text(tr("Kept, the extracted files make the next build faster but take as much room as the game. On the games folder’s disk, an IPA copy takes no room.",
                        "Gardés, les fichiers extraits accélèrent la prochaine construction mais prennent autant de place que le jeu. Sur le disque du dossier des jeux, une copie d’IPA ne prend pas de place.",
                        "Si se conservan, los archivos extraídos aceleran la siguiente compilación pero ocupan tanto como el juego. En el disco de la carpeta de juegos, una copia de IPA no ocupa espacio.",
                        "Behalten beschleunigen die extrahierten Dateien den nächsten Build, belegen aber so viel Platz wie das Spiel. Auf der Festplatte des Spieleordners belegt eine IPA-Kopie keinen Platz."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var url = ""
    @State private var branch = ""

    var body: some View {
        Form {
            Section {
                TextField(tr("Repository", "Dépôt", "Repositorio", "Repository"), text: $url)
                    .onSubmit { save() }
                TextField(tr("Branch", "Branche", "Rama", "Branch"), text: $branch)
                    .onSubmit { save() }
                HStack {
                    Button(tr("Back to nxnative’s", "Revenir à celui de nxnative", "Volver al de nxnative", "Zurück zu dem von nxnative")) {
                        url = BuilderConfig.engineURL
                        branch = BuilderConfig.engineBranch
                        save()
                    }
                    Spacer()
                    Button(tr("Save", "Enregistrer", "Guardar", "Sichern")) { save() }
                        .disabled(url == model.config?.engineURL && branch == model.config?.engineBranch)
                }
            } header: {
                Text("nxnative")
            } footer: {
                Text(tr("The nxnative games are built from. Change it only to try a fork.", "Le nxnative avec lequel les jeux sont construits. À changer seulement pour essayer une variante.", "El nxnative con el que se compilan los juegos. Cámbialo solo para probar un fork.", "Das nxnative, mit dem die Spiele erstellt werden. Ändere es nur, um einen Fork auszuprobieren."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(AppName.name) {
                LabeledContent(tr("Version", "Version", "Versión", "Version"), value: model.info?.version ?? "—")
                LabeledContent("Python", value: model.engine?.python.path ?? "—")
                Button(tr("Show its folder in the Finder", "Afficher son dossier dans le Finder", "Mostrar su carpeta en el Finder", "Seinen Ordner im Finder zeigen")) { model.reveal(model.home.root.path) }
                Button(tr("Open the setup assistant", "Ouvrir l’assistant de configuration", "Abrir el asistente de configuración", "Einrichtungsassistenten öffnen")) {
                    model.showMainWindow()
                    model.openSetup()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            url = model.config?.engineURL ?? BuilderConfig.engineURL
            branch = model.config?.engineBranch ?? BuilderConfig.engineBranch
        }
    }

    private func save() {
        let url = url.trimmingCharacters(in: .whitespaces)
        let branch = branch.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !branch.isEmpty else { return }
        model.update {
            $0.engineURL = url
            $0.engineBranch = branch
        }
    }
}

/// The Finder's panel, to choose a folder or a file.
@MainActor
enum FolderPicker {
    static func choose(title: String, directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = tr("Choose", "Choisir", "Elegir", "Auswählen")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let directory { panel.directoryURL = directory }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = tr("Choose", "Choisir", "Elegir", "Auswählen")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
