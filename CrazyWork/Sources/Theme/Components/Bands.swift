import SwiftUI

/// Three diagonal red stripes — the signature hero moment (once per page).
struct HeroStripeBand<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xxl).padding(.horizontal, Spacing.xl)
            .background(alignment: .top) {
                LinearGradient(colors: [Palette.heroStripeStart, Palette.heroStripeMid, Palette.heroStripeEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.9).frame(height: 120).blur(radius: 28)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Palette.canvas)
    }
}

/// Single teal wash — the cool secondary moment (once per page).
struct AquaGlowBand<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xxl).padding(.horizontal, Spacing.xl)
            .background(alignment: .top) {
                LinearGradient(colors: [Palette.aquaGlowStart.opacity(0.8), Palette.aquaGlowEnd],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120).blur(radius: 32)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Palette.canvas)
    }
}
