"""The showcase page in each of its four languages, each at its own address.

    python3 site/tools/languages.py build/site

site/index.html holds every text in French, English, Spanish and German,
side by side, and shows the visitor's language. A search engine finds a page
by its address and reads it in one language: for the publication, this
writes the page once per language, from the copy of index.html in the folder
it is given, which it replaces with the English one (decision 175).

- English at the root, index.html; French, Spanish and German in fr/, es/
  and de/, each an index.html.
- Each page holds its own language's texts only: an element of the page in
  another language (lang="…") is left out, and the title, the description and
  what a shared link shows are in its language. The screens the script draws
  keep their four languages, as their texts are the script's.
- Each page names its own address (canonical, og:url), its language (html
  lang, og:locale), and the four pages (hreflang, the English one for any
  other language, x-default), as the page's head lists them, and says its
  language in data-page-lang: the page's script shows that one, and the
  English page sends a visitor who reads another on to theirs.
- What search engines read of the app (application/ld+json) gives the page's
  description and language.

The page's links to its icons and to the download page start from the site's
root, so that they lead to the same files from every page.
"""

from __future__ import annotations

import html
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SITE_URL = "https://cartouche.cloud/"
LANGUAGES = ("en", "fr", "es", "de")
LOCALES = {"en": "en_US", "fr": "fr_FR", "es": "es_ES", "de": "de_DE"}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class Problem(Exception):
    """The page is not as the publication expects it: nothing is written."""


def address(language: str) -> str:
    """The address of the page in LANGUAGE."""
    return SITE_URL + ("" if language == "en" else language + "/")


def folder(language: str) -> str:
    return "" if language == "en" else language + "/"


class _Elements(HTMLParser):
    """Where each element of the page in another language than KEEP starts
    and ends, in the page's text. Scripts and styles are text to the parser,
    so the texts the script holds stay."""

    def __init__(self, text: str, keep: str) -> None:
        super().__init__(convert_charrefs=False)
        self.text = text
        self.keep = keep
        self.lines = [0] + [m.end() for m in re.finditer("\n", text)]
        self.stack: list[str] = []
        self.cut: tuple[int, int, str] | None = None
        self.cuts: list[tuple[int, int]] = []

    def position(self) -> int:
        line, column = self.getpos()
        return self.lines[line - 1] + column

    def other(self, attrs: list[tuple[str, str | None]]) -> bool:
        lang = dict(attrs).get("lang")
        return lang in LANGUAGES and lang != self.keep

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in VOID:
            self.handle_startendtag(tag, attrs)
            return
        self.stack.append(tag)
        if self.cut is None and tag != "html" and self.other(attrs):
            self.cut = (self.position(), len(self.stack), tag)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.cut is None and self.other(attrs):
            start = self.position()
            self.cuts.append((start, start + len(self.get_starttag_text() or "")))

    def handle_endtag(self, tag: str) -> None:
        if tag in VOID or tag not in self.stack:
            return
        while self.stack.pop() != tag:
            pass
        if self.cut is not None and len(self.stack) < self.cut[1]:
            start, _, opened = self.cut
            if tag != opened:
                raise Problem(f"<{opened} lang> at {start} ends with </{tag}>")
            end = self.text.index(">", self.position()) + 1
            self.cuts.append((start, end))
            self.cut = None


def keep_only(text: str, language: str) -> str:
    """TEXT without its elements in the other three languages."""
    parser = _Elements(text, language)
    parser.feed(text)
    parser.close()
    if parser.cut is not None:
        raise Problem(f"<{parser.cut[2]} lang> at {parser.cut[0]} never ends")
    kept, at = [], 0
    for start, end in parser.cuts:
        kept.append(text[at:start])
        at = end
    kept.append(text[at:])
    return "".join(kept)


ATTRIBUTE = re.compile(r'\s([\w:-]+)="([^"]*)"')


def _in_language(tag: str, language: str) -> str:
    """A tag whose words the page gives in the four languages (data-fr…),
    with those of LANGUAGE alone: content= takes them, and the four go."""
    found = dict(ATTRIBUTE.findall(tag))
    words = found.get("data-" + language)
    if words is None:
        raise Problem(f"{tag[:60]}… has no words in {language}")
    tag = re.sub(r'\sdata-(?:fr|en|es|de)="[^"]*"', "", tag)
    if 'content="' in tag:
        tag = re.sub(r'\scontent="[^"]*"', lambda m: f' content="{words}"', tag, count=1)
    return tag


def _one(pattern: str, text: str, what: str) -> re.Match[str]:
    found = list(re.finditer(pattern, text))
    if len(found) != 1:
        raise Problem(f"the page has {len(found)} {what}, not one")
    return found[0]


def _replace(text: str, match: re.Match[str], new: str) -> str:
    return text[:match.start()] + new + text[match.end():]


def page_in(text: str, language: str) -> str:
    """The page in LANGUAGE, from site/index.html."""
    text = keep_only(text, language)
    tag = _one(r'<html lang="en" data-lang="en">', text, "<html lang=\"en\" data-lang=\"en\">")
    text = _replace(text, tag, f'<html lang="{language}" data-lang="{language}" data-page-lang="{language}">')
    # The title, the description and what a shared link shows.
    title = _one(r"<title\s[^>]*>[^<]*</title>", text, "<title>")
    words = dict(ATTRIBUTE.findall(title.group(0))).get("data-" + language)
    if words is None:
        raise Problem(f"the title has no words in {language}")
    text = _replace(text, title, f"<title>{words}</title>")
    for name in (r'name="description"', r'property="og:title"', r'property="og:description"'):
        meta = _one(rf"<meta {name}[^>]*>", text, f"<meta {name}>")
        text = _replace(text, meta, _in_language(meta.group(0), language))
    # Its address, its language and the three others.
    for pattern, new in (
        (r'<link rel="canonical" href="[^"]*">', f'<link rel="canonical" href="{address(language)}">'),
        (r'<meta property="og:url" content="[^"]*">', f'<meta property="og:url" content="{address(language)}">'),
        (r'<meta property="og:locale" content="[^"]*">', f'<meta property="og:locale" content="{LOCALES[language]}">'),
    ):
        text = _replace(text, _one(pattern, text, pattern), new)
    alternates = list(re.finditer(r'<meta property="og:locale:alternate" content="[^"]*">', text))
    others = [LOCALES[other] for other in LANGUAGES if other != language]
    if len(alternates) != len(others):
        raise Problem(f"the page has {len(alternates)} og:locale:alternate, not {len(others)}")
    for match, locale in reversed(list(zip(alternates, others))):
        text = _replace(text, match, f'<meta property="og:locale:alternate" content="{locale}">')
    hreflang = dict(re.findall(r'<link rel="alternate" hreflang="([\w-]+)" href="([^"]*)">', text))
    expected = {**{other: address(other) for other in LANGUAGES}, "x-default": address("en")}
    if hreflang != expected:
        raise Problem(f"the page's hreflang links are {hreflang}, not {expected}")
    # What search engines read of the app.
    data = _one(r'(?s)<script type="application/ld\+json">\n(.*?)\n</script>', text, "application/ld+json")
    graph = json.loads(data.group(1))
    description = dict(ATTRIBUTE.findall(_one(r'<meta name="description"[^>]*>', text, "description").group(0)))["content"]
    for node in graph["@graph"]:
        if node["@type"] == "WebSite":
            node["inLanguage"] = language
        if node["@type"] == "SoftwareApplication":
            node["description"] = html.unescape(description)
    written = json.dumps(graph, ensure_ascii=False, indent=4).replace("</", "<\\/")
    written = re.sub(r'\[\n\s+("[^"\n]*"(?:,\n\s+"[^"\n]*")*)\n\s+\]', lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",\n")) + "]", written)
    text = text[:data.start(1)] + written + text[data.end(1):]
    # No element in another language is left, outside the script.
    body = re.sub(r"<script\b.*?</script>", "", text[text.index("<body"):], flags=re.S)
    left = re.findall(r'<\w+\b[^>]*\slang="(?!' + language + r'")(?:fr|en|es|de)"', body)
    if left:
        raise Problem(f"the page in {language} keeps {len(left)} elements in other languages")
    return text


def write(directory: Path) -> list[Path]:
    """Write the four pages from DIRECTORY/index.html, the English one in its
    place: the pages written."""
    source = directory / "index.html"
    text = source.read_text(encoding="utf-8")
    pages = {language: page_in(text, language) for language in LANGUAGES}
    written = []
    for language, page in pages.items():
        path = directory / folder(language) / "index.html"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(page, encoding="utf-8")
        written.append(path)
    return written


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    try:
        for path in write(Path(argv[1])):
            print(f"{path}: {path.stat().st_size:,} bytes")
    except Problem as problem:
        print(f"languages.py: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
