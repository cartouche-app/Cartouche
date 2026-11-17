"""The Mac app's gallery (mac/Sources/CartoucheBuilder/Gallery.swift), which
the Builder workflow runs on a Mac of GitHub's for each pull request: a page
whose window is taller than the gallery's usual one is in a window as tall
as the page, which AppKit would otherwise fit to the runner's screen, too
small for it, as it did the console's System page (17 November): the
picture showed its top alone.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

GALLERY = Path(__file__).resolve().parents[1] / "mac" / "Sources" / "CartoucheBuilder" / "Gallery.swift"
# A page, `.consoleSystem`, not a call such as `.contains(self)`.
PAGE = re.compile(r"\.(\w+)\b(?!\()")


def _property(swift: str, name: str) -> str:
    """The body of the computed property NAME of the gallery's pages."""
    match = re.search(rf"\bvar {name}: \w+ \{{", swift)
    if not match:
        raise ValueError(f"no {name}")
    depth, at = 1, match.end()
    while depth:
        depth += {"{": 1, "}": -1}.get(swift[at], 0)
        at += 1
    return swift[match.end():at - 1]


def heights(swift: str) -> tuple[dict[str, int], int]:
    """The pages the property `size` gives a height of their own, with it,
    and the height of the others'."""
    body = _property(swift, "size")
    pages = {}
    for cases, height in re.findall(r"case ([^:\n]+): return CGSize\(width: [^,]+, height: (\d+)\)", body):
        for case in re.findall(r"\.(\w+)", cases):
            pages[case] = int(height)
    usual = re.search(r"default: return CGSize\(width: [^,]+, height: (\d+)\)", body)
    return pages, int(usual.group(1))


def tall(swift: str) -> set[str]:
    """The pages in a window as tall as they are (Page.isTall)."""
    body = _property(swift, "isTall")
    pages = set(PAGE.findall(body))
    if "isWholeSheet" in body:
        pages |= set(PAGE.findall(_property(swift, "isWholeSheet")))
    return pages


class GalleryWindows(unittest.TestCase):
    def test_a_page_taller_than_the_usual_window_is_in_a_window_as_tall(self):
        swift = GALLERY.read_text()
        pages, usual = heights(swift)
        taller = {page for page, height in pages.items() if height > usual}
        self.assertIn("consoleSystem", taller)
        self.assertEqual(taller - tall(swift), set(),
                         "these pages are taller than the screen of GitHub's Macs: Page.isTall must list them")

    def test_the_check_reads_a_page_left_out(self):
        swift = """
        var isWholeSheet: Bool { self == .sheet }
        var isTall: Bool {
            isWholeSheet || [.storage].contains(self)
        }
        var size: CGSize {
            switch self {
            case .storage: return CGSize(width: 1024, height: 1260)
            case .sheet, .system: return CGSize(width: 1024, height: 980)
            case .narrow: return CGSize(width: Columns.window.width, height: 680)
            default: return CGSize(width: 1220, height: 780)
            }
        }
        """
        pages, usual = heights(swift)
        self.assertEqual(usual, 780)
        self.assertEqual(pages, {"storage": 1260, "sheet": 980, "system": 980, "narrow": 680})
        self.assertEqual(tall(swift), {"storage", "sheet"})


if __name__ == "__main__":
    unittest.main()
