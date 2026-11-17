//
//  CartoucheGuideCard.swift
//  Cartouche
//
//  The first game's guide as a card at the top of the home, over the
//  shelf: the step left, and a tap to the guide (CartoucheGuideView). The
//  console on the Mac shows the same card, of its own guide, the Mac's
//  steps to a first game played there (builder/mac, ConsoleGuide.swift).
//

import SwiftUI

/// The guide at the top of the home, in place of the setup banner, until
/// the player's first game is installed: the step left, and a tap to the
/// guide. Its × takes it off the home for good, for a player who needs no
/// guide; the System page opens the guide then.
@available(iOS 17.0, *)
struct CartoucheGuideCard: View {
    let progress: CartoucheGuide.Progress
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: "flag.checkered")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CartoucheText.guideTitle)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { CartoucheGuide.shared.hideCard() }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.2), in: Circle())
                    // As tall as the flag, so that the card keeps its height.
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CartoucheText.guideHide)
        }
        .foregroundStyle(Color.white)
        .padding(14)
        .background(
            LinearGradient(colors: [CartoucheTheme.indigo, CartoucheTheme.pink.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var detail: String {
        guard let step = progress.current else { return CartoucheText.guideFinishedTitle }
        return CartoucheText.guideCardDetail(progress.number(of: step), progress.steps.count,
                                             CartoucheGuideView.title(step))
    }
}
