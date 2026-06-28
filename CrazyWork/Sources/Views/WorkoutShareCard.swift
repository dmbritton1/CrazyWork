import SwiftUI
import ChallengeCore

/// A compact, fixed-width card rendered to an image for sharing — not shown
/// inline in the app. Always rendered in the branded dark look (the caller forces
/// `.colorScheme = .dark`).
struct WorkoutShareCard: View {
    let date: Date
    let exercises: String      // "Push-up · Squat · Plank"
    let totalReps: Int
    let totalHoldSeconds: Double
    let averageFormPct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("CrazyWork").typography(Typography.headingSm).foregroundStyle(Palette.ink)
                Spacer()
                Text(date, format: .dateTime.month().day().year())
                    .typography(Typography.captionMd).foregroundStyle(Palette.mute)
            }
            Text(exercises).typography(Typography.bodySm).foregroundStyle(Palette.mute)
            HStack(spacing: Spacing.xl) {
                stat("\(totalReps)", "reps")
                stat(LiveWorkoutView.clock(totalHoldSeconds), "held")
                stat("\(averageFormPct)%", "form")
            }
        }
        .padding(Spacing.xl)
        .frame(width: 340, alignment: .leading)
        .background(Palette.surface)
        .overlay(RoundedRectangle(cornerRadius: Radii.xl).stroke(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radii.xl))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).typography(Typography.headingXl).foregroundStyle(Palette.brandRed)
            Text(label).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
    }
}
