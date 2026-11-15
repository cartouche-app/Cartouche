"""parts.py: the screenshots and the UI tests on an iPhone, shared between
several of GitHub's Macs (screens.yml), each taken once, none left out, and
the options uitests.sh gives xcodebuild for a part, as it runs them.

    python3 -m unittest discover -s launcher/Gallery -p 'test_*.py'
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import parts  # noqa: E402
from test_heartbeat import step  # noqa: E402

SCENARIOS = json.loads((HERE / "scenarios.json").read_text())["scenarios"]
UITESTS = HERE / "UITests"
TARGET = "CartoucheGalleryUITests"


def run_by(options, every):
    """The classes of EVERY that xcodebuild runs with OPTIONS."""
    only = {o.split("/", 1)[1] for o in options if o.startswith(f"-only-testing:{TARGET}/")}
    skipped = {o.split("/", 1)[1] for o in options if o.startswith(f"-skip-testing:{TARGET}/")}
    return (only or set(every)) - skipped


class Parse(unittest.TestCase):
    def test_reads_a_part_of_so_many(self):
        self.assertEqual(parts.parse("1/3"), (1, 3))
        self.assertEqual(parts.parse("3/3"), (3, 3))
        self.assertEqual(parts.parse("1/1"), (1, 1))

    def test_refuses_what_is_not_a_part(self):
        for text in ("0/2", "3/2", "1", "1/0", "a/b", "", "1/2/3", "-1/2"):
            with self.assertRaises(ValueError, msg=text):
                parts.parse(text)


class Screenshots(unittest.TestCase):
    def test_every_scenario_once_whatever_the_parts(self):
        names = [s["name"] for s in SCENARIOS]
        for count in range(1, 6):
            taken = [s["name"] for part in range(1, count + 1) for s in parts.scenarios(SCENARIOS, part, count)]
            self.assertEqual(sorted(taken), sorted(names), count)

    def test_one_part_is_every_scenario_in_its_order(self):
        self.assertEqual(parts.scenarios(SCENARIOS, 1, 1), SCENARIOS)

    def test_the_last_part_takes_the_devices_the_others_share_the_sized(self):
        devices = [s for s in SCENARIOS if s.get("device")]
        sized = [s for s in SCENARIOS if not s.get("device")]
        self.assertTrue(devices and sized)
        self.assertEqual(parts.scenarios(SCENARIOS, 3, 3), devices)
        first, second = parts.scenarios(SCENARIOS, 1, 3), parts.scenarios(SCENARIOS, 2, 3)
        # One by one, in their order, so that neither part has more than one more.
        self.assertEqual(first, sized[0::2])
        self.assertEqual(second, sized[1::2])
        self.assertLessEqual(len(first) - len(second), 1)

    def test_a_part_without_a_scenario_is_refused(self):
        sized = [{"name": "home"}, {"name": "system"}]
        with self.assertRaisesRegex(ValueError, "part 2 of 2 has no scenario"):
            parts.scenarios(sized, 2, 2)
        with self.assertRaisesRegex(ValueError, "part 3 of 4 has no scenario"):
            parts.scenarios(sized + [{"name": "duo", "device": "iPhone Duo"}], 3, 4)


class UITests(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work, True)

    def test_finds_each_class_with_its_tests(self):
        (self.work / "ConsoleTestCase.swift").write_text(
            "class ConsoleTestCase: XCTestCase {\n    func tap() {}\n}\n")
        (self.work / "HomeUITests.swift").write_text(
            "final class HomeUITests: ConsoleTestCase {\n"
            "    func testOpens() throws {}\n    func testScrolls() {}\n    private func helper() {}\n}\n"
            "final class SheetUITests: ConsoleTestCase {\n    func testCloses() async throws {}\n}\n")
        (self.work / "IPadUITests.swift").write_text(
            "final class IPadUITests: ConsoleTestCase {\n    func testSideBySide() {}\n}\n")
        # The base class, without a test, and the iPad's, which run on an iPad alone, are not shared.
        self.assertEqual(parts.classes(self.work), {"HomeUITests": 2, "SheetUITests": 1})

    def test_the_classes_of_the_repository(self):
        found = parts.classes(UITESTS)
        files = {path.stem for path in UITESTS.glob("*UITests.swift")} - {"IPadUITests"}
        self.assertEqual(set(found), files)
        self.assertTrue(all(count > 0 for count in found.values()), found)

    def test_every_class_runs_once_whatever_the_parts(self):
        found = parts.classes(UITESTS)
        every = set(found) | {"IPadUITests"}
        for count in range(1, 5):
            runs = [run_by(parts.options(found, part, count), every) for part in range(1, count + 1)]
            self.assertEqual(sorted(name for names in runs for name in names), sorted(found), count)
            self.assertTrue(all(runs), count)

    def test_a_class_it_does_not_know_runs_in_the_last_part(self):
        found = parts.classes(UITESTS)
        every = set(found) | {"IPadUITests", "NewUITests"}
        self.assertIn("NewUITests", run_by(parts.options(found, 2, 2), every))
        self.assertNotIn("NewUITests", run_by(parts.options(found, 1, 2), every))

    def test_the_parts_have_about_as_many_tests(self):
        found = parts.classes(UITESTS)
        loads = [sum(found[name] for name in names) for names in parts.shared(found, 2)]
        self.assertLessEqual(max(loads) - min(loads), max(found.values()), loads)

    def test_one_part_is_every_test_but_the_ipads(self):
        self.assertEqual(parts.options({"HomeUITests": 2}, 1, 1), [f"-skip-testing:{TARGET}/IPadUITests"])

    def test_a_part_without_a_class_is_refused(self):
        with self.assertRaisesRegex(ValueError, "part 2 of 3 has no UI test"):
            parts.options({"HomeUITests": 2}, 2, 3)
        # The last runs whatever the others do not, none here.
        self.assertEqual(parts.options({"HomeUITests": 2}, 3, 3),
                         [f"-skip-testing:{TARGET}/IPadUITests", f"-skip-testing:{TARGET}/HomeUITests"])

    def test_uitests_sh_gives_xcodebuild_the_options_of_its_part(self):
        tests = step(HERE / "uitests.sh", "# The tests of this run:", 'echo "   tests:')
        found = parts.classes(UITESTS)

        def given(device, part):
            done = subprocess.run(["bash", "-c", "\n".join([
                "set -euo pipefail", f'HERE="{HERE}" DEVICE={device} PART={part}', tests,
                'printf "%s\\n" "${TESTS[@]}"'])], capture_output=True, text=True, timeout=60)
            return done.returncode, done.stdout.splitlines(), done.stderr

        for part in ("1/2", "2/2", "1/1"):
            code, printed, said = given("iPhone", part)
            self.assertEqual(code, 0, said)
            self.assertEqual(printed[0], "   tests: " + " ".join(parts.options(found, *parts.parse(part))))
            self.assertEqual(printed[1:], parts.options(found, *parts.parse(part)))
        code, printed, said = given("iPad", "1/1")
        self.assertEqual((code, printed[1:]), (0, [f"-only-testing:{TARGET}/IPadUITests"]), said)
        # A part that is none stops the script before its tests.
        code, printed, said = given("iPhone", "3/2")
        self.assertNotEqual(code, 0)
        self.assertEqual(printed, [])
        self.assertIn("not a part", said)

    def test_the_command_prints_one_option_a_line(self):
        done = subprocess.run([sys.executable, str(HERE / "parts.py"), "tests", "1/2", str(UITESTS)],
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines(), parts.options(parts.classes(UITESTS), 1, 2))
        for wrong, code in ((["tests", "1/2"], 2), (["tests", "0/2", str(UITESTS)], 1),
                            (["tests", "1/2", str(self.work)], 1)):
            done = subprocess.run([sys.executable, str(HERE / "parts.py"), *wrong],
                                  capture_output=True, text=True, timeout=60)
            self.assertEqual(done.returncode, code, wrong)


class Scripts(unittest.TestCase):
    def test_capture_sh_takes_its_part_alone(self):
        script = (HERE / "capture.sh").read_text()
        python = script[script.index("<<'PY'"):]
        chosen = python.index('document["scenarios"] = parts.scenarios(document["scenarios"], PART, PARTS)')
        # Read before this part's are chosen, the scenarios are its own after.
        self.assertLess(python.index('document = json.loads((HERE / "scenarios.json").read_text())'), chosen)
        self.assertEqual(python.count('document["scenarios"] = '), 1)
        self.assertIn('python3 -u - "$HERE" "$OUT" "$BUILD" "$PART" <<\'PY\'', script)

    def test_the_workflow_runs_each_part(self):
        workflow = (HERE.parents[1] / ".github/workflows/screens.yml").read_text()
        for script, job in (("uitests.sh", "screens"), ("capture.sh", "shots")):
            self.assertIn(f'launcher/Gallery/{script} --part "$PART" ', workflow)
            block = re.search(rf"^  {job}:\n(.*?)(?=^  \w+:\n)", workflow, re.M | re.S).group(1)
            self.assertIn("PART: ${{ matrix.part }}/${{ strategy.job-total }}", block, job)
            self.assertIn("fail-fast: false", block, job)


if __name__ == "__main__":
    unittest.main()
