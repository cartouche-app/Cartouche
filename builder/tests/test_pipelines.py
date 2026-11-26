"""A game's pipeline archive, made for the GPUs of the paired iPhones too
(pipelines.py, decision 174)."""

import json
import os
import sys
import zipfile
from pathlib import Path
from unittest import mock

from cartouche_builder import batch, build as builds, build_for, pipelines
from cartouche_builder import config as configs
from cartouche_builder import status as statuses
from cartouche_builder.paths import Paths

from support import MKW, ODYSSEY, Home, commit, make_dump, make_engine_remote

PYTHON = Path(sys.executable)
NAMES = {MKW: "Mario Kart World", ODYSSEY: "Super Mario Odyssey"}
# Breath of the Wild's profile, as nxnative has it at 2f959ede (26 November
# 2026), the only one with pso_mtl4 on: no pso_gpu, so g18p.
METAL4 = "# a game on the Metal 4 path\ntitle_id\t{id}\nname\t{name}\npresent_snap\ton\npso_mtl4\ton\n"


def device(name="iPhone de Lou", gpu="applegpu_g19p", ios=27, model="iPhone19,1"):
    return build_for.Device(name, model, True, gpu, ios)


def pair(paths: Paths, *devices: dict) -> None:
    """bridge.json as the app writes it (BridgeDevices.swift)."""
    rows = [{"id": f"device-{n}", "key": "c2VjcmV0", "paired": "2026-11-26T10:00:00Z", **d} for n, d in enumerate(devices)]
    paths.bridge.parent.mkdir(parents=True, exist_ok=True)
    paths.bridge.write_text(json.dumps({"mac": "mac-id", "devices": rows}))


class Profiles(Home):
    def profile(self, text: str | None) -> Path:
        root = self.tmp / "nxnative"
        folder = root / "dm" / "games" / MKW
        folder.mkdir(parents=True, exist_ok=True)
        if text is not None:
            (folder / "game.tsv").write_text(text)
        return root

    def test_a_profile_on_the_metal_4_path_gets_g18p_by_default(self):
        root = self.profile(METAL4.format(id=MKW, name="Mario Kart World"))
        self.assertEqual(pipelines.profile_default(root, MKW), ["g18p"])
        self.assertEqual(pipelines.profile_default(root, MKW.lower()), ["g18p"])

    def test_its_pso_gpu_names_others(self):
        root = self.profile(METAL4.format(id=MKW, name="Wonder") + "pso_gpu\tg18p applegpu_g17p\n")
        self.assertEqual(pipelines.profile_default(root, MKW), ["g18p", "g17p"])
        # As build_ipa.sh takes it: more than four, or a word that is no
        # GPU, and it is g18p.
        root = self.profile(METAL4.format(id=MKW, name="Wonder") + "pso_gpu\tg15p g16p g17p g18p g19p\n")
        self.assertEqual(pipelines.profile_default(root, MKW), ["g18p"])
        root = self.profile(METAL4.format(id=MKW, name="Wonder") + "pso_gpu\tnone\n")
        self.assertEqual(pipelines.profile_default(root, MKW), ["g18p"])

    def test_no_archive_without_the_metal_4_path_or_a_profile(self):
        """An app that would carry an archive it never reads gets none."""
        self.assertEqual(pipelines.profile_default(self.profile("title_id\tx\nname\tMario Kart World\n"), MKW), [])
        self.assertEqual(pipelines.profile_default(self.profile("pso_mtl4\toff\n"), MKW), [])
        self.assertEqual(pipelines.profile_default(self.profile("# pso_mtl4\ton\n"), MKW), [])
        self.assertEqual(pipelines.profile_default(self.profile(None), MKW), [])


class Choosing(Home):
    def test_the_paired_iphones_gpus_join_the_profiles(self):
        choice = pipelines.choose(["g18p"], [device(), device("iPad", "applegpu_g17g", 27, "iPad16,1")], "27.2")
        self.assertEqual((choice.gpus, choice.added, choice.left_out), (["g18p", "g19p", "g17g"], ["g19p", "g17g"], []))
        self.assertEqual(choice.option, "g18p,g19p,g17g")

    def test_an_iphone_17_adds_nothing_and_nxnative_keeps_its_default(self):
        choice = pipelines.choose(["g18p"], [device(gpu="applegpu_g18p"), device(gpu="g18p")], "27.2")
        self.assertEqual((choice.gpus, choice.added), (["g18p"], []))
        self.assertIsNone(choice.option)

    def test_a_game_without_an_archive_gets_none_for_them_either(self):
        choice = pipelines.choose([], [device()], "27.2")
        self.assertEqual((choice.gpus, choice.option), ([], None))

    def test_an_iphone_on_another_ios_than_the_archives_is_left_out(self):
        """It could not open it: an archive is made for the SDK's major
        version (DM_PSO_IOS_MIN)."""
        choice = pipelines.choose(["g18p"], [device(ios=26), device("iPad", "applegpu_g17g", None, "iPad16,1")], "27.2")
        self.assertEqual((choice.gpus, choice.left_out), (["g18p", "g17g"], [("g19p", "ios")]))
        # Without the SDK's version (no Xcode), it is not left out for it.
        self.assertEqual(pipelines.choose(["g18p"], [device(ios=26)], None).gpus, ["g18p", "g19p"])

    def test_a_gpu_metal_tt_refused_and_four_at_most(self):
        devices = [device(gpu=f"applegpu_g{n}p") for n in (15, 16, 17, 19, 20)]
        choice = pipelines.choose(["g18p"], devices, "27.2", refused={"g20p"})
        self.assertEqual(choice.gpus, ["g18p", "g15p", "g16p", "g17p"])
        self.assertEqual(choice.left_out, [("g19p", "most"), ("g20p", "refused")])

    def test_what_nxnative_says_of_the_archive(self):
        watch = pipelines.Watch()
        watch.read("pipeline archive: g18p,g20p (made on this Mac with metal-tt; --gpu none leaves it out)")
        watch.read("[12:00:01] [RED] pso_offline: metal-tt failed for applegpu_g20p (exit 1): applegpu-nt: error: unknown target")
        choice = pipelines.Choice(gpus=["g18p", "g20p"], added=["g20p"])
        self.assertEqual(watch.refused(choice), [], "the archive has not failed as a whole")
        watch.read("[RED] pipeline archive: pso_offline.py failed (its output is above); the app is built without one")
        self.assertEqual(watch.refused(choice), ["g20p"])
        # The profile's own GPU failing is not the iPhone's doing.
        self.assertEqual(watch.refused(pipelines.Choice(gpus=["g20p"])), [])

    def test_what_metal_tt_refused_holds_until_apples_tools_change(self):
        paths = Paths.default()
        self.assertEqual(pipelines.refused(paths, "Xcode 27.2 (27C55), iOS SDK 27.2"), set())
        pipelines.refuse(paths, "Xcode 27.2 (27C55), iOS SDK 27.2", ["applegpu_g20p", "not a gpu"])
        pipelines.refuse(paths, "Xcode 27.2 (27C55), iOS SDK 27.2", ["g21p"])
        self.assertEqual(pipelines.refused(paths, "Xcode 27.2 (27C55), iOS SDK 27.2"), {"g20p", "g21p"})
        self.assertEqual(pipelines.refused(paths, "Xcode 27.3 (27D10), iOS SDK 27.3"), set())
        (paths.root / "pipelines.json").write_text("{")
        self.assertEqual(pipelines.refused(paths, "Xcode 27.2 (27C55), iOS SDK 27.2"), set())

    def test_the_paired_iphones_tell_their_gpu_and_ios(self):
        paths = Paths.default()
        pair(paths, {"name": "iPhone de Lou", "model": "iPhone19,1", "readsBC": True, "gpu": "applegpu_g19p", "iOS": 27},
             {"name": "iPhone", "model": "iPhone18,1"},
             {"name": "odd", "gpu": "g19p --platform mac", "iOS": True}, {"name": "odd too", "gpu": 19, "iOS": 0})
        found = build_for.paired(paths)
        self.assertEqual([(d.gpu, d.ios) for d in found], [("applegpu_g19p", 27), ("", None), ("", None), ("", None)])

    def test_the_command_names_them_for_the_ipa_only(self):
        ipa = builds.command(PYTHON, Path("b.py"), Path("src"), Path("w"), Path("o.ipa"), None, gpus="g18p,g19p")
        self.assertEqual(ipa[ipa.index("--gpu") + 1], "g18p,g19p")
        self.assertNotIn("--gpu", builds.command(PYTHON, Path("b.py"), Path("src"), Path("w"), Path("o.ipa"), None))
        # For a Mac app, --gpu is the Mac's own archive: left to nxnative.
        self.assertNotIn("--gpu", builds.command(PYTHON, Path("b.py"), Path("src"), Path("w"), Path("o.app"), None, platform="mac-app", gpus="g18p,g19p"))


class Batches(Home):
    """nxnative's fake, Mario Kart World's profile on the Metal 4 path."""

    def setUp(self):
        super().setUp()
        self.remote = make_engine_remote(self.tmp / "remote", NAMES)
        commit(self.remote, "Mario Kart World: the Metal 4 path", {f"dm/games/{MKW}/game.tsv": METAL4.format(id=MKW, name="Mario Kart World")})
        self.sources = self.tmp / "sources"
        make_dump(self.sources / "Mario Kart World", MKW)
        make_dump(self.sources / "Super Mario Odyssey", ODYSSEY)
        self.games = self.tmp / "games"
        self.games.mkdir()
        self.paths = Paths.default()
        configs.save(self.paths, configs.Config(sources=str(self.sources), games=str(self.games), engine_url=str(self.remote), min_free_gb=0, mac=False))
        self.events = []

    def run_due(self, **kwargs):
        follow = lambda kind, title_id, value: self.events.append((kind, title_id, value))
        return batch.run_due(batch.context(), python=PYTHON, check_tools=False, on_event=follow, **kwargs)

    def args(self, title_id):
        return json.loads((batch.context().workspace.build_folder(title_id) / "args.json").read_text())

    def log(self, title_id):
        """The game's log of its last build."""
        return sorted((self.paths.logs / title_id).glob("*.log"))[-1].read_text()

    def archives(self, title_id):
        with zipfile.ZipFile(self.games / f"{NAMES[title_id]} [{title_id}].ipa") as ipa:
            return sorted(n.rsplit("/", 1)[-1] for n in ipa.namelist() if "/pso/" in n)

    def test_the_archive_is_made_for_a_paired_iphones_gpu_too(self):
        pair(self.paths, {"name": "iPhone de Lou", "model": "iPhone19,1", "readsBC": True, "gpu": "applegpu_g19p", "iOS": 27})
        with mock.patch.object(batch.toolchain, "ios_sdk", return_value="27.2"):
            plan, summary = self.run_due()
        self.assertEqual((len(plan.to_build), summary.failed), (2, []))
        args = self.args(MKW)
        self.assertEqual(args[args.index("--gpu") + 1], "g18p,g19p")
        self.assertEqual(self.archives(MKW), ["applegpu_g18p.mtl4a", "applegpu_g19p.mtl4a"])
        self.assertEqual(batch.context().store.get(MKW).build.gpus, ["g18p", "g19p"])
        # Odyssey's profile asks for no archive: none for the iPhone either.
        self.assertNotIn("--gpu", self.args(ODYSSEY))
        self.assertEqual(batch.context().store.get(ODYSSEY).build.gpus, [])
        # What the app reads of the batch: the GPUs, and how many the
        # iPhones added; the game's log says which, never the iPhone's name.
        games = {g["title_id"]: g for g in statuses.read(self.paths)["games"]}
        self.assertEqual((games[MKW]["gpus"], games[MKW]["gpus_added"]), (["g18p", "g19p"], 1))
        self.assertEqual((games[ODYSSEY]["gpus"], games[ODYSSEY]["gpus_added"]), ([], 0))
        log = self.log(MKW)
        self.assertIn("# pipeline archive for g18p, g19p: g19p for the paired iPhones", log)
        self.assertNotIn("Lou", log)

    def test_without_an_iphone_that_adds_one_nxnative_keeps_its_default(self):
        pair(self.paths, {"name": "iPhone 17 Pro", "model": "iPhone18,1", "readsBC": True, "gpu": "applegpu_g18p", "iOS": 27},
             {"name": "iPhone 18 Pro", "model": "iPhone19,1", "readsBC": True, "gpu": "applegpu_g19p", "iOS": 28})
        with mock.patch.object(batch.toolchain, "ios_sdk", return_value="27.2"):
            self.run_due()
        self.assertNotIn("--gpu", self.args(MKW))
        self.assertEqual(batch.context().store.get(MKW).build.gpus, ["g18p"])
        log = self.log(MKW)
        self.assertIn("g19p left out, on another major version of iOS than the archive's", log)

    def test_a_gpu_metal_tt_does_not_know_is_left_out_and_the_game_built_again(self):
        """nxnative packs the app with no archive at all then, g18p's too:
        built again at once without that GPU, and so are the next builds
        until Apple's tools change."""
        pair(self.paths, {"name": "iPhone", "model": "iPhone20,1", "readsBC": True, "gpu": "applegpu_g20p", "iOS": 27})
        with mock.patch.dict(os.environ, {"FAKE_METAL_TT": f"{MKW}:g20p"}), mock.patch.object(batch.toolchain, "ios_sdk", return_value="27.2"):
            plan, summary = self.run_due(only={MKW})
        self.assertEqual(summary.failed, [])
        work = batch.context().workspace.build_folder(MKW)
        self.assertEqual((work / "runs.txt").read_text().count("run"), 2)
        self.assertNotIn("--gpu", self.args(MKW), "built again with nxnative's own default")
        build = batch.context().store.get(MKW).build
        self.assertEqual(build.gpus, ["g18p"])
        # For the tools it was built with: none on a Linux runner, this
        # Mac's Xcode on a Mac.
        self.assertEqual(pipelines.refused(self.paths, build.toolchain), {"g20p"})
        self.assertEqual(pipelines.refused(self.paths, build.toolchain + " and another"), set())
