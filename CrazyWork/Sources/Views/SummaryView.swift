import SwiftUI

struct SummaryView: View {
    let results: [SessionCoordinator.SetResult]

    var body: some View {
        VStack(spacing: 16) {
            Text("Workout Complete").font(.largeTitle).foregroundStyle(.white)
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                VStack {
                    Text("\(r.exerciseID): \(r.completedReps)/\(r.targetReps) reps").foregroundStyle(.white)
                    Text("Form \(Int(r.averageFormScore * 100))%").foregroundStyle(.secondary)
                }
            }
            NavigationLink("Done") { BuildWorkoutView() }.buttonStyle(.borderedProminent)
        }
    }
}
