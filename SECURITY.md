# Security

Cartouche signs in to an Apple account (through its built-in SideStore), signs code on the device, reaches the player's own storage with their passwords, and updates itself from its GitHub releases; on the Mac, Cartouche Builder builds and serves the player's games and updates itself the same way. A flaw in any of these can hurt its users, so please report it privately.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: the **Security** tab of this repository, then **Report a vulnerability**. Do not open a public issue for a vulnerability.

Include what an attacker can do, the steps to reproduce it and the version or commit you tested.

## Scope

- how Cartouche and its SideStore store and use Apple account credentials and certificates;
- how Cartouche, Cartouche Builder and its console store and use the passwords and keys of the player's storage, and the bridge between Cartouche and Cartouche Builder: its pairing by six digits, its encryption, and what it carries, the games, the saves and the storage connections with their passwords ([decision 125](docs/decisions/125.md));
- the publish guard in `guard/` letting game content through;
- the releases and the source the built-in SideStore installs them from (`app/sidestore-source.json`), the releases of Cartouche Builder, which it updates itself from, and of the Cartouche Installer, and the workflows that make them;
- the telemetry server and the project's dashboard in `telemetry/`, and the problem reports the server files;
- the DNS records of cartouche.cloud in `domain/`, and the site they serve;
- the covers Cartouche reads every day from the branch `live-covers`, and the workflow that writes them.

Vulnerabilities in LiveContainer or SideStore themselves are best reported to those projects too.

## How this repository is protected

- main takes changes only through pull requests, squashed, once CI has passed ([`.github/rulesets`](.github/rulesets)). Nobody pushes to it, the release workflow included: a release proposes its source entry in a pull request of its own ([app/releases/README.md](app/releases/README.md)).
- Cartouche's release tags (`v*`) can't be moved or deleted, and a version the source lists never gets another IPA.
- Workflows get a read-only token. Only the jobs that publish a release, of Cartouche, Cartouche Builder or the Installer, the jobs that push the branches workflows keep (`release/v<version>`, the covers, the screenshots and captures, the game sheets' measurements, nxnative's weekly page, the telemetry export, the site's `gh-pages`) and the Branches workflow, which deletes the branches no longer in use, can write. None of them holds a secret or runs anything installed from a package index; the jobs that hold one, the deploys to Cloudflare, the readers of the telemetry database, the Domain workflow and the covers' search on IGDB, can write nothing to the repository.
- Workflows pin each action to a commit, which Dependabot updates, and keep no credentials in their checkouts. The Workflow audit, [zizmor](https://docs.zizmor.sh), fails a pull request that breaks one of these rules.
- The repository never holds games, keys, firmware, pairing files, certificates or provisioning profiles ([LEGAL.md](LEGAL.md), [.gitignore](.gitignore)).
