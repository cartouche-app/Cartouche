"""A game's pipeline archive, made for the GPUs of the player's iPhones too.

nxnative makes, for a game whose profile sets pso_mtl4 on (the Metal 4 path,
the only one that reads it on iOS), the pipeline bases of the game's shader
pairs on the Mac with metal-tt, one archive for each GPU architecture, and
puts them in its IPA (pso/<architecture>.mtl4a). A device whose GPU has one
builds no base at its first start, which takes Breath of the Wild, the only
such game on 26 November 2026, minutes on an iPhone ("Pipeline prebuild":
the first start waits for it, once). By default nxnative makes one for the
profile's pso_gpu, else for g18p, the A19 and A19 Pro of the iPhone 17
family, and none for a game without pso_mtl4 on, whose app would never read
it. Its build script takes the architectures as --gpu, which replaces that
default (docs/development.md, The pipeline archive made offline).

Cartouche tells its paired Mac its GPU's architecture as Metal names it
("applegpu_g19p") and the major version of its iOS (bridge.json,
BridgeDevices.swift, build_for.Device). The builder asks, for a game whose
profile asks for an archive, for the profile's default and the GPU of each
paired iPhone on the iOS the archive is made for: an iPhone opens only an
archive made for its own major version, the iOS SDK's by default
(DM_PSO_IOS_MIN). Four in all at most, as a profile names: each adds about
650 MB to the app on every iPhone it goes to (220 MB to the IPA) and
minutes to a first build. Decision 174.

metal-tt fails for a GPU it does not know, and nxnative then packs the app
with no archive at all, the default's too ("[RED] pipeline archive:
pso_offline.py failed"). The builder then leaves that GPU out of its builds
until Apple's tools change (refused, pipelines.json) and builds the game
again at once without it.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from .config import write_json
from .paths import Paths

# nxnative's default for a profile with pso_mtl4 on and no pso_gpu: the
# A19 and A19 Pro of the iPhone 17 family.
DEFAULT_GPU = "g18p"
# As many as a profile's pso_gpu names at most (build_ipa.sh).
MOST = 4
PREFIX = "applegpu_"
# A GPU architecture as Metal names it, with or without its prefix, as
# CartoucheBridgeDevice.isGPUArchitecture takes it.
ARCHITECTURE = re.compile(r"(applegpu_)?g[0-9]{1,3}[a-z]{0,3}")
# What nxnative says when metal-tt fails for one GPU (pso_offline.py
# compile_archive), and when the archive failed as a whole (build_ipa.sh).
FAILED_FOR = re.compile(r"metal-tt failed for (applegpu_[A-Za-z0-9]+)")
ARCHIVE_FAILED = "pipeline archive: pso_offline.py failed"


def short(name: str) -> str:
    """NAME without its prefix, as nxnative's defaults write it ("g18p")."""
    name = name.strip()
    return name[len(PREFIX):] if name.startswith(PREFIX) else name


def is_architecture(name: object) -> bool:
    return isinstance(name, str) and len(name) <= 32 and bool(ARCHITECTURE.fullmatch(name))


def profile_default(engine_root: Path, title_id: str) -> list[str]:
    """The GPUs nxnative makes the archive of TITLE_ID's IPA for by itself,
    as its profile in the checkout at ENGINE_ROOT says: its pso_gpu (one to
    four), else g18p, for a profile with pso_mtl4 on; none for another, or
    a game without a profile."""
    path = engine_root / "dm" / "games" / title_id.upper() / "game.tsv"
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    rows: dict[str, str] = {}
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, rest = line.partition("\t")
        rows.setdefault(key.strip(), rest)
    if rows.get("pso_mtl4", "off").split("\t")[0].strip() != "on":
        return []
    named = rows.get("pso_gpu", "").split()
    if 1 <= len(named) <= MOST and all(is_architecture(name) for name in named):
        return list(dict.fromkeys(short(name) for name in named))
    return [DEFAULT_GPU]


@dataclass
class Choice:
    """The GPUs a game's archive is made for: GPUS, the default's first,
    and ADDED, those of the paired iPhones among them; LEFT_OUT, the
    paired iPhones' that are not, each with why: "ios" (another major
    version than the archive's), "refused" (metal-tt of these tools does
    not know it), "most" (four already)."""

    gpus: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)
    left_out: list[tuple[str, str]] = field(default_factory=list)

    @property
    def option(self) -> str | None:
        """--gpu for nxnative's script, or None to leave its default: no
        paired iPhone adds a GPU to it."""
        return ",".join(self.gpus) if self.added else None


def choose(default: list[str], devices: list, sdk: str | None, refused: set[str] = frozenset()) -> Choice:
    """The GPUs for an archive whose profile's default is DEFAULT ([] for a
    game without one: none), for the paired iPhones DEVICES
    (build_for.Device), with an iOS SDK of version SDK ("27.2"), metal-tt
    of these tools refusing REFUSED."""
    choice = Choice(gpus=list(default))
    if not default:
        return choice
    major = _major(sdk)
    for device in devices:
        gpu = getattr(device, "gpu", "")
        if not is_architecture(gpu):
            continue
        name = short(gpu)
        if name in choice.gpus or any(name == left for left, _ in choice.left_out):
            continue
        ios = getattr(device, "ios", None)
        if major is not None and ios is not None and ios != major:
            choice.left_out.append((name, "ios"))
        elif name in refused:
            choice.left_out.append((name, "refused"))
        elif len(choice.gpus) >= MOST:
            choice.left_out.append((name, "most"))
        else:
            choice.gpus.append(name)
            choice.added.append(name)
    return choice


def _major(version: str | None) -> int | None:
    found = re.match(r"\s*([0-9]+)", version or "")
    return int(found.group(1)) if found else None


@dataclass
class Watch:
    """What nxnative said of the archive while it built (on_message): the
    GPUs metal-tt failed for, and whether the archive failed as a whole."""

    failed: list[str] = field(default_factory=list)
    archive_failed: bool = False

    def read(self, message: str) -> None:
        for found in FAILED_FOR.finditer(message):
            name = short(found.group(1))
            if name not in self.failed:
                self.failed.append(name)
        if ARCHIVE_FAILED in message:
            self.archive_failed = True

    def refused(self, choice: Choice) -> list[str]:
        """The paired iPhones' GPUs of CHOICE that cost the whole archive."""
        return [name for name in choice.added if name in self.failed] if self.archive_failed else []


# ---- What metal-tt of these tools refused --------------------------------------


def _file(paths: Paths) -> Path:
    return paths.root / "pipelines.json"


def refused(paths: Paths, toolchain: str) -> set[str]:
    """The GPUs metal-tt refused with the tools TOOLCHAIN (toolchain.identity):
    none once they changed."""
    try:
        data = json.loads(_file(paths).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    if not isinstance(data, dict) or data.get("toolchain") != toolchain:
        return set()
    return {short(name) for name in data.get("refused") or [] if is_architecture(name)}


def refuse(paths: Paths, toolchain: str, names: list[str]) -> None:
    """Keeps NAMES among the GPUs metal-tt of TOOLCHAIN refuses."""
    kept = refused(paths, toolchain) | {short(name) for name in names if is_architecture(name)}
    write_json(_file(paths), {"toolchain": toolchain, "refused": sorted(kept)})
