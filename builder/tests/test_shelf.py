"""The build folders chosen on a NAS keep the games' build folders between two
builds, and the games are built on this Mac (shelf.py, decision 163).

On a player's Mac whose build folders were on their NAS's share, every build
failed (25 November): nxnative extracted the game there, then could not open
the RomFS it had just written ("OSError: [Errno 9] Bad file descriptor"), or
read it ("[Errno 5] Input/output error"). The player had put them there to
keep the build folders, and their caches, off the Mac's disk."""

import errno
import json
import os
import shutil
import threading
import time
from pathlib import Path
from unittest import mock

from cartouche_builder import batch, config as configs, storage
from cartouche_builder import shelf as shelves
from cartouche_builder.paths import Paths

from support import MKW, ODYSSEY, Home

from test_batch import BatchHome

MOUNTED = """/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse)
//games@192.168.1.2/Games on /Volumes/Games (smbfs, nodev, nosuid, mounted by player)
/dev/disk7s1 on /Volumes/Backup (apfs, local, nodev, nosuid, journaled, noowners)
"""


class OnNetwork(Home):
    def test_a_share_known_or_mounted_is_a_nas(self):
        known = {"/Volumes/Games": "smb://games@192.168.1.2/Games"}
        self.assertTrue(shelves.on_network(Path("/Volumes/Games/Builds"), known, mounted=""))
        self.assertTrue(shelves.on_network(Path("/Volumes/Games"), known, mounted=""))
        self.assertFalse(shelves.on_network(Path("/Volumes/GamesToo/Builds"), known, mounted=""))
        # Mounted now, as `mount` says, though the settings know it not yet.
        self.assertTrue(shelves.on_network(Path("/Volumes/Games/Builds"), {}, mounted=MOUNTED))
        # This Mac's disks and a disk plugged in: built in, as before.
        self.assertFalse(shelves.on_network(Path("/Users/player/Builds"), {}, mounted=MOUNTED))
        self.assertFalse(shelves.on_network(Path("/Volumes/Backup/Builds"), {}, mounted=MOUNTED))

    def test_the_folder_chosen_on_a_nas_is_kept_in_not_built_in(self):
        paths = Paths.default()
        nas = self.tmp / "nas"
        config = configs.Config(workspace=str(nas / "Builds"), shares={str(nas): "smb://nas.local/Games"})
        shelf = shelves.of(config, paths)
        self.assertEqual(shelf.root, nas / "Builds")
        self.assertEqual(shelves.build_root(config, paths, shelf), paths.workspace)
        local = configs.Config(workspace=str(self.tmp / "Builds"))
        self.assertIsNone(shelves.of(local, paths))
        self.assertEqual(shelves.build_root(local, paths, None), self.tmp / "Builds")
        self.assertEqual(shelves.build_root(configs.Config(), paths, None), paths.workspace)


def build_folder(folder: Path) -> Path:
    """A build folder as nxnative leaves it: the game's files, its packages
    converted, shader caches, its app's build, a log."""
    for name, data in (("extract/v0/RomFS.img", b"r" * 400), ("extract.partial/x", b"p"), ("exefs.partial/main", b"e"), ("tmp/t", b"t"),
                       ("nsp/game.nsp", b"n" * 300), ("shader/cache.bin", b"s" * 120), ("shader/ios/lib.metallib", b"m" * 30),
                       ("ipa/Game.app/Game", b"a" * 50), ("xcode-derived-data/Build/x.o", b"o" * 20), ("logs/build.log", b"l" * 5)):
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return folder


def files(folder: Path) -> set[str]:
    return {str(p.relative_to(folder)) for p in folder.rglob("*") if p.is_file()}


class Shelves(Home):
    def setUp(self):
        super().setUp()
        self.shelf = shelves.Shelf(self.tmp / "nas" / "Builds")
        self.local = build_folder(self.tmp / "mac" / f"{MKW}_build")

    def test_a_folder_goes_to_the_nas_without_what_is_made_again_in_minutes(self):
        size = self.shelf.keep(self.local, storage.parts(self.local))
        kept = self.shelf.folder(self.local.name)
        self.assertEqual(files(kept), {"shader/cache.bin", "shader/ios/lib.metallib", "ipa/Game.app/Game", "xcode-derived-data/Build/x.o", "logs/build.log"})
        self.assertEqual(size, 120 + 30 + 50 + 20 + 5)
        note = self.shelf.note(self.local.name)
        self.assertEqual(note["size"], size)
        self.assertEqual(note["parts"], {"shaders": 150, "app": 70, "other": 5})
        self.assertAlmostEqual(note["kept"], time.time(), delta=60)
        # This Mac's folder is left as it was: the batch frees it.
        self.assertIn("extract/v0/RomFS.img", files(self.local))

    def test_a_folder_kept_again_replaces_the_one_before_whole(self):
        self.shelf.keep(self.local, storage.parts(self.local))
        (self.local / "shader" / "cache.bin").write_bytes(b"S" * 200)
        (self.local / "shader" / "ios" / "lib.metallib").unlink()
        self.shelf.keep(self.local, storage.parts(self.local))
        kept = self.shelf.folder(self.local.name)
        self.assertEqual((kept / "shader" / "cache.bin").read_bytes(), b"S" * 200)
        self.assertFalse((kept / "shader" / "ios" / "lib.metallib").exists())
        self.assertEqual(sorted(p.name for p in self.shelf.root.iterdir()), [".cartouche-builder", self.local.name])

    def test_a_nas_that_does_not_take_it_keeps_what_it_had(self):
        self.shelf.keep(self.local, storage.parts(self.local))
        before = self.shelf.note(self.local.name)
        (self.local / "shader" / "cache.bin").write_bytes(b"S" * 200)
        (self.local / "shader" / "later.bin").write_bytes(b"x")
        copy = shutil.copyfile

        def nas(source, target, *args, **kwargs):
            # The share gives way half-way, as the player's did.
            if Path(source).name == "later.bin":
                raise OSError(errno.EIO, "Input/output error")
            return copy(source, target, *args, **kwargs)

        with mock.patch("shutil.copyfile", nas), self.assertRaises(OSError):
            self.shelf.keep(self.local, storage.parts(self.local))
        kept = self.shelf.folder(self.local.name)
        self.assertEqual((kept / "shader" / "cache.bin").read_bytes(), b"s" * 120)
        self.assertEqual(self.shelf.note(self.local.name), before)
        self.assertEqual(sorted(p.name for p in self.shelf.root.iterdir()), [".cartouche-builder", self.local.name])

    def test_a_stop_ends_a_copy_half_way_and_leaves_both_as_they_were(self):
        self.shelf.keep(self.local, storage.parts(self.local))
        before = self.shelf.note(self.local.name)
        (self.local / "shader" / "cache.bin").write_bytes(b"S" * 200)
        copied = []

        def stopped():
            copied.append(1)
            return len(copied) > 2

        with self.assertRaises(shelves.Stopped):
            self.shelf.keep(self.local, storage.parts(self.local), stopped=stopped)
        kept = self.shelf.folder(self.local.name)
        self.assertEqual((kept / "shader" / "cache.bin").read_bytes(), b"s" * 120)
        self.assertEqual(self.shelf.note(self.local.name), before)
        self.assertEqual(sorted(p.name for p in self.shelf.root.iterdir()), [".cartouche-builder", self.local.name])
        # Back from the NAS, likewise.
        copied.clear()
        with self.assertRaises(shelves.Stopped):
            self.shelf.fetch(self.local, used=None, stopped=stopped)
        self.assertEqual((self.local / "shader" / "cache.bin").read_bytes(), b"S" * 200)
        self.assertEqual(sorted(p.name for p in self.local.parent.iterdir()), [self.local.name])

    def test_a_folder_comes_back_when_this_mac_has_none_or_an_older_one(self):
        self.shelf.keep(self.local, storage.parts(self.local))
        kept_at = self.shelf.kept_at(self.local.name)
        # This Mac's is newer (the NAS did not take its last one): kept.
        (self.local / "shader" / "cache.bin").write_bytes(b"newer")
        self.assertFalse(self.shelf.fetch(self.local, used=kept_at + 10))
        self.assertEqual((self.local / "shader" / "cache.bin").read_bytes(), b"newer")
        # Older: the NAS's comes in its place, without the game's files.
        self.assertTrue(self.shelf.fetch(self.local, used=kept_at - 10))
        self.assertEqual(files(self.local), {"shader/cache.bin", "shader/ios/lib.metallib", "ipa/Game.app/Game", "xcode-derived-data/Build/x.o", "logs/build.log"})
        self.assertEqual((self.local / "shader" / "cache.bin").read_bytes(), b"s" * 120)
        # None on this Mac: it comes.
        storage_free = self.local.parent
        for path in sorted(self.local.rglob("*"), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
        self.local.rmdir()
        self.assertTrue(self.shelf.fetch(self.local, used=None))
        self.assertTrue((self.local / "shader" / "cache.bin").is_file())
        self.assertEqual(sorted(p.name for p in storage_free.iterdir()), [self.local.name])
        # A game the NAS keeps nothing of.
        other = self.tmp / "mac" / f"{ODYSSEY}_build"
        self.assertFalse(self.shelf.fetch(other, used=None))
        self.assertFalse(other.exists())


class BuildsOnTheMac(BatchHome):
    """Build folders chosen on a NAS, as on the player's Mac."""

    def setUp(self):
        super().setUp()
        self.nas = self.tmp / "nas"
        self.chosen = self.nas / "Builds"
        self.settings(mac=False, workspace=str(self.chosen), shares={str(self.nas): "smb://games@nas.local/Games"})

    def test_the_games_build_on_this_mac_and_their_folders_wait_on_the_nas(self):
        plan, summary = self.run_due(only={ODYSSEY})
        self.assertEqual(summary.failed, [])
        paths = Paths.default()
        kept = self.chosen / f"{ODYSSEY}_build"
        # nxnative built in this Mac's folder, never on the NAS.
        args = json.loads((kept / "args.json").read_text())
        work = Path(args[args.index("--work-dir") + 1])
        self.assertEqual(work, paths.workspace / f"{ODYSSEY}_build")
        self.assertFalse(str(Path(args[args.index("-o") + 1])).startswith(str(self.nas)))
        # Its folder is on the NAS, with its shader cache and not the game's
        # files, and this Mac's is gone.
        self.assertTrue((kept / "shader" / "cache.bin").is_file())
        self.assertFalse((kept / "extract").exists())
        self.assertFalse(work.exists())
        self.assertTrue(any(kind == "message" and value == "Sending its build folder to the NAS…" for kind, title_id, value in self.events if title_id == ODYSSEY))
        # The next build comes from it: nxnative finds its earlier run.
        self.run_due(only={ODYSSEY}, force={ODYSSEY})
        self.assertEqual((kept / "runs.txt").read_text(), "run\nrun\n")
        self.assertFalse(work.exists())

    def test_the_nas_is_mounted_again_before_the_builds(self):
        asked = []
        with mock.patch.object(batch.shares, "reconnect", side_effect=lambda paths, known, log=None: asked.extend(paths)):
            batch.survey(batch.context(), update=False)
        self.assertIn(self.chosen, asked)

    def test_a_failed_build_sends_its_folder_to_the_nas_all_the_same(self):
        self.run_due(only={ODYSSEY})
        os.environ["FAKE_FAIL"] = ODYSSEY
        kept = self.chosen / f"{ODYSSEY}_build"
        plan, summary = self.run_due(only={ODYSSEY}, force={ODYSSEY})
        self.assertEqual([entry.title_id for entry, *_ in summary.failed], [ODYSSEY])
        self.assertEqual((kept / "runs.txt").read_text(), "run\nrun\n")
        self.assertFalse(batch.context().workspace.build_folder(ODYSSEY).exists())

    def test_a_build_stopped_leaves_its_folder_on_this_mac_for_the_next(self):
        self.run_due(only={ODYSSEY})
        kept = self.chosen / f"{ODYSSEY}_build"
        work = batch.context().workspace.build_folder(ODYSSEY)
        os.environ["FAKE_SLEEP"] = "30"
        stop = threading.Event()
        timer = threading.Timer(1.5, stop.set)
        timer.start()
        try:
            plan, summary = self.run_due(only={ODYSSEY}, force={ODYSSEY}, stop=stop)
        finally:
            timer.cancel()
        self.assertTrue(summary.stopped)
        self.assertEqual([value for kind, title_id, value in self.events if value == "Sending its build folder to the NAS…"], ["Sending its build folder to the NAS…"])
        # Not sent half-built: the NAS keeps the one before, this Mac the new one.
        self.assertEqual((kept / "runs.txt").read_text(), "run\n")
        self.assertEqual((work / "runs.txt").read_text(), "run\nrun\n")
        # The next build goes on from this Mac's, newer than the NAS's.
        del os.environ["FAKE_SLEEP"]
        self.run_due(only={ODYSSEY}, force={ODYSSEY})
        self.assertEqual((kept / "runs.txt").read_text(), "run\nrun\nrun\n")
        self.assertFalse(work.exists())

    def test_the_storage_counts_the_nas_folders_apart_and_reads_their_notes(self):
        self.run_due(only={ODYSSEY})
        paths = Paths.default()
        config = configs.load(paths)
        found = storage.survey(config, paths)
        folders = [f for f in found["folders"] if f["title_id"] == ODYSSEY]
        self.assertEqual(len(folders), 1)
        self.assertTrue(folders[0]["shelf"])
        self.assertEqual(folders[0]["parts"]["shaders"], 300)
        self.assertEqual(found["totals"]["shelf"], folders[0]["size"])
        self.assertEqual(found["totals"]["shaders"], 0)
        # The build disk is this Mac's.
        self.assertEqual(found["disks"]["workspace"]["path"], str(paths.workspace))
        # Measured from its note, not the NAS's files again.
        (self.chosen / f"{ODYSSEY}_build" / "shader" / "more.bin").write_bytes(b"m" * 1000)
        again = next(f for f in storage.survey(config, paths)["folders"] if f["title_id"] == ODYSSEY)
        self.assertEqual(again["size"], folders[0]["size"])

    def test_a_folder_left_on_the_nas_before_is_measured_once(self):
        old = self.chosen / f"{MKW}_dump"
        (old / "base" / "romfs").mkdir(parents=True)
        (old / "base" / "romfs" / "data.bin").write_bytes(b"d" * 700)
        paths = Paths.default()
        config = configs.load(paths)
        first = next(f for f in storage.survey(config, paths)["folders"] if f["title_id"] == MKW)
        self.assertEqual(first["size"], 700)
        self.assertTrue(first["shelf"])
        (old / "base" / "romfs" / "more.bin").write_bytes(b"d" * 300)
        second = next(f for f in storage.survey(config, paths)["folders"] if f["title_id"] == MKW)
        self.assertEqual(second["size"], 700)

    def test_the_storage_page_frees_the_nas_folders_by_their_notes(self):
        self.run_due(only={ODYSSEY})
        old = self.chosen / f"{MKW}_build"
        (old / "extract").mkdir(parents=True)
        (old / "extract" / "game.bin").write_bytes(b"d" * 700)
        (old / "shader").mkdir()
        (old / "shader" / "cache.bin").write_bytes(b"s" * 40)
        paths = Paths.default()
        config = configs.load(paths)
        storage.survey(config, paths)
        shelf = shelves.of(config, paths)
        # Its extracted files, freed: its note says so.
        storage.clean(config, paths, "extracted", [str(old)])
        self.assertEqual((shelf.note(old.name)["parts"].get("extracted"), shelf.note(old.name)["size"]), (None, 40))
        again = next(f for f in storage.survey(config, paths)["folders"] if f["title_id"] == MKW)
        self.assertEqual(again["size"], 40)
        # A folder freed: the bytes its note says, not measured again.
        kept = self.chosen / f"{ODYSSEY}_build"
        noted = shelf.noted_size(kept.name)
        (kept / "shader" / "more.bin").write_bytes(b"m" * 1000)
        freed = storage.clean(config, paths, "folders", [str(kept)])
        self.assertEqual(freed["freed"], noted)
        self.assertFalse(kept.exists())
        self.assertIsNone(shelf.note(kept.name))
        # The disk the NAS keeps them on.
        self.assertEqual(storage.survey(config, paths)["disks"]["shelf"]["path"], str(self.chosen))
