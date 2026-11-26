---
title: Was du brauchst
description: Das iPhone, iPad oder der Mac, auf dem Cartouche läuft, der Apple Account, mit dem es signiert, und deine eigenen Spiele.
sidebar:
  order: 1
---

Cartouche führt die Spiele aus, die [nxnative](https://github.com/seedds/nxnative) für iPhone, iPad und Mac nativ macht. Du bringst deine eigenen Kopien mit; Cartouche erledigt den Rest.

| | |
| --- | --- |
| **iPhone** | iOS 26 oder neuer, auf einem iPhone 15 Pro oder neuer. Ein iPhone 11 bis 15 spielt die Spiele, die Cartouche für Mac und Cartouche Cloud mit nxnative-nobc erstellen ([weiter unten](#iphone-11-bis-15)). Die größten Spiele brauchen ein iPhone mit 12 GB. |
| **iPad** | iPadOS 26 oder neuer, auf einem iPad mit M1-Chip oder neuer. |
| **Mac** | Ein Mac mit Apple silicon und macOS 26.6 oder neuer, um deine Spiele zu erstellen und dort zu spielen. Ohne Mac erstellt [Cartouche Cloud](/de/cloud/) sie für dich. |
| **Apple Account** | Ein kostenloser genügt, oder ein eigenes Signaturzertifikat (.p12). |
| **Computer** | Ein Mac oder ein Windows-PC, einmal, um Cartouche zu installieren, oder keiner, wenn du schon [SideStore](/de/start/sidestore/) nutzt. |
| **Deine Spiele** | Deine eigenen Kopien, von deiner Konsole gedumpt. |

## Drei Wege zu deinen Spielen

1. **Mit einem Mac.** [Cartouche für Mac](/de/mac/install/) erstellt jedes Spiel aus deiner Kopie, für iPhone, iPad und Mac, und erstellt es neu, wenn nxnative es verbessert. Cartouche installiert es vom Mac oder von deinem NAS aus auf dem iPhone.
2. **Ohne Mac.** Sende deine Kopie auf der Website von [Cartouche Cloud](/de/cloud/) von einem beliebigen Computer aus: Sie wird auf einem Mac in der Cloud erstellt, nur für dich, und Cartouche installiert sie.
3. **Schon erstellte Spiele.** IPAs, die du selbst erstellt hast, werden aus deinem [Speicher](/de/iphone/storage/) oder aus „Dateien“ installiert.

## iPhone 11 bis 15

nxnative braucht einen Grafikchip, der BC-komprimierte Texturen liest, und den haben das iPhone 15, das iPhone 15 Plus und ältere Modelle nicht. [nxnative-nobc](https://github.com/mianmuhammadse/nxnative-nobc), ein separater Fork von nxnative von mianmuhammadse, wandelt diese Texturen für ein solches iPhone um. Cartouche für Mac erstellt von selbst damit, wenn eines deiner gekoppelten iPhones es braucht ([Erstellen für](/de/mac/builder/#für-jedes-deiner-iphones-erstellen)), und die Infoseite eines Spiels sagt, wann sein Build sie umwandelt. Cartouche Cloud erstellt damit ein Spiel, das du für ein iPhone 11 bis 15 sendest ([Ein Spiel erstellen](/de/cloud/#ein-spiel-erstellen)).

:::tip
Du weißt nicht, ob dein iPhone mitbringt, was ein Spiel braucht? Die Infoseite jedes Spiels prüft es für dich: Arbeitsspeicher, iOS-Version und Chip. Siehe [Die Infoseite eines Spiels](/de/iphone/game-sheet/).
:::

## Weiter

[Installiere Cartouche](/de/start/install/) von einem Computer aus oder [aus deinem eigenen SideStore](/de/start/sidestore/).
