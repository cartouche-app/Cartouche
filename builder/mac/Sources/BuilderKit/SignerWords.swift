//
//  SignerWords.swift
//  Cartouche Builder
//
//  What the iPhone page says of the renewal of Cartouche from this Mac
//  (decision 165): the Apple account it renews with, until when Cartouche
//  opens on each iPhone, when this Mac renews it or installs it again over
//  itself, and why it did not, in the player's words. The helper's message, which may name the account or
//  the iPhone, is never shown in place of them: it goes to the log.
//

import Foundation

/// A line of the page, and whether it says something to do.
public struct SignerLine: Equatable, Sendable {
    public var text: String
    public var warning: Bool

    public init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }
}

public enum SignerWords {
    /// The account's title and the line under it: signed in, Apple having
    /// ended the session (ENDED), or not signed in.
    public static func account(_ session: SignerSession?, ended: Bool, now: Date = Date()) -> (title: String, line: SignerLine) {
        guard let session, session.signedIn else {
            return (tr("Apple Account", "Compte Apple", "Cuenta de Apple", "Apple Account"),
                    SignerLine(tr("Not signed in. Signed in once, this Mac renews Cartouche on your iPhone in its last two days. Your password goes to Apple alone: this Mac does not keep it.",
                                  "Non connecté. Connecté une fois, ce Mac renouvelle Cartouche sur votre iPhone dans ses deux derniers jours. Le mot de passe va à Apple seul : ce Mac ne le garde pas.",
                                  "Sin iniciar sesión. Con la sesión iniciada una vez, este Mac renueva Cartouche en tu iPhone en sus dos últimos días. Tu contraseña va solo a Apple: este Mac no la guarda.",
                                  "Nicht angemeldet. Einmal angemeldet, erneuert dieser Mac Cartouche auf deinem iPhone in seinen letzten zwei Tagen. Dein Passwort geht nur an Apple: Dieser Mac behält es nicht.")))
        }
        let title = session.email ?? tr("Apple Account", "Compte Apple", "Cuenta de Apple", "Apple Account")
        if ended {
            return (title, SignerLine(tr("Apple ended the session: sign in again for the next renewal.",
                                         "Apple a fermé la session : connectez-vous de nouveau pour le prochain renouvellement.",
                                         "Apple cerró la sesión: vuelve a iniciarla para la próxima renovación.",
                                         "Apple hat die Sitzung beendet: Melde dich für die nächste Erneuerung erneut an."), warning: true))
        }
        var parts: [String] = []
        if let team = session.teamName { parts.append(tr("Team \(team)", "Équipe \(team)", "Equipo \(team)", "Team \(team)")) }
        if let since = session.since {
            parts.append(tr("signed in \(Format.relative(since, now: now))", "connecté \(Format.relative(since, now: now))",
                            "sesión iniciada \(Format.relative(since, now: now))", "angemeldet \(Format.relative(since, now: now))"))
        }
        parts.append(tr("the password is not kept", "le mot de passe n’est pas gardé", "la contraseña no se guarda", "das Passwort wird nicht behalten"))
        let line = parts.joined(separator: " · ")
        return (title, SignerLine(line.prefix(1).uppercased() + line.dropFirst()))
    }

    /// How this Mac reaches the iPhone.
    public static func link(_ link: String) -> String {
        link == "usb"
            ? tr("by cable", "par câble", "por cable", "per Kabel")
            : tr("on the Wi-Fi", "sur le Wi-Fi", "por Wi-Fi", "über WLAN")
    }

    /// Until when COPY opens, what this Mac does about it (PLAN), and what
    /// came of its last try (LAST); WORKING while it renews it, or installs
    /// it again at PROGRESS; this Mac SIGNEDIN to Apple, or not yet.
    public static func lines(for copy: SignerCartouche, plan: SignerPlan, last: SignerAttempt?, working: Bool, progress: SignerProgress? = nil,
                             signedIn: Bool = true, now: Date = Date()) -> [SignerLine] {
        var lines: [SignerLine] = []
        if let expires = copy.expires {
            lines.append(expires > now
                ? SignerLine(tr("Cartouche opens until \(Format.date(expires))", "Cartouche s’ouvre jusqu’au \(Format.date(expires))",
                                "Cartouche se abre hasta el \(Format.date(expires))", "Cartouche öffnet bis \(Format.date(expires))"))
                : SignerLine(tr("Cartouche expired \(Format.relative(expires, now: now))", "Cartouche a expiré \(Format.relative(expires, now: now))",
                                "Cartouche caducó \(Format.relative(expires, now: now))", "Cartouche ist \(Format.relative(expires, now: now)) abgelaufen"),
                             warning: true))
        }
        if let last, !last.failed, last.expires == copy.expires {
            let when = Format.relative(last.at, now: now)
            lines.append(last.wasInstall
                ? SignerLine(tr("Installed again by this Mac \(when)", "Réinstallé par ce Mac \(when)", "Reinstalado por este Mac \(when)",
                                "Von diesem Mac \(when) neu installiert"))
                : SignerLine(tr("Renewed by this Mac \(when)", "Renouvelé par ce Mac \(when)", "Renovado por este Mac \(when)",
                                "Von diesem Mac \(when) erneuert")))
        }
        if let progress {
            lines.append(SignerLine(installing(progress)))
            return lines
        }
        if working {
            lines.append(SignerLine(tr("Renewing…", "Renouvellement…", "Renovando…", "Wird erneuert …")))
            return lines
        }
        switch plan {
        case .wait(let until):
            if let last, let kind = last.kind, last.expires == copy.expires {
                lines.append(SignerLine(failure(kind: kind), warning: true))
                lines.append(SignerLine(tr("This Mac tries again \(Format.relative(until, now: now))", "Ce Mac réessaie \(Format.relative(until, now: now))",
                                           "Este Mac lo intenta de nuevo \(Format.relative(until, now: now))", "Dieser Mac versucht es \(Format.relative(until, now: now)) erneut")))
            } else if !signedIn {
                lines.append(SignerLine(tr("Signed in to Apple, this Mac renews it from \(Format.date(until))",
                                           "Connecté à Apple, ce Mac le renouvelle à partir du \(Format.date(until))",
                                           "Con la sesión iniciada en Apple, este Mac lo renueva a partir del \(Format.date(until))",
                                           "Bei Apple angemeldet, erneuert dieser Mac es ab \(Format.date(until))")))
            } else {
                lines.append(SignerLine(tr("This Mac renews it from \(Format.date(until))", "Ce Mac le renouvelle à partir du \(Format.date(until))",
                                           "Este Mac lo renueva a partir del \(Format.date(until))", "Dieser Mac erneuert es ab \(Format.date(until))")))
            }
        case .renew:
            lines.append(SignerLine(tr("This Mac renews it now", "Ce Mac le renouvelle maintenant", "Este Mac lo renueva ahora", "Dieser Mac erneuert es jetzt")))
        case .askPassword:
            lines.append(SignerLine(tr("Sign in to Apple above for this Mac to renew it.", "Connectez-vous à Apple ci-dessus pour que ce Mac le renouvelle.",
                                       "Inicia sesión en Apple arriba para que este Mac lo renueve.", "Melde dich oben bei Apple an, damit dieser Mac es erneuert."),
                                    warning: true))
        case .needsInstall:
            if let last, let kind = last.kind, last.wasInstall, last.expires == copy.expires {
                lines.append(SignerLine(failure(kind: kind), warning: true))
            }
            lines.append(SignerLine(needsInstall, warning: true))
        case .reinstall:
            lines.append(SignerLine(tr("This Mac installs it again now, with its games and saves", "Ce Mac le réinstalle maintenant, avec ses jeux et ses sauvegardes",
                                       "Este Mac lo reinstala ahora, con sus juegos y partidas guardadas",
                                       "Dieser Mac installiert es jetzt neu, mit seinen Spielen und Spielständen")))
        case .otherTeam:
            lines.append(SignerLine(failure(kind: "other-team")))
        }
        return lines
    }

    /// What stopped a renewal or a sign-in, by its kind, in the player's
    /// words.
    public static func failure(kind: String) -> String {
        switch kind {
        case "no-session":
            return tr("This Mac is not signed in to Apple.", "Ce Mac n’est pas connecté à Apple.", "Este Mac no tiene la sesión iniciada en Apple.", "Dieser Mac ist nicht bei Apple angemeldet.")
        case "session-ended":
            return tr("Apple ended the session: sign in again.", "Apple a fermé la session : connectez-vous de nouveau.", "Apple cerró la sesión: vuelve a iniciarla.", "Apple hat die Sitzung beendet: Melde dich erneut an.")
        case "wrong-password":
            return tr("Wrong password.", "Mot de passe incorrect.", "Contraseña incorrecta.", "Falsches Passwort.")
        case "wrong-code":
            return tr("Wrong code.", "Code incorrect.", "Código incorrecto.", "Falscher Code.")
        case "cancelled":
            return tr("Sign-in closed.", "Connexion fermée.", "Inicio de sesión cerrado.", "Anmeldung geschlossen.")
        case "account-refused":
            return tr("Apple refuses this account for now: appleid.apple.com says why.", "Apple refuse ce compte pour l’instant : appleid.apple.com dit pourquoi.",
                      "Apple rechaza esta cuenta por ahora: appleid.apple.com dice por qué.", "Apple lehnt dieses Konto vorerst ab: appleid.apple.com sagt, warum.")
        case "too-many-requests":
            return tr("Apple asks to wait before trying again.", "Apple demande d’attendre avant de réessayer.", "Apple pide esperar antes de volver a intentarlo.", "Apple bittet, vor einem neuen Versuch zu warten.")
        case "anisette":
            return tr("The server that introduces this Mac to Apple does not answer.", "Le serveur qui présente ce Mac à Apple ne répond pas.",
                      "El servidor que presenta este Mac a Apple no responde.", "Der Server, der diesen Mac bei Apple vorstellt, antwortet nicht.")
        case "apple":
            return tr("Apple refused the request.", "Apple a refusé la demande.", "Apple rechazó la solicitud.", "Apple hat die Anfrage abgelehnt.")
        case "network":
            return tr("Apple does not answer: check the Internet connection.", "Apple ne répond pas : vérifiez la connexion à Internet.",
                      "Apple no responde: comprueba la conexión a Internet.", "Apple antwortet nicht: Prüfe die Internetverbindung.")
        case "no-iphone":
            return tr("The iPhone is no longer plugged into this Mac nor on its Wi-Fi.", "L’iPhone n’est plus branché à ce Mac ni sur son Wi-Fi.",
                      "El iPhone ya no está conectado a este Mac ni en su Wi-Fi.", "Das iPhone ist weder an diesem Mac angeschlossen noch in seinem WLAN.")
        case "iphone-refused":
            return tr("Unlock the iPhone, and trust this Mac if it asks.", "Déverrouillez l’iPhone, et faites confiance à ce Mac s’il le demande.",
                      "Desbloquea el iPhone y confía en este Mac si lo pide.", "Entsperre das iPhone und vertraue diesem Mac, wenn es fragt.")
        case "no-cartouche":
            return tr("Cartouche is not on this iPhone.", "Cartouche n’est pas sur cet iPhone.", "Cartouche no está en este iPhone.", "Cartouche ist nicht auf diesem iPhone.")
        case "other-team":
            return tr("Installed with another Apple Account: this Mac leaves it alone.", "Installé avec un autre compte Apple : ce Mac n’y touche pas.",
                      "Instalado con otra cuenta de Apple: este Mac no lo toca.", "Mit einem anderen Apple Account installiert: Dieser Mac lässt es in Ruhe.")
        case "certificate-gone":
            return tr("Its certificate is no longer on your Apple Account: only an install over it opens it again.",
                      "Son certificat n’est plus sur votre compte Apple : seule une installation par-dessus le rouvre.",
                      "Su certificado ya no está en tu cuenta de Apple: solo una instalación encima lo vuelve a abrir.",
                      "Sein Zertifikat ist nicht mehr in deinem Apple Account: Nur eine Installation darüber öffnet es wieder.")
        case "no-app-ids":
            return tr("Your account used its 10 App IDs of the week: this Mac tries again later.", "Votre compte a pris ses 10 identifiants d’app de la semaine : ce Mac réessaie plus tard.",
                      "Tu cuenta usó sus 10 ID de app de la semana: este Mac lo intenta más tarde.", "Dein Konto hat seine 10 App-IDs der Woche verbraucht: Dieser Mac versucht es später.")
        case "no-certificate-left":
            return tr("Your Apple Account has as many certificates as Apple allows: revoke one you no longer use in the Cartouche Installer’s Certificates page.",
                      "Votre compte Apple a autant de certificats qu’Apple le permet : révoquez-en un qui ne sert plus dans la page Certificats de l’Installeur Cartouche.",
                      "Tu cuenta de Apple tiene tantos certificados como Apple permite: revoca uno que ya no uses en la página Certificados del Instalador de Cartouche.",
                      "Dein Apple Account hat so viele Zertifikate, wie Apple erlaubt: Widerrufe eines, das du nicht mehr nutzt, auf der Seite Zertifikate des Cartouche Installer.")
        case "download":
            return tr("The download of Cartouche from GitHub did not go through: check the Internet connection.",
                      "Le téléchargement de Cartouche depuis GitHub n’a pas abouti : vérifiez la connexion à Internet.",
                      "La descarga de Cartouche desde GitHub no se completó: comprueba la conexión a Internet.",
                      "Der Download von Cartouche von GitHub ist nicht durchgegangen: Prüfe die Internetverbindung.")
        case "profile-refused":
            return tr("The iPhone refused the new profile.", "L’iPhone a refusé le nouveau profil.", "El iPhone rechazó el nuevo perfil.", "Das iPhone hat das neue Profil abgelehnt.")
        case "iphone":
            return tr("The iPhone did not answer as expected.", "L’iPhone n’a pas répondu comme prévu.", "El iPhone no respondió como se esperaba.", "Das iPhone hat nicht wie erwartet geantwortet.")
        default:
            return tr("The renewal stopped (\(kind)).", "Le renouvellement s’est arrêté (\(kind)).", "La renovación se detuvo (\(kind)).", "Die Erneuerung wurde angehalten (\(kind)).")
        }
    }

    /// A copy whose certificate is gone: what Reinstall does, and when this
    /// Mac does it by itself.
    public static var needsInstall: String {
        tr("Reinstall puts the newest Cartouche over it, with its games and saves. This Mac does it by itself once it expires.",
           "Réinstaller met le dernier Cartouche par-dessus, avec ses jeux et ses sauvegardes. Ce Mac le fait de lui-même une fois qu’il a expiré.",
           "Reinstalar pone el Cartouche más reciente encima, con sus juegos y partidas guardadas. Este Mac lo hace solo una vez que caduca.",
           "Neu installieren legt das neueste Cartouche darüber, mit seinen Spielen und Spielständen. Dieser Mac macht es von selbst, sobald es abgelaufen ist.")
    }

    /// Where an install over Cartouche is: its step, and how much of it is
    /// done.
    public static func installing(_ progress: SignerProgress) -> String {
        let percent = Int((progress.fraction * 100).rounded(.down))
        // Its steps, never a kind of failure (builder/tests/test_signer.py).
        if progress.step == "download" {
            return tr("Installing again: downloading Cartouche, \(percent)%", "Réinstallation : téléchargement de Cartouche, \(percent) %",
                      "Reinstalando: descargando Cartouche, \(percent) %", "Neuinstallation: Cartouche wird geladen, \(percent) %")
        }
        if progress.step == "sign" {
            return tr("Installing again: signing with your Apple Account", "Réinstallation : signature avec votre compte Apple",
                      "Reinstalando: firmando con tu cuenta de Apple", "Neuinstallation: Signieren mit deinem Apple Account")
        }
        return tr("Installing again: installing on the iPhone, \(percent)%", "Réinstallation : installation sur l’iPhone, \(percent) %",
                  "Reinstalando: instalando en el iPhone, \(percent) %", "Neuinstallation: Installation auf dem iPhone, \(percent) %")
    }

    /// When this Mac reaches no iPhone.
    public static var noIphone: String {
        tr("No iPhone reached: plug it into this Mac, or turn on Wi-Fi sync for it in the Finder, for this Mac to renew Cartouche on it.",
           "Aucun iPhone atteint : branchez-le à ce Mac, ou activez sa synchronisation Wi-Fi dans le Finder, pour que ce Mac y renouvelle Cartouche.",
           "Ningún iPhone al alcance: conéctalo a este Mac, o activa su sincronización por Wi-Fi en el Finder, para que este Mac renueve Cartouche en él.",
           "Kein iPhone erreicht: Schließe es an diesen Mac an oder aktiviere seine WLAN-Synchronisierung im Finder, damit dieser Mac Cartouche darauf erneuert.")
    }

    /// Under the section: what a renewal does, and does not.
    public static var footnote: String {
        tr("A renewal installs nothing again: Cartouche keeps its games, its saves and its increased memory. An install over it, when its certificate is gone, keeps them too, and never revokes a certificate.",
           "Un renouvellement ne réinstalle rien : Cartouche garde ses jeux, ses sauvegardes et sa mémoire augmentée. Une installation par-dessus, quand son certificat n’est plus là, les garde aussi, et ne révoque jamais de certificat.",
           "Una renovación no reinstala nada: Cartouche conserva sus juegos, sus partidas guardadas y su memoria ampliada. Una instalación encima, cuando su certificado ya no está, también los conserva, y nunca revoca un certificado.",
           "Eine Erneuerung installiert nichts neu: Cartouche behält seine Spiele, seine Spielstände und seinen erweiterten Speicher. Eine Installation darüber, wenn sein Zertifikat weg ist, behält sie auch und widerruft nie ein Zertifikat.")
    }

    /// The notification that says a renewal waits for the password, Apple
    /// having ended the session, for a copy that EXPIRES then: discreet,
    /// at most once a day, and nothing opens by itself.
    public static func passwordNotice(expires: Date?, now: Date = Date()) -> (title: String, body: String) {
        let title = expires.map { $0 <= now } ?? false
            ? tr("Cartouche expired on your iPhone", "Cartouche a expiré sur votre iPhone", "Cartouche caducó en tu iPhone", "Cartouche ist auf deinem iPhone abgelaufen")
            : tr("Cartouche expires soon on your iPhone", "Cartouche expire bientôt sur votre iPhone", "Cartouche caduca pronto en tu iPhone", "Cartouche läuft bald auf deinem iPhone ab")
        return (title, tr("Apple ended this Mac’s session: sign in again on the iPhone page for this Mac to renew it.",
                          "Apple a fermé la session de ce Mac : connectez-vous de nouveau dans la page iPhone pour que ce Mac le renouvelle.",
                          "Apple cerró la sesión de este Mac: vuelve a iniciarla en la página iPhone para que este Mac lo renueve.",
                          "Apple hat die Sitzung dieses Mac beendet: Melde dich auf der iPhone-Seite erneut an, damit dieser Mac es erneuert."))
    }

    /// The notification that says only an install opens Cartouche again.
    public static var installNotice: (title: String, body: String) {
        (tr("Cartouche needs to be installed again", "Cartouche est à réinstaller", "Hay que reinstalar Cartouche", "Cartouche muss neu installiert werden"),
         tr("Its certificate is no longer on your Apple Account. Reinstall, on the iPhone page, keeps its games and saves; this Mac does it by itself once it expires.",
            "Son certificat n’est plus sur votre compte Apple. Réinstaller, dans la page iPhone, garde ses jeux et ses sauvegardes ; ce Mac le fait de lui-même une fois qu’il a expiré.",
            "Su certificado ya no está en tu cuenta de Apple. Reinstalar, en la página iPhone, conserva sus juegos y partidas guardadas; este Mac lo hace solo una vez que caduca.",
            "Sein Zertifikat ist nicht mehr in deinem Apple Account. Neu installieren auf der iPhone-Seite behält seine Spiele und Spielstände; dieser Mac macht es von selbst, sobald es abgelaufen ist."))
    }

    /// The notification that says this Mac installed Cartouche VERSION
    /// again by itself, and that it opens again.
    public static func reinstalledNotice(version: String) -> (title: String, body: String) {
        (tr("Cartouche opens again on your iPhone", "Cartouche s’ouvre de nouveau sur votre iPhone", "Cartouche vuelve a abrirse en tu iPhone",
            "Cartouche öffnet sich wieder auf deinem iPhone"),
         tr("This Mac installed Cartouche \(version) over it: its games and saves are kept.",
            "Ce Mac a installé Cartouche \(version) par-dessus : ses jeux et ses sauvegardes sont gardés.",
            "Este Mac instaló Cartouche \(version) encima: se conservan sus juegos y partidas guardadas.",
            "Dieser Mac hat Cartouche \(version) darüber installiert: Seine Spiele und Spielstände bleiben erhalten."))
    }

    /// Where Apple sent the code, or will.
    public static func codeLine(_ request: SignerCodeRequest) -> String {
        if request.bySms, let number = request.numbers.first(where: { $0.id == request.selectedNumber }) ?? request.numbers.first,
           let digits = number.lastTwoDigits {
            return tr("Type the code Apple sent by text message to the number ending in \(digits).",
                      "Saisissez le code qu’Apple a envoyé par SMS au numéro finissant par \(digits).",
                      "Escribe el código que Apple envió por SMS al número que termina en \(digits).",
                      "Gib den Code ein, den Apple per SMS an die Nummer mit der Endung \(digits) geschickt hat.")
        }
        return tr("Type the code your Apple devices show.", "Saisissez le code affiché sur vos appareils Apple.",
                  "Escribe el código que muestran tus dispositivos Apple.", "Gib den Code ein, den deine Apple-Geräte anzeigen.")
    }
}
