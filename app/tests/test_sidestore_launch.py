"""Checks that the wait for the built-in SideStore to launch in LiveProcess
always ends (app/patches/livecontainer/0016):

- LiveContainer's bridge (SideStoreSupport/SideStore.swift, RefreshHandler)
  waits through CartoucheSideStoreLaunch (launcher/SideStoreSupport), and
  keeps no continuation of its own that its interruption block could drop:
  a process that quits as it launches ends the wait, with words Cartouche
  reads as SideStore quitting at the stage `launch`; SideStore saying it
  has launched ends it; the five minutes' limit ends its own launch's wait
  alone, and kills that launch's extension only when it did;
- CartoucheSideStoreLaunch itself, built and run with Swift where there is
  one: each launch's wait ends once, whether its end comes before or after
  the wait starts, and the late end of an earlier launch never ends a
  later one's.

LiveContainer's sources are read as app/scripts/prepare.sh leaves them,
every patch applied. Needs the LiveContainer submodule.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_sidestore_outcome import block, patched

ROOT = Path(__file__).resolve().parents[2]
LIVECONTAINER = ROOT / "app" / "LiveContainer"
LIVECONTAINER_PATCHES = ROOT / "app" / "patches" / "livecontainer"
LAUNCH = ROOT / "launcher" / "SideStoreSupport" / "CartoucheSideStoreLaunch.swift"
FAILURE = ROOT / "launcher" / "Sources" / "CartoucheFailure.swift"
BRIDGE = "SideStoreSupport/SideStore.swift"

QUIT_STARTING = "Built-in SideStore quit unexpectedly while starting"
SLOW_START = "Built-in SideStore failed to start in reasonable time"


def table(text: str, name: str) -> str:
    """The lines of CartoucheFailure's table NAME, between its brackets."""
    found = re.search(r"static let " + name + r"[^=]*= \[(.*?)\n    \]", text, re.S)
    if not found:
        raise AssertionError(f"{name} not found")
    return found.group(1)


class SideStoreLaunchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bridge = patched(BRIDGE, LIVECONTAINER, LIVECONTAINER_PATCHES)
        cls.handler = block(cls.bridge, "class RefreshHandler", "RefreshHandler")
        cls.start = block(cls.handler, "func startRefresh(", "RefreshHandler.startRefresh")

    def test_the_bridge_keeps_no_wait_of_its_own(self):
        self.assertNotIn("launchContinuation", self.bridge)
        self.assertIn("let launch = CartoucheSideStoreLaunch()", self.handler)
        # A launch begins once its extension exists, and SideStore is only
        # launched again when no launch is under way.
        self.assertIn("&& !launch.isWaiting {", self.start)
        self.assertLess(self.start.index("self.ext = ext"), self.start.index("let launchNumber = launch.begin()"))

    def test_a_sidestore_that_quits_as_it_launches_ends_the_wait(self):
        interruption = block(self.start, "ext.setRequestInterruptionBlock", "the interruption block")
        self.assertRegex(interruption, r"self\.launch\.end\(launchNumber, with: \.failure\(NSError\(.*"
                         + re.escape(QUIT_STARTING) + r'"\]\)\)\)')
        # The wait starts after the interruption block is set, and after the
        # time limit, whatever came first.
        waits = self.start.index("try await launch.wait(for: launchNumber)")
        self.assertLess(self.start.index("ext.setRequestInterruptionBlock"), waits)
        self.assertLess(self.start.index("DispatchQueue.main.asyncAfter(deadline: .now() + 300)"), waits)

    def test_sidestore_saying_it_launched_ends_the_wait(self):
        finished = block(self.handler, "func finishedLaunching()", "RefreshHandler.finishedLaunching")
        self.assertIn("launch.end(with: .success(()))", finished)

    def test_the_time_limit_ends_its_own_launch_alone(self):
        limit = block(self.start, "DispatchQueue.main.asyncAfter(deadline: .now() + 300)", "the time limit")
        self.assertRegex(limit, r"if self\.launch\.end\(launchNumber, with: \.failure\(NSError\(.*"
                         + re.escape(SLOW_START) + r'"\]\)\)\) \{\s*ext\._kill\(9\)\s*\}')

    def test_cartouche_reads_the_quit_as_it_launches_at_its_stage(self):
        failure = FAILURE.read_text(encoding="utf-8")
        sentences = table(failure, "bridgeSentences")
        prefix = re.search(r'\("([^"]+)", \.sideStoreQuit\)', sentences).group(1)
        self.assertTrue(QUIT_STARTING.startswith(prefix), prefix)
        stages = table(failure, "bridgeStages")
        self.assertIn(f'("{QUIT_STARTING}", "launch")', stages)
        # The bridge's other sentences stay Cartouche's.
        self.assertIn(f'("{SLOW_START}", .sideStoreSlowStart)', sentences)
        self.assertIn('"Built-in SideStore quit unexpectedly"', self.start)

    @unittest.skipUnless(shutil.which("swiftc"), "Needs Swift")
    def test_each_launch_wait_ends_once(self):
        checks = r'''
import Foundation

struct Quit: Error {}

func expectQuit(_ launch: CartoucheSideStoreLaunch, _ number: Int, _ what: String) async {
    do {
        try await launch.wait(for: number)
        fatalError("\(what): the wait went on as if SideStore had launched")
    } catch is Quit {
    } catch {
        fatalError("\(what): \(error)")
    }
}

@main
struct Checks {
    static func main() async {
        // SideStore quits as it launches, before the bridge starts waiting.
        let launch = CartoucheSideStoreLaunch()
        precondition(!launch.isWaiting)
        let first = launch.begin()
        precondition(launch.isWaiting)
        precondition(launch.end(first, with: .failure(Quit())))
        precondition(!launch.isWaiting)
        await expectQuit(launch, first, "quit before the wait")
        // Its time limit, later, finds the wait ended, and kills nothing.
        precondition(!launch.end(first, with: .failure(Quit())))

        // SideStore quits while the bridge waits.
        let second = launch.begin()
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            precondition(launch.end(second, with: .failure(Quit())))
        }
        await expectQuit(launch, second, "quit during the wait")

        // SideStore says it has launched: the wait returns.
        let third = launch.begin()
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            precondition(launch.end(with: .success(())))
        }
        do { try await launch.wait(for: third) } catch { fatalError("launched: \(error)") }
        precondition(!launch.isWaiting)
        // Its process quits later on: the launch is long over.
        precondition(!launch.end(third, with: .failure(Quit())))

        // An earlier launch's time limit, or its process quitting, never
        // ends a later launch's wait.
        let fourth = launch.begin()
        precondition(!launch.end(third, with: .failure(Quit())))
        precondition(launch.isWaiting)
        precondition(launch.end(with: .success(())))
        do { try await launch.wait(for: fourth) } catch { fatalError("later launch: \(error)") }

        // A wait for a launch a later one replaced ends at once.
        let fifth = launch.begin()
        _ = launch.begin()
        do {
            try await launch.wait(for: fifth)
            fatalError("replaced launch: the wait went on")
        } catch is CancellationError {
        } catch {
            fatalError("replaced launch: \(error)")
        }
        print("CartoucheSideStoreLaunch checks passed")
    }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "Checks.swift").write_text(checks, encoding="utf-8")
            built = subprocess.run([
                "swiftc", "-parse-as-library", "-module-name", "LaunchChecks",
                str(LAUNCH), str(folder / "Checks.swift"),
                "-o", str(folder / "checks"), "-module-cache-path", str(folder / "cache"),
            ], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            # A wait that never ends fails here rather than hanging the tests.
            run = subprocess.run([str(folder / "checks")], capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("CartoucheSideStoreLaunch checks passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
