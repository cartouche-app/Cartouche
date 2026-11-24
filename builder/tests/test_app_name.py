"""The Mac's app is Cartouche, as on the iPhone; its folder on the Mac, the
names its installed copies update by and its engine's commands stay.

bundle.sh makes Cartouche.app, called Cartouche in the Finder, the Dock and
the menu bar, with the bundle identifier the copies already installed check
(test_updates.py); the Builder workflow checks, builds and photographs that
app. A copy installed as Cartouche Builder.app moves to Cartouche.app at its
first start as Cartouche (mac/Sources/BuilderKit/AppName.swift, its tests
in mac/Tests/BuilderKitTests/AppNameTests.swift). Its settings, games and
builds stay in ~/Library/Application Support/Cartouche Builder; a nightly
batch tells of itself only while neither app runs, and in Cartouche's name."""

import json
import re
import unittest
from pathlib import Path
from unittest import mock

from cartouche_builder import notify, paths

BUILDER = Path(__file__).resolve().parents[1]
ROOT = BUILDER.parent


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def plist_value(source: str, key: str) -> str:
    match = re.search(rf"<key>{key}</key>\s*<string>([^<]+)</string>", source)
    assert match, key
    return match.group(1)


class AppName(unittest.TestCase):
    def test_the_app_bundle_sh_makes_is_cartouche(self):
        bundle = text("builder/mac/bundle.sh")
        self.assertIn('app="$destination/Cartouche.app"', bundle)
        self.assertIn('cp "$binary" "$app/Contents/MacOS/Cartouche"\n', bundle)
        for key in ("CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"):
            self.assertEqual(plist_value(bundle, key), "Cartouche", key)
        self.assertEqual(plist_value(bundle, "CFBundleIdentifier"), "io.github.clabeuhtegrite.cartouche-builder")

    def test_its_disk_image_shows_cartouche_under_the_name_the_copies_look_for(self):
        image = text("builder/mac/make_dmg.sh")
        self.assertIn('name="Cartouche-Builder-$version.dmg"', image)
        self.assertRegex(image, r'"Cartouche" "\$folder/\$name"')

    def test_the_workflow_checks_builds_and_photographs_cartouche_app(self):
        workflow = text(".github/workflows/builder.yml")
        self.assertNotIn("Cartouche Builder.app", workflow)
        self.assertIn('"build/builder/Cartouche.app/Contents/MacOS/Cartouche" --layout-check', workflow)
        self.assertIn('make_dmg.sh "build/builder/Cartouche.app" build/dmg', workflow)
        self.assertIn('"build/builder/Cartouche.app/Contents/MacOS/Cartouche" --gallery build/screens', workflow)

    def test_the_folder_on_the_mac_keeps_its_name(self):
        with mock.patch.dict("os.environ", {}, clear=False) as environment:
            environment.pop("CARTOUCHE_BUILDER_HOME", None)
            home = paths.Paths.default().root
        self.assertEqual(home.parts[-3:], ("Library", "Application Support", "Cartouche Builder"))
        swift = text("builder/mac/Sources/BuilderKit/Engine.swift")
        self.assertIn('support.appendingPathComponent("Cartouche Builder", isDirectory: true)', swift)

    def test_a_nightly_batch_knows_either_app_runs(self):
        running = re.compile(notify.RUNNING)
        self.assertTrue(running.search("/Applications/Cartouche.app/Contents/MacOS/Cartouche --background"))
        self.assertTrue(running.search("/Applications/Cartouche Builder.app/Contents/MacOS/Cartouche Builder"))
        self.assertTrue(running.search("/Users/player/Applications/Cartouche Builder.app/Contents/MacOS/Cartouche"))
        # The engine's own Python, inside the app, is not the app.
        self.assertFalse(running.search("python3 /Applications/Cartouche.app/Contents/Resources/engine/cartouche_builder"))
        self.assertFalse(running.search("/Applications/Mario Kart World.app/Contents/MacOS/Mario Kart World"))

    def test_the_consoles_system_page_names_it_in_its_language(self):
        # Cartouche for Mac in English, Cartouche pour Mac in French: a
        # verbatim name stayed in English in the French console.
        system = text("launcher/Sources/CartoucheSystemView.swift")
        self.assertNotRegex(system, r'Text\(verbatim: "Cartouche (?:for Mac|Builder)"\)')
        self.assertIn("Text(CartoucheText.macSystemApp)", system)
        words = json.loads(text("builder/mac/console/strings.json"))["strings"]["mac.system.app"]
        self.assertEqual(words, {"en": "Cartouche for Mac", "fr": "Cartouche pour Mac"})

    def test_no_word_of_the_apps_says_cartouche_builder(self):
        # The words the Mac's console, the iPhone and the engine show: a
        # change made beside the rename brought the former name back.
        mac = json.loads(text("builder/mac/console/strings.json"))
        words = [value for section in mac.values() for entry in section.values() for value in entry.values()]
        catalog = json.loads(text("launcher/Sources/Cartouche.xcstrings"))
        words += [unit["stringUnit"]["value"] for entry in catalog["strings"].values()
                  for unit in entry.get("localizations", {}).values() if "stringUnit" in unit]
        said = [word for word in words if "Cartouche Builder" in word]
        self.assertEqual(said, [])
        self.assertNotIn("Cartouche Builder", text("builder/cartouche_builder/texts.py"))

    def test_its_notifications_say_cartouche(self):
        scripts = []
        with mock.patch.object(notify.sys, "platform", "darwin"), \
                mock.patch.dict("os.environ", {"CARTOUCHE_BUILDER_QUIET": ""}), \
                mock.patch.object(notify.subprocess, "run", side_effect=lambda command, **_: scripts.append(command)):
            notify.notify("Mario Kart World is built.")
        self.assertEqual(len(scripts), 1)
        self.assertIn('with title "Cartouche"', scripts[0][-1])


if __name__ == "__main__":
    unittest.main()
