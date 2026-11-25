// The documentation as it is published: the pages Astro wrote in dist/, and
// the pages written in src/content/docs/. Run `npm run build` first; `npm test`
// then reads both, with nothing to install but Node.
//
// The rules are the site's (site/tests/test_site.py): no link to a game, a key
// or a download of one; no price of Cartouche Cloud; no quantity of memory as
// an argument; nothing loaded from another site; and every page in each of
// Cartouche's four languages.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const content = join(root, 'src', 'content', 'docs');
const SITE = 'https://docs.cartouche.cloud';
const LOCALES = ['fr', 'es', 'de'];

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

if (!existsSync(join(dist, 'index.html'))) {
  throw new Error('dist/ is missing: run `npm run build` before `npm test`.');
}

const pages = walk(dist)
  .filter((path) => path.endsWith('.html'))
  .map((path) => ({ path, name: relative(dist, path), html: readFileSync(path, 'utf8') }));

// The links a reader follows: <a> elements, not the head's canonical and
// alternate links, which name the site's own address.
const links = (html) => [...html.matchAll(/<a\s[^>]*>/g)].flatMap((m) => attributes(m[0], 'href'));

const attributes = (html, name) =>
  [...html.matchAll(new RegExp(`\\s${name}="([^"]*)"`, 'g'))].map((m) => m[1].replaceAll('&amp;', '&'));

// The text a reader sees: the page's main column, without its markup.
const text = (html) => {
  const main = html.match(/<main[\s\S]*<\/main>/)?.[0] ?? html;
  return main
    .replace(/<script[\s\S]*?<\/script>/g, ' ')
    .replace(/<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/g, ' ')
    .replace(/\s+/g, ' ');
};

// Every link out of the documentation, whole: Cartouche's site and its
// download page, Cartouche Cloud's site, the repository and its pages, the
// Discord server, nxnative, nxnative-nobc, whose author asked for a link to it
// (decision 160), and the link that adds Cartouche's source to SideStore.
const ALLOWED_LINKS = [
  /https:\/\/cartouche\.cloud\//,
  /https:\/\/cartouche\.cloud\/download\/(?:#(?:installer-mac|installer-windows|builder|sidestore))?/,
  /https:\/\/build\.cartouche\.cloud\/(?:privacy)?/,
  /https:\/\/github\.com\/cartouche-app\/Cartouche/,
  /https:\/\/github\.com\/cartouche-app\/Cartouche\/blob\/main\/[\w/.-]+\.md/,
  /https:\/\/github\.com\/cartouche-app\/Cartouche\/issues\/new\/choose/,
  /https:\/\/discord\.gg\/wG3DZjdAeF/,
  /https:\/\/github\.com\/seedds\/nxnative/,
  /https:\/\/github\.com\/mianmuhammadse\/nxnative-nobc/,
  /sidestore:\/\/source\?url=https:\/\/source\.cartouche\.cloud/,
];

// A price, in any currency: Cartouche Cloud's stays on its own site (the
// owner, 2026-11-18).
const PRICE = /[$€£]\s?\d|\d(?:[\s  ]?[$€£]|\s?(?:usd|eur|dollars?|euros?)\b)/i;

// A quantity of memory: the documentation, like the site, never gives one as
// an argument. A disk's free room, in the Builder's settings, is not memory.
const MEMORY_AMOUNT =
  /\d+(?:[.,]\d+)?\s?(?:GB|GiB|Go|Gio|MB|Mo)\b(?:\s(?:of\s)?(?:RAM|memory|unified))|(?:RAM|memory|mémoire|memoria|Arbeitsspeicher|Speicher)\s(?:of\s|de\s|von\s)?\d+(?:[.,]\d+)?\s?(?:GB|GiB|Go|Gio)\b/i;

// Files of games, keys, firmware and what carries them.
const GAME_FILES = /\.(ipa|nsp|nsz|xci|xcz|nca|ncz|nro|nso|nup|kip|keys|bin|zip|7z|rar|tar|gz|torrent|pkg)(?:$|[?#])/i;

test('every page is written in each language', () => {
  const english = walk(content)
    .map((path) => relative(content, path))
    .filter((name) => !LOCALES.some((locale) => name.startsWith(`${locale}/`)));
  assert.ok(english.length >= 25, `only ${english.length} pages in English`);
  for (const locale of LOCALES) {
    const missing = english.filter((name) => !existsSync(join(content, locale, name)));
    assert.deepEqual(missing, [], `${locale} lacks pages`);
  }
});

test('every page of each language is built', () => {
  for (const page of pages.filter((p) => p.name !== '404.html' && !LOCALES.some((l) => p.name.startsWith(`${l}/`)))) {
    for (const locale of LOCALES) {
      assert.ok(existsSync(join(dist, locale, page.name)), `${locale}/${page.name} is missing`);
    }
  }
});

test('every link inside the documentation leads to a page, and to its heading', () => {
  const ids = new Map();
  const idsOf = (file) => {
    if (!ids.has(file)) ids.set(file, new Set(attributes(readFileSync(file, 'utf8'), 'id')));
    return ids.get(file);
  };
  for (const page of pages) {
    for (const href of links(page.html)) {
      let url = href;
      if (url.startsWith(SITE)) url = url.slice(SITE.length) || '/';
      if (!url.startsWith('/') || url.startsWith('//')) continue;
      const [path, hash] = url.split('#');
      const clean = decodeURIComponent(path.split('?')[0]);
      const file = clean.endsWith('/') ? join(dist, clean, 'index.html') : join(dist, clean);
      assert.ok(existsSync(file), `${page.name} links to ${href}, which is not built`);
      if (hash && file.endsWith('.html')) {
        assert.ok(idsOf(file).has(decodeURIComponent(hash)), `${page.name} links to ${href}, whose heading is not there`);
      }
    }
  }
});

test('links out of the documentation are only the allowed ones', () => {
  for (const page of pages) {
    for (const href of links(page.html)) {
      if (href.startsWith('/') || href.startsWith('#') || href.startsWith(SITE) || !/^[a-z][\w+.-]*:/i.test(href)) continue;
      assert.ok(ALLOWED_LINKS.some((allowed) => new RegExp(`^${allowed.source}$`).test(href)), `${page.name} links to ${href}`);
    }
  }
});

test('nothing is loaded from another site', () => {
  for (const page of pages) {
    const loads = [
      ...attributes(page.html, 'src'),
      ...attributes(page.html, 'srcset').flatMap((set) => set.split(',').map((s) => s.trim().split(' ')[0])),
      ...[...page.html.matchAll(/<link\s[^>]*rel="(?:stylesheet|icon|shortcut icon|preload|modulepreload|manifest)"[^>]*>/g)]
        .flatMap((m) => attributes(m[0], 'href')),
    ];
    for (const url of loads) {
      assert.ok(!/^(?:https?:)?\/\//.test(url) || url.startsWith(SITE), `${page.name} loads ${url}`);
    }
  }
  for (const file of walk(dist).filter((path) => path.endsWith('.css') || path.endsWith('.js'))) {
    const code = readFileSync(file, 'utf8');
    assert.doesNotMatch(code, /url\(\s*["']?(?:https?:)?\/\//, `${relative(dist, file)} loads from another site`);
    assert.doesNotMatch(code, /@import\s+(?:url\()?["']?https?:/, `${relative(dist, file)} imports from another site`);
  }
});

test('no link to a game, a key or a file that carries one', () => {
  for (const page of pages) {
    for (const href of links(page.html)) {
      assert.doesNotMatch(href, GAME_FILES, `${page.name} links to ${href}`);
    }
  }
});

test('no price and no quantity of memory', () => {
  for (const page of pages) {
    const words = text(page.html);
    const price = words.match(PRICE);
    assert.equal(price, null, `${page.name} names a price: ${price?.[0]}`);
    const memory = words.match(MEMORY_AMOUNT);
    assert.equal(memory, null, `${page.name} names an amount of memory: ${memory?.[0]}`);
  }
});

test('every page has a title and a description in its own language', () => {
  for (const page of pages.filter((p) => !p.name.includes('404'))) {
    assert.match(page.html, /<title>[^<]+<\/title>/, `${page.name} has no title`);
    assert.match(page.html, /<meta name="description" content="[^"]+"/, `${page.name} has no description`);
    const locale = LOCALES.find((l) => page.name.startsWith(`${l}/`)) ?? 'en';
    assert.match(page.html, new RegExp(`<html lang="${locale}"`), `${page.name} is not marked ${locale}`);
  }
});

test('every image of a screen is the app, never a game', () => {
  // Screens come from the CI's galleries (launcher-screens/, builder-screens/)
  // and show Cartouche, its Builder and its Installer, never a game running:
  // their names say which app, and nothing else is allowed in.
  const screens = readdirSync(join(root, 'src', 'assets', 'screens'));
  for (const name of screens) {
    assert.match(name, /^(?:iphone|ipad|mac|installer)-[a-z0-9-]+\.webp$/, `${name} is not named after its app`);
    assert.doesNotMatch(name, /ingame|in-game|gameplay|playing-/, `${name} looks like a game running`);
  }
});
