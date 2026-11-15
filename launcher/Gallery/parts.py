"""The part of the gallery's screenshots or UI tests that one Mac takes,
when the CI shares them between several of GitHub's Macs (screens.yml).

On one Mac each, the screenshots took 60 minutes in the Full test pass
43733690016, 79 in the pass of 0.13.1 (43746649258), and the UI tests on an
iPhone 48: a pull request that changed the launcher waited that long for
them. Shared between three Macs and two, each part takes about half an hour
at most, the gallery's build and the simulator's boot included.

capture.sh --part I/N takes the screenshots of part I of N (scenarios()):
the scenarios drawn at their size on the largest iPad, shared one by one
between the parts before the last, and the scenarios of a device of their
own, each on a simulator of that device, in the last. In the pass
43733690016 the sized scenarios took 2099 s, the iPad's boot included, and
the devices' 1375 s, their three boots included.

uitests.sh --part I/N runs the UI tests of part I of N (options()): the
classes of UITests but the iPad's, which run on an iPad alone, shared by
how many tests each has, the most first, each to the part with the fewest
so far. The parts before the last run their classes alone (-only-testing);
the last runs every class the others do not (-skip-testing), so that a
class added later runs there rather than nowhere.

1/1 is every screenshot, and every UI test but the iPad's.

usage: parts.py tests I/N UITESTS_DIRECTORY
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# The UI tests' target, and the class of the iPad's tests (uitests.sh --ipad).
TARGET = "CartoucheGalleryUITests"
IPAD = "IPadUITests"

# A class of tests: final class StorageUITests: ConsoleTestCase {
CLASS = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*\w*TestCase\b", re.M)
TEST = re.compile(r"\bfunc\s+test\w*\s*\(")


def parse(text: str) -> tuple[int, int]:
    """(I, N) from "I/N", part I of N."""
    found = re.fullmatch(r"(\d+)/(\d+)", text.strip())
    if not found or not 1 <= int(found.group(1)) <= int(found.group(2)):
        raise ValueError(f"not a part: {text!r}, as 1/3 for the first of three")
    return int(found.group(1)), int(found.group(2))


def scenarios(every: list[dict], part: int, parts: int) -> list[dict]:
    """The scenarios of scenarios.json that part PART of PARTS takes, in
    their order there."""
    if parts == 1:
        chosen = list(every)
    elif part == parts:
        chosen = [s for s in every if s.get("device")]
    else:
        chosen = [s for s in every if not s.get("device")][part - 1::parts - 1]
    if not chosen:
        raise ValueError(f"part {part} of {parts} has no scenario: take the screenshots in fewer parts")
    return chosen


def classes(directory: Path) -> dict[str, int]:
    """Each class of UI tests in DIRECTORY's Swift files, but the iPad's,
    with how many tests it has: those after its line and before the next
    class's."""
    found: dict[str, int] = {}
    for path in sorted(directory.glob("*.swift")):
        text = path.read_text()
        heads = list(CLASS.finditer(text))
        for head, after in zip(heads, heads[1:] + [None]):
            tests = len(TEST.findall(text, head.end(), after.start() if after else len(text)))
            if tests and head.group(1) != IPAD:
                found[head.group(1)] = found.get(head.group(1), 0) + tests
    return found


def shared(weights: dict[str, int], parts: int) -> list[list[str]]:
    """The classes of each part, PARTS of them: the one with the most tests
    first, each to the part with the fewest tests so far."""
    loads = [0] * parts
    chosen: list[list[str]] = [[] for _ in range(parts)]
    for name in sorted(weights, key=lambda name: (-weights[name], name)):
        least = loads.index(min(loads))
        chosen[least].append(name)
        loads[least] += weights[name]
    return [sorted(names) for names in chosen]


def options(weights: dict[str, int], part: int, parts: int) -> list[str]:
    """xcodebuild's options for the UI tests of part PART of PARTS."""
    every = shared(weights, parts)
    if part < parts:
        if not every[part - 1]:
            raise ValueError(f"part {part} of {parts} has no UI test: run them in fewer parts")
        return [f"-only-testing:{TARGET}/{name}" for name in every[part - 1]]
    others = sorted(name for names in every[:-1] for name in names)
    return [f"-skip-testing:{TARGET}/{name}" for name in [IPAD, *others]]


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] != "tests":
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        part, parts = parse(argv[2])
        weights = classes(Path(argv[3]))
        if not weights:
            raise ValueError(f"no class of UI tests in {argv[3]}")
        print("\n".join(options(weights, part, parts)))
    except ValueError as error:
        print(f"parts.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
