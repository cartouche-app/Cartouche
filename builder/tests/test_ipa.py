import shutil
import subprocess
import threading
import unittest
import zipfile
from datetime import datetime
from pathlib import Path
from unittest import mock

from cartouche_builder import ipa

from support import MKW, UNREADABLE_INFO_PLIST, Home, make_ipa


class Info(Home):
    def test_reads_what_nxnative_writes(self):
        path = make_ipa(self.tmp / "game.ipa", {
            "DMCommit": "2EB71820ABCD+dirty", "DMChain": "adec7d81d970", "DMTitleID": MKW,
            "CFBundleShortVersionString": "1.0.0", "CFBundleIdentifier": "org.nxnative.0400c3f00006e000", "CFBundleDisplayName": "Mario Kart World",
        })
        info = ipa.read_info(path)
        self.assertEqual(info.commit, "2eb71820abcd")
        self.assertTrue(info.dirty)
        self.assertEqual(info.chain, "adec7d81d970")
        self.assertEqual(info.title_id, MKW)
        self.assertEqual(info.version, "1.0.0")
        self.assertEqual(info.built, datetime(2026, 11, 9, 21, 15, 52))

    def test_title_id_from_the_bundle_id(self):
        path = make_ipa(self.tmp / "game.ipa", {"CFBundleIdentifier": "org.nxnative.0400c3f00006e000"})
        self.assertEqual(ipa.read_info(path).title_id, MKW)

    def test_not_an_ipa(self):
        path = self.tmp / "nope.ipa"
        path.write_bytes(b"not a zip")
        self.assertIsNone(ipa.read_info(path))

    def test_an_ipa_another_tool_made(self):
        """Its Info.plist one Python cannot read, or the archive compressed
        in a way Python cannot read, or encrypted: no IPA of nxnative's,
        and no error for the games beside it."""
        path = self.tmp / "other.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Other.app/Info.plist", UNREADABLE_INFO_PLIST)
        self.assertIsNone(ipa.read_info(path))
        for name, flags, method in (("unknown-method.ipa", 0, 99), ("encrypted.ipa", 1, 0)):
            path = make_ipa(self.tmp / name, {"DMTitleID": MKW})
            data = bytearray(path.read_bytes())
            # The Info.plist's local header and its central directory entry.
            for signature, flag_at, method_at in ((b"PK\x03\x04", 6, 8), (b"PK\x01\x02", 8, 10)):
                at = data.index(signature)
                data[at + flag_at] |= flags
                data[at + method_at:at + method_at + 2] = method.to_bytes(2, "little")
            path.write_bytes(bytes(data))
            self.assertIsNone(ipa.read_info(path), name)


class Names(unittest.TestCase):
    def test_as_cartouche_names_them(self):
        self.assertEqual(ipa.file_name("Mario Kart World", MKW.lower()), f"Mario Kart World [{MKW}].ipa")
        self.assertEqual(ipa.clean_name('NieR:Automata  "The End"?'), "NieR Automata The End")
        self.assertEqual(ipa.clean_name(" .Game. "), "Game")
        self.assertEqual(ipa.clean_name("..."), "Game")
        self.assertEqual(len(ipa.clean_name("x" * 300)), 120)
        self.assertEqual(ipa.clean_name("A\tB​C"), "A B C")


class Folder(Home):
    def test_finds_by_name_then_by_info(self):
        games = self.tmp / "games"
        make_ipa(games / f"Mario Kart World [{MKW}].ipa", {"DMTitleID": MKW})
        make_ipa(games / "MarioKartWorld-v2.ipa", {"DMTitleID": MKW})
        make_ipa(games / "Other.ipa", {"DMTitleID": "0100000000010000"})
        found = ipa.find_in_folder(games, MKW)
        self.assertEqual([p.name for p in found], [f"Mario Kart World [{MKW}].ipa", "MarioKartWorld-v2.ipa"])
        self.assertEqual([p.name for p in ipa.find_in_folder(games, MKW, read=False)], [f"Mario Kart World [{MKW}].ipa"])

    def test_delivery_replaces_whole(self):
        games = self.tmp / "games"
        games.mkdir()
        (games / "Game.ipa").write_bytes(b"old")
        source = self.tmp / "new.ipa"
        source.write_bytes(b"new" * 1000)
        target = ipa.deliver(source, games, "Game.ipa")
        self.assertEqual(target.read_bytes(), b"new" * 1000)
        self.assertEqual(sorted(p.name for p in games.iterdir()), ["Game.ipa"])

    def test_stopped_delivery_keeps_the_old_one(self):
        games = self.tmp / "games"
        games.mkdir()
        (games / "Game.ipa").write_bytes(b"old")
        source = self.tmp / "new.ipa"
        source.write_bytes(b"new" * (4 << 20))
        stop = threading.Event()
        stop.set()
        with self.assertRaises(InterruptedError):
            ipa.deliver(source, games, "Game.ipa", stop=stop)
        self.assertEqual((games / "Game.ipa").read_bytes(), b"old")
        self.assertEqual(sorted(p.name for p in games.iterdir()), ["Game.ipa"])

    def test_a_clone_is_stopped_and_followed_as_a_copy_is(self):
        # On a Mac the IPA is an APFS clone when the games folder is on the
        # build folders' disk, as it is by default (_clone): whole at once, it
        # writes no blocks that a Stop or the app's progress would see.
        games = self.tmp / "games"
        games.mkdir()
        (games / "Game.ipa").write_bytes(b"old")
        source = self.tmp / "new.ipa"
        source.write_bytes(b"new" * 1000)
        stop = threading.Event()

        def clone(source, target, then=None):
            shutil.copyfile(source, target)
            if then:
                then()
            return True

        # A Stop before the clone, and one while it runs.
        for when in ("before", "during"):
            if when == "before":
                stop.set()
            else:
                stop.clear()
            with mock.patch.object(ipa, "_clone", side_effect=lambda s, t: clone(s, t, then=stop.set)):
                with self.assertRaises(InterruptedError, msg=when):
                    ipa.deliver(source, games, "Game.ipa", stop=stop)
            self.assertEqual((games / "Game.ipa").read_bytes(), b"old", when)
            self.assertEqual(sorted(p.name for p in games.iterdir()), ["Game.ipa"], when)
        stop.clear()
        steps = []
        with mock.patch.object(ipa, "_clone", side_effect=clone):
            ipa.deliver(source, games, "Game.ipa", stop=stop, progress=lambda done, total: steps.append((done, total)))
        self.assertEqual((games / "Game.ipa").read_bytes(), b"new" * 1000)
        self.assertEqual(steps, [(3000, 3000)])

    def test_a_clone_cut_short_leaves_nothing_to_the_copy(self):
        # cp -c ran past its 600 seconds, or failed, with half of the IPA
        # written: the copy that follows writes it whole. Up to Builder
        # 0.8.2, that half stayed, and the copy, which opens its file only
        # if it is not there, stopped the build with FileExistsError.
        games = self.tmp / "games"
        games.mkdir()
        (games / "Game.ipa").write_bytes(b"old")
        source = self.tmp / "new.ipa"
        source.write_bytes(b"new" * 1000)
        for ending in ("timeout", "error", "failed"):
            def cp(command, **options):
                Path(command[-1]).write_bytes(source.read_bytes()[:1000])
                if ending == "timeout":
                    raise subprocess.TimeoutExpired(command, options["timeout"])
                if ending == "error":
                    raise OSError(5, "Input/output error")
                return subprocess.CompletedProcess(command, 1)

            with mock.patch.object(ipa.sys, "platform", "darwin"), mock.patch.object(ipa.subprocess, "run", side_effect=cp):
                target = ipa.deliver(source, games, "Game.ipa")
            self.assertEqual(target.read_bytes(), b"new" * 1000, ending)
            self.assertEqual(sorted(p.name for p in games.iterdir()), ["Game.ipa"], ending)
            (games / "Game.ipa").write_bytes(b"old")


if __name__ == "__main__":
    unittest.main()
