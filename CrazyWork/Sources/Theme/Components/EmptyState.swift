import SwiftUI

/// Branded empty state: an icon in a surface tile, a heading, and one line
/// pointing at the action that fills the screen — replaces the system-grey
/// `ContentUnavailableView` so first-run screens stay on-brand.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: Radii.md)
                .fill(Palette.surfaceCard)
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: Radii.md).stroke(Palette.hairline, lineWidth: 1))
                .overlay(Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.mute))
            VStack(spacing: Spacing.xs) {
                Text(title).typography(Typography.headingSm).foregroundStyle(Palette.ink)
                Text(message).typography(Typography.bodySm).foregroundStyle(Palette.mute)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.horizontal, Spacing.xl)
    }
}
