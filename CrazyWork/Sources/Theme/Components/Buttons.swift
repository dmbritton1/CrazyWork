import SwiftUI

@MainActor
private func pill<C: View>(_ c: C, bg: Color, fg: Color) -> some View {
    c.typography(Typography.buttonMd).foregroundStyle(fg)
        .padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.lg)
        .frame(minHeight: 36).background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radii.md))
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.primaryPressed : Palette.primary, fg: Palette.onPrimary)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: .clear, fg: Palette.onDark).opacity(c.isPressed ? 0.6 : 1)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: Palette.surfaceElevated, fg: Palette.onDark).opacity(c.isPressed ? 0.85 : 1)
    }
}

struct SecondaryRedButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.brandRed.opacity(0.22) : Palette.brandRedSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentRedBright)
    }
}

struct SecondaryAquaButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.accentAqua.opacity(0.22) : Palette.accentAquaSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentAquaBright)
    }
}
