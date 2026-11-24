"""Checks app/scripts/check_release_downloads.py, which downloads a version's
IPAs again from the addresses Cartouche's source gives, as the Release
workflow does before it proposes the source, against a server of its own on
127.0.0.1 that redirects as GitHub does.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import contextlib
import copy
import hashlib
import http.server
import io
import json
import re
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "app" / "scripts"))

import check_release_downloads as check  # noqa: E402

IPA = b"PK\x03\x04 Cartouche 0.2.0" * 1000
OWN = b"PK\x03\x04 Cartouche 0.2.0 for the player's own certificate" * 700
SIDESTORE = b"PK\x03\x04 Cartouche 0.2.0 for the player's SideStore" * 800


class Releases(http.server.BaseHTTPRequestHandler):
    """GitHub's releases as the source's addresses reach them: under the
    repository's first owner, redirected to where it lives now."""

    files = {}
    failures = {}
    asked = []

    def do_GET(self):
        self.asked.append(self.path)
        moved = re.fullmatch(r"/clabeuhtegrite/Cartouche/releases/download/(.+)", self.path)
        if moved:
            self.send_response(301)
            self.send_header("Location", f"/cartouche-app/Cartouche/releases/download/{moved.group(1)}")
            self.end_headers()
            return
        name = self.path.rsplit("/", 1)[-1]
        if self.failures.get(name, 0) > 0 or name not in self.files:
            self.failures[name] = self.failures.get(name, 0) - 1
            self.send_error(404)
            return
        body = self.files[name]
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class CheckReleaseDownloadsTest(unittest.TestCase):
    def setUp(self):
        Releases.files = {"Cartouche-0.2.0.ipa": IPA, "Cartouche-0.2.0-Own-Certificate.ipa": OWN,
                          "Cartouche-0.2.0-SideStore.ipa": SIDESTORE}
        Releases.failures = {}
        Releases.asked = []
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Releases)
        threading.Thread(target=self.server.serve_forever, args=(0.05,), daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        base = f"http://127.0.0.1:{self.server.server_port}/clabeuhtegrite/Cartouche/releases/download/v0.2.0"
        self.entry = {
            "version": "0.2.0",
            "downloadURL": f"{base}/Cartouche-0.2.0.ipa",
            "size": len(IPA),
            "sha256": sha256(IPA),
            "ownCertificateDownloadURL": f"{base}/Cartouche-0.2.0-Own-Certificate.ipa",
            "ownCertificateSize": len(OWN),
            "ownCertificateSHA256": sha256(OWN),
        }
        older = {"version": "0.1.3", "downloadURL": f"{base}/Cartouche-0.1.3.ipa", "size": 2, "sha256": "cd"}
        self.source = {"apps": [{"bundleIdentifier": "io.github.clabeuhtegrite.cartouche",
                                 "versions": [self.entry, older]}]}
        self.release = {"tag_name": "v0.2.0", "assets": [
            {"name": "Cartouche-0.2.0.ipa", "size": len(IPA), "digest": f"sha256:{sha256(IPA)}"},
            {"name": "Cartouche-0.2.0-Own-Certificate.ipa", "size": len(OWN), "digest": f"sha256:{sha256(OWN)}"},
            {"name": "Cartouche-0.2.0-SideStore.ipa", "size": len(SIDESTORE), "digest": f"sha256:{sha256(SIDESTORE)}"},
        ]}
        self.player_source = {"apps": [{"bundleIdentifier": "io.github.clabeuhtegrite.cartouche", "versions": [{
            "version": "0.2.0", "downloadURL": f"{base}/Cartouche-0.2.0-SideStore.ipa",
            "size": len(SIDESTORE), "sha256": sha256(SIDESTORE),
        }]}]}
        self.slept = []

    def check(self, version="0.2.0", release=None):
        # What it says on the way stays out of the tests' output.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return check.check(self.source, version, release or self.release, sleep=self.slept.append)

    def test_both_ipas_download_as_the_source_and_github_say(self):
        lines = self.check()
        self.assertEqual(lines, [
            f"- The entry's size ({len(IPA):,} bytes) and SHA-256 (`{sha256(IPA)[:8]}…{sha256(IPA)[-8:]}`) are "
            "those of `Cartouche-0.2.0.ipa` downloaded again from the release by its `downloadURL`, and those "
            "GitHub gives for the asset.",
            f"- Its own-certificate size ({len(OWN):,} bytes) and SHA-256 (`{sha256(OWN)[:8]}…{sha256(OWN)[-8:]}`) "
            "are those of `Cartouche-0.2.0-Own-Certificate.ipa` downloaded again from the release by its "
            "`ownCertificateDownloadURL`, and those GitHub gives for the asset.",
        ])
        # From the addresses the source gives, redirected as GitHub does;
        # never the older version's.
        self.assertEqual(Releases.asked, [
            "/clabeuhtegrite/Cartouche/releases/download/v0.2.0/Cartouche-0.2.0.ipa",
            "/cartouche-app/Cartouche/releases/download/v0.2.0/Cartouche-0.2.0.ipa",
            "/clabeuhtegrite/Cartouche/releases/download/v0.2.0/Cartouche-0.2.0-Own-Certificate.ipa",
            "/cartouche-app/Cartouche/releases/download/v0.2.0/Cartouche-0.2.0-Own-Certificate.ipa",
        ])
        self.assertEqual(self.slept, [])

    def test_an_ipa_that_is_not_the_sources_is_refused(self):
        cases = {
            "a byte changed": ("files", "Cartouche-0.2.0.ipa", IPA[:-1] + b"!", "SHA-256"),
            "cut short": ("files", "Cartouche-0.2.0-Own-Certificate.ipa", OWN[:-5], "bytes"),
        }
        for what, (_, name, data, said) in cases.items():
            with self.subTest(what):
                Releases.files = {"Cartouche-0.2.0.ipa": IPA, "Cartouche-0.2.0-Own-Certificate.ipa": OWN, name: data}
                with self.assertRaisesRegex(check.CheckError, said):
                    self.check()
        # Never tried again: the same bytes would come back.
        self.assertEqual(self.slept, [])

    def test_github_must_give_the_same_for_the_assets(self):
        cases = {
            "another SHA-256": lambda assets: assets[0].update(digest=f"sha256:{sha256(b'other')}"),
            "no SHA-256": lambda assets: assets[1].update(digest=None),
            "another size": lambda assets: assets[1].update(size=len(OWN) + 1),
            "no asset": lambda assets: assets.pop(0),
        }
        for what, change in cases.items():
            with self.subTest(what):
                release = copy.deepcopy(self.release)
                change(release["assets"])
                with self.assertRaises(check.CheckError):
                    self.check(release=release)

    def test_a_download_that_fails_is_tried_again(self):
        Releases.failures = {"Cartouche-0.2.0.ipa": 1}
        self.assertEqual(len(self.check()), 2)
        self.assertEqual(self.slept, [check.WAIT])
        Releases.failures = {"Cartouche-0.2.0-Own-Certificate.ipa": check.ATTEMPTS}
        self.slept.clear()
        with self.assertRaisesRegex(check.CheckError, f"did not download, {check.ATTEMPTS} times"):
            self.check()
        self.assertEqual(self.slept, [check.WAIT] * (check.ATTEMPTS - 1))

    def test_a_version_without_the_ipa_for_the_players_own_certificate_checks_its_ipa(self):
        for key in ("ownCertificateDownloadURL", "ownCertificateSize", "ownCertificateSHA256"):
            del self.entry[key]
        self.assertEqual(len(self.check()), 1)
        self.assertNotIn("/cartouche-app/Cartouche/releases/download/v0.2.0/Cartouche-0.2.0-Own-Certificate.ipa",
                         Releases.asked)

    def test_the_source_for_the_players_sidestore_checks_its_own_ipa(self):
        with contextlib.redirect_stdout(io.StringIO()):
            lines = check.check(self.player_source, "0.2.0", self.release, sleep=self.slept.append, player=True)
        self.assertEqual(lines, [
            f"- The SideStore source's size ({len(SIDESTORE):,} bytes) and SHA-256 "
            f"(`{sha256(SIDESTORE)[:8]}…{sha256(SIDESTORE)[-8:]}`) are those of `Cartouche-0.2.0-SideStore.ipa` "
            "downloaded again from the release by its `downloadURL`, and those GitHub gives for the asset.",
        ])
        Releases.files["Cartouche-0.2.0-SideStore.ipa"] = SIDESTORE[:-1]
        with self.assertRaisesRegex(check.CheckError, "the IPA for the player's SideStore"), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            check.check(self.player_source, "0.2.0", self.release, sleep=self.slept.append, player=True)

    def test_the_version_must_be_in_the_source(self):
        with self.assertRaisesRegex(check.CheckError, "no version 0.3.0"):
            self.check("0.3.0")

    def test_the_command_writes_the_lines_for_the_pull_request(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "source.json").write_text(json.dumps(self.source), encoding="utf-8")
            (folder / "release.json").write_text(json.dumps(self.release), encoding="utf-8")
            arguments = ["--version", "0.2.0", "--release", str(folder / "release.json"),
                         "--source", str(folder / "source.json"), "--summary", str(folder / "downloads.md")]
            said = io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(said):
                self.assertEqual(check.main(arguments), 0)
                self.assertEqual(check.main([*arguments[:1], "0.3.0", *arguments[2:]]), 1)
            self.assertEqual((folder / "downloads.md").read_text(encoding="utf-8"),
                             "".join(f"{line}\n" for line in self.check()))
            self.assertIn("the source lists no version 0.3.0", said.getvalue())

    def test_the_release_workflow_checks_them_before_it_proposes_the_source(self):
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
        job = re.search(r"^  publish:\n(.*)", workflow, re.M | re.S).group(1)
        step = re.search(r"- name: Push the branch that adds the release.*?\n(?=      - |\Z)", job, re.S).group(0)
        order = [step.index(text) for text in (
            "python3 app/scripts/add_release.py",
            'gh api "repos/$GITHUB_REPOSITORY/releases/tags/$TAG" > build/release.json',
            'python3 app/scripts/check_release_downloads.py --version "$VERSION"',
            "--release build/release.json --summary build/downloads.md",
            "git add app/sidestore-source.json",
            'git push --force origin "HEAD:refs/heads/$BRANCH"',
            "cat build/downloads.md",
        )]
        self.assertEqual(order, sorted(order))
        # The addresses it checks are those add_release.py writes.
        self.assertIn('--url "https://github.com/clabeuhtegrite/Cartouche/releases/download/$TAG/', step)


if __name__ == "__main__":
    unittest.main()
