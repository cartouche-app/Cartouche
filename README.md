# nxnative's games on players' iPhones and Macs

What the players of [Cartouche](https://github.com/cartouche-app/Cartouche) measured of nxnative's games from 2026-11-10 to 2026-11-25, on their iPhones and on their Macs, summed up for nxnative's developers each Thursday. How, and what is left out: [telemetry/README.md](https://github.com/cartouche-app/Cartouche/blob/main/telemetry/README.md#nxnatives-page).

2827 game sessions on iPhones and iPads from 144 installs, 527.9 hours of play. 942 of the 2249 sessions that count name their nxnative commit. Every line, and every figure, sums up at least 3 installs, or 3 Macs: a smaller group is left out, and a figure fewer of them gave shows –. The games played on players' Macs, and the builds there, follow the devices.

Set apart: 148 sessions on iPhones whose GPU reads no BC texture (A16 and older), which nxnative refuses, from 8 installs; 69 sessions whose game process ran without Increased Memory Limit, which is Cartouche's doing, from 27 installs; 267 sessions of builds with changes of their own, from 22 installs.

## By game

| Game | nxnative | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `184847c51117` (+36) | 48 | 589 | 93.5 | 30 | 30.0 | 24.2 | 43.4 | 33 | 4% | 1 | 4.6 | 5,950 | 224 of 589 | 7 | 2 | 2 | 22 | 93 |
| Mario Kart World `0400C3F00006E000` | 16 commits | 29 | 188 | 11.3 | 60 | 32.0 | 27.4 | 118.6 | 106 | 25% | 4,906 | 0.8 | 5,197 | 39 of 188 | 4 | 0 | 1 | 25 | 49 |
| Super Mario Bros. Wonder `010015100B514000` | 11 commits | 23 | 102 | 24.5 | 60 | 59.2 | 56.3 | 27.0 | 36 | 37% | 947 | 0.4 | 3,058 | 3 of 102 | 0 | 0 | 0 | 1 | 12 |
| Donkey Kong Bananza `040074A01BF12000` | 8 commits | 19 | 87 | 8.8 | 60 | 56.5 | 30.0 | 33.3 | 45 | 10% | 91 | 0.9 | 2,304 | 17 of 87 | 8 | 0 | 0 | 0 | 17 |
| Mario Kart 8 Deluxe `0100152000022000` | 8 commits | 18 | 57 | 23.8 | 60 | 59.8 | 57.2 | 20.3 | 17 | 51% | 553 | 1.5 | 2,974 | 5 of 57 | 0 | 0 | 0 | 1 | 8 |
| The Legend of Zelda: Breath of the Wild `01007EF00011E000` | 8 commits | 14 | 104 | 20.8 | 60 | 30.9 | 30.0 | 34.3 | 20 | 4% | 264 | 2.1 | 3,402 | 12 of 104 | 11 | 0 | 0 | 0 | 53 |
| Pokémon Legends: Z-A `0100F43008C44000` | 13 commits | 10 | 85 | 41.0 | 30 | 30.0 | 29.6 | 42.5 | 17 | 23% | 229 | 0.8 | 3,274 | 8 of 85 | 9 | 0 | 0 | 0 | 8 |
| Super Mario Odyssey `0100000000010000` | 7 commits | 10 | 48 | 4.0 | 60 | 59.6 | 56.6 | 19.0 | 31 | 33% | 2,289 | 0.1 | 3,200 | 24 of 48 | 17 | 0 | 0 | 1 | 5 |
| Kirby and the Forgotten Land `01004D300C5AE000` | 3 commits | 8 | 29 | 2.7 | 60 | 35.0 | 29.4 | 33.5 | 34 | 58% | 2,617 | 0.3 | 3,582 | 3 of 29 | 0 | 0 | 0 | 0 | 7 |
| The Legend of Zelda: Link's Awakening `01006BB00C6F0000` | 5 commits | 7 | 49 | 11.4 | 60 | 57.6 | 45.9 | 25.6 | 34 | 16% | 213 | 0.2 | 2,162 | 4 of 49 | 15 | 0 | 0 | 0 | 8 |
| FINAL FANTASY RESONANCE `0100606026F12000` | 2 commits | 7 | 42 | 13.1 | 60 | 59.8 | 57.1 | 18.9 | 27 | 8% | 295 | 0.1 | 3,446 | 14 of 42 | 0 | 0 | 0 | 0 | 6 |
| Super Mario Galaxy `010099C022B96000` | 2 commits | 7 | 16 | 11.0 | – | – | – | – | – | – | – | – | – | 0 of 16 | 0 | 0 | 0 | 0 | no summary line |
| Fire Emblem Fortune's Weave `04007EF01F8AE000` | 1 commit | 6 | 87 | 32.1 | 60 | 59.8 | 54.9 | 23.6 | 101 | 1% | 599 | 1.7 | 3,389 | 46 of 87 | 1 | 0 | 0 | 0 | 1 |
| Pokemon Pokopia `0400A3A01EE4C000` | 8 commits | 6 | 65 | 10.3 | 60 | 59.2 | 53.0 | 31.5 | 44 | 1% | 429 | 0.5 | 1,702 | 18 of 65 | 3 | 0 | 0 | 0 | 11 |
| The Legend of Zelda: Tears of the Kingdom `0100F2C0115B6000` | 5 commits | 6 | 17 | 6.6 | 60 | 30.6 | 29.7 | 34.8 | 36 | 10% | 263 | 2.3 | 3,549 | 4 of 17 | 0 | 0 | 0 | 0 | 0 |
| Luigi's Mansion 3 `0100DCA0064A6000` | 3 commits | 5 | 38 | 1.9 | 60 | 58.5 | 50.0 | 42.2 | 36 | 6% | 1,538 | – | 2,665 | 6 of 38 | 3 | 0 | 0 | 3 | 5 |
| Mario vs. Donkey Kong `0100B99019412000` | not said | 5 | 17 | 0.2 | 60 | 60.0 | 59.8 | 18.6 | 13 | 21% | 503 | 0.6 | 997 | 0 of 17 | 0 | 0 | 0 | 0 | 7 |
| Super Mario 3D World + Bowser's Fury `010028600EBDA000` | 1 commit | 5 | 13 | 0.2 | 60 | 59.6 | 58.5 | 23.3 | 34 | 80% | 5,897 | 0.7 | 1,742 | 1 of 13 | 0 | 0 | 0 | 0 | 5 |
| The Legend of Zelda: Echoes of Wisdom `01008CF01BAAC000` | 4 commits | 5 | 13 | 2.1 | 60 | 60.0 | 54.4 | 18.7 | 25 | 26% | 690 | 0.7 | 1,758 | 1 of 13 | 0 | 0 | 0 | 0 | 2 |
| Captain Toad: Treasure Tracker `01009BF0072D4000` | 1 commit | 5 | 13 | 0.9 | 60 | 60.0 | 59.8 | 18.5 | 10 | 22% | 161 | 1.5 | 1,155 | 1 of 13 | 0 | 0 | 0 | 0 | 0 |
| Castlevania: Belmont's Curse `0100BA4026E94000` | 1 commit | 4 | 7 | 1.3 | 60 | 59.4 | 52.5 | 21.0 | 27 | 27% | 105 | 1.5 | 2,155 | 0 of 7 | 0 | 0 | 0 | 0 | 0 |
| EA SPORTS FC 27 `0100C49025D3E000` | 2 commits | 3 | 19 | 1.8 | 60 | 30.0 | 29.9 | 39.5 | 30 | 12% | 1,865 | 0.1 | 3,502 | 1 of 19 | 0 | 0 | 0 | 0 | 0 |
| `0100A250097F0000` | not said | 3 | 15 | 0.7 | 60 | 59.5 | 55.2 | 18.8 | 16 | 29% | 324 | 0.1 | 3,402 | 0 of 15 | 0 | 0 | 0 | 0 | 0 |
| Hades `0100535012974000` | 3 commits | 3 | 14 | 1.4 | – | – | – | – | – | – | – | – | – | 3 of 14 | 0 | 0 | 0 | 0 | no summary line |
| Minecraft Dungeons II `0100A7C01B792000` | 1 commit | 3 | 12 | 0.0 | – | – | – | – | – | – | – | – | – | 0 of 12 | 12 | – | 0 | 0 | 0 |
| Pokémon Sword `0100ABF008968000` | 2 commits | 3 | 10 | 2.6 | 30 | 29.9 | 29.9 | 36.2 | – | 2% | – | 4.3 | 1,485 | 1 of 10 | 0 | 0 | 0 | 0 | 1 |
| Mario Tennis Fever `0400D4201C6EA000` | 1 commit | 3 | 10 | 0.9 | 60 | – | – | – | – | – | – | 0.2 | – | 2 of 10 | 0 | 0 | 0 | 0 | 5 |
| The Legend of Zelda: Skyward Sword HD `01002DA013484000` | 1 commit | 3 | 7 | 0.9 | 60 | 60.0 | 59.4 | 17.6 | 16 | 40% | 451 | – | 1,494 | 0 of 7 | 0 | 0 | 0 | 0 | 1 |
| DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition `01006C300E9F0000` | 1 commit | 3 | 7 | 0.4 | 60 | 60.0 | 59.4 | 26.0 | – | 37% | – | – | 2,569 | 1 of 7 | 0 | 0 | 0 | 0 | 0 |
| Pokémon Scarlet `0100A3D008C5C000` | 1 commit | 3 | 6 | 0.7 | 30 | 29.8 | – | 48.0 | – | 19% | – | – | 2,445 | 0 of 6 | 0 | 0 | 0 | 0 | 0 |
| Hollow Knight `0100633007D48000` | 1 commit | 3 | 5 | 0.2 | 60 | – | – | – | 9 | 21% | – | – | – | 0 of 5 | 0 | 0 | 0 | 0 | 2 |
| Cuphead `0100A5C00D162000` | not said | 3 | 5 | 0.5 | 60 | 60.0 | – | 23.0 | 4 | 3% | 4 | 0.1 | 2,824 | 0 of 5 | 0 | 0 | 0 | 0 | 0 |
| Pokémon Legends: Arceus `01001F5010DFA000` | 2 commits | 3 | 4 | 0.9 | 30 | 29.9 | 29.0 | 38.8 | 21 | 22% | 716 | – | 994 | 0 of 4 | 0 | 0 | 0 | 0 | 1 |
| Super Mario Party Jamboree `0100965017338000` | not said | 3 | 3 | 0.4 | 60 | 60.0 | – | 18.1 | 14 | 10% | 366 | 9.2 | 3,172 | 0 of 3 | 0 | 0 | 0 | 0 | 0 |

## By game and model

| Game | Model | nxnative | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `iPhone19,4` | `8d62601f375f` (+22) | 16 | 184 | 34.5 | 60 | 30.0 | 23.8 | 39.2 | 38 | 3% | 32 | 3.8 | 5,952 | 98 of 184 | 0 | 0 | 0 | 11 | 22 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `iPhone18,2` | 10 commits | 14 | 158 | 16.5 | 30 | 27.6 | 22.9 | 55.4 | 33 | 7% | 0 | 46.4 | 5,914 | 59 of 158 | 0 | 0 | 1 | 7 | 31 |
| Mario Kart World `0400C3F00006E000` | `iPhone19,4` | 9 commits | 11 | 76 | 3.4 | 60 | 34.9 | 28.1 | 96.0 | 106 | 29% | 4,497 | 0.5 | 5,448 | 11 of 76 | 4 | 0 | 0 | 25 | 10 |
| Donkey Kong Bananza `040074A01BF12000` | `iPhone19,4` | 5 commits | 8 | 38 | 1.6 | 60 | 56.5 | 32.6 | 26.5 | 46 | 7% | 60 | 0.8 | 2,355 | 10 of 38 | 5 | 0 | 0 | 0 | 1 |
| Mario Kart World `0400C3F00006E000` | `iPhone18,2` | 4 commits | 7 | 17 | 2.5 | 60 | 31.7 | 27.2 | 139.3 | 128 | 25% | 9,359 | 1.3 | 4,905 | 5 of 17 | 0 | 0 | 1 | 0 | 4 |
| Pokémon Legends: Z-A `0100F43008C44000` | `iPhone19,4` | 11 commits | 6 | 76 | 39.5 | 30 | 30.0 | 29.8 | 36.6 | 12 | 25% | 145 | 0.8 | 3,536 | 8 of 76 | 9 | 0 | 0 | 0 | 7 |
| The Legend of Zelda: Breath of the Wild `01007EF00011E000` | `iPhone19,4` | 5 commits | 6 | 35 | 1.7 | 60 | 30.0 | 30.0 | 34.8 | 14 | 23% | 492 | 2.5 | 3,020 | 1 of 35 | 0 | 0 | 0 | 0 | 29 |
| Super Mario Bros. Wonder `010015100B514000` | `iPhone19,4` | 4 commits | 6 | 25 | 2.8 | 60 | 59.7 | 55.7 | 21.2 | 26 | 45% | 1,066 | 0.4 | 3,344 | 2 of 25 | 0 | 0 | 0 | 0 | 2 |
| The Legend of Zelda: Tears of the Kingdom `0100F2C0115B6000` | `iPhone19,4` | 4 commits | 5 | 16 | 6.2 | 60 | 30.0 | 29.6 | 34.2 | 35 | 11% | 292 | 1.2 | 3,030 | 4 of 16 | 0 | 0 | 0 | 0 | 0 |
| Mario Kart 8 Deluxe `0100152000022000` | `iPhone19,4` | 3 commits | 5 | 15 | 1.3 | 60 | 59.9 | 56.2 | 18.9 | 17 | 48% | 576 | 1.5 | 3,001 | 0 of 15 | 0 | 0 | 0 | 0 | 2 |
| FINAL FANTASY RESONANCE `0100606026F12000` | `iPhone19,4` | 1 commit | 4 | 39 | 12.7 | 60 | 59.8 | 57.1 | 19.3 | 27 | 8% | 153 | 0.1 | 4,247 | 13 of 39 | 0 | 0 | 0 | 0 | 6 |
| Mario Kart World `0400C3F00006E000` | `iPhone18,1` | not said | 4 | 39 | 1.3 | 30 | 30.0 | 25.6 | 199.7 | 118 | 21% | 12,834 | 0.4 | 5,048 | 8 of 39 | 0 | 0 | 0 | 0 | 21 |
| Donkey Kong Bananza `040074A01BF12000` | `iPhone18,2` | not said | 4 | 19 | 4.7 | 60 | 38.8 | 19.9 | 33.9 | 52 | 8% | 370 | 0.7 | 2,601 | 4 of 19 | 3 | 0 | 0 | 0 | 2 |
| Fire Emblem Fortune's Weave `04007EF01F8AE000` | `iPhone19,4` | 1 commit | 4 | 12 | 2.9 | 60 | 59.4 | 52.7 | 23.9 | 122 | 2% | 599 | 3.0 | 3,389 | 5 of 12 | 0 | 0 | 0 | 0 | 0 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `iPhone19,2` | 5 commits | 3 | 126 | 26.4 | 60 | 30.0 | 26.4 | 37.1 | 26 | 5% | 9 | 2.9 | 7,260 | 35 of 126 | 0 | 0 | 1 | 3 | 18 |
| Pokemon Pokopia `0400A3A01EE4C000` | `iPhone19,4` | 7 commits | 3 | 49 | 6.8 | 60 | 59.4 | 53.0 | 31.6 | 167 | 0% | 429 | 0.5 | 1,918 | 13 of 49 | 3 | 0 | 0 | 0 | 9 |
| Super Mario Bros. Wonder `010015100B514000` | `iPhone18,1` | not said | 3 | 22 | 0.1 | 60 | 60.0 | 60.0 | 23.1 | – | 58% | – | – | 1,242 | 1 of 22 | 0 | 0 | 0 | 0 | 5 |
| The Legend of Zelda: Link's Awakening `01006BB00C6F0000` | `iPhone19,4` | 3 commits | 3 | 18 | 10.4 | 60 | 60.0 | 55.6 | 18.5 | 13 | 18% | 213 | 0.1 | 2,234 | 0 of 18 | 0 | 0 | 0 | 0 | 4 |
| Mario vs. Donkey Kong `0100B99019412000` | `iPhone18,1` | not said | 3 | 14 | 0.1 | 60 | 59.8 | – | 18.6 | – | 19% | – | 0.6 | 799 | 0 of 14 | 0 | 0 | 0 | 0 | 7 |
| Mario Kart 8 Deluxe `0100152000022000` | `iPhone18,1` | 1 commit | 3 | 11 | 7.4 | 60 | 59.9 | – | 33.4 | 12 | 62% | 585 | 1.8 | 2,989 | 2 of 11 | 0 | 0 | 0 | 0 | 0 |
| Kirby and the Forgotten Land `01004D300C5AE000` | `iPhone18,1` | 1 commit | 3 | 9 | 0.5 | 60 | 59.6 | 29.9 | 33.6 | 45 | 58% | 3,187 | – | 3,394 | 0 of 9 | 0 | 0 | 0 | 0 | 0 |
| Super Mario Bros. Wonder `010015100B514000` | `iPhone18,2` | 3 commits | 3 | 6 | 0.3 | 60 | 59.0 | 59.2 | 32.9 | – | 62% | – | – | 3,426 | 0 of 6 | 0 | 0 | 0 | 0 | 0 |
| Super Mario Odyssey `0100000000010000` | `iPhone19,4` | 1 commit | 3 | 5 | 1.7 | 60 | 59.0 | – | 17.7 | – | 65% | – | – | 2,834 | 0 of 5 | 0 | 0 | 0 | 0 | 0 |

## By game and nxnative commit

| Game | nxnative | Shader chain | Installs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Reached serious heat | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `184847c51117` | not said | 4 | 8 | 1.9 | 60 | 28.6 | 24.1 | 45.2 | 54 | 5% | 44 | 4.4 | – | 0 of 8 | 0 | 0 | 0 | 0 | 3 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `e7dc2d9afdba` | not said | 3 | 23 | 2.3 | 60 | 30.0 | 26.6 | 40.9 | 35 | 6% | 0 | 4.1 | 4,485 | 9 of 23 | 0 | 0 | 0 | 0 | 8 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `8d62601f375f` | not said | 3 | 14 | 5.7 | 30 | 28.4 | 21.1 | 51.6 | 48 | 1% | 58 | 134.5 | 5,955 | 11 of 14 | 0 | 0 | 0 | 1 | 1 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `bee218d97844` | not said | 3 | 14 | 2.6 | 30 | – | – | – | – | – | – | 370.3 | – | 8 of 14 | 0 | – | 0 | 4 | 1 |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | `d2fd78b402f9` | not said | 3 | 6 | 0.7 | 60 | 43.5 | 28.5 | 55.7 | 69 | 0% | 0 | 102.9 | 5,642 | 1 of 6 | 2 | 2 | 0 | 0 | 0 |

## Crashes

| Game | Signal | Cause | Installs | Sessions | Models | nxnative | Minutes in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Minecraft Dungeons II `0100A7C01B792000` | SIGABRT | – | 3 | 12 | 3 models | 1 commit | 0.0 |

## Devices

The installs that started Cartouche, as each last did: 351 installs.

- Models: `iPhone19,4` 85, `iPhone18,2` 39, `iPhone18,1` 25, `iPhone19,2` 17, `iPhone17,2` 16, `iPhone16,2` 15, `iPhone18,3` 15, `iPhone19,3` 15, `iPad16,5` 14, `iPhone15,4` 10, `iPhone18,4` 9, `iPad17,1` 7, `iPhone17,3` 7, `iPhone16,1` 6, `iPad14,3` 5, `iPhone15,2` 5, `iPhone17,1` 5, `iPad13,8` 4, `iPhone12,1` 4, `iPad13,16` 3, `iPad15,7` 3, `iPad16,3` 3, `iPhone14,3` 3, `iPhone14,5` 3; 33 installs on 24 other models.
- iOS: 26.5 8, 26.6 12, 27.0 66, 27.1 3, 27.2 198, 27.3 60.
- The memory limit iOS sets for Cartouche: 8,192 MiB on 134, 6,144 MiB on 131, 4,096 MiB on 27, 3,376 MiB without Increased Memory Limit on 15, 6,656 MiB on 13, 16,384 MiB on 8, 2,348 MiB on 8, 12,288 MiB on 7, 5,120 MiB without Increased Memory Limit on 4.
- iPhones whose GPU reads no BC texture (A16 and older): 36 installs.

## Played on players' Macs

Cartouche Builder builds each game's app for the Mac too, from the same commit, and follows each game played on the Mac, started from its Play button or from the Finder: how each play ended, as nxnative's launcher says it in its log. A Mac counts as an install does.

118 plays of 13 games on 20 Macs, 18.9 hours.

| Game | Macs | Plays | Hours | Median minutes | Quit | GPU revoked | Crashed | Stopped | Unknown |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | 10 | 54 | 14.6 | 3.7 | 41 | 3 | 0 | 0 | 10 |
| Mario Kart 8 Deluxe `0100152000022000` | 3 | 11 | 0.5 | 2.0 | 4 | 0 | 0 | 0 | 7 |

## Measured on players' Macs

What Cartouche's console on the Mac read of each game played there, in the log nxnative's app for the Mac writes, as Cartouche reads an iPhone's: each Mac counts once, as an install does.

| Game | nxnative | Macs | Sessions | Hours | Target fps | FPS median | FPS slowest 5% | Frame p99 ms | Stutters a minute | Waiting for shaders | Shader stall ms a minute | Prepare s | Peak MiB | Crashed | GPU lost | Failed to boot | Out of memory | Drew no frame |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The Legend of Zelda: Ocarina of Time `0400486024DEC000` | 7 commits | 6 | 28 | 11.1 | 60 | 60.0 | 54.2 | 18.3 | 28 | 2% | 11 | 4.7 | 15,376 | 1 | 1 | 0 | 0 | 1 |

## IPAs built on players' Macs, by nxnative commit

Cartouche Builder builds players' games with nxnative's build script, on their Macs. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. Regressions are the games that fail with the commit and had built on their Mac before, and on how many Macs: a commit that broke a build makes them on several.

In all, from 185 nxnative commits: 525 IPAs of 100 games built on 63 Macs, in a median of 24 minutes; 232 failed on 44 Macs.

The steps 3 Macs or more failed at: shader split, 59 on 18 Macs; app build, 22 on 12 Macs; iOS shaders, 18 on 11 Macs; IPA pack, 11 on 5 Macs; extract v0, 5 on 4 Macs; check v0 files, 4 on 3 Macs; survey: code modules, 4 on 3 Macs; a step not said, 55 on 17 Macs; other steps, 54.

| nxnative | Macs | Built | Failed | Regressions | Where they failed |
| --- | --- | --- | --- | --- | --- |
| `0c078130f6db` | 8 | 15 | 5 | 0 | other steps 5 |
| `bee218d97844` | 8 | 14 | 4 | 0 | other steps 4 |
| `23790f8dcc3a` | 7 | 12 | 0 | 0 | – |
| `24e007bed7c2` | 7 | 9 | 1 | 0 | other steps 1 |
| `8d62601f375f` | 7 | 7 | 6 | 4 on fewer than 3 Macs | shader split 6 |
| `b06f4e0e4ac2` | 7 | 10 | 2 | 0 | other steps 2 |
| `0b5fd6020093` | 6 | 5 | 3 | 1 on fewer than 3 Macs | other steps 3 |
| `184847c51117` | 6 | 12 | 0 | 0 | – |
| `786715256f37` | 6 | 0 | 7 | 0 | app build 7 |
| `a67c884ff5f8` | 6 | 6 | 4 | 3 on 3 Macs | other steps 4 |
| `d14217007e76` | 6 | 8 | 2 | 0 | other steps 2 |
| `33c734f61963` | 5 | 5 | 2 | 0 | other steps 2 |
| `8d44bd6ac34a` | 5 | 4 | 19 | 4 on 4 Macs | shader split 6, other steps 13 |
| `0293739df4d9` | 4 | 8 | 0 | 0 | – |
| `130ef2936771` | 4 | 3 | 3 | 2 on fewer than 3 Macs | other steps 3 |
| `2dacca8d0031` | 4 | 26 | 5 | 0 | other steps 5 |
| `547c5db647a2` | 4 | 12 | 3 | 0 | other steps 3 |
| `7ebb76eda8ec` | 4 | 3 | 3 | 3 on 3 Macs | shader split 3 |
| `806fabe19829` | 4 | 9 | 0 | 0 | – |
| `ccd834e06a39` | 4 | 0 | 7 | 1 on fewer than 3 Macs | app build 6, other steps 1 |
| `e4b0d9b75d39` | 4 | 11 | 4 | 0 | other steps 4 |
| `e7dc2d9afdba` | 4 | 4 | 0 | 0 | – |
| `eed6ffc95a0f` | 4 | 2 | 3 | 3 on fewer than 3 Macs | other steps 3 |
| `002724b8e6ae` | 3 | 5 | 0 | 0 | – |
| `087faba98da2` | 3 | 4 | 3 | 0 | other steps 3 |
| `2e6edda4d334` | 3 | 3 | 2 | 0 | other steps 2 |
| `3084f7a205bc` | 3 | 4 | 2 | 0 | other steps 2 |
| `385079757d3a` | 3 | 8 | 2 | 1 on fewer than 3 Macs | other steps 2 |
| `3984f5aa3171` | 3 | 4 | 4 | 2 on fewer than 3 Macs | other steps 4 |
| `4cda80ea694a` | 3 | 1 | 4 | 2 on fewer than 3 Macs | other steps 4 |
| `5dfc86ae80c5` | 3 | 5 | 0 | 0 | – |
| `5f6f162257f5` | 3 | 0 | 3 | 1 on fewer than 3 Macs | other steps 3 |
| `8d44aaf8f3a5` | 3 | 1 | 4 | 0 | other steps 4 |
| `b989137a51d0` | 3 | 4 | 2 | 1 on fewer than 3 Macs | other steps 2 |
| `cb126758411b` | 3 | 5 | 1 | 0 | other steps 1 |
| `d2fd78b402f9` | 3 | 10 | 3 | 0 | other steps 3 |
| `d6585a2de864` | 3 | 1 | 2 | 1 on fewer than 3 Macs | other steps 2 |

## Mac apps built on players' Macs, by nxnative commit

Cartouche Builder also builds each game's app for the Mac it builds on, from the same commit and files, after its IPA or alone. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. Regressions are the games that fail with the commit and had built on their Mac before, and on how many Macs: a commit that broke a build makes them on several.

In all, from 75 nxnative commits: 256 Mac apps of 70 games built on 26 Macs, in a median of 20 minutes; 11 failed on 6 Macs.

The steps 3 Macs or more failed at: shader split, 5 on 3 Macs; other steps, 6.

| nxnative | Macs | Built | Failed | Regressions | Where they failed |
| --- | --- | --- | --- | --- | --- |
| `24e007bed7c2` | 5 | 11 | 0 | 0 | – |
| `184847c51117` | 3 | 8 | 0 | 0 | – |
| `73150dd93e3d` | 3 | 7 | 0 | 0 | – |
| `d2fd78b402f9` | 3 | 19 | 1 | 0 | other steps 1 |
| `e4b0d9b75d39` | 3 | 4 | 0 | 0 | – |

## How it is summed up

- An install is one copy of Cartouche on one iPhone or iPad, under a random number it changes every 13 months or when its player erases what it sent: a player who installs Cartouche again is a new install. A Mac is one copy of Cartouche Builder. Neither number is ever written here.
- Each figure is the median of each install's own median, so that each install counts once however much it played; the peak is each install's highest, of its sessions that drew a frame. Stutters waiting for shaders are a share of all the stutters of the line.
- FPS slowest 5% is the rate of the slowest 5% of a session's time: the frame rate of each `[nvn] power` line, over its 300 frames, weighted by how long they lasted. nxnative times them by the clock, so a stretch that held a pause, the game left behind Cartouche's console or Cartouche in the background counts at the rate that pause brought it to: it counts only from the sessions Cartouche read with its reading 2 of the log or a later one, which leaves such a stretch out, and shows – before. Stutters and the shader stall are per minute of the whole session.
- The figures come from the lines nxnative writes in `log.txt`, which Cartouche reads after each session ([CartoucheGameLog.swift](https://github.com/cartouche-app/Cartouche/blob/main/launcher/Sources/CartoucheGameLog.swift)): the `[nvn]` timing, on-screen and power lines, `[longframe]`, `pipeline prepare`, the memory and thermal lines, `CRASH sig=`, `GPU access revoked` and `[RED] boot:`; for a game drawn with Vulkan, which writes no `[nvn]` line, its `[vk] frame` lines that drew, from Cartouche's reading 5 of the log on, which tell how far it drew and time nothing: its frame figures and stutters show –. A session's commit is the first 12 digits of `DMCommit` in the game's `Info.plist`; Cartouche 0.11.2 and before did not send it. Its shader chain is the first 12 digits of `DMChain` beside it; Cartouche 0.16.1 and before did not send it. Target fps is the rate most of the line's sessions asked for.
- Reached serious heat: the sessions iOS put in its serious thermal state. Drew no frame: the session ended before nxnative's first summary line, or `[vk] frame` line that drew, whatever its end. A line none of whose sessions wrote one, though they lasted 30 minutes or more in all, says no summary line instead: the game may run while Cartouche reads none of these lines for it, as a game drawn with Vulkan before its reading 5, as much as stay on a black screen, and its frame figures show –.
- GPU lost: the crashes nxnative ended once the system took the GPU away from the game for the GPU errors it caused (`[RED] GPU access revoked`), as the crashes' cause says too. Cartouche tells them from its reading 4 of the log on: before it, such a session is a crash like any other abort, and a line with no session read so shows –. On a Mac, nxnative quits the game itself, and its crash has no signal.
- A session counts once, as last sent; a copy of another region counts for its game.
- nxnative, Shader chain, Models: the commit, the shader chain or the model most installs of the line ran, when at least 3 did, and how many others; else only how many, or not said when none sent it. A Mac counts as an install does: a step of a build shows when at least 3 Macs failed at it.
- On players' Macs: a play is a game Cartouche Builder started, from its Play button, the Finder, the Dock or Launchpad, counted once it ended, as the last line of nxnative's launcher in its log says: Quit, `launcher: the host exited with 0`; GPU revoked, with 70, macOS having stopped the game's GPU work; Crashed, another exit code or a signal; Stopped, SIGHUP, SIGINT, SIGKILL or SIGTERM, from outside; Unknown, no such line, as when nxnative's window was closed without playing. Median minutes: the median of each Mac's own median play. Measured: Cartouche's console on the Mac reads the log of each game played there as Cartouche reads an iPhone's, its minutes from the start of nxnative's launcher, its settings window too; nxnative reads no thermal state on the Mac. The Macs whose Cartouche Builder follows a fork of nxnative are left out, and so are the builds with changes of their own.
- Builds, of IPAs and of Mac apps: the Macs whose Cartouche Builder follows a fork of nxnative are left out, and so are the builds the player stopped and the errors of Cartouche Builder's own code. A game of a Mac counts once for a commit, as its last try with it ended, however often its player tried it again. A regression is such a game that failed and had built on that Mac on an earlier try, from any commit of the 28 days. Where they failed is nxnative's stage of each failed game's last try. Minutes: the median of each Mac's own median build, from its builds that built.
