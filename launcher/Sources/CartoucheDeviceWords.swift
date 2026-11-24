//
//  CartoucheDeviceWords.swift
//  Cartouche
//
//  The launcher's words on an iPad (CartoucheText.s). Cartouche.xcstrings
//  calls the device Cartouche runs on the iPhone: this iPhone, your iPhone,
//  the iPhone, cet iPhone, votre iPhone, l’iPhone, ce modèle d’iPhone, este
//  iPhone, tu iPhone, el iPhone, dieses iPhone, deinem iPhone, des iPhones.
//  An iPad calls it the iPad. Any other iPhone stays: a model (an iPhone 15
//  Pro, the iPhone Duo, un iPhone de 12 Go), iPhones in general (another
//  iPhone, which iPhone), where nxnative plays a game (On iPhone, sur
//  iPhone), and the name of Cartouche Builder's setting (Share with
//  Cartouche on the iPhone), which the Mac shows as it is.
//
//  Platform-independent: tested on its own by launcher/Package.swift,
//  against every text of Cartouche.xcstrings.
//

import Foundation

enum CartoucheDeviceWords {
    /// TEXT, in English, French, Spanish or German, as an iPad shows it.
    static func onIPad(_ text: String) -> String {
        guard text.contains("iPhone") else { return text }
        return rules.reduce(text) { text, rule in
            rule.expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                     withTemplate: rule.template)
        }
    }

    /// Each expression, with what takes the place of what it finds.
    private static let rules: [(expression: NSRegularExpression, template: String)] = [
        // English: this, your or the iPhone, but where nxnative plays a game
        // and in the name of Cartouche Builder's setting.
        (expression(#"(?<!plays it on )(?<!with Cartouche on )\b(this|This|your|Your|the|The)([  ])iPhone\b"# + notAModel),
         "$1$2iPad"),
        // The game's language: iPhone language.
        (expression(#"\biPhone(?= language\b)"#), "iPad"),
        // French: cet, votre or l’iPhone, but in the name of Cartouche
        // Builder's setting; ce modèle d’iPhone.
        (expression(#"\b(cet|Cet|votre|Votre)([  ])iPhone\b"# + notAModel), "$1$2iPad"),
        (expression(#"(?<!avec Cartouche sur )\b([lL][’'])iPhone\b"# + notAModel), "$1iPad"),
        (expression(#"\b([cC]e modèle d[’'])iPhone\b"#), "$1iPad"),
        // Spanish: este, tu or el iPhone (del, al), but in the name of
        // Cartouche Builder's setting; este modelo de iPhone.
        (expression(#"(?<!con Cartouche en )\b(este|Este|tu|Tu|el|El|del|Del|al|Al)([  ])iPhone\b"# + notAModel),
         "$1$2iPad"),
        (expression(#"\b([eE]ste modelo de )iPhone\b"#), "$1iPad"),
        // German: dieses, dein or das iPhone, in every case, but in the name
        // of Cartouche Builder's setting; des iPhones; des iPhone-Bildschirms.
        (expression(#"(?<![Mm]it Cartouche auf )\b(dieses|Dieses|diesem|Diesem|dein|Dein|deinem|Deinem|das|Das|dem|Dem|am|Am|vom|Vom|zum|Zum|im|Im)([  ])iPhone\b"# + notAModel),
         "$1$2iPad"),
        (expression(#"\b(des|Des|deines|Deines|dieses|Dieses)([  ])iPhones\b"#), "$1$2iPads"),
        (expression(#"\b(des|Des|deines|Deines|dieses|Dieses)([  ])iPhone-"#), "$1$2iPad-"),
    ]

    /// Not a model of iPhone: neither its number (iPhone 15 Pro) nor Duo.
    private static let notAModel = #"(?![  ]?(?:[0-9]|Duo\b))"#

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants: one that does not compile fails every test.
        try! NSRegularExpression(pattern: pattern)
    }
}
