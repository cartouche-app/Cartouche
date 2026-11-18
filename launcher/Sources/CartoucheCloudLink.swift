//
//  CartoucheCloudLink.swift
//  Cartouche
//
//  This iPhone's link to a Cartouche Cloud account (decision 136), which
//  the page of Cartouche Cloud makes, follows and undoes
//  (CartoucheCloudPage): the code of the account's page, typed there or in
//  the link that page opens Cartouche with, links the iPhone at once, and
//  the platform gives a token for it (CartoucheCloud.swift). Cartouche keeps
//  the token in the iPhone's keychain, as the storage's passwords, for this
//  iPhone alone, and never puts it in a report, the journal or a
//  measurement; a code given while linked links the iPhone to its account
//  in place of the other one, which the platform forgets.
//
//  With the token, Cartouche reads the account's games: every few seconds
//  while the page shows, so that a build moves on its track, and once a
//  minute at most as Cartouche comes forward, so that a game built
//  meanwhile shows in the library, where Install brings it
//  (CartoucheGameActions.install(cloud:)). What it last read is kept in
//  Cartouche's caches, without the token, for the library to show a game
//  built as Cartouche opens. A token the platform no longer knows, as after
//  Unlink on the site, is forgotten at once, with what it read. Reset
//  Cartouche unlinks the iPhone first, a few seconds at most, then erases
//  the token with the storage's items (CartoucheResetPlan.erasedServices).
//
//  The iPhone alone: a Mac builds its own games with Cartouche Builder.
//

import Foundation
import Security

@MainActor
final class CartoucheCloudLink: ObservableObject {
    static let shared = CartoucheCloudLink()

    /// What links or unlinks this iPhone, until the platform answers.
    enum Busy: Equatable {
        case linking, unlinking
    }

    /// Whether this iPhone is linked to an account: it has a token.
    @Published private(set) var isLinked = false
    /// What the service says to anyone: how one gets an account, why no
    /// build starts, and the price of a build. Nil until it answered.
    @Published private(set) var service: CartoucheCloudService?
    /// The account's games and credits, as last read; nil before, and once
    /// unlinked.
    @Published private(set) var account: CartoucheCloudAccount?
    /// When the account was last read.
    @Published private(set) var readAt: Date?
    /// Why the last reading did not go through, until one does.
    @Published private(set) var problem: CartoucheCloudError?
    /// Whether the platform said the token links nothing any more: the
    /// iPhone was unlinked on the site, until it is linked again.
    @Published private(set) var unlinkedElsewhere = false
    /// A link or an unlink under way.
    @Published private(set) var busy: Busy?
    /// Why the last code did not link, or Unlink did not go through.
    @Published private(set) var refusal: CartoucheCloudError?
    /// The code of the link the account's page opened Cartouche with, which
    /// the page's field shows while it links.
    @Published var pendingCode: String?
    /// Whether System opens the page of Cartouche Cloud: that link came.
    @Published var opensPage = false

    let client: CartoucheCloudClient
    /// The device's token, as the keychain keeps it.
    private(set) var token: String?
    private var loop: Task<Void, Never>?
    /// The screens that show the account's games, which it is read for.
    private var viewers = 0
    #if CARTOUCHE_GALLERY
    /// Whether the gallery shows its own answers: nothing is asked.
    private var shownForGallery = false
    #endif

    init(client: CartoucheCloudClient = CartoucheCloudClient()) {
        self.client = client
        token = Self.readToken()
        isLinked = token != nil
        if isLinked { account = Self.readCache() }
    }

    // MARK: The games built

    /// The games built for the account whose IPA is there to fetch, one of
    /// each title, the latest built first: those the library offers to
    /// install.
    var builtGames: [CartoucheCloudBuilt] {
        guard isLinked, let account else { return [] }
        return account.toInstall().map(CartoucheCloudBuilt.init)
    }

    // MARK: Reading the account

    /// Reads the account's games from now on, every few seconds, until
    /// every screen that started it stops it: CartoucheCloud.pause.
    func start() {
        viewers += 1
        #if CARTOUCHE_GALLERY
        if shownForGallery { return }
        #endif
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let answered = await self.refresh()
                let seconds = CartoucheCloud.pause(busy: self.account?.isBusy ?? false, failed: !answered)
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    func stop() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        loop?.cancel()
        loop = nil
    }

    /// Cartouche came forward: a linked iPhone reads its games, once a
    /// minute at most, for a game built meanwhile.
    func cameForward() {
        #if CARTOUCHE_GALLERY
        if shownForGallery { return }
        #endif
        guard isLinked, loop == nil, Date().timeIntervalSince(readAt ?? .distantPast) >= CartoucheCloud.forwardSeconds else {
            return
        }
        Task { await refresh() }
    }

    /// Reads the account's games, with the token; without one, what the
    /// service says to anyone. Whether the platform answered.
    @discardableResult
    func refresh() async -> Bool {
        guard let token else {
            do {
                service = try await client.service()
                problem = nil
                return true
            } catch let error as CartoucheCloudError {
                problem = error
                return false
            } catch {
                return false
            }
        }
        do {
            let read = try await client.account(token: token)
            // Unlinked, or linked to another account, meanwhile.
            guard self.token == token else { return true }
            account = read
            readAt = Date()
            problem = nil
            Self.writeCache(read)
            return true
        } catch let error as CartoucheCloudError where error.kind == .unlinked {
            guard self.token == token else { return true }
            CartoucheReports.note("Cartouche Cloud: the platform no longer knows this iPhone's token, forgotten")
            forgetToken()
            unlinkedElsewhere = true
            return await refresh()
        } catch let error as CartoucheCloudError {
            problem = error
            return false
        } catch {
            return false
        }
    }

    // MARK: Linking

    /// Takes the link the account's page opened Cartouche with
    /// (cartouche://cloud/link?code=…): System opens the page of Cartouche
    /// Cloud, unless it shows already, and the iPhone links with its code
    /// at once. False for any other link, which Cartouche leaves.
    static func opened(_ url: URL) -> Bool {
        guard let code = CartoucheCloudCode.linked(url) else { return false }
        CartoucheReports.note("Cartouche Cloud: opened by the link of an account's page")
        shared.pendingCode = code
        if shared.viewers == 0 { shared.opensPage = true }
        shared.link(code: code)
        return true
    }

    /// Links this iPhone with the code TEXT, as typed: in place of the
    /// account it is linked to, if it is, which the platform then forgets.
    func link(code text: String) {
        guard busy == nil else { return }
        guard let code = CartoucheCloudCode.typed(text) else {
            refusal = CartoucheCloudError(.code)
            return
        }
        busy = .linking
        refusal = nil
        #if CARTOUCHE_GALLERY
        if shownForGallery { return }
        #endif
        Task {
            defer { busy = nil }
            do {
                let linked = try await client.link(code: code)
                let previous = token
                Self.storeToken(linked.token)
                token = linked.token
                isLinked = true
                unlinkedElsewhere = false
                pendingCode = nil
                account = nil
                readAt = nil
                CartoucheReports.note("Cartouche Cloud: this iPhone is linked to an account")
                if let previous, previous != linked.token {
                    try? await client.unlink(token: previous)
                }
                await refresh()
            } catch let error as CartoucheCloudError {
                refusal = error
            } catch {}
        }
    }

    /// Unlinks this iPhone: the platform forgets it, then Cartouche its
    /// token. When the platform cannot be reached, the iPhone stays linked
    /// and the page says why.
    func unlink() {
        guard busy == nil, let token else { return }
        busy = .unlinking
        refusal = nil
        Task {
            defer { busy = nil }
            do {
                try await client.unlink(token: token)
            } catch let error as CartoucheCloudError where error.kind != .unlinked {
                refusal = error
                return
            } catch is CartoucheCloudError {
                // Unlinked already, on the site.
            } catch {
                return
            }
            CartoucheReports.note("Cartouche Cloud: this iPhone is unlinked")
            forgetToken()
            await refresh()
        }
    }

    /// Forgets the token and what it read: the platform no longer knows it.
    func forgetToken() {
        Self.eraseToken()
        token = nil
        isLinked = false
        account = nil
        readAt = nil
        try? FileManager.default.removeItem(at: Self.cacheFile)
    }

    /// Before Reset Cartouche erases the token: the platform forgets this
    /// iPhone, five seconds at most. One it could not hear stays listed on
    /// the account's page until it is unlinked there, or unseen 90 days.
    func unlinkForReset() async {
        guard let token else { return }
        let client = self.client
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await client.unlink(token: token) }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            await group.next()
            group.cancelAll()
        }
        forgetToken()
    }

    // MARK: The keychain

    /// The keychain item of the token, in CartoucheCloud.keychainService.
    private static let tokenAccount = "token"

    private static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CartoucheCloud.keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    private static func storeToken(_ token: String) {
        eraseToken()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CartoucheCloud.keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: Data(token.utf8),
            // This iPhone's alone, readable after its first unlock, as the
            // storage's secrets.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            CartoucheReports.note("Cartouche Cloud: the keychain did not keep the token, OSStatus \(status)")
        }
    }

    private static func eraseToken() {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CartoucheCloud.keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(item as CFDictionary)
    }

    // MARK: What was read last

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cartouche/CloudGames.json")
    }

    private static func readCache() -> CartoucheCloudAccount? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? CartoucheCloudClient.decoder.decode(CartoucheCloudAccount.self, from: data)
    }

    private static func writeCache(_ account: CartoucheCloudAccount) {
        guard let data = try? CartoucheCloudClient.encoder.encode(account) else { return }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
    }

    #if CARTOUCHE_GALLERY
    /// What the gallery shows in place of the platform's answers
    /// (launcher/Gallery): an iPhone linked or not, the account's games,
    /// and a link under way or refused.
    func showForGallery(linked: Bool, service: CartoucheCloudService?, account: CartoucheCloudAccount?,
                        pendingCode: String? = nil, busy: Busy? = nil, refusal: CartoucheCloudError? = nil) {
        shownForGallery = true
        isLinked = linked
        token = linked ? "gallery" : nil
        self.service = service
        self.account = account
        readAt = account == nil ? nil : Date()
        self.pendingCode = pendingCode
        self.busy = busy
        self.refusal = refusal
    }
    #endif
}

extension CartoucheCloudBuilt {
    /// GAME, built, as the library has it.
    init(_ game: CartoucheCloudGame) {
        self.init(id: game.id, titleId: game.titleId, name: game.name, bytes: game.bytes ?? 0,
                  file: game.file ?? CartoucheStoredGame.fileName(game: game.name, titleId: game.titleId),
                  builtAt: game.builtAt, expiresAt: game.expiresAt)
    }
}
