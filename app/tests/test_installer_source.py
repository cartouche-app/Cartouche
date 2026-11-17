"""Cartouche's source (app/sidestore-source.json) as the Cartouche Installer
reads it to find the IPA it installs: serde_json reads it into the structs
Source, SourceApp and Release of installer/src-tauri/src/cartouche.rs, and
latest_in takes the newest release of Cartouche there.

The Installer's workflow builds and tests the installer, on a Mac and on
Windows, only for a pull request that changes installer/. A pull request
that changes nothing but the source, as the Release workflow's "Source:
Cartouche X" does, waited 18 minutes for those builds (#227), and only one
of the installer's tests read the source there, reads_cartouches_own_source.
This test reads the source as the installer does, on every pull request,
with the CI's App sources. It also fails when the installer's reading
changes, until it reads as the installer does again.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import copy
import hashlib
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "app" / "sidestore-source.json"
INSTALLER = ROOT / "installer" / "src-tauri" / "src" / "cartouche.rs"

# What serde_json reads of the source into the installer's structs, from
# Source down: each key, its Rust type, and whether it must be there (it may
# be left out with #[serde(default)]). The installer leaves every other key
# alone.
READS = {
    "Source": {"apps": ("Vec<SourceApp>", True)},
    "SourceApp": {"bundleIdentifier": ("String", True), "versions": ("Vec<Release>", True)},
    "Release": {
        "version": ("String", True),
        "date": ("String", False),
        "downloadURL": ("String", True),
        "size": ("u64", True),
        "sha256": ("String", True),
        "localizedDescription": ("String", False),
    },
}

# The installer's functions that choose the release and check it, and its
# test of the repository's source, which latest() and this file's tests do
# as they do: READING is their digest, which a change to any of them changes.
FUNCTIONS = ("version_key", "latest_in", "reads_cartouches_own_source")
READING = "2bb144f918d9b72e"


class SourceError(ValueError):
    """What makes the installer refuse the source."""


class Unknown(Exception):
    """Something of the installer's code this test does not know how to read."""


def constant(rust, name):
    """The text of the &str constant NAME."""
    found = re.search(rf'^(?:pub )?const {name}: &str =\s*"([^"]*)";', rust, re.M)
    if not found:
        raise Unknown(f"no constant {name} in {INSTALLER.name}")
    return found.group(1)


def raw_string(rust, name):
    """The text of the raw string constant NAME, as the installer's tests have."""
    found = re.search(rf'const {name}: &str = r#"(.*?)"#;', rust, re.S)
    if not found:
        raise Unknown(f"no raw string {name} in {INSTALLER.name}")
    return found.group(1)


def function(rust, name):
    """The text of fn NAME, from its line to the brace that closes it."""
    found = re.search(rf"^( *)(?:pub )?(?:async )?fn {name}\b.*?^\1\}}", rust, re.M | re.S)
    if not found:
        raise Unknown(f"no fn {name} in {INSTALLER.name}")
    return found.group(0)


def digest(rust):
    """The digest of FUNCTIONS, whatever their spaces and line breaks."""
    text = "\n".join(" ".join(function(rust, name).split()) for name in FUNCTIONS)
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def camel(name):
    head, *rest = name.split("_")
    return head + "".join(part.capitalize() for part in rest)


def fields(name, attributes, body):
    """The keys serde reads into the struct NAME: {key: (type, required)}."""
    if "rename_all" in attributes and 'rename_all = "camelCase"' not in attributes:
        raise Unknown(f"struct {name}: {attributes.strip()}")
    for attribute in re.findall(r"#\[serde\(([^\n]*)\)\]", attributes):
        if attribute != 'rename_all = "camelCase"':
            raise Unknown(f"struct {name}: #[serde({attribute})]")
    found, pending = {}, []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("#["):
            pending.append(line)
            continue
        field = re.fullmatch(r"(?:pub(?:\([^)]*\))? )?(\w+): (.+?),?", line)
        if not field:
            raise Unknown(f"struct {name}: {line}")
        rust_name, kind = field.groups()
        key = camel(rust_name) if "camelCase" in attributes else rust_name
        required = True
        for attribute in pending:
            serde = re.fullmatch(r"#\[serde\((.*)\)\]", attribute)
            if not serde:
                continue
            rest = serde.group(1)
            renamed = re.search(r'rename(?:\(deserialize)? = "([^"]+)"\)?', rest)
            if renamed:
                key = renamed.group(1)
                rest = rest.replace(renamed.group(0), "")
            if re.search(r"\bdefault\b", rest):
                required = False
                rest = re.sub(r"\bdefault\b", "", rest)
            if rest.strip(" ,"):
                raise Unknown(f"struct {name}.{rust_name}: {attribute}")
        pending = []
        found[key] = (kind, required)
    return found


def reading(rust):
    """The structs serde_json reads the source into, from Source down."""
    every = {
        match.group(2): (match.group(1), match.group(3))
        for match in re.finditer(r"^((?:#\[[^\n]*\]\n)*)(?:pub )?struct (\w+) \{\n(.*?)^\}", rust, re.M | re.S)
    }
    found, todo = {}, ["Source"]
    while todo:
        name = todo.pop()
        if name in found:
            continue
        if name not in every:
            raise Unknown(f"no struct {name} in {INSTALLER.name}")
        found[name] = fields(name, *every[name])
        for kind, _ in found[name].values():
            inner = re.fullmatch(r"(?:Vec|Option)<(\w+)>", kind)
            if inner and inner.group(1) in every:
                todo.append(inner.group(1))
            elif kind in every:
                todo.append(kind)
    return found


def read(value, kind, where, structs):
    """VALUE read as serde_json reads it into the Rust type KIND."""
    if kind == "String":
        if not isinstance(value, str):
            raise SourceError(f"{where} is not text: {value!r}")
        return value
    if kind == "u64":
        if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 2**64:
            raise SourceError(f"{where} is not a whole number from 0: {value!r}")
        return value
    vector = re.fullmatch(r"Vec<(.+)>", kind)
    if vector:
        if not isinstance(value, list):
            raise SourceError(f"{where} is not a list")
        return [read(item, vector.group(1), f"{where}[{index}]", structs) for index, item in enumerate(value)]
    if kind in structs:
        if not isinstance(value, dict):
            raise SourceError(f"{where} is not an object")
        kept = {}
        for key, (inner, required) in structs[kind].items():
            if key in value:
                kept[key] = read(value[key], inner, f"{where}.{key}", structs)
            elif required:
                raise SourceError(f"{where} has no {key}")
        return kept
    raise Unknown(f"{where}: the type {kind}")


def unique(pairs):
    keys = [key for key, _ in pairs]
    if len(set(keys)) != len(keys):
        raise SourceError(f"a key twice: {sorted(key for key in keys if keys.count(key) > 1)}")
    return dict(pairs)


def refused(constant_name):
    raise SourceError(f"{constant_name} is not JSON")


def version_key(version):
    """The installer's version_key: each part's leading digits as a number, 0 without."""
    return [int(re.match(r"[0-9]*", part).group() or 0) for part in version.split(".")]


def latest(text, rust):
    """The release the installer installs from the source TEXT, as latest_in does."""
    try:
        document = json.loads(text, object_pairs_hook=unique, parse_constant=refused)
    except json.JSONDecodeError as error:
        raise SourceError(f"Cartouche's source does not read: {error}") from error
    source = read(document, "Source", "the source", reading(rust))
    bundle_id, prefix = constant(rust, "BUNDLE_ID"), constant(rust, "DOWNLOAD_PREFIX")
    releases = [release for app in source["apps"] if app["bundleIdentifier"] == bundle_id
                for release in app["versions"]]
    if not releases:
        raise SourceError("Cartouche's source lists no release")
    # max_by_key gives the last of equal versions, max the first.
    release = max(reversed(releases), key=lambda one: version_key(one["version"]))
    if not release["downloadURL"].startswith(prefix):
        raise SourceError(f"Cartouche's source gives an IPA outside its GitHub releases: {release['downloadURL']}")
    return release


class InstallerSourceTest(unittest.TestCase):
    def setUp(self):
        self.rust = INSTALLER.read_text(encoding="utf-8")
        self.source = SOURCE.read_text(encoding="utf-8")

    def test_the_installer_installs_the_newest_release_of_the_source(self):
        # As the installer's reads_cartouches_own_source.
        release = latest(self.source, self.rust)
        version = release["version"]
        self.assertTrue(release["downloadURL"].endswith(f"/v{version}/Cartouche-{version}.ipa"), release)
        self.assertRegex(release["sha256"], r"\A[0-9a-fA-F]{64}\Z")
        self.assertGreater(release["size"], 1_000_000)

    def test_it_reads_the_installers_own_tests_as_they_do(self):
        # Their source, SOURCE in the tests of cartouche.rs: the highest
        # version, not the first; an IPA outside the releases; no Cartouche.
        theirs = raw_string(self.rust, "SOURCE")
        release = latest(theirs, self.rust)
        self.assertEqual((release["version"], release["size"]), ("0.10.0", 1))
        outside = theirs.replace("https://github.com/clabeuhtegrite/Cartouche/releases/download/v0.10.0/",
                                 "https://example.com/")
        other = theirs.replace("io.github.clabeuhtegrite.cartouche", "com.example.other")
        for source in (outside, other):
            self.assertNotEqual(source, theirs)
            with self.assertRaises(SourceError):
                latest(source, self.rust)

    def test_a_release_the_installer_cannot_read_is_refused_even_an_old_one(self):
        # serde_json reads every release of the source, not the newest alone.
        source = json.loads(self.source)
        changes = {
            "no SHA-256": lambda release: release.pop("sha256"),
            "no address": lambda release: release.pop("downloadURL"),
            "a size in text": lambda release: release.update(size=str(release["size"])),
            "a size below 0": lambda release: release.update(size=-1),
            "a size with a fraction": lambda release: release.update(size=release["size"] + 0.5),
            "a version as a number": lambda release: release.update(version=13),
            "a date as a number": lambda release: release.update(date=20261115),
        }
        for what, change in changes.items():
            broken = copy.deepcopy(source)
            change(broken["apps"][0]["versions"][-1])
            with self.subTest(what), self.assertRaises(SourceError):
                latest(json.dumps(broken), self.rust)
        texts = {
            "NaN for a size": re.sub(r'"size": \d+', '"size": NaN', self.source, count=1),
            "a size twice": re.sub(r'("size": \d+)', r"\1, \1", self.source, count=1),
            "cut short": self.source[:-10],
        }
        for what, text in texts.items():
            self.assertNotEqual(text, self.source, what)
            with self.subTest(what), self.assertRaises(SourceError):
                latest(text, self.rust)
        # What a release may leave out, and what the installer does not read.
        fine = copy.deepcopy(source)
        oldest = fine["apps"][0]["versions"][-1]
        oldest.pop("date")
        oldest.pop("localizedDescription")
        oldest["somethingElse"] = [1, None]
        latest(json.dumps(fine), self.rust)

    def test_a_pull_request_of_the_source_alone_runs_this_test_not_the_installers_builds(self):
        workflows = ROOT / ".github" / "workflows"
        installer = (workflows / "installer.yml").read_text(encoding="utf-8")
        paths = re.search(r"^  pull_request:\n    paths: \[(.*)\]$", installer, re.M)
        self.assertIsNotNone(paths, "the Installer's workflow runs for the pull requests that change some paths")
        self.assertIn('"installer/**"', paths.group(1))
        self.assertNotIn("app/sidestore-source.json", paths.group(1))
        # The CI runs on every pull request, whatever it changes, and main
        # requires its App sources, which runs this test.
        ci = (workflows / "ci.yml").read_text(encoding="utf-8")
        self.assertRegex(ci, r"(?m)^  pull_request:\n(?!    paths)")
        job = re.search(r"^  app-sources:\n(.*?)(?=^  [\w-]+:\n)", ci, re.M | re.S).group(1)
        self.assertIn("name: App sources\n", job)
        self.assertIn("python3 -m unittest discover -s app/tests", job)
        ruleset = json.loads((ROOT / ".github" / "rulesets" / "main.json").read_text(encoding="utf-8"))
        required = {check["context"] for rule in ruleset["rules"] if rule["type"] == "required_status_checks"
                    for check in rule["parameters"]["required_status_checks"]}
        self.assertIn("App sources", required)

    def test_it_reads_as_the_installer_reads(self):
        self.assertEqual(reading(self.rust), READS)
        found = digest(self.rust)
        self.assertEqual(found, READING, (
            f"The installer reads Cartouche's source otherwise now: {', '.join(FUNCTIONS)} changed in "
            f"{INSTALLER.relative_to(ROOT)}. Make latest() and these tests read it as they do, "
            f"then set READING to {found!r}."))


if __name__ == "__main__":
    unittest.main()
