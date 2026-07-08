import SwiftUI
import Charts
import ChallengeCore

/// Post-workout report: charts of volume-per-set and form-per-set, plus a
/// per-set breakdown. Shown full-screen when a session finishes.
struct SummaryView: View {
    let results: [SessionCoordinator.SetResult]
    /// Start of the live session, for the heart-rate query. Nil (previews,
    /// future call sites without a live interval) hides the HR chart.
    var workoutStart: Date? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var heartRate: [HealthStore.HeartRateSample] = []

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
                HeroStripeBand {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Workout Complete")
                            .typography(Typography.displayLg).foregroundStyle(Palette.ink)
                        Text(exercisesText).typography(Typography.bodyMd).foregroundStyle(Palette.mute)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xl) {
                    totalsCard

                    if !rows.isEmpty {
                        ChartCard(title: "Volume per set", height: 180) {
                            Chart(rows) { row in
                                BarMark(x: .value("Set", row.setLabel),
                                        y: .value("Done", row.completed))
                                    .cornerRadius(3)
                                    .foregroundStyle(LinearGradient(
                                        colors: [Palette.brandRed, Palette.accentRedDeep],
                                        startPoint: .top, endPoint: .bottom))
                            }
                        }

                        ChartCard(title: "Form per set", height: 180) {
                            Chart(rows) { row in
                                BarMark(x: .value("Set", row.setLabel),
                                        y: .value("Form %", row.formPct))
                                    .cornerRadius(3)
                                    .foregroundStyle(LinearGradient(
                                        colors: [Palette.accentAqua, Palette.accentTealDeep],
                                        startPoint: .top, endPoint: .bottom))
                            }
                            .chartYScale(domain: 0...100)
                        }

                        if heartRate.count >= 2 {
                            ChartCard(title: "Heart rate", height: 180) {
                                Chart(heartRate, id: \.date) { sample in
                                    LineMark(x: .value("Time", sample.date),
                                             y: .value("BPM", sample.bpm))
                                        .interpolationMethod(.catmullRom)
                                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                        .foregroundStyle(Palette.brandRed)
                                }
                            }
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
                            .card(padding: Spacing.lg)
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
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .task {
            guard let workoutStart else { return }
            heartRate = await HealthStore.shared.heartRateSeries(start: workoutStart, end: Date())
        }
    }

    /// The headline moment: three big numerals for what the session produced.
    private var totalsCard: some View {
        HStack(alignment: .top) {
            total("\(totalReps)", "reps", accent: true)
            Spacer()
            total(LiveWorkoutView.clock(totalHoldSeconds), "held")
            Spacer()
            total("\(averageFormPct)%", "form")
        }
        .card(surface: Palette.surfaceElevated)
    }

    private func total(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).font(Typography.numeral(32))
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
            Text(label).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
    }
}
