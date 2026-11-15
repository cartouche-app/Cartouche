"""install.py: capture.sh installs the gallery once more, a minute later, when
its first install after the iPad's first boot goes unanswered, as it did
twice in the full test pass 43659377514, where the 80 sized scenarios got no
screen.

    python3 -m unittest discover -s launcher/Gallery -p 'test_*.py'
"""

import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import install  # noqa: E402

APP = Path("/Build/DerivedData/Build/Products/Debug-iphonesimulator/CartoucheGallery.app")
NAME = "iPad Pro 13-inch (M5)"


class Failure(Exception):
    pass


class Simulator:
    """simctl install as capture.sh's run calls it: no answer for the first
    UNANSWERED tries, then the gallery installed."""

    def __init__(self, unanswered):
        self.unanswered = unanswered
        self.tries = []
        self.slept = []
        self.said = []

    def run(self, *args, timeout=300):
        self.tries.append((args, timeout))
        if len(self.tries) <= self.unanswered:
            raise Failure(f"{' '.join(args[:4])}: no answer in {timeout} s")
        return ""

    def sleep(self, seconds):
        self.slept.append(seconds)

    def say(self, *words, **_):
        self.said.append(" ".join(words))


class Install(unittest.TestCase):
    def install(self, simulator):
        install.install(simulator.run, Failure, "UDID", APP, NAME, say=simulator.say, sleep=simulator.sleep)

    def test_an_install_that_answers_is_tried_once(self):
        simulator = Simulator(unanswered=0)
        self.install(simulator)
        self.assertEqual(simulator.tries, [(("xcrun", "simctl", "install", "UDID", str(APP)), 300)])
        self.assertEqual(simulator.slept, [])
        self.assertEqual(simulator.said, [])

    def test_an_unanswered_install_is_tried_again_a_minute_later(self):
        simulator = Simulator(unanswered=1)
        self.install(simulator)
        self.assertEqual([args for args, _ in simulator.tries], [("xcrun", "simctl", "install", "UDID", str(APP))] * 2)
        self.assertEqual(simulator.slept, [60])
        self.assertEqual(simulator.said, [f"::warning::{NAME}: xcrun simctl install UDID: no answer in 300 s; "
                                          "once more in 60 s"])

    def test_a_second_unanswered_install_gives_the_simulator_up(self):
        simulator = Simulator(unanswered=2)
        with self.assertRaisesRegex(Failure, "no answer in 300 s"):
            self.install(simulator)
        self.assertEqual(len(simulator.tries), 2)

    def test_capture_installs_the_gallery_through_it_alone(self):
        script = (HERE / "capture.sh").read_text()
        code = "\n".join(line for line in script.splitlines() if not line.lstrip().startswith("#"))
        self.assertTrue(re.search(r"(?m)^import install\b", code), "capture.sh imports install.py")
        self.assertEqual(re.findall(r'"simctl",\s*"install"', code), [], "capture.sh installs through install.py")
        self.assertTrue("install.install(run, Failure, udid, APP, name)" in code, "capture.sh installs through it")


if __name__ == "__main__":
    unittest.main()
