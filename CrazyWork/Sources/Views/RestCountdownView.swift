import SwiftUI

/// The rest period between sets: a self-driving countdown that advances to the
/// next set at zero, with a button to skip the remaining wait. `onAdvance` is
/// the coordinator's `beginNextSet` (idempotent — only acts while resting), so a
/// skip-and-timeout race is harmless.
struct RestCountdownView: View {
    let seconds: Int
    let nextExercise: String
    let onAdvance: () -> Void

    @State private var remaining: Int

    init(seconds: Int, nextExercise: String, onAdvance: @escaping () -> Void) {
        self.seconds = seconds
        self.nextExercise = nextExercise
        self.onAdvance = onAdvance
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Rest").typography(Typography.headingLg).foregroundStyle(.white)
            Text(LiveWorkoutView.clock(Double(remaining)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            HStack(spacing: Spacing.sm) {
                Text("Next").typography(Typography.bodySm).foregroundStyle(.white.opacity(0.7))
                Text(nextExercise).typography(Typography.bodyStrong).foregroundStyle(Palette.accentAquaBright)
            }
            Button("Skip rest") { onAdvance() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Spacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radii.xl))
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            onAdvance()
        }
    }
}
