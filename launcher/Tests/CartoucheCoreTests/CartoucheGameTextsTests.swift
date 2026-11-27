//
//  CartoucheGameTextsTests.swift
//  CartoucheCoreTests
//
//  nxnative's prompts and menu over a game in the language Cartouche
//  speaks (Sources/CartoucheGameTexts.swift): the Mac's words, on the
//  iPhone too.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheGameTextsTests: XCTestCase {
    private typealias Texts = CartoucheGameTexts

    private func lines(_ environment: [String: String], _ variable: String) -> [String]? {
        environment[variable]?.components(separatedBy: "\n")
    }

    /// The Mac's texts, as it gave its games up to 0.16.2
    /// (MacPlayEnvironment.texts): one table now, the same words.
    func testTheMacSaysWhatItSaid() {
        let name = "Mario Kart 8 Deluxe"
        XCTAssertEqual(Texts.environment(game: name, language: "fr", on: .mac), [
            "DM_HOME_QUIT_TEXT": "Maintenez pour quitter\nQuitter Mario Kart 8 Deluxe ?\nLa progression non sauvegardée sera perdue.\nQuitter\nAnnuler",
            "DM_CTRL_PROMPT_TEXT": "{min} joueurs attendus\nAppuyez sur un bouton de chaque manette pour la faire rejoindre.\nJoueurs : {joined} sur {min}\nTerminé\nAnnuler",
        ])
        XCTAssertEqual(Texts.environment(game: name, language: "es", on: .mac), [
            "DM_HOME_QUIT_TEXT": "Mantén pulsado para salir\n¿Salir de Mario Kart 8 Deluxe?\nSe perderá el progreso no guardado.\nSalir\nCancelar",
            "DM_CTRL_PROMPT_TEXT": "Se esperan {min} jugadores\nPulsa un botón de cada mando para que se una.\nJugadores: {joined} de {min}\nHecho\nCancelar",
        ])
        XCTAssertEqual(Texts.environment(game: name, language: "de", on: .mac), [
            "DM_HOME_QUIT_TEXT": "Zum Beenden gedrückt halten\nMario Kart 8 Deluxe beenden?\nNicht gespeicherter Fortschritt geht verloren.\nBeenden\nAbbrechen",
            "DM_CTRL_PROMPT_TEXT": "{min} Spieler erwartet\nDrücke eine Taste auf jedem Controller, um ihn hinzuzufügen.\nSpieler: {joined} von {min}\nFertig\nAbbrechen",
        ])
        // English is nxnative's own on the Mac.
        XCTAssertEqual(Texts.environment(game: name, language: "en", on: .mac), [:])
    }

    /// Up to 0.16.2, a game on the iPhone showed both in English, whatever
    /// Cartouche spoke: 249 sessions in French did.
    func testTheIPhoneGetsThePlayersPromptAndTheMenuInEachLanguage() throws {
        for language in Texts.languages {
            let environment = Texts.environment(game: "Mario Kart 8 Deluxe", language: language, on: .iPhone)
            XCTAssertEqual(Set(environment.keys), ["DM_CTRL_PROMPT_TEXT", "DM_GAME_MENU_TEXT"], language)
            // Five lines, in nxnative's order, with its numbers' places.
            let players = try XCTUnwrap(lines(environment, Texts.playersVariable), language)
            XCTAssertEqual(players.count, 5, language)
            XCTAssertFalse(players.contains(""), language)
            XCTAssertTrue(players[0].contains("{min}"), language)
            XCTAssertTrue(players[2].contains("{joined}") && players[2].contains("{min}"), language)
            // Four lines, none empty: the menu's title names Cartouche,
            // where the game's other settings are.
            let menu = try XCTUnwrap(lines(environment, Texts.menuVariable), language)
            XCTAssertEqual(menu.count, 4, language)
            XCTAssertFalse(menu.contains(""), language)
            XCTAssertTrue(menu[0].contains("Cartouche"), language)
            XCTAssertTrue(menu[3].contains("env.txt"), language)
            // The Home button shows Cartouche's console there: nxnative's
            // iPhone has no quit prompt.
            XCTAssertNil(environment[Texts.quitVariable], language)
        }
    }

    /// The same words on the Mac and on the iPhone, for the prompt both
    /// show.
    func testThePlayersPromptIsTheMacsOnTheIPhone() {
        for language in Texts.languages + ["en"] {
            XCTAssertEqual(Texts.environment(game: "Splatoon 3", language: language, on: .iPhone)[Texts.playersVariable],
                           Texts.environment(game: "Splatoon 3", language: language, on: .mac)[Texts.playersVariable], language)
        }
    }

    /// nxnative's menu says its start screen, which Play skips: in English
    /// too, its title names Cartouche's Game settings, the rest nxnative's
    /// own.
    func testInEnglishTheIPhoneGetsTheMenusTitleAlone() {
        XCTAssertEqual(Texts.environment(game: "Splatoon 3", language: "en", on: .iPhone),
                       ["DM_GAME_MENU_TEXT": "More settings in Cartouche: Game settings"])
    }

    func testTheLanguageIsOneOfTheTextsOrEnglish() {
        XCTAssertEqual(Texts.language(of: "fr"), "fr")
        XCTAssertEqual(Texts.language(of: "fr-CA"), "fr")
        XCTAssertEqual(Texts.language(of: "es-419"), "es")
        XCTAssertEqual(Texts.language(of: "de_CH"), "de")
        XCTAssertEqual(Texts.language(of: "DE"), "de")
        XCTAssertEqual(Texts.language(of: "en"), "en")
        XCTAssertEqual(Texts.language(of: "it"), "en")
        XCTAssertEqual(Texts.language(of: "zh-Hans"), "en")
        XCTAssertEqual(Texts.language(of: nil), "en")
        XCTAssertEqual(Texts.language(of: ""), "en")
    }

    /// Play writes them in the game's data folder at each start, in the
    /// language Cartouche speaks then.
    func testPlayWritesThemInTheGamesDataFolderAtEachStart() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(Texts.written(home: home), [:])

        XCTAssertEqual(try Texts.write(game: "Splatoon 3", language: "fr", home: home), ["DM_CTRL_PROMPT_TEXT", "DM_GAME_MENU_TEXT"])
        XCTAssertEqual(Texts.file, "Library/Cartouche/GameTexts.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(Texts.file).path))
        XCTAssertEqual(Texts.written(home: home), Texts.environment(game: "Splatoon 3", language: "fr", on: .iPhone))

        // Cartouche now speaks English: the French texts go.
        XCTAssertEqual(try Texts.write(game: "Splatoon 3", language: "en", home: home), ["DM_GAME_MENU_TEXT"])
        XCTAssertEqual(Texts.written(home: home), ["DM_GAME_MENU_TEXT": "More settings in Cartouche: Game settings"])

        // The file says its language and its version too.
        let data = try Data(contentsOf: home.appendingPathComponent(Texts.file))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["language"] as? String, "en")
        XCTAssertEqual(plist["version"] as? Int, 1)
    }
}
