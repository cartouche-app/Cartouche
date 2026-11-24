"""The builder's words, in English, French, Spanish and German.

t("key", name=value) gives the text in the builder's language: the one the
settings name, else the system's (French, Spanish or German when it is one
of them, English otherwise). The catalog is texts.py.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

from .texts import TEXTS

LANGUAGES = ("en", "fr", "es", "de")
_language: str | None = None


def language_of(tag: str) -> str:
    """The builder's language for TAG, a language as the system writes it:
    "fr_CA.UTF-8" is French, "es-419" Spanish, "de-CH" German, "it" English."""
    base = re.match(r"[a-z]*", tag.lower()).group()
    return base if base in LANGUAGES else "en"


def system_language() -> str:
    for name in ("CARTOUCHE_BUILDER_LANG", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(name, "")
        if value and value not in ("C", "POSIX") and not value.startswith("C."):
            return language_of(value)
    if sys.platform == "darwin":
        try:
            out = subprocess.run(["defaults", "read", "-g", "AppleLanguages"], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        for line in out.splitlines():
            code = line.strip().strip('",()').lower()
            if code:
                return language_of(code)
    return "en"


def set_language(code: str | None) -> None:
    global _language
    _language = code if code in LANGUAGES else None


def language() -> str:
    global _language
    if _language is None:
        _language = system_language()
    return _language


def t(key: str, /, **params: object) -> str:
    """The text of KEY with PARAMS; "<key>.one" when it has one and count is 1."""
    if params.get("count") == 1 and f"{key}.one" in TEXTS:
        key = f"{key}.one"
    entry = TEXTS.get(key)
    if entry is None:
        text = key
    else:
        text = entry[LANGUAGES.index(language())] or entry[0]
    if params:
        try:
            return text.format(**params)
        except (KeyError, IndexError, ValueError):
            return text
    return text
