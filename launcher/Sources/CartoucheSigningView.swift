import SwiftUI

/// The certificate, its password and its profile, for a Cartouche signed
/// with the player's own certificate. Signed on the iPhone by a signing app,
/// the profile is the one in Cartouche: the player chooses the certificate
/// and types its password, no more. Each file is chosen in the Files picker
/// a game's IPA is imported with (CartoucheImportPicker), which UIKit shows
/// over the page: up to 0.16.2, SwiftUI's file importer showed it, and a
/// .p12 tapped in it on an iPhone of iOS 27.3 never came back (issue #353).
@available(iOS 17.0, *)
struct CartoucheSigningView: View {
    @ObservedObject private var setup = CartoucheSetup.shared
    @State private var certificate: Data?
    @State private var profile: Data?
    @State private var password = ""
    @State private var fileProblem: String?

    private let onIPhone = CartoucheImportedSigning.isSignedOnIPhone

    /// CERTIFICATE: one chosen already, as the gallery shows the page after
    /// an import that failed.
    init(certificate: Data? = nil) {
        _certificate = State(initialValue: certificate)
    }

    var body: some View {
        Form {
            Section {
                Text(onIPhone ? CartoucheText.signingHowOnIPhone : CartoucheText.signingHow)
                Button(certificate == nil ? CartoucheText.signingChooseCertificate : CartoucheText.signingCertificateChosen) {
                    choose(.certificate)
                }
                if !onIPhone {
                    Button(profile == nil ? CartoucheText.signingChooseProfile : CartoucheText.signingProfileChosen) {
                        choose(.profile)
                    }
                }
                SecureField(CartoucheText.signingPassword, text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(CartoucheText.signingUse) {
                    guard let certificate, onIPhone || profile != nil else { return }
                    Task {
                        await setup.importSigning(certificate: certificate, password: password, profile: onIPhone ? nil : profile)
                        password = ""
                    }
                }
                .disabled(certificate == nil || (!onIPhone && profile == nil) || setup.isImportingSigning)
                if setup.isImportingSigning { ProgressView(CartoucheText.setupCertificateChecking) }
                if let problem = fileProblem ?? setup.signingProblem {
                    Text(problem).foregroundStyle(.red)
                } else if setup.usesImportedSigning && setup.certificateWorks == true {
                    Label(CartoucheText.setupCertificateDone, systemImage: "checkmark.shield")
                }
            } footer: {
                Text(onIPhone ? CartoucheText.signingOnlyOwnCertificate : CartoucheText.signingReinstall)
            }
        }
        .navigationTitle(CartoucheText.signingTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Shows the Files picker for the certificate or the profile: the file
    /// picked, a copy in Cartouche's temporary folder, is read, then
    /// removed.
    private func choose(_ file: CartoucheImportPicker.Place) {
        CartoucheImportPicker.shared.pick(from: file) { url in
            defer { if file.copies { try? FileManager.default.removeItem(at: url) } }
            do {
                let data = try Self.read(url)
                if file == .certificate { certificate = data } else { profile = data }
                fileProblem = nil
            } catch { fileProblem = error.localizedDescription }
        }
    }

    /// A signing file of 4 MB at most: a .p12 or a profile is a few
    /// kilobytes.
    private static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 4 * 1024 * 1024 else {
            throw CartoucheImportedSigning.ImportError(message: CartoucheText.signingInvalidFile)
        }
        return try Data(contentsOf: url)
    }
}
