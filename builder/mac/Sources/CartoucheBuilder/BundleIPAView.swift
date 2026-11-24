// An existing slim nxnative IPA and its matching game data, without a build.

import AppKit
import BuilderKit
import SwiftUI
import UniformTypeIdentifiers

struct BundleIPAView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var ipa: URL?
    @State private var image: URL?
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Import IPA + ROMFS", "Importer IPA + ROMFS", "Importar IPA + ROMFS", "IPA + ROMFS importieren"))
                .font(.title2.bold())
            Text(tr("Add matching game data to an existing nxnative IPA without compiling. The build must support romfs.img inside its app bundle. Your original files stay as they are.",
                    "Ajoutez les fichiers du jeu à une IPA nxnative existante, sans compiler. Cette version doit accepter romfs.img dans l’app. Vos fichiers d’origine sont conservés.",
                    "Añade los archivos del juego a una IPA de nxnative existente, sin compilar. La compilación debe admitir romfs.img dentro de su app. Tus archivos originales se quedan como están.",
                    "Füge die Spieldateien zu einer vorhandenen IPA von nxnative hinzu, ohne zu kompilieren. Der Build muss romfs.img in seiner App unterstützen. Deine Originaldateien bleiben, wie sie sind."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            fileRow("IPA", url: ipa) { ipa = chooseFile("IPA", extension: "ipa") }
            fileRow("romfs.img", url: image) { image = chooseFile("romfs.img", extension: "img") }
            if model.bundling {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.bundleMessage).font(.callout)
                }
            }
            if let problem { Text(problem).foregroundStyle(.red).textSelection(.enabled) }
            if let result {
                Text(tr("The complete IPA is in your games folder. Refresh Cartouche on the iPhone to install it.",
                        "L’IPA complète est dans le dossier des jeux. Actualisez Cartouche sur l’iPhone pour l’installer.",
                        "La IPA completa está en tu carpeta de juegos. Actualiza Cartouche en el iPhone para instalarla.",
                        "Die vollständige IPA ist in deinem Spieleordner. Aktualisiere Cartouche auf dem iPhone, um sie zu installieren."))
                Button(tr("Show in Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result)])
                }
            }
            HStack {
                Spacer()
                Button(tr("Close", "Fermer", "Cerrar", "Schließen")) { dismiss() }
                    .disabled(model.bundling)
                    .keyboardShortcut(.cancelAction)
                if result == nil {
                    Button(tr("Create complete IPA", "Créer l’IPA complète", "Crear la IPA completa", "Vollständige IPA erstellen")) { importIPA() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ipa == nil || image == nil || model.bundling)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .interactiveDismissDisabled(model.bundling)
    }

    private func fileRow(_ title: String, url: URL?, choose: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(url?.lastPathComponent ?? tr("Not chosen yet", "Pas encore choisi", "Aún no elegido", "Noch nicht gewählt"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(tr("Choose…", "Choisir…", "Elegir…", "Auswählen …"), action: choose)
                .disabled(model.bundling || result != nil)
        }
    }

    private func chooseFile(_ title: String, extension suffix: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: suffix) { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func importIPA() {
        guard let ipa, let image else { return }
        problem = nil
        Task {
            do { result = try await model.bundleIPA(ipa, image: image) }
            catch { problem = error.localizedDescription }
        }
    }
}
