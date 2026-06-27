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
        VStack(spacing: 12) {
            Text("Rest").font(.largeTitle.bold()).foregroundStyle(.white)
            Text(LiveWorkoutView.clock(Double(remaining)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("Next: \(nextExercise)").foregroundStyle(.white.opacity(0.8))
            Button("Skip rest") { onAdvance() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
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
