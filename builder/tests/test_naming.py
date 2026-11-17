"""The help on naming the games, which Cartouche shows under its Storage page
and the Mac app in its settings, its setup assistant and its library
(launcher/Sources/CartoucheNaming.swift), says what the builder does: each
example of the dumps folder is found, or left aside, by the builder's
discovery (library.py), and the names it gives the games folder's IPAs and
the Mac's apps are the examples'. The games folder's and the saves folder's
examples are the iPhone's, which CartoucheNamingTests checks.

Nothing here is a game: the example's packages are a few bytes, named as the
help names them, and its dump is laid out as nxnative reads one.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from cartouche_builder import identify, ipa, library, macapps, titles

from support import Home, make_dump

ROOT = Path(__file__).resolve().parents[2]
NAMING = ROOT / "launcher" / "Sources" / "CartoucheNaming.swift"
CATALOG = ROOT / "launcher" / "Sources" / "Cartouche.xcstrings"

# Example(.dumps, "Example Quest [0100F00D0BAD0000][v0].nsp", .found, .package)
EXAMPLE = re.compile(r'Example\(\.(\w+), "((?:[^"\\]|\\.)*)", \.(found|leftAside), \.(\w+)\)')
# The made-up title ID that the dump of the example holds: its name has none.
DUMP_ID = "0100F00D0BAE0000"


def examples(place: str) -> list[tuple[str, bool, str]]:
    """PLACE's examples, as (path, found, meaning)."""
    found = [(path, verdict == "found", meaning)
             for where, path, verdict, meaning in EXAMPLE.findall(NAMING.read_text(encoding="utf-8")) if where == place]
    assert found, f"no example of {place} in {NAMING.name}"
    return found


def words(key: str) -> str:
    return json.loads(CATALOG.read_text(encoding="utf-8"))["strings"][key]["localizations"]["en"]["stringUnit"]["value"]


class DumpsFolderExamples(Home):
    def sources(self) -> tuple[Path, dict[str, Path]]:
        """A dumps folder of the examples, each at its path, and where."""
        root = self.tmp / "dumps"
        root.mkdir()
        made = {}
        for path, _, meaning in examples("dumps"):
            target = root / path.rstrip("/")
            made[path] = target
            if meaning == "dump":
                make_dump(target, DUMP_ID)
            elif meaning == "buildFolder":
                # As nxnative leaves it: its extraction looks like a dump.
                make_dump(target, "0100F00D0BAF0000")
            else:
                self.assertFalse(path.endswith("/"), path)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"x" * 16)
        return root, made

    def test_the_builder_finds_what_the_help_says_it_finds_and_nothing_else(self):
        root, made = self.sources()
        found = library.discover(root, {})
        taken = {path for game in found.games for path in game.inputs} | {game.folder for game in found.games if game.kind == "dump"}
        for path, is_found, meaning in examples("dumps"):
            with self.subTest(path=path):
                self.assertEqual(made[path] in taken, is_found, meaning)
        games = {game.title_id: game for game in found.games}
        self.assertEqual(sorted(games), sorted(["0100F00D0BAD0000", "0400F00D0BAD0000", DUMP_ID]))
        # The update goes with its game, which is built from both.
        self.assertEqual(games["0100F00D0BAD0000"].kind, "packages")
        self.assertEqual(len(games["0100F00D0BAD0000"].inputs), 2)
        self.assertEqual(games["0400F00D0BAD0000"].kind, "nup")
        self.assertEqual(games[DUMP_ID].kind, "dump")

    def test_an_update_is_known_by_its_games_title_id(self):
        update = next(path for path, _, meaning in examples("dumps") if meaning == "update")
        package = next(path for path, _, meaning in examples("dumps") if meaning == "package")
        self.assertEqual(titles.base_title_id(titles.ids_in_name(update)[0]), titles.ids_in_name(package)[0])
        self.assertTrue(titles.ids_in_name(update)[0].endswith("800"))

    def test_the_folders_left_aside_are_the_builders(self):
        folder = next(path for path, _, meaning in examples("dumps") if meaning == "buildFolder")
        self.assertTrue(library.NOT_GAMES.fullmatch(folder.rstrip("/")))
        for name in ("Example Quest_dump", "__MACOSX"):
            self.assertTrue(library.NOT_GAMES.fullmatch(name), name)

    def test_the_help_says_how_deep_and_which_packages(self):
        depth = re.search(r"static let dumpsDepth = (\d+)", NAMING.read_text(encoding="utf-8"))
        self.assertIsNotNone(depth)
        self.assertEqual(int(depth.group(1)), library.MAX_DEPTH)
        said = words("naming.package")
        for suffix in identify.PACKAGE_SUFFIXES:
            self.assertIn(suffix, said)
        self.assertIn(identify.NUP_SUFFIX, words("naming.nup"))


class GamesFolderNames(Home):
    def test_the_builder_names_an_ipa_and_a_macs_app_as_the_help_shows(self):
        named = {meaning: path for path, _, meaning in examples("games")}
        self.assertEqual(ipa.file_name("Example Quest", "0100f00d0bad0000"), named["namedIPA"])
        self.assertEqual(macapps.packed_name("Example Quest", "0100F00D0BAD0000"), named["macApp"])
