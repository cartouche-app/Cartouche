"""Checks app/scripts/sidestore_ipa.py, which makes the Cartouche IPA a player
installs with their own SideStore, from the release's IPA
(docs/decisions/147.md).

ldid is a stand-in here, which keeps an executable's entitlements as its
content: the real one runs in the App and Release workflows, on macOS.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import plistlib
import stat
import sys
import tempfile
import textwrap
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "app" / "scripts"))

import add_release  # noqa: E402
import sidestore_ipa  # noqa: E402

BUNDLE_ID = "io.github.clabeuhtegrite.cartouche"
APP = "Payload/LiveContainer.app"
DATE = (2026, 11, 24, 12, 0, 0)
EXECUTABLE = 0o100755 << 16
LINK = (stat.S_IFLNK | 0o755) << 16
SOURCE = "https://raw.githubusercontent.com/clabeuhtegrite/Cartouche/main/app/sidestore-player-source.json"
HEADER = b"\xcf\xfa\xed\xfe signed with:"

# An ldid that keeps the entitlements an executable is signed with after its
# header, as the real one keeps them in its code signature.
FAKE_LDID = textwrap.dedent(f"""\
    #!{sys.executable}
    import sys
    from pathlib import Path
    HEADER = {HEADER!r}
    option, path = sys.argv[1], Path(sys.argv[2])
    data = path.read_bytes()
    if not data.startswith(HEADER):
        sys.exit("not an executable")
    if option == "-e":
        sys.stdout.buffer.write(data[len(HEADER):])
    elif option.startswith("-S"):
        path.write_bytes(HEADER + Path(option[2:]).read_bytes())
    else:
        sys.exit("unknown option " + option)
    """)


def signed(groups=None, **more) -> bytes:
    """An executable signed with these app groups, or none."""
    values = {"application-identifier": "AAAAA11111." + BUNDLE_ID, **more}
    if groups is not None:
        values["com.apple.security.application-groups"] = groups
    return HEADER + plistlib.dumps(values)


def release_ipa(path: Path, *, binary=True, info=None, widget=None):
    """An IPA laid out as package.sh lays out Cartouche's."""
    plist = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CartoucheBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": "LiveContainer",
        "CFBundleShortVersionString": "0.16.0",
        "CFBundleVersion": "0.16.0",
        "ALTAppGroups": ["group.com.SideStore.SideStore"],
        "CartoucheSourceURL": "https://raw.githubusercontent.com/clabeuhtegrite/Cartouche/main/app/sidestore-source.json",
    }
    plist.update(info or {})
    entries = [
        (f"{APP}/", None, 0o40755 << 16),
        (f"{APP}/Info.plist", plistlib.dumps(plist, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML), 0),
        (f"{APP}/LiveContainer", signed(["group.com.SideStore.SideStore", "group.com.rileytestut.AltStore"],
                                        **{"keychain-access-groups": ["AAAAA11111.com.kdt.livecontainer.shared"]}),
         EXECUTABLE),
        (f"{APP}/CartoucheCatalog/devices.json", b'{"devices": []}', 0),
        (f"{APP}/Frameworks/SideStoreApp.framework/SideStore", b"sidestore dylib", EXECUTABLE),
        (f"{APP}/Frameworks/Current", b"SideStoreApp.framework", LINK),
        (f"{APP}/PlugIns/", None, 0o40755 << 16),
        (f"{APP}/PlugIns/LiveProcess.appex/Info.plist",
         plistlib.dumps({"CFBundleIdentifier": f"{BUNDLE_ID}.LiveProcess", "CFBundleExecutable": "LiveProcess"}), 0),
        (f"{APP}/PlugIns/LiveProcess.appex/LiveProcess", signed(["group.com.SideStore.SideStore"]), EXECUTABLE),
        (f"{APP}/PlugIns/LiveWidgetExtension.appex/Info.plist",
         plistlib.dumps({"CFBundleIdentifier": f"{BUNDLE_ID}.LiveWidget", "CFBundleExecutable": "LiveWidgetExtension"}), 0),
        (f"{APP}/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension",
         widget if widget is not None else signed(["group.com.SideStore.SideStore"]), EXECUTABLE),
    ]
    with zipfile.ZipFile(path, "w") as archive:
        for name, data, mode in entries:
            entry = zipfile.ZipInfo(name, date_time=DATE)
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.create_system = 3
            entry.external_attr = mode
            archive.writestr(entry, data or b"")
    return path


def entitlements_of(archive: zipfile.ZipFile, name: str) -> dict:
    data = archive.read(name)
    assert data.startswith(HEADER), name
    return plistlib.loads(data[len(HEADER):])


class SideStoreIPATest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.folder = Path(directory.name)
        self.ldid = self.folder / "ldid"
        self.ldid.write_text(FAKE_LDID)
        self.ldid.chmod(0o755)

    def make(self, **layout):
        ipa = release_ipa(self.folder / "Cartouche.ipa", **layout)
        out = self.folder / "out" / "Cartouche-SideStore.ipa"
        signed_again = sidestore_ipa.make(ipa, out, BUNDLE_ID, SOURCE, ldid=str(self.ldid))
        return ipa, out, signed_again

    def test_the_app_and_its_extensions_get_an_app_group_of_their_own(self):
        _, out, signed_again = self.make()
        self.assertEqual(signed_again, ["LiveContainer.app", "LiveProcess.appex", "LiveWidgetExtension.appex"])
        group = "group.com.SideStore.SideStore.cartouche"
        with zipfile.ZipFile(out) as archive:
            app = entitlements_of(archive, f"{APP}/LiveContainer")
            # Never the player's SideStore's group, nor AltStore's.
            self.assertEqual(app["com.apple.security.application-groups"], [group])
            # The rest of the entitlements stays as the release has it.
            self.assertEqual(app["keychain-access-groups"], ["AAAAA11111.com.kdt.livecontainer.shared"])
            self.assertEqual(app["application-identifier"], "AAAAA11111." + BUNDLE_ID)
            for extension in ("LiveProcess.appex/LiveProcess", "LiveWidgetExtension.appex/LiveWidgetExtension"):
                with self.subTest(extension=extension):
                    self.assertEqual(entitlements_of(archive, f"{APP}/PlugIns/{extension}")
                                     ["com.apple.security.application-groups"], [group])

    def test_the_group_is_one_livecontainer_takes_for_the_built_in_sidestores(self):
        # LiveContainer's patches 0002 and 0018 take a group that begins
        # with the built-in SideStore's, and the player's SideStore adds the
        # team after it.
        self.assertTrue(sidestore_ipa.GROUP.startswith("group.com.SideStore.SideStore."))
        self.assertNotEqual(sidestore_ipa.GROUP, sidestore_ipa.BASE_GROUP)

    def test_the_info_plist_says_how_it_was_installed_and_where_its_updates_are(self):
        for binary in (True, False):
            with self.subTest(binary=binary):
                ipa, out, _ = self.make(binary=binary)
                with zipfile.ZipFile(ipa) as before, zipfile.ZipFile(out) as after:
                    old = plistlib.loads(before.read(f"{APP}/Info.plist"))
                    data = after.read(f"{APP}/Info.plist")
                self.assertEqual(data.startswith(b"bplist"), binary, "the Info.plist keeps its format")
                info = plistlib.loads(data)
                self.assertIs(info["CartoucheSideStoreInstall"], True)
                self.assertEqual(info["CartoucheAppGroup"], "group.com.SideStore.SideStore.cartouche")
                self.assertEqual(info["ALTAppGroups"], ["group.com.SideStore.SideStore.cartouche"])
                self.assertEqual(info["CartoucheSourceURL"], SOURCE)
                for key in ("CartoucheSideStoreInstall", "CartoucheAppGroup", "ALTAppGroups", "CartoucheSourceURL"):
                    info.pop(key)
                    old.pop(key, None)
                self.assertEqual(info, old, "nothing else of the Info.plist changes")

    def test_everything_else_is_the_releases(self):
        ipa, out, _ = self.make()
        changed = {f"{APP}/Info.plist", f"{APP}/LiveContainer", f"{APP}/PlugIns/LiveProcess.appex/LiveProcess",
                   f"{APP}/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension"}
        with zipfile.ZipFile(ipa) as before, zipfile.ZipFile(out) as after:
            self.assertEqual([entry.filename for entry in after.infolist()],
                             [entry.filename for entry in before.infolist()], "the same entries, in the same order")
            for entry in before.infolist():
                copied = after.getinfo(entry.filename)
                with self.subTest(entry=entry.filename):
                    self.assertEqual(copied.date_time, entry.date_time)
                    self.assertEqual(copied.external_attr, entry.external_attr, "its permissions, or its link")
                    if entry.filename not in changed:
                        self.assertEqual(after.read(entry.filename), before.read(entry.filename))
            self.assertTrue(stat.S_ISLNK(after.getinfo(f"{APP}/Frameworks/Current").external_attr >> 16))
            self.assertTrue((after.getinfo(f"{APP}/LiveContainer").external_attr >> 16) & 0o111)

    def test_an_extension_without_an_app_group_stays_as_it_is(self):
        widget = signed()
        _, out, signed_again = self.make(widget=widget)
        self.assertNotIn("LiveWidgetExtension.appex", signed_again)
        with zipfile.ZipFile(out) as archive:
            self.assertEqual(archive.read(f"{APP}/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension"), widget)

    def test_it_starts_from_the_releases_ipa_only(self):
        for info, why in (({"CartoucheImportedSigning": True}, "own certificate"),
                          ({"CartoucheSigningHandoffKey": b"key"}, "own certificate"),
                          ({"CartoucheSideStoreInstall": True}, "already"),
                          ({"CFBundleIdentifier": "com.example.other"}, "not a build of Cartouche")):
            with self.subTest(why=why):
                ipa = release_ipa(self.folder / "Cartouche.ipa", info=info)
                out = self.folder / "refused.ipa"
                with self.assertRaisesRegex(sidestore_ipa.SideStoreIPAError, why):
                    sidestore_ipa.make(ipa, out, BUNDLE_ID, SOURCE, ldid=str(self.ldid))
                self.assertFalse(out.exists(), "nothing is left behind")
                self.assertFalse(list(self.folder.glob("refused.ipa*.part")))

    def test_the_source_must_be_https(self):
        ipa = release_ipa(self.folder / "Cartouche.ipa")
        with self.assertRaisesRegex(sidestore_ipa.SideStoreIPAError, "https"):
            sidestore_ipa.make(ipa, self.folder / "x.ipa", BUNDLE_ID, "http://example.com/source.json", ldid=str(self.ldid))

    def test_an_app_without_an_app_group_is_refused(self):
        # The built-in SideStore stops at once without one (missingAppGroup).
        ipa = self.folder / "Cartouche.ipa"
        release_ipa(ipa)
        with zipfile.ZipFile(ipa) as archive:
            entries = [(entry, archive.read(entry)) for entry in archive.infolist()]
        with zipfile.ZipFile(ipa, "w") as archive:
            for entry, data in entries:
                archive.writestr(entry, signed() if entry.filename == f"{APP}/LiveContainer" else data)
        out = self.folder / "none.ipa"
        with self.assertRaisesRegex(sidestore_ipa.SideStoreIPAError, "no app group"):
            sidestore_ipa.make(ipa, out, BUNDLE_ID, SOURCE, ldid=str(self.ldid))
        self.assertFalse(out.exists())

    def test_groups_are_rewritten_once_each(self):
        self.assertEqual(sidestore_ipa.rewritten_groups([
            "group.com.SideStore.SideStore", "group.com.SideStore.SideStore.ABCDE12345",
            "group.com.rileytestut.AltStore", "group.com.example.other",
        ]), ["group.com.SideStore.SideStore.cartouche", "group.com.example.other"])
        # Made again from its own output, nothing changes.
        self.assertEqual(sidestore_ipa.rewritten_groups(["group.com.SideStore.SideStore.cartouche"]),
                         ["group.com.SideStore.SideStore.cartouche"])

    def test_add_release_takes_the_ipa_it_makes(self):
        _, out, _ = self.make()
        add_release.check_sidestore_ipa(out, BUNDLE_ID, "0.16.0", SOURCE)

    def test_the_config_names_the_source_it_writes(self):
        settings = sidestore_ipa.read_config(ROOT / "app" / "config.env")
        url = settings[sidestore_ipa.PLAYER_SOURCE_SETTING]
        self.assertTrue(url.startswith("https://"))
        self.assertTrue(url.endswith("/app/sidestore-player-source.json"))
        self.assertNotEqual(url, settings["CARTOUCHE_SIDESTORE_SOURCE_URL"])
        self.assertTrue((ROOT / "app" / "sidestore-player-source.json").is_file())



class TheAppReadsWhatTheIPAWritesTest(unittest.TestCase):
    """The keys this IPA adds, against the code that reads them: LiveContainer
    (patch 0018), the launcher, and the built-in SideStore's reinstall
    (patch 0025), which no test on a computer runs."""

    @classmethod
    def setUpClass(cls):
        cls.livecontainer = next((ROOT / "app" / "patches" / "livecontainer").glob("0018-*.patch")).read_text(encoding="utf-8")
        cls.sidestore = next((ROOT / "app" / "patches" / "sidestore").glob("0025-*.patch")).read_text(encoding="utf-8")
        sources = ROOT / "launcher" / "Sources"
        cls.signature = (sources / "CartoucheOwnSignature.swift").read_text(encoding="utf-8")
        cls.updates = (sources / "CartoucheUpdates.swift").read_text(encoding="utf-8")
        cls.bridge = (ROOT / "launcher" / "SideStoreSupport" / "CartoucheUpdate.swift").read_text(encoding="utf-8")

    def test_livecontainer_reads_the_group_and_the_source(self):
        self.assertIn(f'[@"{sidestore_ipa.GROUP_KEY}"]', self.livecontainer)
        self.assertIn(f'[@"{sidestore_ipa.SOURCE_KEY}"]', self.livecontainer)
        # It takes the group only when it begins with the built-in
        # SideStore's, as this IPA's does.
        self.assertIn(f'@"{sidestore_ipa.BASE_GROUP}"', self.livecontainer)
        self.assertIn('hasPrefix:[base stringByAppendingString:@"."]', self.livecontainer)
        self.assertTrue(sidestore_ipa.GROUP.startswith(sidestore_ipa.BASE_GROUP + "."))
        # And hands the pairing file SideStore answers with to the launcher.
        self.assertIn("CartoucheSideStoreInstall.opened(url)", self.livecontainer)

    def test_the_launcher_knows_how_it_was_installed(self):
        self.assertIn(f'info["{sidestore_ipa.MARKER}"] as? Bool == true ? .sideStore', self.signature)

    def test_the_reinstall_reaches_the_built_in_sidestores_intent(self):
        name = "ReinstallCartoucheIntent"
        self.assertIn(f"struct {name}: AppIntent", self.sidestore)
        # The bridge finds the intent by its mangled name: module, then type.
        self.assertIn(f'identifier: "{name}"', self.bridge)
        self.assertIn(f'mangledTypeName: "9SideStore{len(name)}{name}V"', self.bridge)
        self.assertIn('@objc(reinstallCartoucheWithProgress:completion:)', self.bridge)
        self.assertIn('NSSelectorFromString("reinstallCartoucheWithProgress:completion:")', self.updates)
        # The version that runs again, not only a newer one.
        self.assertIn("latest >= running", self.sidestore)


if __name__ == "__main__":
    unittest.main()
