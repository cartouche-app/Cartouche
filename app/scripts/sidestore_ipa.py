#!/usr/bin/env python3
"""Make the Cartouche IPA a player installs with their own SideStore.

From the IPA of a release (app/scripts/build.sh), the IPA a player who
already has SideStore on the iPhone installs with it, from Cartouche's
source for SideStore (app/sidestore-player-source.json), without a
computer (docs/decisions/147.md). The release's IPA cannot go there as it
is: it carries LiveContainer+SideStore's app group, which the player's
SideStore registers under the same name as its own,
group.com.SideStore.SideStore.<team>. Both would then keep their app
database in the same file, and each would find the other's, newer or older,
and reset it, the list of the player's apps with it.

So this IPA is the release's with its own app group and its own source:

- group.com.SideStore.SideStore.cartouche in place of the built-in
  SideStore's group, in the entitlements of the app and of each of its
  extensions (LiveProcess, the widget), which ldid signs again: the player's
  SideStore registers the groups an app's entitlements name, as the
  built-in SideStore does when it renews Cartouche. The AltStore group,
  which Cartouche never uses, goes too. The group still begins with the
  built-in SideStore's, so that LiveContainer takes it for that SideStore's
  (app/patches/livecontainer/0018);
- in its Info.plist, CartoucheSideStoreInstall, which tells Cartouche it was
  installed this way (launcher/Sources/CartoucheOwnSignature.swift),
  CartoucheAppGroup, the group above, which LiveContainer and the built-in
  SideStore read in place of their own, ALTAppGroups with that group alone,
  and CartoucheSourceURL, the source for SideStore, where the built-in
  SideStore and Cartouche find its updates, this IPA's of each version.

Everything else is the release's, file for file, extensions included: the
player's SideStore asks whether to keep them, and keeping them on the app's
profile ("Keep App Extensions (Use Main Profile)") uses a single App ID.

usage: sidestore_ipa.py --ipa Cartouche.ipa --out Cartouche-SideStore.ipa
                        [--config app/config.env] [--ldid ldid]
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from own_certificate_ipa import app_folder, copy_info, read_config  # noqa: E402

# LiveContainer+SideStore's app group, which the release carries, and the one
# of this IPA, which begins with it.
BASE_GROUP = "group.com.SideStore.SideStore"
GROUP = BASE_GROUP + ".cartouche"
GROUPS_ENTITLEMENT = "com.apple.security.application-groups"

# The Info.plist keys this IPA adds (CartoucheOwnSignature.swift and
# LiveContainer's patch 0018 read them), and those it must not carry.
MARKER = "CartoucheSideStoreInstall"
GROUP_KEY = "CartoucheAppGroup"
SOURCE_KEY = "CartoucheSourceURL"
IMPORTED = "CartoucheImportedSigning"
HANDOFF_KEY = "CartoucheSigningHandoffKey"
CARTOUCHE_ID = "CartoucheBundleIdentifier"
# Where this IPA's source is (app/config.env).
PLAYER_SOURCE_SETTING = "CARTOUCHE_PLAYER_SIDESTORE_SOURCE_URL"


class SideStoreIPAError(Exception):
    pass


def rewritten_groups(groups: list) -> list[str]:
    """GROUPS with this IPA's group in place of the built-in SideStore's,
    with or without a team, and without AltStore's."""
    rewritten: list[str] = []
    for group in groups:
        if not isinstance(group, str):
            raise SideStoreIPAError(f"an app group is not a string: {group!r}")
        if "AltStore" in group or "rileytestut" in group:
            continue
        if group == BASE_GROUP or group.startswith(BASE_GROUP + "."):
            group = GROUP
        if group not in rewritten:
            rewritten.append(group)
    return rewritten


def entitlements(data: bytes) -> bytes | None:
    """The entitlements DATA (ldid -e) with this IPA's group, or None when
    they name no app group, and the executable stays as it is."""
    if not data.strip():
        return None
    try:
        values = plistlib.loads(data)
    except Exception as exc:  # plistlib raises several kinds
        raise SideStoreIPAError(f"entitlements that do not read: {exc}") from exc
    if not isinstance(values, dict):
        raise SideStoreIPAError("entitlements that are not a dictionary")
    groups = values.get(GROUPS_ENTITLEMENT)
    if groups is None:
        return None
    if not isinstance(groups, list):
        raise SideStoreIPAError(f"{GROUPS_ENTITLEMENT} is not a list")
    values[GROUPS_ENTITLEMENT] = rewritten_groups(groups)
    return plistlib.dumps(values, fmt=plistlib.FMT_XML, sort_keys=True)


def info_plist(data: bytes, bundle_id: str, source_url: str) -> bytes:
    """The app's Info.plist for this IPA, in the format it came in."""
    try:
        info = plistlib.loads(data)
    except Exception as exc:  # plistlib raises several kinds
        raise SideStoreIPAError(f"the app's Info.plist does not read: {exc}") from exc
    if not isinstance(info, dict):
        raise SideStoreIPAError("the app's Info.plist is not a dictionary")
    if info.get("CFBundleIdentifier") != bundle_id or info.get(CARTOUCHE_ID) != bundle_id:
        raise SideStoreIPAError(
            f"not a build of Cartouche: bundle identifier {info.get('CFBundleIdentifier')!r}, "
            f"{CARTOUCHE_ID} {info.get(CARTOUCHE_ID)!r}, not {bundle_id!r}")
    if info.get(IMPORTED) or HANDOFF_KEY in info:
        raise SideStoreIPAError("the IPA for the player's own certificate: start from the release's IPA")
    if MARKER in info:
        raise SideStoreIPAError("already the IPA for the player's SideStore: start from the release's IPA")
    info[MARKER] = True
    info[GROUP_KEY] = GROUP
    info["ALTAppGroups"] = [GROUP]
    info[SOURCE_KEY] = source_url
    binary = data.startswith(b"bplist")
    return plistlib.dumps(info, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML, sort_keys=True)


def executables(source: zipfile.ZipFile, app: str) -> dict[str, str]:
    """The executable of APP and of each of its extensions, by archive name,
    with the bundle it runs: what ldid signs again."""
    names = set(source.namelist())
    bundles = [app] + sorted({
        "/".join(PurePosixPath(name).parts[:4]) for name in names
        if len(PurePosixPath(name).parts) >= 4
        and "/".join(PurePosixPath(name).parts[:2]) == app
        and PurePosixPath(name).parts[2] == "PlugIns"
        and PurePosixPath(name).parts[3].endswith(".appex")
    })
    found = {}
    for bundle in bundles:
        info_name = f"{bundle}/Info.plist"
        if info_name not in names:
            raise SideStoreIPAError(f"{bundle} has no Info.plist")
        try:
            info = plistlib.loads(source.read(info_name))
        except Exception as exc:  # plistlib raises several kinds
            raise SideStoreIPAError(f"{info_name} does not read: {exc}") from exc
        executable = info.get("CFBundleExecutable") if isinstance(info, dict) else None
        if not isinstance(executable, str) or f"{bundle}/{executable}" not in names:
            raise SideStoreIPAError(f"{bundle}: its executable {executable!r} is not in the IPA")
        found[f"{bundle}/{executable}"] = PurePosixPath(bundle).name
    return found


def run(ldid: str, *arguments: str) -> bytes:
    try:
        done = subprocess.run([ldid, *arguments], capture_output=True, check=False)
    except OSError as exc:
        raise SideStoreIPAError(f"ldid does not run: {exc}") from exc
    if done.returncode != 0:
        raise SideStoreIPAError(f"ldid {' '.join(arguments)}: {done.stderr.decode(errors='replace').strip()}")
    return done.stdout


def signed_again(data: bytes, ldid: str, work: Path) -> bytes | None:
    """The executable DATA signed again with this IPA's group, or None when
    its entitlements name no app group."""
    binary = work / "executable"
    binary.write_bytes(data)
    rewritten = entitlements(run(ldid, "-e", str(binary)))
    if rewritten is None:
        return None
    signing = work / "entitlements.plist"
    signing.write_bytes(rewritten)
    run(ldid, f"-S{signing}", str(binary))
    if entitlements(run(ldid, "-e", str(binary))) != rewritten:
        raise SideStoreIPAError("ldid did not sign the executable with the new entitlements")
    return binary.read_bytes()


def make(ipa: Path, out: Path, bundle_id: str, source_url: str, ldid: str = "ldid") -> list[str]:
    """Writes OUT, the IPA for the player's SideStore, from the release's
    IPA. Returns the bundles it signed again."""
    if not source_url.startswith("https://"):
        raise SideStoreIPAError(f"the source for SideStore must be an https address: {source_url!r}")
    try:
        source = zipfile.ZipFile(ipa)
    except (OSError, zipfile.BadZipFile) as exc:
        raise SideStoreIPAError(f"{ipa.name} is not an IPA: {exc}") from exc
    with source, tempfile.TemporaryDirectory(prefix="sidestore-ipa-") as work:
        entries = source.infolist()
        app = app_folder([entry.filename for entry in entries])
        info_name = f"{app}/Info.plist"
        to_sign = executables(source, app)
        signed: list[str] = []
        out.parent.mkdir(parents=True, exist_ok=True)
        handle, temporary = tempfile.mkstemp(prefix=out.name, suffix=".part", dir=out.parent)
        os.close(handle)
        try:
            with zipfile.ZipFile(temporary, "w") as target:
                for entry in entries:
                    copied = copy_info(entry)
                    if entry.filename == info_name:
                        data = info_plist(source.read(entry), bundle_id, source_url)
                        copied.file_size = len(data)
                        target.writestr(copied, data)
                    elif entry.filename in to_sign:
                        data = signed_again(source.read(entry), ldid, Path(work))
                        if data is None:
                            data = source.read(entry)
                        else:
                            signed.append(to_sign[entry.filename])
                        copied.file_size = len(data)
                        target.writestr(copied, data)
                    elif entry.is_dir():
                        target.writestr(copied, b"")
                    else:
                        with source.open(entry) as reading, target.open(copied, "w") as writing:
                            shutil.copyfileobj(reading, writing, 1 << 20)
            if PurePosixPath(app).name not in signed:
                raise SideStoreIPAError("the app's entitlements name no app group: the built-in SideStore needs one")
            os.replace(temporary, out)
        except BaseException:
            Path(temporary).unlink(missing_ok=True)
            raise
    return signed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ipa", type=Path, required=True, help="the release's Cartouche IPA")
    parser.add_argument("--out", type=Path, required=True, help="the IPA for the player's SideStore")
    parser.add_argument("--config", type=Path, default=ROOT / "app" / "config.env")
    parser.add_argument("--ldid", default="ldid", help="the ldid that signs the executables again")
    args = parser.parse_args(argv)
    try:
        settings = read_config(args.config)
        signed = make(args.ipa, args.out, settings["CARTOUCHE_BUNDLE_ID"], settings[PLAYER_SOURCE_SETTING], args.ldid)
    except (SideStoreIPAError, KeyError, OSError) as exc:
        print(f"sidestore_ipa: {exc}", file=sys.stderr)
        return 1
    print(f"wrote {args.out}: app group {GROUP} in " + ", ".join(signed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
