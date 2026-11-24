"""nxnative's newest commit, when its app build fails: the batch goes to the
last commit that built on this Mac (fallback.py); when it splits a game's
shaders otherwise than its profile says: the game builds from the commit
before nxnative's splitter changed (fallback.py too); and why a game was not
built, said to the player and kept for the app (causes.py, disks.py)."""

import contextlib
import errno
import io
import json
import os
import sys
import threading
from dataclasses import asdict
from pathlib import Path
from unittest import mock

from cartouche_builder import api, batch, causes, config as configs, fallback
from cartouche_builder import status as statuses
from cartouche_builder.build import Result
from cartouche_builder.engine import EngineError
from cartouche_builder.paths import Paths
from cartouche_builder.state import Build, Record

from support import HOLLOW, MKW, ODYSSEY, Home, commit, git, make_dump, make_engine_remote

NAMES = {MKW: "Mario Kart World", ODYSSEY: "Super Mario Odyssey"}
PYTHON = Path(sys.executable)


class Base(Home):
    def setUp(self):
        super().setUp()
        self.remote = make_engine_remote(self.tmp / "remote", NAMES)
        self.sources = self.tmp / "sources"
        make_dump(self.sources / "Mario Kart World", MKW)
        make_dump(self.sources / "Super Mario Odyssey", ODYSSEY)
        self.games = self.tmp / "games"
        self.games.mkdir()
        configs.save(Paths.default(), configs.Config(sources=str(self.sources), games=str(self.games), engine_url=str(self.remote), min_free_gb=0))

    def run_due(self, **kwargs):
        return batch.run_due(batch.context(), python=PYTHON, check_tools=False, **kwargs)

    def api(self, *args: str) -> dict:
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            api.main(list(args))
        return json.loads(out.getvalue())

    def runs(self, title_id: str) -> int:
        return (batch.context().workspace.build_folder(title_id) / "runs.txt").read_text().count("run")

    def game(self, title_id: str) -> dict:
        return next(g for g in statuses.read(Paths.default())["games"] if g["title_id"] == title_id)


class Fallback(Base):
    def test_a_commit_that_does_not_build_falls_back_to_the_last_that_did(self):
        plan, summary = self.run_due()
        self.assertEqual(len(summary.built), 2)
        good = batch.context().engine.head()
        broken = commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        plan, summary = self.run_due(force={MKW, ODYSSEY})
        # The first game's app build failed at the newest commit, built from
        # the good one, and the second game was built from it at once.
        self.assertEqual(summary.failed, [])
        self.assertEqual(sorted(entry.title_id for entry, _ in summary.built), sorted(NAMES))
        self.assertEqual(sorted(self.runs(title_id) for title_id in NAMES), [2, 3])
        ctx = batch.context()
        self.assertEqual(ctx.engine.head(), good)
        self.assertEqual({title_id: ctx.store.get(title_id).build.commit for title_id in NAMES}, {MKW: good[:12], ODYSSEY: good[:12]})
        self.assertEqual(list(fallback.broken(ctx.paths)), [broken])
        status = statuses.read(ctx.paths)
        self.assertEqual((status["head"], status["latest"], status["fallback"]), (good, broken, {"from": broken, "to": good}))
        self.assertEqual({g["title_id"]: (g["state"], g["commit"], g["fallback"]) for g in status["games"]},
                         {MKW: ("built", good[:12], True), ODYSSEY: ("built", good[:12], True)})
        self.assertTrue(any("is broken for now" in line for line in status["lines"]), status["lines"])
        self.assertIn(good[:12], summary.report.read_text())
        self.assertEqual(summary.head, good)

        # The next batches stay on it while the newest is the broken one.
        said = []
        plan, summary = self.run_due(log=said.append)
        self.assertEqual(plan.to_build, [])
        self.assertEqual(batch.context().engine.head(), good)
        self.assertTrue(any("does not build for now" in line for line in said), said)
        engine = self.api("library")["engine"]
        self.assertEqual((engine["head"], engine["latest"], engine["latest_short"], engine["held"]), (good, broken, broken[:12], True))
        # A game built while the builder stays there says so, as its batch does.
        plan, summary = self.run_due(force={MKW})
        self.assertEqual(statuses.read(batch.context().paths)["fallback"], {"from": broken, "to": good})
        self.assertEqual((self.game(MKW)["state"], self.game(MKW)["commit"], self.game(MKW)["fallback"]), ("built", good[:12], True))

        # A newer commit is tried, and builds.
        fixed = commit(self.remote, "Mario Kart World: link the probes again (PR #1522)", {"BROKEN": None})
        plan, summary = self.run_due()
        self.assertEqual([entry.title_id for entry, _ in summary.built], [MKW])
        ctx = batch.context()
        self.assertEqual((ctx.engine.head(), ctx.store.get(MKW).build.commit), (fixed, fixed[:12]))
        status = statuses.read(ctx.paths)
        self.assertIsNone(status["fallback"])
        self.assertEqual((self.game(MKW)["commit"], self.game(MKW)["fallback"]), (fixed[:12], False))
        self.assertNotIn("latest", self.api("library")["engine"])

    def test_the_newest_commit_is_not_blamed_when_the_old_one_fails_too(self):
        self.run_due(only={MKW})
        newest = commit(self.remote, "Mario Kart World's menus (PR #3)", {"dm/host/menu.c": "x"})
        os.environ["FAKE_APP_BUILD"] = MKW
        plan, summary = self.run_due(only={MKW})
        self.assertEqual([entry.title_id for entry, _, _ in summary.failed], [MKW])
        self.assertEqual(self.runs(MKW), 3)
        ctx = batch.context()
        # Back to the newest commit, which is not marked, and the failure is
        # recorded at it: the next batch, there, does not try it again.
        self.assertEqual(ctx.engine.head(), newest)
        self.assertEqual(fallback.broken(ctx.paths), {})
        attempt = ctx.store.get(MKW).attempt
        self.assertEqual((attempt.result, attempt.commit), ("failed", newest[:12]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["exit"], game["stage"]), ("failed", "app_build", 1, "app build"))
        self.assertGreater(game["duration"], 0)
        self.assertIsNone(statuses.read(ctx.paths)["fallback"])
        self.assertTrue(any("is not the cause" in line for line in statuses.read(ctx.paths)["lines"]))
        plan, summary = self.run_due(only={MKW})
        self.assertEqual([entry.reasons for entry in plan.entries if entry.title_id == MKW], [["failed_here"]])

    def test_no_fallback_without_a_commit_that_built_here(self):
        commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(len(summary.failed), 1)
        self.assertEqual(self.runs(MKW), 1)
        self.assertEqual(self.game(MKW)["cause"], "app_build")
        self.assertEqual(fallback.broken(Paths.default()), {})

    def test_a_game_built_from_a_newer_commit_is_up_to_date_while_held(self):
        self.run_due()
        good = batch.context().engine.head()
        # Only Mario Kart World's app build fails at the newest commit.
        os.environ["FAKE_BROKEN_ONLY"] = MKW
        broken = commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        self.run_due(only={ODYSSEY}, force={ODYSSEY})
        ctx = batch.context()
        self.assertEqual(ctx.store.get(ODYSSEY).build.commit, broken[:12])
        plan, summary = self.run_due(only={MKW}, force={MKW})
        self.assertEqual([entry.title_id for entry, _ in summary.built], [MKW])
        self.assertEqual(ctx.store.get(MKW).build.commit, good[:12])
        plan = batch.survey(batch.context())
        odyssey = next(entry for entry in plan.entries if entry.title_id == ODYSSEY)
        self.assertEqual((plan.head, odyssey.build, odyssey.reasons), (good, False, ["up_to_date"]))
        self.assertIn(broken[:12], odyssey.detail)

    def test_two_games_at_once_wait_for_the_trial(self):
        paths = Paths.default()
        config = configs.load(paths)
        config.jobs = 2
        configs.save(paths, config)
        self.run_due()
        good = batch.context().engine.head()
        commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        plan, summary = self.run_due(force={MKW, ODYSSEY})
        ctx = batch.context()
        self.assertEqual(ctx.engine.head(), good)
        # Both failed at the newest commit at once: one built again from the
        # good one as the trial, alone, the other's failure recorded. Its
        # IPA of the good commit is up to date with the next batch, which
        # stays there.
        self.assertEqual((len(summary.built), len(summary.failed)), (1, 1))
        self.assertEqual({title_id: ctx.store.get(title_id).build.commit for title_id in NAMES}, {MKW: good[:12], ODYSSEY: good[:12]})
        plan, summary = self.run_due()
        self.assertEqual(plan.to_build, [])

    def test_a_game_waiting_its_turn_builds_after_the_trial(self):
        commit(self.remote, "Hollow Knight's profile", {f"dm/games/{HOLLOW}/game.tsv": f"title_id\t{HOLLOW}\nname\tHollow Knight\n"})
        make_dump(self.sources / "Hollow Knight", HOLLOW)
        paths = Paths.default()
        config = configs.load(paths)
        config.jobs = 2
        configs.save(paths, config)
        self.run_due()
        good = batch.context().engine.head()
        commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        plan, summary = self.run_due(force={MKW, ODYSSEY, HOLLOW})
        third = plan.to_build[2].title_id
        # Two games build at once, and fail at the newest commit; the third,
        # waiting its turn, waits for the trial, then builds from the commit
        # it confirmed, as the batch says.
        self.assertEqual(batch.context().engine.head(), good)
        failed = [entry.title_id for entry, _, _ in summary.failed]
        self.assertLessEqual(len(failed), 1)
        self.assertNotIn(third, failed)
        game = self.game(third)
        self.assertEqual((game["state"], game["commit"], game["fallback"]), ("built", good[:12], True))

    def test_the_last_commit_that_built_is_the_builders_own_on_the_branch(self):
        ctx = batch.context()
        ctx.engine.update()
        first = ctx.engine.head()
        older = commit(self.remote, "One", {"dm/host/one.c": "1"})
        dirty = commit(self.remote, "Two", {"dm/host/two.c": "2"})
        read = commit(self.remote, "Three", {"dm/host/three.c": "3"})
        newest = commit(self.remote, "Link the probes (PR #1520)", {"BROKEN": "x\n"})
        ctx.engine.update()
        git(ctx.engine.root, "checkout", "-q", "-b", "fork", older)
        fork = commit(ctx.engine.root, "A fork's own commit", {"dm/host/fork.c": "fork"})
        ctx.engine.move(newest)

        def built(sha: str, day: int, **fields) -> dict:
            return asdict(Build(commit=sha[:12], built_at=f"2026-11-{day:02d}T08:00:00+00:00", **fields))

        # Newest first: a build from a fork's commit, an IPA's the builder
        # read, one from a checkout with changes, then the builder's own.
        ctx.store.save(Record(MKW, build=Build(commit=fork[:12], built_at="2026-11-11T20:00:00+00:00"),
                              history=[built(read, 11, origin="ipa"), built(dirty, 10, dirty=True), built(older, 9), built(first, 8)]))
        self.assertEqual(fallback.good(ctx.engine, ctx.store, ctx.paths, newest), older)
        # Not a commit marked broken, nor the newest or one after it.
        fallback.mark_broken(ctx.paths, older, first)
        self.assertEqual(fallback.good(ctx.engine, ctx.store, ctx.paths, newest), first)
        self.assertIsNone(fallback.good(ctx.engine, ctx.store, ctx.paths, first))
        # The checkout stays on the good commit a broken one was marked with,
        # while it has it.
        self.assertIsNone(fallback.held(ctx.engine, ctx.paths, newest))
        fallback.mark_broken(ctx.paths, newest, first)
        self.assertEqual(fallback.held(ctx.engine, ctx.paths, newest), first)
        fallback.mark_broken(ctx.paths, newest, "f" * 40)
        self.assertIsNone(fallback.held(ctx.engine, ctx.paths, newest))
        # The last broken commits are kept, not every one.
        for number in range(fallback.KEPT + 1):
            fallback.mark_broken(ctx.paths, f"{number:040x}", first)
        marks = fallback.broken(ctx.paths)
        self.assertEqual(len(marks), fallback.KEPT)
        self.assertNotIn(f"{0:040x}", marks)
        self.assertIn(f"{fallback.KEPT:040x}", marks)


SPLITTER = fallback.SPLITTER
WELCOME = "040057C02159A000"  # Welcome Tour, whose tables 8d62601f split again


class SplitTables(Base):
    """nxnative's 8d62601f (16 November 2026) changed how its shader split
    reads a shader that main holds twice, and split again the tables of the
    one game it was about: Mario Kart World's base game and others stopped
    at "shader split" ("the split shader tables differ from game profile
    0400C3F00006E000's"), on every Mac, the batch falling back for an app
    build alone, and only to a commit that built on this Mac. The splitter
    had changed 27 times since Mario Kart World's tables without harm, and
    may change again before nxnative splits them again."""

    def setUp(self):
        super().setUp()
        self.history("last")
        self.events = []

    def run_due(self, **kwargs):
        return super().run_due(on_event=lambda kind, title_id, value: self.events.append((kind, title_id, value)), **kwargs)

    def history(self, split_by: str) -> None:
        """nxnative's branch from its first commit on: Mario Kart World's
        tables split by SPLIT_BY, the splitter reading the last copy of a
        shader; a commit; then the splitter reading the first copy (Welcome
        Tour's tables split again with it); then the newest."""
        root = git(self.remote, "rev-list", "--max-parents=0", "HEAD")
        git(self.remote, "reset", "-q", "--hard", root)
        self.tables = commit(self.remote, "Mario Kart World's shader tables", {SPLITTER: "reads: last\n", f"dm/games/{MKW}/shader_map.tsv": f"split by: {split_by}\n"})
        self.older = commit(self.remote, "host/audio: preserve surround across output route changes", {"dm/host/audio.c": "surround"})
        self.changed = commit(self.remote, "nvn/raytracing: run Welcome Tour's native ray modules on Metal",
                              {SPLITTER: "reads: first\n", f"dm/games/{WELCOME}/shader_map.tsv": "split by: first\n"})
        self.newest = commit(self.remote, "packing/extract: reject truncated PFS0 payloads (PR #2122)", {"dm/tools/extract.py": "pfs0"})

    def mac_runs(self, title_id: str) -> int:
        return (batch.context().workspace.build_folder(title_id) / "mac_runs.txt").read_text().count("run")

    def entry(self, plan, title_id: str):
        return next(entry for entry in plan.entries if entry.title_id == title_id)

    def test_the_game_builds_from_before_the_splitter_changed_on_a_mac_that_never_built(self):
        plan, summary = self.run_due()
        self.assertEqual((summary.failed, summary.mac_failed), ([], []))
        ctx = batch.context()
        # Its split failed at the newest commit, and it built again from the
        # commit before the splitter changed, its Mac app too; Super Mario
        # Odyssey, whose profile has no tables, from the newest.
        self.assertEqual((self.runs(MKW), self.mac_runs(MKW), self.runs(ODYSSEY)), (2, 1, 1))
        mkw, odyssey = ctx.store.get(MKW), ctx.store.get(ODYSSEY)
        self.assertEqual((mkw.build.commit, mkw.mac.commit, mkw.attempt), (self.older[:12], self.older[:12], None))
        self.assertEqual((odyssey.build.commit, odyssey.mac.commit), (self.newest[:12], self.newest[:12]))
        # The batch goes back to the newest, which is not marked broken for
        # every game: the next batches build the others from it.
        self.assertEqual((ctx.engine.head(), summary.head), (self.newest, self.newest))
        self.assertEqual(fallback.broken(ctx.paths), {})
        status = statuses.read(ctx.paths)
        self.assertEqual((status["head"], status["fallback"]), (self.newest, None))
        # The app says which: from before the splitter changed, not the last
        # commit that built on this Mac.
        self.assertEqual({g["title_id"]: (g["state"], g["commit"], g["fallback"], g["split"], g["mac"]) for g in status["games"]},
                         {MKW: ("built", self.older[:12], True, True, "built"), ODYSSEY: ("built", self.newest[:12], False, False, "built")})
        self.assertIn(f"Mario Kart World built from nxnative {self.older[:12]}: nxnative {self.newest[:12]} reads its shaders otherwise than its profile for now. "
                      f"It is built from {self.older[:12]} until nxnative has a newer commit; the other games are built from {self.newest[:12]}.", status["lines"])
        self.assertIn(f"Back to nxnative {self.newest[:12]}…", status["lines"])
        messages = [value for kind, title_id, value in self.events if kind == "message" and title_id == MKW]
        self.assertIn(f"nxnative {self.newest[:12]} reads its shaders otherwise than its profile says (shader split): trying again from {self.older[:12]}, "
                      "from before nxnative changed how it reads them…", messages)
        # The next batch, at the same commit: nothing due, the game held
        # there, as the app says.
        plan, summary = self.run_due()
        self.assertEqual(plan.to_build, [])
        self.assertEqual((self.entry(plan, MKW).reasons, self.entry(plan, MKW).detail),
                         (["up_to_date"], f"Up to date (built from nxnative {self.older[:12]}: nxnative {self.newest[:12]}, its newest commit, "
                                          "reads its shaders otherwise than its profile for now)"))
        self.assertEqual(self.runs(MKW), 2)

    def test_a_newer_commit_that_still_splits_otherwise_keeps_its_ipa(self):
        self.run_due()
        ctx = batch.context()
        ipa = self.games / ctx.store.get(MKW).build.ipa
        before = ipa.stat().st_mtime_ns
        newer = commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due()
        # Tried at the newest, which splits its shaders otherwise still: its
        # IPA, from before the splitter changed, stays; nothing built again.
        self.assertEqual([entry.title_id for entry in plan.to_build], [MKW])
        self.assertEqual((self.runs(MKW), self.mac_runs(MKW)), (3, 1))
        self.assertEqual((ipa.stat().st_mtime_ns, ctx.store.get(MKW).build.commit), (before, self.older[:12]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["stage"]), ("skipped", "tables", "shader split"))
        self.assertEqual(game["error"], f"nxnative {newer[:12]} reads this game's shaders otherwise than its profile for now, and its IPA is from {self.older[:12]}, "
                                        "from before nxnative changed how it reads them: it stays as it is until nxnative has a newer commit.")
        self.assertEqual(ctx.engine.head(), newer)
        # Held there at this commit, and its IPA up to date.
        plan = batch.survey(batch.context())
        self.assertEqual((self.entry(plan, MKW).build, self.entry(plan, MKW).reasons), (False, ["up_to_date"]))
        self.assertIn(newer[:12], self.entry(plan, MKW).detail)
        # Its files changed: built again from before the splitter changed.
        (self.sources / "Mario Kart World" / "base" / "romfs" / "data.bin").write_bytes(b"romfs 1.1")
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.entry(plan, MKW).reasons[0], "source")
        self.assertEqual(([entry.title_id for entry, _ in summary.built], self.runs(MKW)), ([MKW], 5))
        self.assertEqual(ctx.store.get(MKW).build.commit, self.older[:12])
        # nxnative splits the profile's tables again: built from the newest.
        fixed = commit(self.remote, "Mario Kart World's shader tables split again", {f"dm/games/{MKW}/shader_map.tsv": "split by: first\n"})
        plan, summary = self.run_due()
        self.assertEqual([entry.title_id for entry, _ in summary.built], [MKW])
        self.assertEqual((self.runs(MKW), ctx.store.get(MKW).build.commit), (6, fixed[:12]))
        self.assertEqual((self.game(MKW)["commit"], self.game(MKW)["fallback"]), (fixed[:12], False))

    def test_no_older_commit_when_the_tables_were_split_since(self):
        # The tables split again after the splitter changed: not the same
        # files as the profile's, which no older commit builds.
        commit(self.remote, "Mario Kart World's shader tables split again", {f"dm/games/{MKW}/shader_map.tsv": "split by: someone else's files\n"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.runs(MKW), 1)
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["stage"], game["exit"]), ("failed", "tables", "shader split", 1))
        self.assertEqual(game["error"], causes.words("tables", ""))
        self.assertTrue(game["error"].startswith("nxnative reads this game's shaders otherwise than its profile says (shader split): "), game["error"])
        # Its failure waits for nxnative or its files to change.
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.entry(plan, MKW).reasons, ["failed_here"])

    def test_an_older_commit_that_does_not_build_these_files_is_not_tried_again(self):
        # Tables neither splitter makes of these files.
        self.history("hand")
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.runs(MKW), 2)
        ctx = batch.context()
        self.assertEqual(ctx.engine.head(), self.newest)
        attempt = ctx.store.get(MKW).attempt
        self.assertEqual((attempt.result, attempt.commit), ("failed", self.newest[:12]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["commit"], game["fallback"], game["split"]), ("failed", "tables", self.newest[:12], False, False))
        lines = statuses.read(ctx.paths)["lines"]
        self.assertIn(f"Mario Kart World does not build from nxnative {self.older[:12]} either.", lines)
        self.assertEqual(lines[lines.index(f"Mario Kart World does not build from nxnative {self.older[:12]} either.") + 1],
                         f"Back to nxnative {self.newest[:12]}…")
        # Tried in this batch: not said to be left out.
        self.assertFalse([line for line in lines if "not tried again" in line], lines)
        mark = fallback.splits(ctx.paths)[MKW]
        self.assertEqual((mark["built"], mark["failed"]), (False, [self.older]))
        # A newer commit: tried, not the older one again.
        newer = commit(self.remote, "Mario Kart World's menus", {f"dm/games/{MKW}/README.md": "menus"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.runs(MKW), 3)
        self.assertEqual(ctx.store.get(MKW).attempt.commit, newer[:12])
        self.assertIn(f"Mario Kart World: nxnative's commits from before its splitter changed ({self.older[:12]}) did not build it either "
                      "with these files, and are not tried again.", statuses.read(ctx.paths)["lines"])
        # Its files changed: tried again from there.
        (self.sources / "Mario Kart World" / "base" / "romfs" / "data.bin").write_bytes(b"romfs 1.1")
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.runs(MKW), 5)

    def test_for_this_mac_alone(self):
        paths = Paths.default()
        config = configs.load(paths)
        config.set_platform(MKW, "ios", False)
        configs.save(paths, config)
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(summary.mac_failed, [])
        ctx = batch.context()
        record = ctx.store.get(MKW)
        self.assertEqual((record.build, record.mac.commit, self.mac_runs(MKW)), (None, self.older[:12], 2))
        self.assertEqual(ctx.engine.head(), self.newest)
        plan = batch.survey(batch.context())
        self.assertEqual((self.entry(plan, MKW).build, self.entry(plan, MKW).reasons), (False, ["up_to_date"]))
        # A newer commit that still splits its shaders otherwise: its Mac
        # app, from before the splitter changed, stays as it is.
        newer = commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((self.mac_runs(MKW), ctx.store.get(MKW).mac.commit), (3, self.older[:12]))
        game = self.game(MKW)
        self.assertEqual((game["mac"], game["mac_cause"]), ("skipped", "tables"))
        self.assertEqual(game["mac_error"], f"nxnative {newer[:12]} reads this game's shaders otherwise than its profile for now, and its Mac app is from "
                                            f"{self.older[:12]}, from before nxnative changed how it reads them: it stays as it is until nxnative has a newer commit.")

    def test_two_games_at_once_the_trial_waits_for_the_other(self):
        paths = Paths.default()
        config = configs.load(paths)
        config.jobs = 2
        configs.save(paths, config)
        # Super Mario Odyssey builds until the checkout moved, or for a
        # second and a half: the trial waits for it to end, at the commit
        # it started from, before the checkout goes anywhere.
        release = self.tmp / "release"
        os.environ["FAKE_HOLD"], os.environ["FAKE_SLEEP_ONLY"] = str(release), ODYSSEY
        timer = threading.Timer(1.5, release.touch)
        timer.start()
        self.addCleanup(timer.cancel)

        def follow(kind, title_id, value):
            self.events.append((kind, title_id, value))
            if kind == "engine" and value.get("head") == self.older:
                release.touch()

        plan, summary = Base.run_due(self, on_event=follow)
        self.assertEqual((summary.failed, summary.mac_failed), ([], []))
        ctx = batch.context()
        self.assertEqual({title_id: ctx.store.get(title_id).build.commit for title_id in NAMES}, {MKW: self.older[:12], ODYSSEY: self.newest[:12]})
        self.assertEqual({title_id: ctx.store.get(title_id).mac.commit for title_id in NAMES}, {MKW: self.older[:12], ODYSSEY: self.newest[:12]})
        self.assertEqual(ctx.engine.head(), self.newest)

    def splitter_again(self) -> str:
        """The splitter changed again after the commit that changed how it
        reads a shader held twice, as it still reads it: the newest commit
        and the one before the change."""
        before = git(self.remote, "rev-parse", "HEAD")
        commit(self.remote, "packing/shader_split: read Phyre shaders from split KIT archives (PR #1939)", {SPLITTER: "reads: first\n# Phyre\n"})
        commit(self.remote, "nvn: discover raw pointer pools at binding time", {"dm/nvn/pools.c": "raw"})
        return before

    def test_the_splitter_changed_again_since_on_a_mac_that_never_built(self):
        before = self.splitter_again()
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((summary.failed, summary.mac_failed), ([], []))
        ctx = batch.context()
        # Tried from the newest, from before the splitter's newest change,
        # which reads its shaders as the newest does, then from before the
        # change before it, which built it, its Mac app too, in one batch.
        self.assertEqual((self.runs(MKW), self.mac_runs(MKW)), (3, 1))
        record = ctx.store.get(MKW)
        self.assertEqual((record.build.commit, record.mac.commit), (self.older[:12], self.older[:12]))
        newest = ctx.engine.latest()
        self.assertEqual(ctx.engine.head(), newest)
        lines = statuses.read(ctx.paths)["lines"]
        self.assertIn(f"Mario Kart World does not build from nxnative {before[:12]} either.", lines)
        self.assertIn(f"Mario Kart World built from nxnative {self.older[:12]}: nxnative {newest[:12]} reads its shaders otherwise than its profile "
                      f"for now. It is built from {self.older[:12]} until nxnative has a newer commit; the other games are built from {newest[:12]}.", lines)
        mark = fallback.splits(ctx.paths)[MKW]
        self.assertEqual((mark["built"], mark["older"], mark["failed"]), (True, self.older, [before]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["commit"], game["fallback"], game["split"]), ("built", self.older[:12], True, True))
        # Held there; and at a newer commit, the commit that did not build it
        # is not tried again: its IPA stays.
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((self.entry(plan, MKW).build, self.entry(plan, MKW).reasons, self.runs(MKW)), (False, ["up_to_date"], 3))
        commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(self.runs(MKW), 4)
        self.assertEqual((self.game(MKW)["state"], self.game(MKW)["cause"]), ("skipped", "tables"))
        self.assertEqual(ctx.store.get(MKW).build.commit, self.older[:12])

    def test_a_game_built_from_before_the_splitter_changed_keeps_its_ipa_when_it_changes_again(self):
        self.run_due(only={MKW})
        ctx = batch.context()
        ipa = self.games / ctx.store.get(MKW).build.ipa
        before_ipa = ipa.stat().st_mtime_ns
        self.assertEqual(self.runs(MKW), 2)
        # nxnative changes its splitter again, and Mario Kart World's
        # profile, without splitting its tables again.
        before = self.splitter_again()
        commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due(only={MKW})
        # The newest only: the commit before the splitter's newest change is
        # the one the split differed at last time, so it reads its shaders
        # as the newest does; its IPA, from before the first change, stays
        # as it is.
        self.assertEqual(before, self.newest)
        self.assertEqual((self.runs(MKW), self.mac_runs(MKW)), (3, 1))
        self.assertEqual((ipa.stat().st_mtime_ns, ctx.store.get(MKW).build.commit), (before_ipa, self.older[:12]))
        game = self.game(MKW)
        newest = ctx.engine.latest()
        self.assertEqual((game["state"], game["cause"]), ("skipped", "tables"))
        self.assertEqual(game["error"], f"nxnative {newest[:12]} reads this game's shaders otherwise than its profile for now, and its IPA is from "
                                        f"{self.older[:12]}, from before nxnative changed how it reads them: it stays as it is until nxnative has a newer commit.")
        mark = fallback.splits(ctx.paths)[MKW]
        self.assertEqual((mark["failed"], mark["differ"], mark["older"], mark["built"]), ([], [self.newest, newest], self.older, True))
        self.assertEqual(ctx.engine.head(), newest)
        plan = batch.survey(batch.context())
        self.assertEqual((self.entry(plan, MKW).build, self.entry(plan, MKW).reasons), (False, ["up_to_date"]))

    def again(self, count: int, start: int = 0) -> list[str]:
        """The splitter changed COUNT more times, as it still reads a shader
        main holds twice, and Mario Kart World's profile once (it is due
        again): the commit before each change, newest first."""
        befores = []
        for number in range(start, start + count):
            befores.append(git(self.remote, "rev-parse", "HEAD"))
            commit(self.remote, f"packing/shader_split: read archive {number}", {SPLITTER: f"reads: first\n# archive {number}\n"})
        commit(self.remote, f"nvn/dirty: preserve first-match range lookups ({start})", {f"dm/games/{MKW}/patches.py": f"ranges {start}"})
        return befores[::-1]

    def tried_from(self) -> list[str]:
        """The older commits the batches built the game from, in turn."""
        return [value["commit"] for kind, title_id, value in self.events if kind == "commit" and title_id == MKW and value.get("split")]

    def as_builder_0_7(self) -> None:
        """nxnative.json's marks as Cartouche Builder 0.7.0 and 0.7.1 kept them,
        on players' Macs: no commits whose split differed nor failed
        otherwise."""
        paths = Paths.default()
        data = json.loads(paths.engine_state.read_text())
        for mark in data["split"].values():
            mark.pop("differ", None), mark.pop("otherwise", None)
        paths.engine_state.write_text(json.dumps(data))

    def test_the_splitter_changed_more_than_depth_times_since_it_broke_on_a_mac_that_never_built(self):
        # As at nxnative on 19 November 2026: four changes after 8d62601f,
        # whose parent was the one commit that built seven games; the three
        # newest changes' parents did not.
        befores = self.again(fallback.DEPTH + 1)
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((summary.failed, summary.mac_failed), ([], []))
        ctx = batch.context()
        # The DEPTH newest, then twice as far back: the commit before the
        # change that broke it, its Mac app too, in one batch.
        self.assertEqual(self.tried_from(), [sha[:12] for sha in befores[: fallback.DEPTH]] + [self.older[:12]])
        self.assertEqual((self.runs(MKW), self.mac_runs(MKW)), (2 + fallback.DEPTH, 1))
        record = ctx.store.get(MKW)
        self.assertEqual((record.build.commit, record.mac.commit), (self.older[:12], self.older[:12]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["commit"], game["fallback"], game["split"]), ("built", self.older[:12], True, True))
        self.assertEqual(ctx.engine.head(), ctx.engine.latest())

    def test_a_mac_that_built_it_from_before_the_splitter_broke_keeps_it_however_often_it_changes(self):
        self.run_due(only={MKW})
        ctx = batch.context()
        ipa = self.games / ctx.store.get(MKW).build.ipa
        before_ipa = ipa.stat().st_mtime_ns
        self.assertEqual(self.runs(MKW), 2)
        # Its mark as the Builder before kept it, then more changes of the
        # splitter than DEPTH, twice, and the profile changed each time.
        self.as_builder_0_7()
        for start in (0, 10):
            self.again(fallback.DEPTH + 1, start)
            plan, summary = self.run_due(only={MKW})
            # The newest only: every commit before a change since is newer
            # than the one its split differed at before, and its IPA, from
            # before the change that broke it, stays as it is.
            self.assertEqual(self.runs(MKW), 3 if start == 0 else 4)
            self.assertEqual((self.mac_runs(MKW), self.tried_from()), (1, [self.older[:12]]))
            self.assertEqual((ipa.stat().st_mtime_ns, ctx.store.get(MKW).build.commit), (before_ipa, self.older[:12]))
            game = self.game(MKW)
            self.assertEqual((game["state"], game["cause"]), ("skipped", "tables"))
            self.assertIn(f"its IPA is from {self.older[:12]}", game["error"])
            mark = fallback.splits(ctx.paths)[MKW]
            self.assertEqual((mark["older"], mark["built"], mark["newest"], mark["failed"]), (self.older, True, ctx.engine.latest(), []))
            plan = batch.survey(batch.context())
            self.assertEqual((self.entry(plan, MKW).build, self.entry(plan, MKW).reasons), (False, ["up_to_date"]))

    def test_many_changes_after_it_broke_a_few_builds_then_the_newest_that_builds(self):
        # Six changes of the splitter that split its shaders as its tables
        # say, the change that broke it, then five more.
        root = git(self.remote, "rev-list", "--max-parents=0", "HEAD")
        git(self.remote, "reset", "-q", "--hard", root)
        commit(self.remote, "Mario Kart World's shader tables", {SPLITTER: "reads: last\n", f"dm/games/{MKW}/shader_map.tsv": "split by: last\n"})
        harmless = [commit(self.remote, f"packing/shader_split: read archive h{n}", {SPLITTER: f"reads: last\n# h{n}\n"}) for n in range(6)]
        broke = commit(self.remote, "nvn/raytracing: run Welcome Tour's native ray modules on Metal", {SPLITTER: "reads: first\n"})
        after = [commit(self.remote, f"packing/shader_split: read archive a{n}", {SPLITTER: f"reads: first\n# a{n}\n"}) for n in range(5)]
        commit(self.remote, "nvn: discover raw pointer pools at binding time", {"dm/nvn/pools.c": "raw"})
        newest_first = after[-2::-1] + [broke] + harmless[::-1]
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(summary.failed, [])
        ctx = batch.context()
        # Five builds: the three newest, then twice as far back each time.
        self.assertEqual(self.tried_from(), [newest_first[i][:12] for i in (0, 1, 2, 4, 8)])
        self.assertEqual(ctx.store.get(MKW).build.commit, harmless[2][:12])
        # The next time it is built, the newest commits between it and those
        # that did not, in turn: the one right before the change that broke it.
        commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual(summary.failed, [])
        self.assertEqual(self.tried_from()[5:], [harmless[-1][:12]])
        self.assertEqual(ctx.store.get(MKW).build.commit, harmless[-1][:12])
        self.assertEqual(self.runs(MKW), 8)

    def test_a_commit_whose_split_differed_before_nxnative_fixed_it_rules_nothing_out_since(self):
        self.run_due(only={MKW})
        ctx = batch.context()
        # nxnative reads its shaders as its tables say again: built from the
        # newest, as any game.
        fixed = commit(self.remote, "packing/shaders: preserve verified registered duplicate sources",
                       {SPLITTER: "reads: last\n# fixed\n", f"dm/games/{MKW}/patches.py": "fixed"})
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((ctx.store.get(MKW).build.commit, self.runs(MKW)), (fixed[:12], 3))
        # Then it changes its splitter twice, the second time otherwise.
        harmless = commit(self.remote, "packing/shader_split: read archive h", {SPLITTER: "reads: last\n# h\n"})
        commit(self.remote, "packing/shader_split: read archive a", {SPLITTER: "reads: first\n# a\n"})
        commit(self.remote, "nvn/dirty: preserve first-match range lookups (PR #1227)", {f"dm/games/{MKW}/patches.py": "ranges"})
        plan, summary = self.run_due(only={MKW})
        # The commits newer than the one its split differed at the first time
        # are not ruled out: the game built from one since.
        self.assertEqual(summary.failed, [])
        self.assertEqual(self.tried_from()[1:], [harmless[:12]])
        self.assertEqual((ctx.store.get(MKW).build.commit, self.runs(MKW)), (harmless[:12], 5))

    def test_an_older_commit_that_fails_otherwise_ends_the_walk_and_none_before_it_is_tried(self):
        befores = self.again(fallback.DEPTH + 1)
        run = batch.builds.run

        def metal_at(*args, **kwargs):
            # An Xcode the older commit was not tested with: older commits
            # want older ones still.
            if batch.context().engine.head() == befores[1]:
                return Result(code=1, ok=False, error="this Mac's Metal compiler is not the one the shaders were tested with", stage="check v131072 files", cause="metal")
            return run(*args, **kwargs)

        with mock.patch.object(batch.builds, "run", side_effect=metal_at):
            plan, summary = self.run_due(only={MKW})
        ctx = batch.context()
        self.assertEqual(self.tried_from(), [befores[0][:12], befores[1][:12]])
        game = self.game(MKW)
        newest = ctx.engine.latest()
        self.assertEqual((game["state"], game["cause"], game["commit"]), ("failed", "tables", newest[:12]))
        mark = fallback.splits(ctx.paths)[MKW]
        self.assertEqual((mark["failed"], mark["otherwise"]), ([befores[0], befores[1]], [befores[1]]))
        self.assertEqual(ctx.engine.head(), newest)
        # At a newer commit: none of them again, nor any before them.
        commit(self.remote, "Mario Kart World's menus", {f"dm/games/{MKW}/README.md": "menus"})
        with mock.patch.object(batch.builds, "run", side_effect=metal_at):
            plan, summary = self.run_due(only={MKW})
        self.assertEqual((self.runs(MKW), len(self.tried_from())), (3, 2))
        self.assertIn(f"Mario Kart World: nxnative's commits from before its splitter changed ({befores[0][:12]}, {befores[1][:12]}) "
                      "did not build it either with these files, and are not tried again.", statuses.read(ctx.paths)["lines"])

    def test_an_older_commit_that_fails_otherwise_leaves_the_ipa_this_mac_built(self):
        self.run_due(only={MKW})
        ctx = batch.context()
        ipa = self.games / ctx.store.get(MKW).build.ipa
        before_ipa = ipa.stat().st_mtime_ns
        # nxnative.json lost, more changes: tried from the newest of them,
        # whose app does not link.
        ctx.paths.engine_state.unlink()
        befores = self.again(fallback.DEPTH + 1)
        run = batch.builds.run

        def app_build_at(*args, **kwargs):
            if batch.context().engine.head() == befores[0]:
                return Result(code=1, ok=False, error="xcodebuild failed (exit 65)", stage="app build", cause="app_build")
            return run(*args, **kwargs)

        with mock.patch.object(batch.builds, "run", side_effect=app_build_at):
            plan, summary = self.run_due(only={MKW})
        # The first batch's, then the newest commit before a change: its IPA
        # stays, nothing built from the older commit again.
        self.assertEqual(self.tried_from(), [self.older[:12], befores[0][:12]])
        self.assertEqual((ipa.stat().st_mtime_ns, ctx.store.get(MKW).build.commit), (before_ipa, self.older[:12]))
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"]), ("skipped", "tables"))
        self.assertEqual(self.runs(MKW), 3)

    def test_each_older_commit_once_in_a_batch_whatever_nxnative_json_keeps(self):
        # No commit builds these files, and nxnative.json cannot be written.
        self.history("hand")
        run, heads = batch.builds.run, []

        def counted(*args, **kwargs):
            heads.append(batch.context().engine.head())
            if len(heads) > 4:
                raise RuntimeError("the same commit again")
            return run(*args, **kwargs)

        with mock.patch.object(batch.builds, "run", side_effect=counted), \
                mock.patch.object(fallback, "mark_split", side_effect=OSError(errno.EROFS, "Read-only file system")):
            plan, summary = self.run_due(only={MKW})
        self.assertEqual(heads, [self.newest, self.older])
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["commit"]), ("failed", "tables", self.newest[:12]))
        self.assertEqual(batch.context().engine.head(), self.newest)

    def test_a_commit_that_failed_for_the_macs_sake_is_tried_again(self):
        # The disk filled up at the older commit: not its files' failure.
        run = batch.builds.run

        def full_at_older(*args, **kwargs):
            if batch.context().engine.head() == self.older:
                return Result(code=1, ok=False, error="No space left on device", stage="unpack v0", cause="no_space")
            return run(*args, **kwargs)

        with mock.patch.object(batch.builds, "run", side_effect=full_at_older):
            plan, summary = self.run_due(only={MKW})
        ctx = batch.context()
        game = self.game(MKW)
        self.assertEqual((self.runs(MKW), game["state"], game["cause"], game["commit"]), (1, "skipped", "no_space", ctx.engine.head()[:12]))
        self.assertEqual(ctx.store.get(MKW).attempt.result, "skipped")
        self.assertEqual(fallback.splits(ctx.paths).get(MKW), None)
        lines = statuses.read(ctx.paths)["lines"]
        self.assertNotIn(f"Mario Kart World does not build from nxnative {self.older[:12]} either.", lines)
        self.assertIn(f"Back to nxnative {ctx.engine.head()[:12]}…", lines)
        # The next batch tries it again, and builds it.
        plan, summary = self.run_due(only={MKW})
        self.assertEqual((self.runs(MKW), ctx.store.get(MKW).build.commit), (3, self.older[:12]))

    def test_the_commit_before_the_splitter_changed(self):
        ctx = batch.context()
        ctx.engine.update()
        self.assertEqual(fallback.split_back(ctx.engine, MKW, self.newest), [self.older])
        self.assertEqual(fallback.split_back(ctx.engine, MKW, self.changed), [self.older])
        # The tables split in the commit that changed the splitter, or after
        # it: not the splitter's doing.
        self.assertEqual(fallback.split_back(ctx.engine, WELCOME, self.newest), [])
        self.assertEqual(fallback.split_back(ctx.engine, MKW, self.older), [])
        # No splitter in nxnative's history yet, nor tables.
        first = git(ctx.engine.root, "rev-list", "--max-parents=0", "HEAD")
        self.assertEqual(fallback.split_back(ctx.engine, MKW, first), [])
        self.assertEqual(fallback.split_back(ctx.engine, ODYSSEY, self.newest), [])
        # The splitter changed again since, more than DEPTH times (33 times
        # at nxnative between 19 and 24 November 2026): the commit before
        # each change since the tables, newest first, however many.
        befores = []
        for number in range(fallback.DEPTH + 1):
            befores.append(git(self.remote, "rev-parse", "HEAD"))
            commit(self.remote, f"packing/shader_split: read archive {number}", {SPLITTER: f"reads: first\n# archive {number}\n"})
        ctx.engine.update()
        newest = ctx.engine.head()
        self.assertEqual(fallback.split_back(ctx.engine, MKW, newest), befores[::-1] + [self.older])
        # A change undone, then the splitter of an older commit again: of
        # the commits that hold the same splitter, the newest; none that
        # holds the newest's, which splits them as the newest does.
        fourth = commit(self.remote, "packing/shader_split: read archive 4", {SPLITTER: "reads: first\n# archive 4\n"})
        undone = commit(self.remote, "Revert \"packing/shader_split: read archive 4\"", {SPLITTER: "reads: first\n# archive 3\n"})
        commit(self.remote, "packing/shader_split: read archive 5", {SPLITTER: "reads: first\n"})
        ctx.engine.update()
        self.assertEqual(fallback.split_back(ctx.engine, MKW, ctx.engine.head()), [undone, fourth] + befores[::-1][:-1] + [self.older])

    def test_the_cause_is_named(self):
        said = ("the split shader tables differ from game profile 0400C3F00006E000's:\nshader_map.tsv: 36 row(s) only in the profile, 36 only in the split\n"
                "Either these game files are not the versions the profile registers, or shader_split.py now reads them differently")
        result = Result(code=1, ok=False, error=said, stage="shader split", said=[said])
        self.assertEqual(causes.of_build(result), "tables")
        # A full disk at the split is a full disk.
        full = Result(code=1, ok=False, stage="shader split", said=["shader_split.py failed (exit 1)"], stderr=["OSError: [Errno 28] No space left on device"])
        self.assertEqual(causes.of_build(full), "no_space")


class Causes(Base):
    def test_a_full_disk_is_said_and_tried_again(self):
        os.environ["FAKE_NO_SPACE"] = MKW
        plan, summary = self.run_due(only={MKW})
        message = summary.failed[0][1]
        self.assertRegex(message, r"^nxnative needs 32 GB free on your Mac's disk to build this game, and [\d.]+ GB are left\. ")
        ctx = batch.context()
        self.assertEqual(ctx.store.get(MKW).attempt.result, "skipped")
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["exit"], game["error"]), ("skipped", "no_space", 1, message))
        os.environ.pop("FAKE_NO_SPACE")
        plan, summary = self.run_due(only={MKW})
        self.assertEqual([entry.title_id for entry, _ in summary.built], [MKW])

    def test_a_share_that_fills_up_is_named(self):
        full = OSError(errno.ENOSPC, "No space left on device", "/Volumes/NAS/Games/Mario Kart World [0400C3F00006E000].ipa")
        with mock.patch.object(batch.ipas, "deliver", side_effect=full):
            plan, summary = self.run_due(only={MKW})
        self.assertEqual(summary.failed[0][1], "The disk “NAS” is full. Free some room on it, then try again.")
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"]), ("skipped", "no_space"))
        self.assertEqual(game["failure"], {"exception": "OSError", "where": "batch._one", "errno": 28})

    def test_damaged_files_are_said(self):
        os.environ["FAKE_DAMAGED"] = MKW
        plan, summary = self.run_due(only={MKW})
        self.assertTrue(summary.failed[0][1].startswith("Some of this game's files are damaged (its update v131072): "), summary.failed[0][1])
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["stage"]), ("failed", "damaged", "unpack v131072"))
        # Its failure waits for its files to change.
        plan, summary = self.run_due(only={MKW})
        self.assertEqual([entry.reasons for entry in plan.entries if entry.title_id == MKW], [["failed_here"]])

    def test_an_older_xcode_is_said_and_tried_again(self):
        """nxnative refuses an older Xcode's Metal compiler after its check
        of the game's files: Ocarina of Time's update said "nxnative" there,
        nine times on a Mac with Xcode 27.1 (telemetry of 14 November 2026).
        The Mac's doing, not the game's: skipped, in the player's words."""
        os.environ["FAKE_METAL"] = MKW
        plan, summary = self.run_due(only={MKW})
        message = summary.failed[0][1]
        self.assertEqual(message, "nxnative builds this game's shaders only with the Metal compiler of Xcode 27.2, which it tested them with, "
                                  "and this Mac has Xcode 27.1. Update Xcode in the App Store (the page “This Mac's tools” does it with you), "
                                  "then build the game again.")
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["stage"], game["exit"]), ("skipped", "metal", "check v131072 files", 1))
        self.assertEqual(batch.context().store.get(MKW).attempt.result, "skipped")
        # Once Xcode is updated, the game builds at the next batch.
        os.environ.pop("FAKE_METAL")
        plan, summary = self.run_due(only={MKW})
        self.assertEqual([entry.title_id for entry, _ in summary.built], [MKW])

    def test_a_newer_xcode_waits_for_nxnative(self):
        os.environ["FAKE_METAL"] = MKW
        os.environ["FAKE_XCODE"] = "27.3"
        plan, summary = self.run_due(only={MKW})
        self.assertTrue(summary.failed[0][1].endswith("and this Mac's Xcode 27.3 has another one, which nxnative has not tested yet. "
                                                      "The game builds once it has: Cartouche Builder tries it again at each build."),
                        summary.failed[0][1])
        self.assertEqual(self.game(MKW)["cause"], "metal")

    def test_a_crash_of_nxnative_says_its_exception(self):
        os.environ["FAKE_CRASH"] = MKW
        plan, summary = self.run_due(only={MKW})
        game = self.game(MKW)
        self.assertEqual((game["cause"], game["exit"], game["failure"], game["error"]), ("crashed", 1, {"exception": "KeyError"}, "KeyError: 'icon'"))

    def test_a_batch_that_fills_the_disk_says_so(self):
        full = OSError(errno.ENOSPC, "No space left on device")
        with mock.patch.object(batch, "survey", side_effect=full), self.assertRaises(OSError):
            self.run_due()
        status = statuses.read(Paths.default())
        self.assertEqual(status["state"], "failed")
        self.assertRegex(status["error"], r"^Your Mac's disk is full \([\d.]+ GB left\)\. ")
        self.assertEqual((status["failure"]["exception"], status["failure"]["errno"]), ("OSError", 28))

    def test_nxnative_that_does_not_start(self):
        plan, summary = batch.run_due(batch.context(), python=self.tmp / "no python" / "python3", check_tools=False, only={MKW})
        self.assertTrue(summary.failed[0][1].startswith("nxnative's build script did not start: "), summary.failed[0][1])
        game = self.game(MKW)
        self.assertEqual((game["state"], game["cause"], game["exit"]), ("failed", "no_start", None))

    def test_the_apps_commands_say_a_full_disk(self):
        with mock.patch.object(api.configs, "save", side_effect=OSError(errno.ENOSPC, "No space left on device")):
            answer = self.api("config", "--set", json.dumps({"jobs": 2}))
        error = answer["error"]
        self.assertEqual((error["kind"], error["errno"], error["exception"]), ("no_space", 28, "OSError"))
        self.assertRegex(error["message"], r"^Your Mac's disk is full \([\d.]+ GB left\)\. ")
        failed = EngineError("git fetch failed: fatal: write error: No space left on device")
        with mock.patch.object(batch.Engine, "update", side_effect=failed):
            answer = self.api("library", "--update")
        self.assertEqual(answer["error"]["kind"], "no_space")
        self.assertRegex(answer["error"]["message"], r"^Your Mac's disk is full")
