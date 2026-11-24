//
//  CartoucheBackup.swift
//  Cartouche
//
//  The games Cartouche installs stay out of the iPhone's backups, in iCloud
//  or on a computer (decision 153, issue #302): each takes gigabytes, which
//  fill the player's iCloud, and installs again from the player's storage,
//  while iOS shows no switch for Cartouche under iCloud Backup that would
//  let the player leave it out. A game's saves, in its data folder, stay in
//  the backups, as all else of Cartouche's does.
//
//  iOS leaves out a file or a folder marked so (isExcludedFromBackup), and
//  all that a folder marked so holds. The mark belongs to the item it was
//  set on: an app moved into the marked folder is left out with it, but one
//  in another folder has only its own mark, and a folder removed and made
//  again comes without one. So Cartouche marks its folder of games and each
//  game's app as it installs it, and again as it starts, for the games
//  installed before it marked them and a folder made again since
//  (CartoucheGameActions.leaveGamesOutOfBackups).
//

import Foundation

enum CartoucheBackup {
    /// Marks each of URLS, a file, or a folder with all it holds, as left
    /// out of the backups. Returns those it could not mark: gone, or on a
    /// disk that keeps no such mark.
    @discardableResult
    static func leaveOut(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            var marked = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do {
                try marked.setResourceValues(values)
                return false
            } catch {
                return true
            }
        }
    }

    /// Whether URL itself is marked as left out of the backups, as the disk
    /// says it now.
    static func isLeftOut(_ url: URL) -> Bool {
        var read = url
        read.removeAllCachedResourceValues()
        return (try? read.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
    }
}
