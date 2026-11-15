//
//  GalleryTranslations.swift
//  CartoucheGallery
//
//  The iPhone's translations of what testers wrote on a game's sheet, for
//  the scenario of the testers' results (-GalleryCategory results): the
//  simulator cannot translate, so the gallery keeps them as the iPhone
//  would (GalleryApp.swift, showTranslations).
//

/// What testers wrote on the sheet of Mario Kart World
/// (catalog/games/0400C3F00006E000.json), as the iPhone translates it into
/// French.
enum GalleryTranslations {
    static let french = [
        "nxnative main with the switch2ios patches (0d9b6358)":
            "nxnative main avec les correctifs de switch2ios (0d9b6358)",
        "Ran smoothly at 1080p in handheld mode. Memory peak not recorded yet.":
            "A tourné de façon fluide en 1080p en mode portable. Pic de mémoire pas encore enregistré.",
    ]
}
