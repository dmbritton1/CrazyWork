import SwiftUI
import Charts
import ChallengeCore

/// Post-workout report: charts of volume-per-set and form-per-set, plus a
/// per-set breakdown. Shown full-screen when a session finishes.
struct SummaryView: View {
    let results: [SessionCoordinator.SetResult]
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let setLabel: String     // "Set 1"
        let exercise: String
        let completed: Double    // reps or seconds
        let unit: GoalUnit
        let formPct: Double      // 0...100
        let detail: String       // "12 / 12 reps" or "0:28 / 0:30"
    }

    private var rows: [Row] {
        results.enumerated().map { i, r in
            let name = ExerciseRegistry.displayName(for: r.exerciseID)
            let detail: String
            switch r.goalUnit {
            case .reps:
                detail = "\(Int(r.completed)) / \(r.target) reps"
            case .seconds:
                detail = "\(LiveWorkoutView.clock(r.completed)) / \(LiveWorkoutView.clock(Double(r.target)))"
            }
            return Row(setLabel: "Set \(i + 1)", exercise: name, completed: r.completed,
                       unit: r.goalUnit, formPct: r.averageFormScore * 100, detail: detail)
        }
    }

    private var totalReps: Int {
        results.filter { $0.goalUnit == .reps }.reduce(0) { $0 + Int($1.completed) }
    }

    private var totalHoldSeconds: Double {
        results.filter { $0.goalUnit == .seconds }.reduce(0) { $0 + $1.completed }
    }

    private var averageFormPct: Int {
        let scored = results.filter { $0.completed > 0 }
        guard !scored.isEmpty else { return 0 }
        let mean = scored.reduce(0.0) { $0 + $1.averageFormScore } / Double(scored.count)
        return Int((mean * 100).rounded())
    }

    private var exercisesText: String {
        var seen = Set<String>()
        var names: [String] = []
        for r in results {
            let name = ExerciseRegistry.displayName(for: r.exerciseID)
            if seen.insert(name).inserted { names.append(name) }
        }
        return names.joined(separator: " · ")
    }

    @MainActor private func shareImage() -> Image? {
        let renderer = ImageRenderer(content: WorkoutShareCard(
            date: Date(), exercises: exercisesText,
            totalReps: totalReps, totalHoldSeconds: totalHoldSeconds,
            averageFormPct: averageFormPct)
            .environment(\.colorScheme, .dark)) // shared card is always the branded dark card
        renderer.scale = UIScreen.main.scale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Workout Complete").typography(Typography.displayLg).foregroundStyle(Palette.ink)

                if !rows.isEmpty {
                    chartCard("Volume per set") {
                        Chart(rows) { row in
                            BarMark(x: .value("Set", row.setLabel),
                                    y: .value("Done", row.completed))
                                .foregroundStyle(Palette.brandRed)
                        }
                    }

                    chartCard("Form per set") {
                        Chart(rows) { row in
                            BarMark(x: .value("Set", row.setLabel),
                                    y: .value("Form %", row.formPct))
                                .foregroundStyle(Palette.accentAqua)
                        }
                        .chartYScale(domain: 0...100)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("\(row.setLabel) · \(row.exercise)")
                                    .typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                                Text(row.detail).typography(Typography.bodySm).foregroundStyle(Palette.mute)
                            }
                            Spacer()
                            Text("\(Int(row.formPct))% form")
                                .typography(Typography.bodySm).foregroundStyle(Palette.body)
                        }
                        .card()
                    }
                }

                if let image = shareImage() {
                    ShareLink(item: image,
                              preview: SharePreview("My CrazyWork workout", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Button("Done") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
            content()
                .frame(height: 180)
                .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Palette.hairline) } }
                .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Palette.hairline) } }
        }
        .card()
    }
}
