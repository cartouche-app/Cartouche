# Legal

Cartouche is a launcher. It is not affiliated with, endorsed by or sponsored by Nintendo, Apple or any game publisher, nor by the LiveContainer, SideStore, iloader or nxnative projects. All trademarks belong to their owners; game names appear only to say which games Cartouche supports.

## What the project never contains or distributes

- games, game updates or downloadable content, in any form: NSP, XCI, NUP, NCA, RomFS, executables, or IPAs built from them;
- console keys (`prod.keys`, `title.keys`) or firmware;
- links to places that offer any of the above.

The app has no catalogue of downloadable games and no way to download one: it installs only the player's own copies, from their files or from storage of their own that they sign in to with their own account, never from an address, a link or a public bucket. Cartouche also downloads the IPA that Cartouche Cloud built for the account the player linked it to, from the copy the player sent there themselves, and nothing else: the service gives its address to that account alone, for a quarter of an hour, and keeps the game built two days, for that player alone ([decision 136](docs/decisions/136.md)). The project publishes only its apps, Cartouche, Cartouche Builder and the Cartouche Installer, as GitHub releases, the catalog Cartouche carries, and its site; the publish guard in [`guard/`](guard/) refuses to publish an IPA of Cartouche, or a file of the catalog, that looks like game content.

## Your games

Use only games you own, dumped from your own console with your own keys, as the law of your country allows. Your games stay yours: Cartouche installs them on your iPhone, copies them and your saves only to the storage you set up yourself, and sends none of their files anywhere else. What it measures of a game as it runs, such as its frame rate, goes with the game's title ID to the project's own server, unless you turn it off ([docs/privacy.md](docs/privacy.md)). Cartouche Builder builds them on your Mac from your own files into your own games folder, copies them only to the games folder you chose on your iPhone, on the storage you set up yourself, and downloads, uploads or shares no game, key or IPA anywhere else. Cartouche Cloud builds one for you on its Macs from the copy you send it yourself, from a computer, on its site, and gives the game built back to your account alone, there and in Cartouche once you linked it; its own terms and privacy notice are on its site.

## Issues and pull requests

Issues, pull requests and discussions that contain or link to games, keys, firmware or IPAs built from games are closed and their content is removed, as are such messages on [Cartouche's Discord server](https://discord.gg/wG3DZjdAeF).

## Licence

Cartouche is licensed under the [GNU AGPL-3.0](LICENSE). If you distribute a modified Cartouche, you must offer its full source under the same licence.
