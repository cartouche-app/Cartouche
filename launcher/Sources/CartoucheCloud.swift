//
//  CartoucheCloud.swift
//  Cartouche
//
//  Cartouche Cloud, the service that builds a player's own game for the
//  iPhone on Macs it manages, for an account made on its site,
//  build.cartouche.cloud (decision 136): what Cartouche asks it, and what
//  it answers, as the service's API for the app says them (/api/app/…).
//
//  Cartouche is linked to the player's account by a code the account's
//  page gives, valid ten minutes, once: typed on the System page, or in the
//  link that page opens Cartouche with (cartouche://cloud/link?code=…). The
//  platform gives a token for it, which the device shows with each call
//  from then on, and which reads the account's games and fetches the IPA
//  of a game built, nothing more: sending a game, spending credits and the
//  account itself stay on the site. The token goes to the platform alone:
//  no cookie, no cache, and no redirection followed. The IPA comes straight
//  from the service's storage, at an address the platform gives for a
//  quarter of an hour and gives again for the rest of a longer download,
//  which carries no token.
//
//  The platform answers with codes and numbers, which Cartouche says in
//  its own words (CartoucheTextCloud.swift); the price of a build is never
//  written in the app, which reads it of the service.
//
//  The iPhone alone links to it: Cartouche Cloud builds games for players
//  without a Mac, and a Mac builds its own with Cartouche Builder.
//
//  Platform-independent: tested on its own by launcher/Package.swift,
//  against a stand-in for the platform (CartoucheCloudTests).
//

import Foundation

/// Where Cartouche Cloud is: its platform, the only place the device's
/// token goes, and the pages of its site that the app opens in Safari,
/// where the player signs in by e-mail.
enum CartoucheCloud {
    static let platform = URL(string: "https://build.cartouche.cloud")!
    /// Where an account is made, or signed in to: its address, then a code
    /// sent to it by e-mail.
    static let signInPage = URL(string: "https://build.cartouche.cloud/login")!
    /// The account's page, at Cartouche on your iPhone: the code that
    /// links Cartouche, the iPhones linked, Unlink.
    static let accountPage = URL(string: "https://build.cartouche.cloud/account#cartouche")!
    /// The account's games, where a game is sent from a computer.
    static let gamesPage = URL(string: "https://build.cartouche.cloud/games")!
    static let privacyPage = URL(string: "https://build.cartouche.cloud/privacy")!

    /// How many steps a build has, as the site draws them: the wait, the
    /// Mac getting ready, fetching the game, unpacking it, building it, and
    /// sending back the game built.
    static let trackSteps = 6

    /// The keychain service of the device's token (CartoucheCloudLink),
    /// which Reset Cartouche erases (CartoucheResetPlan).
    static let keychainService = "Cartouche Cloud"

    /// How long Cartouche waits before it asks the account's games again,
    /// in seconds, while the page of Cartouche Cloud shows: often while a
    /// game is on its way, so that its step moves; seldom otherwise; and a
    /// while after the platform did not answer.
    static func pause(busy: Bool, failed: Bool) -> UInt64 {
        failed ? 30 : busy ? 10 : 60
    }

    /// Cartouche coming forward asks the account's games once a minute at
    /// the most, so that a game built meanwhile shows in the library.
    static let forwardSeconds: TimeInterval = 60
}

// MARK: The code

/// The code that links Cartouche to an account: 8 capitals and digits,
/// without those that look alike, 0 and O, 1 and I, as the account's page
/// shows it in two groups of four, "ABCD-EFGH".
enum CartoucheCloudCode {
    static let letters = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    /// The code TEXT is, as the player typed or pasted it, in any case,
    /// with spaces and the dash between its groups or without: nil when it
    /// is not one, as the platform reads it.
    static func typed(_ text: String) -> String? {
        guard text.count <= 32 else { return nil }
        let code = String(text.uppercased().filter { !$0.isWhitespace && $0 != "-" })
        guard code.count == length, code.allSatisfy({ letters.contains($0) }) else { return nil }
        return code
    }

    /// What the code's field keeps of what the player types: the code's
    /// own letters, in capitals, eight at the most.
    static func entered(_ text: String) -> String {
        String(text.uppercased().filter { letters.contains($0) }.prefix(length))
    }

    /// As the account's page shows it.
    static func grouped(_ code: String) -> String {
        guard code.count == length else { return code }
        return String(code.prefix(4)) + "-" + String(code.suffix(4))
    }

    /// The code of a link the account's page opens Cartouche with, its
    /// button or its QR code: cartouche://cloud/link?code=ABCDEFGH. Nil for
    /// any other link, and for a code that is none.
    static func linked(_ url: URL) -> String? {
        guard !url.isFileURL, url.host?.lowercased() == "cloud", url.path == "/link",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let value = items.first(where: { $0.name == "code" })?.value else { return nil }
        return typed(value)
    }
}

// MARK: What the platform answers

/// Why no build starts now, whatever the queue holds: the service paused,
/// or a copy of the platform that builds nothing. A word this Cartouche
/// does not know reads as paused.
enum CartoucheCloudIdle: String, Codable, Equatable {
    case paused, unset

    init(from decoder: Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        self = CartoucheCloudIdle(rawValue: word) ?? .paused
    }
}

/// What the service says to anyone who asks, linked or not: how one gets
/// an account, why no build starts now, and the price of a build.
struct CartoucheCloudService: Codable, Equatable {
    /// Whether anyone may make an account, or only those invited: a word
    /// this Cartouche does not know reads as an invitation.
    enum Signup: String, Codable, Equatable {
        case open, invitation

        init(from decoder: Decoder) throws {
            let word = try decoder.singleValueContainer().decode(String.self)
            self = Signup(rawValue: word) ?? .invitation
        }
    }

    var signup: Signup
    var idle: CartoucheCloudIdle?
    /// In cents of a dollar.
    var price: Int
}

/// A game of the account, as the site's games page shows it.
struct CartoucheCloudGame: Codable, Hashable, Identifiable {
    enum State: String, Codable, Hashable {
        /// On its way from the player's computer.
        case open
        /// In the queue, or waiting for the account's game being built.
        case queued
        case building
        /// Its IPA is there to fetch, until the game expires.
        case built
        case failed
        /// A state this Cartouche does not know.
        case other

        init(from decoder: Decoder) throws {
            let word = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: word) ?? .other
        }
    }

    /// The platform's name of it, 32 hexadecimal digits.
    let id: String
    /// Its title ID.
    let title: String
    let name: String
    let state: State
    /// What its build costs, in cents of a dollar.
    let price: Int
    /// When the service deletes it: the IPA built, two days after its
    /// build, or what was sent.
    let expiresAt: Date

    /// In the queue or being built: the step of its build, from 0
    /// (CartoucheCloud.trackSteps), and how long a build of the game
    /// usually takes, in seconds, when the service knows.
    var stage: Int? = nil
    var usual: Int? = nil
    /// In the queue: waiting for the account's game being built, which
    /// says nothing of its place; else its place, 1 for the next.
    var behind: Bool? = nil
    var place: Int? = nil
    /// Being built: the Mac's step, in the platform's words, and since when.
    var step: String? = nil
    var launchedAt: Date? = nil
    /// Built: its IPA's size, its name, and when.
    var bytes: UInt64? = nil
    var file: String? = nil
    var builtAt: Date? = nil
    /// Failed: why (cause.* of the site), what is left to its player
    /// ("again", "mended", "held", "over"), and until when it may be built
    /// again from the site.
    var cause: String? = nil
    var left: String? = nil
    var until: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, name, state, price, stage, usual, behind, place, step, bytes, file, cause, left, until
        case expiresAt = "expires_at"
        case launchedAt = "launched_at"
        case builtAt = "built_at"
    }

    /// Its title ID as the catalogue writes them.
    var titleId: String { title.uppercased() }

    /// Whether its IPA is there to fetch at NOW.
    func isBuilt(at now: Date = Date()) -> Bool {
        state == .built && expiresAt > now && (bytes ?? 0) > 0
    }

    /// Whether its IPA is there to fetch at NOW, and its title is none of
    /// INSTALLED, the title IDs of the games on this iPhone: Install.
    func isToInstall(at now: Date = Date(), installed: Set<String>) -> Bool {
        isBuilt(at: now) && !installed.contains(titleId)
    }

    /// Whether it is on its way, in the queue or being built: the page
    /// asks of it more often.
    var isUnderWay: Bool {
        state == .open || state == .queued || state == .building
    }

    /// Being built, how long it has left at NOW, as the site says it: a
    /// build of the game usually takes USUAL seconds from its launch; nil
    /// when the service does not know, or once that time is past.
    func timeLeft(at now: Date = Date()) -> TimeInterval? {
        guard state == .building, let usual, let launchedAt else { return nil }
        let left = TimeInterval(usual) - now.timeIntervalSince(launchedAt)
        return left > 0 ? left : nil
    }
}

/// The account's credits, in cents of a dollar: its balance, what its
/// games under way hold of it, what is left to send others, and the price
/// of a build.
struct CartoucheCloudCredits: Codable, Equatable {
    var balance: Int
    var held: Int
    var available: Int
    var price: Int
}

/// What a linked device reads of its account.
struct CartoucheCloudAccount: Codable, Equatable {
    /// The latest first.
    var games: [CartoucheCloudGame]
    var credits: CartoucheCloudCredits
    var idle: CartoucheCloudIdle?

    /// Its games whose IPA is there to fetch at NOW, the latest built first.
    func built(at now: Date = Date()) -> [CartoucheCloudGame] {
        games.filter { $0.isBuilt(at: now) }
            .sorted { ($0.builtAt ?? .distantPast) > ($1.builtAt ?? .distantPast) }
    }

    var isBusy: Bool { games.contains(where: \.isUnderWay) }

    /// What the library offers to install at NOW: of each title, the game
    /// built last whose IPA is there to fetch, the latest built first; none
    /// of a title in INSTALLED, the title IDs of the games on this iPhone
    /// (CartoucheCatalog.installedTitles), which is installed already.
    func toInstall(at now: Date = Date(), installed: Set<String> = []) -> [CartoucheCloudGame] {
        var titles = installed
        return built(at: now).filter { titles.insert($0.titleId).inserted }
    }
}

/// The platform's answer to a code: the device's name there, and its token,
/// given this once.
struct CartoucheCloudLinked: Decodable, Equatable {
    let device: String
    let token: String
}

/// Where the IPA of a game built is fetched, until when, and what it is.
struct CartoucheCloudDownload: Decodable, Equatable {
    let url: URL
    let expiresAt: Date
    let bytes: UInt64
    let file: String

    enum CodingKeys: String, CodingKey {
        case url, bytes, file
        case expiresAt = "expires_at"
    }
}

/// The platform's answer to Unlink.
private struct CartoucheCloudDone: Decodable {
    let ok: Bool
}

// MARK: What went wrong

/// Why a call to Cartouche Cloud did not go through, as the platform said
/// it, or as the network did; its words are the app's
/// (CartoucheTextCloud.swift).
struct CartoucheCloudError: Error, Equatable, CartoucheDescribedError {
    enum Kind: String, Equatable {
        /// The token links nothing any more: the device was unlinked on the
        /// site, the account deleted, or the device unseen for 90 days.
        case unlinked
        /// A code wrong, too old or taken already: the platform says no
        /// more of it.
        case code
        /// The account has as many devices linked as it can.
        case full
        /// The game is not the account's, or its IPA is gone.
        case missing
        /// This copy of the platform has no storage to fetch a game from.
        case storage
        /// The storage refused the IPA's address: past its quarter of an
        /// hour.
        case expired
        /// The iPhone is offline.
        case offline
        /// The platform could not be reached, or the connection broke.
        case network
        /// Any other answer, or one Cartouche cannot read.
        case server
    }

    let kind: Kind
    /// The HTTP status of the answer, if one came.
    var status: Int? = nil
    /// The network's error code (URLError), if none came.
    var network: Int? = nil

    init(_ kind: Kind, status: Int? = nil, network: Int? = nil) {
        self.kind = kind
        self.status = status
        self.network = network
    }

    var failureKind: String { kind.rawValue }
    var failureCause: CartoucheFailure.Cause {
        switch kind {
        case .offline: return .offline
        case .network: return .network
        default: return .serverStatus
        }
    }
    var underlyingError: Error? { nil }
}

// MARK: The calls

/// What Cartouche asks Cartouche Cloud: JSON to its API for the app, the
/// device's token in Authorization with every call but the one that links
/// it, which shows the code, and the one anyone may ask.
final class CartoucheCloudClient: @unchecked Sendable {
    let platform: URL
    let session: URLSession

    /// PLATFORM: the service's, or the tests' stand-in. SESSION: one of
    /// makeSession's.
    init(platform: URL = CartoucheCloud.platform, session: URLSession = CartoucheCloudClient.makeSession()) {
        self.platform = platform
        self.session = session
    }

    /// A session of its own: no cookie, no cache, no redirection followed,
    /// so that the token goes to the platform alone.
    static func makeSession(_ configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: CartoucheCloudNoRedirection(), delegateQueue: nil)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// How one gets an account, why no build starts, and the price of a
    /// build: asked without a token.
    func service() async throws -> CartoucheCloudService {
        try await call("GET", "service")
    }

    /// Links this iPhone with CODE, as typed (CartoucheCloudCode.typed).
    func link(code: String) async throws -> CartoucheCloudLinked {
        try await call("POST", "link", body: ["code": code])
    }

    /// The account's games, its credits, and why no build starts.
    func account(token: String) async throws -> CartoucheCloudAccount {
        try await call("GET", "games", token: token)
    }

    /// The address of GAME's IPA, for a quarter of an hour; AGAIN, to go on
    /// with a download already begun, which the platform does not count a
    /// second time.
    func download(_ game: String, again: Bool = false, token: String) async throws -> CartoucheCloudDownload {
        try await call("POST", "ipa", token: token, body: again ? ["id": game, "again": true] : ["id": game])
    }

    /// The device is linked no more.
    func unlink(token: String) async throws {
        let _: CartoucheCloudDone = try await call("POST", "unlink", token: token, body: [:])
    }

    /// GAME's IPA, built, opened for an install read where it sits: its
    /// address asked of the platform with TOKEN, and asked again as it
    /// expires. AGAIN: to go on with a download already begun.
    func openIPA(_ game: String, again: Bool = false, token: String) async throws -> CartoucheResumingSource.Opened {
        let first = try await download(game, again: again, token: token)
        let source = CartoucheCloudIPA(first, session: session) { [self] in
            try await download(game, again: true, token: token)
        }
        return CartoucheResumingSource.Opened(source: source, close: {})
    }

    /// GAME's IPA, as an install reads it: opened, then opened again after
    /// a read that failed, and read on from where it stopped
    /// (CartoucheResumingSource), as the one download the platform counted
    /// the first time.
    func ipa(_ game: String, token: String,
             pauses: [UInt64] = CartoucheResumingSource.defaultPauses) async throws -> CartoucheResumingSource {
        let begun = CartoucheFlag()
        return try await CartoucheResumingSource.open(pauses: pauses) { [self] in
            let again = begun.isRaised
            begun.raise()
            return try await openIPA(game, again: again, token: token)
        }
    }

    private func call<Answer: Decodable>(_ method: String, _ path: String, token: String? = nil,
                                         body: [String: Any]? = nil) async throws -> Answer {
        var request = URLRequest(url: platform.appendingPathComponent("api/app/" + path),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let (data, response) = try await Self.send(request, on: session)
        guard response.statusCode == 200 else { throw Self.refusal(response.statusCode, data) }
        do {
            return try Self.decoder.decode(Answer.self, from: data)
        } catch {
            throw CartoucheCloudError(.server, status: response.statusCode)
        }
    }

    /// Why the platform said no, by its status and its { error }.
    static func refusal(_ status: Int, _ data: Data) -> CartoucheCloudError {
        let said = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch status {
        case 401: return CartoucheCloudError(.unlinked, status: status)
        case 409: return CartoucheCloudError(.full, status: status)
        case 422: return CartoucheCloudError(.code, status: status)
        case 404: return CartoucheCloudError(.missing, status: status)
        case 503 where said == "storage": return CartoucheCloudError(.storage, status: status)
        default: return CartoucheCloudError(.server, status: status)
        }
    }

    /// REQUEST's answer, or why none came: the network's error as one of
    /// Cartouche Cloud's, a cancelled request as a cancellation.
    static func send(_ request: URLRequest, on session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CartoucheCloudError(.server) }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                throw CartoucheCloudError(.offline, network: error.code.rawValue)
            default:
                throw CartoucheCloudError(.network, network: error.code.rawValue)
            }
        }
    }
}

/// Follows no redirection: the token goes to the platform alone, and an
/// IPA's address is the storage's own.
private final class CartoucheCloudNoRedirection: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: Reading an IPA

/// The IPA of a game built, read where the service keeps it, a part at a
/// time with Range (CartoucheReadAhead), with no token: its address lasts a
/// quarter of an hour, and a download that takes longer asks the platform
/// for another, a minute before it expires, or once the storage refuses
/// it.
final class CartoucheCloudIPA: CartoucheByteSource {
    /// How long before its end an address is given up for a new one.
    static let margin: TimeInterval = 60

    let size: UInt64
    private var address: CartoucheCloudDownload
    private let session: URLSession
    private let renew: () async throws -> CartoucheCloudDownload
    private var parts: CartoucheReadAhead!
    /// How many addresses the platform gave after the first.
    private(set) var renewed = 0

    init(_ first: CartoucheCloudDownload, session: URLSession,
         renew: @escaping () async throws -> CartoucheCloudDownload) {
        size = first.bytes
        address = first
        self.session = session
        self.renew = renew
        parts = CartoucheReadAhead(size: first.bytes) { [unowned self] offset, count in
            try await self.fetch(at: offset, count: count)
        }
    }

    func read(at offset: UInt64, count: Int) async throws -> Data {
        try await parts.read(at: offset, count: count)
    }

    private func fetch(at offset: UInt64, count: Int) async throws -> Data {
        if address.expiresAt.timeIntervalSinceNow < Self.margin {
            try await renewAddress()
        }
        do {
            return try await get(at: offset, count: count)
        } catch let refused as CartoucheCloudError where refused.kind == .expired {
            try await renewAddress()
            return try await get(at: offset, count: count)
        }
    }

    private func renewAddress() async throws {
        let next = try await renew()
        // Another IPA in its place: the archive cannot go on from here.
        guard next.bytes == size else { throw CartoucheResumingSource.Changed(size: size, now: next.bytes) }
        address = next
        renewed += 1
    }

    private func get(at offset: UInt64, count: Int) async throws -> Data {
        var request = URLRequest(url: address.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("bytes=\(offset)-\(offset + UInt64(max(count, 1)) - 1)", forHTTPHeaderField: "Range")
        // The bytes as they are kept, for the ranges to fall right.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await CartoucheCloudClient.send(request, on: session)
        switch response.statusCode {
        case 206:
            return data
        case 200:
            // The whole file, from a storage that took no range.
            let start = Int(offset)
            guard start < data.count else { return Data() }
            return data.subdata(in: start ..< min(data.count, start + count))
        case 400, 401, 403:
            throw CartoucheCloudError(.expired, status: response.statusCode)
        case 404:
            throw CartoucheCloudError(.missing, status: response.statusCode)
        default:
            throw CartoucheCloudError(.server, status: response.statusCode)
        }
    }
}
