---
title: Ce qu'il faut
description: L'iPhone, l'iPad ou le Mac sur lequel tourne Cartouche, le compte Apple avec lequel il se signe, et vos propres jeux.
sidebar:
  order: 1
---

Cartouche fait tourner les jeux que [nxnative](https://github.com/seedds/nxnative) rend natifs sur iPhone, iPad et Mac. Vous apportez vos propres copies ; Cartouche fait le reste.

| | |
| --- | --- |
| **iPhone** | iOS 26 ou plus récent, sur un iPhone 15 Pro ou plus récent. Un iPhone 11 à 15 joue aux jeux que Cartouche pour Mac construit avec nxnative-nobc ([plus bas](#iphone-11-à-15)). Les plus gros jeux demandent un iPhone de 12 Go. |
| **iPad** | iPadOS 26 ou plus récent, sur un iPad avec une puce M1 ou plus récente. |
| **Mac** | Un Mac avec une puce Apple et macOS 26.6 ou plus récent, pour construire vos jeux et y jouer. Sans Mac, [Cartouche Cloud](/fr/cloud/) les construit pour vous. |
| **Compte Apple** | Un compte gratuit suffit, ou votre propre certificat de signature (.p12). |
| **Ordinateur** | Un Mac ou un PC Windows, une fois, pour installer Cartouche, ou aucun si vous utilisez déjà [SideStore](/fr/start/sidestore/). |
| **Vos jeux** | Vos propres copies, tirées de votre console. |

## Trois chemins vers vos jeux

1. **Avec un Mac.** [Cartouche pour Mac](/fr/mac/install/) construit chaque jeu à partir de votre copie, pour l'iPhone, l'iPad et le Mac, et le reconstruit quand nxnative l'améliore. Cartouche l'installe sur l'iPhone depuis le Mac ou depuis votre NAS.
2. **Sans Mac.** Sur le site de [Cartouche Cloud](/fr/cloud/), envoyez votre copie depuis n'importe quel ordinateur : elle est construite sur un Mac dans le cloud, pour vous seul, et Cartouche l'installe.
3. **Des jeux déjà construits.** Les IPA que vous avez construites vous-même s'installent depuis votre [stockage](/fr/iphone/storage/) ou depuis Fichiers.

## iPhone 11 à 15

nxnative demande une puce graphique qui lit les textures compressées en BC, ce que n'ont pas l'iPhone 15, l'iPhone 15 Plus et les modèles plus anciens. [nxnative-nobc](https://github.com/mianmuhammadse/nxnative-nobc), une fourche distincte de nxnative par mianmuhammadse, convertit ces textures pour un tel iPhone. Cartouche pour Mac construit à partir d'elle tout seul quand l'un de vos iPhone associés en a besoin ([Construire pour](/fr/mac/builder/#construire-pour-chacun-de-vos-iphone)), et la fiche d'un jeu dit quand sa construction les convertit.

:::tip
Vous ne savez pas si votre iPhone a ce qu'il faut pour un jeu ? La fiche de chaque jeu le vérifie pour vous : mémoire, version d'iOS et puce. Voir [La fiche d'un jeu](/fr/iphone/game-sheet/).
:::

## Ensuite

[Installez Cartouche](/fr/start/install/) depuis un ordinateur, ou [depuis votre propre SideStore](/fr/start/sidestore/).
