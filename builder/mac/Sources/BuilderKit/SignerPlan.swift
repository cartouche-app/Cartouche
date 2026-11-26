//
//  SignerPlan.swift
//  Cartouche Builder
//
//  When the app has cartouche-signer renew Cartouche on an iPhone it
//  reaches, and what it says when it cannot (decision 165): in Cartouche's
//  last two days, or once it has expired, never earlier unless the player
//  asks; six hours after a try that failed, an hour after one that found
//  the iPhone away or locked; and the password only once Apple has ended
//  the session, by a notification at most once a day, never a window.
//  What a renewal measures, too: never the account, the team, the iPhone's
//  name or its identifier.
//

import Foundation

/// What came of the last renewal tried for a copy of Cartouche on an
/// iPhone: its kind of failure, nil for a renewal, at AT, for the copy that
/// expired at EXPIRES then.
public struct SignerAttempt: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: String?
    public var expires: Date?

    public init(at: Date, kind: String?, expires: Date?) {
        self.at = at
        self.kind = kind
        self.expires = expires
    }

    public var failed: Bool { kind != nil }
}

/// What the app does next for a copy of Cartouche on an iPhone.
public enum SignerPlan: Equatable, Sendable {
    /// Nothing before this date: Cartouche opens longer than two days, or
    /// the last try failed a little while ago.
    case wait(until: Date)
    /// Renew it now.
    case renew
    /// A renewal is due, and only the password signs in again: say so,
    /// discreetly.
    case askPassword
    /// Only an install over Cartouche opens it again: its certificate is
    /// gone from the account.
    case needsInstall
    /// Another Apple Account installed it: the Mac leaves it alone.
    case otherTeam

    /// How long after a failed try the next one comes.
    public static let retry: TimeInterval = 6 * 3_600
    /// How long after a try that found the iPhone away, locked or not
    /// trusting this Mac: it may be back sooner, and is looked for again.
    public static let retryIphone: TimeInterval = 3_600
    /// How often the app looks at the iPhones it reaches.
    public static let lookEvery: TimeInterval = 30 * 60
    /// How long between two notifications that ask for the password.
    public static let askEvery: TimeInterval = 24 * 3_600

    /// The plan for COPY, the session signed in or not, since SINCE, with
    /// TEAM's account, after LAST. A copy another team signed is left
    /// alone. A failure counts only for the copy it was tried for: once
    /// Cartouche opens until another date, renewed or installed again
    /// elsewhere, it no longer holds; nor does an ended session once the
    /// player signed in again.
    public static func next(for copy: SignerCartouche, signedIn: Bool, since: Date? = nil, team: String? = nil, last: SignerAttempt?,
                            now: Date = Date()) -> SignerPlan {
        if signedIn, let team, let copyTeam = copy.teamId, copyTeam != team { return .otherTeam }
        if copy.due == "not-yet" {
            return .wait(until: copy.from ?? now.addingTimeInterval(lookEvery))
        }
        let failure = last.flatMap { attempt -> (kind: String, at: Date)? in
            guard let kind = attempt.kind, attempt.expires == copy.expires else { return nil }
            return (kind, attempt.at)
        }
        if let failure {
            let kind = SignerFailure(kind: failure.kind, stage: "", message: "")
            if kind.needsInstall { return failure.kind == "other-team" ? .otherTeam : .needsInstall }
            if kind.needsPassword {
                guard signedIn, let since, since > failure.at else { return .askPassword }
                return .renew
            }
            if !signedIn { return .askPassword }
            let after = kind.iphoneAway ? retryIphone : retry
            if now < failure.at.addingTimeInterval(after) { return .wait(until: failure.at.addingTimeInterval(after)) }
        }
        return signedIn ? .renew : .askPassword
    }

    /// Whether a notification that asks for the password may go now, the
    /// last one gone at ASKED.
    public static func mayAsk(asked: Date?, now: Date = Date()) -> Bool {
        asked.map { now.timeIntervalSince($0) >= askEvery } ?? true
    }

    /// Whether Apple ended the session signed in at SINCE: a try after it
    /// that only the password would have let through.
    public static func sessionEnded(since: Date?, attempts: [SignerAttempt]) -> Bool {
        attempts.contains { attempt in
            guard let kind = attempt.kind, SignerFailure(kind: kind, stage: "", message: "").needsPassword else { return false }
            return since.map { attempt.at > $0 } ?? true
        }
    }

    /// Whether a notification says that PLAN waits for the password: only
    /// for a player who signed in on this Mac and whose session Apple
    /// ENDED, never for one who never signed in here or signed out. They
    /// read it on the iPhone page, and nothing opens by itself.
    public static func notifiesPassword(_ plan: SignerPlan, signedIn: Bool, ended: Bool) -> Bool {
        plan == .askPassword && signedIn && ended
    }
}

/// What a renewal and its failures measure (builder.renewed,
/// builder.renewFailed): the helper's kind and stage, how the iPhone was
/// reached, whether the player asked, and the days Cartouche had left.
public enum SignerMeasures {
    /// Whole days from NOW to EXPIRES, 0 on the last day, negative once
    /// expired.
    public static func daysLeft(_ expires: Date?, now: Date = Date()) -> Int? {
        expires.map { Int(floor($0.timeIntervalSince(now) / 86_400)) }
    }

    public static func renewed(_ renewal: SignerRenewal, asked: Bool, now: Date = Date()) -> [String: TelemetryValue] {
        var fields: [String: TelemetryValue] = [
            "asked": .flag(asked),
            "due": .text(renewal.due),
            "link": .text(renewal.link),
            "recorded": .flag(renewal.recorded),
            "refreshedSession": .flag(renewal.refreshedSession),
            "registeredAppId": .flag(renewal.registeredAppId),
            "seconds": .number((renewal.seconds * 10).rounded() / 10),
        ]
        if let days = daysLeft(renewal.before, now: now) { fields["daysLeft"] = .count(days) }
        if let days = daysLeft(renewal.expires, now: now) { fields["daysGiven"] = .count(days) }
        return fields
    }

    public static func failed(_ failure: SignerFailure, copy: SignerCartouche?, asked: Bool, now: Date = Date()) -> [String: TelemetryValue] {
        var fields: [String: TelemetryValue] = [
            "asked": .flag(asked),
            "kind": .text(failure.kind),
            "stage": .text(failure.stage),
        ]
        // Apple's and the iPhone's codes are numbers, never a name.
        if let code = failure.code, (-1_000_000...1_000_000_000).contains(code) { fields["code"] = .count(code) }
        if let due = copy?.due { fields["due"] = .text(due) }
        if let days = daysLeft(copy?.expires, now: now) { fields["daysLeft"] = .count(days) }
        return fields
    }

    /// A sign-in on this Mac: "signed-in", or the kind that stopped it.
    public static func signIn(result: String, seconds: Double) -> [String: TelemetryValue] {
        ["result": .text(result), "seconds": .number(seconds.rounded())]
    }
}
