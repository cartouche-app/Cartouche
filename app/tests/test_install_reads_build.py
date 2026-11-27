"""Checks that the question an install asks first on an iPhone whose GPU
reads no BC-compressed texture, the A16's and older
(launcher/Sources/CartoucheInstallQuestions.swift), reads the game's build
before it asks: a build that converts those textures, as nxnative-nobc's
do (CartoucheBCConversion.swift), installs without it.

On 26 November a player with an iPhone 13 sent Sparking Zero to Cartouche
Cloud for an iPhone 11 to 15, downloaded the IPA it built from
nxnative-nobc, and opened it in Cartouche, which still said "This iPhone
cannot run nxnative's games": the question looked at the GPU alone. The
game's sheet said the textures were converted once it was installed.

Each of the three installs CartoucheGameActions.swift asks the question of
passes what it knows of the build: a file's executable read on this iPhone,
a game in the games folder as its scan read it, and a game Cartouche Cloud
built by the nxnative the platform says it built it from.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ACTIONS = ROOT / "launcher" / "Sources" / "CartoucheGameActions.swift"


class InstallReadsBuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ACTIONS.read_text(encoding="utf-8")

    def function(self, signature: str) -> str:
        """The body of the function whose declaration starts with SIGNATURE."""
        start = self.source.find(signature)
        self.assertNotEqual(start, -1, signature)
        end = self.source.find("\n    }\n", start)
        return self.source[start:end]

    def test_the_question_hears_of_the_conversion(self):
        body = self.function("    private func startsNow(")
        self.assertIn("convertsBCTextures: converts", body)
        self.assertIn("CartoucheBCConversion.covers(", self.function("    private static func covers("))

    def test_each_install_says_what_it_knows_of_its_build(self):
        calls = re.findall(r"startsNow\(CartoucheInstallQuestion\(source: \.(\w+)\([^)]*\)\),\s*converted: ([^,]+),",
                           self.source)
        self.assertEqual(dict(calls), {
            "file": "converted",
            "stored": "offered.convertedBC",
            "cloud": "CartoucheBCConversion.conversion(ofCloudEngine: game.engine)",
        })

    def test_a_file_is_read_before_the_question(self):
        body = self.function("    func install(_ url: URL, asked: Bool = false) {")
        self.assertIn("guard asked || CartoucheDevice.supportsBCTextureCompression else {", body)
        self.assertIn("await Self.bcConversion(ofIPA: url)", body)
        self.assertIn("install(url, converted: read.apis, titleId: read.titleId, asked: false)", body)
        reader = self.function("    nonisolated private static func bcConversion(ofIPA url: URL)")
        self.assertIn("CartoucheBCConversion.conversion(", reader)
        self.assertIn('plist.info["CFBundleExecutable"]', reader)


if __name__ == "__main__":
    unittest.main()
