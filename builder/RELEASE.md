Cartouche Builder 0.7.1 gives Cartouche's console on your Mac four more game sheets, made from what players measured, and reads, as the iPhone does, whether a game's build converts its BC textures.

- **Four more game sheets.** In Cartouche's console, the pages of Final Fantasy Resonance, Link's Awakening, Mario vs. Donkey Kong and Pokopia show their sheet: what the game needs of this Mac, and what players measured of it on their iPhones; the other sheets count the sessions played since. Not tried on a real Mac yet.
- **Textures converted to ASTC.** Cartouche's console on the Mac reads, as Cartouche 0.15.0 does on the iPhone, whether a game's build converts its BC textures for a GPU that reads none, as a fork of nxnative does. A Mac's GPU reads BC textures: a game's sheet, how it fits and what Game measurements sends stay as they were.
- **Cartouche Cloud stays on the iPhone.** Cartouche Cloud, which builds a game for a player with no Mac, comes into Cartouche 0.15.0 on the iPhone alone: the console has none of it, and the builder goes on building your games on this Mac.
- **From 0.7.0, 0.6.1 or 0.6.0**, which update themselves to 0.7.1: your settings, your games and their builds stay.
- **From 0.5.0 or older**, which do not find this version by themselves since Cartouche's repository moved to its own organization on GitHub: download it once, and it updates itself again after that. Your settings, your games and their builds stay.

Download `Cartouche-Builder-0.7.1.dmg`, for a Mac with Apple silicon (nxnative builds on macOS 26.6 or later), open it and drag **Cartouche Builder** onto **Applications**. The app is not notarized: the first time, open **System Settings › Privacy & Security** and click **Open Anyway**. Its updates then open without asking.

Your games are yours: the builder builds the dumps of your own Switch, and shares nothing. How it works: [builder/README.md](https://github.com/cartouche-app/Cartouche/blob/main/builder/README.md).
