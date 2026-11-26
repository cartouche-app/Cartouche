//
//  CartoucheTextMods.swift
//  Cartouche
//
//  The words of a game's mods (CartoucheModsView.swift, CartoucheMods.swift),
//  in Cartouche.xcstrings with the others (CartoucheText.swift). The console
//  on the Mac says its own of a few (builder/mac/console/strings.json).
//

import Foundation

extension CartoucheText {
    // MARK: The page

    static var modsTitle: String { s("mods.title", "Mods") }
    static var modsNone: String { s("mods.summary.none", "None") }
    static func modsOn(_ count: Int) -> String {
        count == 1 ? s("mods.summary.one", "1 on") : f("mods.summary.many", "%lld on", count)
    }
    static var modsIntro: String { s("mods.intro", "A mod changes the game’s textures, texts, music or levels: the game reads its files in place of its own. Add one from Files, as its folder or its ZIP.") }
    static var modsAdd: String { s("mods.add", "Add a mod") }
    static var modsRunning: String { s("mods.running", "Quit the game to change its mods.") }
    static var modsEmpty: String { s("mods.empty", "No mod for this game yet.") }
    static var modsOrderFooter: String { s("mods.order.footer", "Where two mods change the same file, the one higher up wins. Changes take effect at the game’s next start.") }
    static func modsFiles(_ count: Int, _ size: String) -> String {
        count == 1 ? f("mods.files.one", "1 file, %@", size) : f("mods.files.many", "%lld files, %@", count, size)
    }
    static func modsOtherVersion(_ version: String) -> String { f("mods.otherVersion", "Added with version %@ of the game: a mod made for one version may not work with another.", version) }
    static var modsMoveUp: String { s("mods.moveUp", "Move up") }
    static var modsMoveDown: String { s("mods.moveDown", "Move down") }
    static var modsDelete: String { s("mods.delete", "Delete") }
    static var modsDeleteQuestion: String { s("mods.delete.question", "Delete this mod?") }
    static var modsDeleteMessage: String { s("mods.delete.message", "Its files are deleted from this iPhone.") }

    // MARK: What came

    static var modsAddedOne: String { s("mods.added.one", "The mod is added and turned on: it takes effect at the game’s next start.") }
    static func modsAddedMany(_ count: Int) -> String { f("mods.added.many", "%lld mods are added, turned off: turn on those you want.", count) }
    static func modsNotAdded(_ name: String, _ why: String) -> String { f("mods.notAdded", "Not added: %1$@. %2$@", name, why) }

    // MARK: What stops a mod

    static var modsNoRomfs: String { s("mods.problem.noRomfs", "There is no romfs folder in it, where a mod keeps its files: choose the mod’s folder or its ZIP.") }
    static var modsEmptyRomfs: String { s("mods.problem.empty", "Its romfs folder holds no file.") }
    static var modsCode: String { s("mods.problem.code", "It changes the game’s code too, in its exefs folder: iOS runs only the code signed with the game, and the game would stop on a black screen. Only mods that change the game’s files work here.") }
    static func modsOtherGame(_ game: String) -> String { f("mods.problem.otherGame", "It is a mod of another game: %@.", game) }
    static var modsUnsafe: String { s("mods.problem.unsafe", "It holds a link or a path that leads out of it: Cartouche does not copy it.") }
    static func modsTooMany(_ count: Int) -> String { f("mods.problem.tooMany", "%lld mods are on already: turn one off first.", count) }
    static func modsNoRoom(_ needed: String, _ free: String) -> String { f("mods.problem.noRoom", "This iPhone does not have room for it: it needs %1$@, and %2$@ is free.", needed, free) }
    static var modsUnreadable: String { s("mods.problem.unreadable", "It is not a ZIP Cartouche can read.") }

    // MARK: What failed

    static var modsReadFailed: String { s("mods.failed.read", "The mod was not read") }
    static var modsAddFailed: String { s("mods.failed.add", "The mod was not added") }
    static var modsChangeFailed: String { s("mods.failed.change", "The mods were not changed") }
    static var modsDeleteFailed: String { s("mods.failed.delete", "The mod was not deleted") }
}
