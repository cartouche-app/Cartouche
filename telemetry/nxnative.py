#!/usr/bin/env python3
"""Sums up, for nxnative's developers, what Cartouche's players measured of
nxnative's games in the last 28 days: the page the nxnative page workflow
puts on the branch nxnative-measurements each Thursday
(.github/workflows/nxnative.yml, telemetry/README.md#nxnatives-page).

By game, by game and model, and by game and nxnative commit, with the
shader chain most of its installs ran: installs,
sessions and hours, the frame rate, the frame time, the stutters and what
they waited for, the shader stall, the preparation before the first frame,
the memory peak, the heat, and how the sessions ended; the crashes several
installs shared; the devices players have; the games played on players'
Macs, in nxnative's app for the Mac, how each ended and what Cartouche's
console on the Mac measured of them; and the builds on players' Macs, of
IPAs and of Mac apps, by nxnative commit. Every line, and every figure, sums
up at least three installs, or three Macs, as everything the project
publishes does (docs/privacy.md): a smaller group is left out, and no
install's or session's number is ever written. Beside the page, for
Cartouche Builder, unbuilt.json: the games at least three Macs tried and
none built, which the app warns of before one is built
(builder/mac/Sources/BuilderKit/Unbuilt.swift). Set apart, so that they do
not read as nxnative's: the sessions on iPhones whose GPU reads no BC
texture, which nxnative refuses; those whose game process ran without
Increased Memory Limit, which is Cartouche's doing; and those of builds with
changes of their own. The sessions played on a Mac, which Cartouche
Builder's console reports (telemetry/README.md#cartouche-builder), are
summed up apart from the iPhones', and the Macs that follow a fork of
nxnative are left out of all the Macs' figures.

It reads the D1 database through Cloudflare's API, with the secrets
CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID, and does nothing without
them. It writes the page as README.md, and unbuilt.json, into --out, says
what it found in the job's summary, and sets the job's output written to
true or false.

    python3 telemetry/nxnative.py --catalog catalog --out build/nxnative

Python's standard library only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sheets import (  # noqa: E402
    API, DATABASE, MIN_IPHONES, PAGE, SLOWEST_READER, WINDOW_DAYS, Cloudflare, Refused, figure_of, number, reads_bc,
)

# A line, and each of its figures, needs this many installs, as the sheets do.
MIN_INSTALLS = MIN_IPHONES
BRANCH = "nxnative-measurements"

# A Mac's model identifier, as Cartouche Builder sends it. The iPhones whose
# GPU reads no BC texture, which nxnative refuses: reads_bc (sheets.py).
MAC = re.compile(r"^Mac[0-9]+,[0-9]+$")

# A game process with this limit or less, while Cartouche had more, ran
# without Increased Memory Limit (CartoucheGuest.m): Cartouche's doing, not
# nxnative's.
WITHOUT_IML_MIB = 3376

SIGNALS = {4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS",
           11: "SIGSEGV", 12: "SIGSYS"}

# Why a game crashed, when its log says (CartoucheGameLog.swift, end.cause):
# gpuLost, nxnative stopped it once the system took the GPU away from it for
# the GPU errors it caused ("[RED] GPU access revoked", gpu_lost_check in
# nvn_mtl.m). Cartouche tells it from its fourth reading of the log on:
# before it, such a session was a crash like any other abort.
CAUSES = {"gpuLost": "GPU access revoked"}
GPU_LOST_READER = 4

# A line no session drew a frame of, though its sessions lasted this long in
# all, may be a game that runs while nxnative writes none of the summary
# lines Cartouche counts frames from, as much as one stuck on a black
# screen: Super Mario Galaxy, 15 sessions and 11 hours on 7 installs, none
# with a summary line (17 November). Its sessions are not said to have drawn
# no frame. The dashboard's rule (UNCOUNTED_MINUTES, telemetry/dashboard).
UNCOUNTED_MINUTES = 30

# The sessions one day received, a page at a time, with D1's parameters as
# text. A session sent again because its log grew is the same session with
# a higher seq.
SESSIONS = (
    "SELECT id, install, session, seq, day, device, ios, game, "
    "json_extract(body, '$.nxnative') AS nxnative, "
    "json_extract(body, '$.nxnativeChanged') AS changed, "
    "json_extract(body, '$.chain') AS chain, "
    "json_extract(body, '$.gameVersion') AS version, "
    "json_extract(body, '$.minutes') AS minutes, "
    "json_extract(body, '$.frames') AS frames, "
    "json_extract(body, '$.targetFps') AS target, "
    "json_extract(body, '$.fps.median') AS fps, "
    "json_extract(body, '$.fps.low5') AS slowest, "
    "json_extract(body, '$.frameMs.p99') AS p99, "
    "json_extract(body, '$.stutters.perMinute') AS stutters, "
    "json_extract(body, '$.stutters.count') AS stutterCount, "
    "json_extract(body, '$.stutters.shaders') AS stutterShaders, "
    "json_extract(body, '$.shaderStallMsPerMinute') AS stall, "
    "json_extract(body, '$.prepare.seconds') AS prepare, "
    "json_extract(body, '$.memory.peakMiB') AS peak, "
    "json_extract(body, '$.thermal.seriousAfterMinutes') AS serious, "
    "json_extract(body, '$.end.kind') AS ending, "
    "json_extract(body, '$.end.signal') AS signal, "
    "json_extract(body, '$.end.pc') AS pc, "
    "json_extract(body, '$.end.lr') AS lr, "
    "json_extract(body, '$.end.cause') AS endCause, "
    "json_extract(body, '$.process.limitMiB') AS processLimit, "
    "json_extract(body, '$.memoryLimitMiB') AS limitMiB, "
    "json_extract(body, '$.reader') AS reader "
    f"FROM reports WHERE kind = 'session' AND day = ?1 AND id > ?2 ORDER BY id LIMIT {PAGE}"
)

# The events the page reads: Cartouche's starts, for the devices, and
# Cartouche Builder's starts, builds and games played, for the builds by
# commit and the games played on Macs.
EVENTS = (
    "SELECT id, install, seq, day, device, ios, name, "
    "json_extract(body, '$.memoryLimitMiB') AS limitMiB, "
    "json_extract(body, '$.increasedMemoryLimit') AS iml, "
    "json_extract(body, '$.fields.nxnative') AS nxnative, "
    "json_extract(body, '$.fields.stage') AS stage, "
    "json_extract(body, '$.fields.cause') AS cause, "
    "json_extract(body, '$.fields.forkOfNxnative') AS fork, "
    "json_extract(body, '$.fields.seconds') AS seconds, "
    "json_extract(body, '$.fields.ended') AS ended, game "
    "FROM reports WHERE kind = 'event' "
    "AND name IN ('app.opened', 'builder.opened', 'builder.built', 'builder.failed', 'builder.macBuilt', "
    "'builder.macFailed', 'builder.played') "
    f"AND day = ?1 AND id > ?2 ORDER BY id LIMIT {PAGE}"
)


def read(cloudflare: Cloudflare, database: str, sql: str, first: dt.date, last: dt.date) -> list[dict]:
    """The rows of SQL for each day from first to last."""
    rows: list[dict] = []
    day = first
    while day <= last:
        after = ""
        while True:
            page = cloudflare.query(database, sql, [day.isoformat(), after])
            rows += page
            if len(page) < PAGE:
                break
            after = page[-1]["id"]
        day += dt.timedelta(days=1)
    return rows


def once(rows: list[dict], key) -> list[dict]:
    """Each row of rows once by key, the one with the highest seq."""
    kept: dict = {}
    for row in rows:
        k = key(row)
        if k not in kept or (row.get("seq") or 0) > (kept[k].get("seq") or 0):
            kept[k] = row
    return list(kept.values())


# MARK: Sessions


def set_apart(session: dict) -> str | None:
    """Why an iPhone's session does not count for nxnative, if it does not."""
    if not reads_bc(session.get("device")):
        return "gpu"
    process, limit = number(session.get("processLimit")), number(session.get("limitMiB"))
    if process is not None and process <= WITHOUT_IML_MIB and (limit or 0) > process:
        return "memory"
    if session.get("changed") in (1, True):
        return "changed"
    return None


def drew_frames(session: dict) -> bool:
    """Whether the session got into the game: it drew a frame."""
    return (number(session.get("frames")) or 0) > 0 or number(session.get("fps")) is not None


def ending(session: dict) -> str | None:
    """How a session ended badly: it crashed, failed to boot, ran out of
    memory, or ended before it drew a frame."""
    kind = session.get("ending")
    if kind in ("crash", "boot-failed", "memory-likely"):
        return kind
    return None if drew_frames(session) else "no-frame"


class Group:
    """Sessions summed up together, each install counting once."""

    def __init__(self, sessions: list[dict]):
        self.sessions = sessions

    @property
    def installs(self) -> set[str]:
        return {s["install"] for s in self.sessions}

    def figure(self, key: str, sessions: list[dict] | None = None, highest: bool = False) -> float | None:
        """The median of each install's own median, or of its highest; none
        when fewer than MIN_INSTALLS installs gave the value. The slowest 5%
        counts only from the reading of the log that takes pauses out, as in
        the game sheets (sheets.SLOWEST_READER)."""
        by: dict[str, list[float]] = defaultdict(list)
        for s in self.sessions if sessions is None else sessions:
            value = figure_of(s, key)
            if value is not None:
                by[s["install"]].append(value)
        if len(by) < MIN_INSTALLS:
            return None
        return statistics.median(max(v) if highest else statistics.median(v) for v in by.values())

    @property
    def peak(self) -> float | None:
        """Each install's highest peak of its sessions that drew a frame."""
        return self.figure("peak", [s for s in self.sessions if drew_frames(s)], highest=True)

    @property
    def shader_share(self) -> float | None:
        """The share of the stutters that waited for shaders, of the
        installs that counted stutters."""
        counted = [s for s in self.sessions if (number(s.get("stutterCount")) or 0) > 0]
        if len({s["install"] for s in counted}) < MIN_INSTALLS:
            return None
        return sum(number(s.get("stutterShaders")) or 0 for s in counted) / sum(number(s["stutterCount"]) for s in counted)

    @property
    def hours(self) -> float:
        return sum(number(s.get("minutes")) or 0 for s in self.sessions) / 60

    @property
    def target(self) -> int | None:
        targets = Counter(int(t) for t in (number(s.get("target")) for s in self.sessions) if t)
        return targets.most_common(1)[0][0] if targets else None

    @property
    def hot(self) -> int:
        return sum(1 for s in self.sessions if number(s.get("serious")) is not None)

    @property
    def endings(self) -> Counter:
        return Counter(e for e in (ending(s) for s in self.sessions) if e)

    @property
    def uncounted(self) -> bool:
        """No session drew a frame, though they lasted UNCOUNTED_MINUTES or
        more in all: nxnative's log may have no summary line for the game."""
        return not any(drew_frames(s) for s in self.sessions) and self.hours * 60 >= UNCOUNTED_MINUTES

    @property
    def gpu_lost(self) -> int | None:
        """The crashes nxnative ended when the system took the GPU away from
        the game; none when Cartouche read no session of the group so as to
        tell them."""
        if not any((number(s.get("reader")) or 1) >= GPU_LOST_READER for s in self.sessions):
            return None
        return sum(1 for s in self.sessions if ending(s) == "crash" and s.get("endCause") == "gpuLost")



def fmt(value: float | None, digits: int = 0) -> str:
    if value is None:
        return "–"
    return f"{value:,.{digits}f}"


def listed(items) -> str:
    items = list(items)
    return ", ".join(items) if items else f"none on {MIN_INSTALLS} installs or more"


def installs_text(n: int) -> str:
    return f"{n} installs" if n >= MIN_INSTALLS or n == 0 else f"fewer than {MIN_INSTALLS} installs"


def macs_text(n: int) -> str:
    return f"{n} Macs" if n >= MIN_INSTALLS or n == 0 else f"fewer than {MIN_INSTALLS} Macs"


def shared(pairs) -> tuple[list[tuple[str, int]], int]:
    """Of (value, install) pairs, the values at least MIN_INSTALLS installs
    share, with how many share each, most first; and how many other values
    there are, which fewer installs share."""
    by: dict[str, set] = defaultdict(set)
    for value, install in pairs:
        if value:
            by[value].add(install)
    kept = sorted(((v, len(i)) for v, i in by.items() if len(i) >= MIN_INSTALLS), key=lambda vi: (-vi[1], vi[0]))
    return kept, len(by) - len(kept)


def most_shared(pairs, what: str) -> str:
    """The value most installs share, when at least MIN_INSTALLS do, and
    how many others; or only how many values, or "not said"."""
    kept, others = shared(pairs)
    if not kept:
        return f"{others} {what}{'s' if others > 1 else ''}" if others else "not said"
    rest = len(kept) - 1 + others
    return f"`{kept[0][0]}`" + (f" (+{rest})" if rest else "")


class Catalog:
    """The names of the games, a copy of another region under its game."""

    def __init__(self, catalog: Path):
        games = json.loads((catalog / "nxnative.json").read_text(encoding="utf-8"))["games"]
        self.names = {g["titleId"]: g["name"] for g in games}
        self.main = {v["titleId"]: g["titleId"] for g in games for v in g.get("variants", [])}
        covers = catalog / "covers.json"
        if covers.exists():
            for cover in json.loads(covers.read_text(encoding="utf-8")).get("covers", []):
                if cover.get("name"):
                    self.names.setdefault(cover["titleId"], cover["name"])

    def game(self, title: str | None) -> str | None:
        return self.main.get(title, title) if title else None

    def name(self, title: str) -> str:
        name = self.names.get(title)
        return f"{name} `{title}`" if name else f"`{title}`"


def commits_text(group: Group) -> str:
    """The nxnative commit most installs of the group ran, and how many others."""
    return most_shared(((s.get("nxnative"), s["install"]) for s in group.sessions), "commit")


def chains_text(group: Group) -> str:
    """The shader chain most installs of the group ran, and how many others."""
    return most_shared(((s.get("chain"), s["install"]) for s in group.sessions), "chain")


FIGURES = ("Installs", "Sessions", "Hours", "Target fps", "FPS median", "FPS slowest 5%", "Frame p99 ms",
           "Stutters a minute", "Waiting for shaders", "Shader stall ms a minute", "Prepare s", "Peak MiB",
           "Reached serious heat", "Crashed", "GPU lost", "Failed to boot", "Out of memory", "Drew no frame")

# The columns of the sessions played on a Mac: a Mac counts as an install
# does, and nxnative reads no thermal state there (telemetry/README.md).
ON_A_MAC = {"Installs": "Macs", "Reached serious heat": None}


def figures(group: Group) -> list[str]:
    """The group's cells, one for each of FIGURES."""
    endings = group.endings
    share = group.shader_share
    return [
        str(len(group.installs)), str(len(group.sessions)), fmt(group.hours, 1), fmt(group.target),
        fmt(group.figure("fps"), 1), fmt(group.figure("slowest"), 1), fmt(group.figure("p99"), 1),
        fmt(group.figure("stutters")), "–" if share is None else f"{share:.0%}", fmt(group.figure("stall")),
        fmt(group.figure("prepare"), 1), fmt(group.peak), f"{group.hot} of {len(group.sessions)}",
        str(endings["crash"]), fmt(group.gpu_lost), str(endings["boot-failed"]), str(endings["memory-likely"]),
        "no summary line" if group.uncounted else str(endings["no-frame"]),
    ]


def table(title: str, keys: list[str], groups: dict[tuple, Group], cells, empty: str, about: str | None = None,
          columns: dict[str, str | None] | None = None) -> list[str]:
    """A section of the page: its groups of MIN_INSTALLS installs or more,
    those of the most installs first, each with its keys' cells and its
    figures, under their names or those columns gives them; a column
    columns names None is left out."""
    columns = columns or {}
    shown = [(i, columns.get(name, name)) for i, name in enumerate(FIGURES) if columns.get(name, name)]
    kept = sorted(((key, group) for key, group in groups.items() if len(group.installs) >= MIN_INSTALLS),
                  key=lambda kv: (-len(kv[1].installs), -len(kv[1].sessions), kv[0]))
    lines = [f"## {title}", ""] + ([about, ""] if about else [])
    if not kept:
        return lines + [empty, ""]
    lines += ["| " + " | ".join(keys + [name for _, name in shown]) + " |",
              "|" + " --- |" * (len(keys) + len(shown))]
    for key, group in kept:
        values = figures(group)
        lines.append("| " + " | ".join(cells(key, group) + [values[i] for i, _ in shown]) + " |")
    return lines + [""]


# MARK: The page


def page(catalog: Catalog, sessions: list[dict], events: list[dict], first: dt.date, last: dt.date) -> tuple[str, list[str]]:
    """The page, and the lines of the job's summary."""
    sessions = once(sessions, lambda s: (s["install"], s["session"]))
    for s in sessions:
        s["game"] = catalog.game(s.get("game"))
    # The page says the days it has measurements of, within the 28.
    days = sorted(r["day"] for r in sessions + events if r.get("day"))
    since = days[0] if days else first.isoformat()
    # The sessions played on a Mac, which Cartouche's console there measured,
    # are summed up apart from the iPhones'.
    on_macs = [s for s in sessions if MAC.match(s.get("device") or "")]
    sessions = [s for s in sessions if not MAC.match(s.get("device") or "")]
    forks = forks_of(events)
    apart = Counter()
    apart_installs: dict[str, set] = defaultdict(set)
    kept = []
    for s in sessions:
        reason = set_apart(s)
        if reason:
            apart[reason] += 1
            apart_installs[reason].add(s["install"])
        elif s.get("game"):
            kept.append(s)

    by_game: dict[tuple, Group] = defaultdict(lambda: Group([]))
    by_model: dict[tuple, Group] = defaultdict(lambda: Group([]))
    by_commit: dict[tuple, Group] = defaultdict(lambda: Group([]))
    for s in kept:
        by_game[(s["game"],)].sessions.append(s)
        by_model[(s["game"], s.get("device") or "")].sessions.append(s)
        if s.get("nxnative"):
            by_commit[(s["game"], s["nxnative"])].sessions.append(s)

    installs = {s["install"] for s in sessions}
    named = sum(1 for s in kept if s.get("nxnative"))
    hours = sum(number(s.get("minutes")) or 0 for s in sessions) / 60
    lines = [
        "# nxnative's games on players' iPhones and Macs",
        "",
        f"What the players of [Cartouche](https://github.com/cartouche-app/Cartouche) measured of nxnative's games "
        f"from {since} to {last}, on their iPhones and on their Macs, summed up for nxnative's developers each "
        "Thursday. How, and what is left out: "
        "[telemetry/README.md](https://github.com/cartouche-app/Cartouche/blob/main/telemetry/README.md#nxnatives-page).",
        "",
        f"{len(sessions)} game sessions on iPhones and iPads from {installs_text(len(installs))}, {hours:,.1f} hours "
        f"of play. {named} of the {len(kept)} sessions that count name their nxnative commit. "
        f"Every line, and every figure, sums up at least {MIN_INSTALLS} installs, or {MIN_INSTALLS} Macs: a smaller "
        "group is left out, and a figure fewer of them gave shows –. The games played on players' Macs, and the "
        "builds there, follow the devices.",
        "",
    ]
    if apart:
        said = {"gpu": "on iPhones whose GPU reads no BC texture (A16 and older), which nxnative refuses",
                "memory": "whose game process ran without Increased Memory Limit, which is Cartouche's doing",
                "changed": "of builds with changes of their own"}
        lines += ["Set apart: " + "; ".join(
            f"{apart[reason]} sessions {said[reason]}, from {installs_text(len(apart_installs[reason]))}"
            if len(apart_installs[reason]) >= MIN_INSTALLS else f"sessions {said[reason]}, from {installs_text(1)}"
            for reason in ("gpu", "memory", "changed") if apart[reason]) + ".", ""]

    lines += table("By game", ["Game", "nxnative"], by_game,
                   lambda key, group: [catalog.name(key[0]), commits_text(group)],
                   f"No game was played on {MIN_INSTALLS} installs or more.")
    lines += table("By game and model", ["Game", "Model", "nxnative"], by_model,
                   lambda key, group: [catalog.name(key[0]), f"`{key[1]}`", commits_text(group)],
                   f"No game was played on {MIN_INSTALLS} installs or more of one model.")
    lines += table("By game and nxnative commit", ["Game", "nxnative", "Shader chain"], by_commit,
                   lambda key, group: [catalog.name(key[0]), f"`{key[1]}`", chains_text(group)],
                   f"No game was played from one nxnative commit on {MIN_INSTALLS} installs or more.")
    lines += crashes(catalog, kept)
    lines += devices(events)
    lines += played(catalog, events, forks)
    measured: dict[tuple, Group] = defaultdict(lambda: Group([]))
    for s in on_macs:
        if s.get("game") and s["install"] not in forks and s.get("changed") not in (1, True):
            measured[(s["game"],)].sessions.append(s)
    lines += table("Measured on players' Macs", ["Game", "nxnative"], measured,
                   lambda key, group: [catalog.name(key[0]), commits_text(group)],
                   f"No game was measured on {MIN_INSTALLS} Macs or more.",
                   about="What Cartouche's console on the Mac read of each game played there, in the log "
                         "nxnative's app for the Mac writes, as Cartouche reads an iPhone's: each Mac counts once, "
                         "as an install does.",
                   columns=ON_A_MAC)
    lines += builds(events, forks, IPAS)
    lines += builds(events, forks, MAC_APPS)
    lines += [
        "## How it is summed up",
        "",
        "- An install is one copy of Cartouche on one iPhone or iPad, under a random number it changes every 13 months "
        "or when its player erases what it sent: a player who installs Cartouche again is a new install. A Mac is one "
        "copy of Cartouche Builder. Neither number is ever written here.",
        "- Each figure is the median of each install's own median, so that each install counts once however much it "
        "played; the peak is each install's highest, of its sessions that drew a frame. Stutters waiting for shaders "
        "are a share of all the stutters of the line.",
        "- FPS slowest 5% is the rate of the slowest 5% of a session's time: the frame rate of each `[nvn] power` "
        "line, over its 300 frames, weighted by how long they lasted. nxnative times them by the clock, so a stretch "
        "that held a pause, the game left behind Cartouche's console or Cartouche in the background counts at the "
        f"rate that pause brought it to: it counts only from the sessions Cartouche read with its reading {SLOWEST_READER} "
        "of the log or a later one, which leaves such a stretch out, and shows – before. Stutters and the shader "
        "stall are per minute of the whole session.",
        "- The figures come from the lines nxnative writes in `log.txt`, which Cartouche reads after each session "
        "([CartoucheGameLog.swift](https://github.com/cartouche-app/Cartouche/blob/main/launcher/Sources/"
        "CartoucheGameLog.swift)): the `[nvn]` timing, on-screen and power lines, `[longframe]`, `pipeline prepare`, "
        "the memory and thermal lines, `CRASH sig=`, `GPU access revoked` and `[RED] boot:`. "
        "A session's commit is the first 12 digits of `DMCommit` in the game's `Info.plist`; Cartouche 0.11.2 and "
        "before did not send it. Its shader chain is the first 12 digits of `DMChain` beside it; Cartouche 0.16.0 "
        "and before did not send it. Target fps is the rate most of the line's sessions asked for.",
        "- Reached serious heat: the sessions iOS put in its serious thermal state. Drew no frame: the session ended "
        "before nxnative's first summary line, whatever its end. A line none of whose sessions wrote one, though they "
        f"lasted {UNCOUNTED_MINUTES} minutes or more in all, says no summary line instead: the game may run while "
        "nxnative writes no `[nvn]` timing, on-screen or power line for it, as much as stay on a black screen, and "
        "its frame figures show –.",
        "- GPU lost: the crashes nxnative ended once the system took the GPU away from the game for the GPU errors it "
        "caused (`[RED] GPU access revoked`), as the crashes' cause says too. Cartouche tells them from its reading "
        f"{GPU_LOST_READER} of the log on: before it, such a session is a crash like any other abort, and a line "
        "with no session read so shows –. On a Mac, nxnative quits the game itself, and its crash has no signal.",
        "- A session counts once, as last sent; a copy of another region counts for its game.",
        "- nxnative, Shader chain, Models: the commit, the shader chain or the model most installs of the line ran, "
        "when at least 3 did, and how many others; else only how many, or not said when none sent it. A Mac counts as an install does: a step of a build shows when at least 3 "
        "Macs failed at it.",
        "- On players' Macs: a play is a game Cartouche Builder started, from its Play button, the Finder, the Dock "
        "or Launchpad, counted once it ended, as the last line of nxnative's launcher in its log says: Quit, "
        "`launcher: the host exited with 0`; GPU revoked, with 70, macOS having stopped the game's GPU work; "
        "Crashed, another exit code or a signal; Stopped, SIGHUP, SIGINT, SIGKILL or SIGTERM, from outside; "
        "Unknown, no such line, as when nxnative's window was closed without playing. Median minutes: the median "
        "of each Mac's own median play. Measured: Cartouche's console on the Mac reads the log of each game played "
        "there as Cartouche reads an iPhone's, its minutes from the start of nxnative's launcher, its settings "
        "window too; nxnative reads no thermal state on the Mac. The Macs whose Cartouche Builder follows a fork of "
        "nxnative are left out, and so are the builds with changes of their own.",
        "- Builds, of IPAs and of Mac apps: the Macs whose Cartouche Builder follows a fork of nxnative are left "
        "out, and so are the builds the player stopped and the errors of Cartouche Builder's own code. A game of a "
        "Mac counts once for a commit, as its last try with it ended, however often its player tried it again. A "
        "regression is such a game that failed and had built on that Mac on an earlier try, from any commit of the "
        "28 days. Where they failed is nxnative's stage of each failed game's last try. Minutes: the median of "
        "each Mac's own median build, from its builds that built.",
        "",
    ]
    uncounted = sorted(catalog.name(key[0]) for key, group in by_game.items()
                       if len(group.installs) >= MIN_INSTALLS and group.uncounted)
    summary = [f"## nxnative's page, {first} to {last}", "",
               f"{len(sessions)} game sessions from {len(installs)} installs; "
               f"{sum(1 for g in by_game.values() if len(g.installs) >= MIN_INSTALLS)} games, "
               f"{sum(1 for g in by_model.values() if len(g.installs) >= MIN_INSTALLS)} lines by model and "
               f"{sum(1 for g in by_commit.values() if len(g.installs) >= MIN_INSTALLS)} by commit "
               f"on {MIN_INSTALLS} installs or more; {named} sessions name their nxnative commit.", ""]
    if uncounted:
        summary += ["Played long without a summary line in their logs: " + ", ".join(uncounted) + ".", ""]
    return "\n".join(lines), summary


def crashes(catalog: Catalog, kept: list[dict]) -> list[str]:
    crashed = [s for s in kept if s.get("ending") == "crash"]
    by_signal: dict[tuple, Group] = defaultdict(lambda: Group([]))
    exact: dict[tuple, Group] = defaultdict(lambda: Group([]))
    for s in crashed:
        signal = int(number(s.get("signal")) or 0)
        cause = s.get("endCause") or ""
        by_signal[(s["game"], signal, cause)].sessions.append(s)
        if s.get("pc") and s.get("nxnative"):
            exact[(s["game"], s.get("version") or "", s["nxnative"], signal, cause, s["pc"],
                   s.get("lr") or "")].sessions.append(s)
    lines = ["## Crashes", ""]
    rows = sorted(((k, g) for k, g in by_signal.items() if len(g.installs) >= MIN_INSTALLS),
                  key=lambda kv: (-len(kv[1].installs), kv[0]))
    if rows:
        lines += ["| Game | Signal | Cause | Installs | Sessions | Models | nxnative | Minutes in |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for (game, signal, cause), group in rows:
            models = most_shared(((s.get("device"), s["install"]) for s in group.sessions), "model")
            lines.append(f"| {catalog.name(game)} | {SIGNALS.get(signal, signal or '–')} | "
                         f"{CAUSES.get(cause, cause or '–')} | {len(group.installs)} | "
                         f"{len(group.sessions)} | {models} | {commits_text(group)} | "
                         f"{fmt(group.figure('minutes'), 1)} |")
        lines.append("")
    else:
        lines += [f"No game crashed with one signal and cause on {MIN_INSTALLS} installs or more.", ""]
    rows = sorted(((k, g) for k, g in exact.items() if len(g.installs) >= MIN_INSTALLS),
                  key=lambda kv: (-len(kv[1].installs), kv[0]))
    if rows:
        lines += ["The same crash, at the same place of the same build, on several installs:", "",
                  "| Game | Version | nxnative | Signal | Cause | pc | lr | Installs | Sessions | Minutes in |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for (game, version, commit, signal, cause, pc, lr), group in rows:
            lines.append(f"| {catalog.name(game)} | {version or '–'} | `{commit}` | {SIGNALS.get(signal, signal)} | "
                         f"{CAUSES.get(cause, cause or '–')} | `{pc}` | `{lr}` | {len(group.installs)} | "
                         f"{len(group.sessions)} | {fmt(group.figure('minutes'), 1)} |")
        lines.append("")
    return lines


def devices(events: list[dict]) -> list[str]:
    """The devices of the installs that started Cartouche, as each last did."""
    last = once([e for e in events if e.get("name") == "app.opened"], lambda e: e["install"])
    lines = ["## Devices", "", f"The installs that started Cartouche, as each last did: {installs_text(len(last))}.", ""]
    if len(last) < MIN_INSTALLS:
        return lines
    models = Counter(e.get("device") or "" for e in last)
    shown = sorted(((m, n) for m, n in models.items() if n >= MIN_INSTALLS), key=lambda mn: (-mn[1], mn[0]))
    rest = sum(n for _, n in models.items()) - sum(n for _, n in shown)
    others = len(models) - len(shown)
    lines.append("- Models: " + listed(f"`{m}` {n}" for m, n in shown)
                 + (f"; {installs_text(rest)} on {others} other model{'s' if others > 1 else ''}" if rest else "") + ".")
    ios = Counter(".".join((e.get("ios") or "").split(".")[:2]) for e in last)
    lines.append("- iOS: " + listed(
        f"{v} {n}" for v, n in sorted(ios.items(), key=lambda vn: [int(x) for x in vn[0].split(".") if x.isdigit()])
        if n >= MIN_INSTALLS and v) + ".")
    limits = Counter((int(number(e.get("limitMiB")) or 0), e.get("iml") in (1, True)) for e in last)
    lines.append("- The memory limit iOS sets for Cartouche: " + listed(
        f"{limit:,} MiB{'' if iml else ' without Increased Memory Limit'} on {n}"
        for (limit, iml), n in sorted(limits.items(), key=lambda kn: (-kn[1], -kn[0][0], not kn[0][1]))
        if n >= MIN_INSTALLS and limit) + ".")
    no_bc = sum(1 for e in last if not reads_bc(e.get("device")))
    lines += [f"- iPhones whose GPU reads no BC texture (A16 and older): {installs_text(no_bc)}.", ""]
    return lines


# MARK: Macs


def forks_of(events: list[dict]) -> set[str]:
    """The Macs whose Cartouche Builder follows a fork of nxnative, as each
    last started."""
    return {e["install"] for e in once([e for e in events if e.get("name") == "builder.opened"], lambda e: e["install"])
            if e.get("fork") in (1, True)}


def seconds_of(event: dict) -> float:
    """How long an event says it took, 0 when it does not."""
    seconds = event.get("seconds")
    return seconds if isinstance(seconds, (int, float)) and not isinstance(seconds, bool) and seconds > 0 else 0


def median_seconds(events: list[dict]) -> float | None:
    """The median of each Mac's own median of how long its events took;
    none when fewer than MIN_INSTALLS Macs said it."""
    by: dict[str, list[float]] = defaultdict(list)
    for e in events:
        if seconds_of(e):
            by[e["install"]].append(seconds_of(e))
    if len(by) < MIN_INSTALLS:
        return None
    return statistics.median(statistics.median(v) for v in by.values())


def counted(n: int, what: str) -> str:
    return f"{n:,} {what}{'' if n == 1 else 's'}"


# How a game played on a Mac ended, as nxnative's launcher says it in its
# log and Cartouche Builder reads it (builder.played's ended, MacPlay.swift),
# in the page's words.
ENDED = (("quit", "Quit"), ("gpu", "GPU revoked"), ("crashed", "Crashed"), ("stopped", "Stopped"),
         ("unknown", "Unknown"))


def played(catalog: Catalog, events: list[dict], forks: set[str]) -> list[str]:
    """The games played on players' Macs, in nxnative's app for the Mac, as
    Cartouche Builder tells each play once it ended (builder.played), those
    of a fork of nxnative left out: how many, and by game, those
    MIN_INSTALLS Macs or more played, with how their plays ended."""
    plays = [e for e in events if e.get("name") == "builder.played" and e.get("game") and e["install"] not in forks]
    lines = ["## Played on players' Macs", "",
             "Cartouche Builder builds each game's app for the Mac too, from the same commit, and follows each game "
             "played on the Mac, started from its Play button or from the Finder: how each play ended, as "
             "nxnative's launcher says it in its log. A Mac counts as an install does.", ""]
    macs = {e["install"] for e in plays}
    if len(macs) < MIN_INSTALLS:
        return lines + [f"No game was played on {MIN_INSTALLS} Macs or more.", ""]
    by: dict[str, list[dict]] = defaultdict(list)
    for e in plays:
        by[catalog.game(e["game"])].append(e)
    lines += [f"{counted(len(plays), 'play')} of {counted(len(by), 'game')} on {len(macs)} Macs, "
              f"{sum(seconds_of(e) for e in plays) / 3600:,.1f} hours.", ""]
    rows = sorted(((game, its) for game, its in by.items() if len({e["install"] for e in its}) >= MIN_INSTALLS),
                  key=lambda gi: (-len({e["install"] for e in gi[1]}), -len(gi[1]), gi[0]))
    if not rows:
        return lines + [f"No game was played on {MIN_INSTALLS} Macs or more.", ""]
    known = dict(ENDED)
    lines += ["| Game | Macs | Plays | Hours | Median minutes | " + " | ".join(name for _, name in ENDED) + " |",
              "|" + " --- |" * (5 + len(ENDED))]
    for game, its in rows:
        ended = Counter(e.get("ended") if e.get("ended") in known else "unknown" for e in its)
        median = median_seconds(its)
        lines.append(f"| {catalog.name(game)} | {len({e['install'] for e in its})} | {len(its)} | "
                     f"{sum(seconds_of(e) for e in its) / 3600:,.1f} | {fmt(None if median is None else median / 60, 1)} | "
                     + " | ".join(str(ended[key]) for key, _ in ENDED) + " |")
    return lines + [""]


# MARK: Builds


# Failures that are not nxnative's: the player stopped the build, or
# Cartouche Builder's own code failed (builder/cartouche_builder/causes.py).
NOT_NXNATIVES = ("stopped", "builder")


class Builds(NamedTuple):
    """A kind of build on players' Macs, as Cartouche Builder reports it."""
    built: str
    failed: str
    what: str
    title: str
    about: str
    empty: str


# The games' IPAs, and their apps for the Mac they are built on, which
# Cartouche Builder counts apart (docs/decisions/095.md).
IPAS = Builds("builder.built", "builder.failed", "IPA", "IPAs built on players' Macs, by nxnative commit",
              "Cartouche Builder builds players' games with nxnative's build script, on their Macs.",
              f"No nxnative commit was built on {MIN_INSTALLS} Macs or more.")
MAC_APPS = Builds("builder.macBuilt", "builder.macFailed", "Mac app",
                  "Mac apps built on players' Macs, by nxnative commit",
                  "Cartouche Builder also builds each game's app for the Mac it builds on, from the same commit and "
                  "files, after its IPA or alone.",
                  f"No nxnative commit was built for the Mac on {MIN_INSTALLS} Macs or more.")


def in_all(last: list[dict], kind: Builds) -> list[str]:
    """The builds of every commit together, each game of a Mac once for a
    commit, as its last try with it ended: how many built, of how many
    games, on how many Macs, and in how long; how many failed, on how many
    Macs, and the steps MIN_INSTALLS Macs or more failed at. What fewer
    Macs did is not counted."""
    macs = {e["install"] for e in last}
    if len(macs) < MIN_INSTALLS:
        return []
    built = [e for e in last if e["name"] == kind.built]
    failed = [e for e in last if e["name"] == kind.failed]
    built_on, failed_on = {e["install"] for e in built}, {e["install"] for e in failed}
    said = f"In all, from {counted(len({e['nxnative'] for e in last}), 'nxnative commit')}: "
    if len(built_on) >= MIN_INSTALLS:
        median = median_seconds(built)
        said += (f"{counted(len(built), kind.what)} of {counted(len({e.get('game') for e in built}), 'game')} built "
                 f"on {len(built_on)} Macs" + ("" if median is None else f", in a median of {median / 60:,.0f} minutes"))
    else:
        said += f"{kind.what}s built on {macs_text(len(built_on))}" if built_on else f"no {kind.what} built"
    if len(failed_on) >= MIN_INSTALLS:
        said += f"; {len(failed):,} failed on {len(failed_on)} Macs."
    else:
        said += f"; some failed, on {macs_text(len(failed_on))}." if failed_on else "; none failed."
    lines = [said, ""]
    if len(failed_on) >= MIN_INSTALLS:
        # The steps named, the most failed games first, then the failures
        # that said none, as the table does, and the other steps together.
        unsaid = "a step not said"
        pairs = [(e.get("stage") or unsaid, e["install"]) for e in failed]
        stages, _ = shared(pairs)
        counts = Counter(stage for stage, _ in pairs)
        if stages:
            rest = len(pairs) - sum(counts[stage] for stage, _ in stages)
            lines += [f"The steps {MIN_INSTALLS} Macs or more failed at: " + "; ".join(
                f"{stage}, {counts[stage]:,} on {n} Macs"
                for stage, n in sorted(stages, key=lambda sn: (sn[0] == unsaid, -counts[sn[0]], -sn[1], sn[0])))
                + (f"; other steps, {rest:,}" if rest else "") + ".", ""]
    return lines


def builds(events: list[dict], forks: set[str], kind: Builds) -> list[str]:
    """Cartouche Builder's builds of KIND on players' Macs, by nxnative
    commit, but those of a fork of nxnative and the failures that are not
    nxnative's. A game of a Mac counts once for a commit, as its last try
    with it ended, however often its player tried it again; its regressions
    are the games that failed so and had built on that Mac on an earlier
    try, which is what a commit that broke a build does, where a game a Mac
    never built may fail for its own files."""
    tries = [e for e in events
             if e.get("name") in (kind.built, kind.failed) and e["install"] not in forks and e.get("nxnative")
             and not (e["name"] == kind.failed and e.get("cause") in NOT_NXNATIVES)]

    def game_of_mac(e: dict) -> tuple:
        return e["install"], e.get("game")

    # When each game of each Mac first built, as the Mac counts its reports.
    first_built: dict[tuple, int] = {}
    for e in tries:
        if e["name"] == kind.built:
            key, seq = game_of_mac(e), e.get("seq") or 0
            first_built[key] = min(first_built.get(key, seq), seq)
    by: dict[str, list] = defaultdict(list)
    for e in tries:
        by[e["nxnative"]].append(e)
    rows = []
    for commit, its in by.items():
        macs = {e["install"] for e in its}
        if len(macs) < MIN_INSTALLS:
            continue
        last = once(its, game_of_mac)
        failed = [e for e in last if e["name"] == kind.failed]
        back = [e for e in failed if first_built.get(game_of_mac(e), e.get("seq") or 0) < (e.get("seq") or 0)]
        rows.append((commit, len(macs), len(last) - len(failed), failed, back))
    rows.sort(key=lambda row: (-row[1], row[0]))
    lines = [f"## {kind.title}", "",
             f"{kind.about} A game of a Mac counts once for a commit, as its last try with it ended, however often "
             "its player tried it again. Regressions are the games that fail with the commit and had built on their "
             "Mac before, and on how many Macs: a commit that broke a build makes them on several.", ""]
    lines += in_all(once(tries, lambda e: (e["nxnative"],) + game_of_mac(e)), kind)
    if not rows:
        return lines + [kind.empty, ""]
    lines += ["| nxnative | Macs | Built | Failed | Regressions | Where they failed |",
              "| --- | --- | --- | --- | --- | --- |"]
    for commit, macs, built, failed, back in rows:
        # The steps at least MIN_INSTALLS Macs failed at, with how many
        # games failed at each; the others together.
        pairs = [(e.get("stage") or "a step not said", e["install"]) for e in failed]
        stages, _ = shared(pairs)
        counts = Counter(stage for stage, _ in pairs)
        where = [f"{stage} {counts[stage]}" for stage, _ in stages]
        rest = len(pairs) - sum(counts[stage] for stage, _ in stages)
        if rest:
            where.append(f"other steps {rest}")
        regressions = f"{len(back)} on {macs_text(len({e['install'] for e in back}))}" if back else "0"
        lines.append(f"| `{commit}` | {macs} | {built} | {len(failed)} | {regressions} | {', '.join(where) or '–'} |")
    return lines + [""]


# A game's own failures, as Cartouche Builder names their causes
# (builder/cartouche_builder/causes.py), and those of a builder older than
# 0.5.0, which named none: not the player's files (damaged, zip, keys), nor
# the Mac's (no_space, no_room, metal), nor a commit of nxnative that breaks
# every game's app build (app_build) or splits a game's shaders otherwise than
# its profile says (tables), nor a stop or the builder's own code.
GAMES_OWN = (None, "", "nxnative", "crashed", "signal", "no_ipa")


def unbuilt(events: list[dict], first: dt.date, last: dt.date) -> dict:
    """unbuilt.json, for Cartouche Builder: the games at least MIN_INSTALLS
    Macs tried in the window, failing for reasons of the game's own, and
    none built, those of a fork of nxnative left out. For each, how many
    Macs tried and how many builds failed; the median of each Mac's longest
    attempt, in hours, when MIN_INSTALLS Macs said how long it took; and the
    step the most Macs failed at, when MIN_INSTALLS share it."""
    forks = forks_of(events)
    built = {e["game"] for e in events if e.get("name") == "builder.built" and e.get("game") and e["install"] not in forks}
    tried: dict[str, dict] = defaultdict(lambda: {"macs": {}, "failures": 0, "stages": []})
    for e in events:
        if e.get("name") != "builder.failed" or e["install"] in forks or not e.get("game") or e.get("cause") not in GAMES_OWN:
            continue
        game = tried[e["game"]]
        game["failures"] += 1
        seconds = e.get("seconds") if isinstance(e.get("seconds"), (int, float)) else 0
        game["macs"][e["install"]] = max(game["macs"].get(e["install"], 0), seconds)
        # A step not said counts for none: the app shows the step as is.
        game["stages"].append((e.get("stage") or "", e["install"]))
    games = []
    for title, game in sorted(tried.items()):
        if title in built or len(game["macs"]) < MIN_INSTALLS:
            continue
        entry: dict = {"titleId": title, "macs": len(game["macs"]), "failures": game["failures"]}
        longest = [seconds for seconds in game["macs"].values() if seconds > 0]
        if len(longest) >= MIN_INSTALLS:
            entry["hours"] = round(statistics.median(longest) / 3600, 1)
        stages, _ = shared(game["stages"])
        if stages:
            entry["stage"] = stages[0][0]
        games.append(entry)
    return {"schema": 1, "from": first.isoformat(), "to": last.isoformat(), "games": games}


def run(catalog: Path, out: Path, today: dt.date, cloudflare: Cloudflare) -> list[str]:
    """Writes the page and unbuilt.json into out; returns the lines of the
    job's summary."""
    first, last = today - dt.timedelta(days=WINDOW_DAYS), today - dt.timedelta(days=1)
    database = cloudflare.database(DATABASE)
    sessions = read(cloudflare, database, SESSIONS, first, last)
    events = read(cloudflare, database, EVENTS, first, last)
    text, summary = page(Catalog(catalog), sessions, events, first, last)
    out.mkdir(parents=True, exist_ok=True)
    (out / "README.md").write_text(text, encoding="utf-8")
    never = unbuilt(events, first, last)
    (out / "unbuilt.json").write_text(json.dumps(never, indent=2) + "\n", encoding="utf-8")
    return summary + [f"Games no Mac built, of {MIN_INSTALLS} Macs or more: {len(never['games'])}, in unbuilt.json.",
                      f"The page goes on the branch `{BRANCH}`."]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", type=Path, default=Path("catalog"))
    parser.add_argument("--out", type=Path, required=True, help="where the page is written, as README.md")
    parser.add_argument("--today", type=dt.date.fromisoformat, default=dt.datetime.now(dt.timezone.utc).date(),
                        help="the day of the run, in UTC: the sessions of the 28 days before it count")
    args = parser.parse_args(argv)

    def output(written: bool) -> None:
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
                file.write(f"written={'true' if written else 'false'}\n")

    token, account = os.environ.get("CLOUDFLARE_API_TOKEN"), os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    if not token or not account:
        print("::notice::CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are not set: no measurement was read.")
        output(False)
        return 0
    cloudflare = Cloudflare(account, token, os.environ.get("CLOUDFLARE_API") or API)
    try:
        lines = run(args.catalog, args.out, args.today, cloudflare)
    except Refused as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
            file.write("\n".join(lines) + "\n")
    output(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
