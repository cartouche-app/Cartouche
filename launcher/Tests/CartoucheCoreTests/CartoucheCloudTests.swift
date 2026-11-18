import XCTest
@testable import CartoucheCore

/// Cartouche Cloud as the app reaches it (CartoucheCloud.swift), against a
/// stand-in for its platform in the test's own process: the app's API as
/// the platform answers it, its games in each state, a code valid ten
/// minutes, once, ten devices at most, and its storage, which serves an IPA
/// a part at a time at an address that lasts a quarter of an hour of the
/// stand-in's clock.
final class CartoucheCloudTests: XCTestCase {
    private var client: CartoucheCloudClient!

    override func setUp() {
        super.setUp()
        CartoucheCloudStandIn.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CartoucheCloudStandIn.self]
        client = CartoucheCloudClient(platform: CartoucheCloudStandIn.platform,
                                      session: CartoucheCloudClient.makeSession(configuration))
    }

    private var standIn: CartoucheCloudStandIn.State { CartoucheCloudStandIn.state }

    /// Links a device with a code the account's page gave: its token.
    private func linked() async throws -> String {
        let code = standIn.offer()
        return try await client.link(code: code).token
    }

    // MARK: The code

    func testTakesTheCodeAsTheAccountsPageShowsItOrAsTyped() {
        for text in ["ABCD-EFGH", "abcd-efgh", " ABCD EFGH ", "ABCDEFGH", "abCD efGH\n"] {
            XCTAssertEqual(CartoucheCloudCode.typed(text), "ABCDEFGH", text)
        }
        XCTAssertEqual(CartoucheCloudCode.typed("2345-6789"), "23456789")
        // 0, O, 1 and I are none of its letters; nor is anything but eight.
        for text in ["ABCD-EFG0", "ABCD-EFGO", "ABCD-EFG1", "ABCD-EFGI", "ABCD-EFG", "ABCD-EFGHJ", "", "ABCD_EFGH",
                     "ÀBCD-EFGH", String(repeating: " ", count: 30) + "ABCDEFGH"] {
            XCTAssertNil(CartoucheCloudCode.typed(text), text)
        }
        XCTAssertEqual(CartoucheCloudCode.grouped("ABCDEFGH"), "ABCD-EFGH")
    }

    func testTheFieldKeepsTheCodesOwnLettersAsTheyAreTyped() {
        XCTAssertEqual(CartoucheCloudCode.entered("abcd-"), "ABCD")
        XCTAssertEqual(CartoucheCloudCode.entered("ABCD-EFGH-JK"), "ABCDEFGH")
        XCTAssertEqual(CartoucheCloudCode.entered("a0b1c O I d"), "ABCD")
        XCTAssertEqual(CartoucheCloudCode.entered(""), "")
    }

    func testReadsTheCodeOfTheLinkTheAccountsPageOpens() throws {
        let link = try XCTUnwrap(URL(string: "cartouche://cloud/link?code=ABCDEFGH"))
        XCTAssertEqual(CartoucheCloudCode.linked(link), "ABCDEFGH")
        XCTAssertEqual(CartoucheCloudCode.linked(try XCTUnwrap(URL(string: "cartouche://CLOUD/link?code=abcd-efgh"))), "ABCDEFGH")
        for text in ["cartouche://cloud/link?code=ABCDEFG0", "cartouche://cloud/link", "cartouche://cloud/unlink?code=ABCDEFGH",
                     "cartouche://games/link?code=ABCDEFGH", "cartouche://livecontainer-launch?bundle-name=x",
                     "file:///cloud/link?code=ABCDEFGH"] {
            XCTAssertNil(CartoucheCloudCode.linked(try XCTUnwrap(URL(string: text))), text)
        }
    }

    // MARK: Anyone's question

    func testAsksTheServiceWithoutAToken() async throws {
        let service = try await client.service()
        XCTAssertEqual(service, CartoucheCloudService(signup: .invitation, idle: nil, price: 250))
        standIn.service = #"{"signup":"open","idle":"paused","price":300}"#
        let open = try await client.service()
        XCTAssertEqual(open, CartoucheCloudService(signup: .open, idle: .paused, price: 300))
        // Words this Cartouche does not know.
        standIn.service = #"{"signup":"waitlist","idle":"moving","price":250,"more":1}"#
        let newer = try await client.service()
        XCTAssertEqual(newer, CartoucheCloudService(signup: .invitation, idle: .paused, price: 250))
        let asked = standIn.requests.filter { $0.path == "/api/app/service" }
        XCTAssertEqual(asked.count, 3)
        XCTAssertTrue(asked.allSatisfy { $0.method == "GET" && $0.authorization == nil })
    }

    // MARK: Linking

    func testLinksWithACodeOnce() async throws {
        let code = standIn.offer()
        let linked = try await client.link(code: code)
        XCTAssertEqual(linked.token.count, 43)
        XCTAssertNotNil(standIn.devices[linked.token])
        let sent = try XCTUnwrap(standIn.requests.last)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertNil(sent.authorization)
        XCTAssertEqual(sent.body as? [String: String], ["code": code])
        // A code is good once; a wrong one says no more.
        await assertRefused(.code) { _ = try await self.client.link(code: code) }
        await assertRefused(.code) { _ = try await self.client.link(code: "ABCDEFGH") }
    }

    func testACodeLastsTenMinutes() async throws {
        let code = standIn.offer()
        standIn.forward(10 * 60 + 1)
        await assertRefused(.code) { _ = try await self.client.link(code: code) }
    }

    func testTenDevicesAtMost() async throws {
        for _ in 0..<10 { _ = try await linked() }
        await assertRefused(.full) { _ = try await self.client.link(code: self.standIn.offer()) }
    }

    // MARK: The account's games

    func testReadsTheAccountsGamesInEachState() async throws {
        let token = try await linked()
        let account = try await client.account(token: token)
        XCTAssertEqual(account.credits, CartoucheCloudCredits(balance: 2500, held: 500, available: 2000, price: 250))
        XCTAssertNil(account.idle)
        XCTAssertEqual(account.games.map(\.state), [.queued, .building, .built, .failed, .open, .other])
        let (queued, building, built, failed) = (account.games[0], account.games[1], account.games[2], account.games[3])
        XCTAssertEqual(queued.behind, true)
        XCTAssertNil(queued.place)
        XCTAssertEqual(queued.stage, 0)
        XCTAssertEqual(building.stage, 4)
        XCTAssertEqual(building.step, "build")
        XCTAssertEqual(building.usual, 2700)
        XCTAssertEqual(building.launchedAt, CartoucheCloudStandIn.moment("2026-11-17T12:01:00Z"))
        XCTAssertEqual(built.bytes, UInt64(CartoucheCloudStandIn.ipa.count))
        XCTAssertEqual(built.file, "Mario Kart 8 Deluxe [0100152000022000].ipa")
        XCTAssertEqual(built.builtAt, CartoucheCloudStandIn.moment("2026-11-17T12:32:00Z"))
        XCTAssertEqual(built.titleId, "0100152000022000")
        XCTAssertEqual([failed.cause, failed.left], ["build", "held"])
        XCTAssertNil(failed.until)
        XCTAssertTrue(account.isBusy)
        // Only the game built is there to fetch, until it expires.
        XCTAssertEqual(account.built(at: CartoucheCloudStandIn.moment("2026-11-18T12:00:00Z")).map(\.id), [built.id])
        XCTAssertEqual(account.built(at: built.expiresAt).map(\.id), [])
        let sent = try XCTUnwrap(standIn.requests.last)
        XCTAssertEqual([sent.method, sent.path], ["GET", "/api/app/games"])
        XCTAssertEqual(sent.authorization, "Bearer " + token)
    }

    func testTheTimeLeftOfABuildIsTheUsualTimeSinceItsLaunch() async throws {
        let account = try await client.account(token: try await linked())
        let building = account.games[1]
        let launched = try XCTUnwrap(building.launchedAt)
        XCTAssertEqual(building.timeLeft(at: launched.addingTimeInterval(600)), 2100)
        XCTAssertNil(building.timeLeft(at: launched.addingTimeInterval(2700)))
        XCTAssertNil(account.games[0].timeLeft(at: launched))
    }

    func testKeepsWhatItReadAsItWasRead() async throws {
        let account = try await client.account(token: try await linked())
        let kept = try CartoucheCloudClient.encoder.encode(account)
        XCTAssertEqual(try CartoucheCloudClient.decoder.decode(CartoucheCloudAccount.self, from: kept), account)
    }

    func testATokenThatLinksNothingIsSaidSo() async throws {
        let token = try await linked()
        for wrong in ["", String(repeating: "A", count: 43), token + "x"] {
            await assertRefused(.unlinked) { _ = try await self.client.account(token: wrong) }
        }
        // Unlinked on the site.
        standIn.devices[token] = nil
        await assertRefused(.unlinked) { _ = try await self.client.account(token: token) }
    }

    func testUnlinks() async throws {
        let token = try await linked()
        try await client.unlink(token: token)
        XCTAssertNil(standIn.devices[token])
        await assertRefused(.unlinked) { _ = try await self.client.account(token: token) }
        await assertRefused(.unlinked) { try await self.client.unlink(token: token) }
    }

    // MARK: The IPA

    func testReadsTheIPAWithoutTheToken() async throws {
        let token = try await linked()
        let opened = try await client.openIPA(CartoucheCloudStandIn.builtGame, token: token)
        let ipa = CartoucheCloudStandIn.ipa
        XCTAssertEqual(opened.source.size, UInt64(ipa.count))
        let head = try await opened.source.read(at: 0, count: 100)
        XCTAssertEqual(head, ipa.prefix(100))
        let tail = try await opened.source.read(at: UInt64(ipa.count - 10), count: 100)
        XCTAssertEqual(tail, ipa.suffix(10))
        let whole = try await opened.source.read(at: 0, count: ipa.count)
        XCTAssertEqual(whole, ipa)
        let stored = standIn.requests.filter { $0.host == CartoucheCloudStandIn.storageHost }
        XCTAssertGreaterThan(stored.count, 0)
        XCTAssertTrue(stored.allSatisfy { $0.authorization == nil && $0.range != nil }, "the token goes to the platform alone")
        let asked = try XCTUnwrap(standIn.requests.first { $0.path == "/api/app/ipa" })
        XCTAssertEqual(asked.body as? [String: String], ["id": CartoucheCloudStandIn.builtGame])
        XCTAssertEqual(asked.authorization, "Bearer " + token)
    }

    func testADownloadThatOutlivesItsAddressAsksAnother() async throws {
        let token = try await linked()
        let opened = try await client.openIPA(CartoucheCloudStandIn.builtGame, token: token)
        let ipa = CartoucheCloudStandIn.ipa
        let part = 4 << 20
        var read = try await opened.source.read(at: 0, count: part)
        // A quarter of an hour later, the storage refuses the address: the
        // platform gives another, and the download goes on from there.
        standIn.forward(15 * 60 + 1)
        read += try await opened.source.read(at: UInt64(part), count: ipa.count - part)
        XCTAssertEqual(read, ipa)
        let asked = standIn.requests.filter { $0.path == "/api/app/ipa" }
        XCTAssertEqual(asked.count, 2)
        // The second address goes on with the same download: the platform
        // counts it once.
        XCTAssertEqual(asked[0].body as? [String: String], ["id": CartoucheCloudStandIn.builtGame])
        let again = try XCTUnwrap(asked[1].body as? [String: Any])
        XCTAssertEqual(again["id"] as? String, CartoucheCloudStandIn.builtGame)
        XCTAssertEqual(again["again"] as? Bool, true)
        XCTAssertEqual(standIn.refusedAddresses, 1)
        XCTAssertEqual((opened.source as? CartoucheCloudIPA)?.renewed, 1)
    }

    func testAnAddressAboutToExpireIsGivenUpFirst() async throws {
        let token = try await linked()
        // Addresses that last less than the margin: each part asks for one.
        standIn.addressSeconds = 30
        let opened = try await client.openIPA(CartoucheCloudStandIn.builtGame, token: token)
        let part = 4 << 20
        _ = try await opened.source.read(at: 0, count: part)
        _ = try await opened.source.read(at: UInt64(part), count: part)
        XCTAssertEqual((opened.source as? CartoucheCloudIPA)?.renewed, 2)
        XCTAssertEqual(standIn.refusedAddresses, 0)
    }

    func testAnInstallGoesOnAfterTheNetworkDroppedAsTheSameDownload() async throws {
        let token = try await linked()
        let source = try await client.ipa(CartoucheCloudStandIn.builtGame, token: token, pauses: [0, 0])
        let ipa = CartoucheCloudStandIn.ipa
        let part = 4 << 20
        var read = try await source.read(at: 0, count: part)
        // The network drops: the IPA opens again, and the install reads on
        // from where it stopped.
        standIn.dropsNext = 1
        read += try await source.read(at: UInt64(part), count: ipa.count - part)
        XCTAssertEqual(read, ipa)
        XCTAssertEqual(source.reopened, 1)
        // The platform counts the download once.
        let asked = standIn.requests.filter { $0.path == "/api/app/ipa" }
        XCTAssertEqual(asked.count, 2)
        XCTAssertEqual(asked[0].body as? [String: String], ["id": CartoucheCloudStandIn.builtGame])
        XCTAssertEqual((asked[1].body as? [String: Any])?["again"] as? Bool, true)
    }

    func testAnIPAGoneOrAnotherIsSaidSo() async throws {
        let token = try await linked()
        await assertRefused(.missing) { _ = try await self.client.openIPA(String(repeating: "0", count: 32), token: token) }
        standIn.storage = false
        await assertRefused(.storage) { _ = try await self.client.openIPA(CartoucheCloudStandIn.builtGame, token: token) }
        standIn.storage = true
        let opened = try await client.openIPA(CartoucheCloudStandIn.builtGame, token: token)
        // Built again meanwhile, at another size: the install cannot go on.
        standIn.forward(15 * 60 + 1)
        standIn.ipaBytes = UInt64(CartoucheCloudStandIn.ipa.count + 1)
        do {
            _ = try await opened.source.read(at: 0, count: 4 << 20)
            XCTFail("read another IPA")
        } catch is CartoucheResumingSource.Changed {
        }
    }

    // MARK: The network

    func testNoRedirectionIsFollowed() async throws {
        standIn.redirects = true
        await assertRefused(.server) { _ = try await self.client.service() }
        XCTAssertFalse(standIn.requests.contains { $0.host == "elsewhere.test" })
    }

    func testOfflineIsSaid() async throws {
        standIn.offline = true
        await assertRefused(.offline) { _ = try await self.client.service() }
    }

    func testAnAnswerItCannotReadIsTheServers() async throws {
        standIn.service = "<html>maintenance</html>"
        await assertRefused(.server) { _ = try await self.client.service() }
    }

    private func assertRefused(_ kind: CartoucheCloudError.Kind, file: StaticString = #filePath, line: UInt = #line,
                               _ call: @escaping () async throws -> Void) async {
        do {
            try await call()
            XCTFail("not refused", file: file, line: line)
        } catch let error as CartoucheCloudError {
            XCTAssertEqual(error.kind, kind, file: file, line: line)
        } catch {
            XCTFail("\(error)", file: file, line: line)
        }
    }
}

/// The stand-in for Cartouche Cloud's platform and its storage, answering
/// as the platform does (its API for the app): one account, with a game
/// in each state, and the IPA of the game built.
final class CartoucheCloudStandIn: URLProtocol {
    static let platform = URL(string: "https://cloud.test")!
    static let storageHost = "storage.test"
    static let builtGame = "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"
    /// 9 MiB, so that an install reads it in several parts.
    static let ipa: Data = {
        var bytes = [UInt8](repeating: 0, count: 9 << 20)
        var seed: UInt32 = 2_463_534_242
        for index in bytes.indices {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            bytes[index] = UInt8(truncatingIfNeeded: seed)
        }
        return Data(bytes)
    }()

    static func moment(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// A request as the stand-in saw it.
    struct Seen {
        let method: String
        let host: String
        let path: String
        let authorization: String?
        let range: String?
        let body: Any?
    }

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        /// Its clock, which the tests move on: the IPA's addresses expire by it.
        var now = Date()
        var service = #"{"signup":"invitation","idle":null,"price":250}"#
        var codes: [String: (expires: Date, used: Bool)] = [:]
        /// The iPhones linked, by token: when each was.
        var devices: [String: Date] = [:]
        var addressSeconds: TimeInterval = 15 * 60
        var addresses: [String: Date] = [:]
        var refusedAddresses = 0
        var storage = true
        var redirects = false
        var offline = false
        /// How many of the storage's next answers the network drops.
        var dropsNext = 0
        var ipaBytes = UInt64(CartoucheCloudStandIn.ipa.count)
        private(set) var seen: [Seen] = []

        var requests: [Seen] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        func forward(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }

        /// A code, as the account's page gives it.
        func offer() -> String {
            let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
            let code = String((0..<8).map { _ in letters.randomElement()! })
            codes[code] = (now.addingTimeInterval(10 * 60), false)
            return code
        }

        func note(_ seen: Seen) {
            lock.lock()
            self.seen.append(seen)
            lock.unlock()
        }
    }

    nonisolated(unsafe) static var state = State()

    static func reset() {
        state = State()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let state = Self.state
        let url = request.url!
        let body = Self.body(of: request)
        state.note(Seen(method: request.httpMethod ?? "GET", host: url.host ?? "", path: url.path,
                        authorization: request.value(forHTTPHeaderField: "Authorization"),
                        range: request.value(forHTTPHeaderField: "Range"),
                        body: body.flatMap { try? JSONSerialization.jsonObject(with: $0) }))
        if state.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if url.host == Self.storageHost, state.dropsNext > 0 {
            state.dropsNext -= 1
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let (status, headers, data) = url.host == Self.storageHost ? stored(url, state) : answer(url, body, state)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private typealias Answer = (Int, [String: String], Data)

    private func json(_ status: Int, _ object: Any) -> Answer {
        (status, ["Content-Type": "application/json", "Cache-Control": "no-store"],
         (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private func answer(_ url: URL, _ body: Data?, _ state: State) -> Answer {
        let method = request.httpMethod ?? "GET"
        if state.redirects {
            return (302, ["Location": "https://elsewhere.test/api/app/service"], Data())
        }
        let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        switch (method, url.path) {
        case ("GET", "/api/app/service"):
            return (200, ["Content-Type": "application/json"], Data(state.service.utf8))
        case ("POST", "/api/app/link"):
            guard let sent else { return json(400, ["error": "body"]) }
            guard let code = sent["code"] as? String, let offered = state.codes[code], !offered.used,
                  offered.expires > state.now else { return json(422, ["error": "code"]) }
            state.codes[code]?.used = true
            guard state.devices.count < 10 else { return json(409, ["error": "full"]) }
            let token = String((0..<43).map { _ in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").randomElement()! })
            state.devices[token] = state.now
            return json(200, ["device": String(repeating: "d", count: 32), "token": token])
        case (_, "/api/app/games"), (_, "/api/app/ipa"), (_, "/api/app/unlink"):
            guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer "),
                  state.devices[String(header.dropFirst(7))] != nil else {
                return (401, ["Content-Type": "application/json", "WWW-Authenticate": #"Bearer realm="Cartouche Cloud""#],
                        Data(#"{"error":"token"}"#.utf8))
            }
            switch url.path {
            case "/api/app/games":
                return json(200, Self.account)
            case "/api/app/ipa":
                guard state.storage else { return json(503, ["error": "storage"]) }
                guard sent?["id"] as? String == Self.builtGame else { return json(404, ["error": "missing"]) }
                let name = UUID().uuidString
                let expires = state.now.addingTimeInterval(state.addressSeconds)
                state.addresses[name] = expires
                return json(200, ["url": "https://\(Self.storageHost)/cartouche-cloud/builds/\(Self.builtGame)/game.ipa?X-Amz-Signature=\(name)",
                                  "expires_at": ISO8601DateFormatter().string(from: expires),
                                  "bytes": state.ipaBytes, "file": "Mario Kart 8 Deluxe [0100152000022000].ipa"])
            default:
                state.devices[String(header.dropFirst(7))] = nil
                return json(200, ["ok": true])
            }
        default:
            return json(404, ["error": "missing"])
        }
    }

    /// The storage: the IPA, a range of it, at an address of the platform's
    /// that has not expired.
    private func stored(_ url: URL, _ state: State) -> Answer {
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "X-Amz-Signature" }?.value ?? ""
        guard let expires = state.addresses[name], expires > state.now else {
            state.refusedAddresses += 1
            return (403, [:], Data("<Error><Code>AccessDenied</Code></Error>".utf8))
        }
        let ipa = Self.ipa
        guard let range = request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="),
              let dash = range.firstIndex(of: "-"),
              let start = Int(range[range.index(range.startIndex, offsetBy: 6) ..< dash]),
              let end = Int(range[range.index(after: dash)...]) else {
            return (200, [:], ipa)
        }
        let last = min(end, ipa.count - 1)
        return (206, ["Content-Range": "bytes \(start)-\(last)/\(ipa.count)"], ipa.subdata(in: start ..< last + 1))
    }

    /// The account's games, as the platform's tests show them.
    private static var account: [String: Any] {
        let expires = "2026-11-19T12:32:00Z"
        return [
            "games": [
                ["id": "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", "title": "0100152000022000", "name": "Mario Kart 8 Deluxe",
                 "state": "queued", "price": 250, "expires_at": expires, "stage": 0, "usual": NSNull(), "behind": true,
                 "place": NSNull()],
                ["id": "a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2", "title": "0100152000022000", "name": "Mario Kart 8 Deluxe",
                 "state": "building", "price": 250, "expires_at": expires, "stage": 4, "usual": 2700, "step": "build",
                 "launched_at": "2026-11-17T12:01:00Z"],
                ["id": builtGame, "title": "0100152000022000", "name": "Mario Kart 8 Deluxe", "state": "built",
                 "price": 250, "expires_at": expires, "bytes": ipa.count,
                 "file": "Mario Kart 8 Deluxe [0100152000022000].ipa", "built_at": "2026-11-17T12:32:00Z"],
                ["id": "a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3", "title": "01006F8002326000", "name": "Animal Crossing",
                 "state": "failed", "price": 250, "expires_at": expires, "cause": "build", "left": "held",
                 "until": NSNull()],
                ["id": "a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4", "title": "0100000000010000", "name": "Super Mario Odyssey",
                 "state": "open", "price": 250, "expires_at": expires],
                ["id": "a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5", "title": "0100000000010000", "name": "Super Mario Odyssey",
                 "state": "archived", "price": 250, "expires_at": expires],
            ],
            "credits": ["balance": 2500, "held": 500, "available": 2000, "price": 250],
            "idle": NSNull(),
        ]
    }
}
