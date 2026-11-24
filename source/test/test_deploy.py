"""Checks source/deploy.sh against a stand-in for Cloudflare's API and for
the source's address.

- without the secrets, the deploy does nothing;
- it uploads worker.js as it is, as the Worker cartouche-source's module,
  with no binding and no logs kept, and turns off its workers.dev address;
- the token goes to Cloudflare in a header, and is never printed;
- when the address gives the source, the deploy says so; when it does not,
  as before the domain is attached to the Worker, it warns with the steps
  that attach it, and does not fail;
- Cloudflare refusing the upload fails the deploy with its errors.

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

HERE = Path(__file__).resolve().parent
DEPLOY = HERE.parent / "deploy.sh"
WORKER = HERE.parent / "worker.js"
SOURCE = HERE.parent.parent / "app" / "sidestore-player-source.json"
TOKEN = "cf-token-that-must-never-be-printed"
ACCOUNT = "0123456789abcdef0123456789abcdef"


class StandIn:
    """Cloudflare's API under /client/v4, and the source's address at /source/."""

    def __init__(self):
        self.calls: list[tuple[str, str, dict, bytes]] = []
        self.refuse_upload = False
        self.source: tuple[int, bytes] = (200, SOURCE.read_bytes())

    def answer(self, method, path, headers, body):
        if path == "/source/":
            return self.source
        self.calls.append((method, path, headers, body))
        if headers.get("Authorization") != f"Bearer {TOKEN}":
            return 403, json.dumps({"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}).encode()
        if method == "PUT" and path.endswith("/workers/scripts/cartouche-source") and self.refuse_upload:
            return 400, json.dumps({"success": False, "errors": [{"code": 10021, "message": "Uncaught SyntaxError"}]}).encode()
        return 200, json.dumps({"success": True, "errors": [], "result": {}}).encode()


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

        do_GET = do_PUT = do_POST = handle_one

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
        env.update(CLOUDFLARE_API_TOKEN=TOKEN, CLOUDFLARE_ACCOUNT_ID=ACCOUNT, CLOUDFLARE_API=f"{self.base}/client/v4",
                   CARTOUCHE_SOURCE_ADDRESS=f"{self.base}/source/", GITHUB_STEP_SUMMARY=str(self.summary))
        env.update(values)
        env = {key: value for key, value in env.items() if value is not None}
        result = subprocess.run([str(DEPLOY)], env=env, capture_output=True, text=True, timeout=60)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        return result

    def test_without_the_secrets_it_does_nothing(self):
        result = self.deploy(CLOUDFLARE_API_TOKEN=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("is not deployed", result.stdout)
        self.assertEqual(self.standin.calls, [])

    def test_it_uploads_the_worker_and_turns_off_its_workers_dev_address(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        prefix = f"/client/v4/accounts/{ACCOUNT}/workers/scripts/cartouche-source"
        self.assertEqual([(method, path) for method, path, _, _ in self.standin.calls],
                         [("PUT", prefix), ("POST", prefix + "/subdomain")])
        _, _, headers, body = self.standin.calls[0]
        uploaded = parts(headers, body)
        self.assertEqual(uploaded["worker.js"], ("application/javascript+module", WORKER.read_bytes()))
        metadata = json.loads(uploaded["metadata"][1])
        self.assertEqual(metadata["main_module"], "worker.js")
        self.assertEqual(metadata["bindings"], [])
        self.assertEqual(metadata["observability"], {"enabled": False})
        self.assertRegex(metadata["compatibility_date"], r"^\d{4}-\d{2}-\d{2}$")
        self.assertEqual(json.loads(self.standin.calls[1][3]), {"enabled": False, "previews_enabled": False})

    def test_it_says_when_the_address_gives_the_source(self):
        result = self.deploy()
        self.assertIn(f"{self.base}/source/ gives Cartouche's source for SideStore", result.stdout)
        self.assertNotIn("::warning::", result.stdout)
        self.assertIn(f"{self.base}/source/", self.summary.read_text())

    def test_until_the_domain_is_attached_it_warns_with_the_steps_and_does_not_fail(self):
        for answer in [(404, b"not found"), (200, b"<!doctype html>"), (200, b'{"identifier": "another", "apps": []}')]:
            with self.subTest(answer=answer):
                self.standin.source = answer
                result = self.deploy()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("::warning::", result.stdout)
                self.assertIn("Workers & Pages › cartouche-source › Settings › Domains & Routes › Add › Custom domain › source.cartouche.cloud",
                              result.stdout)

    def test_a_refused_upload_fails_the_deploy(self):
        self.standin.refuse_upload = True
        result = self.deploy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("10021: Uncaught SyntaxError", result.stderr)
        self.assertEqual(len(self.standin.calls), 1)


if __name__ == "__main__":
    unittest.main()
