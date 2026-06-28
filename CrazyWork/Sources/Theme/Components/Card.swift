import SwiftUI

struct CardModifier: ViewModifier {
    var surface: Color = Palette.surface
    var radius: CGFloat = Radii.lg
    var padding: CGFloat = Spacing.xl
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func card(surface: Color = Palette.surface, radius: CGFloat = Radii.lg,
              padding: CGFloat = Spacing.xl) -> some View {
        modifier(CardModifier(surface: surface, radius: radius, padding: padding))
    }
}
