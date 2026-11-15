Cartouche Builder 0.6.1 no longer waits forever after a build's step has ended, and always finds its updates.

- **A build that never ended.** A build no longer waits forever after one of its steps has ended: the builder now starts each program it runs, nxnative's, Xcode's and Homebrew's, and waits for its end in a way that cannot miss it.
- **Updates, always found.** Updates are found however many of Cartouche's releases come before the builder's: the app reads GitHub's answers one after the other until it finds its own.
- **From 0.6.0**, which updates itself to 0.6.1: your settings, your games and their builds stay.
- **From 0.5.0 or older**, which do not find this version by themselves since Cartouche's repository moved to its own organization on GitHub: download it once, and it updates itself again after that. Your settings, your games and their builds stay, and you also get 0.6.0's changes: Cartouche's console on the Mac, your games built and played on this Mac with your iPhone's saves, and their builds followed and started from your iPhone.

Download `Cartouche-Builder-0.6.1.dmg`, for a Mac with Apple silicon (nxnative builds on macOS 26.6 or later), open it and drag **Cartouche Builder** onto **Applications**. The app is not notarized: the first time, open **System Settings › Privacy & Security** and click **Open Anyway**. Its updates then open without asking.

Your games are yours: the builder builds the dumps of your own Switch, and shares nothing. How it works: [builder/README.md](https://github.com/cartouche-app/Cartouche/blob/main/builder/README.md).
