"""Checks that Cartouche shows nxnative's settings in the reader's language:
every text of nxnative's settings list (its dm/games/settings.tsv, which it
writes into each game as dm/launcher.json) is one CartoucheText.gameSettingText
knows (app/scripts/game_setting_texts.py), on the iPhone and in the console
of the Mac, which shows the iPhone's page.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "app" / "scripts" / "game_setting_texts.py"

spec = importlib.util.spec_from_file_location("game_setting_texts", SCRIPT)
texts_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(texts_module)

# The texts of nxnative's settings list at its commit 2f959ede (27 November
# 2026), as game_setting_texts.texts reads them: up to 0.16.2, Rotation and
# its choices, Texture filtering, the Microphone and its gain, the newer note
# of Picture shape and two of its shapes showed in English.
NXNATIVE_2F959EDE = [
    "Game", "Frame rate", "30 fps", "40 fps", "60 fps", "120 fps", "Dynamic resolution",
    "Lets the game lower its resolution under load. Turn off to keep full resolution for the selected console mode.",
    "Render scale", "Console mode", "Docked", "Handheld", "Upscaling", "Uses more GPU time and can increase heat.",
    "Standard", "MetalFX", "Game's upscaler", "Game's own", "Texture filtering",
    "Sharper ground and walls seen at an angle. 16x costs little on a Mac.", "Game default", "2x", "4x", "8x", "16x",
    "Game language", "Display mode", "Window", "Fullscreen", "Picture",
    "Fill crops the game's 16:9 picture to cover the screen. Health bars, subtitles or maps near the edges can be cut off. "
    "A full-screen picture without cropping needs a patch for each game.",
    "Fit", "Fill", "Rotation", "Automatic", "Landscape", "Portrait", "Frame-rate counter", "Controls", "Touch feedback",
    "Game rumble", "Rumble strength", "Rumble cutoff", "Press a button to join", "Switch 2 controllers",
    "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. "
    "macOS asks once for Bluetooth access.",
    "Microphone", "Lets the game hear your microphone. macOS asks for access when you launch with this enabled.",
    "Microphone gain", "Picture shape", "Taller shapes render more pixels and can increase GPU time and heat.",
    "Match screen", "MacBook (16:10)", "iPhone Duo screen (1.43:1)", "16:9 (Switch)", "Performance", "Frame buffering",
    "Up to one frame more display latency.", "Metal 4 pipelines", "Keeps a pipeline archive; uses more memory.",
    "Pipeline prebuild", "The first start waits a few minutes for it, once.", "Encode thread", "Hold frames when late",
    "Performance HUD",
]

# Texts of older games' lists, which their builds still show.
OLDER = [
    "Adjusts resolution between 70% and 100% under load. Turn off to keep full resolution for the selected console mode.",
    "Renders about a quarter more pixels: a little slower and warmer.",
    "This game's files do not list its languages, so some of these may not be in the game. It may then show another one.",
]


class GameSettingTextsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.known = texts_module.known(texts_module.SWIFT.read_text(encoding="utf-8"))

    def test_every_text_of_nxnatives_list_is_translated(self):
        self.assertEqual(texts_module.untranslated(NXNATIVE_2F959EDE, self.known), [])

    def test_the_texts_of_older_lists_stay_translated(self):
        self.assertEqual(texts_module.untranslated(OLDER, self.known), [])

    def test_a_text_cartouche_does_not_know_is_listed(self):
        self.assertEqual(texts_module.untranslated(["Rotation", "A setting of tomorrow", "60 fps", "8x", "MetalFX"],
                                                   self.known), ["A setting of tomorrow"])

    def test_the_texts_of_a_list_are_its_sections_labels_notes_and_options(self):
        tsv = "\n".join([
            "# variable\tkind\tdefault\tshown\tsection\tlabel\tnote\tmeta",
            "DM_FPS_TARGET\tchoice\t30=30 fps,40=40 fps?fixups:FRAME_STEP_120\tDM_GAME_FPS_TARGET\talways\tGame\tFrame rate\t\tlevel=basic",
            "DM_LANG\tchoice\tlanguages\tbuild:DM_LANG\tlanguages>1\tGame\tGame language\t\tlevel=basic",
            "DM_SCREEN_ASPECT\tchoice\tauto=Match screen?platform:ios,1.6=MacBook (16:10)?platform:mac,0=16:9 (Switch)\tauto|0"
            "\tfixups:SCREEN_ASPECT\tGame\tPicture shape\tTaller shapes render more pixels.",
            "DM_MIC_GAIN\trange\t1:8:0.5\t1\tmac-mic\tControls\tMicrophone gain\t\tneeds=DM_MIC=1",
            "DM_METAL_HUD\ttoggle\t-\t0\talways\tPerformance\tPerformance HUD",
            "",
        ])
        self.assertEqual(texts_module.texts(tsv), [
            "Game", "Frame rate", "30 fps", "40 fps", "Game language", "Picture shape", "Taller shapes render more pixels.",
            "Match screen", "MacBook (16:10)", "16:9 (Switch)", "Controls", "Microphone gain", "Performance", "Performance HUD",
        ])

    def test_the_cases_of_the_switch_are_read(self):
        self.assertIn("Game's upscaler", self.known)
        self.assertIn("Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. "
                      "macOS asks once for Bluetooth access.", self.known)
        self.assertNotIn("Polish", self.known)


if __name__ == "__main__":
    unittest.main()
