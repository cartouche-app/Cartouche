//
//  CartoucheReporting.swift
//  Cartouche
//
//  The reports on what goes wrong (CartoucheReport.swift), in the app: made
//  where an error shows, with this iPhone's and this Cartouche's state, kept
//  with the last ten and with a journal of Cartouche's last steps, both in
//  Application Support/Cartouche, and copied by the Copy the report button
//  under each error, without a password, a user name, an Apple ID, a team's
//  name, nor a server's address, name or folder (CartoucheRedaction, from
//  the player's settings).
//
//  The console on the Mac makes the same, with that Mac's and Cartouche
//  Builder's state, in the Builder's folder (keep(in:)).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(SMBClient)
import SMBClient
#endif

@MainActor
enum CartoucheReports {
    #if os(iOS)
    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Cartouche", isDirectory: true)

    #if CARTOUCHE_GALLERY
    // The gallery's screens start from nothing.
    private static let journalFile: URL? = nil
    private static let archiveFile: URL? = nil
    #else
    private static let journalFile: URL? = folder.appendingPathComponent("Journal.txt")
    private static let archiveFile: URL? = folder.appendingPathComponent("Reports.json")
    #endif

    private static let journalLines = CartoucheJournal(file: journalFile)
    private static let archive = CartoucheReportArchive(file: archiveFile)
    #else
    // The console's on the Mac, in memory until Cartouche Builder says
    // where its folder is (keep(in:)), as the app starts: its gallery and
    // its tests keep nothing.
    private static var journalLines = CartoucheJournal(file: nil)
    private static var archive = CartoucheReportArchive(file: nil)

    /// Keeps the journal and the last reports in FOLDER from now on, in
    /// Cartouche Builder's folder, or in memory alone for nil: once, as the
    /// app starts, before the console notes anything.
    static func keep(in folder: URL?) {
        journalLines = CartoucheJournal(file: folder?.appendingPathComponent("Journal.txt"))
        archive = CartoucheReportArchive(file: folder?.appendingPathComponent("Reports.json"))
    }
    #endif

    /// The last steps a report takes along.
    static let journalShown = 40

    // MARK: Making a report

    /// Posted on the main thread for each report made, with the report,
    /// redacted, as its object. Its user info holds, under "origin", the
    /// report's origin as its raw value ("install"), under "error" the
    /// error behind it, if any, under "failure" why it failed, as names and
    /// numbers (CartoucheFailure), and under "background" whether it came
    /// of a check Cartouche made by itself.
    static let reported = Notification.Name("CartoucheErrorReported")

    /// A report on what just went wrong at ORIGIN, as the player reads it:
    /// TITLE and MESSAGE, the ERROR behind them, the STEP Cartouche was at
    /// and how far it had gone, and the FACTS of that step, such as its
    /// sizes. FAILURE says why, as the measurements send it; without one,
    /// it is read off ERROR, with STAGE, the step as a key. It is noted in
    /// the journal and posted as reported. Unless it came of a check
    /// Cartouche makes by itself, IN BACKGROUND, such as reading the games
    /// folder each time it comes back, which fails whenever the player is
    /// away from home, it is kept with the last ten.
    static func make(_ origin: CartoucheReport.Origin, _ title: String, message: String, error: Error? = nil,
                     step: String? = nil, fraction: Double? = nil, stage: String? = nil, seconds: Double? = nil,
                     failure: CartoucheFailure? = nil, facts: [CartoucheReport.Fact] = [],
                     inBackground: Bool = false) -> CartoucheReport {
        let failure = failure ?? error.map {
            CartoucheFailure.of($0, stage: stage, fraction: fraction, seconds: seconds, status: protocolStatus)
        }
        note("Problem (" + origin.rawValue + "): " + title + ": " + message + (error.map { " [" + describe($0) + "]" } ?? "")
             + (failure.map { " {" + $0.summary + "}" } ?? ""))
        let report = CartoucheReport(origin: origin, title: title, message: message, step: step, fraction: fraction,
                                     error: error.map(describe), failure: failure, facts: facts, environment: environment(),
                                     journal: journal(last: journalShown))
        let redaction = redaction()
        if !inBackground {
            archive.add(report, redactedBy: redaction)
        }
        var info: [String: Any] = ["origin": origin.rawValue, "background": inBackground]
        if let error {
            info["error"] = error
        }
        if let failure {
            info["failure"] = failure
        }
        NotificationCenter.default.post(name: reported, object: report.redacted(by: redaction), userInfo: info)
        return report
    }

    /// The report's text, redacted, to copy or to send.
    static func text(of report: CartoucheReport) -> String {
        report.text(redactedBy: redaction())
    }

    /// Puts the report's text on the pasteboard.
    static func copy(_ report: CartoucheReport) {
        copy(text: text(of: report))
        note("Report copied: " + report.title)
    }

    /// Puts TEXT on the pasteboard, as Copy the report does.
    static func copy(text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// The last reports, the newest first, redacted.
    static var recent: [CartoucheReport] { archive.reports }

    // MARK: The journal

    /// Notes a step in the journal, redacted. OWN is for a line made of
    /// Cartouche's own words and numbers alone, never of a name, a message
    /// or a path from anywhere else: a name of the player's that is one of
    /// its words stays in it ("Saves sent to the saves folder: 3 games").
    static func note(_ text: String, own: Bool = false) {
        journalLines.note(redaction().redact(text, own: own))
    }

    /// The journal's COUNT last lines, oldest first.
    static func journal(last count: Int) -> [String] {
        journalLines.last(count)
    }

    /// Forgets the journal and the reports kept, files and all, as
    /// Cartouche is reset (CartoucheReset): what is noted next starts them
    /// again.
    static func forget() {
        journalLines.clear()
        archive.clear()
    }

    /// Waits for the journal's lines and the reports on their way to their
    /// files: before Cartouche ends at once, as a reset ends it.
    static func flush() {
        journalLines.flush()
        archive.flush()
    }

    private static var startNoted = false

    /// Notes that Cartouche opened, once per launch; on the Mac, that the
    /// console first showed.
    static func noteStart() {
        guard !startNoted else { return }
        startNoted = true
        let environment = environment()
        #if os(iOS)
        note("Cartouche \(environment.cartouche) started, iOS \(environment.system), \(environment.device)")
        #else
        note("Console of Cartouche for Mac \(environment.cartouche) shown, macOS \(environment.system), \(environment.device)")
        #endif
    }

    /// Notes what Cartouche does with a game (CartoucheGameActions.work):
    /// each step as the screen says it, every quarter of the way, and its
    /// end, unless it FAILED, which its report noted.
    static func noteWork(from old: CartoucheGameWork?, to new: CartoucheGameWork?, failed: Bool) {
        switch (old, new) {
        case (nil, let new?):
            note(new.title + ": " + new.step)
        case (let old?, let new?):
            if old.kind != new.kind || old.name != new.name || old.step != new.step {
                note(new.title + ": " + new.step)
            } else if let fraction = new.fraction, fraction < 1, Int(fraction * 4) > Int((old.fraction ?? 0) * 4) {
                note(new.title + ": " + CartoucheReport.percent(fraction))
            }
        case (let old?, nil):
            if !failed { note(old.title + ": done") }
        case (nil, nil):
            break
        }
    }

    // MARK: The player's storage

    /// A report on the connection to SERVER, as its form holds it, which
    /// failed with ERROR. What the player typed in the form is taken out of
    /// reports first: it is not in their settings yet.
    static func connectionFailed(to server: CartoucheStorageServer, error: Error) -> CartoucheReport {
        redactTyped(servers: [server.host] + (server.tailnet ?? []), names: [server.name, server.share], accounts: [server.username])
        var facts: [CartoucheReport.Fact] = []
        if let port = server.port {
            facts.append(.init("Port", String(port)))
        }
        if server.kind == .s3 {
            let host = server.host.lowercased()
            facts.append(.init("S3 server", host.contains("amazonaws.com") ? "Amazon S3" : "the player's own"))
            facts.append(.init("Connection", host.hasPrefix("http://") ? "HTTP" : "HTTPS"))
            if let region = server.region {
                facts.append(.init("Region", region))
            }
        }
        // A server that does not answer from here: its address may be wrong,
        // or the iPhone, or the Mac, away from its network.
        let message = (error as? CartoucheStorageOffline).map {
            $0.isSignedOut || $0.isMac || $0.tailscale == .off ? $0.localizedDescription : CartoucheText.storageOfflineCheck($0.name)
        } ?? error.localizedDescription
        return make(.storage, CartoucheText.storageConnectFailed, message: message, error: error,
                    step: "Connecting to " + kindName(server.kind), stage: "connect", facts: facts)
    }

    // MARK: What a report says of this iPhone, or of this Mac

    #if os(iOS)
    /// This iPhone and this Cartouche, now.
    static func environment() -> CartoucheReport.Environment {
        let info = Bundle.main.infoDictionary ?? [:]
        var cartouche = info["CFBundleShortVersionString"] as? String ?? "?"
        if let build = info["LCVersionInfo"] as? String, !build.isEmpty {
            cartouche += " (" + build + ")"
        }
        let bases = [("LiveContainer", "CartoucheLiveContainerVersion"), ("SideStore", "CartoucheSideStoreVersion")]
            .compactMap { name, key in (info[key] as? String).map { name + " " + $0 } }
        var system = CartoucheDevice.iOSVersion
        if let build = systemBuild, !build.isEmpty {
            system += " (" + build + ")"
        }
        let model = CartoucheDevice.modelIdentifier.isEmpty ? "?" : CartoucheDevice.modelIdentifier
        let device: String
        if let profile = CartoucheCatalog.shared.device(CartoucheDevice.modelIdentifier) {
            device = "\(model) (\(profile.chip), \(profile.memoryGB) GB)"
        } else {
            device = "\(model) (\(ProcessInfo.processInfo.physicalMemory / 1_048_576) MiB)"
        }
        let language = (Bundle.main.preferredLocalizations.first ?? "?") + " (" + (Locale.preferredLanguages.first ?? "?") + ")"

        // Cartouche's words and numbers only, never a name of the player's:
        // a report takes nothing but addresses out of them
        // (CartoucheReport.Environment).
        var facts: [CartoucheReport.Fact] = []
        let increased = "Increased Memory Limit " + (CartoucheDevice.hasIncreasedMemoryLimit ? "on" : "off")
        if let memory = CartoucheMemoryReading.now() {
            facts.append(.init("Memory", "limit \(memory.limitMiB) MiB, used \(memory.footprintMiB) MiB, \(increased)"))
        } else {
            facts.append(.init("Memory", "no limit from iOS, \(increased)"))
        }
        // A game behind the console has a limit of its own, which iOS may
        // set above Cartouche's.
        if CartoucheGameKeeping.isAvailable {
            let keeping = CartoucheGameKeeping.shared
            let behind = !keeping.keepsConsoleOpen ? "off"
                : keeping.limitMiB.map {
                    "limit \($0) MiB at the last game" + (keeping.behindLacksIML ? ", without Increased Memory Limit" : "")
                } ?? "not measured yet"
            facts.append(.init("Memory behind Cartouche", behind))
        }
        if let free = freeSpace {
            facts.append(.init("Free on this iPhone", CartoucheReport.bytes(free)))
        }
        let setup = CartoucheSetup.shared
        let certificate: String
        switch (setup.hasCertificate, setup.certificateWorks) {
        case (false, _): certificate = "none"
        case (true, true?): certificate = "works"
        case (true, false?): certificate = "refused by iOS"
        case (true, nil): certificate = "being checked"
        }
        facts.append(.init("Setup", "pairing file \(setup.hasPairingFile ? "yes" : "no"), Apple ID \(setup.appleID == nil ? "no" : "yes"), certificate \(certificate)"))
        if let days = CartoucheSignature.current().daysLeft {
            facts.append(.init("Signature", days < 0 ? "expired" : "\(days) days left"))
        }
        facts.append(storage())
        // The tunnel up: LocalDevVPN, which the built-in SideStore needs,
        // or Tailscale, which reaches the player's servers away from home;
        // iOS keeps one at a time.
        let tunnels = [CartoucheVPN.isConnected ? "LocalDevVPN" : nil, CartoucheTailscale.isConnected ? "Tailscale" : nil]
            .compactMap { $0 }
        facts.append(.init("VPN", tunnels.isEmpty ? "none" : tunnels.joined(separator: ", ")))
        return CartoucheReport.Environment(cartouche: cartouche, basedOn: bases.isEmpty ? nil : bases.joined(separator: ", "),
                                           system: system, device: device, language: language, facts: facts)
    }
    #else
    /// This Mac and Cartouche Builder, whose window the console is in, now:
    /// the Builder's version, macOS's, the Mac's model, chip and memory,
    /// and what the iPhone's says of the player's storage. A Mac has no
    /// signature, setup or memory limit of the iPhone's to say.
    static func environment() -> CartoucheReport.Environment {
        let info = Bundle.main.infoDictionary ?? [:]
        let builder = info["CFBundleShortVersionString"] as? String ?? "?"
        var system = CartoucheDevice.iOSVersion
        if let build = systemBuild, !build.isEmpty {
            system += " (" + build + ")"
        }
        let model = CartoucheDevice.modelIdentifier.isEmpty ? "?" : CartoucheDevice.modelIdentifier
        let memoryGB = CartoucheDeviceMeasurement.memoryGB(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        let device = "\(model) (\(CartoucheDevice.chip), \(memoryGB) GB)"
        let language = (Bundle.main.preferredLocalizations.first ?? "?") + " (" + (Locale.preferredLanguages.first ?? "?") + ")"
        var facts: [CartoucheReport.Fact] = []
        if let games = CartoucheDevice.gameMemoryMiB {
            facts.append(.init("Memory for a game", "\(games) MiB, as Metal says"))
        }
        if let free = freeSpace {
            facts.append(.init("Free on this Mac", CartoucheReport.bytes(free)))
        }
        facts.append(storage())
        return CartoucheReport.Environment(cartouche: builder, basedOn: nil, system: system, device: device,
                                           language: language, facts: facts, app: "Cartouche for Mac", systemName: "macOS")
    }
    #endif

    /// The places the player's storage gives, by their kind alone.
    private static func storage() -> CartoucheReport.Fact {
        let settings = CartoucheStorageSettings.shared
        let places = CartoucheStorageRole.allCases.compactMap { role -> String? in
            guard let server = settings.location(role)?.server else { return nil }
            return "\(role.rawValue) on \(kindName(server.kind))" + (settings.isReadOnly(role) ? " (read-only)" : "")
        }
        return .init("Storage", places.isEmpty ? "none" : places.joined(separator: ", "))
    }

    /// "SMB", as a report names a kind of storage.
    static func kindName(_ kind: CartoucheStorageServer.Kind) -> String {
        switch kind {
        case .smb: return "SMB"
        #if os(iOS)
        case .folder: return "a folder in Files"
        #else
        case .folder: return "a folder of the Mac's"
        #endif
        case .s3: return "S3"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .mac: return "Cartouche on a Mac"
        case .drive: return "Google Drive"
        }
    }

    /// "a games folder on SMB": where a step reads or writes, without a name.
    static func place(_ role: CartoucheStorageRole) -> String {
        guard let server = CartoucheStorageSettings.shared.location(role)?.server else { return "no \(role.rawValue) folder" }
        return "the \(role.rawValue) folder, on \(kindName(server.kind))"
    }

    /// "From: the games folder, on SMB": place(_:) as a step's fact, of
    /// Cartouche's own words alone, which a player's name that is one of
    /// them leaves whole (CartoucheReport.Fact.isOwn).
    static func place(_ role: CartoucheStorageRole, as name: String) -> CartoucheReport.Fact {
        .init(name, place(role), own: true)
    }

    /// iOS's build, or macOS's, "25B72".
    private static let systemBuild: String? = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var build = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else { return nil }
        return String(cString: build)
    }()

    /// The room for a game, as an install reads it (CartoucheFreeSpace).
    private static var freeSpace: Int64? {
        CartoucheFreeSpace.forImportantUsage(at: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    // MARK: The error

    /// The status an error of SMB, S3, FTP, SFTP or Google Drive holds, for
    /// its cause.
    nonisolated static func protocolStatus(_ error: Error) -> CartoucheFailure.ProtocolStatus? {
        #if canImport(SMBClient)
        if let response = error as? ErrorResponse {
            return .init(kind: .smb, status: Int(UInt32(truncatingIfNeeded: response.header.status)))
        }
        #endif
        #if canImport(NIOSSH)
        if let failure = error as? SFTPFailure {
            return .init(kind: .sftp, status: Int(failure.code))
        }
        #endif
        if let failure = error as? CartoucheS3Failure {
            return .init(kind: .s3, status: failure.status, code: failure.code)
        }
        if let failure = error as? FTPFailure {
            return .init(kind: .ftp, status: failure.reply.code)
        }
        if let failure = error as? CartoucheDriveFailure {
            return .init(kind: .drive, status: failure.status, code: failure.reason.isEmpty ? nil : failure.reason)
        }
        if let failure = error as? CartoucheDriveTokenFailure {
            return .init(kind: .drive, status: failure.status, code: failure.code.isEmpty ? nil : failure.code)
        }
        return nil
    }

    /// ERROR as its domains and codes, with what an error of SMB, S3, FTP,
    /// SFTP or Google Drive holds.
    static func describe(_ error: Error) -> String {
        CartoucheReport.describe(error) { error in
            #if canImport(SMBClient)
            if let response = error as? ErrorResponse {
                return String(format: "NTSTATUS 0x%08X", response.header.status)
            }
            #endif
            #if canImport(NIOSSH)
            if let failure = error as? SFTPFailure {
                return "SFTP status \(failure.code)"
            }
            #endif
            if let failure = error as? CartoucheS3Failure {
                return "HTTP \(failure.status) \(failure.code)"
            }
            if let failure = error as? FTPFailure {
                return "FTP \(failure.reply.code)"
            }
            // Google's reason or code, never its message, which may name
            // the player's project or files.
            if let failure = error as? CartoucheDriveFailure {
                return "Google Drive " + (failure.errorDescription ?? "")
            }
            if let failure = error as? CartoucheDriveTokenFailure {
                return "Google sign-in " + (failure.errorDescription ?? "")
            }
            return nil
        }
    }

    // MARK: What a report never holds

    #if os(iOS)
    /// The team's name, which is the player's own on a free account.
    private static let teamName = CartoucheSignature.current().teamName
    #endif

    /// What the player typed since Cartouche opened that their settings do
    /// not hold yet: a server they are adding, the Apple ID of a first
    /// sign-in.
    private static var typed = CartoucheRedaction()

    /// Takes what the player just typed out of reports, as their own: the
    /// SERVERS, NAMES and ACCOUNTS of a form, before its connection works
    /// and its settings are kept. Called before trying them.
    static func redactTyped(servers: [String] = [], names: [String] = [], accounts: [String] = []) {
        typed.servers += servers.filter { !typed.servers.contains($0) }
        typed.names += names.filter { !typed.names.contains($0) }
        typed.accounts += accounts.filter { !typed.accounts.contains($0) }
    }

    /// What the player's settings name: their servers' addresses, the names
    /// of their places, their shared folders and buckets, the paths of their
    /// folders, their user names and access key IDs, their Apple ID and their
    /// team's name, or on the Mac the names of its account; and what they
    /// typed since Cartouche opened.
    static func redaction() -> CartoucheRedaction {
        let settings = CartoucheStorageSettings.shared
        var redaction = typed
        for server in settings.servers {
            redaction.servers.append(server.host)
            redaction.servers.append(contentsOf: server.tailnet ?? [])
            redaction.names.append(server.name)
            redaction.names.append(server.share)
            redaction.accounts.append(server.username)
        }
        redaction.paths = CartoucheStorageRole.allCases.compactMap { settings.place($0)?.path }
        #if os(iOS)
        if let appleID = CartoucheSetup.shared.appleID {
            redaction.accounts.append(appleID)
        }
        if let teamName {
            redaction.accounts.append(teamName)
        }
        #else
        // The Mac's account, which the paths of its folders and the
        // system's messages name: "/Users/lou/…", "Lou Martin".
        redaction.accounts += [NSUserName(), NSFullUserName()]
        #endif
        return redaction
    }
}

// MARK: What the storage's errors stand for

extension CartoucheStorageError: CartoucheDescribedError {
    var failureKind: String { kind.rawValue }

    var failureCause: CartoucheFailure.Cause {
        switch kind {
        case .noSpaceHere: return .noSpace
        case .noSpaceThere: return .storageFull
        case .readOnly: return .storageReadOnly
        case .gameUnreadable: return .fileUnreadable
        case .tooLarge, .listingTooLong, .copyUnreadable, .badAnswer: return .storageAnswer
        case .notInBuild: return .other
        case .noPassword, .keysNeeded, .accountNeeded, .noSavesFolder: return .storageSetup
        case .notAnApp: return .notAnApp
        case .badAddress, .badBucket, .badName: return .storageAddress
        case .signInFailed, .noSubsystem: return .storageServer
        case .folderGone, .notThere: return .storageNotFound
        case .noHostKey, .hostKeyChanged: return .storageHostKey
        case .badClient, .driveOff: return .storageSetup
        case .clientRefused, .noLastingSignIn, .webSignIn: return .storageCredentials
        case .driveScope: return .storagePermission
        case .driveFailed: return .storageServer
        }
    }
}

extension CartoucheStorageOffline: CartoucheDescribedError {
    var failureKind: String { isSignedOut ? "driveSignedOut" : isMac ? "macOffline" : "offline" }
    var failureCause: CartoucheFailure.Cause { .storageOffline }
    var underlyingError: Error? { nil }
}

// MARK: The button under an error

/// Copy the report, under an error: copies the report, which says so for a
/// moment.
@available(iOS 17.0, *)
struct CartoucheReportButton: View {
    let report: CartoucheReport
    @State private var copied = false

    var body: some View {
        Button {
            CartoucheReports.copy(report)
            copied = true
        } label: {
            Label(copied ? CartoucheText.reportCopied : CartoucheText.reportCopy,
                  systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityHint(CartoucheText.reportHint)
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// Says over the console that the report is copied, once its alert has
/// gone.
@available(iOS 17.0, *)
struct CartoucheReportCopiedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(CartoucheText.reportCopied)
                    .font(.subheadline.weight(.semibold))
                Text(CartoucheText.reportCopiedDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
