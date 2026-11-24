"""A stand-in for the part of Cloudflare's API that telemetry/deploy.sh,
telemetry/move.sh and telemetry/sheets.py call, for their tests. It runs the
SQL it is sent on SQLite, as D1 would: a script as it comes, or one
statement with its parameters, whose rows it answers. It has two accounts:
the one of the zone cartouche.cloud, which TOKEN reaches, and the one the
telemetry started in, FORMER_ACCOUNT, which FORMER_TOKEN reaches, each with
its databases, Workers and workers.dev subdomain; it exports a database as
D1 does, as a file of SQL at a signed address, and imports one sent to the
address it gives. Under /github, it answers as GitHub's API does for a
repository, to the deploy's check of the problems' repository; under
/workers.dev, as each Worker's address does, to the checks of the server,
the dashboard and the relay.
"""

import hashlib

import email
import email.policy
import json
import os
import re
import sqlite3
import threading
from collections import namedtuple
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ACCOUNT = "0123456789abcdef0123456789abcdef"
TOKEN = "a-token-for-the-tests"
PREFIX = f"/client/v4/accounts/{ACCOUNT}"
ZONE = "cartouche.cloud"
ZONE_ID = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"
# The account the telemetry started in, Ad's own, and its token.
FORMER_ACCOUNT = "fedcba9876543210fedcba9876543210"
FORMER_TOKEN = "the-former-accounts-token-for-the-tests"
GITHUB_TOKEN = "github_pat_for_the_tests"
# An answer sent as it is, not as JSON: its headers and its bytes.
Raw = namedtuple("Raw", "headers body")
# Where Cloudflare Access sends a request it has not signed in.
ACCESS_SIGN_IN = "https://team.cloudflareaccess.com/cdn-cgi/access/login/{host}?kid=0&redirect_url=%2F"


class Account:
    """What one account holds: its databases, all on its one SQLite, its
    Workers, their workers.dev addresses, daily runs and domains."""

    def __init__(self, token):
        self.token = token
        self.databases = []
        self.subdomain = None
        self._sql = None
        self.scripts = {}
        # Each script's workers.dev address and daily run: name -> body.
        self.enabled = {}
        self.schedules = {}
        self.domains = []
        # What was deleted, as (kind, name).
        self.deleted = []

    @property
    def sql(self):
        """Its SQLite, made when first asked for."""
        if self._sql is None:
            self._sql = sqlite3.connect(":memory:", check_same_thread=False)
            self._sql.row_factory = sqlite3.Row
        return self._sql


class Cloudflare:
    """What the stand-in holds, and every call it answered."""

    def __init__(self):
        self.calls = []
        self.main = Account(TOKEN)
        self.former = Account(FORMER_TOKEN)
        self.accounts = {ACCOUNT: self.main, FORMER_ACCOUNT: self.former}
        self.queries = []
        # The files of SQL D1 exported or was sent, by name.
        self.files = {}
        self.exports = 0
        self.imports = []
        # Set by a test, to run once an export has taken its copy, with the account.
        self.while_exporting = None
        # Set by a test: (method, path in the account) -> the answer.
        self.refusals = {}
        # GitHub's repositories the token can read: name -> private.
        self.repositories = {}
        # Repositories moved to another owner: old name -> new name. GitHub
        # answers the old name with a redirect to the repository's ID.
        self.moved = {}
        # What each Worker's workers.dev address answers: the server its
        # name, the dashboard its closed page until Access protects it.
        self.workers_dev = {
            "cartouche-telemetry": (200, Raw({"Content-Type": "text/plain"}, b"Cartouche telemetry\n")),
            "cartouche-dashboard": (403, Raw({"Content-Type": "text/html"}, b"<h1>Ce tableau de bord est ferm\xc3\xa9</h1>")),
        }

    # The account of the zone, as the deploy's tests knew it.
    databases = property(lambda self: self.main.databases)
    subdomain = property(lambda self: self.main.subdomain)
    sql = property(lambda self: self.main.sql)
    scripts = property(lambda self: self.main.scripts)
    enabled = property(lambda self: self.main.enabled)
    schedules = property(lambda self: self.main.schedules)
    domains = property(lambda self: self.main.domains)

    def behind_access(self, name):
        """The answer of a Worker Cloudflare Access protects: its sign-in."""
        self.workers_dev[name] = (302, Raw({"Location": ACCESS_SIGN_IN.format(host=f"{name}.workers.dev")}, b""))

    def answer(self, method, path, query, headers, body):
        self.calls.append((method, path))
        if path.startswith("/workers.dev/"):
            return self.workers_dev.get(path[len("/workers.dev/"):].strip("/"), (404, Raw({}, b"")))
        if path.startswith("/signed/"):
            name = path[len("/signed/"):]
            if method == "GET" and name in self.files:
                return 200, Raw({"Content-Type": "application/sql"}, self.files[name])
            if method == "PUT" and name.startswith("upload-"):
                self.files[name] = body
                return 200, Raw({"ETag": f'"{hashlib.md5(body).hexdigest()}"'}, b"")
            return 404, Raw({}, b"")
        if path.startswith("/github/repos/") or path.startswith("/github/repositories/"):
            if headers.get("Authorization") != f"Bearer {GITHUB_TOKEN}":
                return 401, {"message": "Bad credentials"}
            # A repository's ID: its place among the repositories.
            names = list(self.repositories)
            if path.startswith("/github/repositories/"):
                number = path[len("/github/repositories/"):]
                name = names[int(number)] if number.isdigit() and int(number) < len(names) else None
            else:
                name = path[len("/github/repos/"):]
            if method == "GET" and self.moved.get(name) in self.repositories:
                place = f"/github/repositories/{names.index(self.moved[name])}"
                return 301, Raw({"Content-Type": "application/json", "Location": place},
                                json.dumps({"message": "Moved Permanently", "url": place}).encode())
            if method != "GET" or name not in self.repositories:
                return 404, {"message": "Not Found"}
            return 200, {"full_name": name, "private": self.repositories[name]}
        authorization = headers.get("Authorization")
        if (method, path) == ("GET", "/client/v4/zones"):
            if authorization not in (f"Bearer {TOKEN}", f"Bearer {FORMER_TOKEN}"):
                return 403, {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}
            # The zone is in the account the domain's token reaches.
            seen = authorization == f"Bearer {TOKEN}" and query.get("name", [""])[0] == ZONE
            zones = [{"id": ZONE_ID, "name": ZONE, "account": {"id": ACCOUNT}}] if seen else []
            return 200, {"success": True, "result": zones}
        match = re.fullmatch(r"/client/v4/accounts/([^/]+)(/.*)", path)
        account = self.accounts.get(match.group(1)) if match else None
        if account is None or authorization != f"Bearer {account.token}":
            return 403, {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}]}
        path = match.group(2)
        return self.account_answer(account, method, path, query, headers, body)

    def account_answer(self, account, method, path, query, headers, body):
        gone = (404, {"success": False, "errors": [{"code": 10007, "message": "Not found"}]})
        if (method, path) in self.refusals:
            return self.refusals[(method, path)]
        if (method, path) == ("GET", "/d1/database"):
            name = query.get("name", [""])[0]
            return 200, {"success": True, "result": [d for d in account.databases if name in d["name"]]}
        if (method, path) == ("POST", "/d1/database"):
            request = json.loads(body)
            prefix = "d1-" if account is self.main else "former-d1-"
            database = {"uuid": f"{prefix}{len(account.databases)}", **request}
            account.databases.append(database)
            return 200, {"success": True, "result": database}
        match = re.fullmatch(r"/d1/database/([^/]+)(/query|/export|/import)?", path)
        if match and match.group(1) not in [d["uuid"] for d in account.databases]:
            return 404, {"success": False, "errors": [{"code": 7404, "message": "No such database"}]}
        if method == "DELETE" and match and not match.group(2):
            account.databases[:] = [d for d in account.databases if d["uuid"] != match.group(1)]
            account.deleted.append(("d1", match.group(1)))
            return 200, {"success": True, "result": None}
        if method == "POST" and match and match.group(2) == "/query":
            request = json.loads(body)
            self.last_sql = request["sql"]
            if "params" in request:
                self.queries.append((request["sql"], request["params"]))
                rows = [dict(row) for row in account.sql.execute(request["sql"], request["params"])]
            else:
                account.sql.executescript(request["sql"])
                rows = []
            return 200, {"success": True, "result": [{"success": True, "results": rows, "meta": {}}]}
        if method == "POST" and match and match.group(2) == "/export":
            return self.export(account, match.group(1), json.loads(body), headers)
        if method == "POST" and match and match.group(2) == "/import":
            return self.import_(account, match.group(1), json.loads(body), headers)
        if (method, path) == ("GET", "/workers/subdomain"):
            if account.subdomain is None:
                return 404, {"success": False, "errors": [{"code": 10007, "message": "This account has no subdomain"}]}
            return 200, {"success": True, "result": {"subdomain": account.subdomain}}
        if (method, path) == ("PUT", "/workers/subdomain"):
            account.subdomain = json.loads(body)["subdomain"]
            return 200, {"success": True, "result": {"subdomain": account.subdomain}}
        if (method, path) == ("GET", "/workers/scripts"):
            return 200, {"success": True, "result": [{"id": name} for name in account.scripts]}
        if (method, path) == ("GET", "/workers/domains"):
            hostname = query.get("hostname", [None])[0]
            return 200, {"success": True, "result": [d for d in account.domains if hostname in (None, d["hostname"])]}
        if (method, path) == ("PUT", "/workers/domains"):
            domain = {"id": f"domain-{len(account.domains)}", **json.loads(body)}
            account.domains.append(domain)
            return 200, {"success": True, "result": domain}
        match = re.fullmatch(r"/workers/scripts/([^/]+)/settings", path)
        if method == "GET" and match:
            if match.group(1) not in account.scripts:
                return gone
            return 200, {"success": True, "result": {"bindings": [
                {key: value for key, value in binding.items() if key != "text"}
                for binding in account.scripts[match.group(1)]["metadata"]["bindings"]]}}
        match = re.fullmatch(r"/workers/scripts/([^/]+)", path)
        if method == "DELETE" and match:
            if match.group(1) not in account.scripts:
                return gone
            del account.scripts[match.group(1)]
            account.enabled.pop(match.group(1), None)
            account.schedules.pop(match.group(1), None)
            account.deleted.append(("worker", match.group(1)))
            return 200, {"success": True, "result": None}
        if method == "PUT" and match:
            message = email.message_from_bytes(
                b"Content-Type: " + headers["Content-Type"].encode() + b"\r\n\r\n" + body, policy=email.policy.HTTP)
            parts = {part.get_param("name", header="content-disposition"): part for part in message.iter_parts()}
            account.scripts[match.group(1)] = {
                "metadata": json.loads(parts["metadata"].get_content()),
                "module type": parts["worker.js"].get_content_type(),
                "module": parts["worker.js"].get_payload(decode=True),
                # Every module, by its name: its type and its bytes.
                "modules": {name: (part.get_content_type(), part.get_payload(decode=True))
                            for name, part in parts.items() if name != "metadata"},
            }
            return 200, {"success": True, "result": {"id": match.group(1)}}
        match = re.fullmatch(r"/workers/scripts/([^/]+)/subdomain", path)
        if method == "POST" and match:
            account.enabled[match.group(1)] = json.loads(body)
            return 200, {"success": True, "result": account.enabled[match.group(1)]}
        match = re.fullmatch(r"/workers/scripts/([^/]+)/schedules", path)
        if method == "PUT" and match:
            account.schedules[match.group(1)] = json.loads(body)
            return 200, {"success": True, "result": {"schedules": account.schedules[match.group(1)]}}
        return 404, {"success": False, "errors": [{"code": 7003, "message": f"No route for {method} {path}"}]}

    def signed(self, headers, name):
        return f"http://{headers['Host']}/signed/{name}"

    def export(self, account, uuid, request, headers):
        """D1's export, as its API polls it: the first call starts it, the
        next, with its bookmark, gives the file's signed address. Only the
        rows of the tables asked, when the options leave the schema out."""
        options = request.get("dump_options", {})
        if request.get("output_format") != "polling":
            return 400, {"success": False, "errors": [{"code": 7400, "message": "output_format"}]}
        if "current_bookmark" not in request:
            self.exports += 1
            return 200, {"success": True, "result": {"at_bookmark": f"export-{self.exports}", "messages": ["Generating"],
                                                    "type": "export"}}
        tables = options.get("tables") or None
        lines = []
        for line in account.sql.iterdump():
            insert = re.match(r'INSERT INTO "([^"]+)"', line)
            if insert and (tables is None or insert.group(1) in tables):
                lines.append(line)
            elif not insert and not options.get("no_schema") and line.startswith("CREATE TABLE"):
                lines.append(line)
        name = f"export-{uuid}-{request['current_bookmark']}.sql"
        self.files[name] = ("PRAGMA defer_foreign_keys=TRUE;\n" + "\n".join(lines) + "\n").encode()
        # What happens once D1 has taken its copy.
        if self.while_exporting:
            self.while_exporting(account)
        return 200, {"success": True, "result": {"at_bookmark": request["current_bookmark"], "status": "complete",
                                                "success": True, "type": "export",
                                                "result": {"filename": name, "signed_url": self.signed(headers, name)}}}

    def import_(self, account, uuid, request, headers):
        """D1's import, as its API goes: init gives an address to put the
        file at, ingest runs it once its md5 is the one announced, poll says
        it is complete."""
        action = request.get("action")
        if action == "init":
            name = f"upload-{request['etag']}"
            return 200, {"success": True, "result": {"upload_url": self.signed(headers, name), "filename": name}}
        if action == "ingest":
            sql = self.files.get(request.get("filename"))
            if sql is None or hashlib.md5(sql).hexdigest() != request.get("etag"):
                return 200, {"success": True, "result": {"success": False, "status": "error", "error": "Bad etag"}}
            account.sql.executescript(sql.decode())
            self.imports.append((uuid, sql.decode()))
            return 200, {"success": True, "result": {"at_bookmark": f"import-{len(self.imports)}", "success": False,
                                                    "messages": ["Starting import"], "type": "import"}}
        if action == "poll":
            return 200, {"success": True, "result": {"at_bookmark": request.get("current_bookmark"), "success": True,
                                                    "status": "complete", "type": "import",
                                                    "result": {"num_queries": 1}}}
        return 400, {"success": False, "errors": [{"code": 7400, "message": "action"}]}


def serve(cloudflare):
    """The stand-in on a port of its own, until the server is shut down."""

    class Handler(BaseHTTPRequestHandler):
        def handle_one(self):
            url = urlparse(self.path)
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            status, answer = cloudflare.answer(self.command, url.path, parse_qs(url.query), self.headers, body)
            headers, data = answer if isinstance(answer, Raw) else ({"Content-Type": "application/json"}, json.dumps(answer).encode())
            self.send_response(status)
            for name, value in headers.items():
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_PUT = do_DELETE = handle_one

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def environment(server, **values):
    """The environment of a run against the stand-in: no proxy, and nothing
    of the job's own summary or outputs unless given."""
    kept = {key: value for key, value in os.environ.items()
            if key.lower() not in ("http_proxy", "https_proxy", "all_proxy", "github_step_summary", "github_output")}
    kept.update(CLOUDFLARE_API=f"http://127.0.0.1:{server.server_port}/client/v4",
                TELEMETRY_CHECK_BASE=f"http://127.0.0.1:{server.server_port}/workers.dev/", NO_PROXY="127.0.0.1", **values)
    return kept
