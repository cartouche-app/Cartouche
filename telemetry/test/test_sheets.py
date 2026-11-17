"""Checks telemetry/sheets.py, the weekly sum of the game sessions into the
game sheets, against a stand-in for Cloudflare's API (standin.py) whose D1
database holds sessions as the Worker keeps them, made from the session of
app-reports.json.

- a model three iPhones played on gets a result, made of the medians of each
  iPhone's own and the highest of their memory peaks; a model two iPhones
  played on gets none, and neither does any of its figures that fewer than
  three iPhones measured;
- a session sent again counts once, at its highest seq; only the 28 days
  before the run count; a copy of another region counts for its game;
- the status follows from how the sessions ended and the frame rate;
- testers' results stay, a measured result of a model measured again is
  replaced, and the sheet stays valid for its schema and the publish guard;
- a game of nxnative's list without a sheet gets one once three iPhones of a
  model played it, named by its main release's title ID, which says what
  the game needs: the iOS and the GPU nxnative needs, and Increased Memory
  Limit when its peak, with the room Cartouche keeps, does not fit in the
  most an app had without it; a game played on fewer of each model, or that
  nxnative's list does not have, gets none;
- any sheet comes to need Increased Memory Limit once its peak does, and
  never stops needing it;
- the job that commits the sheets takes only those of the catalog, or new
  ones of games of nxnative's list, named by their title ID;
- without the secrets, nothing is read.

Run from the repository root: python3 -m unittest discover -s telemetry/test -v
"""

import copy
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

from standin import ACCOUNT, TOKEN, Cloudflare, environment, serve

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHEETS = HERE.parent / "sheets.py"
SCHEMA = HERE.parent / "schema.sql"
SCHEMA_OF_SHEETS = ROOT / "catalog" / "schema" / "game.schema.json"
MKW = "0400C3F00006E000"
SENTINELS = "01003FC01670C000"
SENTINELS_JAPAN = "010045C014650000"
TODAY = "2026-11-12"
# The reading of the log the sessions come from, unless a test says: one
# whose slowest 5% counts (sheets.py, SLOWEST_READER).
READER = 2

TEMPLATE = next(r for r in json.loads((HERE / "app-reports.json").read_text(encoding="utf-8"))["reports"]
                if r["kind"] == "session")

# The catalog of the tests, in the catalog's own formats: two games of
# nxnative's list, one with a copy of another region, and a sheet with a
# tester's result.
NXNATIVE = {"schema": 1, "nxnative": "0123456789abcdef0123456789abcdef01234567", "games": [
    {"titleId": SENTINELS, "name": "13 Sentinels: Aegis Rim", "platform": "switch", "genre": "rpg",
     "status": "bringup", "engine": "Vanillaware's engine", "build": "1.10", "sdk": "11.4.3",
     "variants": [{"titleId": SENTINELS_JAPAN, "region": "japan", "build": "1.00 (base)"}]},
    {"titleId": MKW, "name": "Mario Kart World", "platform": "switch2", "genre": "racing",
     "status": "iphone", "engine": "Nintendo's engine", "build": "1.0.0", "sdk": "20.0.0"},
]}
# The catalog's memory limits, as devices.json measured them: an app had
# 3,376 MiB without Increased Memory Limit, and 8,192 with it.
DEVICES = {"schema": 1, "devices": [
    {"identifier": "iPhone19,4", "chip": "A20 Pro", "memoryGB": 12, "measurements": [
        {"date": "2026-11-04", "iOS": "27.3", "increasedMemoryLimit": False, "appMemoryLimitMiB": 3376},
        {"date": "2026-11-10", "iOS": "27.3", "increasedMemoryLimit": True, "appMemoryLimitMiB": 8192}]},
]}
TESTER = {"device": "iPhone19,4", "iOS": "27.3", "date": "2026-11-05", "engine": "nxnative 0d9b6358",
          "status": "playable", "notes": ["Ran smoothly at 1080p in handheld mode."]}
SHEET = {"schema": 1, "titleId": MKW, "name": "Mario Kart World", "platform": "switch2",
         "requirements": {"minimumIOS": "26.0", "bcTextureCompression": True, "increasedMemoryLimit": True},
         "recommended": {"resolution": "1080p", "mode": "handheld"}, "results": [TESTER]}

try:
    import jsonschema
except ImportError:  # the Telemetry workflow installs it with the publish guard
    jsonschema = None

sys.path.insert(0, str(ROOT / "guard"))
from cartouche_guard.guard import check_catalog  # noqa: E402  (the guard is Python's standard library only)


def schema_as_deployed() -> str:
    lines = SCHEMA.read_text(encoding="utf-8").splitlines()
    return "\n".join(line for line in lines if not line.lstrip().startswith("--"))


class SheetsTest(unittest.TestCase):
    def setUp(self):
        self.cloudflare = Cloudflare()
        self.cloudflare.databases.append({"uuid": "d1-0", "name": "cartouche-telemetry", "jurisdiction": "eu"})
        self.cloudflare.sql.executescript(schema_as_deployed())
        self.server = serve(self.cloudflare)
        self.addCleanup(self.cloudflare.sql.close)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)
        self.catalog = self.work / "catalog"
        (self.catalog / "games").mkdir(parents=True)
        (self.catalog / "nxnative.json").write_text(json.dumps(NXNATIVE, indent=2) + "\n", encoding="utf-8")
        (self.catalog / "devices.json").write_text(json.dumps(DEVICES, indent=2) + "\n", encoding="utf-8")
        (self.catalog / "games" / f"{MKW}.json").write_text(json.dumps(SHEET, indent=2) + "\n", encoding="utf-8")
        self.phones = [str(uuid.uuid4()) for _ in range(5)]

    # MARK: Helpers

    def session(self, install, day="2026-11-10", device="iPhone19,4", game=MKW, session=None, seq=1, **fields):
        """A session as the Worker keeps it: the fixture's, with these fields."""
        report = copy.deepcopy(TEMPLATE)
        report.update(id=str(uuid.uuid4()), install=install, device=device, game=game, seq=seq,
                      session=session or str(uuid.uuid4()), end={"kind": "unknown"}, reader=READER)
        for key, value in fields.items():
            if value is None:
                report.pop(key, None)
            else:
                report[key] = value
        self.cloudflare.sql.execute(
            "INSERT INTO reports (id, kind, install, day, seq, cartouche, device, ios, game, name, session, body) "
            "VALUES (?, 'session', ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)",
            (report["id"], install, day, seq, report["cartouche"], device, report["ios"], game, report["session"],
             json.dumps(report)))
        return report

    def run_sheets(self, secrets=True):
        values = {"GITHUB_OUTPUT": str(self.work / "output"), "GITHUB_STEP_SUMMARY": str(self.work / "summary.md")}
        if secrets:
            values.update(CLOUDFLARE_API_TOKEN=TOKEN, CLOUDFLARE_ACCOUNT_ID=ACCOUNT)
        result = subprocess.run(
            [sys.executable, str(SHEETS), "--catalog", str(self.catalog), "--out", str(self.work / "sheets"),
             "--today", TODAY],
            env=environment(self.server, **values), capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def output(self):
        return (self.work / "output").read_text(encoding="utf-8")

    def written(self, title=MKW):
        path = self.work / "sheets" / f"{title}.json"
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None

    def measured(self, title=MKW):
        sheet = self.written(title)
        self.assertIsNotNone(sheet, "the sheet was not written")
        return {r["device"]: r for r in sheet["results"] if "measured" in r}

    def assert_valid(self, sheet):
        check_catalog(json.dumps(sheet).encode(), "sheet")
        for result in sheet["results"]:
            self.assertLessEqual(len(result["engine"]), 120)
            for note in result.get("notes", []):
                self.assertLessEqual(len(note), 300)
        if jsonschema is not None:
            schema = json.loads(SCHEMA_OF_SHEETS.read_text(encoding="utf-8"))
            jsonschema.validate(sheet, schema)

    # MARK: Tests

    def test_three_iphones_of_a_model_make_a_result_of_their_medians(self):
        for phone, fps, peak, stutters in zip(self.phones[:3], (58.0, 59.0, 60.0), (4640, 4720, 4800), (1.2, 1.4, 1.6)):
            self.session(phone, fps={"median": fps, "low5": fps - 6}, memory={"peakMiB": peak},
                         stutters={"count": 10, "perMinute": stutters})
        # The third iPhone's other session moves its own median, not the others'.
        self.session(self.phones[2], day="2026-11-11", fps={"median": 30.0, "low5": 20.0},
                     memory={"peakMiB": 5200}, stutters={"count": 40, "perMinute": 4.0})
        self.run_sheets()
        self.assertEqual(self.output(), "changed=true\n")
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["status"], "playable")
        self.assertEqual(result["date"], "2026-11-11")
        self.assertEqual(result["iOS"], "27.3")
        self.assertEqual(result["engine"], "nxnative 6c3aeb3d70a1")
        # Each iPhone's median: 58, 59 and (60 + 30) / 2 = 45: their median is 58.
        self.assertEqual(result["measured"], {
            "iPhones": 3, "sessions": 4, "from": "2026-11-10", "to": "2026-11-11", "fps": 58, "slowestFps": 52,
            "targetFps": 60, "stuttersPerMinute": 1.4, "endedBadlyPercent": 0, "nxnative": "6c3aeb3d70a1"})
        # Each iPhone's highest peak: 4640, 4720 and 5200, the highest of them.
        self.assertEqual(result["peakMemoryMiB"], 5200)
        self.assertEqual(result["notes"], [
            "Measured by Cartouche on 3 iPhones, 4 sessions from 2026-11-10 to 2026-11-11: 58 fps for 60 (median), "
            "52 fps in the slowest 5% of the time, 1.4 stutters a minute. None ended badly."])
        sheet = self.written()
        self.assertEqual(sheet["results"][0], TESTER, "the tester's result stays first, as it was")
        self.assert_valid(sheet)
        summary = (self.work / "summary.md").read_text(encoding="utf-8")
        self.assertIn("| Mario Kart World | iPhone19,4 | 3 | 4 | playable |", summary)

    def test_three_ipads_of_a_model_make_a_result_that_says_ipads(self):
        for phone in self.phones[:3]:
            self.session(phone, device="iPad13,16")
        self.run_sheets()
        result = self.measured()["iPad13,16"]
        self.assertEqual(result["measured"]["iPhones"], 3, "the schema's key, for iPads too")
        self.assertTrue(result["notes"][0].startswith("Measured by Cartouche on 3 iPads, 3 sessions"), result["notes"])
        self.assert_valid(self.written())

    def test_a_model_no_sheet_may_name_is_left_out(self):
        for phone in self.phones[:3]:
            self.session(phone, device="iPod9,1")
        self.run_sheets()
        self.assertEqual(self.output(), "changed=false\n")

    def test_two_iphones_make_no_result(self):
        for phone in self.phones[:2]:
            self.session(phone)
        self.session(self.phones[0], device="iPhone18,1")
        result = self.run_sheets()
        self.assertEqual(self.output(), "changed=false\n")
        self.assertIsNone(self.written())
        self.assertIn("Left out: 2 models of a game with a sheet, played on fewer than 3 iPhones.", result.stdout)
        self.assertNotIn("iPhone18,1", result.stdout + (self.work / "summary.md").read_text(encoding="utf-8"))

    def test_a_figure_fewer_than_three_iphones_measured_is_left_out(self):
        self.session(self.phones[0], memory={"peakMiB": 4000})
        self.session(self.phones[1], memory={"peakMiB": 4100})
        self.session(self.phones[2], memory=None, fps=None, stutters=None, frames=10)
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertNotIn("peakMemoryMiB", result)
        self.assertNotIn("fps", result["measured"])
        self.assertNotIn("stuttersPerMinute", result["measured"])
        self.assertEqual(result["notes"], [
            "Measured by Cartouche on 3 iPhones, 3 sessions from 2026-11-10 to 2026-11-10. None ended badly."])
        self.assert_valid(self.written())

    def test_the_peak_counts_only_the_sessions_that_drew_a_frame(self):
        # As Mario Kart World's on 2026-11-11: an iPhone whose sessions all
        # crashed before their first frame, with 2 and 50 MiB loaded, made
        # the peak of the three 4,475 MiB, under the 5,499 another measured.
        self.session(self.phones[0], memory={"peakMiB": 5499})
        self.session(self.phones[1], memory={"peakMiB": 4475})
        for peak in (2, 50):
            self.session(self.phones[2], memory={"peakMiB": peak}, frames=None, fps=None, stutters=None,
                         end={"kind": "crash", "signal": 11})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertNotIn("peakMemoryMiB", result)
        # Once that iPhone plays the game, the peak is the highest of the three.
        self.session(self.phones[2], day="2026-11-11", memory={"peakMiB": 5161})
        self.run_sheets()
        self.assertEqual(self.measured()["iPhone19,4"]["peakMemoryMiB"], 5499)

    def test_the_peak_is_the_highest_of_the_iphones_not_their_median(self):
        # As Mario Kart World's on 2026-11-13: the iPhones' peaks were 5,499,
        # 5,018 and 3,434 MiB, with a fourth that only crashed at boot. Their
        # median, 5,018, leaves the eighth of 6,144 behind the console, and
        # would have started the game there (docs/decisions.md, 48), where
        # the first iPhone's 5,499 does not fit.
        for peak in (5499, 5161):
            self.session(self.phones[0], memory={"peakMiB": peak})
        for peak in (4475, 5018):
            self.session(self.phones[1], memory={"peakMiB": peak})
        self.session(self.phones[2], fps={"median": 0.6, "low5": 0.3}, memory={"peakMiB": 3434})
        for peak in (2, 50, 2):
            self.session(self.phones[3], memory={"peakMiB": peak}, frames=None, fps=None, stutters=None,
                         end={"kind": "crash", "signal": 11})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["measured"]["iPhones"], 4)
        self.assertEqual(result["peakMemoryMiB"], 5499)
        self.assertGreater(result["peakMemoryMiB"] + 6144 // 8, 6144, "it starts in Cartouche's place")
        self.assert_valid(self.written())

    def test_the_slowest_5_percent_counts_only_from_the_reading_that_takes_pauses_out(self):
        # As Super Mario Bros. Wonder's on 2026-11-13: 59.6 fps for 60, and 4
        # fps in the slowest 5% of the time, from the stretches that held a
        # pause behind the console. Read by Cartouche's first reading of the
        # log, the slowest 5% is left out, and does not make the game
        # playable with issues.
        for phone in self.phones[:3]:
            self.session(phone, reader=1, fps={"median": 59.6, "low5": 4.0}, stutters={"count": 2, "perMinute": 0.1})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["measured"]["fps"], 59.6)
        self.assertNotIn("slowestFps", result["measured"])
        self.assertEqual(result["status"], "playable")
        self.assertNotIn("slowest", result["notes"][0])
        # From the reading that takes the pauses out, it counts again, and a
        # slowest 5% under three quarters of the target is an issue.
        for phone in self.phones[:3]:
            self.session(phone, day="2026-11-11", fps={"median": 59.6, "low5": 40.0},
                         stutters={"count": 2, "perMinute": 0.1})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["measured"]["slowestFps"], 40)
        self.assertEqual(result["status"], "playable-with-issues")
        self.assertIn("40 fps in the slowest 5% of the time", result["notes"][0])

    def test_a_session_sent_again_counts_once_at_its_highest_seq(self):
        again = str(uuid.uuid4())
        self.session(self.phones[0], session=again, seq=3, fps={"median": 20.0, "low5": 10.0})
        self.session(self.phones[0], session=again, seq=5, day="2026-11-11", fps={"median": 60.0, "low5": 58.0})
        self.session(self.phones[1], fps={"median": 60.0, "low5": 58.0})
        self.session(self.phones[2], fps={"median": 60.0, "low5": 58.0})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["measured"]["sessions"], 3)
        self.assertEqual(result["measured"]["fps"], 60)
        self.assertEqual(result["status"], "playable")

    def test_only_the_28_days_before_the_run_count(self):
        for phone in self.phones[:3]:
            self.session(phone, day="2026-10-15")
        self.session(self.phones[0], day="2026-10-14", end={"kind": "crash", "signal": 11})
        self.session(self.phones[1], day=TODAY, end={"kind": "crash", "signal": 11})
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual((result["measured"]["sessions"], result["measured"]["from"]), (3, "2026-10-15"))
        self.assertEqual(result["measured"]["endedBadlyPercent"], 0)

    def test_a_copy_of_another_region_counts_for_its_game(self):
        sheet = {"schema": 1, "titleId": SENTINELS, "name": "13 Sentinels: Aegis Rim", "platform": "switch",
                 "requirements": {"minimumIOS": "26.0", "bcTextureCompression": True, "increasedMemoryLimit": False},
                 "results": []}
        (self.catalog / "games" / f"{SENTINELS}.json").write_text(json.dumps(sheet, indent=2) + "\n")
        self.session(self.phones[0], game=SENTINELS)
        self.session(self.phones[1], game=SENTINELS_JAPAN)
        self.session(self.phones[2], game=SENTINELS_JAPAN)
        self.run_sheets()
        self.assertEqual(self.measured(SENTINELS)["iPhone19,4"]["measured"]["iPhones"], 3)
        self.assertIsNone(self.written(MKW))
        self.assert_valid(self.written(SENTINELS))

    def test_the_status_follows_how_the_sessions_ended_and_the_frame_rate(self):
        crash = {"kind": "crash", "signal": 11, "pc": "main+0x10"}
        cases = {
            "iPhone17,1": ([{"frames": None, "fps": None, "minutes": 0.2, "end": {"kind": "boot-failed"}}] * 3,
                           "does-not-run"),
            "iPhone17,2": ([{"end": crash}, {"end": {"kind": "memory-likely"}}, {}], "boots"),
            "iPhone17,3": ([{"end": crash}] + [{}] * 8, "playable-with-issues"),
            "iPhone17,4": ([{"fps": {"median": 50.0, "low5": 45.0}}] * 3, "playable-with-issues"),
            "iPhone17,5": ([{"fps": {"median": 59.0, "low5": 40.0}}] * 3, "playable-with-issues"),
            # A game the player quit behind the console ended well.
            "iPhone18,1": ([{"fps": {"median": 55.0, "low5": 46.0}}] * 2
                           + [{"fps": {"median": 55.0, "low5": 46.0}, "end": {"kind": "quit"}}], "playable"),
        }
        for device, (sessions, _) in cases.items():
            for i, fields in enumerate(sessions):
                self.session(self.phones[i % 3], device=device, **fields)
        self.run_sheets()
        measured = self.measured()
        self.assertEqual({device: measured[device]["status"] for device in cases},
                         {device: status for device, (_, status) in cases.items()})
        self.assertEqual(measured["iPhone17,2"]["notes"][0].split(". ")[-1],
                         "2 sessions ended badly: 1 crash, 1 out of memory.")
        self.assertEqual(measured["iPhone17,2"]["measured"]["endedBadlyPercent"], 66.7)
        # How they ended, for Cartouche to say it in the player's language.
        self.assertEqual(measured["iPhone17,1"]["measured"]["endedBadly"], {"didNotStart": 3})
        self.assertEqual(measured["iPhone17,2"]["measured"]["endedBadly"], {"crashes": 1, "outOfMemory": 1})
        self.assertEqual(measured["iPhone17,3"]["measured"]["endedBadly"], {"crashes": 1})
        self.assertNotIn("endedBadly", measured["iPhone18,1"]["measured"])
        self.assert_valid(self.written())

    def test_a_model_measured_again_is_replaced_and_the_others_stay(self):
        path = self.catalog / "games" / f"{MKW}.json"
        sheet = json.loads(path.read_text(encoding="utf-8"))
        old = {"device": "iPhone19,4", "iOS": "27.2", "date": "2026-10-01", "engine": "nxnative 0123456789ab",
               "status": "boots", "notes": ["Older."],
               "measured": {"iPhones": 3, "sessions": 3, "from": "2026-09-20", "to": "2026-10-01"}}
        other = {**old, "device": "iPhone18,3"}
        sheet["results"] += [other, old]
        path.write_text(json.dumps(sheet, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for phone in self.phones[:3]:
            self.session(phone)
        self.run_sheets()
        results = self.written()["results"]
        self.assertEqual([r["device"] for r in results], ["iPhone19,4", "iPhone18,3", "iPhone19,4"])
        self.assertNotIn("measured", results[0])
        self.assertEqual(results[1], other)
        self.assertEqual((results[2]["date"], results[2]["status"]), ("2026-11-10", "playable"))

    def test_the_same_figures_again_change_nothing(self):
        for phone in self.phones[:3]:
            self.session(phone)
        self.run_sheets()
        shutil.copy(self.work / "sheets" / f"{MKW}.json", self.catalog / "games" / f"{MKW}.json")
        shutil.rmtree(self.work / "sheets")
        (self.work / "output").unlink()
        self.run_sheets()
        self.assertEqual(self.output(), "changed=false\n")
        self.assertIsNone(self.written())

    def test_engines_and_games_without_a_sheet(self):
        builds = ("6c3aeb3d70a1", "6c3aeb3d70a1", "aaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbb")
        for i, build in enumerate(builds):
            self.session(self.phones[i % 3], nxnative=build)
        # A game nxnative's list does not have, on three iPhones of a model.
        for phone in self.phones[:3]:
            self.session(phone, game="0100F2C0115B6000")
        # A game of the list on three iPhones, but two of a model at most.
        for phone, device in zip(self.phones[:3], ("iPhone19,4", "iPhone19,4", "iPhone18,2")):
            self.session(phone, game=SENTINELS, device=device)
        result = self.run_sheets()
        measured = self.measured()["iPhone19,4"]
        self.assertEqual(measured["engine"], "nxnative 6c3aeb3d70a1 and 2 other builds")
        self.assertEqual((measured["measured"]["nxnative"], measured["measured"]["otherBuilds"]), ("6c3aeb3d70a1", 2))
        self.assertIn("Played on 3 iPhones or more, but on fewer than 3 of each model, so with no sheet yet: "
                      f"13 Sentinels: Aegis Rim ({SENTINELS}, 3 iPhones).", result.stdout)
        self.assertIn("Played on 3 iPhones or more, with no sheet, not being in nxnative's list: "
                      "0100F2C0115B6000 (3 iPhones).", result.stdout)
        self.assertNotIn("Left out", result.stdout, "a game with no sheet has no model left out")
        self.assertIsNone(self.written(SENTINELS))
        self.assertIsNone(self.written("0100F2C0115B6000"))
        self.assertEqual(sorted(path.name for path in (self.work / "sheets").iterdir()), [f"{MKW}.json"])

    def test_sessions_that_report_no_build_leave_it_out(self):
        for phone in self.phones[:3]:
            self.session(phone, nxnative=None)
        self.run_sheets()
        result = self.measured()["iPhone19,4"]
        self.assertEqual(result["engine"], "nxnative, its build not reported")
        self.assertNotIn("nxnative", result["measured"])
        self.assertNotIn("otherBuilds", result["measured"])
        self.assert_valid(self.written())

    # MARK: New sheets

    def test_a_game_without_a_sheet_gets_one_once_three_iphones_of_a_model_played_it(self):
        # 13 Sentinels has no sheet: three iPhones of a model, one of them
        # with the Japanese release, and two of another model, which gets no
        # result.
        for phone, game, peak in zip(self.phones[:3], (SENTINELS, SENTINELS_JAPAN, SENTINELS), (1800, 2000, 2100)):
            self.session(phone, game=game, memory={"peakMiB": peak})
        for phone in self.phones[3:5]:
            self.session(phone, game=SENTINELS, device="iPhone18,2")
        result = self.run_sheets()
        self.assertEqual(self.output(), "changed=true\n")
        sheet = self.written(SENTINELS)
        self.assertIsNotNone(sheet, "the game's first sheet, named by its main release's title ID")
        self.assertIsNone(self.written(SENTINELS_JAPAN))
        # nxnative's name and platform; what nxnative needs of every game;
        # and a peak of 2,100 MiB, which leaves the 512 MiB of room under
        # the 3,376 an app had without Increased Memory Limit.
        self.assertEqual({key: sheet[key] for key in ("schema", "titleId", "name", "platform", "requirements")}, {
            "schema": 1, "titleId": SENTINELS, "name": "13 Sentinels: Aegis Rim", "platform": "switch",
            "requirements": {"minimumIOS": "26.0", "bcTextureCompression": True, "increasedMemoryLimit": False}})
        self.assertEqual(list(sheet), ["schema", "titleId", "name", "platform", "requirements", "results"])
        self.assertEqual([r["device"] for r in sheet["results"]], ["iPhone19,4"])
        entry = sheet["results"][0]
        self.assertEqual((entry["status"], entry["peakMemoryMiB"], entry["measured"]["iPhones"]), ("playable", 2100, 3))
        self.assert_valid(sheet)
        self.assertIn("| 13 Sentinels: Aegis Rim | iPhone19,4 | 3 | 3 | playable |", result.stdout)
        self.assertIn(f"New sheets, of games played on 3 iPhones or more of a model: 13 Sentinels: Aegis Rim "
                      f"({SENTINELS}).", result.stdout)
        self.assertIn("Left out: 1 model of a game with a sheet, played on fewer than 3 iPhones.", result.stdout)
        self.assertIn(f"Sheets changed: {SENTINELS}.json.", result.stdout)
        self.assertIsNone(self.written(MKW), "Mario Kart World's sheet, which nobody played, stays as it is")

        # Taken into the catalog, it is a sheet like the others: the same
        # sessions again change nothing.
        shutil.copy(self.work / "sheets" / f"{SENTINELS}.json", self.catalog / "games" / f"{SENTINELS}.json")
        shutil.rmtree(self.work / "sheets")
        self.run_sheets()
        self.assertIsNone(self.written(SENTINELS))

    def test_a_new_sheet_needs_increased_memory_limit_when_its_peak_does_not_fit_without_it(self):
        # The highest of the iPhones' peaks, 2,865 MiB, leaves 511 under the
        # 3,376 an app had without the capability: less than the 512 of
        # room Cartouche keeps under it (docs/decisions.md, 48).
        for phone, peak in zip(self.phones[:3], (2700, 2865, 2800)):
            self.session(phone, game=SENTINELS, memory={"peakMiB": peak})
        self.run_sheets()
        sheet = self.written(SENTINELS)
        self.assertEqual(sheet["results"][0]["peakMemoryMiB"], 2865)
        self.assertTrue(sheet["requirements"]["increasedMemoryLimit"])
        self.assert_valid(sheet)

        # 2,864 MiB leaves the room: the game fits without it.
        self.cloudflare.sql.execute("DELETE FROM reports")
        shutil.rmtree(self.work / "sheets")
        for phone, peak in zip(self.phones[:3], (2700, 2864, 2800)):
            self.session(phone, game=SENTINELS, memory={"peakMiB": peak})
        self.run_sheets()
        self.assertFalse(self.written(SENTINELS)["requirements"]["increasedMemoryLimit"])

    def test_a_new_sheet_needs_nothing_more_than_was_measured(self):
        # A peak of 5,000 MiB on two iPhones only: no peak is given, and
        # nothing says that the game needs Increased Memory Limit.
        self.session(self.phones[0], game=SENTINELS, memory={"peakMiB": 5000})
        self.session(self.phones[1], game=SENTINELS, memory={"peakMiB": 5000})
        self.session(self.phones[2], game=SENTINELS, memory=None, frames=None, fps=None, stutters=None,
                     end={"kind": "crash", "signal": 6})
        self.run_sheets()
        sheet = self.written(SENTINELS)
        self.assertNotIn("peakMemoryMiB", sheet["results"][0])
        self.assertFalse(sheet["requirements"]["increasedMemoryLimit"])
        self.assert_valid(sheet)

        # Nor when devices.json measured no app without the capability.
        devices = copy.deepcopy(DEVICES)
        devices["devices"][0]["measurements"] = [m for m in devices["devices"][0]["measurements"]
                                                 if m["increasedMemoryLimit"]]
        (self.catalog / "devices.json").write_text(json.dumps(devices), encoding="utf-8")
        self.session(self.phones[2], game=SENTINELS, memory={"peakMiB": 5000})
        shutil.rmtree(self.work / "sheets")
        self.run_sheets()
        sheet = self.written(SENTINELS)
        self.assertEqual(sheet["results"][0]["peakMemoryMiB"], 5000)
        self.assertFalse(sheet["requirements"]["increasedMemoryLimit"])

    def test_a_game_that_does_not_run_gets_a_sheet_that_says_so(self):
        for phone in self.phones[:3]:
            self.session(phone, game=SENTINELS, frames=None, fps=None, stutters=None, memory={"peakMiB": 40},
                         minutes=0.3, end={"kind": "boot-failed"})
        self.run_sheets()
        sheet = self.written(SENTINELS)
        self.assertEqual(sheet["results"][0]["status"], "does-not-run")
        self.assertNotIn("peakMemoryMiB", sheet["results"][0])
        self.assertFalse(sheet["requirements"]["increasedMemoryLimit"])
        self.assert_valid(sheet)

    def test_long_sessions_that_drew_no_frame_make_no_result(self):
        # nxnative may write none of the summary lines Cartouche counts
        # frames from, as for Super Mario Galaxy: sessions that lasted half
        # an hour or more in all, with no frame, do not say the game does
        # not run. Ten minutes each, on three iPhones of a model.
        for phone in self.phones[:3]:
            self.session(phone, game=SENTINELS, frames=None, fps=None, stutters=None, minutes=10.0)
            self.session(phone, device="iPhone18,2", frames=None, fps=None, stutters=None, minutes=10.0)
        result = self.run_sheets()
        self.assertIsNone(self.written(SENTINELS), "a game whose sessions counted no frame gets no sheet")
        self.assertIsNone(self.written(), "Mario Kart World's sheet gets no result for iPhone18,2")
        self.assertIn("No result, as none of their sessions drew a frame, though they lasted 30 minutes or more in all "
                      "(nxnative may write no summary line for the game, as much as it may stay on a black screen): "
                      "13 Sentinels: Aegis Rim on iPhone19,4 (3 iPhones, 0.5 hours), "
                      "Mario Kart World on iPhone18,2 (3 iPhones, 0.5 hours).", result.stdout)
        self.assertNotIn("so with no sheet yet", result.stdout)
        self.assertIn("No sheet changed.", result.stdout)

    def test_a_sheet_comes_to_need_increased_memory_limit_once_its_peak_does(self):
        sheet = {"schema": 1, "titleId": SENTINELS, "name": "13 Sentinels: Aegis Rim", "platform": "switch",
                 "requirements": {"minimumIOS": "26.0", "bcTextureCompression": True, "increasedMemoryLimit": False},
                 "results": [{**TESTER, "notes": ["Ran well."]}]}
        path = self.catalog / "games" / f"{SENTINELS}.json"
        path.write_text(json.dumps(sheet, indent=2) + "\n", encoding="utf-8")
        for phone, peak in zip(self.phones[:3], (3100, 2000, 2500)):
            self.session(phone, game=SENTINELS, memory={"peakMiB": peak})
        self.run_sheets()
        written = self.written(SENTINELS)
        self.assertEqual(written["requirements"],
                         {"minimumIOS": "26.0", "bcTextureCompression": True, "increasedMemoryLimit": True})
        self.assertEqual(written["results"][0], sheet["results"][0], "the tester's result stays as it was")
        self.assert_valid(written)

        # Measured lower afterwards, it still needs it: what the
        # measurements showed, they never take back.
        path.write_text(json.dumps(written, indent=2) + "\n", encoding="utf-8")
        self.cloudflare.sql.execute("DELETE FROM reports")
        shutil.rmtree(self.work / "sheets")
        for phone in self.phones[:3]:
            self.session(phone, game=SENTINELS, memory={"peakMiB": 1500})
        self.run_sheets()
        self.assertTrue(self.written(SENTINELS)["requirements"]["increasedMemoryLimit"])

    def test_the_job_that_commits_the_sheets_takes_those_of_the_catalog_and_new_ones_of_nxnatives_list(self):
        written = self.work / "sheets"
        written.mkdir()

        def take():
            return subprocess.run(
                [sys.executable, str(SHEETS), "--catalog", str(self.catalog), "--take", str(written)],
                env=environment(self.server), capture_output=True, text=True, timeout=60)

        mkw = dict(SHEET, results=[TESTER, {**TESTER, "date": "2026-11-12"}])
        sentinels = dict(SHEET, titleId=SENTINELS, name="13 Sentinels: Aegis Rim", platform="switch")
        (written / f"{MKW}.json").write_text(json.dumps(mkw), encoding="utf-8")
        (written / f"{SENTINELS}.json").write_text(json.dumps(sentinels), encoding="utf-8")
        result = take()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [f"{SENTINELS}.json (new)", f"{MKW}.json"])
        self.assertEqual(json.loads((self.catalog / "games" / f"{MKW}.json").read_text(encoding="utf-8")), mkw)
        self.assertEqual(json.loads((self.catalog / "games" / f"{SENTINELS}.json").read_text(encoding="utf-8")),
                         sentinels)

        # Not a sheet of a game nxnative's list does not have, nor one of
        # another region's release, nor a sheet under another game's name,
        # nor anything else: none is taken then. A name that is not a
        # sheet's is said as JSON writes it, on the error's line.
        refused = {
            "0100F2C0115B6000.json": json.dumps(dict(SHEET, titleId="0100F2C0115B6000")),
            f"{SENTINELS_JAPAN}.json": json.dumps(dict(sentinels, titleId=SENTINELS_JAPAN)),
            f"{SENTINELS}.json": json.dumps(dict(SHEET, name="13 Sentinels: Aegis Rim")),
            "notes.txt": "hello",
            f"{SENTINELS}.json\n::notice::taken": json.dumps(sentinels),
        }
        for name, value in refused.items():
            shutil.rmtree(written)
            written.mkdir()
            (written / f"{MKW}.json").write_text(json.dumps(dict(mkw, name="Changed")), encoding="utf-8")
            (written / name).write_text(value, encoding="utf-8")
            result = take()
            self.assertEqual(result.returncode, 1, name)
            said = name if re.fullmatch(r"[0-9A-F]{16}\.json", name) else json.dumps(name)
            self.assertIn(f"::error::{said} ", result.stderr)
            self.assertNotIn("\n::notice::", "\n" + result.stderr + result.stdout)
            self.assertEqual(json.loads((self.catalog / "games" / f"{MKW}.json").read_text(encoding="utf-8")), mkw,
                             "nothing is taken")
        self.assertEqual(json.loads((self.catalog / "games" / f"{SENTINELS}.json").read_text(encoding="utf-8")),
                         sentinels)
        self.assertEqual(sorted(path.name for path in (self.catalog / "games").iterdir()),
                         [f"{SENTINELS}.json", f"{MKW}.json"])

    def test_without_the_secrets_nothing_is_read(self):
        self.session(self.phones[0])
        result = self.run_sheets(secrets=False)
        self.assertIn("not set", result.stdout)
        self.assertEqual(self.output(), "changed=false\n")
        self.assertEqual(self.cloudflare.calls, [])

    def test_a_refusal_fails_the_run_with_cloudflares_words(self):
        values = {"CLOUDFLARE_API_TOKEN": "another-token", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT}
        result = subprocess.run(
            [sys.executable, str(SHEETS), "--catalog", str(self.catalog), "--out", str(self.work / "sheets")],
            env=environment(self.server, **values), capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 1)
        self.assertIn("10000: Authentication error", result.stderr)
        self.assertNotIn("another-token", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
