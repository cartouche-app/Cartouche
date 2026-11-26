"""Checks what an iPhone whose GPU reads no BC-compressed texture is told,
the A16's and older (launcher/Sources/CartoucheText.swift): nxnative's games
stop there before their first image, and two places build them for it from
nxnative-nobc, a separate fork of nxnative that converts those textures:
Cartouche for Mac, once the two are paired, and Cartouche Cloud, for a game
sent for an iPhone 11 to 15.

Until 26 November 2026 only the Mac was named, and Cartouche Cloud built
every game from nxnative: a player with an iPhone 13 and no Mac paid for a
build this iPhone could not run. Cartouche Cloud's page now asks which
iPhone a game is for.

The question an install asks first (CartoucheGamesView.swift) and This
iPhone on the System page (CartoucheSystemView.swift) say the same.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "launcher" / "Sources"
LANGUAGES = ("en", "fr", "es", "de")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class NoBCAdviceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read(SOURCES / "CartoucheText.swift")
        cls.catalog = json.loads(read(SOURCES / "Cartouche.xcstrings"))["strings"]

    def value(self, key: str, language: str) -> str:
        self.assertIn(key, self.catalog)
        return self.catalog[key]["localizations"][language]["stringUnit"]["value"]

    def test_the_advice_names_the_mac_and_cartouche_cloud(self):
        advice = re.search(r"static var installGPUAdvice: String \{ (.*?) \}\n", self.text)
        self.assertIsNotNone(advice, "no installGPUAdvice in CartoucheText.swift")
        self.assertEqual([part.strip() for part in advice.group(1).split('+ " " +')],
                         ["reasonGPU", "installGPUBuilder", "installGPUCloud"])
        for language in LANGUAGES:
            with self.subTest(language=language):
                builder = self.value("work.install.gpu.builder", language)
                self.assertIn("Mac", builder)
                self.assertIn("nxnative-nobc", builder)
                cloud = self.value("work.install.gpu.cloud", language)
                self.assertIn("Cartouche Cloud", cloud)
                self.assertIn("iPhone 11", cloud)

    def test_the_install_question_and_the_system_page_say_it(self):
        for name in ("CartoucheGamesView.swift", "CartoucheSystemView.swift"):
            with self.subTest(name=name):
                source = read(SOURCES / name)
                self.assertIn("Text(CartoucheText.installGPUAdvice)", source)
                self.assertNotIn("CartoucheText.installGPUBuilder", source)


if __name__ == "__main__":
    unittest.main()
