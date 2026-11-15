#!/usr/bin/env python3
"""Download a version's IPAs again, as iPhones and the Cartouche Installer
download them, and check them against Cartouche's source.

Each IPA comes from the address the source gives, the IPA's (downloadURL)
and, when the version names it, the one for the player's own certificate
(ownCertificateDownloadURL): its size and SHA-256 must be the source's, and
those GitHub gives for the release's asset of that name.

The Release workflow runs it once the release is published, before it pushes
the branch release/v<version> (.github/workflows/release.yml). The pull
request "Source: Cartouche X" is then checked already, and can be opened as
soon as the run ends. The lines it writes with --summary say what it checked,
for that pull request's "How it was tested".

usage: check_release_downloads.py --version X.Y.Z --release RELEASE.json
                                  [--source FILE] [--summary FILE]

RELEASE.json is GitHub's release, as `gh api repos/OWNER/REPO/releases/tags/TAG`
gives it.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import sys
import time
import urllib.request
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
# A download that fails is tried again, WAIT seconds later, ATTEMPTS times in
# all: a size or a SHA-256 that differs is never tried again.
ATTEMPTS = 3
WAIT = 10
CHUNK = 1 << 20


class CheckError(Exception):
    pass


def entry(source: dict, version: str) -> dict:
    """The source's entry for VERSION."""
    for app in source.get("apps", []):
        for release in app.get("versions", []):
            if release.get("version") == version:
                return release
    raise CheckError(f"the source lists no version {version}")


def ipas(release: dict) -> list[tuple[str, str, str, int, str]]:
    """Each IPA the entry names: (what, its address's key, address, size, SHA-256)."""
    found = [("the IPA", "downloadURL", release["downloadURL"], release["size"], release["sha256"])]
    if "ownCertificateDownloadURL" in release:
        found.append(("the IPA for the player's own certificate", "ownCertificateDownloadURL",
                      release["ownCertificateDownloadURL"], release["ownCertificateSize"],
                      release["ownCertificateSHA256"]))
    return found


def download(url: str) -> tuple[int, str]:
    """The size and SHA-256 of what URL serves, its redirects followed."""
    digest, size = hashlib.sha256(), 0
    request = urllib.request.Request(url, headers={"User-Agent": "cartouche-release-check"})
    with urllib.request.urlopen(request, timeout=60) as response:
        while chunk := response.read(CHUNK):
            digest.update(chunk)
            size += len(chunk)
    return size, digest.hexdigest()


def downloaded(url: str, fetch=download, sleep=time.sleep) -> tuple[int, str]:
    """FETCH(URL), tried again on a failed download, ATTEMPTS times in all."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return fetch(url)
        except (OSError, http.client.HTTPException) as error:
            if attempt == ATTEMPTS:
                raise CheckError(f"{url} did not download, {ATTEMPTS} times: {error}") from error
            print(f"   {url} did not download ({error}): again in {WAIT} s", file=sys.stderr)
            sleep(WAIT)
    raise AssertionError("unreachable")


def short(sha256: str) -> str:
    return f"{sha256[:8]}…{sha256[-8:]}"


def check(source: dict, version: str, release: dict, fetch=download, sleep=time.sleep) -> list[str]:
    """Checks each IPA of VERSION, and gives a line for each, in the words of
    the pull request that adds it to the source."""
    assets = {asset.get("name"): asset for asset in release.get("assets", [])}
    lines = []
    for what, key, url, size, sha256 in ipas(entry(source, version)):
        name = PurePosixPath(urlsplit(url).path).name
        got_size, got_sha256 = downloaded(url, fetch, sleep)
        if got_size != size:
            raise CheckError(f"{what}, {name}: {got_size} bytes from {url}, where the source says {size}")
        if got_sha256 != sha256.lower():
            raise CheckError(f"{what}, {name}: SHA-256 {got_sha256} from {url}, where the source says {sha256}")
        asset = assets.get(name)
        if asset is None:
            raise CheckError(f"{what}: the release has no asset {name}")
        if asset.get("size") != size:
            raise CheckError(f"{what}, {name}: GitHub gives {asset.get('size')} bytes for the asset, the source {size}")
        if (asset.get("digest") or "").lower() != f"sha256:{sha256.lower()}":
            raise CheckError(f"{what}, {name}: GitHub gives {asset.get('digest')!r} for the asset, "
                             f"where the source says SHA-256 {sha256}")
        whose = "The entry's" if key == "downloadURL" else "Its own-certificate"
        lines.append(f"- {whose} size ({size:,} bytes) and SHA-256 (`{short(sha256)}`) are those of `{name}` "
                     f"downloaded again from the release by its `{key}`, and those GitHub gives for the asset.")
        print(f"{name}: {size} bytes, SHA-256 {sha256}, from {url}: as the source and GitHub say")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--version", required=True)
    parser.add_argument("--release", type=Path, required=True, help="GitHub's release, as JSON")
    parser.add_argument("--source", type=Path, default=ROOT / "app" / "sidestore-source.json")
    parser.add_argument("--summary", type=Path, help="where to write the lines for the pull request")
    args = parser.parse_args(argv)
    try:
        lines = check(json.loads(args.source.read_text(encoding="utf-8")), args.version,
                      json.loads(args.release.read_text(encoding="utf-8")))
    except CheckError as error:
        print(f"check_release_downloads.py: {error}", file=sys.stderr)
        return 1
    if args.summary:
        args.summary.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
