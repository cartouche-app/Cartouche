"""Whom the games are built for, and so which nxnative builds them (build_for.py)."""

import json
import os
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

from cartouche_builder import api, batch, build_for, library
from cartouche_builder import config as configs
from cartouche_builder.paths import Paths
from cartouche_builder.planner import fingerprint, plan
from cartouche_builder.state import Build

from support import MKW, ODYSSEY, Home, commit, git, make_dump, make_engine_remote, make_ipa
from test_engine_planner import NAMES, PlanHome

PYTHON = Path(sys.executable)
# The app's own copy of the rule (BuildFor.swift) is checked against these
# answers of the engine's (BuildForTests.swift).
FIXTURE = Path(__file__).resolve().parents[1] / "mac" / "Tests" / "BuilderKitTests" / "Fixtures" / "build-for.json"
EXAMPLE_MODELS = (
    [f"iPhone{major},{minor}" for major, minors in ((12, (1, 3, 5, 8)), (13, (1, 2, 3, 4)), (14, (2, 3, 4, 5, 6, 7, 8)), (15, (2, 3, 4, 5)), (16, (1, 2)),
                                                  (17, (1, 2, 3, 4, 5)), (18, (1, 2, 3, 4)), (19, (1, 2, 4))) for minor in minors]
    + [f"iPad{major},{minor}" for major, minors in ((12, (1, 2)), (13, (1, 2, 4, 8, 16, 17, 18, 19)), (14, (1, 2, 3, 5, 8, 10)), (15, (3, 5, 7, 8)),
                                                 (16, (1, 3, 5)), (17, (1,))) for minor in minors]
    + ["Mac16,12", "", "iPhone15", "iPhone15,", "iPhone 15,4", "iPhone١٥,4"]
)
EXAMPLE_CHOICES = [
    ({}, []),
    ({}, [{"name": "iPhone 17 Pro", "model": "iPhone18,1", "readsBC": True}, {"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False}]),
    ({}, [{"name": "iPhone de Lou", "model": "iPhone15,4"}]),
    ({}, [{"name": "iPad", "model": "iPad13,4", "readsBC": False}]),
    ({}, [{"name": "iPhone"}]),
    ({"build_for": "iPhone18,2"}, [{"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False}]),
    ({"build_for": "iPhone14,7"}, []),
    ({"build_for": "iPad15,7"}, []),
    ({"engine_url": "https://github.com/someone/nxnative.git", "engine_branch": "dev", "build_for": "iPhone15,4"}, []),
    ({"engine_url": "https://github.com/seedds/nxnative/"}, [{"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False}]),
]
FORK = build_for.key(build_for.FORK_URL, build_for.FORK_BRANCH)
NXNATIVE = build_for.key(configs.ENGINE_URL, configs.ENGINE_BRANCH)


def pair(paths: Paths, *devices: dict) -> None:
    """bridge.json as the app writes it (BridgeDevices.swift): each device
    with its key, which the engine never reads."""
    rows = [{"id": f"device-{n}", "key": "c2VjcmV0", "paired": "2026-11-24T10:00:00Z", **device} for n, device in enumerate(devices)]
    paths.bridge.parent.mkdir(parents=True, exist_ok=True)
    paths.bridge.write_text(json.dumps({"mac": "mac-id", "devices": rows}))


class Models(unittest.TestCase):
    def test_the_iphones_up_to_the_a16_read_no_bc(self):
        for model in ("iPhone12,1", "iPhone14,6", "iPhone14,7", "iPhone15,2", "iPhone15,4", "iPhone15,5"):
            self.assertFalse(build_for.reads_bc(model), model)
        for model in ("iPhone16,1", "iPhone16,2", "iPhone17,5", "iPhone18,4", "iPhone19,4"):
            self.assertTrue(build_for.reads_bc(model), model)

    def test_ipads_with_an_a_chip_before_the_a17_pro_read_no_bc(self):
        for model in ("iPad12,1", "iPad13,1", "iPad13,18", "iPad14,1", "iPad15,7", "iPad15,8"):
            self.assertFalse(build_for.reads_bc(model), model)
        for model in ("iPad13,4", "iPad13,16", "iPad14,3", "iPad14,8", "iPad15,3", "iPad16,1", "iPad16,5", "iPad17,1"):
            self.assertTrue(build_for.reads_bc(model), model)

    def test_a_mac_or_an_unknown_name_reads_bc(self):
        for model in ("Mac16,12", "", "iPhone", "iPhone15", "x86_64"):
            self.assertTrue(build_for.reads_bc(model), model)


class Sources(unittest.TestCase):
    def test_nxnative_with_no_iphone_paired(self):
        source = build_for.source(configs.Config(), [])
        self.assertEqual((source.url, source.branch, source.kind), (configs.ENGINE_URL, "main", "nxnative"))
        self.assertFalse(source.fork)

    def test_the_fork_for_a_paired_iphone_without_bc(self):
        devices = [build_for.Device("iPhone 17 Pro", "iPhone18,1"), build_for.Device("iPhone de Lou", "iPhone15,4")]
        source = build_for.source(configs.Config(), devices)
        self.assertEqual((source.url, source.branch, source.kind), (build_for.FORK_URL, "no-bc", "no-bc"))
        self.assertEqual((source.model, source.device), ("iPhone15,4", "iPhone de Lou"))
        self.assertEqual(source.key, FORK)

    def test_what_cartouche_says_of_its_gpu_wins_over_the_model(self):
        self.assertEqual(build_for.source(configs.Config(), [build_for.Device("iPad", "iPad13,4", said=False)]).kind, "no-bc")
        self.assertEqual(build_for.source(configs.Config(), [build_for.Device("iPhone", "iPhone15,4", said=True)]).kind, "nxnative")

    def test_an_older_cartouche_that_said_nothing_counts_for_nothing(self):
        self.assertEqual(build_for.source(configs.Config(), [build_for.Device("iPhone")]).kind, "nxnative")

    def test_the_model_chosen_wins_over_the_paired_iphones(self):
        without = [build_for.Device("iPhone de Lou", "iPhone15,4")]
        self.assertEqual(build_for.source(configs.Config(build_for="iPhone18,2"), without).kind, "nxnative")
        chosen = build_for.source(configs.Config(build_for="iPhone14,7"), [])
        self.assertEqual((chosen.kind, chosen.model, chosen.device), ("no-bc", "iPhone14,7", ""))

    def test_a_repository_chosen_under_advanced_wins_over_both(self):
        config = configs.Config(engine_url="https://github.com/someone/nxnative.git", engine_branch="dev", build_for="iPhone15,4")
        source = build_for.source(config, [build_for.Device("iPhone de Lou", "iPhone15,4")])
        self.assertEqual((source.url, source.branch, source.kind), ("https://github.com/someone/nxnative.git", "dev", "custom"))
        # nxnative's own, written otherwise, is still nxnative's.
        self.assertFalse(build_for.custom(configs.Config(engine_url="https://github.com/seedds/nxnative/")))

    def test_their_names(self):
        self.assertEqual(build_for.label(NXNATIVE), "nxnative")
        self.assertEqual(build_for.label(FORK), "nxnative's no-bc variant, by mianmuhammadse")
        self.assertEqual(build_for.label("https://github.com/someone/nxnative#dev"), "someone/nxnative (branch dev)")


class AppExamples(unittest.TestCase):
    def test_the_apps_examples_are_the_engines(self):
        """CARTOUCHE_BUILDER_FIXTURES=write writes them again."""
        choices = []
        for settings, devices in EXAMPLE_CHOICES:
            paired = [build_for.Device(d["name"], d.get("model", ""), d.get("readsBC")) for d in devices]
            source = build_for.source(configs.Config(**settings), paired)
            choices.append({"config": settings, "devices": devices, "kind": source.kind, "model": source.model, "device": source.device})
        examples = {"models": {model: build_for.reads_bc(model) for model in EXAMPLE_MODELS}, "choices": choices}
        if os.environ.get("CARTOUCHE_BUILDER_FIXTURES") == "write":
            FIXTURE.write_text(json.dumps(examples, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        self.assertEqual(json.loads(FIXTURE.read_text(encoding="utf-8")), examples, "CARTOUCHE_BUILDER_FIXTURES=write writes them again")


class Settings(Home):
    def test_build_for_is_a_model_or_nothing(self):
        paths = Paths.default()
        configs.save(paths, configs.Config(build_for="iPhone15,4"))
        self.assertEqual(configs.load(paths).build_for, "iPhone15,4")
        with self.assertRaises(ValueError):
            configs.Config(build_for="iPhone 15").validate()


class Paired(Home):
    def test_the_paired_iphones_their_names_and_models_never_their_keys(self):
        paths = Paths.default()
        pair(paths, {"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False}, {"name": "iPad"}, {"name": 3, "model": "../x", "readsBC": "no"})
        found = build_for.paired(paths)
        self.assertEqual(found, [build_for.Device("iPhone de Lou", "iPhone15,4", False), build_for.Device("iPad"), build_for.Device("")])
        self.assertNotIn("c2VjcmV0", repr(found))

    def test_no_file_or_a_damaged_one_pairs_nothing(self):
        paths = Paths.default()
        self.assertEqual(build_for.paired(paths), [])
        paths.root.mkdir(parents=True, exist_ok=True)
        paths.bridge.write_text("{")
        self.assertEqual(build_for.paired(paths), [])

    def test_the_batch_builds_from_the_fork_for_a_paired_iphone_without_bc(self):
        paths = Paths.default()
        configs.save(paths, configs.Config())
        self.assertEqual((batch.context().engine.url, batch.context().engine.branch), (configs.ENGINE_URL, "main"))
        pair(paths, {"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False})
        ctx = batch.context()
        self.assertEqual((ctx.engine.url, ctx.engine.branch, ctx.source_key), (build_for.FORK_URL, "no-bc", FORK))


class Planning(PlanHome):
    def plan_from(self, source):
        found = library.discover(self.sources, NAMES)
        entries = plan(found.games, self.engine, self.engine.head(), self.engine.profiles(), self.store, self.config, self.games, "", mac=self.place, source=source).entries
        return {e.title_id: e for e in entries}

    def built(self, title_id, engine=""):
        game = next(g for g in library.discover(self.sources, NAMES).games if g.title_id == title_id)
        name = f"{NAMES[title_id]} [{title_id}].ipa"
        make_ipa(self.games / name, {"DMTitleID": title_id, "DMCommit": self.engine.head()[:12]})
        when = time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime())
        self.store.built(title_id, Build(commit=self.engine.head()[:12], built_at=when, ipa=name, fingerprint=fingerprint(game), engine=engine))

    def test_an_ipa_from_nxnative_is_built_again_from_the_fork(self):
        # Built before builds said their nxnative: from the settings' one.
        self.built(MKW)
        self.built(ODYSSEY, engine=FORK)
        entries = self.plan_from(FORK)
        self.assertTrue(entries[MKW].build)
        self.assertEqual(entries[MKW].reasons, ["engine"])
        self.assertEqual(entries[MKW].detail, "Built from nxnative; the games are built from nxnative's no-bc variant, by mianmuhammadse now")
        self.assertEqual(entries[ODYSSEY].reasons, ["up_to_date"])

    def test_and_back_from_nxnative_once_no_iphone_needs_the_fork(self):
        self.built(MKW, engine=FORK)
        self.built(ODYSSEY)
        entries = self.plan_from(NXNATIVE)
        self.assertEqual(entries[MKW].reasons, ["engine"])
        self.assertEqual(entries[ODYSSEY].reasons, ["up_to_date"])

    def test_a_game_built_for_this_mac_alone_stays(self):
        self.config.ios = False
        self.config.mac = True
        self.mac_built(MKW)
        self.assertEqual(self.plan_from(FORK)[MKW].reasons, ["up_to_date"])


class Batches(Home):
    """nxnative's fake and a fork of it, branch no-bc, with a commit of its
    own, both on this disk in place of GitHub's."""

    def setUp(self):
        super().setUp()
        self.remote = make_engine_remote(self.tmp / "remote", NAMES)
        self.fork = self.tmp / "fork"
        git(self.tmp, "clone", "-q", str(self.remote), str(self.fork))
        git(self.fork, "checkout", "-q", "-b", "no-bc")
        self.fork_head = commit(self.fork, "No BC: BC1-3 stored as ASTC 4x4", {"dm/gfx/nvn/nvn_bc2astc.h": "// the fork's\n"})
        self.enterContext(mock.patch.object(build_for, "ENGINE_URL", str(self.remote)))
        self.enterContext(mock.patch.object(build_for, "FORK_URL", str(self.fork)))
        self.sources = self.tmp / "sources"
        make_dump(self.sources / "Mario Kart World", MKW)
        self.games = self.tmp / "games"
        self.games.mkdir()
        self.paths = Paths.default()
        configs.save(self.paths, configs.Config(sources=str(self.sources), games=str(self.games), engine_url=str(self.remote), min_free_gb=0, mac=False))

    def run_due(self):
        return batch.run_due(batch.context(), python=PYTHON, check_tools=False)

    def test_a_paired_iphone_without_bc_rebuilds_the_games_from_the_fork(self):
        plan, summary = self.run_due()
        self.assertEqual((len(plan.to_build), summary.failed), (1, []))
        record = batch.context().store.get(MKW)
        self.assertEqual(record.build.engine, build_for.key(str(self.remote), "main"))
        self.assertNotEqual(record.build.commit, self.fork_head[:12])

        pair(self.paths, {"name": "iPhone de Lou", "model": "iPhone15,4", "readsBC": False})
        plan, summary = self.run_due()
        self.assertEqual([e.reasons for e in plan.to_build], [["engine"]])
        self.assertEqual(summary.failed, [])
        ctx = batch.context()
        self.assertEqual(ctx.store.get(MKW).build.commit, self.fork_head[:12])
        self.assertEqual(ctx.store.get(MKW).build.engine, build_for.key(str(self.fork), "no-bc"))
        info = api.engine_info(ctx, ctx.engine.head())
        self.assertEqual((info["kind"], info["url"], info["branch"], info["model"], info["device"]), ("no-bc", str(self.fork), "no-bc", "iPhone15,4", "iPhone de Lou"))

        # Up to date from then on, until no paired iPhone needs the fork.
        plan, _ = self.run_due()
        self.assertEqual(plan.to_build, [])
        pair(self.paths, {"name": "iPhone 17 Pro", "model": "iPhone18,1", "readsBC": True})
        plan, summary = self.run_due()
        self.assertEqual([e.reasons for e in plan.to_build], [["engine"]])
        self.assertEqual(batch.context().store.get(MKW).build.engine, build_for.key(str(self.remote), "main"))


if __name__ == "__main__":
    unittest.main()
