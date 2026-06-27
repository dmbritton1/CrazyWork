import SwiftUI
import ChallengeCore

struct BuildWorkoutView: View {
    @State private var plan: [PlannedSet] = []

    /// Default target per goal unit: 10 reps, or a 30-second hold.
    private static func defaultTarget(for unit: GoalUnit) -> Int {
        switch unit {
        case .reps: return 10
        case .seconds: return 30
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(ExerciseRegistry.all, id: \.id) { info in
                        Button("Add \(info.displayName) — \(targetLabel(info.goalUnit, Self.defaultTarget(for: info.goalUnit)))") {
                            plan.append(PlannedSet(exerciseID: info.id,
                                                   target: Self.defaultTarget(for: info.goalUnit)))
                        }
                    }
                }
                Section("Your workout") {
                    if plan.isEmpty { Text("No sets yet").foregroundStyle(.secondary) }
                    ForEach(plan) { set in
                        Text("\(displayName(set.exerciseID)) — \(targetLabel(unit(set.exerciseID), set.target))")
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

    private func targetLabel(_ unit: GoalUnit, _ target: Int) -> String {
        switch unit {
        case .reps: return "×\(target)"
        case .seconds: return "\(target)s"
        }
    }

    private func unit(_ id: String) -> GoalUnit {
        ExerciseRegistry.all.first { $0.id == id }?.goalUnit ?? .reps
    }

    private func displayName(_ id: String) -> String {
        ExerciseRegistry.all.first { $0.id == id }?.displayName ?? id
    }
}
