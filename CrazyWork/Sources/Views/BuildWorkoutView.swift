import SwiftUI
import ChallengeCore

struct BuildWorkoutView: View {
    @Binding var entries: [WorkoutEntry]
    @Binding var restSeconds: Int
    @Environment(\.modelContext) private var modelContext
    @State private var showingSavePrompt = false
    @State private var newName = ""

    private static func defaultTarget(for unit: GoalUnit) -> Int {
        switch unit {
        case .reps: return 10
        case .seconds: return 30
        }
    }

    private var plannedSetCount: Int { WorkoutPlan.expand(entries).count }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        HeroStripeBand {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Build").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                                Text("Compose your session").typography(Typography.bodyMd)
                                    .foregroundStyle(Palette.mute)
                            }
                        }

                        addExerciseSection
                        yourWorkoutSection
                        restSection
                        Button("Save workout") { showingSavePrompt = true }
                            .buttonStyle(TertiaryButtonStyle())
                            .disabled(entries.isEmpty)
                            .opacity(entries.isEmpty ? 0.5 : 1)
                            .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Save workout", isPresented: $showingSavePrompt) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Save") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    modelContext.insert(SavedWorkout(name: name, restSeconds: restSeconds, entries: entries))
                    newName = ""
                }
            } message: {
                Text("Save this workout to load again later.")
            }
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(entries), restSeconds: restSeconds)
                } label: {
                    Text(entries.isEmpty ? "Start Workout" : "Start Workout · \(plannedSetCount) sets")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(entries.isEmpty)
                .opacity(entries.isEmpty ? 0.5 : 1)
                .padding(Spacing.lg)
                .background(Palette.canvas)
            }
        }
    }

    private var addExerciseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ADD EXERCISE").typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
                .padding(.horizontal, Spacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(ExerciseRegistry.all, id: \.id) { info in
                        Button {
                            entries.append(WorkoutEntry(exerciseID: info.id, sets: 3,
                                                        target: Self.defaultTarget(for: info.goalUnit)))
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                ExerciseTile(exerciseID: info.id, size: 56)
                                Text(info.displayName).typography(Typography.captionMd)
                                    .foregroundStyle(Palette.body)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    private var yourWorkoutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("YOUR WORKOUT").typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
                .padding(.horizontal, Spacing.lg)
            if entries.isEmpty {
                Text("No exercises yet").typography(Typography.bodyMd).foregroundStyle(Palette.mute)
                    .padding(.horizontal, Spacing.lg)
            }
            ForEach($entries) { $entry in
                EntryRow(entry: $entry, unit: unit(entry.exerciseID), name: displayName(entry.exerciseID)) {
                    entries.removeAll { $0.id == entry.id }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Rest between sets").typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                Spacer()
                Stepper("\(restSeconds)s", value: $restSeconds, in: 0...180, step: 5)
                    .labelsHidden()
                Text("\(restSeconds)s").typography(Typography.bodyMd).foregroundStyle(Palette.body)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .card(surface: Palette.surface)
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func unit(_ id: String) -> GoalUnit { ExerciseRegistry.goalUnit(for: id) }
    private func displayName(_ id: String) -> String { ExerciseRegistry.displayName(for: id) }
}

/// One editable workout entry: exercise name + sets and per-set target steppers.
private struct EntryRow: View {
    @Binding var entry: WorkoutEntry
    let unit: GoalUnit
    let name: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ExerciseTile(exerciseID: entry.exerciseID)
                Text(name).typography(Typography.headingSm).foregroundStyle(Palette.ink)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(Palette.mute)
                }
                .buttonStyle(.plain)
            }
            stepperRow("Sets", value: $entry.sets, range: 1...10, suffix: "")
            switch unit {
            case .reps:
                stepperRow("Reps", value: $entry.target, range: 1...50, suffix: "")
            case .seconds:
                stepperRow("Hold", value: $entry.target, range: 5...300, step: 5, suffix: "s")
            }
        }
        .card()
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>,
                            step: Int = 1, suffix: String) -> some View {
        HStack {
            Text(label).typography(Typography.bodySm).foregroundStyle(Palette.body)
            Spacer()
            Text("\(value.wrappedValue)\(suffix)").typography(Typography.bodyMd).foregroundStyle(Palette.ink)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper(label, value: value, in: range, step: step).labelsHidden()
        }
    }
}
