import SwiftUI
import ChallengeCore

struct BuildWorkoutView: View {
    @Binding var entries: [WorkoutEntry]
    @Binding var restSeconds: Int

    private static func defaultTarget(for unit: GoalUnit) -> Int {
        switch unit {
        case .reps: return 10
        case .seconds: return 30
        }
    }

    private var plannedSetCount: Int { WorkoutPlan.expand(entries).count }

    var body: some View {
        NavigationStack {
            List {
                Section("Add exercise") {
                    ForEach(ExerciseRegistry.all, id: \.id) { info in
                        Button {
                            entries.append(WorkoutEntry(exerciseID: info.id, sets: 3,
                                                        target: Self.defaultTarget(for: info.goalUnit)))
                        } label: {
                            Label(info.displayName, systemImage: "plus.circle.fill")
                        }
                    }
                }
                Section("Your workout") {
                    if entries.isEmpty {
                        Text("No exercises yet").foregroundStyle(.secondary)
                    }
                    ForEach($entries) { $entry in
                        EntryRow(entry: $entry,
                                 unit: unit(entry.exerciseID),
                                 name: displayName(entry.exerciseID))
                    }
                    .onDelete { entries.remove(atOffsets: $0) }
                }
                Section("Rest between sets") {
                    Stepper("Rest: \(restSeconds)s", value: $restSeconds, in: 0...180, step: 5)
                }
            }
            .navigationTitle("Build Workout")
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(entries))
                } label: {
                    Text(entries.isEmpty ? "Start Workout" : "Start Workout · \(plannedSetCount) sets")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(entries.isEmpty)
                .padding()
            }
        }
    }

    private func unit(_ id: String) -> GoalUnit {
        ExerciseRegistry.all.first { $0.id == id }?.goalUnit ?? .reps
    }

    private func displayName(_ id: String) -> String {
        ExerciseRegistry.all.first { $0.id == id }?.displayName ?? id
    }
}

/// One editable workout entry: exercise name + sets and per-set target steppers.
private struct EntryRow: View {
    @Binding var entry: WorkoutEntry
    let unit: GoalUnit
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            Stepper("Sets: \(entry.sets)", value: $entry.sets, in: 1...10)
            switch unit {
            case .reps:
                Stepper("Reps: \(entry.target)", value: $entry.target, in: 1...50)
            case .seconds:
                Stepper("Hold: \(entry.target)s", value: $entry.target, in: 5...300, step: 5)
            }
        }
        .padding(.vertical, 4)
    }
}
