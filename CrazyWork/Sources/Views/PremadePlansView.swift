import SwiftUI
import ChallengeCore
import SwiftData

/// The Plans tab: curated workouts shown as cards (name, estimated time,
/// description, exercise summary). The + button opens the builder for a new
/// workout; choosing a card opens the builder pre-loaded with that plan.
struct PremadePlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWorkout.createdAt, order: .reverse) private var saved: [SavedWorkout]
    @State private var draftEntries: [WorkoutEntry] = []
    @State private var draftRest = 30
    @State private var showingBuilder = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HeroStripeBand {
                            HStack {
                                Text("Plans").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                                Spacer()
                                Button(action: newWorkout) {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                }
                                .accessibilityLabel("Build a workout")
                            }
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
            .sheet(isPresented: $showingBuilder) {
                BuildWorkoutView(entries: $draftEntries, restSeconds: $draftRest)
            }
        }
    }

    private func newWorkout() {
        draftEntries = []
        draftRest = 30
        showingBuilder = true
    }

    private func choose(_ plan: PremadePlan) {
        draftEntries = plan.entries
        draftRest = plan.restSeconds
        showingBuilder = true
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
            .padding(.top, Spacing.sm)
    }

    private func planCard(_ plan: PremadePlan, onDelete: (() -> Void)?) -> some View {
        Button { choose(plan) } label: { card(plan, onDelete: onDelete) }
            .buttonStyle(PressableButtonStyle())
    }

    private func card(_ plan: PremadePlan, onDelete: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
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
            HStack(spacing: Spacing.sm) {
                ForEach(exerciseIDs(plan), id: \.self) { id in
                    ExerciseTile(exerciseID: id, size: 32)
                }
                Text(setsText(plan)).typography(Typography.captionMd).foregroundStyle(Palette.stone)
                    .padding(.leading, Spacing.xs)
            }
        }
        .card()
    }

    private func timeText(_ plan: PremadePlan) -> String {
        let minutes = max(1, Int((Double(plan.estimatedSeconds()) / 60).rounded()))
        return "~\(minutes) min"
    }

    private func exerciseIDs(_ plan: PremadePlan) -> [String] {
        var seen = Set<String>()
        return plan.entries.compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
    }

    private func setsText(_ plan: PremadePlan) -> String {
        let sets = plan.entries.reduce(0) { $0 + $1.sets }
        return "\(sets) sets · \(plan.restSeconds)s rest"
    }
}
