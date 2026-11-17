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
(28 times between Mario Kart World's tables of 7 November and 8d62601f), and
may change again before the tables are split again: when the commit before
the newest change splits the game's shaders otherwise too, the game is built
from the commit before the change before it, and so on for the DEPTH newest
changes, in the same batch; a commit that did not build the game's files is
not tried again for them. The game is held where it built (nxnative.json's
"split") until nxnative has a newer commit, which is tried in turn (the
planner, held_split), and not built again from it while its IPA is from
there already. A Mac that never built a game has its fallback too: the
commit comes from nxnative's history, not from the builder's records.
"""

from __future__ import annotations

import json
from dataclasses import asdict

from .config import write_json
from .engine import Engine
from .paths import Paths
from .state import Store, now_iso

KEPT = 20  # the broken commits remembered, and the games held (split)
DEPTH = 3  # the splitter's changes a game's split goes back through, newest first

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


def split_back(engine: Engine, title_id: str, at: str) -> list[str]:
    """The commits to build TITLE_ID from when nxnative's shader split at AT
    makes other tables than its profile's: the parent of each commit up to
    AT that changed the splitter since the profile's tables last changed,
    newest first, the DEPTH newest, as full SHAs. The newest change is the
    likeliest cause, an older one when the splitter changed again since
    without splitting the tables again. None when the tables changed with
    the splitter or after it: the game's files are then not the version the
    profile registers, and no older commit helps; nor when the profile has
    no split tables."""
    tables = engine.last_change(at, *(f"dm/games/{title_id}/{name}" for name in SPLIT_TABLES))
    if not tables:
        return []
    found: list[str] = []
    for changed in engine.changes(tables, at, SPLITTER, limit=DEPTH):
        older = engine.parent(changed)
        if older and older not in found:
            found.append(older)
    return found


def splits(paths: Paths) -> dict[str, dict]:
    """The games whose split at nxnative's commit "newest" differed from their
    profile's, by title ID: "older", the last commit before a change of the
    splitter it was built from, "built" whether the game built from it,
    "failed" those that did not build it, and "fingerprint" its files."""
    marks = _load(paths).get("split")
    if not isinstance(marks, dict):
        return {}
    return {title_id: mark for title_id, mark in marks.items() if isinstance(title_id, str) and isinstance(mark, dict)}


def mark_split(paths: Paths, title_id: str, newest: str, older: str, built: bool, fingerprint: str) -> None:
    """TITLE_ID built from OLDER at NEWEST (BUILT), or not, with the files of
    FINGERPRINT: the commits that did not build these files are kept with
    them, and forgotten once the files change."""
    data = _load(paths)
    marks = splits(paths)
    failed = tried(marks.pop(title_id, None), fingerprint)
    if not built and older not in failed:
        failed.append(older)
    marks[title_id] = {"newest": newest, "older": older, "built": built, "failed": failed[-KEPT:], "fingerprint": fingerprint, "at": now_iso()}
    data["split"] = dict(list(marks.items())[-KEPT:])
    write_json(paths.engine_state, data, mode=0o644)


def tried(mark: dict | None, fingerprint: str) -> list[str]:
    """The commits that did not build the game's files of FINGERPRINT (MARK,
    splits()): not tried again for them."""
    if not mark or mark.get("fingerprint") != fingerprint or not isinstance(mark.get("failed"), list):
        return []
    return [sha for sha in mark["failed"] if isinstance(sha, str) and sha]


def held_split(mark: dict | None, head: str, base: str | None, fingerprint: str) -> bool:
    """Whether a game built from BASE stays there at HEAD, the newest commit
    nxnative's split of its shaders differed at (MARK, splits()): it built
    from the older commit, with the same files (FINGERPRINT)."""
    return bool(
        mark and mark.get("built") and base and mark.get("newest") == head and mark.get("older") == base
        and (not mark.get("fingerprint") or not fingerprint or mark.get("fingerprint") == fingerprint)
    )
