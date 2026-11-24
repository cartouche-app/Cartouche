//
//  AppName.swift
//  Cartouche on the Mac
//
//  The Mac's app is Cartouche, as on the iPhone. Until it was renamed it
//  was Cartouche Builder, in Cartouche Builder.app, and a copy already
//  installed updates itself in that same place (Updater.swift replaces the
//  app where it is). So the first start of a renamed version there moves
//  the app to Cartouche.app beside it and opens it again from there, before
//  anything else starts: the Finder, the Dock, Launchpad and Spotlight then
//  say Cartouche too. Its settings, games and builds stay where they are,
//  in ~/Library/Application Support/Cartouche Builder (Engine.swift).
//
//  The app stays where it is when it cannot move: on its disk image, in a
//  folder only an administrator may change, or beside a Cartouche.app
//  already there. Its menus and windows say Cartouche all the same.
//

import Foundation

public enum AppName {
    /// What the app is called, everywhere it is shown.
    public static let name = "Cartouche"
    /// Its folder.
    public static let bundle = "Cartouche.app"
    /// Its folder until it was renamed.
    public static let former = "Cartouche Builder.app"

    /// Where the app at APP moves: Cartouche.app beside it, when it is still
    /// Cartouche Builder.app in a folder the player may change and nothing
    /// is there under that name yet; nil when it stays.
    public static func destination(for app: URL, manager: FileManager = .default) -> URL? {
        guard app.lastPathComponent == former else { return nil }
        let parent = app.deletingLastPathComponent()
        let renamed = parent.appendingPathComponent(bundle, isDirectory: true)
        guard manager.isWritableFile(atPath: parent.path),
              !manager.fileExists(atPath: renamed.path) else { return nil }
        return renamed
    }

    /// Moves the app at APP to Cartouche.app beside it, where it may: its
    /// new place, or nil when it stays where it is.
    @discardableResult
    public static func move(_ app: URL, manager: FileManager = .default) -> URL? {
        guard let renamed = destination(for: app, manager: manager) else { return nil }
        do {
            try manager.moveItem(at: app, to: renamed)
        } catch {
            return nil
        }
        return renamed
    }

    /// What the copy at its new place is opened with: the arguments this
    /// one had (--background after an update installed by itself), and
    /// --opens-at-login when it opened at login, which it then asks again
    /// for its new place.
    public static func arguments(from arguments: [String], opensAtLogin: Bool) -> [String] {
        var kept = Array(arguments.dropFirst()).filter { $0 != openedAtLogin }
        if opensAtLogin { kept.append(openedAtLogin) }
        return kept
    }

    /// The argument that says the app opened at login before it moved.
    public static let openedAtLogin = "--opens-at-login"

    /// Opens APP with ARGUMENTS once this process has ended.
    public static func openAgain(_ app: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let script = "pid=$1; app=$2; shift 2; while /bin/kill -0 \"$pid\" 2>/dev/null; do /bin/sleep 0.3; done; "
            + "if [ $# -gt 0 ]; then /usr/bin/open \"$app\" --args \"$@\"; else /usr/bin/open \"$app\"; fi"
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
