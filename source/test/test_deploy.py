"""Checks source/deploy.sh against a stand-in for Cloudflare's API and for
the source's address.

- without the domain's token, the deploy does nothing;
- it reads the zone, and deploys in the zone's account: worker.js as it is,
  as the Worker cartouche-source's module, with no binding and no logs kept,
  without its workers.dev address;
- it attaches source.cartouche.cloud to the Worker, with the zone, once:
  a deploy again leaves the domain as it is; a domain another Worker has
  stops it;
- it removes the copy the first deploy left in the telemetry's account,
  with the telemetry's token, and says when there is none;
- while the domain's token may not deploy Workers, it warns with what to add
  to it, and does not fail; any other refusal fails it with Cloudflare's
  errors;
- the tokens go to Cloudflare in headers, and are never printed;
- it says whether the address gives the source, and warns when it does not.

Run from the repository root: python3 -m unittest discover -s source/test -v
"""

import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from email.parser import BytesParser
from email.policy import HTTP
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

HERE = Path(__file__).resolve().parent
DEPLOY = HERE.parent / "deploy.sh"
WORKER = HERE.parent / "worker.js"
SOURCE = HERE.parent.parent / "app" / "sidestore-player-source.json"
TOKEN = "domain-token-that-must-never-be-printed"
TELEMETRY_TOKEN = "telemetry-token-that-must-never-be-printed"
ACCOUNT = "c0ffee00c0ffee00c0ffee00c0ffee00"
TELEMETRY_ACCOUNT = "0123456789abcdef0123456789abcdef"
ZONE_ID = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"
HOST = "source.cartouche.cloud"
PERMISSIONS = "add Account › Workers Scripts › Edit and Zone › Workers Routes › Edit"


def ok(result=None):
    return 200, {"success": True, "errors": [], "messages": [], "result": {} if result is None else result}


def refused(status, code, message):
    return status, {"success": False, "errors": [{"code": code, "message": message}], "messages": [], "result": None}


class StandIn:
    """Cloudflare's API under /client/v4, and the source's address at /source/."""

    def __init__(self):
        self.calls: list[tuple[str, str, dict, bytes]] = []
        self.may_deploy = True
        self.refuse_upload = False
        self.domains: list[dict] = []
        self.telemetry_copy = True
        self.source: tuple[int, bytes] = (200, SOURCE.read_bytes())

    def answer(self, method, url, headers, body):
        parts = urlsplit(url)
        path, query = parts.path, parse_qs(parts.query)
        if path == "/source/":
            return self.source[0], self.source[1]
        self.calls.append((method, url, headers, body))
        status, answer = self.api(method, path, query, headers.get("Authorization"), body)
        return status, json.dumps(answer).encode()

    def api(self, method, path, query, authorization, body):
        path = path.removeprefix("/client/v4")
        if authorization == f"Bearer {TELEMETRY_TOKEN}":
            if method == "DELETE" and path == f"/accounts/{TELEMETRY_ACCOUNT}/workers/scripts/cartouche-source":
                if not self.telemetry_copy:
                    return refused(404, 10007, "workers.api.error.script_not_found")
                self.telemetry_copy = False
                return ok(None)
            return refused(403, 10000, "Authentication error")
        if authorization != f"Bearer {TOKEN}":
            return refused(403, 10000, "Authentication error")
        if method == "GET" and path == "/zones":
            self.assert_equal(query, {"name": ["cartouche.cloud"]})
            return ok([{"id": ZONE_ID, "name": "cartouche.cloud", "account": {"id": ACCOUNT, "name": "cartouche.cloud"}}])
        if not path.startswith(f"/accounts/{ACCOUNT}/workers/"):
            return refused(404, 7003, "Could not route to " + path)
        if not self.may_deploy:
            return refused(403, 10000, "Authentication error")
        rest = path.removeprefix(f"/accounts/{ACCOUNT}/workers/")
        if method == "PUT" and rest == "scripts/cartouche-source":
            if self.refuse_upload:
                return refused(400, 10021, "Uncaught SyntaxError")
            return ok({"id": "cartouche-source"})
        if method == "POST" and rest == "scripts/cartouche-source/subdomain":
            return ok({"enabled": False})
        if method == "GET" and rest == "domains":
            return ok([one for one in self.domains if one["hostname"] in query.get("hostname", [one["hostname"]])])
        if method == "PUT" and rest == "domains":
            asked = json.loads(body)
            domain = {"id": "d1", "hostname": asked["hostname"], "service": asked["service"], "zone_id": asked["zone_id"],
                      "zone_name": "cartouche.cloud", "environment": "production"}
            self.domains.append(domain)
            return ok(domain)
        return refused(404, 7003, "Could not route to " + path)

    @staticmethod
    def assert_equal(a, b):
        if a != b:
            raise AssertionError(f"{a!r} != {b!r}")


def serve(standin: StandIn) -> ThreadingHTTPServer:
    class Handler(BaseHTTPRequestHandler):
        def handle_one(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            status, answer = standin.answer(self.command, self.path, dict(self.headers), body)
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(answer)))
            self.end_headers()
            self.wfile.write(answer)

        do_GET = do_PUT = do_POST = do_DELETE = handle_one

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def parts(headers: dict, body: bytes) -> dict:
    """The parts of a multipart body, by name: (content type, bytes)."""
    message = BytesParser(policy=HTTP).parsebytes(f"Content-Type: {headers['Content-Type']}\r\n\r\n".encode() + body)
    return {part.get_param("name", header="content-disposition"): (part.get_content_type(), part.get_payload(decode=True))
            for part in message.iter_parts()}


@unittest.skipUnless(shutil.which("curl") and shutil.which("jq"), "the deploy needs curl and jq")
class DeployTest(unittest.TestCase):
    def setUp(self):
        self.standin = StandIn()
        self.server = serve(self.standin)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_port}"
        self.summary = Path(self.enterContext(tempfile.TemporaryDirectory())) / "summary.md"

    def deploy(self, **values) -> subprocess.CompletedProcess:
        env = {key: value for key, value in os.environ.items() if not key.startswith(("CLOUDFLARE_", "GITHUB_"))}
        env.update(CLOUDFLARE_DOMAIN_TOKEN=TOKEN, CLOUDFLARE_API_TOKEN=TELEMETRY_TOKEN, CLOUDFLARE_ACCOUNT_ID=TELEMETRY_ACCOUNT,
                   CLOUDFLARE_API=f"{self.base}/client/v4", CARTOUCHE_SOURCE_ADDRESS=f"{self.base}/source/",
                   CARTOUCHE_SOURCE_TRIES="1", GITHUB_STEP_SUMMARY=str(self.summary))
        env.update(values)
        env = {key: value for key, value in env.items() if value is not None}
        result = subprocess.run([str(DEPLOY)], env=env, capture_output=True, text=True, timeout=60)
        for token in (TOKEN, TELEMETRY_TOKEN):
            self.assertNotIn(token, result.stdout + result.stderr)
        return result

    def asked(self):
        return [(method, url.removeprefix("/client/v4")) for method, url, _, _ in self.standin.calls]

    def test_without_the_domains_token_it_does_nothing(self):
        result = self.deploy(CLOUDFLARE_DOMAIN_TOKEN=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("is not deployed", result.stdout)
        self.assertEqual(self.standin.calls, [])

    def test_it_deploys_in_the_zones_account_and_attaches_the_domain(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        scripts = f"/accounts/{ACCOUNT}/workers/scripts/cartouche-source"
        self.assertEqual(self.asked(), [
            ("GET", "/zones?name=cartouche.cloud"),
            ("PUT", scripts),
            ("POST", scripts + "/subdomain"),
            ("GET", f"/accounts/{ACCOUNT}/workers/domains?hostname={HOST}"),
            ("PUT", f"/accounts/{ACCOUNT}/workers/domains"),
            ("DELETE", f"/accounts/{TELEMETRY_ACCOUNT}/workers/scripts/cartouche-source"),
        ])
        _, _, headers, body = self.standin.calls[1]
        uploaded = parts(headers, body)
        self.assertEqual(uploaded["worker.js"], ("application/javascript+module", WORKER.read_bytes()))
        metadata = json.loads(uploaded["metadata"][1])
        self.assertEqual(metadata["main_module"], "worker.js")
        self.assertEqual(metadata["bindings"], [])
        self.assertEqual(metadata["observability"], {"enabled": False})
        self.assertRegex(metadata["compatibility_date"], r"^\d{4}-\d{2}-\d{2}$")
        self.assertEqual(json.loads(self.standin.calls[2][3]), {"enabled": False, "previews_enabled": False})
        self.assertEqual(json.loads(self.standin.calls[4][3]), {"hostname": HOST, "service": "cartouche-source", "zone_id": ZONE_ID})
        self.assertIn("Removed the copy of cartouche-source from the telemetry's account", result.stdout)
        self.assertFalse(self.standin.telemetry_copy)

    def test_a_deploy_again_keeps_the_domain_and_finds_no_copy_to_remove(self):
        self.deploy()
        self.standin.calls.clear()
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(("PUT", f"/accounts/{ACCOUNT}/workers/domains"), self.asked())
        self.assertIn(f"{HOST} is the Worker's domain", result.stdout)
        self.assertIn("The telemetry's account has no copy of cartouche-source", result.stdout)
        self.assertEqual(len(self.standin.domains), 1)

    def test_without_the_telemetrys_secrets_it_removes_nothing(self):
        result = self.deploy(CLOUDFLARE_API_TOKEN=None, CLOUDFLARE_ACCOUNT_ID=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("DELETE", [method for method, _ in self.asked()])

    def test_a_domain_another_worker_has_stops_it(self):
        self.standin.domains.append({"id": "d0", "hostname": HOST, "service": "something-else", "zone_id": ZONE_ID})
        result = self.deploy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("is the domain of the Worker something-else", result.stderr)

    def test_while_the_token_may_not_deploy_it_warns_with_what_to_add_and_does_not_fail(self):
        self.standin.may_deploy = False
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("::warning::The token Cartouche domain may not deploy the source's Worker yet", result.stdout)
        self.assertIn(PERMISSIONS, result.stdout)
        self.assertIn(PERMISSIONS, self.summary.read_text())
        self.assertEqual([method for method, _ in self.asked()], ["GET", "PUT"])

    def test_a_refused_upload_fails_the_deploy(self):
        self.standin.refuse_upload = True
        result = self.deploy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("10021: Uncaught SyntaxError", result.stderr)

    def test_it_says_when_the_address_gives_the_source(self):
        result = self.deploy()
        self.assertIn(f"{self.base}/source/ gives Cartouche's source for SideStore", result.stdout)
        self.assertNotIn("::warning::", result.stdout)
        self.assertIn(f"{self.base}/source/", self.summary.read_text())

    def test_it_warns_when_the_address_does_not_give_the_source_yet(self):
        for answer in [(404, b"not found"), (200, b"<!doctype html>"), (200, b'{"identifier": "another", "apps": []}')]:
            with self.subTest(answer=answer):
                self.standin.source = answer
                result = self.deploy()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("::warning::", result.stdout)
                self.assertIn("does not give the source yet", result.stdout)


if __name__ == "__main__":
    unittest.main()
