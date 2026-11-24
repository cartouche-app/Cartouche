"""Who the games are built for, and so which nxnative builds them.

nxnative refuses a GPU that reads no BC-compressed texture, the A16's and
older (iPhone 15 and 15 Plus, iPhone 14 and earlier, the iPad with the A16
and older iPads with an A chip): every game says so on its screen. Muhammad's
fork of it, branch no-bc (FORK_URL), stores those textures otherwise on such
a GPU, BC1 to BC3 as ASTC 4x4 and the other BC formats and 3D textures
decompressed, for the games that draw with NVN and, since 22 November 2026,
with Vulkan; its OpenGL games still need BC. On a GPU that reads BC it takes
nxnative's own path: a game built from it runs there as one built from
nxnative. Cartouche tells which IPA was built that way (CartoucheBCConversion,
decisions 137 and 145).

The settings say whom the games are for (config.build_for): the iPhones
paired with this Mac, as Cartouche tells each its model and whether its GPU
reads BC when it connects (bridge.json, BridgeDevices.swift), or a model the
player chose. The games are built from the fork when one of them reads no
BC, from nxnative otherwise. A repository or branch the player chose under
Advanced (config.engine_url, engine_branch) wins over both. The games of the
iPhone are built again when the nxnative they were built from is no longer
the one in use (planner.py).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

from .config import ENGINE_BRANCH, ENGINE_URL, Config
from .i18n import t
from .paths import Paths

FORK_URL = "https://github.com/mianmuhammadse/nxnative-nobc.git"
FORK_BRANCH = "no-bc"

MODEL = re.compile(r"^(iPhone|iPad)([0-9]+),([0-9]+)$")
# The iPhones up to iPhone15,x read no BC (iPhone16,1, the iPhone 15 Pro's
# A17 Pro, is the first that does), as the telemetry's reads_bc has it.
LAST_IPHONE_WITHOUT_BC = 15
# The iPads whose GPU reads no BC, from iPad13,x on: those with an A chip
# older than the A17 Pro. The ones with an M chip, and the iPad mini with the
# A17 Pro, read them; those before iPad13,x all have an older A chip.
IPADS_WITHOUT_BC = frozenset({
    "iPad13,1", "iPad13,2",  # iPad Air (4th generation), A14
    "iPad13,18", "iPad13,19",  # iPad (10th generation), A14
    "iPad14,1", "iPad14,2",  # iPad mini (6th generation), A15
    "iPad15,7", "iPad15,8",  # iPad (A16)
})
FIRST_IPAD = 13


def is_model(value: str) -> bool:
    return bool(MODEL.match(value or ""))


def reads_bc(model: str) -> bool:
    """Whether the GPU of MODEL ("iPhone15,4") reads BC textures. Any other
    device, a Mac or one this does not know, is taken to read them."""
    found = MODEL.match(model or "")
    if not found:
        return True
    kind, major = found.group(1), int(found.group(2))
    if kind == "iPhone":
        return major > LAST_IPHONE_WITHOUT_BC
    return major >= FIRST_IPAD and model not in IPADS_WITHOUT_BC


@dataclass(frozen=True)
class Device:
    """A paired iPhone, as Cartouche told the Mac: its model, and whether
    its GPU reads BC (None from a Cartouche that said only its model, or
    nothing: an older one)."""

    name: str
    model: str = ""
    said: bool | None = None

    @property
    def reads_bc(self) -> bool | None:
        """Whether its GPU reads BC, None when it is not known."""
        if self.said is not None:
            return self.said
        return reads_bc(self.model) if is_model(self.model) else None


def paired(paths: Paths) -> list[Device]:
    """The iPhones paired with this Mac, from bridge.json: their names and
    models only, never their keys."""
    try:
        data = json.loads(paths.bridge.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    devices = data.get("devices") if isinstance(data, dict) else None
    found = []
    for device in devices if isinstance(devices, list) else []:
        if not isinstance(device, dict):
            continue
        name, model, said = device.get("name"), device.get("model"), device.get("readsBC")
        found.append(Device(
            name=name if isinstance(name, str) else "",
            model=model if isinstance(model, str) and is_model(model) else "",
            said=said if isinstance(said, bool) else None,
        ))
    return found


@dataclass(frozen=True)
class Source:
    """The nxnative the games are built from now, and why.

    kind: "nxnative" (its own), "no-bc" (Muhammad's fork, for a GPU without
    BC) or "custom" (the repository or branch chosen under Advanced). MODEL:
    the model the games are built for, chosen ("iPhone15,4") or the paired
    iPhone's that needs the fork, whose name DEVICE then is."""

    url: str
    branch: str
    kind: str
    model: str = ""
    device: str = ""

    @property
    def key(self) -> str:
        """What a build records of it (state.Build.engine)."""
        return key(self.url, self.branch)

    @property
    def fork(self) -> bool:
        return self.kind != "nxnative"


def key(url: str, branch: str) -> str:
    return f"{url.strip().removesuffix('.git').rstrip('/')}#{branch.strip()}"


def custom(config: Config) -> bool:
    """Whether the player chose another repository or branch under Advanced."""
    return key(config.engine_url, config.engine_branch) != key(ENGINE_URL, ENGINE_BRANCH)


def source(config: Config, devices: list[Device]) -> Source:
    """The nxnative to build from, for CONFIG and the paired iPhones DEVICES."""
    if custom(config):
        return Source(config.engine_url, config.engine_branch, "custom")
    if config.build_for:
        if not reads_bc(config.build_for):
            return Source(FORK_URL, FORK_BRANCH, "no-bc", model=config.build_for)
        return Source(ENGINE_URL, ENGINE_BRANCH, "nxnative", model=config.build_for)
    without = next((d for d in devices if d.reads_bc is False), None)
    if without:
        return Source(FORK_URL, FORK_BRANCH, "no-bc", model=without.model, device=without.name)
    return Source(ENGINE_URL, ENGINE_BRANCH, "nxnative")


def current(config: Config, paths: Paths) -> Source:
    return source(config, paired(paths))


def label(engine: str) -> str:
    """The nxnative ENGINE (a key()) in the player's words."""
    if engine == key(ENGINE_URL, ENGINE_BRANCH):
        return "nxnative"
    if engine == key(FORK_URL, FORK_BRANCH):
        return t("build_for.fork")
    url, _, branch = engine.partition("#")
    repository = url.removeprefix("https://github.com/").removeprefix("git@github.com:")
    return t("build_for.custom", repository=repository, branch=branch)


def recorded(build_engine: str, config: Config) -> str:
    """The nxnative a build was made from: the one it recorded, or for one
    made before builds said it, the one the settings named, which every
    build came from then."""
    return build_engine or key(config.engine_url, config.engine_branch)
