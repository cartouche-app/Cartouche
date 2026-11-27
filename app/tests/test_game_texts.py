"""Checks that nxnative's prompt that waits for more players and its gear
menu over a game reach the iPhone's games in the language Cartouche speaks,
in the Mac's words (docs/decisions/179.md):

- one table of the texts, launcher/Sources/CartoucheGameTexts.swift, which
  the Mac's start of a game reads too (builder/mac, MacPlayEnvironment):
  the Mac has no table of its own;
- Play writes them in the game's data folder, behind the console and in
  Cartouche's place alike, and Cartouche's code in the game's process
  (launcher/Guest), which app/scripts/prepare.sh copies into
  LiveContainerShared, reads that file, under the same name, and sets those
  variables alone, never one the game's env.txt or its start set;
- it acts in nxnative's games only, never in Cartouche's own screens or the
  built-in SideStore, and as the game has finished launching, once
  nxnative's main.m has read the game's env.txt files;
- the part that sets them needs no LiveContainer, so that the launcher's
  harness runs it, and the harness runs as it changes;
- the menu says Cartouche's own words: its Game settings button, and its
  note of a setting an env.txt file sets.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUEST = ROOT / "launcher" / "Guest"
START = GUEST / "CartoucheGameTexts.m"
ENVIRONMENT = GUEST / "CartoucheGameTextsEnvironment.m"
HEADER = GUEST / "CartoucheGameTextsEnvironment.h"
TEXTS = ROOT / "launcher" / "Sources" / "CartoucheGameTexts.swift"
ACTIONS = ROOT / "launcher" / "Sources" / "CartoucheGameActions.swift"
CATALOG = ROOT / "launcher" / "Sources" / "Cartouche.xcstrings"
MAC_PLAY = ROOT / "builder" / "mac" / "Sources" / "BuilderKit" / "MacPlay.swift"
HARNESS = ROOT / "launcher" / "Harness"
WORKFLOW = ROOT / ".github" / "workflows" / "harness.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def c_function(source: str, name: str) -> str:
    """The body of the C function NAME in SOURCE, up to its closing brace at
    the start of a line."""
    match = re.search(rf"\n(?:static )?[\w *<>]+\b{name}\([^)]*\) \{{\n(.*?)\n\}}\n", source, re.S)
    if not match:
        raise AssertionError(f"no function {name}")
    return match.group(1)


def swift_strings(text: str) -> list:
    """The string literals of a Swift array, with \\u{00A0} as the
    character."""
    return [re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), s)
            for s in re.findall(r'"((?:[^"\\]|\\.)*)"', text)]


def menu_lines(language: str) -> list:
    source = read(TEXTS)
    case = '_' if language == "en" else f'"{language}"'
    match = re.search(rf"case \(menuVariable, {re.escape(case)}\):\n(?:\s*//[^\n]*\n)*\s*return \[(.*?)\]\n", source, re.S)
    if not match:
        raise AssertionError(f"no menu for {language}")
    return swift_strings(match.group(1))


def catalog(key: str, language: str) -> str:
    entry = json.loads(read(CATALOG))["strings"][key]
    return entry["localizations"][language]["stringUnit"]["value"]


class GameTextsTest(unittest.TestCase):
    def test_the_game_reads_the_file_play_writes(self):
        written = re.search(r'public static let file = "([^"]+)"', read(TEXTS)).group(1)
        self.assertEqual(written, "Library/Cartouche/GameTexts.plist")
        self.assertEqual(re.search(r'CartoucheGameTextsFile = @"([^"]+)"', read(ENVIRONMENT)).group(1), written)
        # Play writes it for nxnative's games, behind the console and in
        # Cartouche's place alike, in the language Cartouche speaks.
        actions = read(ACTIONS)
        prepare = re.search(r"private static func prepareStart\(.*?\n    \}\n", actions, re.S).group(0)
        self.assertIn("giveTexts(of: app, container: container)", prepare)
        self.assertIn("CartoucheGameTexts.language(of: CartoucheText.bundle.preferredLocalizations.first)", actions)
        self.assertIn("CartoucheGameTexts.write(game: app.displayName, language: language, home: container.containerURL)", actions)

    def test_it_sets_nxnatives_texts_alone_and_never_over_the_games_own(self):
        variables = re.findall(r'@"(DM_\w+)"', c_function(read(ENVIRONMENT), "CartoucheGameTextsVariables"))
        self.assertEqual(variables, ["DM_CTRL_PROMPT_TEXT", "DM_GAME_MENU_TEXT"])
        iphone = re.search(r"case \.iPhone: return \[(.*?)\]", read(TEXTS)).group(1)
        names = dict(re.findall(r'public static let (\w+Variable) = "(DM_\w+)"', read(TEXTS)))
        self.assertEqual([names[n.strip()] for n in iphone.split(",")], variables, "the iPhone's variables, in the same order")
        apply = c_function(read(ENVIRONMENT), "CartoucheGameTextsApply")
        self.assertIn("for (NSString *variable in CartoucheGameTextsVariables()) {", apply)
        self.assertIn("if (getenv(variable.UTF8String)) continue;", apply)
        self.assertIn("setenv(variable.UTF8String, text.UTF8String, 0)", apply)
        self.assertEqual(len(re.findall(r"\bsetenv\(", apply)), 1)

    def test_it_acts_in_nxnatives_games_alone_once_they_have_launched(self):
        start = read(START)
        is_game = c_function(start, "CartoucheGameTextsIsGame")
        self.assertIn("if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore) return NO;", is_game)
        self.assertIn('stringByAppendingPathComponent:@"dm"]', is_game)
        self.assertIn('infoDictionary[@"DMLanguage"]', is_game)
        begins = c_function(start, "CartoucheGameTextsStart")
        self.assertIn('getenv("HOME")', begins)
        self.assertIn("if (!home || !CartoucheGameTextsIsGame()) return;", begins)
        self.assertIn("CartoucheGameTextsApply(@(home))", begins)
        self.assertIn('addObserverForName:@"UIApplicationDidFinishLaunchingNotification"', start)
        self.assertRegex(start, r"queue:nil\n")

    def test_it_links_neither_uikit_nor_livecontainer_where_the_harness_runs_it(self):
        for path in (START, ENVIRONMENT, HEADER):
            with self.subTest(file=path.name):
                self.assertIsNone(re.search(r"@import UIKit|#(?:import|include) <UIKit", read(path)))
        self.assertNotIn("utils.h", read(ENVIRONMENT) + read(HEADER))
        self.assertNotIn("NSUserDefaults", read(ENVIRONMENT))

    def test_the_harness_runs_the_part_that_sets_them(self):
        project = read(HARNESS / "project.yml")
        self.assertIn("- path: ../Guest/CartoucheGameTextsEnvironment.m", project)
        self.assertNotIn("../Guest/CartoucheGameTexts.m", project)
        self.assertIn('#import "../../Guest/CartoucheGameTextsEnvironment.h"', read(HARNESS / "Sources" / "Harness-Bridging-Header.h"))
        self.assertIn("func testPlayGivesTheGameNxnativesTextsInCartouchesLanguage()", read(HARNESS / "Tests" / "PlayTests.swift"))
        workflow = read(WORKFLOW)
        self.assertEqual(workflow.count('"launcher/Guest/CartoucheGameTextsEnvironment.*"'), 2, "on main and on pull requests")
        self.assertIn("'launcher/Guest/CartoucheGameTextsEnvironment.*'", workflow, "in what a pull request's run is remembered by")

    def test_the_mac_reads_the_same_table(self):
        mac = read(MAC_PLAY)
        self.assertIn("CartoucheGameTexts.environment(game: name, language: language, on: .mac)", mac)
        for words in ("Maintenez pour quitter", "joueurs attendus", "Mantén pulsado", "Spieler erwartet"):
            self.assertNotIn(words, mac, "one table, in CartoucheGameTexts.swift")

    def test_the_menu_says_cartouches_own_words(self):
        for language in ("en", "fr", "es", "de"):
            with self.subTest(language=language):
                lines = menu_lines(language)
                # Its title names Cartouche's Game settings: Play skips
                # nxnative's start screen, which its own title names.
                self.assertIn(catalog("action.gameSettings", language), lines[0])
                self.assertIn("Cartouche", lines[0])
                if language == "en":
                    self.assertEqual(len(lines), 1, "the rest is nxnative's own English")
                    continue
                self.assertEqual(len(lines), 4)
                self.assertEqual(lines[3], catalog("settings.fixed", language))
                self.assertIn(catalog("setting.section.controls", language).lower(), lines[1].lower())


if __name__ == "__main__":
    unittest.main()
