# The source at source.cartouche.cloud

<https://source.cartouche.cloud/> is the address a player adds to their own SideStore to install Cartouche without a computer ([decision 147](../docs/decisions/147.md), [decision 155](../docs/decisions/155.md)). It answers with Cartouche's source for the player's SideStore, [`app/sidestore-player-source.json`](../app/sidestore-player-source.json), and nothing else: the source lists Cartouche alone, its IPA for the player's SideStore from this repository's releases, never a game.

## How it is served

- The [Showcase site](../.github/workflows/site.yml) workflow publishes that file on GitHub Pages as <https://cartouche.cloud/sidestore.json>, beside the site, and again each time it changes on main, as merging the Release workflow's *Source* pull request changes it ([site/README.md](../site/README.md#publishing)). That address is the one `app/config.env` writes into the IPA for the player's SideStore, where Cartouche's built-in SideStore reads its updates: it hangs on GitHub Pages alone.
- A name under the domain cannot be the site's: GitHub Pages serves one domain for a repository. So [`worker.js`](worker.js), the Cloudflare Worker `cartouche-source`, answers at `source.cartouche.cloud` with the file as Pages has it, at `/` and at `/sidestore.json`, as JSON, kept five minutes in Cloudflare's cache: a new version reaches SideStore within minutes of the site's publication, and the Worker needs no deploy for it. Any other address is a 404, any method but GET and HEAD a 405, and when Pages does not give a source (an error, a page of GitHub's, half a file), SideStore gets a 502, never that page.
- The Showcase site workflow deploys the Worker after each publication, with [`deploy.sh`](deploy.sh), which calls Cloudflare's API with curl and jq, in the account that has the zone `cartouche.cloud`: a Worker's domain is in the account of its zone. It reads the zone and its account, uploads the Worker, with no binding and no logs kept and no `workers.dev` address, attaches `source.cartouche.cloud` to it when it is not yet, and reads what `https://source.cartouche.cloud/` answers, which it says in the job's summary. Cloudflare makes the name's DNS record and its certificate itself, as for `build.cartouche.cloud`: the record is Cloudflare's, outside [`domain/records.json`](../domain/records.json), which the Domain workflow leaves alone ([domain/README.md](../domain/README.md)).

## The token

The deploy takes `CLOUDFLARE_DOMAIN_TOKEN`, the Domain workflow's account token *Cartouche domain*, in the domain's account ([domain/README.md](../domain/README.md#the-token)), with **Account › Workers Scripts › Edit** and **Zone › Workers Routes › Edit** besides its own. While it has not these two, each deploy warns with what to add, in **Manage account › Account API Tokens › Cartouche domain › Edit**, and does not fail.

The first deploy (2026-11-24) took the telemetry's token, whose account is the owner's own, without the domain: the Worker went there, where no domain of `cartouche.cloud` can reach it. With the telemetry's `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, each deploy removes that copy when it is still there.

## Working on it

```
node --test source/test/worker.test.js
python3 -m unittest discover -s source/test -v
CLOUDFLARE_DOMAIN_TOKEN=... source/deploy.sh
```

CI runs both tests on every pull request (Showcase site), and the Full test pass with the site's.
