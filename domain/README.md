# cartouche.cloud

Cartouche's domain. The owner registered it at OVH on 2026-11-16 and handed it to the project on 2026-11-17; its zone is at Cloudflare, in the owner's account, whose name servers OVH gives for it. [`records.json`](records.json) holds the records the project keeps in the zone, each with why it is there, and the [Domain](../.github/workflows/domain.yml) workflow keeps the zone as the file says, from main ([decision 128](../docs/decisions/128.md)).

| Name | Records | What for |
| --- | --- | --- |
| `cartouche.cloud` | A and AAAA, GitHub Pages' four addresses of each | The showcase site, [`site/`](../site/), on GitHub Pages |
| `www.cartouche.cloud` | CNAME `cartouche-app.github.io` | `www`, which GitHub Pages sends on to `cartouche.cloud` |
| `_github-pages-challenge-cartouche-app.cartouche.cloud` | TXT | GitHub's verification of the domain for the organization `cartouche-app` |
| `cartouche.cloud` | TXT `v=spf1 -all` | No server sends mail as `cartouche.cloud`, so a mail server refuses one that claims to |
| `_dmarc.cartouche.cloud` | TXT `v=DMARC1; p=reject; …` | The same, said to mail servers that read DMARC |

## The site

GitHub Pages serves the site, as it did at `cartouche-app.github.io/Cartouche`, and the records point the domain to it as [GitHub's guide](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site) says: its four A and four AAAA addresses at the apex, `www` to the organization's default domain, without the repository's name. Every record is *DNS only*, the grey cloud of Cloudflare's dashboard: Cloudflare answers with GitHub's addresses and stands in front of nothing, so that GitHub Pages sees its own addresses, gets the site's certificate from Let's Encrypt and serves the site over HTTPS. Behind Cloudflare's proxy, it would get none. Nothing else stands at the apex either, since another A, AAAA or CNAME record there would stop the certificate too, and the zone has no wildcard, which GitHub warns would let anyone's site on GitHub Pages take a name of the zone. The tests check all three.

The site's half is [`site/CNAME`](../site/CNAME), the domain, which the Showcase site workflow publishes beside the page each time: GitHub Pages reads it to serve the site there and to send its old address, `cartouche-app.github.io/Cartouche`, on to it, page by page ([site/README.md](../site/README.md#publishing)). It came once these records answered: published before them, it would have sent the old address to a name that answered nothing, and resolvers would have kept that empty answer for the zone's half hour.

GitHub can also verify the domain for the organization: then no repository but the organization's can serve a site on `cartouche.cloud` or a name right under it, even if Cartouche's site ever stopped while the records still point to GitHub Pages. The organization's owner added the domain in the organization's **Settings › Pages › Add a domain**, which showed a TXT record, `_github-pages-challenge-cartouche-app.cartouche.cloud`, now in the file (2026-11-17); once it answers, the owner clicks **Verify** there. It must then stay, or the verification lapses.

## Changing a record

A change is a pull request on `records.json`: the CI's **Domain** job checks the file and the script ([`tests/`](tests/)), and once the change is on main, the Domain workflow applies it. In one batch, which Cloudflare runs in a single transaction, it adds the file's records that the zone lacks, gives its own records the comment, TTL and proxy status the file says, and deletes those of its own that the file no longer has. Its own are the records whose comment starts with `domain/records.json: `, followed by the file's `why`. A record of the zone without that mark, made in the dashboard, by Email Routing or for a Worker's custom domain, stays as it is, and the run's summary lists it; a record of the file that is the same as one of them, by type, name and content, takes it over. The summary then says what public resolvers answer, and the run fails if one of them still misses a record of the file after a quarter of an hour.

Run it from the Actions tab with **plan** to see what it would change, without changing anything. Do not change the project's records in the dashboard: the next run puts the file's back.

```
python3 -m unittest discover -s domain/tests -v
CLOUDFLARE_DOMAIN_TOKEN=... python3 domain/sync.py domain/records.json --plan
python3 domain/sync.py domain/records.json --resolve
```

## The token

The workflow takes `CLOUDFLARE_DOMAIN_TOKEN`, a secret of the repository's environment `cloudflare`: an account token of Cloudflare's, *Cartouche domain*, with **Zone › DNS › Edit** and **Zone › Zone › Read** on the zone `cartouche.cloud` alone, which the owner made in Cloudflare's dashboard from [this template](https://dash.cloudflare.com/?to=/:account/api-tokens&permissionGroupKeys=%5B%7B%22key%22%3A%22dns%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22zone%22%2C%22type%22%3A%22read%22%7D%5D&name=Cartouche%20domain), with **Zone Resources › Specific zone › cartouche.cloud**. It reaches nothing but this zone's records: not the telemetry's Workers and database, which take their own token ([telemetry/README.md](../telemetry/README.md)), nor anything else of the account. Without it, the workflow changes nothing and says so. It is never written anywhere else, and the owner revokes it in **Manage account › Account API tokens**.

## What stays with the owner

The registration, at OVH: the domain is registered until 2027-11-16, and its name servers there are Cloudflare's two for the zone. The zone has no DNSSEC yet: Cloudflare would sign it, and its DS record would go to OVH.
