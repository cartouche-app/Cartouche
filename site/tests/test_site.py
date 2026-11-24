"""What the showcase page may show, load and link to.

    python3 -m unittest discover -s site/tests -v

The page shows Cartouche with games of nxnative's list, their covers and
artworks loaded from IGDB by the IDs of catalog/covers.json, as the app loads
them; it carries no image of a game. Besides those images it loads nothing
from another site, and it links only to Cartouche's repository, nxnative's,
IGDB, Cartouche's Discord server and Cartouche Cloud's site: never to a game,
a dump, an IPA, a catalog of games, keys or firmware, nor to another server of
the project (docs/decisions.md, 40, amended by 129 and 138). It says what
Cartouche Cloud does for a player with no Mac, never its price. Its only
downloads are the project's own programs for a computer, the Cartouche
Installer and Cartouche for Mac, each a file of their releases marked for
the publication to give its newest one (site/tools/downloads.py), as the
download page, download/index.html, gives them too. Its only pictures are
its own drawings, never a game's: the icon an iPhone puts on its Home
Screen, and the picture a link to the site shows where it is shared
(social.png, drawn from tools/social.html). 404.html is the page GitHub Pages
serves for an address the site does not have.

A catalog change that touches a game of the page (its name, its covers, where
nxnative plays it) fails here: update the list at the top of the page's
script, <script id="games">, as the message says.
"""

from __future__ import annotations

import colorsys
import json
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path

SITE = Path(__file__).resolve().parents[1]
PAGE = SITE / "index.html"
DOWNLOAD_PAGE = SITE / "download" / "index.html"
NOT_FOUND_PAGE = SITE / "404.html"
CATALOG = SITE.parent / "catalog"

# The files the site offers, straight from this repository's releases: the
# Cartouche Installer for Mac and for Windows, and Cartouche for Mac. A link
# to one is marked data-download="<file>", for the publication to give it the
# newest release (site/tools/downloads.py).
REPOSITORY = "https://github.com/cartouche-app/Cartouche"
DOWNLOADS = {
    "builder": re.compile(re.escape(REPOSITORY) + r"/releases/download/builder-v(\d+\.\d+\.\d+)/Cartouche-Builder-\1\.dmg"),
    "installer-mac": re.compile(re.escape(REPOSITORY) + r"/releases/download/installer-v(\d+\.\d+\.\d+)/Cartouche-Installer-\1-Mac\.dmg"),
    "installer-windows": re.compile(re.escape(REPOSITORY) + r"/releases/download/installer-v(\d+\.\d+\.\d+)/Cartouche-Installer-\1-Windows\.exe"),
}

# The project's Discord server, by the one invite its bot keeps, which never
# expires (decided by Ad on 17 Nov).
DISCORD = "https://discord.gg/wG3DZjdAeF"

# Cartouche Cloud's own site, which builds a player's games on its Macs from
# the copy they send it, for a player with no Mac (decision 138): the page
# links to its first page and to its privacy notice, and to nothing else of
# it.
CLOUD = "https://build.cartouche.cloud/"

# Every absolute link the page may hold, whole: the repository and its pages,
# the files above, the Discord server, nxnative, IGDB, which the page credits,
# and Cartouche Cloud's site.
ALLOWED_LINKS = [
    re.compile(re.escape(REPOSITORY)),
    re.compile(re.escape(REPOSITORY) + r"/blob/main/[\w/.-]+\.md(?:#[\w-]+)?"),
    re.compile(re.escape(REPOSITORY) + r"/issues/new/choose"),
    re.compile(re.escape(DISCORD)),
    *DOWNLOADS.values(),
    re.compile(r"https://github\.com/seedds/nxnative"),
    re.compile(r"https://www\.igdb\.com"),
    re.compile(re.escape(CLOUD) + r"(?:privacy)?"),
]

# A price, in any currency the page could name: Cartouche Cloud's stays on its
# own site and in the app, which read it from the service (the owner,
# 2026-11-18).
PRICE = re.compile(r"(?i)[$€£]\s?\d|\d(?:[\s\u00a0\u202f]?[$€£]|\s?(?:usd|eur|dollars?|euros?)\b)")

# The one other site the page loads from: IGDB's image server, at the sizes
# IGDB names, for the IDs of catalog/covers.json.
IGDB = "https://images.igdb.com/igdb/image/upload/"
IGDB_HOST = "https://images.igdb.com"
IGDB_SIZES = {"t_cover_small", "t_cover_big", "t_cover_big_2x", "t_screenshot_med", "t_screenshot_big", "t_720p", "t_1080p"}

# Files of games, keys, firmware and what carries them.
GAME_FILES = re.compile(
    r"\.(ipa|nsp|nsz|xci|xcz|nca|ncz|nro|nso|nup|kip|keys|bin|zip|7z|rar|tar|gz|torrent|dmg|pkg)\b",
    re.IGNORECASE,
)

# Files the site is made of, and nothing else: no image of a game. CNAME
# names the site's domain for GitHub Pages. Its two pictures, each by its name
# and size: the icon an iPhone puts on its Home Screen (Cartouche's, from
# app/icon) and the picture a link to the site shows where it is shared, drawn
# from tools/social.html.
SITE_FILES = {".html", ".svg", ".md", ".py"}
PICTURES = {"apple-touch-icon.png": (180, 180), "social.png": (1200, 630)}
SITE_NAMES = {"CNAME", *PICTURES}

# The site's address, at its domain.
SITE_URL = "https://" + (SITE / "CNAME").read_text(encoding="utf-8").strip() + "/"


def job_text(workflow: Path, key: str) -> str:
    """The lines of the job KEY of WORKFLOW, up to the next job: the tests
    read the workflows as text, with nothing to install."""
    text = workflow.read_text(encoding="utf-8")
    start = text.index(f"\n  {key}:\n")
    following = re.search(r"\n  [A-Za-z0-9_-]+:\n", text[start + 1:])
    return text[start:start + 1 + following.start()] + "\n" if following else text[start:]


def png_size(path: Path) -> tuple[int, int]:
    """A PNG's width and height, from its header."""
    data = path.read_bytes()[:24]
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", f"{path.name} is not a PNG"
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")

# What the page may say of a game: its status on the page, and where
# nxnative must play it for the page to say so.
STATUSES = {"ready": "iphone", "stored": "iphone", "iphone": "iphone", "mac": "mac"}


class Page(HTMLParser):
    """The page's tags, with their attributes, its scripts and styles, and
    the rest of its text."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: list[tuple[str, dict[str, str]]] = []
        self.ids: set[str] = set()
        self.scripts: list[tuple[dict[str, str], str]] = []
        self.styles: list[str] = []
        self.words: list[str] = []
        self._in: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        self.tags.append((tag, values))
        if "id" in values:
            self.ids.add(values["id"])
        if tag == "script":
            self._in = tag
            self.scripts.append((values, ""))
        elif tag == "style":
            self._in = tag
            self.styles.append("")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        if tag == self._in:
            self._in = None

    def handle_data(self, data: str) -> None:
        if self._in == "script":
            attrs, text = self.scripts[-1]
            self.scripts[-1] = (attrs, text + data)
        elif self._in == "style":
            self.styles[-1] += data
        else:
            self.words.append(data)


# The Mac's app is Cartouche, as on the iPhone, called Cartouche for Mac where
# the site tells it from the iPhone's; only its folder on the Mac keeps the
# name it had until then (builder/tests/test_app_name.py).
FORMER_NAME = re.compile(r"Cartouche Builder(?!/)")


def check_the_mac_app_is_cartouche(test: unittest.TestCase, text: str) -> None:
    test.assertEqual(FORMER_NAME.findall(text), [], "the Mac's app is Cartouche for Mac now")
    test.assertIn("Cartouche for Mac", text)
    test.assertIn("Cartouche pour Mac", text)


def read_page(path: Path = PAGE) -> tuple[str, Page]:
    text = path.read_text(encoding="utf-8")
    page = Page()
    page.feed(text)
    page.close()
    return text, page


def download_of(href: str) -> str | None:
    """The file of the site's downloads a link gives, if it gives one."""
    return next((key for key, pattern in DOWNLOADS.items() if pattern.fullmatch(href)), None)


def check_shared(test: unittest.TestCase, page: Page, address: str) -> None:
    """A page's own address, at the site's domain, and what a link to it
    shows where it is shared (Discord, Reddit, Messages…): the site's own
    picture, social.png, and its icon for an iPhone's Home Screen."""
    links = {attrs.get("rel"): attrs.get("href", "") for tag, attrs in page.tags if tag == "link"}
    metas = {attrs.get("property", attrs.get("name")): attrs.get("content", "") for tag, attrs in page.tags if tag == "meta"}
    test.assertEqual(links.get("canonical"), address)
    test.assertEqual(metas.get("og:url"), address)
    test.assertEqual(metas.get("og:site_name"), "Cartouche")
    test.assertTrue(metas.get("og:title") and metas.get("og:description"))
    test.assertEqual(metas.get("og:image"), SITE_URL + "social.png")
    test.assertEqual((metas.get("og:image:width"), metas.get("og:image:height")), tuple(str(n) for n in PICTURES["social.png"]))
    test.assertTrue(metas.get("og:image:alt"))
    test.assertEqual(metas.get("twitter:card"), "summary_large_image")
    # Every address the page gives other sites is the site's own.
    for name, content in metas.items():
        if "//" in content:
            test.assertTrue(content.startswith(SITE_URL), f"<meta {name}> names {content!r}")
    icon = links.get("apple-touch-icon", "")
    test.assertRegex(icon, r"^(?:\.\./|/)?apple-touch-icon\.png$")


# What a page says to its visitor besides its elements' text.
SAID = ("content", "data-fr", "data-en", "data-es", "data-de", "aria-label", "data-label-fr", "data-label-en", "data-label-es", "data-label-de", "title", "alt")


# The site's languages, in the order each text gives them.
LANGUAGES = ("fr", "en", "es", "de")


def check_languages(test: unittest.TestCase, text: str, least: int) -> None:
    """Every text of a page in the four languages: each element in French
    followed by its twins in English, Spanish and German, each label and
    description in the four too."""
    body = text[text.index("<body>"):]
    found = re.findall(r'<(\w+)\b[^>]*\slang="(fr|en|es|de)"', body)
    tags = {language: [tag for tag, lang in found if lang == language] for language in LANGUAGES}
    for language in LANGUAGES[1:]:
        test.assertEqual(tags["fr"], tags[language], f"the page's French and {language} elements differ")
    test.assertGreater(len(tags["fr"]), least)
    for language in LANGUAGES:
        test.assertEqual(len(re.findall(rf"data-label-{language}=", text)), len(re.findall(r"data-label-fr=", text)), language)
        test.assertIn(f'data-{language}="', text)
    # The script that picks the language before the page is drawn knows the four.
    for language in LANGUAGES:
        test.assertIn(f'data-set-lang="{language}"', text)
        test.assertIn(f'html:not([data-lang="{language}"]) [lang="{language}"]', text)


def check_downloads(test: unittest.TestCase, text: str, page: Page) -> dict[str, str]:
    """Each download of a page: a file of its releases, marked as that file,
    one release for each file wherever the page links to it, and no version
    said: a button says what it downloads, not which version (the owner,
    2026-11-10). The version of each file."""
    versions: dict[str, set[str]] = {}
    for tag, attrs in page.tags:
        key = download_of(attrs.get("href", "")) if tag == "a" else None
        if key or "data-download" in attrs:
            test.assertEqual(attrs.get("data-download"), key, f"<{tag} href={attrs.get('href')!r}> is marked data-download={attrs.get('data-download')!r}")
            versions.setdefault(key, set()).add(DOWNLOADS[key].fullmatch(attrs["href"]).group(1))
    for key, found in versions.items():
        test.assertEqual(len(found), 1, f"{key}: the page links to {sorted(found)}")
    # The Installer's two files are one release.
    if "installer-mac" in versions and "installer-windows" in versions:
        test.assertEqual(versions["installer-mac"], versions["installer-windows"])
    # Only links are marked, and nothing the visitor reads names a version.
    test.assertNotRegex(text, r"\sdata-download-")
    said = page.words + [value for tag, attrs in page.tags for name, value in attrs.items() if name in SAID]
    for words in said:
        test.assertNotRegex(words, r"(?i)\bversion\s+\d")
        for found in versions.values():
            for version in found:
                test.assertNotRegex(words, r"(?<![\d.])" + re.escape(version) + r"(?![\d.])", f"the page says the version {version}")
    return {key: found.pop() for key, found in versions.items()}


def app_colors(title_id: str) -> tuple[str, str]:
    """CartoucheTheme.colors(for:): a hue from the FNV-1a hash of the title
    ID, a light colour and a deep one."""
    value = 0xCBF29CE484222325
    for byte in title_id.encode():
        value = ((value ^ byte) * 0x100000001B3) % (1 << 64)
    hue = (value % 360) / 360

    def color(h: float, s: float, b: float) -> str:
        return "#" + "".join(f"{round(c * 255):02X}" for c in colorsys.hsv_to_rgb(h, s, b))

    return color(hue, 0.62, 0.90), color((hue + 0.07) % 1, 0.80, 0.40)


class SiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text, cls.page = read_page()
        cls.code = "\n".join(text for attrs, text in cls.page.scripts if attrs.get("type") != "application/json")
        data = [text for attrs, text in cls.page.scripts if attrs.get("id") == "games"]
        cls.games = json.loads(data[0]) if len(data) == 1 else []
        # Links the script writes into the screens: href="#…" in its markup
        # and href: "#…" in its data.
        cls.script_links = re.findall(r'href="([^"\']+)"', cls.code) + re.findall(r'href:\s*"([^"]+)"', cls.code)

    def links(self) -> list[str]:
        return [attrs["href"] for tag, attrs in self.page.tags if tag == "a" and "href" in attrs] + self.script_links

    def test_loads_nothing_from_another_site_but_igdb_images(self) -> None:
        for tag, attrs in self.page.tags:
            for name in ("src", "srcset", "poster", "data", "action", "formaction"):
                value = attrs.get(name, "")
                self.assertNotRegex(value, r"^(?:[a-z][a-z0-9+.-]*:|//)", f"<{tag} {name}> loads {value!r}")
            if tag == "link":
                href = attrs.get("href", "")
                # A connection made early to IGDB's image server, nothing
                # loaded, and the page's own address, at the site's domain.
                if attrs.get("rel") == "preconnect":
                    self.assertEqual(href, IGDB_HOST)
                elif attrs.get("rel") == "canonical":
                    self.assertEqual(href, SITE_URL)
                else:
                    self.assertNotRegex(href, r"^(?:[a-z][a-z0-9+.-]*:|//)", f"<link> loads {href!r}")
            self.assertNotIn(tag, ("iframe", "embed", "object", "form", "base", "video", "audio"), f"the page has an <{tag}>")
            if tag == "script":
                self.assertNotIn("src", attrs, "the page's script is its own, inline")
        for style in self.page.styles:
            self.assertNotIn("@import", style)
            for url in re.findall(r"url\(\s*['\"]?([^'\")]+)", style):
                self.assertFalse(re.match(r"(?:[a-z][a-z0-9+.-]*:|//)", url) and not url.startswith("data:"), f"the styles load {url!r}")
        # The only address the script builds is IGDB's image server's, at
        # IGDB's sizes; every other address in it is a link the page may hold.
        self.assertEqual(self.code.count('"' + IGDB + '"'), 1, "the script names IGDB's image server once")
        for url in re.findall(r"""(?:https?:)?//[^\s"'<>)\\]+""", self.code):
            self.assertTrue(url == IGDB or any(p.fullmatch(url) for p in ALLOWED_LINKS), f"the script holds {url!r}")
        for size in re.findall(r'"(t_\w+)"', self.code):
            self.assertIn(size, IGDB_SIZES)
        # The images are sent without the page's address.
        self.assertRegex(self.text, r'<meta name="referrer" content="no-referrer">')
        # Nothing else reaches a server from the page: no request, beacon or cookie.
        for call in ("fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "EventSource", "document.cookie", "import(", "new Image", "navigator.", "Worker("):
            if call == "navigator.":
                # The page reads the browser's languages, nothing else of it.
                self.assertEqual(set(re.findall(r"navigator\.(\w+)", self.text)), {"languages", "language"})
                continue
            self.assertNotIn(call, self.code)

    def test_a_shared_link_shows_the_sites_own_picture(self) -> None:
        check_shared(self, self.page, SITE_URL)

    def test_links_only_to_the_projects_repositories_and_igdb(self) -> None:
        for href in self.links():
            if href.startswith("#"):
                self.assertIn(href[1:], self.page.ids, f"{href} leads nowhere on the page")
            elif href == "download/":
                # The site's download page, beside it on Pages.
                self.assertTrue(DOWNLOAD_PAGE.is_file())
            else:
                self.assertTrue(any(p.fullmatch(href) for p in ALLOWED_LINKS), f"the page links to {href!r}")

    def test_icons_are_the_pages_own(self) -> None:
        for tag, attrs in self.page.tags:
            if tag == "use":
                href = attrs.get("href", attrs.get("xlink:href", ""))
                self.assertTrue(href.startswith("#") and href[1:] in self.page.ids, f"<use> of {href!r}")
        for name in set(re.findall(r'<use href="#([\w-]+)"', self.code)):
            self.assertIn(name, self.page.ids)
        for name in set(re.findall(r'ic\("([\w-]+)"', self.code) + re.findall(r'icon:\s*"([\w-]+)"', self.code)):
            self.assertIn("i-" + name, self.page.ids, f"{name!r} has no symbol")

    def test_no_game_download_or_dump(self) -> None:
        for tag, attrs in self.page.tags:
            self.assertNotIn("download", attrs, f"<{tag} download>")
            for name in ("href", "src"):
                # The project's own Installer and Builder aside.
                if name == "href" and tag == "a" and download_of(attrs.get(name, "")):
                    continue
                self.assertNotRegex(attrs.get(name, ""), GAME_FILES, f"<{tag} {name}> is a file of a game, keys or an archive")
        for href in self.links():
            if download_of(href):
                continue
            self.assertNotRegex(href, GAME_FILES)
            self.assertFalse(href.startswith(("magnet:", "ftp:", "smb:", "sftp:", "s3:")), href)
        # The site holds its page, its icon, its notes and its tests: no image
        # of a game, which IGDB serves.
        for path in SITE.rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                self.assertTrue(path.suffix in SITE_FILES or path.name in SITE_NAMES, f"{path.relative_to(SITE)} is not a file the site is made of")
                self.assertLess(path.stat().st_size, 512 * 1024, f"{path.relative_to(SITE)} is too large for the site")
        self.assertEqual(sorted(p.name for p in SITE.glob("*.svg")), ["favicon.svg"])
        self.assertEqual(sorted(p.relative_to(SITE).as_posix() for p in SITE.rglob("*.png")), sorted(PICTURES))
        for name, size in PICTURES.items():
            self.assertEqual(png_size(SITE / name), size, name)

    def test_downloads_are_the_installer_and_the_builder(self) -> None:
        # Each button gives the file itself, Mac and Windows for the
        # Installer, with no version beside it.
        versions = check_downloads(self, self.text, self.page)
        self.assertEqual(sorted(versions), sorted(DOWNLOADS))
        buttons = [attrs["data-download"] for tag, attrs in self.page.tags if tag == "a" and "data-download" in attrs]
        self.assertEqual(buttons, ["builder", "installer-mac", "installer-windows", "builder"])

    def test_the_mac_app_is_cartouche_for_mac(self) -> None:
        check_the_mac_app_is_cartouche(self, self.text)

    def test_no_server_address_or_secret(self) -> None:
        for path in [PAGE, DOWNLOAD_PAGE, NOT_FOUND_PAGE, SITE / "favicon.svg", SITE / "tools" / "social.html"]:
            # Drawings' numbers aside: an icon's path can read like an address.
            text = re.sub(r'\s(?:d|points|viewBox|transform)="[^"]*"', "", path.read_text(encoding="utf-8"))
            for pattern, what in (
                (r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "an IP address"),
                (r"(?i)workers\.dev|\.local\b|localhost|telemetry\.|r2\.dev|amazonaws\.com|\.lan\b", "a server"),
                (r"[a-z]+://[^/\s\"']*@", "credentials in a URL"),
                (r"(?i)(?:api[_-]?key|secret|token|password|client[_-]?id)\s*[:=]\s*['\"]\w", "a secret"),
            ):
                found = re.search(pattern, text)
                self.assertIsNone(found, f"{path.name} holds {what}: {found and found.group(0)!r}")

    def test_every_text_in_the_four_languages(self) -> None:
        # Static text: each element in French is followed by its twins in
        # English, Spanish and German.
        check_languages(self, self.text, 100)
        for tag, attrs in self.page.tags:
            if "data-label-fr" in attrs:
                self.assertIn("aria-label", attrs, f"<{tag}> has no label before the script names it")
        # The screens' texts: each call of t() and each group of words the
        # script holds gives the four.
        for call in re.findall(r"(?<![\w.])t\(([^()]*(?:\([^()]*\)[^()]*)*)\)", self.code):
            if call == "fr, en, es, de":
                continue
            self.assertNotRegex(call, r'^"[^"]*", "[^"]*"$', f"t({call}) has two languages")
        self.assertNotRegex(self.code, r'\[\s*"[^"]*",\s*"[^"]*"\s*\]', "a group of words in two languages")
        # The games' examples, in the four languages too.
        for game in self.games:
            for key in ("time", "sessions", "size", "detail", "stored"):
                if key in game:
                    self.assertEqual(len(game[key]), 4, f"{game['name']}: {key}")
                    self.assertTrue(all(game[key]), f"{game['name']}: {key}")

    def test_the_discord_server_by_its_one_invite(self) -> None:
        # In the header beside GitHub, in the footer, and in the FAQ's answer on help.
        discord = [attrs for tag, attrs in self.page.tags if tag == "a" and "discord" in attrs.get("href", "")]
        self.assertEqual({attrs["href"] for attrs in discord}, {DISCORD})
        self.assertEqual(len(discord), 6, "header, footer, and the FAQ's answer in each of the four languages")
        self.assertIn('<a class="gh" href="' + DISCORD + '"', self.text)
        self.assertIn('<use href="#i-discord"/>', self.text)
        self.assertNotRegex(self.text, r"(?i)discord(?:app)?\.com/invite|discord\.gg/(?!wG3DZjdAeF\b)")

    def test_cartouche_cloud_without_its_price(self) -> None:
        # Its section, from the header too, says what it does and leads to
        # its site; the FAQ, to its privacy notice.
        self.assertIn("cloud", self.page.ids)
        self.assertIn('<a href="#cloud">', self.text[: self.text.index("<main>")])
        self.assertEqual({href for href in self.links() if href.startswith(CLOUD)}, {CLOUD, CLOUD + "privacy"})
        # Nothing the page says gives what a build costs.
        for path in (PAGE, DOWNLOAD_PAGE, NOT_FOUND_PAGE):
            text, page = read_page(path)
            said = page.words + [value for tag, attrs in page.tags for name, value in attrs.items() if name in SAID]
            said += [text for attrs, text in page.scripts]
            for words in said:
                found = PRICE.search(words)
                self.assertIsNone(found, f"{path.name} says a price: {found and words[max(0, found.start() - 40):found.end() + 40]!r}")

    def test_the_page_credits_igdb_and_provides_no_game(self) -> None:
        for sentence in (
            "Les noms, les jaquettes et les illustrations des jeux appartiennent à leurs éditeurs ; ils viennent d’<a href=\"https://www.igdb.com\">IGDB</a>",
            "Games’ names, covers and artworks belong to their publishers; they come from <a href=\"https://www.igdb.com\">IGDB</a>",
            "Cartouche n’en fournit aucun : vous construisez les vôtres à partir de vos propres copies.",
            "Cartouche provides none of them: you build your own from your own copies.",
        ):
            self.assertIn(sentence, self.text)

    def test_games_are_the_catalogs(self) -> None:
        nxnative = {game["titleId"]: game for game in json.loads((CATALOG / "nxnative.json").read_text(encoding="utf-8"))["games"]}
        covers = {cover["titleId"]: cover for cover in json.loads((CATALOG / "covers.json").read_text(encoding="utf-8"))["covers"]}
        # A testers' sheet with a game playable on an iPhone says it plays there.
        playable = set()
        for path in (CATALOG / "games").glob("*.json"):
            sheet = json.loads(path.read_text(encoding="utf-8"))
            if any(r.get("status") in ("playable", "playable-with-issues") for r in sheet.get("results", [])):
                playable.add(sheet["titleId"])
        self.assertGreaterEqual(len(self.games), 6)
        self.assertEqual(len({g["id"] for g in self.games}), len(self.games))
        for game in self.games:
            title_id, name = game["titleId"], game["name"]
            with self.subTest(game=name):
                self.assertIn(title_id, nxnative, f"{name} is not in catalog/nxnative.json")
                listed = nxnative[title_id]
                for key in ("name", "platform", "genre"):
                    self.assertEqual(game[key], listed[key], f"{name}: its {key} in catalog/nxnative.json is {listed[key]!r}")
                # Where the page says it plays is where nxnative plays it.
                plays = "iphone" if listed["status"] == "iphone" or title_id in playable else listed["status"]
                self.assertIn(game["status"], STATUSES)
                self.assertEqual(game["catalog"], STATUSES[game["status"]])
                if game["catalog"] == "iphone":
                    self.assertEqual(plays, "iphone", f"{name}: the page says it plays on the iPhone, catalog/nxnative.json says {listed['status']!r}")
                else:
                    self.assertIn(plays, ("mac", "iphone"), f"{name}: the page says it plays on the Mac, catalog/nxnative.json says {listed['status']!r}")
                # Its cover and artwork are those Cartouche shows.
                self.assertIn(title_id, covers, f"{name} has no cover in catalog/covers.json")
                for key in ("cover", "artwork"):
                    self.assertRegex(game[key], r"^[a-z0-9]+$")
                    self.assertEqual(game[key], covers[title_id].get(key), f"{name}: its {key} in catalog/covers.json is {covers[title_id].get(key)!r}")
                # Its colours are those Cartouche gives it.
                self.assertEqual((game["light"], game["dark"]), app_colors(title_id), f"{name}: Cartouche's colours for it")
                # The player's games have their play time and size, or their IPA's.
                if game["status"] == "ready":
                    self.assertTrue(all(key in game for key in ("time", "sessions", "size", "detail")), name)
                if game["status"] == "stored":
                    self.assertIn("stored", game, name)

    def test_the_hints_stand_above_the_devices_shadows(self) -> None:
        # A device is positioned, and its shadow falls on the hint under it:
        # drawn over the hint's text, it made it hard to read. The hint is
        # positioned too, above the devices that #ipad-mac lifts.
        styles = re.sub(r"/\*.*?\*/", "", self.text, flags=re.S)
        rules = [(selector.strip(), body) for selector, body in re.findall(r"([^{}]+)\{([^{}]*)\}", styles)]
        hint = [body for selector, body in rules if selector == ".hint"]
        self.assertEqual(len(hint), 1)
        self.assertRegex(hint[0], r"position:\s*relative")
        level = re.search(r"z-index:\s*(\d+)", hint[0])
        self.assertIsNotNone(level, "the hint has no z-index")
        lifted = [int(z) for selector, body in rules if selector.startswith(".duo >") for z in re.findall(r"z-index:\s*(\d+)", body)]
        self.assertTrue(lifted)
        self.assertGreater(int(level.group(1)), max(lifted))

    def test_the_page_shows_only_igdbs_images_of_its_games(self) -> None:
        for tag, attrs in self.page.tags:
            self.assertNotEqual(tag, "img", "the page's images are its games', which its script shows")
        # The script builds each image's address from IGDB's server, a size
        # and the ID of a game of the list, and from nothing else.
        for src in re.findall(r'(?:src|srcset)="\' \+ (\w+)\(', self.code):
            self.assertEqual(src, "igdb")
        self.assertRegex(self.code, r'function igdb\(size, id\) \{ return IGDB \+ size \+ "/" \+ id \+ "\.jpg"; \}')
        for call in re.findall(r'igdb\("(t_\w+)", (\w+)\.(\w+)\)', self.code):
            self.assertIn(call[0], IGDB_SIZES)
            self.assertIn(call[2], ("cover", "artwork"))
        self.assertNotIn("data:image", self.text)


class DownloadPageTests(unittest.TestCase):
    """download/index.html: the newest file of each of the project's programs
    for a computer, for the links of the repository's guides. A link to it
    that names one, download/#builder, #installer-mac or #installer-windows,
    starts its download from the page's button."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.text, cls.page = read_page(DOWNLOAD_PAGE)
        cls.code = "\n".join(text for attrs, text in cls.page.scripts)

    def test_loads_nothing_from_another_site_and_sends_nothing(self) -> None:
        for tag, attrs in self.page.tags:
            for name in ("src", "srcset", "poster", "data", "action", "formaction"):
                self.assertNotRegex(attrs.get(name, ""), r"^(?:[a-z][a-z0-9+.-]*:|//)", f"<{tag} {name}> loads {attrs.get(name)!r}")
            if tag == "link" and attrs.get("rel") != "canonical":
                self.assertNotRegex(attrs.get("href", ""), r"^(?:[a-z][a-z0-9+.-]*:|//)", f"<link> loads {attrs.get('href')!r}")
            self.assertNotIn(tag, ("iframe", "embed", "object", "form", "base", "video", "audio", "img"), f"the page has an <{tag}>")
            if tag == "script":
                self.assertNotIn("src", attrs, "the page's script is its own, inline")
        for style in self.page.styles:
            self.assertNotIn("@import", style)
            self.assertNotRegex(style, r"url\(\s*['\"]?(?:[a-z][a-z0-9+.-]*:|//)")
        self.assertRegex(self.text, r'<meta name="referrer" content="no-referrer">')
        # The script names no address: the file it starts is its button's.
        self.assertNotRegex(self.code, r"https?:")
        for call in ("fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "EventSource", "document.cookie", "import(", "new Image", "Worker(", "window.open"):
            self.assertNotIn(call, self.code)
        self.assertEqual(set(re.findall(r"navigator\.(\w+)", self.text)), {"languages", "language"})
        self.assertEqual(re.findall(r"location\.href\s*=\s*([^;]+);", self.code), ["link.href"])

    def test_links_to_the_files_the_site_and_the_repository(self) -> None:
        for tag, attrs in self.page.tags:
            if tag != "a":
                continue
            href = attrs.get("href", "")
            if href.startswith("#"):
                self.assertIn(href[1:], self.page.ids, f"{href} leads nowhere on the page")
            elif href != "../":
                self.assertTrue(any(p.fullmatch(href) for p in ALLOWED_LINKS), f"the page links to {href!r}")
        for tag, attrs in self.page.tags:
            if tag == "use":
                href = attrs.get("href", "")
                self.assertTrue(href.startswith("#") and href[1:] in self.page.ids, f"<use> of {href!r}")

    def test_each_file_has_its_card_and_its_button(self) -> None:
        # The address names the card; the card's one button gives its file.
        cards = [attrs["id"] for tag, attrs in self.page.tags if tag == "li" and "file" in attrs.get("class", "").split()]
        self.assertEqual(sorted(cards), sorted(DOWNLOADS))
        for key in cards:
            card = self.text[self.text.index(f'id="{key}"'):]
            card = card[:card.index("</li>")]
            self.assertEqual(re.findall(r'\sdata-download="([^"]*)"', card), [key])
            self.assertEqual(card.count("data-started hidden"), 1, f"{key} says when its download starts")
        versions = check_downloads(self, self.text, self.page)
        self.assertEqual(sorted(versions), sorted(DOWNLOADS))

    def test_the_discord_server_in_its_footer(self) -> None:
        discord = [attrs["href"] for tag, attrs in self.page.tags if tag == "a" and "discord" in attrs.get("href", "")]
        self.assertEqual(discord, [DISCORD])

    def test_a_shared_link_shows_the_sites_own_picture(self) -> None:
        check_shared(self, self.page, SITE_URL + "download/")

    def test_the_mac_app_is_cartouche_for_mac(self) -> None:
        check_the_mac_app_is_cartouche(self, self.text)

    def test_the_same_files_as_the_site(self) -> None:
        text, page = read_page()
        self.assertEqual(check_downloads(self, self.text, self.page), check_downloads(self, text, page))

    def test_every_text_in_the_four_languages(self) -> None:
        check_languages(self, self.text, 15)

    def test_provides_no_game(self) -> None:
        for sentence in (
            "Cartouche ne contient et ne télécharge aucun jeu, aucune clé ni aucun firmware : vous construisez vos jeux à partir de vos propres copies.",
            "Cartouche contains and downloads no games, no keys and no firmware: you build your games from your own copies.",
        ):
            self.assertIn(sentence, self.text)


class NotFoundPageTests(unittest.TestCase):
    """404.html: what GitHub Pages serves for an address the site does not
    have, at any depth, so its links and icons start from the site's root.
    Back to the site, or to its downloads."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.text, cls.page = read_page(NOT_FOUND_PAGE)
        cls.code = "\n".join(text for attrs, text in cls.page.scripts)

    def test_loads_nothing_from_another_site_and_sends_nothing(self) -> None:
        for tag, attrs in self.page.tags:
            for name in ("src", "srcset", "poster", "data", "action", "formaction"):
                self.assertNotIn(name, attrs, f"<{tag} {name}>")
            if tag == "link":
                self.assertRegex(attrs.get("href", ""), r"^/[\w.-]+$", f"<link> loads {attrs.get('href')!r}")
            self.assertNotIn(tag, ("iframe", "embed", "object", "form", "base", "video", "audio", "img"), f"the page has an <{tag}>")
            if tag == "script":
                self.assertNotIn("src", attrs, "the page's script is its own, inline")
        for style in self.page.styles:
            self.assertNotIn("@import", style)
            self.assertNotIn("url(", style)
        self.assertRegex(self.text, r'<meta name="referrer" content="no-referrer">')
        self.assertRegex(self.text, r'<meta name="robots" content="noindex">')
        self.assertNotRegex(self.code, r"https?:")
        for call in ("fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "EventSource", "document.cookie", "import(", "new Image", "Worker(", "window.open", "location"):
            self.assertNotIn(call, self.code)
        self.assertEqual(set(re.findall(r"navigator\.(\w+)", self.text)), {"languages", "language"})

    def test_links_back_to_the_site_from_any_address(self) -> None:
        hrefs = [attrs.get("href", "") for tag, attrs in self.page.tags if tag == "a"]
        self.assertIn("/", hrefs)
        self.assertIn("/download/", hrefs)
        for href in hrefs:
            if href.startswith("#"):
                self.assertIn(href[1:], self.page.ids, f"{href} leads nowhere on the page")
            elif href.startswith("/"):
                self.assertIn(href, ("/", "/download/"), f"the page links to {href!r}")
            else:
                self.assertTrue(any(p.fullmatch(href) for p in ALLOWED_LINKS), f"the page links to {href!r}")
        for tag, attrs in self.page.tags:
            if tag == "use":
                href = attrs.get("href", "")
                self.assertTrue(href.startswith("#") and href[1:] in self.page.ids, f"<use> of {href!r}")
        self.assertEqual([attrs["href"] for tag, attrs in self.page.tags if tag == "a" and "discord" in attrs.get("href", "")], [DISCORD])

    def test_every_text_in_the_four_languages(self) -> None:
        check_languages(self, self.text, 5)


class Publication(unittest.TestCase):
    """What the Showcase site workflow keeps on gh-pages, which Pages serves."""

    def test_it_publishes_every_file_the_site_serves(self) -> None:
        workflow = (SITE.parent / ".github" / "workflows" / "site.yml").read_text(encoding="utf-8")
        copied = re.search(r"\n\s+cp ([^\n]*) build/site/\n", workflow)
        self.assertIsNotNone(copied, "site.yml copies the site's files to build/site/")
        self.assertEqual(sorted(copied.group(1).split()), sorted("site/" + name for name in ["index.html", "404.html", "favicon.svg", "CNAME", *PICTURES]))
        self.assertIn("cp site/download/index.html build/site/download/", workflow)
        for name in ["index.html", "404.html", "favicon.svg", "CNAME", *PICTURES]:
            self.assertTrue((SITE / name).is_file(), name)

    def test_it_serves_the_source_for_the_players_sidestore(self) -> None:
        # The address a player adds to their own SideStore, which app/
        # config.env writes into the IPA for that SideStore, is at the site's
        # domain: site.yml publishes the source there, and again each time it
        # changes on main, as the Release workflow's "Source" pull request
        # changes it (docs/decisions/155.md).
        root = SITE.parent
        settings = dict(line.split("=", 1) for line in (root / "app" / "config.env").read_text(encoding="utf-8").splitlines()
                        if "=" in line and not line.startswith("#"))
        self.assertEqual(settings["CARTOUCHE_PLAYER_SIDESTORE_SOURCE_URL"], SITE_URL + "sidestore.json")
        workflow = (root / ".github" / "workflows" / "site.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"\n\s+cp app/sidestore-player-source\.json build/site/sidestore\.json\n")
        paths = re.search(r"\n\s+paths: \[([^\]\n]*)\]\n", workflow)
        self.assertIsNotNone(paths, "site.yml runs on main for some paths")
        self.assertIn('"app/sidestore-player-source.json"', paths.group(1))
        # Cartouche alone, and its IPA for the player's SideStore from this
        # repository's releases: never a game on the domain.
        source = json.loads((root / "app" / "sidestore-player-source.json").read_text(encoding="utf-8"))
        for app in source["apps"]:
            self.assertEqual(app["bundleIdentifier"], settings["CARTOUCHE_BUNDLE_ID"])
            for version in app["versions"]:
                self.assertRegex(version["downloadURL"], r"^https://github\.com/[^/]+/Cartouche/releases/download/v[0-9.]+/Cartouche-[0-9.]+-SideStore\.ipa$")

    def test_the_worker_at_source_cartouche_cloud_gives_what_the_site_publishes(self) -> None:
        # The address a player adds to their SideStore, source.<domain>: a
        # Worker that reads the file the site publishes (source/README.md),
        # which the workflow deploys after each publication, never in the
        # Full test pass, and whose tests CI runs with the site's.
        root = SITE.parent
        worker = (root / "source" / "worker.js").read_text(encoding="utf-8")
        domain = (SITE / "CNAME").read_text(encoding="utf-8").strip()
        self.assertIn(f'export const SOURCE = "{SITE_URL}sidestore.json";', worker)
        self.assertIn(f'export const HOST = "source.{domain}";', worker)
        deploy = job_text(root / ".github" / "workflows" / "site.yml", "source")
        self.assertRegex(deploy, r"\n    needs: publish\n")
        self.assertRegex(deploy, r"\n    if: \$\{\{ !inputs\.full \}\}\n")
        self.assertRegex(deploy, r"\n    environment: cloudflare\n")
        self.assertRegex(deploy, r"\n        run: source/deploy\.sh\n")
        for workflow, job in (("site.yml", "page"), ("ci.yml", "site")):
            runs = job_text(root / ".github" / "workflows" / workflow, job)
            self.assertIn("node --test source/test/worker.test.js", runs, workflow)
            self.assertIn("python3 -m unittest discover -s source/test", runs, workflow)
        workflow = (root / ".github" / "workflows" / "site.yml").read_text(encoding="utf-8")
        self.assertIn('"source/**"', re.search(r"\n\s+paths: \[([^\]\n]*)\]\n", workflow).group(1))


class Domain(unittest.TestCase):
    """site/CNAME, the site's domain, which GitHub Pages reads on gh-pages to
    serve the site there and send its old address on to it."""

    def test_it_names_the_domain_whose_records_point_to_github_pages(self) -> None:
        text = (SITE / "CNAME").read_text(encoding="utf-8")
        self.assertRegex(text, r"^[a-z0-9-]+(?:\.[a-z0-9-]+)+\n$", "CNAME holds one name, on one line")
        name = text.strip()
        # domain/records.json gives the name GitHub Pages' addresses, and
        # www to the organization's site (domain/tests check them).
        zone = json.loads((SITE.parent / "domain" / "records.json").read_text(encoding="utf-8"))
        self.assertEqual(name, zone["zone"])
        kinds = {r["type"] for r in zone["records"] if r["name"] == name}
        self.assertTrue({"A", "AAAA"} <= kinds and "CNAME" not in kinds, kinds)
        self.assertIn({"type": "CNAME", "content": "cartouche-app.github.io"}, [{"type": r["type"], "content": r["content"]} for r in zone["records"] if r["name"] == "www." + name])

    def test_the_app_and_the_guides_link_to_the_site_at_its_domain(self) -> None:
        # The app's guide sends the Mac the site's Builder section, and the
        # guides and READMEs link to its pages: at the domain, whose address
        # does not hang on GitHub's. The old address only redirects.
        name = (SITE / "CNAME").read_text(encoding="utf-8").strip()
        root = SITE.parent
        paths = [root / "README.md", *root.glob("*/README.md"), *(root / "docs").glob("*.md"), *(root / "launcher" / "Sources").glob("*.swift")]
        for path in paths:
            self.assertFalse("https://cartouche-app.github.io/Cartouche" in path.read_text(encoding="utf-8"), f"{path.relative_to(root)} links to the site's old address")
        guide = (root / "launcher" / "Sources" / "CartoucheGuide.swift").read_text(encoding="utf-8")
        found = re.search(r'static let builderPage = URL\(string: "([^"]+)"\)', guide)
        self.assertIsNotNone(found, "CartoucheGuide.builderPage")
        self.assertEqual(found.group(1), f"https://{name}/#builder")
        self.assertIn("builder", read_page()[1].ids)

    def test_every_publication_keeps_it(self) -> None:
        # gh-pages is made again at each publication: without CNAME, GitHub
        # Pages would drop the domain, its records still pointing to GitHub.
        workflow = (SITE.parent / ".github" / "workflows" / "site.yml").read_text(encoding="utf-8")
        self.assertRegex(workflow, r"\n\s+cp [^\n]*\bsite/CNAME\b[^\n]* build/site/\n")
        self.assertNotIn("github.io/${GITHUB_REPOSITORY", workflow)


if __name__ == "__main__":
    unittest.main()
