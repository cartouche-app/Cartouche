"""Checks that Keep other apps' sound (System › While a game runs) reaches
the game's process, and only there (docs/decisions/168.md):

- Cartouche's code in the game's process (launcher/Guest), which
  app/scripts/prepare.sh copies into LiveContainerShared, reads the file
  Play writes in the game's data folder (launcher/Sources/
  CartoucheOtherAudio.swift), under the same name and key;
- it acts in nxnative's games only, never in Cartouche's own screens or the
  built-in SideStore, and only as the game has finished launching, before
  the scene where nxnative sets its audio session;
- it mixes every way a game sets its category, with the option's own value,
  for the categories that take it, and links neither AVFAudio nor UIKit,
  which LiveContainerShared would load in every process of Cartouche's;
- the part that mixes needs no LiveContainer, so that the launcher's
  harness runs it with the Simulator's AVAudioSession, and the harness runs
  as it changes;
- off until the player turns it on, so that nothing changes from before.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUEST = ROOT / "launcher" / "Guest"
START = GUEST / "CartoucheOtherAudio.m"
SESSION = GUEST / "CartoucheOtherAudioSession.m"
HEADER = GUEST / "CartoucheOtherAudioSession.h"
LAUNCHER = ROOT / "launcher" / "Sources" / "CartoucheOtherAudio.swift"
ACTIONS = ROOT / "launcher" / "Sources" / "CartoucheGameActions.swift"
SYSTEM = ROOT / "launcher" / "Sources" / "CartoucheSystemView.swift"
TELEMETRY = ROOT / "launcher" / "Sources" / "CartoucheTelemetry.swift"
HARNESS = ROOT / "launcher" / "Harness"
WORKFLOW = ROOT / ".github" / "workflows" / "harness.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def c_function(source: str, name: str) -> str:
    """The body of the C function NAME in SOURCE, up to its closing brace at
    the start of a line."""
    match = re.search(rf"\n(?:static )?[\w *]+\b{name}\([^)]*\) \{{\n(.*?)\n\}}\n", source, re.S)
    if not match:
        raise AssertionError(f"no function {name}")
    return match.group(1)


class OtherAudioTest(unittest.TestCase):
    def test_the_game_reads_the_file_play_writes(self):
        session, launcher = read(SESSION), read(LAUNCHER)
        written = re.search(r'static let file = "([^"]+)"', launcher).group(1)
        self.assertEqual(re.search(r'CartoucheOtherAudioFile = @"([^"]+)"', session).group(1), written)
        self.assertEqual(written, "Library/Cartouche/OtherAudio.plist")
        self.assertEqual(re.search(r'CartoucheOtherAudioKey = @"([^"]+)"', session).group(1),
                         re.search(r'static let key = "([^"]+)"', launcher).group(1))
        # Play writes it for nxnative's games, behind the console and in
        # Cartouche's place alike, from the player's choice.
        prepare = re.search(r"private static func prepareStart\(.*?\n    \}\n", read(ACTIONS), re.S).group(0)
        self.assertIn("keepOtherAudio(of: app, container: container)", prepare)
        self.assertIn("CartoucheOtherAudio.write(keeping: keeps, home: container.containerURL)", read(ACTIONS))

    def test_it_acts_in_nxnatives_games_alone_once_they_have_launched(self):
        start = read(START)
        is_game = c_function(start, "CartoucheOtherAudioIsGame")
        self.assertIn("if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore) return NO;", is_game)
        self.assertIn('stringByAppendingPathComponent:@"dm"]', is_game)
        self.assertIn('infoDictionary[@"DMLanguage"]', is_game)
        begins = c_function(start, "CartoucheOtherAudioStart")
        self.assertIn('getenv("HOME")', begins)
        self.assertIn("!CartoucheOtherAudioIsGame() || !CartoucheOtherAudioIsKept(@(home))) return;", begins)
        self.assertIn("CartoucheOtherAudioKeep(YES)", begins)
        # As UIKit says the game has finished launching, on its own thread,
        # before the game's first scene (nxnative's front_ios_boot).
        self.assertIn('addObserverForName:@"UIApplicationDidFinishLaunchingNotification"', start)
        self.assertRegex(start, r"queue:nil\n")

    def test_every_way_of_setting_the_category_mixes(self):
        session = read(SESSION)
        self.assertIn("static const NSUInteger CartoucheOtherAudioMix = 0x1;", session)
        for selector in ("setCategory:error:", "setCategory:withOptions:error:", "setCategory:mode:options:error:",
                         "setCategory:mode:routeSharingPolicy:options:error:"):
            self.assertIn(f"class_getInstanceMethod(session, @selector({selector}))", session)
        for category in ("Playback", "PlayAndRecord", "MultiRoute"):
            self.assertIn(f'CartoucheOtherAudioName("AVAudioSessionCategory{category}")', session)
        self.assertEqual(len(re.findall(r"method_setImplementation\(", session)), 4)
        # Only while kept, and only for the categories that take the option.
        options = c_function(session, "CartoucheOtherAudioOptions")
        self.assertIn("keeping && [mixable containsObject:category] ? options | CartoucheOtherAudioMix : options", options)

    def test_it_links_neither_avfaudio_nor_uikit_nor_livecontainer(self):
        for path in (START, SESSION, HEADER):
            with self.subTest(file=path.name):
                source = read(path)
                self.assertIsNone(re.search(r"@import (?:AVFAudio|AVFoundation|UIKit)|#(?:import|include) <(?:AVFAudio|AVFoundation|UIKit)",
                                            source))
                # Found at run time, never referenced at link time.
                code = re.sub(r"//.*", "", source)
                self.assertIsNone(re.search(r"\[AVAudioSession |\[UIApplication ", code))
        # The harness builds the part that mixes without LiveContainer.
        self.assertNotIn("utils.h", read(SESSION) + read(HEADER))
        self.assertNotIn("NSUserDefaults", read(SESSION))

    def test_the_harness_runs_the_part_that_mixes(self):
        project = read(HARNESS / "project.yml")
        self.assertIn("- path: ../Guest/CartoucheOtherAudioSession.m", project)
        self.assertNotIn("../Guest/CartoucheOtherAudio.m", project)
        self.assertIn('#import "../../Guest/CartoucheOtherAudioSession.h"', read(HARNESS / "Sources" / "Harness-Bridging-Header.h"))
        self.assertTrue((HARNESS / "Tests" / "OtherAudioTests.swift").exists())
        workflow = read(WORKFLOW)
        self.assertEqual(workflow.count('"launcher/Guest/CartoucheOtherAudioSession.*"'), 2, "on main and on pull requests")
        self.assertIn("'launcher/Guest/CartoucheOtherAudioSession.*'", workflow, "in what a pull request's run is remembered by")

    def test_off_until_the_player_turns_it_on(self):
        launcher = read(LAUNCHER)
        self.assertIn("keeps = UserDefaults.standard.bool(forKey: Self.defaultsKey)", launcher)
        self.assertIn('static let defaultsKey = "Cartouche.keepOtherAudio"', launcher)
        # Off, Play leaves no file, and the game's session is nxnative's.
        write = re.search(r"static func write\(keeping: Bool, home: URL\) throws \{(.*?)\n    \}\n", launcher, re.S).group(1)
        self.assertIn("guard keeping else {", write)
        self.assertIn("removeItem(at: url)", write)
        # The System page's row, on the iPhone, whatever games run behind
        # the console there.
        system = read(SYSTEM)
        playing = re.search(r"    private var playingSection: some View \{\n(.*?)\n    \}\n", system, re.S).group(1)
        self.assertIn("Toggle(CartoucheText.keepOtherAudio, isOn: $otherAudio.keeps)", playing)
        self.assertRegex(playing, r"\n            \}\n            Toggle\(CartoucheText.keepOtherAudio",
                         "the row is outside the part that needs games behind the console")

    def test_each_session_says_whether_the_game_kept_other_apps_sound(self):
        self.assertIn("otherAudio: CartoucheOtherAudio.isKept(home: container.containerURL)", read(TELEMETRY))
        self.assertIn("otherAudio: flag,", read(ROOT / "telemetry" / "worker.js"))


if __name__ == "__main__":
    unittest.main()
