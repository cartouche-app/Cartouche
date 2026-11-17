//
//  Probe.swift
//  Research for the pull request of the builder's words after the console
//  in light mode (17 November), removed before it is merged.
//
//  A window as the app's: the switch at the top, the builder (a sidebar's
//  list and a page of cards) or the console, dark, under it. `Probe
//  STRATEGY FOLDER` opens it on the builder, the Mac in light mode, takes
//  its picture, shows the console, takes its picture, shows the builder
//  again and takes its picture, then has the app's appearance changed and
//  changed back, as macOS does when the player changes theirs, and takes a
//  last one. It says how far each picture of the builder is from the first,
//  and the colour scheme SwiftUI gave each part each time. `Probe --compare
//  A B` says how far picture B is from picture A.
//

import AppKit
import ScreenCaptureKit
import SwiftUI

/// How the console's window is made dark.
enum Strategy: String, CaseIterable {
    /// The app's: preferredColorScheme(.dark) on the console.
    case preferred
    /// The window's appearance, set before the switch, outside SwiftUI's
    /// updates.
    case windowFirst
    /// A view of the console's that makes its window dark as it comes in,
    /// and gives it back its appearance as it goes, during SwiftUI's update.
    case viewDuring
    /// The same, just after SwiftUI's update.
    case viewAfter
    /// preferredColorScheme always said: dark for the console, the Mac's for
    /// the builder.
    case explicit
}

@main
enum Main {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "--compare" {
            Compare.run(arguments[2], arguments[3])
            return
        }
        ProbeApp.main()
    }
}

struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @StateObject private var probe = Probe.shared

    var body: some Scene {
        Window("Probe", id: "main") {
            Root()
                .environmentObject(probe)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 660)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await Steps.run() }
    }
}

@MainActor
final class Probe: ObservableObject {
    static let shared = Probe()

    @Published var console = false
    let strategy: Strategy = CommandLine.arguments.dropFirst().compactMap(Strategy.init(rawValue:)).first ?? .preferred
    /// The colour scheme each part's views last had, as SwiftUI gave it.
    static var seen: [String: ColorScheme] = [:]

    func show(console: Bool) {
        if strategy == .windowFirst, let window = Steps.window {
            window.appearance = console ? NSAppearance(named: .darkAqua) : nil
        }
        self.console = console
    }
}

struct Root: View {
    @EnvironmentObject private var probe: Probe

    var body: some View {
        let content = Group {
            if probe.console {
                ConsoleStandIn()
            } else {
                BuilderStandIn()
            }
        }
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Afficher", selection: Binding(get: { probe.console }, set: { probe.show(console: $0) })) {
                    Text("Console").tag(true)
                    Text("Builder").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        if probe.strategy == .explicit {
            content.preferredColorScheme(probe.console ? .dark : Steps.macScheme)
        } else {
            content
        }
    }
}

struct ConsoleStandIn: View {
    @EnvironmentObject private var probe: Probe

    var body: some View {
        let page = NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Accueil")
                    .font(.largeTitle.weight(.bold))
                Text("Vos jeux sur ce Mac")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    ForEach(["Donkey Kong Bananza", "Mario Kart World", "Link's Awakening"], id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                                .frame(width: 160, height: 220)
                            Text(name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("12 h de jeu")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 160)
                    }
                }
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SchemeProbe(part: "console"))
        }
        switch probe.strategy {
        case .preferred:
            page.preferredColorScheme(.dark)
        case .viewDuring:
            page.background(DarkWindow(after: false))
        case .viewAfter:
            page.background(DarkWindow(after: true))
        case .windowFirst, .explicit:
            page
        }
    }
}

struct BuilderStandIn: View {
    @State private var chosen: String? = "Bibliothèque"
    private let pages = ["Bibliothèque", "Constructions", "Stockage", "iPhone", "Outils du Mac"]

    var body: some View {
        NavigationSplitView {
            List(selection: $chosen) {
                ForEach(pages, id: \.self) { page in
                    Label(page, systemImage: "square.grid.2x2")
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("nxnative 6c3aeb3a")
                        .font(.caption.weight(.semibold))
                    Text("Vérifié il y a 2 heures")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bibliothèque")
                        .font(.largeTitle.weight(.bold))
                    Text("Vos jeux, et ce que nxnative a amélioré pour eux")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    ForEach(0..<4) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mario Kart 8 Deluxe, \(index + 1)")
                                .font(.headline)
                            Text("nxnative a modifié son profil : 3 commits")
                                .foregroundStyle(.secondary)
                            Button("Reconstruire") {}
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
                .padding(28)
            }
            .background(SchemeProbe(part: "builder"))
        }
        .toolbar(removing: .title)
    }
}

/// Keeps the colour scheme SwiftUI gives the views around it.
struct SchemeProbe: View {
    let part: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .onAppear { Probe.seen[part] = scheme }
            .onChange(of: scheme) { _, scheme in Probe.seen[part] = scheme }
    }
}

/// Makes the window it is in dark while it is there, and gives the window
/// back the appearance it had as it leaves: at once, or AFTER SwiftUI's
/// update.
struct DarkWindow: NSViewRepresentable {
    let after: Bool

    func makeNSView(context: Context) -> DarkWindowView { DarkWindowView(after: after) }
    func updateNSView(_ view: DarkWindowView, context: Context) {}
}

final class DarkWindowView: NSView {
    private let after: Bool
    private weak var darkened: NSWindow?
    private var before: NSAppearance?

    init(after: Bool) {
        self.after = after
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let darkened, darkened !== window {
            let before = self.before
            change { darkened.appearance = before }
            self.darkened = nil
        }
        if let window, darkened == nil {
            before = window.appearance
            darkened = window
            change { window.appearance = NSAppearance(named: .darkAqua) }
        }
    }

    private func change(_ action: @escaping () -> Void) {
        if after {
            DispatchQueue.main.async(execute: action)
        } else {
            action()
        }
    }
}

@MainActor
enum Steps {
    static var window: NSWindow?
    static var macScheme: ColorScheme = .light
    static let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { $0.hasPrefix("/") }
                                ?? FileManager.default.currentDirectoryPath)

    static func run() async {
        say("the Mac's own appearance: \(NSApp.effectiveAppearance.name.rawValue)")
        // The Mac in light mode, as the player's was.
        NSApp.appearance = NSAppearance(named: .aqua)
        guard let window = await mainWindow() else {
            say("✗ the window never opened")
            exit(2)
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        let first = await picture(window, "1-builder")
        say("the builder: \(state(window))")
        Probe.shared.show(console: true)
        try? await Task.sleep(for: .seconds(2))
        _ = await picture(window, "2-console")
        say("the console: \(state(window))")
        Probe.shared.show(console: false)
        try? await Task.sleep(for: .seconds(2))
        let after = await picture(window, "3-builder-after-the-console")
        say("the builder after the console: \(state(window))")
        if let first, let after { say("  against the first picture: " + Compare.describe(first, after)) }
        // What macOS does when the player changes theirs: the app's
        // appearance changes, and changes back.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? await Task.sleep(for: .seconds(1))
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .seconds(2))
        let nudged = await picture(window, "4-builder-after-the-macs-appearance-changed")
        say("the builder after the app's appearance changed and changed back: \(state(window))")
        if let first, let nudged { say("  against the first picture: " + Compare.describe(first, nudged)) }
        // The console again, then the builder, a second time.
        Probe.shared.show(console: true)
        try? await Task.sleep(for: .seconds(2))
        Probe.shared.show(console: false)
        try? await Task.sleep(for: .seconds(2))
        let again = await picture(window, "5-builder-after-the-console-again")
        say("the builder after the console, again: \(state(window))")
        if let first, let again { say("  against the first picture: " + Compare.describe(first, again)) }
        exit(0)
    }

    static func state(_ window: NSWindow) -> String {
        let seen = Probe.seen.map { "\($0.key) \($0.value == .dark ? "dark" : "light")" }.sorted().joined(separator: ", ")
        return "window \(window.appearance?.name.rawValue ?? "nil"), effective \(window.effectiveAppearance.name.rawValue); "
            + "SwiftUI's schemes: \(seen)"
    }

    private static func mainWindow() async -> NSWindow? {
        for _ in 0..<150 {
            if let window = NSApp.windows.first(where: { $0.isVisible && ($0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "Probe") }) {
                return window
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// The window as the window server shows it, else as AppKit draws it;
    /// saved as STRATEGY-NAME.png in the folder.
    static func picture(_ window: NSWindow, _ name: String) async -> CGImage? {
        var image: CGImage?
        do {
            let content = try await SCShareableContent.currentProcess
            if let shown = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let filter = SCContentFilter(desktopIndependentWindow: shown)
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = Int((filter.contentRect.width * scale).rounded())
                configuration.height = Int((filter.contentRect.height * scale).rounded())
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } else {
                say("ScreenCaptureKit does not list the window")
            }
        } catch {
            say("ScreenCaptureKit: \(error.localizedDescription)")
        }
        if image == nil, let view = window.contentView?.superview, let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: drawn)
            image = drawn.cgImage
            say("\(name): drawn by AppKit")
        }
        if let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: folder.appendingPathComponent("\(Probe.shared.strategy.rawValue)-\(name).png"))
        }
        return image
    }

    static func say(_ text: String) {
        FileHandle.standardError.write(Data("probe \(Probe.shared.strategy.rawValue): \(text)\n".utf8))
    }
}

enum Compare {
    static func pixels(_ image: CGImage) -> (width: Int, height: Int, bytes: [UInt8]) {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (width, height, bytes)
    }

    static func luminance(_ bytes: [UInt8], _ index: Int) -> Int {
        (Int(bytes[index]) * 54 + Int(bytes[index + 1]) * 183 + Int(bytes[index + 2]) * 19) >> 8
    }

    /// The share of the pixels whose luminance changed by more than a
    /// quarter, where, and the share of dark pixels in each.
    static func describe(_ first: CGImage, _ second: CGImage) -> String {
        let a = pixels(first)
        let b = pixels(second)
        guard a.width == b.width, a.height == b.height else { return "sizes differ: \(a.width)×\(a.height), \(b.width)×\(b.height)" }
        var changed = 0
        var darkA = 0
        var darkB = 0
        var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let index = (y * a.width + x) * 4
                let la = luminance(a.bytes, index)
                let lb = luminance(b.bytes, index)
                if la < 90 { darkA += 1 }
                if lb < 90 { darkB += 1 }
                if abs(la - lb) > 64 {
                    changed += 1
                    box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
                }
            }
        }
        let total = Double(a.width * a.height)
        func percent(_ count: Int) -> String { String(format: "%.2f %%", Double(count) / total * 100) }
        let area = changed == 0 ? "" : " (x \(box.minX)…\(box.maxX), y \(box.minY)…\(box.maxY) of \(a.width)×\(a.height))"
        return "\(percent(changed)) of the pixels changed\(area); dark pixels \(percent(darkA)), then \(percent(darkB))"
    }

    static func run(_ first: String, _ second: String) {
        guard let a = NSImage(contentsOfFile: first)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let b = NSImage(contentsOfFile: second)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("unreadable: \(first) or \(second)")
            exit(2)
        }
        print("\(URL(fileURLWithPath: second).lastPathComponent) against \(URL(fileURLWithPath: first).lastPathComponent): " + describe(a, b))
        exit(0)
    }
}
