# cartouche.cloud

Cartouche's domain. The owner registered it at OVH on 2026-11-16 and handed it to the project on 2026-11-17; its zone is at Cloudflare, in the owner's account, whose name servers OVH gives for it. [`records.json`](records.json) holds the records the project keeps in the zone, each with why it is there, and the [Domain](../.github/workflows/domain.yml) workflow keeps the zone as the file says, from main ([decision 128](../docs/decisions/128.md)). The records of the mail that `contact@cartouche.cloud` receives are Email Routing's, Cloudflare's own ([below](#mail)).

| Name | Records | What for |
| --- | --- | --- |
| `cartouche.cloud` | A and AAAA, GitHub Pages' four addresses of each | The showcase site, [`site/`](../site/), on GitHub Pages |
| `www.cartouche.cloud` | CNAME `cartouche-app.github.io` | `www`, which GitHub Pages sends on to `cartouche.cloud` |
| `_github-pages-challenge-cartouche-app.cartouche.cloud` | TXT | GitHub's verification of the domain for the organization `cartouche-app` |
| `_dmarc.cartouche.cloud` | TXT `v=DMARC1; p=reject; …` | No server sends mail as `cartouche.cloud`: mail servers refuse mail that claims to come from it, unless SPF or DKIM vouches for it |

## The site

GitHub Pages serves the site, as it did at `cartouche-app.github.io/Cartouche`, and the records point the domain to it as [GitHub's guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site) says: its four A and four AAAA addresses at the apex, `www` to the organization's default domain, without the repository's name. Every record is *DNS only*, the grey cloud of Cloudflare's dashboard: Cloudflare answers with GitHub's addresses and stands in front of nothing, so that GitHub Pages sees its own addresses, gets the site's certificate from Let's Encrypt and serves the site over HTTPS. Behind Cloudflare's proxy, it would get none. Nothing else stands at the apex either, since another A, AAAA or CNAME record there would stop the certificate too, and the zone has no wildcard, which GitHub warns would let anyone's site on GitHub Pages take a name of the zone. The tests check all three.

The site's half is [`site/CNAME`](../site/CNAME), the domain, which the Showcase site workflow publishes beside the page each time: GitHub Pages reads it to serve the site there and to send its old address, `cartouche-app.github.io/Cartouche`, on to it, page by page ([site/README.md](../site/README.md#publishing)). It came once these records answered: published before them, it would have sent the old address to a name that answered nothing, and resolvers would have kept that empty answer for the zone's half hour.

GitHub can also verify the domain for the organization: then no repository but the organization's can serve a site on `cartouche.cloud` or a name right under it, even if Cartouche's site ever stopped while the records still point to GitHub Pages. The organization's owner added the domain in the organization's **Settings › Pages › Add a domain**, which showed a TXT record, `_github-pages-challenge-cartouche-app.cartouche.cloud`, now in the file (2026-11-17); once it answers, the owner clicks **Verify** there. It must then stay, or the verification lapses.

## Names Cloudflare keeps

A Worker's custom domain has a DNS record Cloudflare makes and keeps itself, outside the file, which the Domain workflow leaves alone: `source.cartouche.cloud`, the source for the player's SideStore, which the Showcase site workflow attaches to the Worker `cartouche-source` with this token ([source/README.md](../source/README.md)), `docs.cartouche.cloud`, the documentation for players, which the Documentation workflow attaches to the Worker `cartouche-docs` with the same token ([docs-site/README.md](../docs-site/README.md)), and `build.cartouche.cloud`, Cartouche Cloud's.

## Mail

`contact@cartouche.cloud` is forwarded to the owner's mailbox by Cloudflare's [Email Routing](https://developers.cloudflare.com/email-service/configuration/domains/), which the owner set up in the dashboard, under **Compute › Email Service › Email Routing** (2026-11-17, [decision 130](../docs/decisions/130.md)). Its records are its own, locked there, and not in the file: three MX records at the apex, `route1`, `route2` and `route3.mx.cloudflare.net`, with priorities Cloudflare picks; an SPF record at the apex, `v=spf1 include:_spf.mx.cloudflare.net ~all`, so that mail servers take the mail it forwards; and its DKIM key, `cf2024-1._domainkey.cartouche.cloud`. The Domain workflow leaves them as they are and lists them in its summary.

So the file has no SPF record: a name has one, or mail servers take none of them, and the script stops before changing anything if one of the file's would stand beside another. It keeps the DMARC record, since no server sends mail as the domain: mail that claims to come from `cartouche.cloud` is refused, unless SPF or DKIM vouches for it. The addresses and where they forward stay in the owner's Cloudflare account.

## Changing a record

A change is a pull request on `records.json`: the CI's **Domain** job checks the file and the script ([`tests/`](tests/)), and once the change is on main, the Domain workflow applies it. In one batch, which Cloudflare runs in a single transaction, it adds the file's records that the zone lacks, gives its own records the comment, TTL and proxy status the file says, and deletes those of its own that the file no longer has. Its own are the records whose comment starts with `domain/records.json: `, followed by the file's `why`. A record of the zone without that mark, made in the dashboard, by Email Routing or for a Worker's custom domain, stays as it is, and the run's summary lists it; a record of the file that is the same as one of them, by type, name and content, takes it over. Where a record of the file could not stand beside one of them, a CNAME beside any record of its name or an SPF record beside another, the run stops before changing anything. The summary then says what public resolvers answer, and the run fails if one of them still misses a record of the file after a quarter of an hour.

Run it from the Actions tab with **plan** to see what it would change, without changing anything. Do not change the project's records in the dashboard: the next run puts the file's back.

```
python3 -m unittest discover -s domain/tests -v
CLOUDFLARE_DOMAIN_TOKEN=... python3 domain/sync.py domain/records.json --plan
python3 domain/sync.py domain/records.json --resolve
```

## The token

The workflow takes `CLOUDFLARE_DOMAIN_TOKEN`, a secret of the repository's environment `cloudflare`: an account token of Cloudflare's, *Cartouche domain*, with **Zone › DNS › Edit** and **Zone › Zone › Read** on the zone `cartouche.cloud` alone, which the owner made in Cloudflare's dashboard from [this template](https://dash.cloudflare.com/?to=/:account/api-tokens&permissionGroupKeys=%5B%7B%22key%22%3A%22dns%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22zone%22%2C%22type%22%3A%22read%22%7D%5D&name=Cartouche%20domain), with **Zone Resources › Specific zone › cartouche.cloud**. Since 2026-11-24 it also has **Account › Workers Scripts › Edit** and **Zone › Workers Routes › Edit**, with which the Showcase site workflow deploys the Worker `cartouche-source` in this account and gives it the name `source.cartouche.cloud` ([source/README.md](../source/README.md)), and the Documentation workflow the Worker `cartouche-docs` at `docs.cartouche.cloud` ([docs-site/README.md](../docs-site/README.md)): the owner added them in **Manage account › Account API Tokens › Cartouche domain › Edit**, which keeps the token's value. It reaches nothing but this zone's records: not the telemetry's Workers and database, which take their own token ([telemetry/README.md](../telemetry/README.md)), nor anything else of the account. Without it, the workflow changes nothing and says so. It is never written anywhere else, and the owner revokes it in **Manage account › Account API tokens**.

## What stays with the owner

The registration, at OVH: the domain is registered until 2027-11-16, and its name servers there are Cloudflare's two for the zone. DNSSEC, since 2026-11-17: Cloudflare signs the zone, and the owner gave OVH its DS record, which OVH passes on to the `.cloud` registry. Email Routing, in the owner's Cloudflare account ([Mail](#mail)).
