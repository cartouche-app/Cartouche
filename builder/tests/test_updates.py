"""What a copy of Cartouche Builder already installed looks for to update
itself, and what the Builder workflow publishes: they must stay one.

A copy finds only what it was built to find (mac/Sources/BuilderKit/
Updater.swift): the releases builder-v<version> of the repository, or of the
one GitHub answers for once it moved, neither drafts nor pre-releases, each
with its disk image Cartouche-Builder-<version>.dmg and that image's SHA-256
beside it, and in the image an app whose bundle identifier is its own. A
release named otherwise is never found, and each player has to download the
app again by hand, as with 0.5.0 and older, which took their disk images
from github.com/clabeuhtegrite/Cartouche alone and find none since the
repository moved to its organization (README.md, Updates; decision 116).

These are the names of every copy since 0.6.0. Renaming the app, its disk
image or its tag means publishing these names as well, for as long as such
copies run; the bundle identifier never changes. An installed copy updated
from end to end, with the disk image the workflow made:
mac/Tests/BuilderKitTests/UpdaterEndToEndTests.swift."""

import re
import unittest
from pathlib import Path

BUILDER = Path(__file__).resolve().parents[1]
ROOT = BUILDER.parent

# What every copy of the app since 0.6.0 looks for.
INSTALLED = {
    "repository": "cartouche-app/Cartouche",
    "tag": "builder-v",
    "image": "Cartouche-Builder-{version}.dmg",
    "identifier": "io.github.clabeuhtegrite.cartouche-builder",
}

WHY = ("the copies of Cartouche Builder already installed look for these names to update themselves: "
       "a release named otherwise is never found, and each player has to download the app again by hand "
       "(builder/tests/test_updates.py)")


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class Updates(unittest.TestCase):
    def setUp(self):
        self.updater = text("builder/mac/Sources/BuilderKit/Updater.swift")
        self.bundle = text("builder/mac/bundle.sh")
        self.image = text("builder/mac/make_dmg.sh")
        self.workflow = text(".github/workflows/builder.yml")

    def found(self, pattern: str, source: str, what: str) -> str:
        match = re.search(pattern, source, re.M)
        self.assertIsNotNone(match, f"{what} is no longer where this test reads it: {pattern}")
        return match.group(1)

    def test_the_app_looks_for_what_the_installed_copies_look_for(self):
        swift = self.updater
        self.assertEqual(self.found(r'static let repository = "([^"]+)"', swift, "the repository"), INSTALLED["repository"], WHY)
        self.assertEqual(self.found(r'static let tagPrefix = "([^"]+)"', swift, "the tag"), INSTALLED["tag"], WHY)
        image = self.found(r'func imageName\(_ version: String\) -> String \{\s*"([^"]+)"', swift, "the disk image's name")
        self.assertEqual(image, INSTALLED["image"].replace("{version}", r"\(version)"), WHY)
        self.assertIn('asset(imageName(version) + ".sha256")', swift, WHY)
        self.assertEqual(self.found(r'static let identifier = "([^"]+)"', swift, "the bundle identifier"), INSTALLED["identifier"], WHY)
        # Neither drafts nor pre-releases.
        self.assertIn("release.draft != true && release.prerelease != true && release.tag_name.hasPrefix(tagPrefix)", swift)

    def test_the_app_is_built_with_the_identifier_they_check_and_its_version(self):
        identifier = self.found(r"<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>", self.bundle, "bundle.sh's identifier")
        self.assertEqual(identifier, INSTALLED["identifier"], WHY)
        shown = self.found(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", self.bundle, "bundle.sh's version")
        self.assertEqual(shown, "$version")
        self.assertRegex(self.bundle, r'(?m)^version=\$\(sed -n .*"\$builder/pyproject\.toml"\)$')

    def test_the_disk_image_is_named_as_they_look_for_it(self):
        self.assertIn('version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")', self.image)
        name = self.found(r'^name="([^"]+)"$', self.image, "make_dmg.sh's name")
        self.assertEqual(name, INSTALLED["image"].replace("{version}", "$version"), WHY)
        self.assertIn('shasum -a 256 "$name" >"$name.sha256"', self.image, WHY)

    def test_the_workflow_publishes_a_release_they_take(self):
        start = self.workflow.index("- name: Publish the release")
        step = self.workflow[start : self.workflow.index("- name:", start + 1)]
        self.assertIn("VERSION=$(sed -n 's/^version = \"\\(.*\\)\"$/\\1/p' builder/pyproject.toml)", step)
        tag = self.found(r'TAG="([^"]+)\$VERSION"', step, "the release's tag")
        self.assertEqual(tag, INSTALLED["tag"], WHY)
        image = INSTALLED["image"].replace("{version}", "$VERSION")
        self.assertIn(f'test -f "build/dmg/{image}"', step, WHY)
        self.assertIn(f'test -f "build/dmg/{image}.sha256"', step, WHY)
        self.assertIn('gh release create "$TAG" build/dmg/*', step)
        # Published to the repository the workflow runs in, which the copies
        # read, or which GitHub answers for once it moved.
        self.assertIn("REPOSITORY: ${{ github.repository }}", step)
        self.assertIn('--repo "$REPOSITORY"', step)
        for flag in ("--prerelease", "--draft"):
            self.assertNotIn(flag, step, WHY)

    def test_the_version_is_one_they_compare(self):
        # BuilderVersion.parts: one to four numbers of six digits at most,
        # without a suffix ("0.7.0-beta" is never taken).
        version = self.found(r'^version = "(.*)"$', text("builder/pyproject.toml"), "the builder's version")
        self.assertRegex(version, r"^\d{1,6}(\.\d{1,6}){0,3}$", WHY)


if __name__ == "__main__":
    unittest.main()
