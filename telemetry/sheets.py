#!/usr/bin/env python3
"""Sums up the game sessions Cartouche's telemetry received into the results
of the game sheets in catalog/games/, for the Game measurements workflow
(.github/workflows/measurements.yml), each week.

For each game of nxnative's list and each sheet, and each iPhone model at
least three iPhones played the game on in the last 28 days, one result: how
the game ran, as the median of each iPhone's own median so that each iPhone
counts once however much it played, the most memory any of them used, how its
sessions ended, and a status that follows from them
(telemetry/README.md#game-sheets). A model fewer iPhones played the game on
gets no result: every figure on the sheets comes from three iPhones or more
(docs/privacy.md). The results testers wrote stay as they are; a measured
result is replaced by the model's new one, and kept while the model has none.
A game of nxnative's list without a sheet gets one with its first result,
which says what the game needs from nxnative's own needs and from what was
measured, never from a guess; and any sheet comes to need Increased Memory
Limit once its peak does not fit in the memory an app has without it.

It reads the D1 database through Cloudflare's API, with the secrets
CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID, and does nothing without
them. It writes the sheets that changed, and the new ones, into --out, says
what it found in the job's summary, and sets the job's output changed to true
or false. With --take, the workflow's job that commits them, which holds no
secret, checks the sheets a run wrote and copies them into the catalog: each
must be a sheet the catalog has, or a new one of a game of nxnative's list,
named by its title ID.

    python3 telemetry/sheets.py --catalog catalog --out build/sheets
    python3 telemetry/sheets.py --catalog catalog --take build/sheets

Python's standard library only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

DATABASE = "cartouche-telemetry"
API = "https://api.cloudflare.com/client/v4"
# The models a sheet's result may name (catalog/schema/game.schema.json).
DEVICE = re.compile(r"^(iPhone|iPad)[0-9]+,[0-9]+$")
# A sheet's file, named by its game's title ID.
SHEET_FILE = re.compile(r"^[0-9A-F]{16}\.json$")

# A result needs this many iPhones of the model, and so does each of its
# figures.
MIN_IPHONES = 3
WINDOW_DAYS = 28
PAGE = 2000

# How a session ended badly (CartoucheGameLog.swift): it crashed, it never
# drew a frame, or iOS stopped it for its memory. "unknown" is a game the
# player closed as much as one iOS stopped without a word, and "quit" one
# the player quit behind the console, so neither counts.
ENDED_BADLY = {"crash": "crash", "memory-likely": "out of memory", "boot-failed": "did not start"}
# The same, as a result's measured.endedBadly counts them, which Cartouche
# says in the player's language (CartoucheMeasuredNote.swift).
ENDED_BADLY_KEYS = {"crash": "crashes", "memory-likely": "outOfMemory", "boot-failed": "didNotStart"}

# The reading of nxnative's log (CartoucheGameLogReader.version, in a
# report's reader) from which a session's slowest 5% counts. nxnative times
# each stretch of 300 frames by the clock, so before it a stretch that held a
# pause, the game left behind the console or Cartouche in the background,
# counted at the rate that pause brought it to: one pause of a minute took
# the slowest 5% of a session of twenty minutes under 5 fps.
SLOWEST_READER = 2

# The status of a model's result:
#   does-not-run          no session drew a frame;
#   boots                 half of the sessions or more ended badly;
#   playable-with-issues  a tenth of them or more ended badly, or the median
#                         frame rate is under 90 % of the rate the game asks
#                         for, or that of the slowest 5 % of the time under
#                         75 % of it;
#   playable              otherwise.
BOOTS = 0.5
ISSUES = 0.1
ISSUES_FPS = 0.9
ISSUES_SLOWEST = 0.75

# What a new sheet says its game needs (requirements), from nxnative's own
# needs and from what was measured, never from a guess:
#   minimumIOS            the iOS every game nxnative builds needs: its iOS
#                         app is built for iOS 26 and later, for Metal 4
#                         (dm/ios/project.yml), as docs/architecture.md
#                         says. An iPhone that played the game says that it
#                         runs on its iOS, never that it would not on an
#                         older one;
#   bcTextureCompression  true: nxnative refuses for every game a GPU that
#                         reads no BC-compressed texture (dm/ios/Sources/
#                         main.m, docs/decisions.md, 67);
#   increasedMemoryLimit  whether its peak does not fit in the memory an app
#                         has without the capability (needs_iml), on any
#                         sheet, a new one or not.
MINIMUM_IOS = "26.0"

# The sessions one day received, a page at a time, with D1's parameters
# as text. A session sent again because its log grew is the same session
# with a higher seq.
SESSIONS = (
    "SELECT id, install, session, seq, day, device, ios, game, "
    "json_extract(body, '$.nxnative') AS nxnative, "
    "json_extract(body, '$.frames') AS frames, "
    "json_extract(body, '$.fps.median') AS fps, "
    "json_extract(body, '$.fps.low5') AS slowest, "
    "json_extract(body, '$.targetFps') AS target, "
    "json_extract(body, '$.stutters.perMinute') AS stutters, "
    "json_extract(body, '$.memory.peakMiB') AS peak, "
    "json_extract(body, '$.end.kind') AS ending, "
    "json_extract(body, '$.reader') AS reader "
    f"FROM reports WHERE kind = 'session' AND day = ?1 AND id > ?2 ORDER BY id LIMIT {PAGE}"
)


class Refused(Exception):
    """Cloudflare refused a call, or could not be reached."""


class Cloudflare:
    def __init__(self, account: str, token: str, base: str = API):
        self.base = f"{base}/accounts/{account}"
        self.token = token

    def call(self, method: str, path: str, body=None, query=None):
        url = self.base + path + ("?" + urllib.parse.urlencode(query) if query else "")
        request = urllib.request.Request(
            url, method=method, data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                answer = json.load(response)
        except urllib.error.HTTPError as error:
            try:
                answer = json.load(error)
            except ValueError:
                answer = {"errors": [{"code": error.code, "message": error.reason}]}
        except (urllib.error.URLError, OSError) as error:
            raise Refused(f"Cloudflare could not be reached for {method} {path}: {error}") from error
        if not isinstance(answer, dict) or answer.get("success") is not True:
            errors = answer.get("errors") if isinstance(answer, dict) else None
            words = "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errors or []) or "no reason given"
            raise Refused(f"Cloudflare refused {method} {path}: {words}")
        return answer.get("result")

    def database(self, name: str) -> str:
        found = [d for d in self.call("GET", "/d1/database", query={"name": name}) or [] if d.get("name") == name]
        if not found:
            raise Refused(f"there is no D1 database {name}: the telemetry server is not deployed")
        return found[0]["uuid"]

    def query(self, database: str, sql: str, params: list) -> list[dict]:
        return self.call("POST", f"/d1/database/{database}/query", {"sql": sql, "params": params})[0]["results"]


def read_sessions(cloudflare: Cloudflare, database: str, first: dt.date, last: dt.date) -> list[dict]:
    """The sessions received from first to last, each once, at its highest seq."""
    sessions: dict[tuple[str, str], dict] = {}
    day = first
    while day <= last:
        after = ""
        while True:
            rows = cloudflare.query(database, SESSIONS, [day.isoformat(), after])
            for row in rows:
                key = (row["install"], row["session"])
                if key not in sessions or (row["seq"] or 0) > (sessions[key]["seq"] or 0):
                    sessions[key] = row
            if len(rows) < PAGE:
                break
            after = rows[-1]["id"]
        day += dt.timedelta(days=1)
    return list(sessions.values())


# MARK: Figures


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split(".") if part.isdigit())


def number(value) -> float | None:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def figure_of(session: dict, key: str) -> float | None:
    """The session's figure KEY: its slowest 5% only from SLOWEST_READER on."""
    if key == "slowest" and (number(session.get("reader")) or 1) < SLOWEST_READER:
        return None
    return number(session.get(key))


def drew_frames(session: dict) -> bool:
    """Whether the session got into the game: it drew a frame."""
    return (number(session.get("frames")) or 0) > 0 or number(session.get("fps")) is not None


def median(values: list[float]) -> float | None:
    """The median, when enough iPhones gave a value."""
    return statistics.median(values) if len(values) >= MIN_IPHONES else None


def highest(values: list[float]) -> float | None:
    """The highest, when enough iPhones gave a value."""
    return max(values) if len(values) >= MIN_IPHONES else None


def rounded(value: float | None, digits: int = 1) -> float | int | None:
    if value is None:
        return None
    value = round(value, digits)
    return int(value) if value == int(value) else value


def shown(value: float) -> str:
    return f"{rounded(value):g}"


@dataclass
class IPhone:
    """One iPhone's sessions of the game."""

    sessions: list[dict]

    def values(self, key: str) -> list[float]:
        return [v for v in (figure_of(s, key) for s in self.sessions) if v is not None]

    def median(self, key: str) -> float | None:
        values = self.values(key)
        return statistics.median(values) if values else None

    @property
    def peak(self) -> float | None:
        """Its highest memory peak, of the sessions that drew a frame: one
        that ended before its first frame had loaded little of the game,
        and says nothing of what it needs. Cartouche reads a sheet's peak to
        choose where a game starts (docs/decisions.md, 48)."""
        values = [v for v in (number(s.get("peak")) for s in self.sessions if drew_frames(s)) if v is not None]
        return max(values) if values else None

    @property
    def ios(self) -> str:
        return max(self.sessions, key=lambda s: (s["day"], s["seq"] or 0))["ios"]


@dataclass
class Result:
    """A model's sessions of a game, summed up."""

    device: str
    iphones: list[IPhone]

    @property
    def sessions(self) -> list[dict]:
        return [s for phone in self.iphones for s in phone.sessions]

    def figure(self, key: str) -> float | None:
        return median([v for v in (phone.median(key) for phone in self.iphones) if v is not None])

    @property
    def target(self) -> int | None:
        targets = Counter(int(s["target"]) for s in self.sessions if number(s.get("target")))
        return max(targets.items(), key=lambda item: (item[1], item[0]))[0] if targets else None

    @property
    def ended_badly(self) -> Counter:
        return Counter(s["ending"] for s in self.sessions if s.get("ending") in ENDED_BADLY)

    @property
    def played(self) -> int:
        return sum(1 for s in self.sessions if drew_frames(s))

    @property
    def status(self) -> str:
        sessions = len(self.sessions)
        badly = sum(self.ended_badly.values()) / sessions
        target, fps, slowest = self.target, self.figure("fps"), self.figure("slowest")
        if self.played == 0:
            return "does-not-run"
        if badly >= BOOTS:
            return "boots"
        if badly >= ISSUES:
            return "playable-with-issues"
        if target and fps is not None and fps < ISSUES_FPS * target:
            return "playable-with-issues"
        if target and slowest is not None and slowest < ISSUES_SLOWEST * target:
            return "playable-with-issues"
        return "playable"

    @property
    def ios(self) -> str:
        versions = Counter(phone.ios for phone in self.iphones)
        return max(versions.items(), key=lambda item: (item[1], version(item[0])))[0]

    @property
    def builds(self) -> tuple[str, int] | None:
        """The nxnative commit most sessions reported, and how many other
        commits some did; None when none reported one."""
        commits = Counter(s["nxnative"][:12] for s in self.sessions if s.get("nxnative"))
        if not commits:
            return None
        commit = max(commits.items(), key=lambda item: (item[1], item[0]))[0]
        return commit, len(commits) - 1

    @property
    def engine(self) -> str:
        if self.builds is None:
            return "nxnative, its build not reported"
        commit, others = self.builds
        if not others:
            return f"nxnative {commit}"
        return f"nxnative {commit} and {others} other build{'s' if others > 1 else ''}"

    def note(self) -> str:
        sessions = self.sessions
        days = sorted(s["day"] for s in sessions)
        # An iPad's model counts iPads, as Cartouche says it.
        devices = "iPads" if self.device.startswith("iPad") else "iPhones"
        lead = (f"Measured by Cartouche on {len(self.iphones)} {devices}, "
                f"{len(sessions)} sessions from {days[0]} to {days[-1]}")
        running = []
        fps, slowest, stutters, target = self.figure("fps"), self.figure("slowest"), self.figure("stutters"), self.target
        if fps is not None:
            running.append(f"{shown(fps)} fps" + (f" for {target}" if target else "") + " (median)")
        if slowest is not None:
            running.append(f"{shown(slowest)} fps in the slowest 5% of the time")
        if stutters is not None:
            running.append(f"{shown(stutters)} stutters a minute")
        badly = self.ended_badly
        count = sum(badly.values())
        if count:
            kinds = ", ".join(
                f"{n} {'crash' + ('es' if n > 1 else '') if kind == 'crash' else ENDED_BADLY[kind]}"
                for kind, n in sorted(badly.items(), key=lambda item: (-item[1], item[0])))
            ending = f"{count} session{'s' if count > 1 else ''} ended badly: {kinds}."
        else:
            ending = "None ended badly."
        # The first parts that fit in the 300 letters a note may have.
        while running:
            text = f"{lead}: {', '.join(running)}. {ending}"
            if len(text) <= 300:
                return text
            running.pop()
        return f"{lead}. {ending}"[:300]

    def entry(self) -> dict:
        sessions = self.sessions
        days = sorted(s["day"] for s in sessions)
        entry = {
            "device": self.device,
            "iOS": self.ios,
            "date": days[-1],
            "engine": self.engine,
            "status": self.status,
        }
        # The highest of the iPhones' peaks, not their median: Cartouche starts
        # the game where its peak fits (docs/decisions.md, 48), and it must
        # fit there on the iPhone that needed the most.
        peak = highest([v for v in (phone.peak for phone in self.iphones) if v is not None])
        if peak is not None:
            entry["peakMemoryMiB"] = max(int(round(peak)), 1)
        entry["notes"] = [self.note()]
        measured = {"iPhones": len(self.iphones), "sessions": len(sessions), "from": days[0], "to": days[-1]}
        for key, value in (("fps", self.figure("fps")), ("slowestFps", self.figure("slowest")),
                           ("targetFps", self.target), ("stuttersPerMinute", self.figure("stutters"))):
            if value is not None:
                measured[key] = rounded(value)
        measured["endedBadlyPercent"] = rounded(100 * sum(self.ended_badly.values()) / len(sessions))
        # How they ended badly and the nxnative builds, which the note and the
        # engine say in English, for Cartouche to say them in the player's
        # language.
        if self.ended_badly:
            measured["endedBadly"] = {ENDED_BADLY_KEYS[kind]: n for kind, n in sorted(self.ended_badly.items())}
        if self.builds is not None:
            commit, others = self.builds
            measured["nxnative"] = commit
            if others:
                measured["otherBuilds"] = others
        entry["measured"] = measured
        return entry


def results(sessions: list[dict], sheet_of: dict[str, str]) -> tuple[
        dict[str, list[Result]], Counter, dict[str, set[str]], dict[str, set[str]]]:
    """What the sessions make, by the title ID of the sheet their game has or
    gets (sheet_of): the results of each sheet; how many of its game's
    models too few iPhones played on; the iPhones that played it. Then the
    iPhones that played each game of no sheet nor of nxnative's list."""
    phones: dict[tuple[str, str], dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    unlisted: dict[str, set[str]] = defaultdict(set)
    for session in sessions:
        game = session.get("game")
        if not game or not DEVICE.match(session.get("device") or ""):
            continue
        sheet = sheet_of.get(game)
        if sheet is None:
            unlisted[game].add(session["install"])
            continue
        phones[(sheet, session["device"])][session["install"]].append(session)
    found: dict[str, list[Result]] = defaultdict(list)
    too_few: Counter = Counter()
    iphones: dict[str, set[str]] = defaultdict(set)
    for (sheet, device), by_install in sorted(phones.items()):
        iphones[sheet].update(by_install)
        if len(by_install) < MIN_IPHONES:
            too_few[sheet] += 1
            continue
        found[sheet].append(Result(device, [IPhone(by_install[i]) for i in sorted(by_install)]))
    return found, too_few, iphones, unlisted


def merged(sheet: dict, measured: list[Result]) -> dict:
    """The sheet with its measured results replaced by those measured now."""
    testers = [r for r in sheet["results"] if "measured" not in r]
    kept = {r["device"]: r for r in sheet["results"] if "measured" in r}
    kept.update({result.device: result.entry() for result in measured})
    return {**sheet, "results": testers + [kept[device] for device in sorted(kept)]}


# MARK: What a sheet needs


def limit_without_iml(devices: dict) -> int | None:
    """The most memory iOS gave an app without Increased Memory Limit, of
    the limits catalog/devices.json measured on real devices: 3,376 MiB on
    an iPhone with 12 GB, which gave it 8,192 with the capability. None
    while it has no such measurement."""
    limits = [m["appMemoryLimitMiB"] for device in devices.get("devices", [])
              for m in device.get("measurements", []) if m.get("increasedMemoryLimit") is False]
    return max(limits) if limits else None


def room(limit: int) -> int:
    """The room a game keeps under LIMIT, in MiB, as Cartouche judges
    whether a game fits under a limit (CartoucheGamePlace.roomMiB,
    docs/decisions.md, 48): a peak that leaves it less is a game iOS would
    stop there."""
    return max(512, limit // 8)


def peak_of(sheet: dict) -> int | None:
    """The sheet's peak, as Cartouche reads it (CartoucheGameSheet.peakMemoryMiB):
    the highest of its own and its results'."""
    peaks = [sheet["requirements"].get("peakMemoryMiB")] + [r.get("peakMemoryMiB") for r in sheet["results"]]
    peaks = [p for p in peaks if isinstance(p, int) and not isinstance(p, bool)]
    return max(peaks) if peaks else None


def needs_iml(peak: int | None, without: int | None) -> bool:
    """Whether a game whose peak is PEAK needs Increased Memory Limit: with
    its room, it does not fit in WITHOUT, the most memory an app has without
    the capability. Nothing says so while neither was measured."""
    return peak is not None and without is not None and peak + room(without) > without


def with_requirements(sheet: dict, without: int | None) -> dict:
    """The sheet, needing Increased Memory Limit once its peak does: what the
    measurements showed it needs, they never take back. Its other
    requirements stay as they are."""
    if sheet["requirements"]["increasedMemoryLimit"] or not needs_iml(peak_of(sheet), without):
        return sheet
    return {**sheet, "requirements": {**sheet["requirements"], "increasedMemoryLimit": True}}


def new_sheet(game: dict, measured: list[Result], without: int | None) -> dict:
    """The first sheet of GAME, a game of nxnative.json that had none: its
    name and platform as nxnative's list gives them, what it needs, and the
    results measured now."""
    sheet = {
        "schema": 1,
        "titleId": game["titleId"],
        "name": game["name"],
        "platform": game["platform"],
        "requirements": {"minimumIOS": MINIMUM_IOS, "bcTextureCompression": True, "increasedMemoryLimit": False},
        "results": [],
    }
    return with_requirements(merged(sheet, measured), without)


def refusals(catalog: Path, written: Path) -> list[str]:
    """Why the sheets a run wrote into WRITTEN may not go into the catalog:
    each must be a file named by a title ID, of a sheet the catalog has or
    of a game of nxnative's list, whose titleId it is. Nothing when all may."""
    listed = {game["titleId"] for game in json.loads((catalog / "nxnative.json").read_text(encoding="utf-8"))["games"]}
    found = []
    for path in sorted(written.iterdir()):
        name = path.name
        if not SHEET_FILE.fullmatch(name) or path.is_symlink() or not path.is_file():
            # Its name as JSON writes it: a file's name may hold a line of its
            # own, which the job's log would read as a command.
            found.append(f"{json.dumps(name)} is not a sheet's file, named by its title ID")
            continue
        title = name[:-len(".json")]
        if not (catalog / "games" / name).is_file() and title not in listed:
            found.append(f"{name} is neither a sheet of catalog/games nor one of a game of catalog/nxnative.json")
            continue
        try:
            sheet = json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            found.append(f"{name} is not JSON: {error}")
            continue
        if not isinstance(sheet, dict) or sheet.get("titleId") != title:
            found.append(f"{name} is not the sheet of {title}")
    return found


def take(catalog: Path, written: Path) -> list[str]:
    """Copies the sheets a run wrote into WRITTEN into the catalog's games,
    and returns their names; copies none, and raises ValueError, while
    refusals finds any."""
    found = refusals(catalog, written)
    if found:
        raise ValueError("; ".join(found))
    names = [path.name for path in sorted(written.iterdir())]
    for name in names:
        shutil.copyfile(written / name, catalog / "games" / name)
    return names


def text(value) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


# MARK: The run


def run(catalog: Path, out: Path, today: dt.date, cloudflare: Cloudflare) -> tuple[list[str], list[str]]:
    """Writes the sheets that changed, and the new ones, into out; returns
    their names, and the lines of the job's summary."""
    nxnative = json.loads((catalog / "nxnative.json").read_text(encoding="utf-8"))
    without = limit_without_iml(json.loads((catalog / "devices.json").read_text(encoding="utf-8")))
    games = {game["titleId"]: game for game in nxnative["games"]}
    sheets = {path.stem: (path, json.loads(path.read_text(encoding="utf-8")))
              for path in sorted((catalog / "games").glob("*.json"))}
    # A copy of another region reports its own title ID, and counts for its
    # game's sheet: the one the catalog has, else the one its game gets,
    # named by the main release's title ID, by which Cartouche finds a
    # game's sheet (CartoucheCatalog.entries).
    sheet_of: dict[str, str] = {}
    for game in nxnative["games"]:
        ids = [game["titleId"]] + [v["titleId"] for v in game.get("variants", [])]
        for sheet in (i for i in ids if i in sheets):
            for i in ids:
                sheet_of.setdefault(i, sheet)
    for sheet in sheets:
        sheet_of.setdefault(sheet, sheet)
    for game in nxnative["games"]:
        for i in [game["titleId"]] + [v["titleId"] for v in game.get("variants", [])]:
            sheet_of.setdefault(i, game["titleId"])

    first, last = today - dt.timedelta(days=WINDOW_DAYS), today - dt.timedelta(days=1)
    database = cloudflare.database(DATABASE)
    sessions = read_sessions(cloudflare, database, first, last)
    found, too_few, iphones, unlisted = results(sessions, sheet_of)

    changed, new = [], []
    lines = [f"## Game measurements, {first} to {last}", "",
             f"{len(sessions)} game sessions, from {len({s['install'] for s in sessions})} iPhones.", ""]
    if found:
        lines += ["| Game | Model | iPhones | Sessions | Status |", "| --- | --- | --- | --- | --- |"]
    for sheet_id, measured in sorted(found.items()):
        if sheet_id in sheets:
            path, sheet = sheets[sheet_id]
            written = text(with_requirements(merged(sheet, measured), without))
        else:
            path, sheet = catalog / "games" / f"{sheet_id}.json", new_sheet(games[sheet_id], measured, without)
            written = text(sheet)
            new.append(sheet_id)
        for result in measured:
            lines.append(f"| {sheet['name']} | {result.device} | {len(result.iphones)} | "
                         f"{len(result.sessions)} | {result.status} |")
        if sheet_id not in sheets or written != path.read_text(encoding="utf-8"):
            out.mkdir(parents=True, exist_ok=True)
            (out / path.name).write_text(written, encoding="utf-8")
            changed.append(path.name)
    if found:
        lines.append("")
    if new:
        lines += [f"New sheets, of games played on {MIN_IPHONES} iPhones or more of a model: " + ", ".join(
            f"{games[game]['name']} ({game})" for game in new) + ".", ""]
    # The models left out of a game that has a sheet, or gets one now.
    left_out = sum(n for sheet, n in too_few.items() if sheet in sheets or sheet in found)
    if left_out:
        lines += [f"Left out: {left_out} model{'s' if left_out > 1 else ''} of a game with a sheet, "
                  f"played on fewer than {MIN_IPHONES} iPhones.", ""]
    waiting = {game: len(installs) for game, installs in sorted(iphones.items())
               if game not in sheets and game not in found and len(installs) >= MIN_IPHONES}
    if waiting:
        lines += [f"Played on {MIN_IPHONES} iPhones or more, but on fewer than {MIN_IPHONES} of each model, "
                  "so with no sheet yet: " + ", ".join(
                      f"{games[game]['name']} ({game}, {count} iPhones)" for game, count in waiting.items()) + ".", ""]
    unknown = {game: len(installs) for game, installs in sorted(unlisted.items()) if len(installs) >= MIN_IPHONES}
    if unknown:
        lines += [f"Played on {MIN_IPHONES} iPhones or more, with no sheet, not being in nxnative's list: " + ", ".join(
            f"{game} ({count} iPhones)" for game, count in unknown.items()) + ".", ""]
    lines.append(f"Sheets changed: {', '.join(changed)}." if changed else "No sheet changed.")
    return changed, lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", type=Path, default=Path("catalog"))
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument("--out", type=Path, help="where the sheets that changed, and the new ones, are written")
    what.add_argument("--take", type=Path, help="the sheets a run wrote, to check and copy into the catalog")
    parser.add_argument("--today", type=dt.date.fromisoformat, default=dt.datetime.now(dt.timezone.utc).date(),
                        help="the day of the run, in UTC: the sessions of the 28 days before it count")
    args = parser.parse_args(argv)

    if args.take:
        found = refusals(args.catalog, args.take)
        for refusal in found:
            print(f"::error::{refusal}", file=sys.stderr)
        if found:
            return 1
        had = {path.name for path in (args.catalog / "games").glob("*.json")}
        for name in take(args.catalog, args.take):
            print(f"{name}{'' if name in had else ' (new)'}")
        return 0

    def output(changed: bool) -> None:
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
                file.write(f"changed={'true' if changed else 'false'}\n")

    token, account = os.environ.get("CLOUDFLARE_API_TOKEN"), os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    if not token or not account:
        print("::notice::CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are not set: no measurement was read.")
        output(False)
        return 0
    cloudflare = Cloudflare(account, token, os.environ.get("CLOUDFLARE_API") or API)
    try:
        changed, lines = run(args.catalog, args.out, args.today, cloudflare)
    except Refused as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
            file.write("\n".join(lines) + "\n")
    output(bool(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
