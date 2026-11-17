//
//  ConsoleNaming.swift
//  Cartouche on the Mac
//
//  How to name what the dumps folder, the games folder and the saves folder
//  hold: the iPhone's page, under its Storage page (CartoucheNamingView.swift),
//  for the builder's settings, its setup assistant and its library
//  (NamingHelp.swift in CartoucheBuilder). It shows in the Mac's appearance,
//  as the builder's pages around it, not on the console's stage.
//

import SwiftUI

public struct CartoucheMacNaming: View {
    private let opensOnDumps: Bool

    /// OPENSONDUMPS: opened on the dumps folder, for the builder's dumps.
    public init(opensOnDumps: Bool = false) {
        self.opensOnDumps = opensOnDumps
    }

    /// The page's title, in the language the console speaks.
    public static var title: String { CartoucheText.namingTitle }

    public var body: some View {
        CartoucheNamingView(opening: opensOnDumps ? .dumps : nil, onStage: false)
    }
}
