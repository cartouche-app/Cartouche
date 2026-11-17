# Contributing

Thanks for helping. Cartouche is written in English: code, comments, docs and commit messages. Questions, help and ideas, in English, French, Spanish or German, are on [Cartouche's Discord server](https://discord.gg/wG3DZjdAeF); bugs and compatibility reports go in [the issue forms](https://github.com/cartouche-app/Cartouche/issues/new/choose).

## Ground rules

- Never attach, commit or link games, keys, firmware or IPAs built from games, in code, issues, logs or screenshots. See [LEGAL.md](LEGAL.md).
- Logs and reports must not contain personal data: Apple account names, device identifiers that are not needed, file paths with your name.
- Changes to LiveContainer or SideStore go in `app/patches/` as patch files, never as edits to the submodules. A fix that helps those projects too should also be offered to them.
- Cartouche's console on the Mac is made of the launcher's own files ([decision 95](docs/decisions/095.md)): a change to the launcher that makes sense on a Mac goes in a file the Mac shares, with what only an iPhone has under `#if os(iOS)`, never in a copy for the Mac. A new file of `launcher/Sources` is linked in `builder/mac/Sources/CartoucheConsole/Shared` or named in [`builder/mac/console/unshared.json`](builder/mac/console/unshared.json) with its reason, which the CI's Cartouche Builder tests check ([builder/README.md](builder/README.md#development)).

## Pull requests

- Every change to main goes through a pull request, squashed when it is merged: main takes no push ([.github/rulesets](.github/rulesets/README.md)).
- One change per pull request, with a description of what it does and how it was tested.
- Once a pull request is merged or closed, its branch is deleted, with the screenshots kept for it, by the [Branches workflow](.github/branches/README.md); **Restore branch** on the pull request brings it back. New work goes on a branch started again from main. A branch no pull request has stays until its author deletes it.
- A fix comes with a test that fails without it, where the bug was: a unit test of the launcher, a test of its harness in the iOS Simulator ([launcher/Harness](launcher/Harness/README.md)), a storage test against real servers, a UI test of the gallery, a test of Cartouche Builder or of the Installer, or a Python test. The pull request says which.
- A change players can see, in Cartouche, Cartouche Builder, the Installer or the site, shows them before and after: the Launcher screens workflow takes a screenshot of every screen of the app for a pull request that changes one, and the Builder workflow of every page of Cartouche Builder and of its console.
- A choice that shapes the project is a decision, with its reasons: a file of its own in [`docs/decisions/`](docs/decisions/README.md), named by its next free number on three digits.
- A pull request never raises a version, of Cartouche (`CARTOUCHE_VERSION` in `app/config.env`), Cartouche Builder (`builder/pyproject.toml`) or the Installer (`installer/src-tauri/tauri.conf.json`), nor writes release notes: the pull request of a version does, with what was merged since the last one ([app/releases/README.md](app/releases/README.md)).
- CI must pass. main requires the publish guard's tests and the catalog checks, the app's sources, the shell checks, the workflow audit and, when the app's files change, the app build ([.github/rulesets](.github/rulesets/README.md)). The other workflows run when their part changes, and must pass too: the storage tests against real servers when the storage code changes ([launcher/StorageTests](launcher/StorageTests/README.md)), the launcher's harness and screens when its sources do, and the tests of Cartouche Builder, the Installer, the telemetry server, the site and the domain.
- Before any release, of Cartouche, Cartouche Builder or the Installer, the [Full test pass](.github/full-pass/README.md) runs every test of the repository on its commit, whatever it changes, and nothing is published until it has passed.
- A compatibility sheet in `catalog/games/` needs a result measured on a real device; see the compatibility report issue form.

## Development

- App: `app/scripts/build.sh` on a Mac, see [app/README.md](app/README.md); its screens, [launcher/README.md](launcher/README.md).
- Cartouche Builder: see [builder/README.md](builder/README.md#development).
- Installer: see [installer/README.md](installer/README.md).
- Publish guard: see [guard/README.md](guard/README.md).
- Telemetry server and dashboard: see [telemetry/README.md](telemetry/README.md).
- The site: see [site/README.md](site/README.md); the domain's DNS records: [domain/README.md](domain/README.md).

## Licence of contributions

By contributing, you agree that your contribution is licensed under the [GNU AGPL-3.0](LICENSE), like the rest of the project.
