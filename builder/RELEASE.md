Cartouche for Mac 0.8.1 measures your storage to its end: the builder's Storage page no longer shows "exit 15", nor stays on "Measuring…".

- **Storage.** The builder's Storage page measured its folders only while it stayed on screen: when the page went away or was drawn again, the measurement stopped, showed "exit 15" and left the page on "Measuring…", as it has since 0.5.0. The measurement now goes on to its end, even on a NAS where it takes a while, and its result shows when you come back to the page; a stopped measurement is no longer an error. Not tried on a real Mac yet.
- **Games of your NAS through the cable.** With an iPhone plugged into this Mac, and this Mac on its Ethernet, Cartouche can now pass a game of your NAS, FTP or SFTP server on to the iPhone through the cable. The next Cartouche for iPhone asks for it; Cartouche 0.16.1 does not yet. Not tried on a real Mac yet.
- **Measurements.** Each session of the console also sends the shader chain the game was built with, its first 12 digits, beside nxnative's commit, so that nxnative sees which chain each measurement ran. Never a path or a name.
- **From 0.8.0, 0.7.1, 0.7.0 or 0.6.x**, which update themselves to 0.8.1: your settings, your games and their builds stay; from 0.7.1 or older, the app takes its new name, Cartouche, at its first start.
- **From 0.5.0 or older**, which do not find this version by themselves since Cartouche's repository moved to its own organization on GitHub: download it once, and it updates itself again after that. Your settings, your games and their builds stay.

Download `Cartouche-Builder-0.8.1.dmg`, for a Mac with Apple silicon (nxnative builds on macOS 26.6 or later), open it and drag **Cartouche** onto **Applications**. The app is not notarized: the first time, open **System Settings › Privacy & Security** and click **Open Anyway**. Its updates then open without asking.

Your games are yours: the builder builds the dumps of your own Switch, and shares nothing. How it works: [builder/README.md](https://github.com/cartouche-app/Cartouche/blob/main/builder/README.md).
