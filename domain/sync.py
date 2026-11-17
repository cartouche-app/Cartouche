#!/usr/bin/env python3
"""Keep cartouche.cloud's DNS records at Cloudflare as records.json says.

    CLOUDFLARE_DOMAIN_TOKEN=... python3 domain/sync.py domain/records.json [--plan]
    python3 domain/sync.py domain/records.json --resolve [--wait SECONDS]

The token is an account token of Cloudflare's limited to the zone, with
Zone > DNS > Edit and Zone > Zone > Read (README.md). The script finds the
zone by its name, reads its records, and changes, in one batch, only the
records it made itself, those whose comment starts with "domain/records.json: ":
it adds the file's records that the zone lacks, gives its own the comment, TTL
and proxy status the file says, and deletes those the file no longer has. A
record of the zone without that mark, made by hand, by Email Routing or for a
Worker's custom domain, stays as it is and is listed; a record of the file
that is the same as one of them, by type, name and content, takes it over.
Where a record of the file could not stand beside one of them, a CNAME beside
any record of its name, an SPF record beside another, it stops before
changing anything.
With --plan, it says what it would change, and changes nothing. Without the
token, it says so and changes nothing, as the telemetry's deploy does without
its secrets.

With --resolve, it asks public resolvers, Google's and Cloudflare's, over
HTTPS, for each of the file's names, and says whether they answer the file's
records; with --wait, it asks again for that long until they do. It needs no
token, and fails if a resolver still misses one of the records at the end.

What it did, in Markdown, also goes to the file GITHUB_STEP_SUMMARY names.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

API = "https://api.cloudflare.com/client/v4"
RESOLVERS = ("https://dns.google/resolve", "https://cloudflare-dns.com/dns-query")
TOKEN = "CLOUDFLARE_DOMAIN_TOKEN"
MARK = "domain/records.json: "
# Cloudflare keeps 100 characters of a record's comment on the free plan.
COMMENT_LIMIT = 100
# The types the file may hold, with their numbers in DNS answers.
TYPES = {"A": 1, "CNAME": 5, "MX": 15, "TXT": 16, "AAAA": 28, "CAA": 257}
PROXIABLE = {"A", "AAAA", "CNAME"}
AGENT = "cartouche-domain"


class Problem(Exception):
    """What the file or the zone holds that the script will not apply, or
    what Cloudflare refused."""


def unquote_txt(content: str) -> str:
    """A TXT record's text, without the quotes of its strings: Cloudflare
    keeps it as "v=spf1 -all", some resolvers answer it without them."""
    content = content.strip()
    if not content.startswith('"'):
        return content
    text, inside, escaped = [], False, False
    for char in content:
        if escaped:
            text.append(char)
            escaped = False
        elif inside and char == "\\":
            escaped = True
        elif char == '"':
            inside = not inside
        elif inside:
            text.append(char)
    return "".join(text)


def quote_txt(text: str) -> str:
    """A TXT record's text as Cloudflare keeps it: quoted strings of 255
    characters at most."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return " ".join(f'"{escaped[i:i + 255]}"' for i in range(0, max(len(escaped), 1), 255))


def normalized(kind: str, content: str) -> str:
    """The record's content as it compares: an address in its shortest form,
    a host name without its final dot, a text without its quotes."""
    if kind == "A":
        return str(ipaddress.IPv4Address(content.strip()))
    if kind == "AAAA":
        return str(ipaddress.IPv6Address(content.strip()))
    if kind in ("CNAME", "MX"):
        return content.strip().lower().rstrip(".")
    if kind == "TXT":
        return unquote_txt(content)
    return content.strip()


def host(name: str) -> str:
    return name.strip().lower().rstrip(".")


def is_spf(kind: str, content: str) -> bool:
    """An SPF record: a TXT record whose text starts with v=spf1 (RFC 7208)."""
    return kind == "TXT" and re.match(r"v=spf1(\s|$)", unquote_txt(content).strip(), re.IGNORECASE) is not None


def identity(kind: str, name: str, content: str, priority: int | None) -> tuple:
    return (kind, host(name), normalized(kind, content), priority if kind == "MX" else None)


@dataclass(frozen=True)
class Record:
    """A record of the file."""

    type: str
    name: str
    content: str
    why: str
    priority: int | None = None
    proxied: bool = False
    ttl: int = 1

    @property
    def comment(self) -> str:
        return MARK + self.why

    def key(self) -> tuple:
        return identity(self.type, self.name, self.content, self.priority)

    def settings(self) -> dict:
        """What the script keeps of a record it made, besides what makes it
        the record."""
        settings: dict = {"comment": self.comment, "ttl": self.ttl}
        if self.type in PROXIABLE:
            settings["proxied"] = self.proxied
        return settings

    def body(self) -> dict:
        """The record as Cloudflare's API takes it."""
        content = quote_txt(self.content) if self.type == "TXT" else self.content
        body = {"type": self.type, "name": self.name, "content": content, **self.settings()}
        if self.type == "MX":
            body["priority"] = self.priority
        return body

    def describe(self) -> str:
        return f"{self.type} {self.name} {self.content}"


def load(path: Path) -> tuple[str, list[Record]]:
    """The zone and its records, as the file says, once checked."""
    data = json.loads(path.read_text(encoding="utf-8"))
    zone = host(data["zone"])
    records = []
    for entry in data["records"]:
        unknown = set(entry) - {"type", "name", "content", "why", "priority", "proxied", "ttl"}
        if unknown:
            raise Problem(f"{entry.get('name')}: the file's records have no {', '.join(sorted(unknown))}")
        records.append(
            Record(
                type=entry["type"],
                name=host(entry["name"]),
                content=entry["content"],
                why=entry["why"].strip(),
                priority=entry.get("priority"),
                proxied=entry.get("proxied", False),
                ttl=entry.get("ttl", 1),
            )
        )
    check(zone, records)
    return zone, records


def check(zone: str, records: list[Record]) -> None:
    """Refuse what Cloudflare would refuse, or what would put the zone at risk."""
    seen = set()
    types_by_name: dict[str, list[str]] = {}
    for record in records:
        where = record.describe()
        if record.type not in TYPES:
            raise Problem(f"{where}: the file keeps no record of type {record.type}")
        if record.name != zone and not record.name.endswith("." + zone):
            raise Problem(f"{where}: not a name of the zone {zone}")
        if "*" in record.name:
            raise Problem(f"{where}: a wildcard would let anyone's GitHub Pages site take a name of the zone")
        if not record.why:
            raise Problem(f"{where}: the file says why each record is there")
        if len(record.comment) > COMMENT_LIMIT:
            raise Problem(f"{where}: its comment, {record.comment!r}, is longer than Cloudflare's {COMMENT_LIMIT} characters")
        if record.proxied and record.type not in PROXIABLE:
            raise Problem(f"{where}: Cloudflare proxies only A, AAAA and CNAME records")
        if (record.type == "MX") != (record.priority is not None):
            raise Problem(f"{where}: an MX record, and only one, has a priority")
        if record.ttl != 1 and not 60 <= record.ttl <= 86400:
            raise Problem(f"{where}: a TTL is 1, for Cloudflare's own, or 60 to 86400 seconds")
        try:
            record.key()
        except ValueError as error:
            raise Problem(f"{where}: {error}") from None
        if record.key() in seen:
            raise Problem(f"{where}: twice in the file")
        seen.add(record.key())
        types_by_name.setdefault(record.name, []).append(record.type)
    for name, kinds in types_by_name.items():
        if "CNAME" in kinds and len(kinds) > 1:
            raise Problem(f"{name}: a CNAME record is the only record of its name")
    for name in types_by_name:
        if sum(1 for r in records if r.name == name and is_spf(r.type, r.content)) > 1:
            raise Problem(f"{name}: one SPF record at a name, or mail servers take none of them")


class Cloudflare:
    """The few calls of Cloudflare's API the script makes."""

    def __init__(self, token: str, api: str = API, sleep=time.sleep) -> None:
        self.token = token
        self.api = api.rstrip("/")
        self.sleep = sleep

    def call(self, method: str, path: str, body: dict | None = None, query: dict | None = None) -> dict:
        url = self.api + path + ("?" + urllib.parse.urlencode(query) if query else "")
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json", "User-Agent": AGENT}
        for attempt in range(5):
            request = urllib.request.Request(url, data=data, method=method, headers=headers)
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    answer = json.load(response)
            except urllib.error.HTTPError as error:
                if error.code in (429, 500, 502, 503, 504) and attempt < 4:
                    self.sleep(2**attempt)
                    continue
                try:
                    answer = json.load(error)
                except (ValueError, OSError):
                    raise Problem(f"Cloudflare answered {method} {path} with HTTP {error.code}") from None
            except (urllib.error.URLError, TimeoutError) as error:
                if attempt < 4:
                    self.sleep(2**attempt)
                    continue
                raise Problem(f"Cloudflare's API does not answer: {getattr(error, 'reason', error)}") from None
            if not answer.get("success"):
                errors = "; ".join(f"{e.get('code')} {e.get('message')}" for e in answer.get("errors") or []) or "no reason given"
                raise Problem(f"Cloudflare refused {method} {path}: {errors}")
            return answer
        raise Problem(f"Cloudflare's API does not answer {method} {path}")

    def zone(self, name: str) -> dict:
        zones = self.call("GET", "/zones", query={"name": name})["result"]
        if not zones:
            raise Problem(f"the token sees no zone {name}: it must be limited to that zone, with Zone > Zone > Read and Zone > DNS > Edit")
        return zones[0]

    def records(self, zone_id: str) -> list[dict]:
        records: list[dict] = []
        page = 1
        while True:
            answer = self.call("GET", f"/zones/{zone_id}/dns_records", query={"page": page, "per_page": 100})
            records += answer["result"]
            if page >= (answer.get("result_info") or {}).get("total_pages", 1):
                return records
            page += 1

    def batch(self, zone_id: str, changes: dict) -> None:
        self.call("POST", f"/zones/{zone_id}/dns_records/batch", body=changes)


def ours(record: dict) -> bool:
    return (record.get("comment") or "").startswith(MARK)


def same_record(have: dict, want: Record) -> bool:
    try:
        return identity(have["type"], have["name"], have["content"], have.get("priority")) == want.key()
    except ValueError:
        return False


@dataclass
class Plan:
    """What the zone must change to be as the file says."""

    posts: list[Record] = field(default_factory=list)
    patches: list[tuple[dict, Record]] = field(default_factory=list)
    deletes: list[dict] = field(default_factory=list)
    same: list[Record] = field(default_factory=list)
    others: list[dict] = field(default_factory=list)

    def empty(self) -> bool:
        return not (self.posts or self.patches or self.deletes)

    def changes(self) -> dict:
        """The batch that makes them, which Cloudflare runs in one
        transaction: its deletes, then its patches, then its posts."""
        changes: dict = {}
        if self.deletes:
            changes["deletes"] = [{"id": record["id"]} for record in self.deletes]
        if self.patches:
            changes["patches"] = [{"id": have["id"], **want.settings()} for have, want in self.patches]
        if self.posts:
            changes["posts"] = [want.body() for want in self.posts]
        return changes


def plan(records: list[Record], existing: list[dict]) -> Plan:
    result = Plan()
    taken: set[str] = set()
    for want in records:
        # One of the script's own first, then one made by hand, which the
        # file's record takes over.
        candidates = sorted((r for r in existing if r["id"] not in taken and same_record(r, want)), key=lambda r: not ours(r))
        if not candidates:
            result.posts.append(want)
            continue
        have = candidates[0]
        taken.add(have["id"])
        if any(have.get(key) != value for key, value in want.settings().items()):
            result.patches.append((have, want))
        else:
            result.same.append(want)
    for record in existing:
        if record["id"] not in taken:
            (result.deletes if ours(record) else result.others).append(record)
    # A CNAME stands alone at its name: beside a record made by hand, the
    # whole batch would fail.
    for want in result.posts:
        for other in result.others:
            if host(other["name"]) == want.name and "CNAME" in (want.type, other["type"]):
                raise Problem(
                    f"{want.name} has a {other['type']} record that is not the file's, and a CNAME is the only record "
                    "of its name: delete it in Cloudflare's dashboard, or put it in the file"
                )
    # One SPF record at a name: beside another, as Email Routing keeps its own
    # at the apex, mail servers would take neither.
    for want in records:
        for other in result.others:
            if host(other["name"]) == want.name and is_spf(want.type, want.content) and is_spf(other["type"], other["content"]):
                raise Problem(
                    f"{want.name} has an SPF record that is not the file's, {unquote_txt(other['content'])!r}, and a name has "
                    "only one, or mail servers take neither: take the file's out, or delete the other in Cloudflare's dashboard"
                )
    return result


def table(rows: list[tuple[str, ...]], header: tuple[str, ...]) -> list[str]:
    lines = ["| " + " | ".join(header) + " |", "|" + " --- |" * len(header)]
    lines += ["| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |" for row in rows]
    return lines


def report(zone: dict, result: Plan, dry: bool) -> list[str]:
    verbs = ("would add", "would update", "would delete") if dry else ("added", "updated", "deleted")
    rows = [(verbs[0], r.type, r.name, r.content, r.why) for r in result.posts]
    rows += [(verbs[1], want.type, want.name, want.content, want.why) for have, want in result.patches]
    rows += [(verbs[2], r["type"], r["name"], r["content"], (r.get("comment") or "")[len(MARK):]) for r in result.deletes]
    rows += [("unchanged", r.type, r.name, r.content, r.why) for r in result.same]
    lines = [f"## {zone['name']}", ""]
    servers = ", ".join(zone.get("name_servers") or [])
    lines += [f"Zone {zone.get('status', '?')} at Cloudflare, served by {servers or 'its name servers'}.", ""]
    lines += table(rows, ("", "Type", "Name", "Content", "Why"))
    lines.append("")
    if result.others:
        lines += ["Left as they are, not the file's records:", ""]
        lines += table([(r["type"], r["name"], r["content"], r.get("comment") or "") for r in result.others], ("Type", "Name", "Content", "Comment"))
    else:
        lines.append("The zone has no record but the file's.")
    return lines


def sync(zone_name: str, records: list[Record], token: str, dry: bool, api: str = API) -> list[str]:
    cloudflare = Cloudflare(token, api)
    zone = cloudflare.zone(zone_name)
    if zone.get("status") != "active":
        raise Problem(f"the zone {zone_name} is {zone.get('status')} at Cloudflare, not active: its name servers must be Cloudflare's at the registrar")
    result = plan(records, cloudflare.records(zone["id"]))
    lines = report(zone, result, dry)
    if dry or result.empty():
        lines += ["", "Nothing changed." if result.empty() else "Nothing changed: a plan only."]
        return lines
    cloudflare.batch(zone["id"], result.changes())
    after = plan(records, cloudflare.records(zone["id"]))
    if not after.empty():
        raise Problem(f"the zone {zone_name} still differs from the file after the batch")
    lines += ["", f"The zone has the file's {len(records)} records."]
    return lines


def ask(resolver: str, name: str, kind: str) -> set[str] | None:
    """What a resolver answers for a name and a type, over HTTPS (DNS over
    HTTPS's JSON form, as Google and Cloudflare serve it), or None if it does
    not answer."""
    url = resolver + "?" + urllib.parse.urlencode({"name": name, "type": kind})
    request = urllib.request.Request(url, headers={"Accept": "application/dns-json", "User-Agent": AGENT})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            answer = json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return None
    if answer.get("Status") not in (0, 3):
        return None
    found = set()
    for entry in answer.get("Answer") or []:
        if entry.get("type") != TYPES[kind] or host(entry.get("name", "")) != name:
            continue
        data = entry.get("data", "")
        if kind == "MX":
            priority, _, target = data.partition(" ")
            found.add(f"{priority} {normalized('MX', target)}")
        else:
            try:
                found.add(normalized(kind, data))
            except ValueError:
                found.add(data)
    return found


def expected(record: Record) -> str:
    content = normalized(record.type, record.content)
    return f"{record.priority} {content}" if record.type == "MX" else content


def resolve(records: list[Record], resolvers=RESOLVERS, wait: int = 0, sleep=time.sleep, clock=time.monotonic) -> tuple[int, list[str]]:
    wanted: dict[tuple[str, str], set[str]] = {}
    for record in records:
        wanted.setdefault((record.name, record.type), set()).add(expected(record))
    deadline = clock() + wait
    while True:
        rows, missing = [], 0
        for (name, kind), contents in wanted.items():
            for resolver in resolvers:
                answers = ask(resolver, name, kind)
                where = urllib.parse.urlsplit(resolver).hostname or resolver
                if answers is None:
                    state, missing = "no answer", missing + 1
                elif contents <= answers:
                    extra = answers - contents
                    state = "as the file says" + (f", and also {', '.join(sorted(extra))}" if extra else "")
                else:
                    state, missing = "still missing " + ", ".join(sorted(contents - answers)), missing + 1
                rows.append((name, kind, where, state))
        if not missing or clock() >= deadline:
            break
        sleep(min(30, max(1, deadline - clock())))
    lines = ["## What public resolvers answer", ""] + table(rows, ("Name", "Type", "Resolver", "Answer"))
    lines += ["", "Every resolver answers the file's records." if not missing else f"{missing} answers still miss the file's records."]
    return (1 if missing else 0), lines


def main(argv: list[str] | None = None, environ=os.environ) -> int:
    parser = argparse.ArgumentParser(description="Keep cartouche.cloud's DNS records at Cloudflare as records.json says.")
    parser.add_argument("records", type=Path, help="domain/records.json")
    parser.add_argument("--plan", action="store_true", help="say what would change, and change nothing")
    parser.add_argument("--resolve", action="store_true", help="ask public resolvers whether they answer the file's records")
    parser.add_argument("--wait", type=int, default=0, help="with --resolve, ask again for so many seconds until they do")
    args = parser.parse_args(argv)
    status = 0
    try:
        zone, records = load(args.records)
        if args.resolve:
            resolvers = environ.get("DOMAIN_RESOLVERS", " ".join(RESOLVERS)).split()
            status, lines = resolve(records, resolvers, args.wait)
        elif not environ.get(TOKEN):
            lines = [f"## {zone}", "", f"Nothing changed: the environment cloudflare has no secret {TOKEN} (domain/README.md)."]
            print(f"::notice::{TOKEN} is not set: nothing changed")
        else:
            lines = sync(zone, records, environ[TOKEN], args.plan, environ.get("CLOUDFLARE_API", API))
    except Problem as problem:
        print(f"::error::{problem}")
        lines = [f"Nothing more changed: {problem}."]
        status = 1
    text = "\n".join(lines) + "\n"
    print(text)
    if environ.get("GITHUB_STEP_SUMMARY"):
        with open(environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(text)
    return status


if __name__ == "__main__":
    sys.exit(main())
