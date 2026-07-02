import SwiftUI

struct Badge: View {
    enum Style { case pro, redSoft, aquaSoft, infoSoft, greenSoft }
    let text: String
    var style: Style = .pro

    private var colors: (Color, Color) {
        switch style {
        case .pro:      return (Palette.surfaceElevated, Palette.mute)
        case .redSoft:  return (Palette.brandRedSoft, Palette.accentRedBright)
        case .aquaSoft: return (Palette.accentAquaSoft, Palette.accentAquaBright)
        case .infoSoft: return (Palette.accentBlueSoft, Palette.accentBlue)
        case .greenSoft: return (Palette.accentGreenSoft, Palette.accentGreen)
        }
    }

    var body: some View {
        Text(text).typography(Typography.captionSm).foregroundStyle(colors.1)
            .padding(.vertical, Spacing.xxs).padding(.horizontal, Spacing.sm)
            .background(colors.0).clipShape(RoundedRectangle(cornerRadius: Radii.xs))
    }
}
