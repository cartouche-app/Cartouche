//
//  CartoucheNamingView.swift
//  Cartouche
//
//  How to name what the games folder, the saves folder and Cartouche
//  Builder's dumps folder hold, from the Storage page: for each place, the
//  names Cartouche or the Builder finds and those they leave aside, with
//  what each makes of them (CartoucheNaming.swift). The Builder's settings,
//  its setup assistant and its library show the same page on the Mac
//  (builder/mac, NamingHelp.swift), in the Mac's own appearance.
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheNamingView: View {
    /// The place the page opens on, when not the first: the dumps folder
    /// from the Builder's dumps, or a place further down in the gallery's
    /// screenshots (launcher/Gallery).
    var opening: CartoucheNaming.Place?
    /// On the console's dark stage, as the iPhone's System pages are; the
    /// Builder shows it in the Mac's appearance.
    var onStage = true

    var body: some View {
        ScrollViewReader { reader in
            Form {
                Section {
                    Text(CartoucheText.namingIntro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(CartoucheNaming.Place.allCases) { place in
                    Section {
                        ForEach(CartoucheNaming.examples(in: place)) { example in
                            CartoucheNamingRow(example: example)
                                .id(example.id)
                        }
                    } header: {
                        Label(CartoucheText.namingPlace(place), systemImage: Self.symbol(place))
                    } footer: {
                        Text(CartoucheText.namingFooter(place))
                    }
                }
            }
            .formStyle(.grouped)
            .modifier(CartoucheNamingStage(isOn: onStage))
            .navigationTitle(CartoucheText.namingTitle)
            .task {
                guard let opening, let first = CartoucheNaming.examples(in: opening).first else { return }
                // Once the form has laid out its rows; the place's header
                // shows above its first one.
                try? await Task.sleep(for: .milliseconds(500))
                reader.scrollTo(first.id, anchor: UnitPoint(x: 0.5, y: 0.15))
            }
        }
    }

    static func symbol(_ place: CartoucheNaming.Place) -> String {
        switch place {
        case .games: return "square.stack.3d.up.fill"
        case .saves: return "clock.arrow.circlepath"
        case .dumps: return "desktopcomputer"
        }
    }
}

/// An example: its folders, each a line further in, then its own name, as
/// the Finder or Files lists them; whether its place finds it or leaves it
/// aside, and why.
@available(iOS 17.0, *)
struct CartoucheNamingRow: View {
    let example: CartoucheNaming.Example

    /// How much further in each folder's content is.
    private static let indent: CGFloat = 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: example.isFound ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(example.isFound ? Color.green : Color.orange)
                .accessibilityLabel(example.isFound ? CartoucheText.namingFound : CartoucheText.namingLeftAside)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(example.folders.enumerated()), id: \.offset) { level, folder in
                    Text(verbatim: folder + "/")
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(level) * Self.indent)
                }
                Text(verbatim: example.isFolder ? example.name + "/" : example.name)
                    .foregroundStyle(example.isFound ? .primary : .secondary)
                    .padding(.leading, CGFloat(example.folders.count) * Self.indent)
                Text(CartoucheText.namingWhy(example.meaning))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .font(.system(.footnote, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("naming." + example.place.rawValue + "." + example.meaning.rawValue)
    }
}

/// The console's stage behind the page, or the system's background.
@available(iOS 17.0, *)
private struct CartoucheNamingStage: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.cartoucheStageBackground()
        } else {
            content
        }
    }
}
