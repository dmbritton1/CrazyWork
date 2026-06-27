import SwiftUI
import ChallengeCore

struct SummaryView: View {
    let results: [SessionCoordinator.SetResult]

    var body: some View {
        VStack(spacing: 16) {
            Text("Workout Complete").font(.largeTitle).foregroundStyle(.white)
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                VStack {
                    Text("\(displayName(r.exerciseID)): \(achieved(r))").foregroundStyle(.white)
                    Text("Form \(Int(r.averageFormScore * 100))%").foregroundStyle(.secondary)
                }
            }
            NavigationLink("Done") { BuildWorkoutView() }.buttonStyle(.borderedProminent)
        }
    }

    private func achieved(_ r: SessionCoordinator.SetResult) -> String {
        switch r.goalUnit {
        case .reps:
            return "\(Int(r.completed)) / \(r.target) reps"
        case .seconds:
            return "\(LiveWorkoutView.clock(r.completed)) / \(LiveWorkoutView.clock(Double(r.target)))"
        }
    }

    private func displayName(_ id: String) -> String {
        ExerciseRegistry.all.first { $0.id == id }?.displayName ?? id
    }
}
