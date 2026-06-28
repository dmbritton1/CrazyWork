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
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HeroStripeBand {
                            Text("Plans").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                        }
                        LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                            if !saved.isEmpty {
                                sectionHeader("MY WORKOUTS")
                                ForEach(saved) { workout in
                                    planCard(workout.asPlan, onDelete: { modelContext.delete(workout) })
                                }
                            }
                            sectionHeader("PLANS")
                            ForEach(PremadePlanCatalog.all) { plan in
                                planCard(plan, onDelete: nil)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.bottom, Spacing.lg)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
            .padding(.top, Spacing.sm)
    }

    private func planCard(_ plan: PremadePlan, onDelete: (() -> Void)?) -> some View {
        Button { onChoose(plan) } label: { card(plan, onDelete: onDelete) }
            .buttonStyle(.plain)
    }

    private func card(_ plan: PremadePlan, onDelete: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                Text(plan.name).typography(Typography.headingSm).foregroundStyle(Palette.ink)
                Spacer()
                Badge(text: timeText(plan), style: .aquaSoft)
                if let onDelete {
                    Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(Palette.mute) }
                        .buttonStyle(.plain)
                        .padding(.leading, Spacing.xs)
                }
            }
            Text(plan.summary).typography(Typography.bodySm).foregroundStyle(Palette.mute)
            Text(exerciseSummary(plan)).typography(Typography.captionMd).foregroundStyle(Palette.stone)
        }
        .card()
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
