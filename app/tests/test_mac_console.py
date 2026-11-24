"""Checks Cartouche's console on the Mac (builder/mac/Sources/CartoucheConsole),
which builds the iPhone's console screens for the Mac:

- its Shared folder holds links to the launcher's own files, by their own
  names, and nothing else, so that the Mac shows what the iPhone shows;
- every other file of the launcher is listed in builder/mac/console/unshared.json
  with why the console does not link it: the iPhone's alone, the Mac's own
  in its place, or the step of the plan that brings it (Ad, 13 November: the
  whole of the iPhone's app, and its changes to come, on the Mac);
- the Builder's workflow builds the app again when one of those files or the
  launcher's words change (.github/workflows/builder.yml);
- the console reaches the player's storage as the app does: SMBClient from
  its submodule, which the workflow checks out, swift-nio-ssh and swift-nio
  at the app's versions, and the packages they bring pinned as the app pins
  them (app/patches/livecontainer/0007);
- none of those files uses, outside an iPhone-only part, a name of UIKit's
  or of the iPhone's SwiftUI that the Mac does not have, but those the
  console's shims give it (Mac/ConsoleShims.swift), nor a name of the
  launcher's that the console does not have, from a file it does not link,
  with no stand-in for it (Mac/ConsoleStandIns.swift): a change to the
  iPhone's screens that only a Mac would find otherwise;
- the Mac's own words (builder/mac/console/strings.json) say what the
  launcher's say, with the same placeholders, those of the console's own
  files are there as the files say them, and console/strings.py writes
  each language's table where the console reads it;
- the console's Storage page, the iPhone's with This Mac's folders in place
  of its games folder and saves folder (Mac/ConsoleStorage.swift), has the
  rows those sections open, as the UI tests know them;
- the console's System page, the iPhone's with the Builder's updates in
  place of Cartouche's (Mac/ConsoleSystem.swift), shows the version once,
  in the section of the app, as the iPhone does;
- the shared files write days, numbers and lists in the console's language
  (CartoucheText.locale), which the app's settings may choose other than
  the Mac's, never in the Mac's (Locale.current): on the iPhone, the two are
  one.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import importlib.util
import json
import os
import plistlib
import re
import tempfile
import unittest
from pathlib import Path

from test_launcher_strings import placeholders
from test_storage_tests import added_file, pins

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "launcher" / "Sources"
CONSOLE = ROOT / "builder" / "mac" / "Sources" / "CartoucheConsole"
SHARED = CONSOLE / "Shared"
WORKFLOW = ROOT / ".github" / "workflows" / "builder.yml"
CATALOG = LAUNCHER / "Cartouche.xcstrings"
MAC_STRINGS = ROOT / "builder" / "mac" / "console" / "strings.json"
UNSHARED = ROOT / "builder" / "mac" / "console" / "unshared.json"
MAC_SOURCES = ROOT / "builder" / "mac" / "Sources"
MAC_PACKAGE = ROOT / "builder" / "mac"
PLAN_STEPS = range(7, 10)  # the plan's steps still to come after this one (docs/decisions/095.md)
WRITER = ROOT / "builder" / "mac" / "console" / "strings.py"
STORAGE_PAGE = LAUNCHER / "CartoucheStorageView.swift"
MAC_STORAGE = CONSOLE / "Mac" / "ConsoleStorage.swift"
SYSTEM_PAGE = LAUNCHER / "CartoucheSystemView.swift"
MAC_SYSTEM = CONSOLE / "Mac" / "ConsoleSystem.swift"
LANGUAGES = ("en", "fr", "es", "de")

# Names the Mac does not have: UIKit's, and the iPhone's alone in SwiftUI.
IPHONE_ONLY = re.compile(
    r"\bUI(?!Image\b|Application\.did(?:BecomeActive|EnterBackground)Notification\b)[A-Z]\w*"
    r"|\bnavigationBar(?:TitleDisplayMode|Drawer|Leading|Trailing|Hidden|Items)\b"
    r"|\bfor: \.navigationBar\b|\btopBar(?:Leading|Trailing)\b|\binsetGrouped\b"
    r"|\bfullScreenCover\b|\btextInputAutocapitalization\b|\bkeyboardType\b|\bstatusBarHidden\b"
    r"|\bnavigationTransition\b|\bmatchedTransitionSource\b|\bEditButton\b|\bPageTabViewStyle\b"
)
# The conditions of an iPhone-only part.
IPHONE_CONDITION = re.compile(r"^(?:os\(iOS\)|canImport\(UIKit\))(?:\s*\|\|\s*os\((?:iOS|visionOS|tvOS)\))*$")
# The conditions of a part the console never builds: the iPhone's alone,
# and the launcher's gallery (CARTOUCHE_GALLERY, which the Builder does not
# define). The console links the packages of SMB and SFTP, as the app does
# (builder/mac/Package.swift): their parts are built.
_ELSEWHERE = r"(?:os\((?:iOS|visionOS|tvOS)\)|canImport\(UIKit\)|CARTOUCHE_GALLERY)"
NOT_ON_THE_MAC = re.compile(rf"^{_ELSEWHERE}(?:\s*\|\|\s*{_ELSEWHERE})*$")
# The launcher's own names, and LiveContainer's, as the console's files use
# them, where one is declared, and a string, whose words are no names.
OWN_NAME = re.compile(r"\b(?:Cartouche|LC)[A-Z]\w*")
DECLARATION = re.compile(r"\b(?:class|struct|enum|protocol|typealias|actor)\s+((?:Cartouche|LC)[A-Z]\w*)")
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def outside_iphone_parts(swift: str, condition=IPHONE_CONDITION):
    """The lines the Mac compiles, as (number, line): those outside the
    parts whose condition CONDITION matches, by default the `#if os(iOS)` or
    `#if canImport(UIKit)` ones, comments left out."""
    stack = []  # for each #if, whether its current branch is left out
    for number, line in enumerate(swift.splitlines(), start=1):
        directive = line.strip()
        if directive.startswith("#if "):
            stack.append(bool(condition.match(directive[4:].strip())))
            continue
        if directive.startswith("#elseif ") or directive == "#else":
            # Another branch: left out only if it says so.
            stack[-1] = directive.startswith("#elseif ") and bool(condition.match(directive[8:].strip()))
            continue
        if directive == "#endif":
            stack.pop()
            continue
        if any(stack):
            continue
        code = line.split("//", 1)[0]
        if code.strip():
            yield number, code


def footers_cut_on_the_mac(swift: str):
    """The lines of SWIFT that open a section's footer in a list, the section
    being SwiftUI's own rather than a CartoucheSection: a list on the Mac
    gives a section's footer two lines at most, and cuts a longer one at both
    ends. A file without a list, as a form, keeps its sections' footers, and
    the parts only the iPhone builds are the iPhone's."""
    if not re.search(r"\bList\s*\{", swift):
        return []
    on_the_mac = {number for number, _ in outside_iphone_parts(swift)}
    lines = [STRING.sub('""', line) for line in swift.splitlines()]
    found = []
    for index, line in enumerate(lines):
        at = re.search(r"\}\s*footer:\s*\{", line)
        if not at or index + 1 not in on_the_mac:
            continue
        # Back to the line that opens the section, past the blocks of its
        # header and of its rows, each closed by the "}" before its label.
        depth, number, code = 0, index, line[:at.start() + 1]
        while True:
            for character in reversed(code):
                depth += {"}": 1, "{": -1}.get(character, 0)
            if depth <= 0 or number == 0:
                break
            number -= 1
            code = lines[number]
        if not re.search(r"\bCartoucheSection\b", code):
            found.append(index + 1)
    return found


def written_in_the_macs_language(swift: str):
    """The lines of SWIFT that the Mac compiles and that write a day, a
    number or a list with `.formatted(…)` and no locale: in the Mac's
    language, Locale.current, rather than in the console's,
    CartoucheText.locale (CartoucheText.dateAndTime, or
    `.locale(CartoucheText.locale)` on the style)."""
    return [(number, code) for number, code in outside_iphone_parts(swift, NOT_ON_THE_MAC)
            if ".formatted(" in STRING.sub('""', code) and "locale" not in code]


def own_names(swift: str):
    """The launcher's names that SWIFT declares, and those it uses, in the
    parts the console builds."""
    codes = [STRING.sub('""', code) for _, code in outside_iphone_parts(swift, NOT_ON_THE_MAC)]
    declared = {name for code in codes for name in DECLARATION.findall(code)}
    used = {name for code in codes for name in OWN_NAME.findall(code)}
    return declared, used


def _block(code: str, opening: int) -> str:
    """The text between the brace at OPENING and the one that closes it."""
    depth = 0
    for at in range(opening, len(code)):
        depth += {"{": 1, "}": -1}.get(code[at], 0)
        if depth == 0:
            return code[opening + 1:at]
    raise ValueError("a block that does not close")


def _code(swift: str) -> str:
    """SWIFT without its strings' words nor its comments."""
    return "\n".join(STRING.sub('""', line).split("//", 1)[0] for line in swift.splitlines())


def type_body(swift: str, name: str) -> str:
    """The body of the type NAME that SWIFT declares."""
    code = _code(swift)
    match = re.search(rf"\b(?:struct|class|enum|extension)\s+{name}\b[^{{]*", code)
    if not match:
        raise ValueError(f"no {name}")
    return _block(code, match.end())


def members(body: str):
    """The bodies of the functions and computed properties of a type's BODY,
    by their names."""
    found = {}
    for match in re.finditer(r"\bfunc\s+(\w+)\s*(?:<[^>]*>)?\(|\bvar\s+(\w+)\s*:[^=\n{]*\{", body):
        if match.group(1):
            # Past its parameters, to its body.
            depth, at = 0, match.end() - 1
            while True:
                depth += {"(": 1, ")": -1}.get(body[at], 0)
                if depth == 0:
                    break
                at += 1
            opening = body.find("{", at)
        else:
            opening = match.end() - 1
        found[match.group(1) or match.group(2)] = _block(body, opening)
    return found


def rows_of(swift: str, page: str, section: str):
    """The identifiers that the rows of SECTION, a part of the type PAGE
    that SWIFT declares, are given, as `Self.<name>`, through the parts of
    PAGE it calls too."""
    parts = members(type_body(swift, page))
    rows, seen, waiting = set(), set(), [section]
    while waiting:
        name = waiting.pop()
        if name in seen or name not in parts:
            continue
        seen.add(name)
        rows |= set(re.findall(r"\.accessibilityIdentifier\(Self\.(\w+)\)", parts[name]))
        waiting += [other for other in parts if re.search(rf"\b{other}\b", parts[name])]
    return rows


def load_writer():
    spec = importlib.util.spec_from_file_location("mac_console_strings", WRITER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MacConsoleSources(unittest.TestCase):
    def test_the_shared_files_are_links_to_the_launchers_own(self):
        names = sorted(path.name for path in SHARED.iterdir())
        self.assertGreater(len(names), 0)
        for name in names:
            with self.subTest(name=name):
                link = SHARED / name
                self.assertTrue(link.is_symlink(), f"{name} is a file of its own, not the launcher's")
                self.assertEqual(os.readlink(link), f"../../../../../launcher/Sources/{name}")
                self.assertTrue((LAUNCHER / name).is_file(), f"launcher/Sources/{name} is gone")

    def test_every_launcher_file_is_linked_or_says_why_not(self):
        """A new file of the launcher comes to the Mac with it, or says why
        it does not, so that the iPhone's app and its changes to come are
        the Mac's too."""
        listed = json.loads(UNSHARED.read_text(encoding="utf-8"))["files"]
        linked = {path.name for path in SHARED.iterdir()}
        launcher = {path.name for path in LAUNCHER.glob("*.swift")}
        self.assertEqual(sorted(launcher - linked - set(listed)), [],
                         "link them in Shared (and the Builder workflow's list), or say why not in builder/mac/console/unshared.json")
        self.assertEqual(sorted(set(listed) - launcher), [], "files of unshared.json the launcher no longer has")
        self.assertEqual(sorted(set(listed) & linked), [], "files linked in Shared and listed as not linked")
        for name, entry in sorted(listed.items()):
            with self.subTest(name=name):
                self.assertIn(entry.get("kind"), ("iphone", "mac", "later"))
                self.assertGreater(len(entry.get("why", "").strip()), 20, "why, in a sentence")
                if entry["kind"] == "mac":
                    self.assertTrue((MAC_SOURCES / entry.get("mac", "")).is_file(), "the Mac's own file in its place")
                if entry["kind"] == "later":
                    self.assertIn(entry.get("step"), PLAN_STEPS, "the step of the plan that brings it")

    def test_the_macs_own_files_are_beside_them(self):
        for path in (CONSOLE / "Mac").iterdir():
            with self.subTest(name=path.name):
                self.assertFalse(path.is_symlink())
                self.assertFalse((LAUNCHER / path.name).exists(), "a name of the launcher's own")

    def test_the_builders_workflow_runs_when_a_shared_file_changes(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        trigger = workflow.split("pull_request:", 1)[1].split("workflow_dispatch:", 1)[0]
        listed = set(re.findall(r'^\s*- "launcher/Sources/([^"*]+)"$', trigger, re.MULTILINE))
        linked = {path.name for path in SHARED.iterdir()}
        self.assertEqual(sorted(listed - linked - {CATALOG.name}), [], "files the console no longer links")
        self.assertEqual(sorted(linked - listed), [], "files the console links that the workflow misses")
        self.assertIn(CATALOG.name, listed)
        # A run that changes only them is built again, not taken as built.
        self.assertIn("$SHARED launcher/Sources/Cartouche.xcstrings", workflow)

    def test_the_shared_files_use_nothing_the_mac_lacks(self):
        for link in sorted(SHARED.iterdir()):
            with self.subTest(name=link.name):
                lines = list(outside_iphone_parts(link.read_text(encoding="utf-8")))
                found = [f"{link.name}:{number}: {code.strip()}"
                         for number, code in lines if IPHONE_ONLY.search(code)]
                self.assertEqual(found, [], "wrap them in #if os(iOS), or give the Mac its own in Mac/")
                imports = [code.strip() for _, code in lines if re.match(r"\s*(?:@\w+\s+)?import UIKit\b", code)]
                self.assertEqual(imports, [], "import UIKit only under #if canImport(UIKit)")

    def test_the_shared_files_write_in_the_consoles_language(self):
        """A day, a number or a list in the language the console speaks,
        which the Builder's settings may choose other than the Mac's: "17
        nov. 2026 à 9:59" in French on a Mac in English, as on an iPhone."""
        found = []
        for link in sorted(SHARED.iterdir()):
            found += [f"{link.name}:{number}: {code.strip()}"
                      for number, code in written_in_the_macs_language(link.read_text(encoding="utf-8"))]
        self.assertEqual(found, [], "use CartoucheText.dateAndTime, or .locale(CartoucheText.locale) on the style")

    def test_the_check_sees_a_day_in_the_macs_language(self):
        swift = """
let sent = date.formatted(date: .abbreviated, time: .shortened)
let kept = CartoucheText.dateAndTime(date)
let names = list.formatted(.list(type: .and).locale(CartoucheText.locale))
let said = Text(".formatted(")
#if os(iOS)
let iPhone = date.formatted()
#endif
"""
        self.assertEqual([number for number, _ in written_in_the_macs_language(swift)], [2])

    def test_the_shared_files_name_only_what_the_console_has(self):
        """A launcher file the console links that starts using a name of a
        file it does not link, such as the iPhone's renewals, needs a
        stand-in for it on the Mac, or the part is the iPhone's alone: the
        Builder's app would no longer build, which only a Mac would say."""
        files = sorted(SHARED.iterdir()) + sorted((CONSOLE / "Mac").glob("*.swift"))
        declared = set().union(*(own_names(path.read_text(encoding="utf-8"))[0] for path in files))
        for link in sorted(SHARED.iterdir()):
            with self.subTest(name=link.name):
                _, used = own_names(link.read_text(encoding="utf-8"))
                self.assertEqual(sorted(used - declared), [],
                                 "give the Mac a stand-in (Mac/ConsoleStandIns.swift), link the file that declares it, "
                                 "or wrap the part in #if os(iOS)")

    def test_the_shared_files_footers_take_the_lines_they_need(self):
        """A list on the Mac gives a section's footer two lines at most, and
        cuts a longer one at both ends: the saves' footers on a game's sheet
        were. A section with a footer in a list is a CartoucheSection
        (CartoucheTheme.swift), whose footer is the section's last row on
        the Mac."""
        for link in sorted(SHARED.iterdir()):
            with self.subTest(name=link.name):
                found = footers_cut_on_the_mac(link.read_text(encoding="utf-8"))
                self.assertEqual(found, [], "a section with a footer in a list: make it a CartoucheSection")

    def test_the_check_sees_a_footer_cut_on_the_mac(self):
        swift = "\n".join([
            "List {",
            "CartoucheSection {", "} footer: {", "    Text(a)", "}",
            "Section {", "    if b { c }", "} footer: {", "    Text(d)", "}",
            "Section {", "} header: {", "    Text(e)", "} footer: {", "    footer(f)", "}",
            "return CartoucheSection {", '    Text("{")', "} header: {", "    Text(g)", "} footer: { Text(h) }",
            "}",
        ])
        self.assertEqual(footers_cut_on_the_mac(swift), [8, 14])
        # The iPhone's own sections keep SwiftUI's.
        iphone = "\n".join(["List {", "#if os(iOS)", "Section {", "} footer: {", "    Text(a)", "}", "#else",
                             "Section {", "} footer: {", "    Text(b)", "}", "#endif", "}"])
        self.assertEqual(footers_cut_on_the_mac(iphone), [9])
        # A form's footers take their lines on the Mac.
        form = "\n".join(["Form {", "Section {", "} footer: {", "    Text(a)", "}", "}"])
        self.assertEqual(footers_cut_on_the_mac(form), [])

    def test_the_check_sees_a_name_the_console_lacks(self):
        swift = "\n".join([
            "struct CartoucheThing {}", "#if os(iOS)", "let a = CartoucheRenewals.shared", "#endif",
            "#if CARTOUCHE_GALLERY", "let b = CartoucheGalleryOnly()", "#else", "let c = CartoucheThing()", "#endif",
            "#if canImport(UIKit)", "let d = CartoucheUIKitOnly()", "#endif",
            # SMB's and SFTP's parts: the console builds them.
            "#if canImport(NIOSSH)", "let g = CartoucheSFTPMissing.self", "#endif",
            "let e = CartoucheMissing.shared // CartoucheInAComment", 'let f = "CartoucheInAString"',
        ])
        declared, used = own_names(swift)
        self.assertEqual(sorted(used - declared), ["CartoucheMissing", "CartoucheSFTPMissing"])

    def test_the_check_sees_an_unguarded_name(self):
        swift = "\n".join([
            "#if os(iOS)", "let a = UIDevice.current", "#else", "let b = 1", "#endif",
            "let c = UIImage()", "let d = UIScreen.main // the screen",
            "#if canImport(UIKit)", "import UIKit", "#endif",
        ])
        lines = list(outside_iphone_parts(swift))
        self.assertEqual([number for number, code in lines if IPHONE_ONLY.search(code)], [7])
        self.assertNotIn(2, [number for number, _ in lines])
        self.assertIn(4, [number for number, _ in lines])


class MacConsolePackages(unittest.TestCase):
    """The packages the shared storage files need, SMB's and SFTP's, as the
    app builds them: their parts are built for the Mac (NOT_ON_THE_MAC)."""

    def test_pins_the_packages_the_app_pins(self):
        app = pins(json.loads(added_file("Package.resolved")))
        mac = pins(json.loads((MAC_PACKAGE / "Package.resolved").read_text(encoding="utf-8")))
        self.assertEqual(mac, app)

    def test_asks_for_the_versions_the_app_asks_for(self):
        project = added_file("project.pbxproj")
        manifest = (MAC_PACKAGE / "Package.swift").read_text(encoding="utf-8")
        for name in ("swift-nio-ssh", "swift-nio"):
            url = re.escape(f"https://github.com/apple/{name}.git")
            app = re.search(url + r'";\s*requirement = \{\s*kind = exactVersion;\s*version = ([0-9.]+);', project)
            mac = re.search(r'\.package\(url: "' + url + r'", exact: "([0-9.]+)"\)', manifest)
            self.assertIsNotNone(app, f"the app does not pin {name} to a version")
            self.assertIsNotNone(mac, f"builder/mac/Package.swift does not pin {name} to a version")
            self.assertEqual(mac.group(1), app.group(1), name)
        self.assertIn('.package(path: "../../app/SMBClient")', manifest)
        console = manifest.split('name: "CartoucheConsole"', 1)[1].split(".target(", 1)[0]
        for product in ("SMBClient", "NIOSSH", "NIOCore", "NIOPosix"):
            self.assertIn(f'.product(name: "{product}"', console, product)

    def test_the_workflow_checks_out_smbclient_before_it_builds(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        job = workflow.split("\n  mac:\n", 1)[1].split("\n  keep:\n", 1)[0]
        self.assertIn("git submodule update --init app/SMBClient", job,
                      "the console builds SMBClient from its submodule: the mac job checks it out")
        checkout = job.index("actions/checkout@")
        submodule = job.index("git submodule update --init app/SMBClient")
        self.assertLess(checkout, submodule)
        self.assertLess(submodule, job.index("swift test --package-path builder/mac"))
        # A new SMBClient builds the app again.
        trigger = workflow.split("pull_request:", 1)[1].split("workflow_dispatch:", 1)[0]
        self.assertIn('- "app/SMBClient"', trigger)
        self.assertIn("app/SMBClient telemetry/test/builder-reports.json", workflow)


class MacConsoleWords(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(CATALOG.read_text(encoding="utf-8"))["strings"]
        cls.mac = json.loads(MAC_STRINGS.read_text(encoding="utf-8"))

    def test_the_overrides_say_what_the_launchers_words_say(self):
        overrides = self.mac["overrides"]
        self.assertIn("sheet.onThisIPhone", overrides)
        for key, values in overrides.items():
            with self.subTest(key=key):
                self.assertIn(key, self.catalog, "a word the launcher does not have: put it in \"strings\"")
                english = self.catalog[key]["localizations"]["en"]["stringUnit"]["value"]
                self.assertEqual(sorted(values), sorted(LANGUAGES))
                for language in LANGUAGES:
                    self.assertTrue(values[language].strip())
                    self.assertEqual(placeholders(values[language]), placeholders(english), language)
                    self.assertNotIn("iPhone", values[language], language)

    def test_the_macs_own_words_are_its_own(self):
        for key, values in self.mac.get("strings", {}).items():
            with self.subTest(key=key):
                self.assertNotIn(key, self.catalog, "a word of the launcher's: put it in \"overrides\"")
                self.assertEqual(sorted(values), sorted(LANGUAGES))
                self.assertTrue(all(values[language].strip() for language in LANGUAGES))
                for language in LANGUAGES:
                    self.assertEqual(placeholders(values[language]), placeholders(values["en"]), language)

    def test_french_spacing(self):
        # As the launcher's words (test_launcher_strings.py): a no-break
        # space before the French colon and semicolon, which then never
        # starts a line.
        for section in ("overrides", "strings"):
            for key, values in self.mac.get(section, {}).items():
                with self.subTest(key=key):
                    self.assertIsNone(re.search(r"[^\u00a0\u202f][:;](?:\s|$)", values["fr"]), values["fr"])

    def test_the_console_files_words_are_the_macs_own(self):
        """The words the console's own files speak (Mac/, CartoucheText's
        s() and f()) are its own words, in English as the files say them:
        a word a file adds without them would stay in English."""
        spoken = {}
        for path in sorted((CONSOLE / "Mac").glob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for key, english in re.findall(r'\b[sf]\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"', text):
                spoken[key] = english
        self.assertEqual(sorted(spoken), sorted(self.mac.get("strings", {})))
        for key, english in spoken.items():
            with self.subTest(key=key):
                self.assertEqual(self.mac["strings"][key]["en"], english)

    def test_the_file_is_written_as_the_test_reads_it(self):
        text = MAC_STRINGS.read_text(encoding="utf-8")
        self.assertEqual(text, json.dumps(self.mac, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    def test_each_language_is_written_where_the_console_reads_it(self):
        writer = load_writer()
        with tempfile.TemporaryDirectory() as folder:
            resources = Path(folder)
            written = writer.write(CATALOG, MAC_STRINGS, resources)
            paths = {language: [resources / f"{language}.lproj" / "Cartouche.strings",
                                resources / "Console" / language / "Cartouche.strings",
                                resources / "Console" / language / f"{language}.lproj" / "Cartouche.strings"]
                     for language in LANGUAGES}
            self.assertEqual(sorted(written), sorted(path for language in LANGUAGES for path in paths[language]))
            keys = set(self.catalog) | set(self.mac.get("strings", {}))
            for language in LANGUAGES:
                # Its folder holds that language alone, the same words at
                # its root and in its localization as in the app's.
                folder = sorted(path.name for path in (resources / "Console" / language).iterdir())
                self.assertEqual(folder, ["Cartouche.strings", f"{language}.lproj"])
                tables = [plistlib.loads(path.read_bytes()) for path in paths[language]]
                self.assertEqual(set(tables[0]), keys)
                self.assertTrue(all(table == tables[0] for table in tables), language)
            french = plistlib.loads((resources / "Console" / "fr" / "Cartouche.strings").read_bytes())
            english = plistlib.loads((resources / "en.lproj" / "Cartouche.strings").read_bytes())
            # The Mac's words over the launcher's; the others as the launcher has them.
            self.assertEqual(french["sheet.onThisIPhone"], self.mac["overrides"]["sheet.onThisIPhone"]["fr"])
            self.assertEqual(english["sheet.onThisIPhone"], "On this Mac")
            for key in sorted(set(self.catalog) - set(self.mac["overrides"]))[:50]:
                self.assertEqual(french[key], self.catalog[key]["localizations"]["fr"]["stringUnit"]["value"])


class MacConsoleStorage(unittest.TestCase):
    """The console's Storage page, the iPhone's (CartoucheStorageView.swift)
    with This Mac's folders, the Builder's, in place of its games folder and
    saves folder (CartoucheMacFoldersSection, Mac/ConsoleStorage.swift)."""

    def test_this_macs_folders_have_the_rows_of_the_sections_they_stand_for(self):
        page = STORAGE_PAGE.read_text()
        rows = rows_of(page, "CartoucheStorageView", "gamesSection") | rows_of(page, "CartoucheStorageView", "savesSection")
        # How to name the games, under the games folder: the check sees it.
        self.assertIn("namingRow", rows)
        # Another games folder is added on the iPhone: the console shows
        # the iPhone's, under its games folder (CartoucheMacIPhoneGamesSection).
        rows.discard("addGamesRow")
        mac = type_body(MAC_STORAGE.read_text(), "CartoucheMacFoldersSection")
        for row in sorted(rows):
            self.assertTrue(f"CartoucheStorageView.{row}" in mac,
                            f"The iPhone's games folder or saves folder has the row {row}, This Mac's folders not")

    def test_the_check_follows_a_row_through_the_parts_a_section_calls(self):
        swift = """
struct Page: View {
    static let tapped = "page.tapped"
    static let elsewhere = "page.elsewhere"
    var body: some View {
        List { part(.one) }
    }
    private func part(_ which: Which) -> some View {
        Section { link }
    }
    private var link: some View {
        Button("Go {") {}
            .accessibilityIdentifier(Self.tapped)
    }
    private var other: some View {
        Text("}").accessibilityIdentifier(Self.elsewhere)
    }
}
"""
        self.assertEqual(rows_of(swift, "Page", "part"), {"tapped"})
        self.assertEqual(rows_of(swift, "Page", "body"), {"tapped"})



class MacConsoleSystem(unittest.TestCase):
    """The console's System page, the iPhone's (CartoucheSystemView.swift)
    with the Builder's updates in place of Cartouche's
    (CartoucheMacUpdatesSection, Mac/ConsoleSystem.swift)."""

    def test_the_version_shows_once_as_on_the_iphone(self):
        # The iPhone has its version in its Cartouche section, which the Mac
        # shows as Cartouche for Mac, and its updates say only what the
        # updater found: a Version row in the Mac's updates showed it twice,
        # and empty in the gallery (17 November).
        page = "\n".join(line for _, line in outside_iphone_parts(SYSTEM_PAGE.read_text()))
        self.assertEqual(len(re.findall(r"LabeledContent\(CartoucheText\.version\b", page)), 1)
        updates = type_body(MAC_SYSTEM.read_text(), "CartoucheMacUpdatesSection")
        self.assertNotRegex(updates, r"CartoucheText\.version\b")


if __name__ == "__main__":
    unittest.main()
