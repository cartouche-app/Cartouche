//
//  CartoucheFreeSpace.swift
//  Cartouche
//
//  The room left on a disk, read again at each question. Foundation keeps
//  the values a URL has read, and gives them back to that URL's next
//  readings for a while. LCPath.docPath, a URL kept for the app's life, so
//  answered an install with the room the iPhone had at the one before, 49
//  seconds earlier: 9.3 GB, though the player had freed 64 GB in between,
//  and the report of that second, read through a URL of its own, counted
//  73.43 GB (cartouche-reports #10, 15 November 2026). Here, each reading
//  goes through a URL of the same place made for it, which has read nothing
//  yet: the iPhone's installs and its reports, and the room a Mac tells an
//  iPhone over the bridge (builder/mac, BridgeServer.swift). Foundation
//  only, so that swift test checks it on a Mac (launcher/Package.swift).
//

import Foundation

public enum CartoucheFreeSpace {
    /// The room on the disk that holds URL for what the player asks for,
    /// such as a game: what is free there, with what iOS or macOS would
    /// purge for it, as Settings and the Finder count it. nil when the
    /// system cannot say.
    public static func forImportantUsage(at url: URL) -> Int64? {
        #if canImport(Darwin)
        let values = try? unread(url).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
        #else
        // Only Apple's systems purge for an app.
        return available(at: url)
        #endif
    }

    /// What is free on the disk that holds URL, without what the system
    /// could purge. nil when the system cannot say.
    public static func available(at url: URL) -> Int64? {
        let values = try? unread(url).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// URL's place, as a URL that has read nothing yet.
    private static func unread(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: url.hasDirectoryPath)
    }
}
