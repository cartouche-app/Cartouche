//
//  NamingHelp.swift
//  Cartouche Builder
//
//  How to name what the dumps folder, the games folder and the saves folder
//  hold: the console's page (CartoucheMacNaming), which the iPhone shows
//  under its Storage page, in a sheet over the settings' Folders tab, the
//  setup assistant's steps of the dumps and of the games folder, and the
//  library when it found no game or left files aside. This file imports the
//  console, and not CartoucheCore, whose names the console shares
//  (ConsoleWindow.swift).
//

import BuilderKit
import CartoucheConsole
import SwiftUI

/// The page, with its title, and a button that closes it.
struct NamingHelp: View {
    /// Opened on the dumps folder, rather than at its top.
    let onDumps: Bool
    @Environment(\.dismiss) private var dismiss

    static let size = CGSize(width: 560, height: 480)

    // Written out, for the files that open it and the gallery's pages:
    // with the private value above, the synthesized one may be this
    // file's alone.
    init(onDumps: Bool = false) {
        self.onDumps = onDumps
    }

    /// Its title, in the language the console speaks, the app's.
    static var title: String { CartoucheMacNaming.title }

    var body: some View {
        VStack(spacing: 0) {
            Text(NamingHelp.title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            CartoucheMacNaming(opensOnDumps: onDumps)
            Divider()
            HStack {
                Spacer()
                Button(tr("Close", "Fermer", "Cerrar", "Schließen")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: NamingHelp.size.width, height: NamingHelp.size.height)
    }
}

/// A button that opens the page in a sheet.
struct NamingHelpButton: View {
    let title: String
    let onDumps: Bool
    /// A link's look, in a line of text, rather than a button's.
    let link: Bool
    @State private var showing = false

    init(title: String, onDumps: Bool = false, link: Bool = false) {
        self.title = title
        self.onDumps = onDumps
        self.link = link
    }

    var body: some View {
        Group {
            if link {
                Button(title) { showing = true }
                    .buttonStyle(.link)
            } else {
                Button(title) { showing = true }
            }
        }
        .sheet(isPresented: $showing) {
            NamingHelp(onDumps: onDumps)
        }
    }

    /// The words of the button that opens it, at its top, on the games
    /// folder, as Cartouche's under its Storage page.
    static var games: String { tr("How to name your games", "Comment nommer vos jeux", "Cómo nombrar tus juegos", "So benennst du deine Spiele") }
    /// The words of the button that opens it on the dumps folder.
    static var dumps: String { tr("How to name your dumps", "Comment nommer vos dumps", "Cómo nombrar tus dumps", "So benennst du deine Dumps") }
}
