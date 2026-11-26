---
title: Lo que necesitas
description: El iPhone, iPad o Mac en el que funciona Cartouche, la cuenta de Apple con la que se firma y tus propios juegos.
sidebar:
  order: 1
---

Cartouche ejecuta los juegos que [nxnative](https://github.com/seedds/nxnative) hace nativos para iPhone, iPad y Mac. Tú pones tus propias copias; Cartouche hace el resto.

| | |
| --- | --- |
| **iPhone** | iOS 26 o posterior, en un iPhone 15 Pro o posterior. Un iPhone 11 a 15 juega los juegos que Cartouche para Mac y Cartouche Cloud compilan con nxnative-nobc ([más abajo](#iphone-11-a-15)). Los juegos más grandes necesitan un iPhone de 12 GB. |
| **iPad** | iPadOS 26 o posterior, en un iPad con chip M1 o posterior. |
| **Mac** | Un Mac con Apple silicon y macOS 26.6 o posterior, para compilar tus juegos y jugarlos allí. Sin Mac, [Cartouche Cloud](/es/cloud/) los compila por ti. |
| **Cuenta de Apple** | Basta con una gratuita, o con un certificado de firma (.p12) propio. |
| **Ordenador** | Un Mac o un PC con Windows, una vez, para instalar Cartouche, o ninguno si ya usas [SideStore](/es/start/sidestore/). |
| **Tus juegos** | Tus propias copias, extraídas de tu consola. |

## Tres caminos hacia tus juegos

1. **Con un Mac.** [Cartouche para Mac](/es/mac/install/) compila cada juego a partir de tu copia, para el iPhone, el iPad y el Mac, y lo vuelve a compilar cuando nxnative lo mejora. Cartouche lo instala en el iPhone desde el Mac o desde tu NAS.
2. **Sin Mac.** En el sitio de [Cartouche Cloud](/es/cloud/), envía tu copia desde cualquier ordenador: se compila en un Mac en la nube, solo para ti, y Cartouche lo instala.
3. **Juegos ya compilados.** Las IPA que compilaste tú mismo se instalan desde tu [almacenamiento](/es/iphone/storage/) o desde Archivos.

## iPhone 11 a 15

nxnative necesita un chip gráfico que lea texturas comprimidas en BC, que el iPhone 15, el iPhone 15 Plus y los modelos anteriores no tienen. [nxnative-nobc](https://github.com/mianmuhammadse/nxnative-nobc), una bifurcación distinta de nxnative de mianmuhammadse, convierte esas texturas para un iPhone así. Cartouche para Mac compila con ella por sí solo cuando uno de tus iPhone emparejados lo necesita ([Compilar para](/es/mac/builder/#compilar-para-cada-uno-de-tus-iphone)), y la ficha de un juego dice cuándo su compilación las convierte. Cartouche Cloud compila con ella un juego que envías para un iPhone 11 a 15 ([Compilar un juego](/es/cloud/#compilar-un-juego)).

:::tip
¿No sabes si tu iPhone tiene lo que necesita un juego? La ficha de cada juego lo comprueba por ti: memoria, versión de iOS y chip. Mira [La ficha de un juego](/es/iphone/game-sheet/).
:::

## Siguiente

[Instala Cartouche](/es/start/install/) desde un ordenador, o [desde tu propio SideStore](/es/start/sidestore/).
