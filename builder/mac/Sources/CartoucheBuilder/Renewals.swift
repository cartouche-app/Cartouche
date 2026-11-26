//
//  Renewals.swift
//  Cartouche Builder
//
//  Cartouche renewed on the iPhones this Mac reaches, by the cable or on
//  its Wi-Fi, with the app's helper cartouche-signer (decision 165). Once
//  the player signed in here, the app looks at them every half hour, and
//  renews the copy its Apple session's team signed in Cartouche's last two
//  days or once it expired, never earlier unless the player asks
//  (SignerPlan); before, it reads them only for the iPhone page. The password is
//  typed on the iPhone page alone, goes to the helper's input and to
//  Apple, and is kept nowhere. It is asked again only once Apple ended the
//  session and a renewal is due: by a notification without a sound, at
//  most once a day, and nothing opens by itself. What came of each try is
//  kept in the app's settings, by iPhone and copy, never the helper's
//  message, which can name the account or the iPhone: that goes to a log
//  in the helper's folder, readable by the player's account only.
//

import BuilderKit
import CartoucheCore
import Foundation

/// Where the sign-in on the iPhone page is.
enum RenewalSignIn: Equatable {
    /// The account and its password to type.
    case form
    /// The helper is talking to Apple.
    case signingIn
    /// Apple asks for its code.
    case code(SignerCodeRequest)
}

@MainActor
final class RenewalController: ObservableObject {
    /// The helper; nil in a build without it, and in the gallery.
    let signer: Signer?
    let sample: Bool
    @Published private(set) var session: SignerSession?
    @Published private(set) var iphones: [SignerIphone] = []
    /// When the app last looked at the iPhones, and why it found none when
    /// the helper did not answer.
    @Published private(set) var looked: Date?
    @Published private(set) var lookFailure: SignerFailure?
    /// The copies being renewed now (key(_:_:)).
    @Published private(set) var working: Set<String> = []
    /// What came of the last try for each copy.
    @Published private(set) var attempts: [String: SignerAttempt] = [:]
    /// The step of the sign-in, while the page shows it.
    @Published var step: RenewalSignIn?
    @Published private(set) var signInFailure: String?
    weak var model: AppModel?
    private var loop: Task<Void, Never>?
    private var looking = false
    private var code: CheckedContinuation<SignerCodeAnswer, Never>?

    static let attemptsKey = "renewalAttempts"
    /// When a notification last asked for the password.
    static let askedKey = "renewalAsked"
    /// The copies a notification said only an install opens again, by
    /// key and expiry: told once each.
    static let toldInstallKey = "renewalToldInstall"

    init(home: BuilderHome, sample: Bool) {
        self.sample = sample
        signer = sample ? nil : Signer.bundled(home: home)
        if !sample {
            attempts = UserDefaults.standard.data(forKey: Self.attemptsKey)
                .flatMap { try? Self.decoder.decode([String: SignerAttempt].self, from: $0) } ?? [:]
        }
    }

    /// Whether the page shows the section: the app carries the helper.
    var available: Bool { signer != nil || sample }
    var signedIn: Bool { session?.signedIn == true }

    /// Whether Apple ended the session: only the password signs in again.
    var sessionEnded: Bool {
        signedIn && SignerPlan.sessionEnded(since: session?.since, attempts: Array(attempts.values))
    }

    static func key(_ udid: String, _ bundleId: String) -> String { udid + "|" + bundleId }

    func last(_ iphone: SignerIphone, _ copy: SignerCartouche) -> SignerAttempt? {
        attempts[Self.key(iphone.udid, copy.bundleId)]
    }

    func isWorking(_ iphone: SignerIphone, _ copy: SignerCartouche) -> Bool {
        working.contains(Self.key(iphone.udid, copy.bundleId))
    }

    func plan(_ iphone: SignerIphone, _ copy: SignerCartouche, now: Date = Date()) -> SignerPlan {
        SignerPlan.next(for: copy, signedIn: signedIn, since: session?.since, team: session?.teamId, last: last(iphone, copy), now: now)
    }

    // MARK: Looking

    /// From the app's start: a first look a little after, then every half
    /// hour, renewing what is due.
    func attach(model: AppModel) {
        self.model = model
        guard signer != nil, loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            while !Task.isCancelled {
                await self?.look(renewing: true)
                try? await Task.sleep(nanoseconds: UInt64(SignerPlan.lookEvery * 1_000_000_000))
            }
        }
    }

    /// Reads the session and the iPhones; RENEWING, acts on each copy as
    /// its plan says. The page looks without renewing when it shows.
    func look(renewing: Bool) async {
        guard let signer, !looking else { return }
        looking = true
        defer { looking = false }
        do {
            session = try await signer.session()
            // A player who has not signed in here: nothing to renew, and
            // the iPhones are read for the page alone, when it shows.
            if renewing, session?.signedIn != true { return }
            iphones = try await signer.devices()
            lookFailure = nil
        } catch {
            lookFailure = error as? SignerFailure ?? SignerFailure(kind: "internal", stage: "iphone", message: "\(error)")
            iphones = []
            note(lookFailure!)
        }
        looked = Date()
        guard renewing else { return }
        for iphone in iphones {
            for copy in iphone.cartouche {
                switch plan(iphone, copy) {
                case .renew: await renew(iphone, copy, asked: false)
                case .askPassword: askPassword(for: copy)
                case .needsInstall: tellInstall(iphone, copy)
                case .wait, .otherTeam: break
                }
            }
        }
    }

    // MARK: Renewing

    /// Renews COPY on IPHONE: due, or whenever the player ASKED.
    func renew(_ iphone: SignerIphone, _ copy: SignerCartouche, asked: Bool) async {
        guard let signer else { return }
        let key = Self.key(iphone.udid, copy.bundleId)
        guard !working.contains(key) else { return }
        working.insert(key)
        defer { working.remove(key) }
        do {
            let renewal = try await signer.renew(udid: iphone.udid, onlyIfDue: !asked)
            guard renewal.renewed else { return }
            keep(SignerAttempt(at: Date(), kind: nil, expires: renewal.expires), for: key)
            model?.telemetry.event("builder.renewed", fields: SignerMeasures.renewed(renewal, asked: asked))
        } catch {
            let failure = error as? SignerFailure ?? SignerFailure(kind: "internal", stage: "session", message: "\(error)")
            keep(SignerAttempt(at: Date(), kind: failure.kind, expires: copy.expires), for: key)
            model?.telemetry.event("builder.renewFailed", fields: SignerMeasures.failed(failure, copy: copy, asked: asked))
            note(failure)
        }
        // Until when it opens now, as the iPhone says.
        if let found = try? await signer.devices() { iphones = found }
    }

    private func keep(_ attempt: SignerAttempt, for key: String) {
        attempts[key] = attempt
        guard !sample else { return }
        UserDefaults.standard.set(try? Self.encoder.encode(attempts), forKey: Self.attemptsKey)
    }

    // MARK: Notifications

    /// A renewal due that only the password lets through, Apple having
    /// ended the session: said at most once a day, without a sound.
    private func askPassword(for copy: SignerCartouche) {
        guard let model, SignerPlan.notifiesPassword(.askPassword, signedIn: signedIn, ended: sessionEnded) else { return }
        let asked = UserDefaults.standard.object(forKey: Self.askedKey) as? Date
        guard SignerPlan.mayAsk(asked: asked) else { return }
        UserDefaults.standard.set(Date(), forKey: Self.askedKey)
        let notice = SignerWords.passwordNotice(expires: copy.expires)
        model.notify(title: notice.title, body: notice.body, section: .iphone, sound: false)
    }

    /// Only an install opens COPY again: said once for it.
    private func tellInstall(_ iphone: SignerIphone, _ copy: SignerCartouche) {
        guard let model else { return }
        let told = Self.key(iphone.udid, copy.bundleId) + "|" + (copy.expires.map { String(Int($0.timeIntervalSince1970)) } ?? "")
        var all = UserDefaults.standard.stringArray(forKey: Self.toldInstallKey) ?? []
        guard !all.contains(told) else { return }
        all = Array((all + [told]).suffix(20))
        UserDefaults.standard.set(all, forKey: Self.toldInstallKey)
        let notice = SignerWords.installNotice
        model.notify(title: notice.title, body: notice.body, section: .iphone, sound: false)
    }

    // MARK: Signing in

    /// Signs in with EMAIL and PASSWORD, which go to the helper's input
    /// and nowhere else; the code, when Apple asks, from the page.
    func signIn(email: String, password: String) {
        guard let signer, step != .signingIn else { return }
        signInFailure = nil
        step = .signingIn
        let started = Date()
        Task {
            do {
                session = try await signer.signIn(email: email, password: password) { [weak self] request in
                    await self?.askCode(request) ?? .cancel
                }
                step = nil
                model?.telemetry.event("builder.appleSignIn", fields: SignerMeasures.signIn(result: "signed-in", seconds: Date().timeIntervalSince(started)))
                // A renewal due goes at once.
                await look(renewing: true)
            } catch {
                let failure = error as? SignerFailure ?? SignerFailure(kind: "internal", stage: "session", message: "\(error)")
                code = nil
                step = failure.kind == "cancelled" ? nil : .form
                signInFailure = failure.kind == "cancelled" ? nil : SignerWords.failure(kind: failure.kind)
                model?.telemetry.event("builder.appleSignIn", fields: SignerMeasures.signIn(result: failure.kind, seconds: Date().timeIntervalSince(started)))
                note(failure)
            }
        }
    }

    private func askCode(_ request: SignerCodeRequest) async -> SignerCodeAnswer {
        step = .code(request)
        return await withCheckedContinuation { continuation in code = continuation }
    }

    /// The player's answer to Apple's code.
    func answer(_ answer: SignerCodeAnswer) {
        guard let code else { return }
        self.code = nil
        step = .signingIn
        code.resume(returning: answer)
    }

    /// Closes the form; a sign-in asking for its code is cancelled.
    func closeSignIn() {
        if code != nil {
            answer(.cancel)
        } else if step != .signingIn {
            step = nil
        }
        signInFailure = nil
    }

    func signOut() {
        guard let signer else { return }
        Task {
            do {
                session = try await signer.signOut()
            } catch {
                note(error as? SignerFailure ?? SignerFailure(kind: "internal", stage: "session", message: "\(error)"))
            }
        }
    }

    // MARK: The log

    /// The helper's message, which can name the account or the iPhone: in
    /// its folder only, readable by the player's account, the last lines.
    private func note(_ failure: SignerFailure) {
        guard let signer else { return }
        let url = signer.folder.appendingPathComponent("renewals.log")
        let line = ISO8601DateFormatter().string(from: Date()) + " " + failure.kind + " " + failure.stage + (failure.code.map { " \($0)" } ?? "") + ": " + failure.message
        let kept = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").suffix(199).map(String.init)
        try? FileManager.default.createDirectory(at: signer.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try? (kept + [line]).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: The gallery

    /// Shows a sample session, iPhones and what came of their tries.
    func preview(session: SignerSession?, iphones: [SignerIphone], attempts: [String: SignerAttempt] = [:],
                 signIn: RenewalSignIn? = nil, failure: String? = nil) {
        guard sample else { return }
        self.session = session
        self.iphones = iphones
        self.attempts = attempts
        step = signIn
        signInFailure = failure
        looked = Date()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
