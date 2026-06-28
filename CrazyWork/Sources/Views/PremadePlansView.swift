import SwiftUI
import ChallengeCore
import SwiftData

/// The Plans tab: curated workouts shown as cards (name, estimated time,
/// description, exercise summary). Choosing one hands the plan back via
/// `onChoose` — `RootView` loads it into the builder and switches tabs.
struct PremadePlansView: View {
    let onChoose: (PremadePlan) -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWorkout.createdAt, order: .reverse) private var saved: [SavedWorkout]

    var body: some View {
        NavigationStack {
            List {
                if !saved.isEmpty {
                    Section("My Workouts") {
                        ForEach(saved) { workout in
                            Button { onChoose(workout.asPlan) } label: { card(workout.asPlan) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(saved[i]) }
                        }
                    }
                }
                Section("Plans") {
                    ForEach(PremadePlanCatalog.all) { plan in
                        Button { onChoose(plan) } label: { card(plan) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Plans")
        }
    }

    private func card(_ plan: PremadePlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.name).font(.headline)
                Spacer()
                Label(timeText(plan), systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(plan.summary).font(.subheadline).foregroundStyle(.secondary)
            Text(exerciseSummary(plan)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func timeText(_ plan: PremadePlan) -> String {
        let minutes = max(1, Int((Double(plan.estimatedSeconds()) / 60).rounded()))
        return "~\(minutes) min"
    }

    private func exerciseSummary(_ plan: PremadePlan) -> String {
        plan.entries
            .map { entry in ExerciseRegistry.displayName(for: entry.exerciseID) }
            .joined(separator: " · ")
    }
}
