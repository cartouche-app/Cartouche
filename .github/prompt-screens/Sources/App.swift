//
//  App.swift
//  PromptScreens
//
//  Screenshots of nxnative's own prompt that waits for more players and of
//  its gear menu over a game on the iPhone, with the texts Cartouche gives
//  a game or without them, for PR #367 alone, removed before it merges.
//  The texts go the way they go in a game: CartoucheGameTexts.write into a
//  data folder, as Play writes them, then CartoucheGameTextsApply from that
//  folder, as Cartouche's code in the game's process puts them in its
//  environment. The menu is nxnative's GameMenu.swift at its commit
//  dc9c2374 (MIT License, Copyright (c) 2026 seedds), with the settings of
//  its docs/settings.md, "In-game menu", in place of a game's list.
//
//  Arguments: -show prompt|menu, -texts none|en|fr|es|de.
//

import UIKit

// nxnative's GameMenu.swift, unchanged.
enum GameMenuText: Int, CaseIterable {
    case moreSettings, controllerLayout, tap, fixedSetting

    var english: String {
        switch self {
        case .moreSettings: return "More settings on the start screen"
        case .controllerLayout: return "Controller layout"
        case .tap: return "Tap"
        case .fixedSetting: return "Set in env.txt"
        }
    }

    static func line(_ label: GameMenuText, in payload: String?) -> String {
        let lines = (payload ?? "").replacingOccurrences(of: "\\n", with: "\n").components(separatedBy: "\n")
        guard label.rawValue < lines.count else { return label.english }
        let text = lines[label.rawValue].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? label.english : text
    }

    var text: String { Self.line(self, in: getenv("DM_GAME_MENU_TEXT").flatMap { String(validatingCString: $0) }) }
}

/// A setting of the menu, as nxnative's launcher.json names it.
private struct Row {
    let label: String
    let options: [String]
    let current: Int
    let fixed: Bool
    var toggle: Bool { options.isEmpty }
}

private func gameMenu() -> UIMenu {
    let title = GameMenuText.moreSettings.text
    return UIMenu(title: title, children: [UIDeferredMenuElement.uncached { done in done(gameMenuItems()) }])
}

private func gameMenuItems() -> [UIMenuElement] {
    let names = ["2D", "3D", GameMenuText.tap.text]
    let layouts = (0..<3).map { l in UIAction(title: names[l], state: l == 0 ? .on : .off) { _ in } }
    let layout = UIMenu(title: GameMenuText.controllerLayout.text, options: .singleSelection, children: layouts)
    let game = [Row(label: "Console mode", options: ["Docked", "Handheld"], current: 1, fixed: false),
                Row(label: "Picture", options: ["Sharp", "Smooth"], current: 0, fixed: false),
                Row(label: "Rotation", options: ["Auto", "Landscape", "Portrait"], current: 0, fixed: true),
                Row(label: "Frame-rate counter", options: [], current: 0, fixed: false)]
    let controls = [Row(label: "Touch feedback", options: [], current: 1, fixed: false),
                    Row(label: "Game rumble", options: [], current: 1, fixed: false)]
    return [UIMenu(options: .displayInline, children: game.map(gameMenuRow)),
            UIMenu(options: .displayInline, children: [layout] + controls.map(gameMenuRow))]
}

private func gameMenuRow(_ s: Row) -> UIMenuElement {
    let attributes: UIMenuElement.Attributes = s.fixed ? .disabled : []
    if s.toggle {
        let a = UIAction(title: s.label, attributes: attributes, state: s.current == 1 ? .on : .off) { _ in }
        if s.fixed { a.subtitle = GameMenuText.fixedSetting.text }
        return a
    }
    let current = s.options[s.current]
    let actions = s.options.enumerated().map { i, o in UIAction(title: o, attributes: attributes, state: i == s.current ? .on : .off) { _ in } }
    return UIMenu(title: s.label, subtitle: s.fixed ? "\(current) · \(GameMenuText.fixedSetting.text)" : nil, options: .singleSelection, children: actions)
}

private func argument(_ name: String) -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let i = arguments.firstIndex(of: "-" + name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

final class GameViewController: UIViewController {
    private let gear = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor(red: 0.16, green: 0.24, blue: 0.36, alpha: 1).cgColor,
                           UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).cgColor]
        gradient.frame = view.bounds
        view.layer.addSublayer(gradient)
        gear.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
        gear.tintColor = UIColor(white: 1, alpha: 0.85)
        gear.backgroundColor = UIColor(white: 1, alpha: 0.12)
        gear.layer.cornerRadius = 22
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.menu = gameMenu()
        gear.showsMenuAsPrimaryAction = true
        view.addSubview(gear)
        NSLayoutConstraint.activate([gear.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     gear.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                                     gear.widthAnchor.constraint(equalToConstant: 44), gear.heightAnchor.constraint(equalToConstant: 44)])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            if argument("show") == "menu" {
                openMenu()
            } else if let window = view.window {
                NxShowControllerPrompt(window, 2, 4, 1)
            }
        }
    }

    /// Opens the gear's menu as a tap does.
    private func openMenu() {
        let present = NSSelectorFromString("_presentMenuAtLocation:")
        if let interaction = gear.contextMenuInteraction, interaction.responds(to: present) {
            typealias Present = @convention(c) (AnyObject, Selector, CGPoint) -> Void
            let call = unsafeBitCast(interaction.method(for: present), to: Present.self)
            call(interaction, present, CGPoint(x: gear.bounds.midX, y: gear.bounds.midY))
            NSLog("prompt-screens: menu opened by _presentMenuAtLocation:")
        } else {
            gear.performPrimaryAction()
            NSLog("prompt-screens: menu opened by performPrimaryAction")
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // As Play, then the game's process.
        if let language = argument("texts"), language != "none" {
            let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("game-home", isDirectory: true)
            do {
                let written = try CartoucheGameTexts.write(game: "Mario Kart 8 Deluxe", language: language, home: home)
                let set = CartoucheGameTextsApply(home.path)
                NSLog("prompt-screens: \(language): written \(written), set \(set)")
            } catch {
                NSLog("prompt-screens: \(error)")
            }
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
