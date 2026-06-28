import SwiftUI

struct ExerciseTile: View {
    let exerciseID: String
    var size: CGFloat = 48
    var body: some View {
        RoundedRectangle(cornerRadius: Radii.md).fill(Palette.surfaceCard)
            .frame(width: size, height: size)
            .overlay(Image(systemName: Self.symbol(for: exerciseID))
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(Palette.body))
    }
    static func symbol(for id: String) -> String {
        switch id {
        case "pushup":      return "figure.strengthtraining.functional"
        case "squat":       return "figure.strengthtraining.traditional" // barbell squat stance
        case "lunge":       return "figure.step.training"                // stepping/lunge motion
        case "plank":       return "figure.core.training"                // prone hold
        case "situp":       return "figure.cooldown"                     // floor crunch (distinct from plank)
        case "glutebridge": return "figure.pilates"                      // supine mat/hip work
        default:            return "figure.strengthtraining.traditional"
        }
    }
}
