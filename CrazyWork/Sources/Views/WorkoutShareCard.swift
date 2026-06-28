import SwiftUI
import ChallengeCore

/// A compact, fixed-width card rendered to an image for sharing — not shown
/// inline in the app.
struct WorkoutShareCard: View {
    let date: Date
    let exercises: String      // "Push-up · Squat · Plank"
    let totalReps: Int
    let totalHoldSeconds: Double
    let averageFormPct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CrazyWork").font(.headline.bold())
                Spacer()
                Text(date, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(exercises).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                stat("\(totalReps)", "reps")
                stat(LiveWorkoutView.clock(totalHoldSeconds), "held")
                stat("\(averageFormPct)%", "form")
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
