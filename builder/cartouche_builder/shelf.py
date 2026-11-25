"""The games' build folders kept on a NAS between two builds (decision 163).

nxnative builds a game in its build folder, and reads at once the files it
has just written there: on a NAS's share, macOS's SMB client fails it (a
player's Mac, 25 November: "OSError: [Errno 9] Bad file descriptor" as
nxnative opened the RomFS it had just extracted, then "[Errno 5]
Input/output error"; every build failed). The build folders chosen on a NAS
are therefore where the builder KEEPS them, never where it builds: a game is
built in the builder's own folder on this Mac, its build folder brought back
from the NAS first, with what its next build reuses (its shader caches, its
app's build), and sent back once built, leaving this Mac's disk. What
nxnative makes again in minutes does not travel: the game's extracted files
and its converted packages.

On the NAS a build folder is replaced whole, never half: it is written beside
the old one (<title ID>_build.incoming), which goes once the new one is
there. Each one kept has a note in .cartouche-builder/, with when it was kept
and its size by part, which the Storage page reads instead of measuring the
NAS's files again (minutes over SMB for a large game).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import time
from pathlib import Path
from typing import Callable

from . import shares
from .workspace import EXTRACTED, NOTES, OWN_FOLDER, remove_tree

# The parts of a build folder that stay on the Mac (and go with it): made
# again in minutes, as big as the game. The rest travels.
LEFT = frozenset((*EXTRACTED, "nsp"))
INCOMING = ".incoming"
OLD = ".old"
# The filesystems of a NAS's share, as `mount` names them.
NETWORK = frozenset(("smbfs", "nfs", "afpfs", "webdav", "cifs", "ftp"))
# "//player@nas.local/Games on /Volumes/Games (smbfs, nodev, nosuid, mounted by player)"
MOUNT_LINE = re.compile(r"^.+? on (?P<point>/.*?) \((?P<kind>[\w.-]+)")


class Stopped(Exception):
    """A copy to or from the NAS stopped half-way, as the batch was: the
    folder it was replacing is as it was."""


def on_network(path: Path, known: dict[str, str] | None = None, mounted: str | None = None) -> bool:
    """Whether PATH is on a NAS's share: under one of the KNOWN shares' mount
    points (the player's, mounted or not), or on a filesystem of the network
    as `mount` says it (MOUNTED: what it said)."""
    text = str(path)
    for point in known or {}:
        if text == point or text.startswith(point.rstrip("/") + "/"):
            return True
    if mounted is None:
        found = shares.mount_text()
        if found is None:
            return False
        mounted = found
    best = ""
    kind = ""
    for line in mounted.splitlines():
        match = MOUNT_LINE.match(line.strip())
        if not match:
            continue
        point = match.group("point")
        if (text == point or text.startswith(point.rstrip("/") + "/") or point == "/") and len(point) >= len(best):
            best, kind = point, match.group("kind").lower()
    return kind in NETWORK


class Shelf:
    """The build folders kept in ROOT, a folder on a NAS."""

    def __init__(self, root: Path):
        self.root = root

    def folder(self, name: str) -> Path:
        return self.root / name

    def _note(self, name: str) -> Path:
        return self.root / NOTES / f"{name}.json"

    def note(self, name: str) -> dict | None:
        """What the note of the build folder NAME says: when it was kept, its
        size and its parts' sizes."""
        try:
            data = json.loads(self._note(name).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        if not isinstance(data, dict) or data.get("folder") != name:
            return None
        return data

    def kept_at(self, name: str) -> float | None:
        data = self.note(name) or {}
        kept = data.get("kept")
        return float(kept) if isinstance(kept, (int, float)) and not isinstance(kept, bool) else None

    def fetch(self, local: Path, used: float | None, stopped: Callable[[], bool] | None = None) -> bool:
        """Brings back to LOCAL, a game's build folder on this Mac, the one the
        NAS keeps of it: when this Mac has none, or one older than the NAS's
        (USED: when the builder last used LOCAL, from its note). Whether it
        came. Raises OSError when the NAS's could not be read, Stopped when
        STOPPED says so between two files: LOCAL is then as it was."""
        source = self.folder(local.name)
        if not source.is_dir() or source.is_symlink():
            return False
        kept = self.kept_at(local.name)
        if local.exists() and used is not None and (kept is None or kept <= used):
            return False
        incoming = local.with_name(local.name + INCOMING)
        remove_tree(incoming)
        try:
            shutil.copytree(source, incoming, symlinks=True, ignore=_top_left_out(source), copy_function=_copy(stopped))
        except BaseException:
            remove_tree(incoming)
            raise
        remove_tree(local)
        incoming.rename(local)
        return True

    def keep(self, local: Path, parts: dict[str, int], stopped: Callable[[], bool] | None = None) -> int:
        """Sends LOCAL, a game's build folder on this Mac, to the NAS in place
        of the one it kept, without what does not travel (LEFT); PARTS, its
        parts' sizes (storage.parts). The bytes kept. Raises OSError when the
        NAS did not take it, Stopped when STOPPED says so between two files:
        what it kept before stays."""
        self.root.mkdir(parents=True, exist_ok=True)
        target = self.folder(local.name)
        incoming = target.with_name(target.name + INCOMING)
        old = target.with_name(target.name + OLD)
        remove_tree(incoming)
        try:
            shutil.copytree(local, incoming, symlinks=True, ignore=_top_left_out(local), copy_function=_copy(stopped))
        except BaseException:
            remove_tree(incoming)
            raise
        remove_tree(old)
        if target.exists():
            target.rename(old)
        incoming.rename(target)
        remove_tree(old)
        kept = {category: size for category, size in parts.items() if size and not _left_category(category)}
        size = sum(kept.values())
        note = self._note(local.name)
        note.parent.mkdir(parents=True, exist_ok=True)
        now = time.time()
        note.write_text(json.dumps({"folder": local.name, "kept": now, "used": now, "size": size, "parts": kept}) + "\n", encoding="utf-8")
        return size

    def noted_size(self, name: str) -> int | None:
        """The bytes of the build folder NAME, from its note."""
        size = (self.note(name) or {}).get("size")
        return size if isinstance(size, int) and not isinstance(size, bool) else None

    def dropped(self, folder: Path, categories: tuple[str, ...]) -> None:
        """Notes that FOLDER no longer holds its parts of CATEGORIES (its
        extracted files, freed from the Storage page)."""
        data = self.note(folder.name)
        if data is None or not isinstance(data.get("parts"), dict):
            return
        parts = {category: size for category, size in data["parts"].items() if category not in categories}
        data.update(parts=parts, size=sum(size for size in parts.values() if isinstance(size, int)))
        try:
            self._note(folder.name).write_text(json.dumps(data) + "\n", encoding="utf-8")
        except OSError:
            pass

    def note_sizes(self, folder: Path, parts: dict[str, int]) -> None:
        """Keeps PARTS, the parts' sizes of FOLDER measured once, in its note:
        the next measure reads them there."""
        note = self._note(folder.name)
        try:
            note.parent.mkdir(parents=True, exist_ok=True)
            when = (self.note(folder.name) or {}).get("used") or folder.stat().st_mtime
            note.write_text(json.dumps({"folder": folder.name, "kept": when, "used": when, "size": sum(parts.values()), "parts": parts}) + "\n",
                            encoding="utf-8")
        except OSError:
            pass


def _left_category(category: str) -> bool:
    """Whether a part's category (storage.CATEGORIES) is one that stays on the Mac."""
    return category in ("extracted", "packages", "temporary")


def _copy(stopped: Callable[[], bool] | None):
    """For shutil.copytree: copies a file, unless STOPPED says to stop."""

    def copy(source: str, target: str) -> str:
        if stopped is not None and stopped():
            raise Stopped()
        return shutil.copy2(source, target)

    return copy


def _top_left_out(root: Path):
    """For shutil.copytree from ROOT: its top's parts that do not travel."""
    top = os.path.normpath(str(root))

    def ignore(folder: str, names: list[str]) -> set[str]:
        if os.path.normpath(folder) != top:
            return set()
        return {name for name in names if name in LEFT}

    return ignore


def of(config, paths) -> Shelf | None:
    """The shelf of CONFIG's build folders: the folder chosen, when it is on
    a NAS; None when the builds keep their folders where they are built."""
    chosen = config.path("workspace")
    if chosen is None or not on_network(chosen, config.shares):
        return None
    return Shelf(chosen)


def build_root(config, paths, shelf: Shelf | None) -> Path:
    """Where the games are built: the folder chosen, unless it is a NAS's,
    whose builds are on this Mac, in the builder's own folder."""
    return paths.workspace if shelf is not None else config.workspace_path(paths)
