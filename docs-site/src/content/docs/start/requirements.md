---
title: What you need
description: The iPhone, iPad or Mac Cartouche runs on, the Apple account it signs with, and your own games.
sidebar:
  order: 1
---

Cartouche runs the games [nxnative](https://github.com/seedds/nxnative) makes native for iPhone, iPad and Mac. You bring your own copies; Cartouche does the rest.

| | |
| --- | --- |
| **iPhone** | iOS 26 or later, on an iPhone 15 Pro or newer. An iPhone 11 to 15 plays the games Cartouche for Mac builds from nxnative-nobc ([below](#iphone-11-to-15)). The biggest games need a 12 GB iPhone. |
| **iPad** | iPadOS 26 or later, on an iPad with an M1 chip or newer. |
| **Mac** | A Mac with Apple silicon and macOS 26.6 or later, to build your games and play them there. With no Mac, [Cartouche Cloud](/cloud/) builds them for you. |
| **Apple account** | A free one is enough, or a signing certificate (.p12) of your own. |
| **Computer** | A Mac or a Windows PC, once, to install Cartouche, or none if you already use [SideStore](/start/sidestore/). |
| **Your games** | Your own copies, dumped from your console. |

## Three ways to your games

1. **With a Mac.** [Cartouche for Mac](/mac/install/) builds each game from your copy, for the iPhone, the iPad and the Mac, and builds it again when nxnative improves it. Cartouche installs it on the iPhone from the Mac or from your NAS.
2. **Without a Mac.** On [Cartouche Cloud](/cloud/)'s site, send your copy from any computer: it is built on a Mac in the cloud, for you alone, and Cartouche installs it.
3. **Games built already.** IPAs you built yourself install from your [storage](/iphone/storage/) or from Files.

## iPhone 11 to 15

nxnative needs a graphics chip that reads BC-compressed textures, which the iPhone 15, the iPhone 15 Plus and earlier models do not have. [nxnative-nobc](https://github.com/mianmuhammadse/nxnative-nobc), a separate fork of nxnative by mianmuhammadse, converts those textures for such an iPhone. Cartouche for Mac builds from it by itself when one of your paired iPhones needs it ([Build for](/mac/builder/#build-for-each-of-your-iphones)), and a game's sheet says when its build converts them.

:::tip
Not sure your iPhone has what a game needs? Every game's sheet checks it for you: memory, iOS version and chip. See [A game's sheet](/iphone/game-sheet/).
:::

## Next

[Install Cartouche](/start/install/) from a computer, or [from your own SideStore](/start/sidestore/).
