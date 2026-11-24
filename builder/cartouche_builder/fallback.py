"""nxnative's newest commit, when it does not build: the last one that did.

nxnative has no releases, and a commit on its branch can break every game's
build: on 11 November 2026, four commits in a row did not link the iOS app
(the "app build" stage), and every build of that night failed.

A batch builds from the branch's newest commit. When a game's app build
fails there and an older commit of the branch built a game on this Mac (the
good one, from the builder's records), the batch goes to the good commit
once no other game builds, and builds that game again from it, alone. If it
builds, the newest commit is marked broken here (nxnative.json), the rest of
the batch builds from the good one, and so do the next batches (survey's
hold), until the branch has a newer commit, which is tried in turn. If it
does not build either, the newest commit is not the cause: the batch goes
back to it, and the game's failure is recorded as any other.

A commit can also break one game's build, not every game's: nxnative's
shader split (dm/gfx/tools/shader_split.py) checks the tables it makes of a
game's shaders against those of the game's profile (dm/games/<ID>/), which
were split when the profile was registered. Its 8d62601f of 16 November 2026
kept the first copy of a shader that main holds twice instead of the last
one, and split again the tables of the one game it was about: from then on,
Mario Kart World's base game and others stopped at "shader split" ("the
split shader tables differ from game profile ..."), on every Mac. nxnative's
own words name the two causes: these files are not the version the profile
registers, or its splitter reads them differently now and the profile's
tables were not split again. When the splitter changed after the profile's
tables did (split_back), the game is built again from the commit before that
change, alone, once no other game builds, its Mac app too; then the batch
goes back to the commit the others build from. The splitter changes often
(28 times between Mario Kart World's tables of 7 November and 8d62601f, 33
more between 19 and 24 November), and may change again many times before the
tables are split again: when the commit before the newest change splits the
game's shaders otherwise too, the game is built from the commit before an
older change, in the same batch (split_order). A Mac that never built a game
has its fallback too: the commit comes from nxnative's history, not from the
builder's records.

Which older commits, and in what order. With DEPTH 3, the fallback went back
through the three newest changes only: after nxnative changed its splitter
twice more on the morning of 19 November, the commit before 8d62601f, the one
that had built seven games (Final Fantasy Resonance, Fire Emblem: Three
Houses, Triangle Strategy and others) on players' Macs, was out of its reach:
building those games again failed, on the Macs that had built them from it
too (30 failures at "shader split" on 9 Macs on 19 and 20 November, until
nxnative's c9b12271 of 21 November read their shaders as before). Now:
- every change since the tables counts, and the commits before them that hold
  the same splitter are tried once (the newest), none that holds the newest
  commit's (split_back);
- what this Mac learnt is kept with the game's files (nxnative.json's
  "split"): the commits whose split of them differed ("differ", the newest
  ones it was tried at among them), and any commit after one of them holds
  its splitter or a later one, so it is not tried; those that failed them
  otherwise than by their split ("otherwise"), which are too old for this
  Mac, and so are the commits before them; and those that did not build
  them at all ("failed"), not tried again;
- a game this Mac built from these files after its tables (its IPA, its Mac
  app, or the commit its split last built from) goes back to that commit, at
  most DEPTH newer ones tried first: there, its IPA stays as it is, however
  many times the splitter changed since;
- a game this Mac never built goes back through the rest newest first, the
  DEPTH newest one after the other, then each twice as far back as the one
  before, then the oldest (gallop): a few builds find a commit that splits
  it right however many changes ago its splitter broke, and the next time
  the game is built, the commits between it and the newest that did not are
  tried in turn.
The game is held where it built (nxnative.json's "split") until nxnative has
a newer commit, which is tried in turn (the planner, held_split), and not
built again from it while its IPA is from there already.
"""

from __future__ import annotations

import json
from dataclasses import asdict

from .config import write_json
from .engine import Engine
from .paths import Paths
from .state import Store, now_iso

KEPT = 20  # the broken commits remembered, and the games held (split)
DEPTH = 3  # the newest changes of the splitter a game's split goes back through one after the other

# nxnative's shader split, and the tables of a game's profile it is checked
# against (scripts/build_ipa_from_nsp.py: SPLIT_TABLES, split_shaders).
SPLITTER = "dm/gfx/tools/shader_split.py"
SPLIT_TABLES = ("shader_facts_manual.tsv", "shader_map.tsv", "shader_facts.tsv", "shader_pairs.tsv", "pso_pairs.tsv")


def _load(paths: Paths) -> dict:
    try:
        data = json.loads(paths.engine_state.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def broken(paths: Paths) -> dict[str, dict]:
    """The commits whose app build failed where the good one built, by full
    SHA: {"at": when, "good": the commit the builder went to}."""
    marks = _load(paths).get("broken")
    if not isinstance(marks, dict):
        return {}
    return {sha: mark for sha, mark in marks.items() if isinstance(sha, str) and isinstance(mark, dict)}


def mark_broken(paths: Paths, commit: str, good: str) -> None:
    data = _load(paths)
    marks = broken(paths)
    marks.pop(commit, None)
    marks[commit] = {"at": now_iso(), "good": good}
    data["broken"] = dict(list(marks.items())[-KEPT:])
    write_json(paths.engine_state, data, mode=0o644)


def held(engine: Engine, paths: Paths, newest: str) -> str | None:
    """The commit to stay on when NEWEST, the branch's newest, is marked
    broken: the good one it was marked with, while the checkout has it."""
    mark = broken(paths).get(newest)
    good = mark.get("good") if mark else None
    return engine.resolve(good) if isinstance(good, str) and good else None


def good(engine: Engine, store: Store, paths: Paths, before: str) -> str | None:
    """The newest commit a game was built from on this Mac (a build of the
    builder's, its last or an earlier one) that is older than BEFORE on its
    branch and not marked broken: its full SHA, or None."""
    marks = broken(paths)
    builds: list[tuple[str, str]] = []
    for record in store.all().values():
        for build in ([asdict(record.build)] if record.build else []) + record.history:
            commit, when = build.get("commit"), build.get("built_at")
            if build.get("origin", "builder") == "builder" and not build.get("dirty") and isinstance(commit, str) and commit and isinstance(when, str):
                builds.append((when, commit))
    seen: set[str] = set()
    for _when, commit in sorted(builds, reverse=True):
        sha = engine.resolve(commit)
        if not sha or sha in seen:
            continue
        seen.add(sha)
        if sha != before and sha not in marks and engine.is_ancestor(sha, before):
            return sha
    return None


# ---- One game's shaders, split otherwise than its profile says -----------


def _tables(engine: Engine, title_id: str, at: str) -> str | None:
    return engine.last_change(at, *(f"dm/games/{title_id}/{name}" for name in SPLIT_TABLES))


def split_back(engine: Engine, title_id: str, at: str) -> list[str]:
    """The commits to build TITLE_ID from when nxnative's shader split at AT
    makes other tables than its profile's: the parent of each commit up to
    AT that changed the splitter since the profile's tables last changed,
    newest first, as full SHAs; of those that hold the same splitter, the
    newest, and none that holds AT's, which splits them as AT does. The
    newest change is the likeliest cause, an older one when the splitter
    changed again since without splitting the tables again. None when the
    tables changed with the splitter or after it: the game's files are then
    not the version the profile registers, and no older commit helps; nor
    when the profile has no split tables."""
    tables = _tables(engine, title_id, at)
    if not tables:
        return []
    revisions = engine.revisions(tables, at, SPLITTER)
    held = {revisions[0][3]} if revisions and revisions[0][3] else set()
    found: list[str] = []
    for _changed, older, before, _after in revisions:
        if not older or older in found or (before and before in held):
            continue
        if before:
            held.add(before)
        found.append(older)
    return found


def split_order(engine: Engine, title_id: str, at: str, candidates: list[str], mark: dict | None, fingerprint: str,
                built: list[str] = ()) -> tuple[list[str], str | None]:
    """CANDIDATES (split_back) to build TITLE_ID's files of FINGERPRINT from,
    in that order, after its split at AT differed, with what MARK (splits())
    and BUILT (the commits its IPA and Mac app were built from, with these
    files) say of them; and the newest commit known to build these files
    after the profile's tables, which ends the order, or None (see the
    module's docstring)."""
    if not candidates:
        return [], None
    tables = _tables(engine, title_id, at)
    if not tables:
        return [], None
    known = mark if mark and mark.get("fingerprint") == fingerprint else {}
    failed = set(tried(mark, fingerprint))

    def full(commits) -> list[str]:
        # Full SHAs, after the profile's tables and up to AT.
        out: list[str] = []
        for commit in commits:
            sha = engine.resolve(commit) if isinstance(commit, str) and commit else None
            if sha and sha not in out and (sha == tables or engine.is_ancestor(tables, sha)) and engine.is_ancestor(sha, at):
                out.append(sha)
        return out

    good = [sha for sha in full([*built, known.get("older") if known.get("built") else None]) if sha not in failed and sha != at]
    newest = next((sha for sha in good if not any(other != sha and engine.is_ancestor(sha, other) for other in good)), None)
    # A commit whose split differed, unless the game built from these files
    # at a newer one since: nxnative fixed it in between.
    differ = [sha for sha in full([at, known.get("newest"), *listed(known, "differ")]) if not any(engine.is_ancestor(sha, g) for g in good)]
    ruled = set(failed)
    for sha in differ:
        ruled |= {sha} | engine.descendants(sha, at)
    if newest:
        later = engine.descendants(newest, at)
        return [older for older in candidates if older in later and older not in ruled][:DEPTH] + [newest], newest
    for sha in full(listed(known, "otherwise")):
        ruled |= engine.ancestors(sha, tables)
    return gallop([older for older in candidates if older not in ruled]), None


def gallop(commits: list[str]) -> list[str]:
    """COMMITS, newest first, to try in turn: the DEPTH newest, then each twice
    as far back as the one before, then the oldest."""
    picked: list[str] = []
    index = 0
    while index < len(commits):
        picked.append(commits[index])
        index = index + 1 if index + 1 < DEPTH else max(index * 2, index + 1)
    if commits and picked[-1] != commits[-1]:
        picked.append(commits[-1])
    return picked


def splits(paths: Paths) -> dict[str, dict]:
    """The games whose split at nxnative's commit "newest" differed from their
    profile's, by title ID: "older", the last commit before a change of the
    splitter it was built from, "built" whether the game built from it,
    "fingerprint" its files, and of the commits tried with these files:
    "failed" those that did not build them, "differ" those whose split of
    them differed (the "newest" ones among them), "otherwise" those that
    failed them otherwise."""
    marks = _load(paths).get("split")
    if not isinstance(marks, dict):
        return {}
    return {title_id: mark for title_id, mark in marks.items() if isinstance(title_id, str) and isinstance(mark, dict)}


def mark_split(paths: Paths, title_id: str, newest: str, older: str, built: bool, fingerprint: str, split: bool = True) -> None:
    """TITLE_ID built from OLDER at NEWEST (BUILT), or not, by its split
    (SPLIT) or otherwise, with the files of FINGERPRINT: the commits tried
    for these files are kept with them, and forgotten once the files
    change."""
    data = _load(paths)
    marks = splits(paths)
    mark = marks.pop(title_id, None)
    failed = tried(mark, fingerprint)
    differ, otherwise = listed(mark, "differ", fingerprint), listed(mark, "otherwise", fingerprint)
    # The newest commit of the mark before is one whose split differed too.
    for sha in ([mark.get("newest")] if mark and mark.get("fingerprint") == fingerprint else []) + [newest]:
        if isinstance(sha, str) and sha and sha not in differ:
            differ.append(sha)
    if not built:
        if older not in failed:
            failed.append(older)
        kind = differ if split else otherwise
        if older not in kind:
            kind.append(older)
    marks[title_id] = {"newest": newest, "older": older, "built": built, "failed": failed[-KEPT:], "differ": differ[-KEPT:],
                       "otherwise": otherwise[-KEPT:], "fingerprint": fingerprint, "at": now_iso()}
    data["split"] = dict(list(marks.items())[-KEPT:])
    write_json(paths.engine_state, data, mode=0o644)


def tried(mark: dict | None, fingerprint: str) -> list[str]:
    """The commits that did not build the game's files of FINGERPRINT (MARK,
    splits()): not tried again for them."""
    return listed(mark, "failed", fingerprint)


def listed(mark: dict | None, key: str, fingerprint: str | None = None) -> list[str]:
    """MARK's list KEY (splits()), when its files are those of FINGERPRINT
    (None: whatever its files)."""
    if not mark or (fingerprint is not None and mark.get("fingerprint") != fingerprint) or not isinstance(mark.get(key), list):
        return []
    return [sha for sha in mark[key] if isinstance(sha, str) and sha]


def held_split(mark: dict | None, head: str, base: str | None, fingerprint: str) -> bool:
    """Whether a game built from BASE stays there at HEAD, the newest commit
    nxnative's split of its shaders differed at (MARK, splits()): it built
    from the older commit, with the same files (FINGERPRINT)."""
    return bool(
        mark and mark.get("built") and base and mark.get("newest") == head and mark.get("older") == base
        and (not mark.get("fingerprint") or not fingerprint or mark.get("fingerprint") == fingerprint)
    )
