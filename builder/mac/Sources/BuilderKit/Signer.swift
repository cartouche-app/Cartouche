//
//  Signer.swift
//  Cartouche Builder
//
//  cartouche-signer, the helper the app carries in Contents/Helpers, which
//  renews Cartouche on the player's iPhone with a new provisioning profile,
//  as SideStore does on the iPhone, without installing it again
//  (builder/mac/signer, decision 165); or, its certificate gone, installs
//  the newest Cartouche over it for the same team, which keeps its games
//  and saves (reinstall). One command a run: its lines of JSON
//  on its output, its answer or its failure last. The app keeps no password:
//  at a sign-in it hands the password to the helper's input, which sends it
//  to Apple alone; the helper keeps the session Apple gives, in the
//  Builder's folder (BuilderHome.signer), readable by the player alone.
//

import Foundation

/// What stopped the helper: its kind, which says what to do, and where
/// ("session", "apple", "download" or "iphone"). The message may name the account or
/// the iPhone: it goes to the log and a report the player copies, never in
/// the measurements.
public struct SignerFailure: Error, Decodable, Equatable, Sendable {
    public var kind: String
    public var stage: String
    public var code: Int?
    public var message: String

    public init(kind: String, stage: String, code: Int? = nil, message: String) {
        self.kind = kind
        self.stage = stage
        self.code = code
        self.message = message
    }

    /// Apple ended the session: only the password signs in again.
    public var needsPassword: Bool { kind == "session-ended" || kind == "no-session" }
    /// Only an install over Cartouche opens it again: its certificate is
    /// gone, or another Apple Account installed it.
    public var needsInstall: Bool { kind == "certificate-gone" || kind == "other-team" }
    /// The iPhone is not here, or not ready: plugged in and unlocked, it
    /// may be later.
    public var iphoneAway: Bool { kind == "no-iphone" || kind == "iphone-refused" || kind == "iphone" }
}

/// The session the helper keeps, as the app shows it: never its tokens.
public struct SignerSession: Decodable, Equatable, Sendable {
    public var signedIn: Bool
    public var email: String?
    public var teamId: String?
    public var teamName: String?
    public var since: Date?
    public var refreshed: Date?

    public init(signedIn: Bool, email: String? = nil, teamId: String? = nil, teamName: String? = nil, since: Date? = nil, refreshed: Date? = nil) {
        self.signedIn = signedIn
        self.email = email
        self.teamId = teamId
        self.teamName = teamName
        self.since = since
        self.refreshed = refreshed
    }
}

/// A copy of Cartouche on an iPhone, and until when it opens.
public struct SignerCartouche: Decodable, Equatable, Sendable {
    public var bundleId: String
    public var version: String?
    public var teamId: String?
    public var expires: Date?
    /// "not-yet", "now" (its last two days) or "expired".
    public var due: String?
    /// When its last two days start, for "not-yet".
    public var from: Date?

    public init(bundleId: String, version: String? = nil, teamId: String? = nil, expires: Date? = nil, due: String? = nil, from: Date? = nil) {
        self.bundleId = bundleId
        self.version = version
        self.teamId = teamId
        self.expires = expires
        self.due = due
        self.from = from
    }
}

/// An iPhone this Mac reaches, by the cable ("usb") or on its Wi-Fi
/// ("network"), with the copies of Cartouche on it.
public struct SignerIphone: Decodable, Equatable, Sendable {
    public var udid: String
    public var name: String?
    public var ios: String?
    public var link: String
    public var cartouche: [SignerCartouche]
    public var error: SignerFailure?

    public init(udid: String, name: String? = nil, ios: String? = nil, link: String, cartouche: [SignerCartouche], error: SignerFailure? = nil) {
        self.udid = udid
        self.name = name
        self.ios = ios
        self.link = link
        self.cartouche = cartouche
        self.error = error
    }
}

/// What a renewal did.
public struct SignerRenewal: Decodable, Equatable, Sendable {
    public var renewed: Bool
    public var bundleId: String
    public var before: Date?
    public var expires: Date?
    public var due: String
    public var from: Date?
    /// Whether Cartouche's App ID had to be registered again, taking one of
    /// the ten of the week.
    public var registeredAppId: Bool
    /// Whether Apple gave the session a new token, without the password.
    public var refreshedSession: Bool
    /// Whether Cartouche's Documents have the renewal's date.
    public var recorded: Bool
    public var link: String
    public var seconds: Double

    public init(renewed: Bool, bundleId: String, before: Date? = nil, expires: Date? = nil, due: String, from: Date? = nil,
                registeredAppId: Bool = false, refreshedSession: Bool = false, recorded: Bool = true, link: String, seconds: Double) {
        self.renewed = renewed
        self.bundleId = bundleId
        self.before = before
        self.expires = expires
        self.due = due
        self.from = from
        self.registeredAppId = registeredAppId
        self.refreshedSession = refreshedSession
        self.recorded = recorded
        self.link = link
        self.seconds = seconds
    }
}

/// What an install over Cartouche did (reinstall): the newest version,
/// signed for the same team, over the same identifier.
public struct SignerReinstall: Decodable, Equatable, Sendable {
    public var reinstalled: Bool
    public var bundleId: String
    /// The version installed now, and the copy's before.
    public var version: String
    public var previousVersion: String?
    public var before: Date?
    public var expires: Date?
    public var due: String
    public var from: Date?
    public var refreshedSession: Bool
    public var link: String
    public var seconds: Double

    public init(reinstalled: Bool, bundleId: String, version: String, previousVersion: String? = nil, before: Date? = nil, expires: Date? = nil,
                due: String, from: Date? = nil, refreshedSession: Bool = false, link: String, seconds: Double) {
        self.reinstalled = reinstalled
        self.bundleId = bundleId
        self.version = version
        self.previousVersion = previousVersion
        self.before = before
        self.expires = expires
        self.due = due
        self.from = from
        self.refreshedSession = refreshedSession
        self.link = link
        self.seconds = seconds
    }

    /// Whether a newer version came with it.
    public var updated: Bool { previousVersion != version }
}

/// Where an install over Cartouche is: "download", "sign" or "install",
/// and the fraction of that step done, from 0 to 1.
public struct SignerProgress: Equatable, Sendable {
    public var step: String
    public var fraction: Double

    public init(step: String, fraction: Double) {
        self.step = step
        self.fraction = min(max(fraction, 0), 1)
    }

    /// The steps in their order, and the share of the whole each takes:
    /// the download of about 30 MB and the install, by the cable or on the
    /// Wi-Fi, take the longest.
    static let steps: [(name: String, share: Double)] = [("download", 0.4), ("sign", 0.2), ("install", 0.4)]

    /// How much of the whole install is done, from 0 to 1.
    public var overall: Double {
        var done = 0.0
        for (name, share) in SignerProgress.steps {
            if name == step { return done + share * fraction }
            done += share
        }
        return 0
    }

    /// The helper's progress line, {"event": "progress", "step", "fraction"};
    /// nil for any other.
    static func read(_ line: String) -> SignerProgress? {
        struct Event: Decodable { var event: String?; var step: String?; var fraction: Double? }
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)), event.event == "progress",
              let step = event.step, let fraction = event.fraction else { return nil }
        return SignerProgress(step: step, fraction: fraction)
    }
}

/// Apple asks for a code: on a trusted device, or by text message.
public struct SignerCodeRequest: Decodable, Equatable, Sendable {
    public struct Number: Decodable, Equatable, Sendable {
        public var id: Int
        public var number: String?
        public var lastTwoDigits: String?

        public init(id: Int, number: String? = nil, lastTwoDigits: String? = nil) {
            self.id = id
            self.number = number
            self.lastTwoDigits = lastTwoDigits
        }
    }

    public var bySms: Bool
    public var lastError: String?
    public var numbers: [Number]
    public var selectedNumber: Int?

    public init(bySms: Bool, lastError: String? = nil, numbers: [Number] = [], selectedNumber: Int? = nil) {
        self.bySms = bySms
        self.lastError = lastError
        self.numbers = numbers
        self.selectedNumber = selectedNumber
    }
}

/// The player's answer to a code request.
public enum SignerCodeAnswer: Equatable, Sendable {
    case code(String)
    case sms(Int)
    case devices
    case resend
    case cancel

    var line: [String: Any] {
        switch self {
        case .code(let code): return ["code": code]
        case .sms(let id): return ["sms": id]
        case .devices: return ["devices": true]
        case .resend: return ["resend": true]
        case .cancel: return ["cancel": true]
        }
    }
}

/// The helper's last line: its answer, or what stopped it.
private struct SignerEnvelope<T: Decodable>: Decodable {
    var result: T?
    var error: SignerFailure?
}

public final class Signer: Sendable {
    public let helper: URL
    public let folder: URL

    /// How long a command may take: a renewal, a few requests to Apple and
    /// to the iPhone.
    static let timeout: TimeInterval = 180
    /// How long an install over Cartouche may take: its download, about
    /// 30 MB, its signature, and its install, on the Wi-Fi too.
    static let installTimeout: TimeInterval = 20 * 60

    public init(helper: URL, folder: URL) {
        self.helper = helper
        self.folder = folder
    }

    /// The helper the app carries, with the Builder's folder; nil when this
    /// app has none (a build without it). CARTOUCHE_SIGNER names another.
    public static func bundled(home: BuilderHome = .default) -> Signer? {
        var candidates: [URL] = []
        if let forced = ProcessInfo.processInfo.environment["CARTOUCHE_SIGNER"], !forced.isEmpty {
            candidates.append(URL(fileURLWithPath: forced))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cartouche-signer"))
        guard let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return Signer(helper: helper, folder: home.signer)
    }

    var baseArguments: [String] { ["--folder", folder.path] }

    /// The iPhones this Mac reaches, each with its copies of Cartouche.
    public func devices() async throws -> [SignerIphone] {
        struct Answer: Decodable { var iphones: [SignerIphone] }
        let answer: Answer = try await command(["devices"])
        return answer.iphones
    }

    /// The session, from this Mac alone.
    public func session() async throws -> SignerSession {
        try await command(["session"])
    }

    public func signOut() async throws -> SignerSession {
        try await command(["sign-out"])
    }

    /// Renews Cartouche on the iPhone UDID: in its last two days or once
    /// expired with ONLYIFDUE, whenever without.
    public func renew(udid: String, onlyIfDue: Bool) async throws -> SignerRenewal {
        try await command(["renew", "--udid", udid] + (onlyIfDue ? ["--if-due"] : []))
    }

    /// Installs the newest Cartouche over the copy of the session's team on
    /// the iPhone UDID, as the Cartouche Installer updates it: for a copy
    /// whose certificate is gone. PROGRESS gets each step as it goes.
    public func reinstall(udid: String, progress: @escaping @Sendable (SignerProgress) -> Void) async throws -> SignerReinstall {
        try await command(["reinstall", "--udid", udid], timeout: Signer.installTimeout) { line in
            if let step = SignerProgress.read(line) { progress(step) }
        }
    }

    /// Runs one command, and decodes its answer; LINE gets each of its
    /// lines as it comes.
    func command<T: Decodable>(_ arguments: [String], timeout: TimeInterval = Signer.timeout,
                               line: (@Sendable (String) -> Void)? = nil) async throws -> T {
        let result = try await Run.program(helper.path, baseArguments + arguments, timeout: timeout, outputLine: line)
        if result.timedOut {
            throw SignerFailure(kind: "internal", stage: "session", message: "The signer took more than \(Int(timeout)) s")
        }
        return try Signer.answer(result.output, tail: result.tail())
    }

    /// The answer, or the failure, of the helper's last line.
    static func answer<T: Decodable>(_ output: Data, tail: String = "") throws -> T {
        let lines = output.split(separator: 10).filter { !$0.isEmpty }
        guard let last = lines.last else {
            throw SignerFailure(kind: "internal", stage: "session", message: "The signer said nothing. \(tail)")
        }
        return try decode(Data(last))
    }

    static func decode<T: Decodable>(_ line: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: SignerEnvelope<T>
        do {
            envelope = try decoder.decode(SignerEnvelope<T>.self, from: line)
        } catch {
            throw SignerFailure(kind: "internal", stage: "session", message: "The signer's answer does not read: \(error)")
        }
        if let failure = envelope.error { throw failure }
        guard let result = envelope.result else {
            throw SignerFailure(kind: "internal", stage: "session", message: "The signer gave no answer")
        }
        return result
    }

    /// Signs in with PASSWORD, and asks CODE when Apple wants a code. The
    /// password goes to the helper's input, and nowhere else.
    public func signIn(email: String, password: String,
                       code: @escaping @Sendable (SignerCodeRequest) async -> SignerCodeAnswer) async throws -> SignerSession {
        let process = Process()
        process.executableURL = helper
        process.arguments = baseArguments + ["sign-in", "--email", email]
        process.environment = Run.environment()
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        struct Event: Decodable { var event: String? }
        let decoder = JSONDecoder()
        for try await line in output.fileHandleForReading.bytes.lines {
            let data = Data(line.utf8)
            guard let event = (try? decoder.decode(Event.self, from: data))?.event else {
                return try Signer.decode(data)
            }
            switch event {
            case "password":
                try send(["password": password])
            case "code":
                let request = (try? decoder.decode(SignerCodeRequest.self, from: data))
                    ?? SignerCodeRequest(bySms: false, lastError: nil, numbers: [], selectedNumber: nil)
                try send(await code(request).line)
            default:
                continue
            }
        }
        throw SignerFailure(kind: "internal", stage: "session", message: "The signer ended without an answer")
    }
}
