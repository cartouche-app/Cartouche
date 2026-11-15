"""Property lists the builder reads but did not write: an app's or an IPA's
Info.plist, the nightly run's agent.

macOS reads a property list more leniently than Python does. An app whose
Info.plist has a stray control character in a string, or a byte its
declared encoding does not have, opens on the Mac and is listed in the
Finder, while Python's XML parser stops at it with an ExpatError ("not
well-formed (invalid token): line 19, column 0"), which is neither a
ValueError nor plistlib's InvalidFileException; a <date> plistlib cannot
read raises an AttributeError, a binary plist's dictionary keyed by a list
a TypeError. Such a file is no game's: read as nothing, it never stops the
builder from reading the others, the library or the Storage page among them.
"""

from __future__ import annotations

import plistlib
from typing import Any


def loads(data: bytes) -> Any | None:
    """DATA's property list, or None when Python cannot read it."""
    try:
        return plistlib.loads(data)
    except Exception:  # noqa: BLE001 - another app's file, whatever plistlib makes of it
        return None
