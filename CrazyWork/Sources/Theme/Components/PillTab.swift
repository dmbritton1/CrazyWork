import SwiftUI

struct PillTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).typography(Typography.bodySm)
                .foregroundStyle(isActive ? Palette.onDark : Palette.body)
                .padding(.vertical, Spacing.xs).padding(.horizontal, Spacing.md)
                .background(isActive ? Palette.surfaceElevated : .clear)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}
