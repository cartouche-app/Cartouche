"""Checks telemetry/move.sh against a stand-in for Cloudflare's API with two
accounts: the zone's, where the telemetry goes, and the one it started in.

- move: the former Worker becomes the relay, holding the reports before the
  export begins, with no daily run; every row of the former database's four
  tables reaches the new one, in the same order, a problem's lines and
  quotes as they were, each once; a row the former database took after its
  copy comes in a second round; then the relay opens, to
  https://telemetry.cartouche.cloud, at the former workers.dev address, and
  the job's summary says what the former account still holds;
- the move does nothing while the new database holds rows and the former
  Worker is the server still, nor before the telemetry is deployed in the
  zone's account; run again after a move, it adds what is missing and
  keeps what the relay brought;
- relay: the relay again, open, only once the move is done;
- clean: only once the move is done, and while the new database holds at
  least the former's rows, it deletes the former database and dashboard,
  and keeps the relay;
- the tokens go to Cloudflare in headers, and are never printed;
- the workflow runs it by hand only, from the environment cloudflare, with
  the step asked.

Run from the repository root: python3 -m unittest discover -s telemetry/test -v
"""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from standin import ACCOUNT, FORMER_ACCOUNT, FORMER_TOKEN, TOKEN, Cloudflare, environment, serve

HERE = Path(__file__).resolve().parent
MOVE = HERE.parent / "move.sh"
RELAY = HERE.parent / "relay" / "worker.js"
SCHEMA = HERE.parent / "schema.sql"
WORKFLOW = HERE.parents[1] / ".github" / "workflows" / "telemetry-move.yml"
TARGET = "https://telemetry.cartouche.cloud"
NAME = "cartouche-telemetry"
FORMER = f"/client/v4/accounts/{FORMER_ACCOUNT}"
NEW = f"/client/v4/accounts/{ACCOUNT}"


def schema() -> str:
    return "\n".join(line for line in SCHEMA.read_text(encoding="utf-8").splitlines() if not re.match(r"\s*--", line))


def everything(sql) -> dict:
    """Each table's rows, in the order they came."""
    return {table: [tuple(row) for row in sql.execute(f"SELECT * FROM {table} ORDER BY rowid")]
            for table in ("reports", "daily", "problems", "lookups")}


@unittest.skipUnless(shutil.which("curl") and shutil.which("jq"), "the move needs curl and jq")
class MoveTest(unittest.TestCase):
    def setUp(self):
        self.cloudflare = Cloudflare()
        self.server = serve(self.cloudflare)
        self.addCleanup(self.cloudflare.main.sql.close)
        self.addCleanup(self.cloudflare.former.sql.close)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        # The zone's account, as the deploy left it: the new database, empty.
        main = self.cloudflare.main
        main.databases.append({"uuid": "d1-0", "name": NAME, "jurisdiction": "eu"})
        main.sql.executescript(schema())
        # The account the telemetry started in: its server, its dashboard and
        # their database, with rows.
        former = self.cloudflare.former
        former.subdomain = "perso-test"
        former.databases.append({"uuid": "former-d1-0", "name": NAME, "jurisdiction": "eu"})
        database = [{"type": "d1", "name": "DB", "id": "former-d1-0"}]
        for name in (NAME, "cartouche-dashboard"):
            former.scripts[name] = {"metadata": {"main_module": "worker.js", "bindings": database}, "module": b"// the server"}
            former.enabled[name] = {"enabled": True, "previews_enabled": False}
        former.schedules[NAME] = [{"cron": "17 3 * * *"}]
        former.sql.executescript(schema())
        former.sql.executemany("INSERT INTO reports (id, kind, install, day, seq, cartouche, device, ios, body) "
                               "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [
                                   (f"r{n:03}", "event", f"install-{n % 7}", f"2026-11-{10 + n % 14:02}", n, "0.15.1",
                                    "iPhone18,1", "27.2", f'{{"n": {n}, "name": "app.opened"}}')
                                   for n in (5, 1, 9, 3, 7, 2, 8)])
        former.sql.executemany("INSERT INTO daily VALUES (?, ?, ?)", [("install-1", "2026-11-23", 12), ("install-2", "2026-11-24", 3)])
        former.sql.execute("INSERT INTO problems VALUES (?, ?, ?, ?, ?)",
                           ("p1", "2026-11-24", "It's stuck", "What happened:\nINSERT INTO 'x' -- it's \"quoted\"\n\nLogs:\n…", None))
        former.sql.execute("INSERT INTO lookups VALUES (?, ?, ?)", ("switch:zelda", "2026-11-20", '{"id": 7}'))
        former.sql.commit()

    def move(self, step="move", **values):
        secrets = {"CLOUDFLARE_DOMAIN_TOKEN": TOKEN, "CLOUDFLARE_API_TOKEN": FORMER_TOKEN, "CLOUDFLARE_ACCOUNT_ID": FORMER_ACCOUNT}
        secrets.update(values)
        with tempfile.TemporaryDirectory() as folder:
            summary = Path(folder) / "summary.md"
            result = subprocess.run(["bash", str(MOVE), step], capture_output=True, text=True, timeout=60,
                                    env=environment(self.server, GITHUB_STEP_SUMMARY=str(summary), TELEMETRY_CHECK_TRIES="1",
                                                    TELEMETRY_MOVE_SETTLE="0", TELEMETRY_MOVE_POLL="0", TELEMETRY_MOVE_POLLS="5",
                                                    **secrets))
            result.summary = summary.read_text() if summary.exists() else ""
        self.assertNotIn(TOKEN, result.stdout + result.stderr + result.summary)
        self.assertNotIn(FORMER_TOKEN, result.stdout + result.stderr + result.summary)
        return result

    def relay(self):
        return self.cloudflare.former.scripts[NAME]

    def test_the_move_holds_the_reports_copies_every_row_then_opens_the_relay(self):
        before = everything(self.cloudflare.former.sql)
        held = []
        self.cloudflare.while_exporting = lambda account: held.append(self.relay()["metadata"]["bindings"])
        result = self.move()
        self.assertEqual(result.returncode, 0, result.stderr)
        # Held before D1 took its copy: no report reached the former database after it.
        self.assertEqual(held, [[{"type": "plain_text", "name": "TARGET", "text": TARGET},
                                 {"type": "plain_text", "name": "HOLD", "text": "yes"}]])
        # Every row, in the order it came, each once.
        self.assertEqual(everything(self.cloudflare.main.sql), before)
        self.assertEqual(len(self.cloudflare.imports), 1)
        imported = self.cloudflare.imports[0][1]
        self.assertNotRegex(imported, r'(?m)^INSERT INTO "')
        # A line of the player's text that starts as a statement does is theirs, untouched.
        self.assertIn("\nINSERT INTO ''x'' -- it''s", imported)
        self.assertRegex(imported, r'(?m)^INSERT OR IGNORE INTO "reports"')
        self.assertNotIn("CREATE TABLE", imported)
        # The relay, open, at the former address, with no database and no daily run.
        relay = self.relay()
        self.assertEqual(relay["module"], RELAY.read_bytes())
        self.assertEqual(relay["module type"], "application/javascript+module")
        self.assertEqual(relay["metadata"]["bindings"], [{"type": "plain_text", "name": "TARGET", "text": TARGET}])
        self.assertEqual(relay["metadata"]["observability"], {"enabled": False})
        self.assertEqual(self.cloudflare.former.enabled[NAME], {"enabled": True, "previews_enabled": False})
        self.assertEqual(self.cloudflare.former.schedules[NAME], [])
        # Nothing deleted yet; the former dashboard reads what it read.
        self.assertEqual(self.cloudflare.former.deleted, [])
        self.assertEqual(everything(self.cloudflare.former.sql), before)
        self.assertIn("Moved: the new database holds every row of the former", result.summary)
        self.assertIn(f"The former address https://{NAME}.perso-test.workers.dev relays to {TARGET}, which answers.", result.summary)
        self.assertIn("The former account holds the Workers: cartouche-dashboard, cartouche-telemetry; "
                      "the D1 databases: cartouche-telemetry.", result.summary)
        # Nothing of the zone's account's Workers is touched.
        self.assertEqual(self.cloudflare.main.scripts, {})

    def test_a_row_the_former_database_took_after_its_copy_comes_in_a_second_round(self):
        late = []

        def arrives(account):
            if not late:
                late.append(1)
                account.sql.execute("INSERT INTO reports (id, kind, install, day, body) VALUES ('late', 'event', 'i', '2026-11-24', '{}')")
                account.sql.commit()

        self.cloudflare.while_exporting = arrives
        result = self.move()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.cloudflare.imports), 2)
        self.assertEqual(everything(self.cloudflare.main.sql), everything(self.cloudflare.former.sql))
        self.assertIn("Round 2:", result.stdout)

    def test_databases_that_still_differ_keep_the_reports_held(self):
        self.cloudflare.while_exporting = lambda account: (
            account.sql.execute(f"INSERT INTO daily VALUES ('i', '{len(self.cloudflare.imports)}', 1)"), account.sql.commit())
        result = self.move()
        self.assertEqual(result.returncode, 1)
        self.assertIn("still differ after three rounds", result.stderr)
        self.assertIn({"type": "plain_text", "name": "HOLD", "text": "yes"}, self.relay()["metadata"]["bindings"])

    def test_nothing_moves_while_the_new_database_holds_rows_and_the_former_worker_is_the_server(self):
        self.cloudflare.main.sql.execute("INSERT INTO reports (id, kind, install, day, body) VALUES ('new', 'event', 'i', 'd', '{}')")
        result = self.move()
        self.assertEqual(result.returncode, 1)
        self.assertIn("The new database holds rows already", result.stderr)
        self.assertEqual(self.relay()["module"], b"// the server")
        self.assertEqual(self.cloudflare.exports, 0)

    def test_nothing_moves_before_the_telemetry_is_deployed_in_the_zones_account(self):
        self.cloudflare.main.databases.clear()
        result = self.move()
        self.assertEqual(result.returncode, 1)
        self.assertIn("deploy the telemetry first", result.stderr)
        self.assertEqual(self.relay()["module"], b"// the server")

    def test_a_move_run_again_adds_what_is_missing_and_keeps_what_the_relay_brought(self):
        self.assertEqual(self.move().returncode, 0)
        main = self.cloudflare.main.sql
        main.execute("INSERT INTO reports (id, kind, install, day, body) VALUES ('relayed', 'event', 'i', '2026-11-25', '{}')")
        main.execute("DELETE FROM reports WHERE id = 'r003'")
        main.commit()
        result = self.move()
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = {row[0] for row in main.execute("SELECT id FROM reports")}
        self.assertEqual(ids, {row[0] for row in self.cloudflare.former.sql.execute("SELECT id FROM reports")} | {"relayed"})
        self.assertEqual(self.relay()["metadata"]["bindings"], [{"type": "plain_text", "name": "TARGET", "text": TARGET}])

    def test_the_relay_goes_again_once_the_move_is_done(self):
        result = self.move("relay")
        self.assertEqual(result.returncode, 1)
        self.assertIn("run the step move first", result.stderr)
        self.assertEqual(self.relay()["module"], b"// the server")
        self.assertEqual(self.move().returncode, 0)
        self.relay()["module"] = b"// an older relay"
        result = self.move("relay")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.relay()["module"], RELAY.read_bytes())

    def test_clean_deletes_the_former_database_and_dashboard_once_the_move_is_done(self):
        result = self.move("clean")
        self.assertEqual(result.returncode, 1)
        self.assertIn("run the step move first", result.stderr)
        self.assertEqual(self.cloudflare.former.deleted, [])
        self.assertEqual(self.move().returncode, 0)
        result = self.move("clean")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cloudflare.former.deleted, [("d1", "former-d1-0"), ("worker", "cartouche-dashboard")])
        self.assertEqual(list(self.cloudflare.former.scripts), [NAME])
        self.assertEqual(self.relay()["module"], RELAY.read_bytes())
        self.assertIn("The former account holds the Workers: cartouche-telemetry; the D1 databases: none.", result.summary)
        # Again: nothing left to delete.
        result = self.move("clean")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("The former account has no dashboard.", result.stdout)

    def test_clean_deletes_nothing_while_the_new_database_holds_less(self):
        self.assertEqual(self.move().returncode, 0)
        self.cloudflare.main.sql.execute("DELETE FROM lookups")
        self.cloudflare.main.sql.commit()
        result = self.move("clean")
        self.assertEqual(result.returncode, 1)
        self.assertIn("The new database holds less than the former", result.stderr)
        self.assertEqual(self.cloudflare.former.deleted, [])

    def test_it_needs_both_accounts_and_a_step(self):
        self.assertEqual(self.move("everything").returncode, 2)
        result = self.move(CLOUDFLARE_API_TOKEN="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("No CLOUDFLARE_API_TOKEN", result.stderr)
        self.assertEqual(self.cloudflare.calls, [])

    def test_the_workflow_runs_a_step_by_hand_from_the_environment_cloudflare(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertRegex(workflow, r"(?m)^on:\n  workflow_dispatch:")
        self.assertNotRegex(workflow, r"(?m)^  (push|pull_request|schedule):")
        self.assertIn("environment: cloudflare", workflow)
        for secret in ("CLOUDFLARE_DOMAIN_TOKEN", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
            self.assertIn(f"{secret}: ${{{{ secrets.{secret} }}}}", workflow)
        self.assertIn('telemetry/move.sh "$STEP"', workflow)
        for step in ("move", "relay", "clean"):
            self.assertRegex(workflow, rf"(?m)^\s+- {step}$")


if __name__ == "__main__":
    unittest.main()
