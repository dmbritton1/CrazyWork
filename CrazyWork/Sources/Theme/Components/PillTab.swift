import SwiftUI

struct PillTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).typography(Typography.bodySm)
                .foregroundStyle(isActive ? Palette.accentRedBright : Palette.body)
                .padding(.vertical, Spacing.xs).padding(.horizontal, Spacing.md)
                .background(isActive ? Palette.brandRedSoft : .clear)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}
