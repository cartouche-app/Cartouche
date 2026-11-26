//
//  Signer.swift
//  Cartouche Builder
//
//  cartouche-signer, the helper the app carries in Contents/Helpers, which
//  renews Cartouche on the player's iPhone with a new provisioning profile,
//  as SideStore does on the iPhone, without installing it again
//  (builder/mac/signer, decision 165). One command a run: its lines of JSON
//  on its output, its answer or its failure last. The app keeps no password:
//  at a sign-in it hands the password to the helper's input, which sends it
//  to Apple alone; the helper keeps the session Apple gives, in the
//  Builder's folder (BuilderHome.signer), readable by the player alone.
//

import Foundation

/// What stopped the helper: its kind, which says what to do, and where
/// ("session", "apple" or "iphone"). The message may name the account or
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
}

/// Apple asks for a code: on a trusted device, or by text message.
public struct SignerCodeRequest: Decodable, Equatable, Sendable {
    public struct Number: Decodable, Equatable, Sendable {
        public var id: Int
        public var number: String?
        public var lastTwoDigits: String?
    }

    public var bySms: Bool
    public var lastError: String?
    public var numbers: [Number]
    public var selectedNumber: Int?
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

    /// Runs one command, and decodes its answer.
    func command<T: Decodable>(_ arguments: [String]) async throws -> T {
        let result = try await Run.program(helper.path, baseArguments + arguments, timeout: Signer.timeout)
        if result.timedOut {
            throw SignerFailure(kind: "internal", stage: "session", message: "The signer took more than \(Int(Signer.timeout)) s")
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
