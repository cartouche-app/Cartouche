# The documentation at docs.cartouche.cloud

<https://docs.cartouche.cloud/> is the documentation for players ([decision 161](../docs/decisions/161.md)): how to install Cartouche and play, every screen of Cartouche on the iPhone and the iPad, Cartouche for Mac (its console and the Builder), the Cartouche Installer and Cartouche Cloud, in English, French, Spanish and German. The [showcase site](../site/README.md) stays short and sends readers here for the details.

## What it is made of

- [Astro](https://astro.build/) and [Starlight](https://starlight.astro.build/), its theme for documentation, at the versions [`package-lock.json`](package-lock.json) pins: Markdown pages in, static HTML out, with no server code.
- Pages in [`src/content/docs/`](src/content/docs/): English at the root, French, Spanish and German under `fr/`, `es/` and `de/`, each page at the same path in each language. A page left untranslated would show in English with a notice; the tests ask for all of them. The sidebar and its words in each language are in [`astro.config.mjs`](astro.config.mjs); the words of Starlight's own interface it does not translate, as the search's in French and German, in [`src/content/i18n/`](src/content/i18n/).
- The screens in [`src/assets/screens/`](src/assets/screens/), named after their app (`iphone-`, `ipad-`, `mac-`, `installer-`), with a copy per language prefixed `fr-`, `es-` or `de-` for those of the iPhone, the iPad and the Mac. They come from the CI's galleries, never from a real device: Cartouche's from the Launcher screens workflow (`launcher-screens/<branch>`), the Mac's from the Builder workflow (`builder-screens/main`; the console in dark mode, the Builder in light mode, as the gallery takes them in each language; the console's Storage page cut to its own column, down to its last line), the Installer's from its window's tests, in English only. None shows a game running, a price of Cartouche Cloud or an amount of memory: a screen that shows one is cut or left out. They are kept as WebP, the iPad's at half their size.
- [`src/styles/cartouche.css`](src/styles/cartouche.css): Cartouche's colours, the site's, over Starlight's, and the frames of the screens.
- The search is [Pagefind](https://pagefind.app/), which Starlight builds into the site: it runs in the reader's browser, from the site's own files.

The documentation never names a price, never gives an amount of memory as an argument, links to no game, key or firmware, and loads nothing from another site: [`public/_headers`](public/_headers) sends a Content Security Policy that keeps it so, and the tests check each.

## How it is served

The [Documentation](../.github/workflows/docs.yml) workflow builds it when `docs-site/` changes on main, runs its tests, then deploys it with [`deploy.sh`](deploy.sh): [wrangler](https://developers.cloudflare.com/workers/wrangler/) uploads `dist/` as the static assets of the Worker `cartouche-docs` ([`wrangler.jsonc`](wrangler.jsonc)), which has no code of its own, keeps no logs, has no `workers.dev` or preview address, and answers at its domain alone. It is in the account of the zone `cartouche.cloud`, like the [source's Worker](../source/README.md), with the same token, `CLOUDFLARE_DOMAIN_TOKEN` of the environment `cloudflare` ([domain/README.md](../domain/README.md#the-token)), which has **Account › Workers Scripts › Edit** and **Zone › Workers Routes › Edit** since 2026-11-24: nothing new to create at Cloudflare. Cloudflare makes the name's DNS record and certificate itself, outside [`domain/records.json`](../domain/records.json). An address it does not have gets the documentation's 404 page.

For search engines, Starlight writes the sitemap, `sitemap-index.xml`, with each page's three other languages, and names each page's address and its languages in its head; [`public/robots.txt`](public/robots.txt) lets them read every page and names the sitemap, and a link to a page shows the site's own picture, `https://cartouche.cloud/social.png` (`og:image`, in [`astro.config.mjs`](astro.config.mjs)), which the page never loads ([decision 175](../docs/decisions/175.md)). The first page's description names what players search for, in each language.

The CI builds and checks it on every pull request (job *Documentation* of [ci.yml](../.github/workflows/ci.yml)), and so does the Full test pass.

## Working on it

```
cd docs-site
npm ci --ignore-scripts
npm run dev        # http://localhost:4321/, as it is written
npm run build      # dist/, as it is published
npm test           # after a build
```

`npm run preview`, or `npx wrangler dev`, serves `dist/` as Cloudflare does, headers included. Set `ASTRO_TELEMETRY_DISABLED=1` to keep Astro from sending its usage measures.

When Cartouche changes, its page here changes in the same pull request, in each language, with the app's own words for its buttons (`launcher/Sources/Cartouche.xcstrings`, the Builder's `tr(...)`, `installer/src/locales/`).
