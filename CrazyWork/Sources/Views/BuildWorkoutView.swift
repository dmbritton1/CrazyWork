import SwiftUI
import ChallengeCore

struct BuildWorkoutView: View {
    @State private var plan: [PlannedSet] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(ExerciseRegistry.all, id: \.id) { info in
                        Button("Add 1 set of \(info.displayName) (×10)") {
                            plan.append(PlannedSet(exerciseID: info.id, targetReps: 10))
                        }
                    }
                }
                Section("Your workout") {
                    if plan.isEmpty { Text("No sets yet").foregroundStyle(.secondary) }
                    ForEach(plan) { set in
                        Text("\(displayName(set.exerciseID)) — \(set.targetReps) reps")
                    }
                    .onDelete { plan.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Build Workout")
            .toolbar {
                NavigationLink("History") { HistoryView() }
            }
            .safeAreaInset(edge: .bottom) {
                NavigationLink("Start Workout") { LiveWorkoutView(plan: plan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.isEmpty)
                    .padding()
            }
        }
    }

    private func displayName(_ id: String) -> String {
        ExerciseRegistry.all.first { $0.id == id }?.displayName ?? id
    }
}
