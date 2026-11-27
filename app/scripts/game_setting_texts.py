#!/usr/bin/env python3
"""Lists the texts of nxnative's settings list that Cartouche shows in English.

Cartouche's settings page shows the rows of a game's dm/launcher.json, which
nxnative writes from its dm/games/settings.tsv: a section, each setting's
label and note, and each option of a choice. CartoucheText.gameSettingText
(launcher/Sources/CartoucheText.swift) gives each text it knows in the
reader's language; a text it does not know shows as nxnative wrote it, in
English, on the iPhone and in the console of the Mac.

    python3 app/scripts/game_setting_texts.py SETTINGS_TSV

prints the texts of SETTINGS_TSV (nxnative's dm/games/settings.tsv, at any
commit) that gameSettingText does not know, one a line, and exits 1 when
there is one. The game's languages are not among them: iOS names those
(CartoucheText.languageName).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "launcher" / "Sources" / "CartoucheText.swift"

# A frame rate, "60 fps", which gameSettingText writes in the reader's
# language whatever its number.
FRAME_RATE = re.compile(r"^\d+ fps$")
# A multiplier, "16x" (Texture filtering), the same in every language.
MULTIPLIER = re.compile(r"^\d+x$")
# Names, the same in every language: Apple's upscaler (Upscaling).
NAMES = {"MetalFX"}


def texts(tsv: str) -> list[str]:
    """The texts the rows of TSV show, in their order, once each: the
    sections, each setting's label and note, and the label of each option of
    a choice, without the condition after its "?"."""
    found: list[str] = []

    def add(text: str) -> None:
        text = text.strip()
        if text and text not in found:
            found.append(text)

    for line in tsv.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) < 7:
            continue
        kind, values, section, label = columns[1], columns[2], columns[5], columns[6]
        note = columns[7] if len(columns) > 7 else ""
        add(section)
        add(label)
        add(note)
        if kind == "choice" and values != "languages":
            for option in values.split(","):
                value_label = option.split("?", 1)[0].split("=", 1)
                if len(value_label) == 2:
                    add(value_label[1])
    return found


def known(swift: str) -> set[str]:
    """The texts gameSettingText knows: the patterns of its switch's cases."""
    start = swift.index("static func gameSettingText(")
    end = swift.index("default:", start)
    known_texts: set[str] = set()
    for case in re.findall(r'^\s*case (.+?):\s*(?:return|$)', swift[start:end], re.MULTILINE):
        for text in re.findall(r'"((?:[^"\\]|\\.)*)"', case):
            known_texts.add(text.replace('\\"', '"').replace("\\\\", "\\"))
    return known_texts


def untranslated(found: list[str], known_texts: set[str]) -> list[str]:
    """The texts of FOUND that show in English: neither known, nor a frame
    rate, a multiplier or a name."""
    return [text for text in found
            if text not in known_texts and text not in NAMES and not FRAME_RATE.match(text) and not MULTIPLIER.match(text)]


def main(arguments: list[str]) -> int:
    if len(arguments) != 1:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: game_setting_texts.py SETTINGS_TSV", file=sys.stderr)
        return 2
    missing = untranslated(texts(Path(arguments[0]).read_text(encoding="utf-8")), known(SWIFT.read_text(encoding="utf-8")))
    for text in missing:
        print(text)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
