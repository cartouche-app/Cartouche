//
//  RenewalView.swift
//  Cartouche Builder
//
//  The iPhone page's renewal of Cartouche from this Mac (Renewals.swift,
//  decision 165): the Apple Account it renews with, signed in once with
//  the password and Apple's code, which the page sends on and forgets;
//  each iPhone this Mac reaches, until when Cartouche opens there, when
//  this Mac renews it or why it did not, in the player's words
//  (SignerWords), and Renew, for whenever the player wants it.
//

import BuilderKit
import SwiftUI

struct RenewalSection: View {
    @ObservedObject var renewals: RenewalController
    @State private var email = ""
    /// Typed, sent to the helper, and emptied at once.
    @State private var password = ""
    @State private var code = ""

    /// A row of the section: a copy of Cartouche on an iPhone, or an
    /// iPhone without one, or that did not answer.
    private struct Row: Identifiable {
        let iphone: SignerIphone
        let copy: SignerCartouche?
        var id: String { iphone.udid + "|" + (copy?.bundleId ?? "") }
    }

    private var rows: [Row] {
        renewals.iphones.flatMap { iphone in
            iphone.error == nil && !iphone.cartouche.isEmpty
                ? iphone.cartouche.map { Row(iphone: iphone, copy: $0) }
                : [Row(iphone: iphone, copy: nil)]
        }
    }

    var body: some View {
        if renewals.available {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Renewing Cartouche", "Renouvellement de Cartouche", "Renovación de Cartouche", "Erneuerung von Cartouche").uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Card(padding: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        account
                        if let step = renewals.step {
                            Divider().padding(.leading, 48)
                            signIn(step)
                        }
                        ForEach(rows) { row in
                            Divider().padding(.leading, 48)
                            copyRow(row)
                        }
                        if rows.isEmpty, renewals.looked != nil {
                            Divider().padding(.leading, 48)
                            line(symbol: "cable.connector", SignerWords.noIphone)
                        }
                    }
                }
                Text(SignerWords.footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .task { await renewals.look(renewing: false) }
        }
    }

    // MARK: The account

    private var account: some View {
        let said = SignerWords.account(renewals.session, ended: renewals.sessionEnded)
        return HStack(spacing: 14) {
            Image(systemName: "person.crop.circle")
                .font(.title3)
                .foregroundStyle(said.line.warning ? Color.orange : Theme.indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(said.title)
                    .font(.callout.weight(.medium))
                Text(said.line.text)
                    .font(.caption)
                    .foregroundStyle(said.line.warning ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if renewals.signedIn, !renewals.sessionEnded {
                Button(tr("Sign Out", "Se déconnecter", "Cerrar sesión", "Abmelden")) { renewals.signOut() }
                    .controlSize(.small)
            } else if renewals.step == nil {
                Button(tr("Sign In…", "Se connecter…", "Iniciar sesión…", "Anmelden …")) {
                    email = renewals.session?.email ?? email
                    renewals.step = .form
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The form: the account and its password, then Apple's code.
    @ViewBuilder
    private func signIn(_ step: RenewalSignIn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch step {
            case .form, .signingIn:
                let busy = step == .signingIn
                TextField(tr("Apple Account", "Compte Apple", "Cuenta de Apple", "Apple Account"), text: $email, prompt: Text(verbatim: "name@example.com"))
                    .frame(maxWidth: 320)
                    .disabled(busy)
                SecureField(tr("Password", "Mot de passe", "Contraseña", "Passwort"), text: $password)
                    .frame(maxWidth: 320)
                    .disabled(busy)
                    .onSubmit(send)
                Text(tr("Sent to Apple alone, once: this Mac keeps the session Apple gives, never the password.",
                        "Envoyé à Apple seul, une fois : ce Mac garde la session qu’Apple donne, jamais le mot de passe.",
                        "Enviada solo a Apple, una vez: este Mac guarda la sesión que da Apple, nunca la contraseña.",
                        "Nur an Apple gesendet, einmal: Dieser Mac behält die Sitzung, die Apple gibt, nie das Passwort."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(tr("Sign In", "Se connecter", "Iniciar sesión", "Anmelden"), action: send)
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    Button(tr("Cancel", "Annuler", "Cancelar", "Abbrechen")) { renewals.closeSignIn() }
                        .disabled(busy)
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                }
                .controlSize(.small)
            case .code(let request):
                Text(SignerWords.codeLine(request))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(tr("Code", "Code", "Código", "Code"), text: $code, prompt: Text(verbatim: "123456"))
                    .frame(maxWidth: 160)
                    .onSubmit(sendCode)
                HStack(spacing: 8) {
                    Button(tr("Continue", "Valider", "Continuar", "Weiter"), action: sendCode)
                        .keyboardShortcut(.defaultAction)
                        .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                    if !request.bySms, let number = request.numbers.first {
                        Button(tr("By Text Message", "Par SMS", "Por SMS", "Per SMS")) { renewals.answer(.sms(number.id)) }
                    }
                    Button(tr("Send Again", "Renvoyer", "Reenviar", "Erneut senden")) { renewals.answer(.resend) }
                    Button(tr("Cancel", "Annuler", "Cancelar", "Abbrechen")) { renewals.closeSignIn() }
                }
                .controlSize(.small)
            }
            if let failure = renewals.signInFailure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 50)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        guard !email.isEmpty, !password.isEmpty else { return }
        let typed = password
        password = ""
        renewals.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: typed)
    }

    private func sendCode() {
        let typed = code.filter(\.isNumber)
        guard typed.count >= 6 else { return }
        code = ""
        renewals.answer(.code(typed))
    }

    // MARK: The iPhones

    private func copyRow(_ row: Row) -> some View {
        let iphone = row.iphone
        var title = [iphone.name ?? "iPhone", SignerWords.link(iphone.link)]
        var lines: [SignerLine] = []
        var plan: SignerPlan?
        if let failure = iphone.error {
            lines = [SignerLine(SignerWords.failure(kind: failure.kind), warning: true)]
        } else if let copy = row.copy {
            if let version = copy.version { title.append("Cartouche " + version) }
            plan = renewals.plan(iphone, copy)
            lines = SignerWords.lines(for: copy, plan: plan!, last: renewals.last(iphone, copy),
                                      working: renewals.isWorking(iphone, copy), signedIn: renewals.signedIn)
        } else {
            lines = [SignerLine(SignerWords.failure(kind: "no-cartouche"))]
        }
        let renewable = renewals.signedIn && !renewals.sessionEnded && plan.map { $0 != .otherTeam && $0 != .needsInstall } == true
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundStyle(lines.contains(where: \.warning) ? Color.orange : Theme.indigo)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.joined(separator: " · "))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(line.warning ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if renewable, let copy = row.copy {
                Button(tr("Renew", "Renouveler", "Renovar", "Erneuern")) {
                    Task { await renewals.renew(iphone, copy, asked: true) }
                }
                .controlSize(.small)
                .disabled(renewals.isWorking(iphone, copy))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func line(symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.indigo)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
