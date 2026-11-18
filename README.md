# nxnative's games on players' iPhones and Macs

What the players of [Cartouche](https://github.com/cartouche-app/Cartouche) measured of nxnative's games from 2026-11-10 to 2026-11-17, on their iPhones and on their Macs, summed up for nxnative's developers each Thursday. How, and what is left out: [telemetry/README.md](https://github.com/cartouche-app/Cartouche/blob/main/telemetry/README.md#nxnatives-page).

1390 game sessions on iPhones and iPads from 107 installs, 279.1 hours of play. 364 of the 1110 sessions that count name their nxnative commit. Every line, and every figure, sums up at least 3 installs, or 3 Macs: a smaller group is left out, and a figure fewer of them gave shows –. The games played on players' Macs, and the builds there, follow the devices.

Set apart: 68 sessions on iPhones whose GPU reads no BC texture (A16 and older), which nxnative refuses, from 6 installs; 57 sessions whose game process ran without Increased Memory Limit, which is Cartouche's doing, from 22 installs; 118 sessions of builds with changes of their own, from 14 installs.

## By game

| Game | nxnative | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `bee218d97844` (+15) | 26 | 243 | 41.0 | 30 | 30.0 | 24.2 | 41.5 | 29 | 4% | 0 | 4.0 | 5,950 | 95 of 243 | 3 | – | 2 | 19 | 36 |
| Mario Kart World `0400C3F00006E000` | 8 commits | 20 | 123 | 7.6 | 60 | 30.6 | 28.4 | 118.6 | 108 | 26% | 4,906 | 0.5 | 5,366 | 28 of 123 | 3 | 0 | 1 | 12 | 37 |
| Super Mario Bros. Wonder `010015100B514000` | 7 commits | 19 | 86 | 21.3 | 60 | 59.2 | 56.0 | 27.0 | 35 | 34% | 828 | 0.4 | 2,937 | 2 of 86 | 0 | – | 0 | 1 | 11 |
| Donkey Kong Bananza `040074A01BF12000` | 3 commits | 11 | 44 | 2.3 | 60 | 56.5 | 32.6 | 30.8 | 46 | 14% | 102 | 9.6 | 2,304 | 6 of 44 | 3 | – | 0 | 0 | 11 |
| Mario Kart 8 Deluxe `0100152000022000` | 4 commits | 11 | 27 | 15.0 | 60 | 59.8 | 55.6 | 21.0 | 13 | 56% | 529 | 1.5 | 2,959 | 0 of 27 | 0 | 0 | 0 | 1 | 3 |
| The Legend of Zelda: Breath of the Wild `01007EF00011E000` | 5 commits | 8 | 51 | 2.7 | 60 | 31.2 | 30.0 | 34.0 | 8 | 15% | 415 | 6.4 | 3,178 | 1 of 51 | 0 | – | 0 | 0 | 42 |
| Pokémon Legends: Z-A `0100F43008C44000` | 9 commits | 7 | 53 | 34.8 | 30 | 30.0 | 29.8 | 37.7 | 14 | 23% | 60 | 0.8 | 2,833 | 8 of 53 | 9 | – | 0 | 0 | 5 |
| Super Mario Galaxy `010099C022B96000` | 2 commits | 7 | 15 | 11.0 | – | – | – | – | – | – | – | – | – | 0 of 15 | 0 | – | 0 | 0 | no summary line |
| The Legend of Zelda: Tears of the Kingdom `0100F2C0115B6000` | 4 commits | 6 | 16 | 6.5 | 60 | 30.6 | 29.5 | 36.0 | 36 | 10% | 227 | 2.3 | 3,549 | 4 of 16 | 0 | – | 0 | 0 | 0 |
| Super Mario Odyssey `0100000000010000` | 1 commit | 6 | 15 | 1.8 | 60 | 59.5 | 57.1 | 19.1 | 40 | 68% | 2,216 | 0.1 | 2,889 | 0 of 15 | 2 | – | 0 | 0 | 2 |
| Fire Emblem Fortune's Weave `04007EF01F8AE000` | 1 commit | 5 | 34 | 14.8 | 60 | 59.7 | 52.7 | 23.6 | 122 | 1% | 599 | 3.0 | 3,389 | 15 of 34 | 1 | – | 0 | 0 | 0 |
| FINAL FANTASY RESONANCE `0100606026F12000` | 1 commit | 5 | 30 | 10.9 | 60 | 59.8 | 58.9 | 19.3 | 17 | 7% | 145 | 0.1 | 2,866 | 11 of 30 | 0 | – | 0 | 0 | 5 |
| Luigi's Mansion 3 `0100DCA0064A6000` | 3 commits | 5 | 28 | 1.6 | 60 | 59.1 | 53.1 | 42.2 | 44 | 6% | 1,538 | – | 2,665 | 3 of 28 | 3 | – | 0 | 3 | 3 |
| The Legend of Zelda: Link's Awakening `01006BB00C6F0000` | 3 commits | 4 | 27 | 2.7 | 60 | 60.0 | 57.0 | 18.3 | 11 | 14% | 143 | 0.3 | 2,032 | 0 of 27 | 9 | 0 | 0 | 0 | 6 |
| The Legend of Zelda: Echoes of Wisdom `01008CF01BAAC000` | 3 commits | 4 | 9 | 0.4 | 60 | 60.0 | 55.6 | 18.9 | 20 | 57% | 790 | 0.9 | 1,484 | 0 of 9 | 0 | – | 0 | 0 | 1 |
| Kirby and the Forgotten Land `01004D300C5AE000` | 1 commit | 3 | 22 | 2.4 | 60 | 45.3 | 30.0 | 39.7 | 24 | 56% | 1,326 | 0.3 | 4,006 | 1 of 22 | 0 | – | 0 | 0 | 7 |
| Mario vs. Donkey Kong `0100B99019412000` | not said | 3 | 13 | 0.1 | 60 | 60.0 | – | 18.3 | – | 38% | – | 1.4 | 1,013 | 0 of 13 | 0 | – | 0 | 0 | 6 |
| Minecraft Dungeons II `0100A7C01B792000` | 1 commit | 3 | 12 | 0.0 | – | – | – | – | – | – | – | – | – | 0 of 12 | 12 | – | 0 | 0 | 0 |

## By game and model

| Game | Model | nxnative | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `iPhone19,4` | `bee218d97844` (+11) | 12 | 116 | 25.8 | 30 | 30.0 | 23.7 | 38.3 | 38 | 3% | 58 | 2.7 | 5,983 | 63 of 116 | 0 | – | 0 | 11 | 13 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `iPhone18,2` | 2 commits | 7 | 43 | 3.8 | 30 | 30.0 | 29.9 | 52.9 | 34 | 7% | 0 | 5.8 | 5,530 | 18 of 43 | 0 | – | 1 | 5 | 8 |
| Mario Kart World `0400C3F00006E000` | `iPhone19,4` | 4 commits | 7 | 38 | 2.2 | 60 | 30.5 | 28.9 | 101.0 | 93 | 27% | 3,917 | 0.5 | 7,257 | 8 of 38 | 3 | 0 | 0 | 12 | 2 |
| Donkey Kong Bananza `040074A01BF12000` | `iPhone19,4` | 3 commits | 7 | 23 | 0.8 | 60 | 56.5 | 32.6 | 28.4 | 47 | 5% | 102 | 18.3 | 2,324 | 5 of 23 | 0 | – | 0 | 0 | 1 |
| Super Mario Bros. Wonder `010015100B514000` | `iPhone19,4` | 3 commits | 6 | 23 | 2.5 | 60 | 59.7 | 56.0 | 21.7 | 22 | 44% | 865 | 0.4 | 2,998 | 2 of 23 | 0 | – | 0 | 0 | 2 |
| Pokémon Legends: Z-A `0100F43008C44000` | `iPhone19,4` | 8 commits | 5 | 46 | 33.5 | 30 | 30.0 | 29.8 | 35.9 | 11 | 26% | 60 | 1.0 | 3,624 | 8 of 46 | 9 | – | 0 | 0 | 4 |
| The Legend of Zelda: Breath of the Wild `01007EF00011E000` | `iPhone19,4` | 3 commits | 5 | 30 | 0.9 | 60 | 30.0 | – | 34.6 | 8 | 13% | 415 | 3.3 | 2,861 | 0 of 30 | 0 | – | 0 | 0 | 25 |
| The Legend of Zelda: Tears of the Kingdom `0100F2C0115B6000` | `iPhone19,4` | 3 commits | 5 | 15 | 6.2 | 60 | 30.0 | 29.5 | 36.6 | 35 | 11% | 292 | 1.2 | 3,030 | 4 of 15 | 0 | – | 0 | 0 | 0 |
| Mario Kart World `0400C3F00006E000` | `iPhone18,2` | 3 commits | 5 | 14 | 1.5 | 60 | 31.7 | – | 139.3 | 149 | 29% | 10,052 | 0.6 | 5,314 | 3 of 14 | 0 | – | 1 | 0 | 4 |
| Fire Emblem Fortune's Weave `04007EF01F8AE000` | `iPhone19,4` | 1 commit | 4 | 11 | 2.9 | 60 | 59.4 | 52.7 | 24.3 | 122 | 2% | 599 | 3.0 | 3,389 | 5 of 11 | 0 | – | 0 | 0 | 0 |
| Mario Kart 8 Deluxe `0100152000022000` | `iPhone19,4` | 2 commits | 4 | 10 | 0.8 | 60 | 59.9 | 56.1 | 19.2 | 17 | 65% | 578 | 1.5 | 2,984 | 0 of 10 | 0 | – | 0 | 0 | 2 |
| FINAL FANTASY RESONANCE `0100606026F12000` | `iPhone19,4` | not said | 3 | 28 | 10.8 | 60 | 59.8 | – | 19.4 | 22 | 6% | 117 | 0.1 | 3,658 | 11 of 28 | 0 | – | 0 | 0 | 5 |
| Mario Kart World `0400C3F00006E000` | `iPhone18,1` | not said | 3 | 27 | 0.4 | 60 | 30.0 | – | 214.8 | 121 | 31% | 14,406 | 0.3 | 4,813 | 2 of 27 | 0 | – | 0 | 0 | 18 |
| The Legend of Zelda: Link's Awakening `01006BB00C6F0000` | `iPhone19,4` | 3 commits | 3 | 9 | 2.3 | 60 | 60.0 | 57.0 | 18.2 | 9 | 26% | 157 | 0.5 | 1,831 | 0 of 9 | 0 | – | 0 | 0 | 3 |

## By game and nxnative commit

| Game | nxnative | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `bee218d97844` | 3 | 13 | 2.6 | 30 | – | – | – | – | – | – | 370.3 | – | 7 of 13 | 0 | – | 0 | 4 | 1 |

## Crashes

| Game | Signal | Cause | Installs | Sessions | Models | nxnative | Minutes in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Minecraft Dungeons II `0100A7C01B792000` | SIGABRT | – | 3 | 12 | 3 models | 1 commit | 0.0 |

## Devices

The installs that started Cartouche, as each last did: 255 installs.

- Models: `iPhone19,4` 69, `iPhone18,2` 30, `iPhone18,1` 16, `iPhone19,2` 16, `iPhone18,3` 13, `iPhone16,2` 11, `iPad16,5` 10, `iPhone17,2` 9, `iPhone18,4` 8, `iPad17,1` 7, `iPhone17,3` 6, `iPhone19,3` 6, `iPhone15,4` 5, `iPhone16,1` 5, `iPhone15,2` 4, `iPhone17,1` 4, `iPad13,16` 3, `iPad13,8` 3, `iPad15,7` 3; 27 installs on 21 other models.
- iOS: 26.5 3, 26.6 7, 27.0 48, 27.1 3, 27.2 156, 27.3 37.
- The memory limit iOS sets for Cartouche: 8,192 MiB on 110, 6,144 MiB on 95, 4,096 MiB on 18, 6,656 MiB on 8, 3,376 MiB without Increased Memory Limit on 8, 12,288 MiB on 7, 5,120 MiB without Increased Memory Limit on 3, 2,348 MiB on 3.
- iPhones whose GPU reads no BC texture (A16 and older): 19 installs.

## Played on players' Macs

Cartouche Builder builds each game's app for the Mac too, from the same commit, and follows each game played on the Mac, started from its Play button or from the Finder: how each play ended, as nxnative's launcher says it in its log. A Mac counts as an install does.

58 plays of 10 games on 12 Macs, 5.6 hours.

| Game | Macs | Plays | Hours | Median minutes | Quit | GPU revoked | Crashed | Stopped | Unknown |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | 5 | 17 | 3.5 | 5.3 | 12 | 0 | 0 | 0 | 5 |
| Mario Kart 8 Deluxe `0100152000022000` | 3 | 9 | 0.5 | 2.0 | 3 | 0 | 0 | 0 | 6 |

## Measured on players' Macs

What Cartouche's console on the Mac read of each game played there, in the log nxnative's app for the Mac writes, as Cartouche reads an iPhone's: each Mac counts once, as an install does.

No game was measured on 3 Macs or more.

## IPAs built on players' Macs, by nxnative commit

Cartouche Builder builds players' games with nxnative's build script, on their Macs. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. Regressions are the games that fail with the commit and had built on their Mac before, and on how many Macs: a commit that broke a build makes them on several.

In all, from 99 nxnative commits: 215 IPAs of 55 games built on 49 Macs, in a median of 25 minutes; 129 failed on 35 Macs.

The steps 3 Macs or more failed at: shader split, 23 on 11 Macs; app build, 21 on 11 Macs; iOS shaders, 13 on 8 Macs; IPA pack, 10 on 4 Macs; extract v0, 5 on 4 Macs; check v0 files, 4 on 3 Macs; a step not said, 32 on 12 Macs; other steps, 21.

| nxnative | Macs | Built | Failed | Regressions | Where they failed |
| --- | --- | --- | --- | --- | --- |
| `0c078130f6db` | 8 | 15 | 5 | 0 | other steps 5 |
| `bee218d97844` | 8 | 14 | 4 | 0 | other steps 4 |
| `23790f8dcc3a` | 7 | 12 | 0 | 0 | – |
| `8d62601f375f` | 7 | 7 | 6 | 4 on fewer than 3 Macs | shader split 6 |
| `b06f4e0e4ac2` | 7 | 10 | 2 | 0 | other steps 2 |
| `33c734f61963` | 6 | 7 | 2 | 0 | other steps 2 |
| `786715256f37` | 6 | 0 | 7 | 0 | app build 7 |
| `547c5db647a2` | 4 | 12 | 3 | 0 | other steps 3 |
| `ccd834e06a39` | 4 | 0 | 7 | 1 on fewer than 3 Macs | app build 6, other steps 1 |
| `e4b0d9b75d39` | 4 | 8 | 5 | 0 | other steps 5 |
| `2e6edda4d334` | 3 | 3 | 2 | 0 | other steps 2 |
| `3084f7a205bc` | 3 | 4 | 2 | 0 | other steps 2 |
| `4cda80ea694a` | 3 | 1 | 4 | 2 on fewer than 3 Macs | other steps 4 |
| `5f6f162257f5` | 3 | 0 | 3 | 1 on fewer than 3 Macs | other steps 3 |
| `8d44aaf8f3a5` | 3 | 1 | 4 | 0 | other steps 4 |
| `d6585a2de864` | 3 | 1 | 2 | 1 on fewer than 3 Macs | other steps 2 |
| `e6a358f5c131` | 3 | 3 | 1 | 0 | other steps 1 |

## Mac apps built on players' Macs, by nxnative commit

Cartouche Builder also builds each game's app for the Mac it builds on, from the same commit and files, after its IPA or alone. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. Regressions are the games that fail with the commit and had built on their Mac before, and on how many Macs: a commit that broke a build makes them on several.

In all, from 18 nxnative commits: 37 Mac apps of 22 games built on 13 Macs, in a median of 41 minutes; some failed, on fewer than 3 Macs.

No nxnative commit was built for the Mac on 3 Macs or more.

## How it is summed up

- An install is one copy of Cartouche on one iPhone or iPad, under a random number it changes every 13 months or when its player erases what it sent: a player who installs Cartouche again is a new install. A Mac is one copy of Cartouche Builder. Neither number is ever written here.
- Each figure is the median of each install's own median, so that each install counts once however much it played; the peak is each install's highest, of its sessions that drew a frame. Stutters waiting for shaders are a share of all the stutters of the line.
- FPS slowest 5% is the rate of the slowest 5% of a session's time: the frame rate of each `[nvn] power` line, over its 300 frames, weighted by how long they lasted. nxnative times them by the clock, so a stretch that held a pause, the game left behind Cartouche's console or Cartouche in the background counts at the rate that pause brought it to: it counts only from the sessions Cartouche read with its reading 2 of the log or a later one, which leaves such a stretch out, and shows – before. Stutters and the shader stall are per minute of the whole session.
- The figures come from the lines nxnative writes in `log.txt`, which Cartouche reads after each session ([CartoucheGameLog.swift](https://github.com/cartouche-app/Cartouche/blob/main/launcher/Sources/CartoucheGameLog.swift)): the `[nvn]` timing, on-screen and power lines, `[longframe]`, `pipeline prepare`, the memory and thermal lines, `CRASH sig=`, `GPU access revoked` and `[RED] boot:`. A session's commit is the first 12 digits of `DMCommit` in the game's `Info.plist`; Cartouche 0.11.2 and before did not send it. Target fps is the rate most of the line's sessions asked for.
- Reached serious heat: the sessions iOS put in its serious thermal state. Drew no frame: the session ended before nxnative's first summary line, whatever its end. A line none of whose sessions wrote one, though they lasted 30 minutes or more in all, says no summary line instead: the game may run while nxnative writes no `[nvn]` timing, on-screen or power line for it, as much as stay on a black screen, and its frame figures show –.
- GPU lost: the crashes nxnative ended once the system took the GPU away from the game for the GPU errors it caused (`[RED] GPU access revoked`), as the crashes' cause says too. Cartouche tells them from its reading 4 of the log on: before it, such a session is a crash like any other abort, and a line with no session read so shows –. On a Mac, nxnative quits the game itself, and its crash has no signal.
- A session counts once, as last sent; a copy of another region counts for its game.
- nxnative, Models: the commit, or the model, most installs of the line ran, when at least 3 did, and how many others; else only how many. A Mac counts as an install does: a step of a build shows when at least 3 Macs failed at it.
- On players' Macs: a play is a game Cartouche Builder started, from its Play button, the Finder, the Dock or Launchpad, counted once it ended, as the last line of nxnative's launcher in its log says: Quit, `launcher: the host exited with 0`; GPU revoked, with 70, macOS having stopped the game's GPU work; Crashed, another exit code or a signal; Stopped, SIGHUP, SIGINT, SIGKILL or SIGTERM, from outside; Unknown, no such line, as when nxnative's window was closed without playing. Median minutes: the median of each Mac's own median play. Measured: Cartouche's console on the Mac reads the log of each game played there as Cartouche reads an iPhone's, its minutes from the start of nxnative's launcher, its settings window too; nxnative reads no thermal state on the Mac. The Macs whose Cartouche Builder follows a fork of nxnative are left out, and so are the builds with changes of their own.
- Builds, of IPAs and of Mac apps: the Macs whose Cartouche Builder follows a fork of nxnative are left out, and so are the builds the player stopped and the errors of Cartouche Builder's own code. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. A regression is such a game that failed and had built on that Mac on an earlier try, from any commit of the 28 days. Where they failed is nxnative's stage of each failed game's last try. Minutes: the median of each Mac's own median build, from its builds that built.
