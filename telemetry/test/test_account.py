"""Checks telemetry/account.sh against a stand-in for Cloudflare's API: it
prints the account of the zone cartouche.cloud, where the database is
(decision 158), for the token that sees the zone; it fails with
Cloudflare's words for one that does not; it prints nothing without a
token; the token is never printed. And the workflows that read the database
read it there, with the domain's token.

Run from the repository root: python3 -m unittest discover -s telemetry/test -v
"""

import shutil
import subprocess
import unittest
from pathlib import Path

from standin import ACCOUNT, FORMER_TOKEN, TOKEN, Cloudflare, environment, serve

HERE = Path(__file__).resolve().parent
ACCOUNT_SH = HERE.parent / "account.sh"
WORKFLOWS = HERE.parents[1] / ".github" / "workflows"


@unittest.skipUnless(shutil.which("curl") and shutil.which("jq"), "it needs curl and jq")
class AccountTest(unittest.TestCase):
    def setUp(self):
        self.cloudflare = Cloudflare()
        self.server = serve(self.cloudflare)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def account(self, **values):
        return subprocess.run(["bash", str(ACCOUNT_SH)], env=environment(self.server, **values),
                              capture_output=True, text=True, timeout=30)

    def test_it_prints_the_account_of_the_zone(self):
        result = self.account(CLOUDFLARE_API_TOKEN=TOKEN)
        self.assertEqual((result.returncode, result.stdout), (0, f"{ACCOUNT}\n"), result.stderr)
        self.assertNotIn(TOKEN, result.stderr)

    def test_a_token_that_does_not_see_the_zone_fails(self):
        result = self.account(CLOUDFLARE_API_TOKEN=FORMER_TOKEN)
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("does not see the zone cartouche.cloud", result.stderr)
        result = self.account(CLOUDFLARE_API_TOKEN="another-token")
        self.assertEqual((result.returncode, result.stdout), (1, ""))
        self.assertIn("10000: Authentication error", result.stderr)
        self.assertNotIn("another-token", result.stderr)

    def test_without_a_token_it_prints_nothing(self):
        result = self.account(CLOUDFLARE_API_TOKEN="")
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        self.assertEqual(self.cloudflare.calls, [])

    def test_the_readers_of_the_database_read_it_in_the_zones_account(self):
        for workflow, script in (("telemetry-export.yml", "telemetry/export.py"), ("measurements.yml", "telemetry/sheets.py"),
                                 ("nxnative.yml", "telemetry/nxnative.py")):
            text = (WORKFLOWS / workflow).read_text(encoding="utf-8")
            self.assertIn("CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_DOMAIN_TOKEN }}", text, workflow)
            self.assertNotIn("secrets.CLOUDFLARE_ACCOUNT_ID", text, workflow)
            # A token that does not see the zone fails the step, rather than reading nothing.
            self.assertIn(f'CLOUDFLARE_ACCOUNT_ID="$(telemetry/account.sh)"\n          export CLOUDFLARE_ACCOUNT_ID\n          python3 {script}',
                          text, workflow)


if __name__ == "__main__":
    unittest.main()
