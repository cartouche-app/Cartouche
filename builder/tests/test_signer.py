"""Cartouche for Mac and its helper cartouche-signer say the same things
(decision 165): the kinds of error the helper gives (mac/signer/src/error.rs)
are those its README lists, those the app's words say in the player's words
(mac/Sources/BuilderKit/SignerWords.swift) and those their tests go through;
the file the helper writes in Cartouche's Documents is the one Cartouche
reads on the iPhone (launcher/Sources/CartoucheRenewalRules.swift); and
the helper's folder is the app's."""

import re
import unittest
from pathlib import Path

BUILDER = Path(__file__).resolve().parents[1]
ROOT = BUILDER.parent


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def helper_kinds() -> list[str]:
    source = text("builder/mac/signer/src/error.rs")
    block = source[source.index("pub fn as_str"):]
    block = block[: block.index("\n    }\n")]
    return re.findall(r'=> "([a-z-]+)"', block)


# What only the app's own mistakes give, which no player can do anything
# about: the words say so with the kind.
TECHNICAL = {"usage", "internal"}


class SignerTest(unittest.TestCase):
    def test_the_readme_lists_every_kind_of_error(self):
        kinds = helper_kinds()
        self.assertIn("certificate-gone", kinds)
        readme = text("builder/mac/signer/README.md")
        line = next(line for line in readme.splitlines() if line.startswith("The kinds of error are "))
        self.assertEqual(re.findall(r"`([a-z-]+)`", line.split(". The stages")[0]), kinds)

    def test_the_app_says_each_kind_in_the_players_words(self):
        words = text("builder/mac/Sources/BuilderKit/SignerWords.swift")
        said = set(re.findall(r'case "([a-z-]+)":', words))
        self.assertEqual(said, set(helper_kinds()) - TECHNICAL)
        tests = text("builder/mac/Tests/BuilderKitTests/SignerPlanTests.swift")
        listed = tests[tests.index("let kinds = ["):]
        listed = listed[: listed.index("]")]
        self.assertEqual(re.findall(r'"([a-z-]+)"', listed), [kind for kind in helper_kinds() if kind not in TECHNICAL])

    def test_the_app_reads_the_kinds_that_say_what_to_do(self):
        signer = text("builder/mac/Sources/BuilderKit/Signer.swift")
        for kind in re.findall(r'kind == "([a-z-]+)"', signer):
            self.assertIn(kind, helper_kinds())

    def test_cartouche_reads_the_file_the_helper_writes(self):
        helper = text("builder/mac/signer/src/iphone.rs")
        written = re.search(r'pub const RENEWAL_RECORD: &str = "([^"]+)";', helper).group(1)
        self.assertEqual(written, "/Documents/.cartouche/renewal.json")
        rules = text("launcher/Sources/CartoucheRenewalRules.swift")
        read = re.search(r'static let path = "([^"]+)"', rules).group(1)
        self.assertEqual("/Documents/" + read, written)
        # The fields both sides name (the helper's in snake case, which serde
        # writes in camel case), and who renewed it.
        record = helper[helper.index("pub struct RenewalRecord"):]
        record = record[: record.index("}")]
        self.assertIn('#[serde(rename_all = "camelCase")]\npub struct RenewalRecord', helper)
        written_fields = [re.sub(r"_([a-z])", lambda m: m.group(1).upper(), name)
                          for name in re.findall(r"pub ([a-z_]+):", record)]
        self.assertEqual(written_fields, ["bundleIdentifier", "expirationDate", "refreshedDate", "by"])
        for field in written_fields:
            self.assertIn(field, rules)
        self.assertIn('by: "mac"', text("builder/mac/signer/src/renew.rs"))
        self.assertIn('"mac"', rules)

    def test_the_helper_keeps_its_session_in_the_apps_folder(self):
        main = text("builder/mac/signer/src/main.rs")
        self.assertIn('"Library/Application Support/Cartouche Builder/Signer"', main)
        engine = text("builder/mac/Sources/BuilderKit/Engine.swift")
        self.assertIn('appendingPathComponent("Signer", isDirectory: true)', engine)


if __name__ == "__main__":
    unittest.main()
