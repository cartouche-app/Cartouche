#!/usr/bin/env python3
"""Add a release of Cartouche to the source its built-in SideStore reads.

The built-in SideStore reads app/sidestore-source.json from the main branch
(CARTOUCHE_SIDESTORE_SOURCE_URL in app/config.env). When the source lists a
higher version of Cartouche than the one installed, SideStore offers the
update in My Apps, downloads the IPA, checks it and installs it over the app,
without a computer. This script adds one version to that source, from the
IPA that the release workflow (.github/workflows/release.yml) has just
published, and checks the IPA as SideStore will:

- its bundle identifier is Cartouche's, and its version is CARTOUCHE_VERSION,
  which SideStore compares with the source (VerifyAppOperation);
- its version is higher than every version the source already lists;
- the size and SHA-256 written into the source are the IPA's own, which
  SideStore checks again after downloading it.

The source lists Cartouche and nothing else: never a game.

With --own-certificate-ipa and --own-certificate-url, the version also names
the IPA a player signs on the iPhone with their own certificate
(app/scripts/own_certificate_ipa.py), its address, size and SHA-256: an
install signed that way has no SideStore to update it, and Cartouche gives
the player that address when it says the version is out
(launcher/Sources/CartoucheUpdates.swift). SideStore and the Cartouche
Installer read neither.

With --sidestore-ipa and --sidestore-url, the version also goes to the source
a player adds to their own SideStore (app/sidestore-player-source.json,
CARTOUCHE_PLAYER_SIDESTORE_SOURCE_URL), with the IPA for the player's
SideStore (app/scripts/sidestore_ipa.py, docs/decisions/147.md): the player's
SideStore installs that one, and Cartouche installed from it updates from
that source. Each source names its own IPA, never the other's.

usage: add_release.py --ipa Cartouche.ipa --url URL --notes FILE [--version X.Y.Z]
                      [--own-certificate-ipa FILE --own-certificate-url URL]
                      [--sidestore-ipa FILE --sidestore-url URL [--player-source FILE]]
                      [--date 2026-11-07T08:00:00Z] [--source FILE] [--config FILE]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r"(\d+)\.(\d+)\.(\d+)")
# Versions the source keeps, newest first. SideStore offers the first one
# this iPhone's iOS supports.
KEPT_VERSIONS = 10

# How Cartouche presents itself in its SideStore. The icon is the one the
# app carries (app/icon/), served from the main branch.
APP_ENTRY = {
    "name": "Cartouche",
    "developerName": "Cartouche contributors",
    "subtitle": "Play your own games built with nxnative",
    "localizedDescription": (
        "Cartouche runs the games you build with nxnative from your own copies, "
        "renews itself without a computer, and gives them Increased Memory Limit. "
        "It never downloads a game."
    ),
    "iconURL": "https://raw.githubusercontent.com/cartouche-app/Cartouche/main/app/icon/AppIcon.appiconset/AppIcon1024.png",
    "tintColor": "#4F46E5",
    "category": "games",
}

# The Info.plist keys of the IPA for the player's SideStore
# (app/scripts/sidestore_ipa.py), and the app group it must begin with.
SIDESTORE_MARKER = "CartoucheSideStoreInstall"
SIDESTORE_GROUP_KEY = "CartoucheAppGroup"
BUILT_IN_GROUP = "group.com.SideStore.SideStore"


class ReleaseError(Exception):
    pass


def parse_version(version: str) -> tuple[int, int, int]:
    match = VERSION.fullmatch(version)
    if not match:
        raise ReleaseError(f"not a major.minor.patch version: {version!r}")
    return tuple(int(part) for part in match.groups())


def read_config(path: Path) -> dict[str, str]:
    settings = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            settings[key.strip()] = value.strip()
    return settings


def app_info(ipa: Path) -> dict:
    """The Info.plist of the one app at the top of an IPA's Payload."""
    with zipfile.ZipFile(ipa) as archive:
        plists = [
            name for name in archive.namelist()
            if len(PurePosixPath(name).parts) == 3
            and PurePosixPath(name).parts[0] == "Payload"
            and PurePosixPath(name).parts[1].endswith(".app")
            and PurePosixPath(name).parts[2] == "Info.plist"
        ]
        if len(plists) != 1:
            raise ReleaseError(f"{ipa.name}: an IPA must hold exactly one Payload/<name>.app/Info.plist")
        return plistlib.loads(archive.read(plists[0]))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def check_build(ipa: Path, info: dict, bundle_id: str, version: str) -> None:
    """That INFO, the Info.plist of IPA, is Cartouche's at VERSION."""
    if info.get("CFBundleIdentifier") != bundle_id:
        raise ReleaseError(f"{ipa.name}: bundle identifier {info.get('CFBundleIdentifier')!r}, not Cartouche's {bundle_id!r}")
    if info.get("CFBundleShortVersionString") != version:
        raise ReleaseError(f"{ipa.name}: version {info.get('CFBundleShortVersionString')!r}, not {version!r}")
    if info.get("CFBundleVersion") != version:
        raise ReleaseError(f"{ipa.name}: build version {info.get('CFBundleVersion')!r}, not {version!r}")


def check_own_certificate_ipa(ipa: Path, bundle_id: str, version: str) -> None:
    """That IPA is the one a player signs with their own certificate, of
    this very version: in that mode, without the Cartouche Installer's key,
    and without app extensions (own_certificate_ipa.py)."""
    info = app_info(ipa)
    check_build(ipa, info, bundle_id, version)
    if info.get("CartoucheImportedSigning") is not True:
        raise ReleaseError(f"{ipa.name}: not in the mode of the player's own certificate (CartoucheImportedSigning)")
    if "CartoucheSigningHandoffKey" in info:
        raise ReleaseError(f"{ipa.name}: signed by the Cartouche Installer for one player")
    with zipfile.ZipFile(ipa) as archive:
        extensions = sorted({
            part for name in archive.namelist() for part in PurePosixPath(name).parts
            if part.endswith(".appex") or part in ("PlugIns", "Extensions", "Watch")
        })
    if extensions:
        raise ReleaseError(f"{ipa.name}: app extensions left: {', '.join(extensions)}")


def check_sidestore_ipa(ipa: Path, bundle_id: str, version: str, source_url: str) -> None:
    """That IPA is the one a player installs with their own SideStore, of
    this very version: with an app group of its own, never the one the
    player's SideStore keeps its apps in, and its updates from SOURCE_URL,
    the source it is listed in (sidestore_ipa.py)."""
    info = app_info(ipa)
    check_build(ipa, info, bundle_id, version)
    if info.get(SIDESTORE_MARKER) is not True:
        raise ReleaseError(f"{ipa.name}: not the IPA for the player's SideStore ({SIDESTORE_MARKER})")
    if info.get("CartoucheImportedSigning") or "CartoucheSigningHandoffKey" in info:
        raise ReleaseError(f"{ipa.name}: in the mode of the player's own certificate")
    group = info.get(SIDESTORE_GROUP_KEY)
    if not isinstance(group, str) or not group.startswith(BUILT_IN_GROUP + "."):
        raise ReleaseError(f"{ipa.name}: its app group {group!r} is not one of its own")
    if info.get("ALTAppGroups") != [group]:
        raise ReleaseError(f"{ipa.name}: ALTAppGroups {info.get('ALTAppGroups')!r}, not its own group alone")
    if info.get("CartoucheSourceURL") != source_url:
        raise ReleaseError(f"{ipa.name}: its updates come from {info.get('CartoucheSourceURL')!r}, "
                           f"not from the source for SideStore {source_url!r}")


def with_version(source: dict, entry: dict, bundle_id: str) -> dict:
    """SOURCE with ENTRY first among Cartouche's versions, once it is
    higher than each of them."""
    new = parse_version(entry["version"])
    apps = source.setdefault("apps", [])
    others = [app for app in apps if app.get("bundleIdentifier") != bundle_id]
    if others:
        raise ReleaseError("the source must list Cartouche and nothing else: "
                           + ", ".join(repr(app.get("bundleIdentifier")) for app in others))
    previous = apps[0].get("versions", []) if apps else []
    for release in previous:
        if parse_version(release["version"]) >= new:
            raise ReleaseError(f"the source already lists {release['version']}: a release must be higher")
    source["apps"] = [{
        **APP_ENTRY,
        "bundleIdentifier": bundle_id,
        "versions": [entry, *previous][:KEPT_VERSIONS],
    }]
    return source


def add_sidestore_release(source: dict, *, ipa: Path, url: str, notes: str, date: str,
                          bundle_id: str, version: str, source_url: str) -> dict:
    """The source for the player's SideStore with this release first, its
    IPA for the player's SideStore for an IPA."""
    if not url.startswith("https://"):
        raise ReleaseError(f"the address of the IPA for the player's SideStore must be https: {url!r}")
    parse_version(version)
    check_sidestore_ipa(ipa, bundle_id, version, source_url)
    info = app_info(ipa)
    entry = {
        "version": version,
        "date": date,
        "localizedDescription": notes.strip(),
        "downloadURL": url,
        "size": ipa.stat().st_size,
        "sha256": sha256(ipa),
    }
    if info.get("MinimumOSVersion"):
        entry["minOSVersion"] = info["MinimumOSVersion"]
    return with_version(source, entry, bundle_id)


def add_release(source: dict, *, ipa: Path, url: str, notes: str, date: str,
                bundle_id: str, version: str, own_certificate_ipa: Path | None = None,
                own_certificate_url: str | None = None) -> dict:
    """The source with this release first among Cartouche's versions."""
    if not url.startswith("https://"):
        raise ReleaseError(f"the download address must be https: {url!r}")
    if (own_certificate_ipa is None) != (own_certificate_url is None):
        raise ReleaseError("the IPA for the player's own certificate needs both its file and its address")
    if own_certificate_url is not None and not own_certificate_url.startswith("https://"):
        raise ReleaseError(f"the address of the IPA for the player's own certificate must be https: {own_certificate_url!r}")
    parse_version(version)

    info = app_info(ipa)
    check_build(ipa, info, bundle_id, version)
    if info.get("CartoucheImportedSigning"):
        raise ReleaseError(f"{ipa.name}: the IPA for the player's own certificate, not the one SideStore installs")
    if info.get(SIDESTORE_MARKER):
        raise ReleaseError(f"{ipa.name}: the IPA for the player's SideStore, not the one the built-in SideStore installs")
    if own_certificate_ipa is not None:
        check_own_certificate_ipa(own_certificate_ipa, bundle_id, version)

    entry = {
        "version": version,
        "date": date,
        "localizedDescription": notes.strip(),
        "downloadURL": url,
        "size": ipa.stat().st_size,
        "sha256": sha256(ipa),
    }
    if info.get("MinimumOSVersion"):
        entry["minOSVersion"] = info["MinimumOSVersion"]
    if own_certificate_ipa is not None:
        entry["ownCertificateDownloadURL"] = own_certificate_url
        entry["ownCertificateSize"] = own_certificate_ipa.stat().st_size
        entry["ownCertificateSHA256"] = sha256(own_certificate_ipa)
    return with_version(source, entry, bundle_id)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ipa", type=Path, required=True, help="the published Cartouche IPA")
    parser.add_argument("--url", required=True, help="where SideStore downloads it")
    parser.add_argument("--notes", type=Path, required=True, help="release notes, shown by SideStore")
    parser.add_argument("--version", help="the released version (default: CARTOUCHE_VERSION)")
    parser.add_argument("--own-certificate-ipa", type=Path,
                        help="the IPA of this version a player signs with their own certificate")
    parser.add_argument("--own-certificate-url", help="where the player downloads it")
    parser.add_argument("--sidestore-ipa", type=Path,
                        help="the IPA of this version a player installs with their own SideStore")
    parser.add_argument("--sidestore-url", help="where the player's SideStore downloads it")
    parser.add_argument("--player-source", type=Path, default=ROOT / "app" / "sidestore-player-source.json",
                        help="the source the player adds to their own SideStore")
    parser.add_argument("--date", default=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    parser.add_argument("--source", type=Path, default=ROOT / "app" / "sidestore-source.json")
    parser.add_argument("--config", type=Path, default=ROOT / "app" / "config.env")
    args = parser.parse_args(argv)

    settings = read_config(args.config)
    player_source = None
    try:
        if (args.sidestore_ipa is None) != (args.sidestore_url is None):
            raise ReleaseError("the IPA for the player's SideStore needs both its file and its address")
        version = args.version or settings["CARTOUCHE_VERSION"]
        source = json.loads(args.source.read_text(encoding="utf-8"))
        add_release(
            source,
            ipa=args.ipa,
            url=args.url,
            notes=args.notes.read_text(encoding="utf-8"),
            date=args.date,
            bundle_id=settings["CARTOUCHE_BUNDLE_ID"],
            version=version,
            own_certificate_ipa=args.own_certificate_ipa,
            own_certificate_url=args.own_certificate_url,
        )
        if args.sidestore_ipa is not None:
            player_source = json.loads(args.player_source.read_text(encoding="utf-8"))
            add_sidestore_release(
                player_source,
                ipa=args.sidestore_ipa,
                url=args.sidestore_url,
                notes=args.notes.read_text(encoding="utf-8"),
                date=args.date,
                bundle_id=settings["CARTOUCHE_BUNDLE_ID"],
                version=version,
                source_url=settings["CARTOUCHE_PLAYER_SIDESTORE_SOURCE_URL"],
            )
    except (ReleaseError, KeyError, zipfile.BadZipFile) as exc:
        print(f"add_release: {exc}", file=sys.stderr)
        return 1
    # Both sources once both are made: never one without the other.
    args.source.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{args.source.name}: Cartouche {version} added")
    if player_source is not None:
        args.player_source.write_text(json.dumps(player_source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{args.player_source.name}: Cartouche {version} added, with the IPA for the player's SideStore")
    return 0


if __name__ == "__main__":
    sys.exit(main())
