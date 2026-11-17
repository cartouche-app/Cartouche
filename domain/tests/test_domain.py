"""cartouche.cloud's records, and the script that keeps them at Cloudflare.

    python3 -m unittest discover -s domain/tests -v

The file, domain/records.json, gives the site GitHub Pages' own addresses,
with nothing in front of them, and lets no server send mail as the domain.
The script, domain/sync.py, runs here against a stand-in for Cloudflare's API
and for two resolvers over HTTPS: it changes only the records it made, in one
batch, takes over a record made by hand that the file has too, leaves the
others, and changes nothing without its token or with --plan.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DOMAIN = Path(__file__).resolve().parents[1]
ROOT = DOMAIN.parent
sys.path.insert(0, str(DOMAIN))

import sync  # noqa: E402

RECORDS = DOMAIN / "records.json"

# GitHub Pages' addresses for an apex domain, and the default domain of the
# organization's sites, which www points to without the repository's name
# (docs.github.com, "Managing a custom domain for your GitHub Pages site").
GITHUB_PAGES_A = {"185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"}
GITHUB_PAGES_AAAA = {"2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"}
GITHUB_PAGES_HOST = "cartouche-app.github.io"

TOKEN = "a-token-of-the-tests"


class FakeCloudflare:
    """Cloudflare's API as the script calls it, for one zone and its records,
    checked as Cloudflare checks them, and two resolvers over HTTPS that
    answer from those records: /google, which answers a text unquoted, and
    /cloudflare, which quotes it."""

    PAGE = 3

    def __init__(self, status: str = "active") -> None:
        self.zone = {"id": "z1", "name": "cartouche.cloud", "status": status, "name_servers": ["ariella.ns.cloudflare.com", "neil.ns.cloudflare.com"]}
        self.records: dict[str, dict] = {}
        self.batches: list[dict] = []
        self.calls: list[str] = []
        self.counter = 0
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args) -> None:
                pass

            def answer(self, code: int, body: dict) -> None:
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self) -> None:
                self.route("GET")

            def do_POST(self) -> None:
                self.route("POST")

            def route(self, method: str) -> None:
                url = urllib.parse.urlsplit(self.path)
                query = dict(urllib.parse.parse_qsl(url.query))
                fake.calls.append(f"{method} {url.path}")
                if url.path in ("/google", "/cloudflare"):
                    return self.answer(200, fake.resolve(query["name"], query["type"], quoted=url.path == "/cloudflare"))
                if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                    return self.answer(403, {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]})
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
                code, answer = fake.api(method, url.path, query, body)
                self.answer(code, answer)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()

    def add(self, **record) -> str:
        self.counter += 1
        record.setdefault("ttl", 1)
        record.setdefault("comment", None)
        record.setdefault("proxied", False)
        record["id"] = f"r{self.counter}"
        self.records[record["id"]] = record
        return record["id"]

    def refuse(self, code: int, message: str) -> tuple[int, dict]:
        return 400, {"success": False, "errors": [{"code": code, "message": message}]}

    def api(self, method: str, path: str, query: dict, body) -> tuple[int, dict]:
        if method == "GET" and path == "/zones":
            return 200, {"success": True, "result": [self.zone] if query.get("name") == self.zone["name"] else []}
        if method == "GET" and path == "/zones/z1/dns_records":
            page = int(query.get("page", 1))
            records = sorted(self.records.values(), key=lambda r: int(r["id"][1:]))
            pages = max(1, -(-len(records) // self.PAGE))
            return 200, {
                "success": True,
                "result": records[(page - 1) * self.PAGE:page * self.PAGE],
                "result_info": {"page": page, "per_page": self.PAGE, "total_pages": pages, "total_count": len(records)},
            }
        if method == "POST" and path == "/zones/z1/dns_records/batch":
            return self.batch(body)
        return 404, {"success": False, "errors": [{"code": 7003, "message": "No route for that URI"}]}

    def batch(self, body: dict) -> tuple[int, dict]:
        # One transaction: all of it, or nothing.
        records = json.loads(json.dumps(self.records))
        for entry in body.get("deletes", []):
            if records.pop(entry["id"], None) is None:
                return self.refuse(81044, "Record does not exist.")
        for entry in body.get("patches", []):
            if entry["id"] not in records:
                return self.refuse(81044, "Record does not exist.")
            records[entry["id"]].update({k: v for k, v in entry.items() if k != "id"})
        counter = self.counter
        for entry in body.get("posts", []):
            if entry["type"] == "TXT" and not entry["content"].startswith('"'):
                return self.refuse(9999, "the tests want a text quoted, as Cloudflare keeps it")
            if len(entry.get("comment") or "") > 100:
                return self.refuse(9100, "DNS record comment cannot be longer than 100 characters.")
            if entry["type"] != "TXT" and "proxied" not in entry:
                return self.refuse(9999, "the tests want the proxy status said")
            others = [r for r in records.values() if r["name"] == entry["name"]]
            if others and "CNAME" in [entry["type"]] + [r["type"] for r in others]:
                return self.refuse(81053, "An A, AAAA, or CNAME record with that host already exists.")
            counter += 1
            record = {"ttl": 1, "comment": None, "proxied": False, **entry, "id": f"r{counter}"}
            records[record["id"]] = record
        self.records, self.counter = records, counter
        self.batches.append(body)
        return 200, {"success": True, "result": {}}

    def resolve(self, name: str, kind: str, quoted: bool) -> dict:
        number = sync.TYPES[kind]
        answers = []
        for record in self.records.values():
            if record["name"] != name or record["type"] != kind:
                continue
            data = record["content"]
            if kind == "TXT":
                data = data if quoted else sync.unquote_txt(data)
            elif kind in ("CNAME", "MX"):
                data += "."
            if kind == "MX":
                data = f"{record['priority']} {data}"
            answers.append({"name": name + ".", "type": number, "TTL": 300, "data": data})
        return {"Status": 0 if answers or any(r["name"] == name for r in self.records.values()) else 3, "Answer": answers}


def run(*argv: str, environ: dict | None = None) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        status = sync.main(list(argv), environ if environ is not None else {})
    return status, out.getvalue()


def write_records(directory: str, records: list[dict]) -> Path:
    path = Path(directory) / "records.json"
    path.write_text(json.dumps({"zone": "cartouche.cloud", "records": records}), encoding="utf-8")
    return path


class TheRecords(unittest.TestCase):
    """domain/records.json."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.zone, cls.records = sync.load(RECORDS)

    def named(self, name: str, kind: str | None = None) -> list[sync.Record]:
        return [r for r in self.records if r.name == name and kind in (None, r.type)]

    def test_the_zone_is_cartouche_cloud(self) -> None:
        self.assertEqual(self.zone, "cartouche.cloud")
        self.assertTrue(all(r.why for r in self.records))

    def test_the_site_has_github_pages_addresses_and_nothing_else(self) -> None:
        # Any other A or AAAA record at the apex, or a CNAME there, would stop
        # GitHub Pages from getting the site's certificate.
        self.assertEqual({r.content for r in self.named("cartouche.cloud", "A")}, GITHUB_PAGES_A)
        self.assertEqual({r.content for r in self.named("cartouche.cloud", "AAAA")}, GITHUB_PAGES_AAAA)
        self.assertEqual(self.named("cartouche.cloud", "CNAME"), [])
        self.assertEqual([(r.type, r.content) for r in self.named("www.cartouche.cloud")], [("CNAME", GITHUB_PAGES_HOST)])

    def test_nothing_stands_in_front_of_github_pages(self) -> None:
        # Behind Cloudflare's proxy, GitHub Pages would see Cloudflare's
        # addresses, and could not get the site's certificate.
        for record in self.records:
            self.assertFalse(record.proxied, record.describe())
            self.assertNotIn("*", record.name)

    def test_no_server_sends_mail_as_the_domain(self) -> None:
        self.assertEqual([r.content for r in self.named("cartouche.cloud", "TXT") if r.content.startswith("v=spf1")], ["v=spf1 -all"])
        dmarc = self.named("_dmarc.cartouche.cloud", "TXT")
        self.assertEqual(len(dmarc), 1)
        self.assertTrue(dmarc[0].content.startswith("v=DMARC1; p=reject;"), dmarc[0].content)
        self.assertEqual(self.named("cartouche.cloud", "MX"), [])

    def test_github_verifies_the_domain_for_the_organization(self) -> None:
        # The challenge GitHub showed the organization's owner in its
        # settings, Pages: it stays once the domain is verified, else the
        # verification lapses.
        challenge = self.named("_github-pages-challenge-cartouche-app.cartouche.cloud")
        self.assertEqual([r.type for r in challenge], ["TXT"])
        self.assertRegex(challenge[0].content, r"^[0-9a-f]{20,}$")

    def test_the_check_refuses_what_cloudflare_or_github_would(self) -> None:
        good = {"type": "A", "name": "cartouche.cloud", "content": "185.199.108.153", "why": "The site"}
        for change, problem in (
            ({"name": "*.cartouche.cloud"}, "wildcard"),
            ({"name": "cartouche.app"}, "not a name of the zone"),
            ({"why": " "}, "says why"),
            ({"why": "x" * 90}, "longer than"),
            ({"type": "TXT", "content": "x", "proxied": True}, "proxies only"),
            ({"type": "MX", "content": "mail.cartouche.cloud"}, "priority"),
            ({"type": "SRV"}, "no record of type"),
            ({"content": "185.199.108"}, "185.199.108"),
            ({"ttl": 30}, "TTL"),
            ({"note": "x"}, "have no note"),
        ):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(sync.Problem, problem):
                    sync.load(write_records(directory, [{**good, **change}]))
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(sync.Problem, "twice"):
                sync.load(write_records(directory, [good, {**good, "content": "185.199.108.153 "}]))
            cname = {"type": "CNAME", "name": "www.cartouche.cloud", "content": GITHUB_PAGES_HOST, "why": "www"}
            with self.assertRaisesRegex(sync.Problem, "only record of its name"):
                sync.load(write_records(directory, [cname, {**good, "name": "www.cartouche.cloud"}]))

    def test_records_compare_as_dns_reads_them(self) -> None:
        self.assertEqual(sync.normalized("AAAA", "2606:50c0:8000:0000:0000:0000:0000:0153"), "2606:50c0:8000::153")
        self.assertEqual(sync.normalized("CNAME", "Cartouche-App.GitHub.io."), GITHUB_PAGES_HOST)
        self.assertEqual(sync.normalized("TXT", '"v=spf1 " "-all"'), "v=spf1 -all")
        self.assertEqual(sync.normalized("TXT", "v=spf1 -all"), "v=spf1 -all")
        self.assertEqual(sync.unquote_txt(sync.quote_txt('a "b" \\ c')), 'a "b" \\ c')
        long = "k=" + "x" * 600
        self.assertEqual(sync.quote_txt(long).count('" "'), 2)
        self.assertEqual(sync.unquote_txt(sync.quote_txt(long)), long)


class TheScript(unittest.TestCase):
    """domain/sync.py against a stand-in for Cloudflare."""

    def setUp(self) -> None:
        self.cloudflare = FakeCloudflare()
        self.addCleanup(self.cloudflare.close)
        self.environ = {sync.TOKEN: TOKEN, "CLOUDFLARE_API": self.cloudflare.url}
        _, self.records = sync.load(RECORDS)

    def sync(self, *flags: str, records: Path = RECORDS, environ: dict | None = None) -> tuple[int, str]:
        return run(str(records), *flags, environ=self.environ if environ is None else environ)

    def zone(self) -> set[tuple]:
        return {sync.identity(r["type"], r["name"], r["content"], r.get("priority")) for r in self.cloudflare.records.values()}

    def test_it_adds_the_files_records_in_one_batch_then_changes_nothing(self) -> None:
        status, out = self.sync()
        self.assertEqual(status, 0, out)
        self.assertEqual(self.zone(), {r.key() for r in self.records})
        self.assertEqual(len(self.cloudflare.batches), 1)
        self.assertEqual(len(self.cloudflare.batches[0]["posts"]), len(self.records))
        for record in self.cloudflare.records.values():
            self.assertTrue(record["comment"].startswith(sync.MARK), record)
            self.assertFalse(record["proxied"])
        self.assertIn(f"The zone has the file's {len(self.records)} records.", out)
        status, out = self.sync()
        self.assertEqual(status, 0, out)
        self.assertEqual(len(self.cloudflare.batches), 1)
        self.assertIn("Nothing changed.", out)

    def test_a_plan_changes_nothing(self) -> None:
        status, out = self.sync("--plan")
        self.assertEqual(status, 0, out)
        self.assertEqual(self.cloudflare.records, {})
        self.assertNotIn("POST /zones/z1/dns_records/batch", self.cloudflare.calls)
        self.assertIn("would add", out)
        self.assertIn("Nothing changed: a plan only.", out)

    def test_without_its_token_it_changes_nothing_and_says_so(self) -> None:
        status, out = self.sync(environ={"CLOUDFLARE_API": self.cloudflare.url})
        self.assertEqual(status, 0, out)
        self.assertEqual(self.cloudflare.calls, [])
        self.assertIn(f"::notice::{sync.TOKEN} is not set", out)

    def test_it_takes_over_the_same_record_made_by_hand_and_leaves_the_others(self) -> None:
        self.cloudflare.add(type="A", name="cartouche.cloud", content="185.199.108.153", comment="made by hand")
        self.cloudflare.add(type="TXT", name="cartouche.cloud", content='"v=spf1 -all"')
        other = self.cloudflare.add(type="TXT", name="cartouche.cloud", content='"google-site-verification=abc"')
        status, out = self.sync()
        self.assertEqual(status, 0, out)
        self.assertEqual(len(self.cloudflare.records), len(self.records) + 1)
        self.assertEqual(self.cloudflare.records["r1"]["comment"], sync.MARK + "The site, on GitHub Pages")
        self.assertEqual(self.cloudflare.records["r2"]["comment"], sync.MARK + "No server sends mail as cartouche.cloud")
        self.assertIsNone(self.cloudflare.records[other]["comment"])
        self.assertEqual(len(self.cloudflare.batches[0]["patches"]), 2)
        self.assertIn("Left as they are, not the file's records:", out)
        self.assertIn("google-site-verification=abc", out)

    def test_it_deletes_its_records_the_file_no_longer_has(self) -> None:
        self.assertEqual(self.sync()[0], 0)
        with tempfile.TemporaryDirectory() as directory:
            fewer = [entry for entry in json.loads(RECORDS.read_text())["records"] if entry["type"] != "TXT"]
            status, out = self.sync(records=write_records(directory, fewer))
        self.assertEqual(status, 0, out)
        self.assertEqual(len(self.cloudflare.batches[1]["deletes"]), len([r for r in self.records if r.type == "TXT"]))
        self.assertNotIn("TXT", {r["type"] for r in self.cloudflare.records.values()})
        self.assertIn("deleted", out)

    def test_it_gives_its_records_the_files_settings(self) -> None:
        self.assertEqual(self.sync()[0], 0)
        www = next(r for r in self.cloudflare.records.values() if r["name"] == "www.cartouche.cloud")
        www.update(proxied=True, ttl=3600)
        status, out = self.sync()
        self.assertEqual(status, 0, out)
        self.assertEqual(self.cloudflare.batches[1], {"patches": [{"id": www["id"], "comment": www["comment"], "ttl": 1, "proxied": False}]})
        self.assertFalse(self.cloudflare.records[www["id"]]["proxied"])

    def test_a_cname_beside_a_record_made_by_hand_stops_it_before_anything_changes(self) -> None:
        self.cloudflare.add(type="A", name="www.cartouche.cloud", content="192.0.2.1")
        status, out = self.sync()
        self.assertEqual(status, 1, out)
        self.assertIn("a CNAME is the only record of its name", out)
        self.assertEqual(self.cloudflare.batches, [])

    def test_cloudflares_refusals_fail_it(self) -> None:
        status, out = self.sync(environ={**self.environ, sync.TOKEN: "another"})
        self.assertEqual(status, 1, out)
        self.assertIn("Cloudflare refused GET /zones: 10000 Authentication error", out)
        self.assertNotIn("another", out)
        pending = FakeCloudflare(status="pending")
        self.addCleanup(pending.close)
        status, out = self.sync(environ={**self.environ, "CLOUDFLARE_API": pending.url})
        self.assertEqual(status, 1, out)
        self.assertIn("pending at Cloudflare, not active", out)

    def test_it_writes_what_it_did_in_the_jobs_summary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            summary = Path(directory) / "summary.md"
            status, _ = self.sync(environ={**self.environ, "GITHUB_STEP_SUMMARY": str(summary)})
            self.assertEqual(status, 0)
            text = summary.read_text()
        self.assertIn("## cartouche.cloud", text)
        self.assertIn("Zone active at Cloudflare, served by ariella.ns.cloudflare.com, neil.ns.cloudflare.com.", text)
        self.assertIn("| added | CNAME | www.cartouche.cloud | cartouche-app.github.io |", text)


class TheResolvers(unittest.TestCase):
    """domain/sync.py --resolve, against resolvers that answer from the
    stand-in's records."""

    def setUp(self) -> None:
        self.cloudflare = FakeCloudflare()
        self.addCleanup(self.cloudflare.close)
        self.resolvers = [self.cloudflare.url + "/google", self.cloudflare.url + "/cloudflare"]
        _, self.records = sync.load(RECORDS)

    def fill(self) -> None:
        for record in self.records:
            body = record.body()
            body.pop("comment")
            self.cloudflare.add(**body)

    def test_they_answer_the_files_records(self) -> None:
        self.fill()
        self.cloudflare.add(type="TXT", name="cartouche.cloud", content='"google-site-verification=abc"')
        status, out = run(str(RECORDS), "--resolve", environ={"DOMAIN_RESOLVERS": " ".join(self.resolvers)})
        self.assertEqual(status, 0, out)
        self.assertIn("Every resolver answers the file's records.", out)
        self.assertIn("as the file says, and also google-site-verification=abc", out)

    def test_a_missing_record_fails_once_the_wait_is_over(self) -> None:
        status, lines = sync.resolve(self.records, self.resolvers, wait=0)
        self.assertEqual(status, 1)
        self.assertIn("still missing 185.199.108.153", "\n".join(lines))

    def test_it_asks_again_until_they_answer(self) -> None:
        now = [0.0]
        waits = []

        def sleep(seconds: float) -> None:
            waits.append(seconds)
            now[0] += seconds
            if len(waits) == 2:
                self.fill()

        status, lines = sync.resolve(self.records, self.resolvers, wait=600, sleep=sleep, clock=lambda: now[0])
        self.assertEqual(status, 0, "\n".join(lines))
        self.assertEqual(waits, [30, 30])


class TheWorkflow(unittest.TestCase):
    """The Domain workflow applies the file from main alone, with the secret
    of the environment cloudflare, and the CI tests it on every pull request."""

    def test_it_applies_the_file_from_main_with_the_environments_secret(self) -> None:
        workflow = (ROOT / ".github/workflows/domain.yml").read_text()
        self.assertIn("if: ${{ github.ref == 'refs/heads/main' }}", workflow)
        self.assertIn("environment: cloudflare", workflow)
        self.assertIn("CLOUDFLARE_DOMAIN_TOKEN: ${{ secrets.CLOUDFLARE_DOMAIN_TOKEN }}", workflow)
        self.assertIn("python3 domain/sync.py domain/records.json", workflow)
        self.assertIn('paths: ["domain/**", ".github/workflows/domain.yml"]', workflow)
        self.assertNotIn("pull_request", workflow)

    def test_the_ci_runs_these_tests(self) -> None:
        self.assertIn("python3 -m unittest discover -s domain/tests -v", (ROOT / ".github/workflows/ci.yml").read_text())


if __name__ == "__main__":
    unittest.main()
