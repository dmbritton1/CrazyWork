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
            let name = ExerciseRegistry.all.first { $0.id == r.exerciseID }?.displayName ?? r.exerciseID
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Workout Complete").font(.largeTitle.bold())

                if !rows.isEmpty {
                    chartCard("Volume per set") {
                        Chart(rows) { row in
                            BarMark(x: .value("Set", row.setLabel),
                                    y: .value("Done", row.completed))
                                .foregroundStyle(by: .value("Exercise", row.exercise))
                        }
                    }

                    chartCard("Form per set") {
                        Chart(rows) { row in
                            BarMark(x: .value("Set", row.setLabel),
                                    y: .value("Form %", row.formPct))
                                .foregroundStyle(.green)
                        }
                        .chartYScale(domain: 0...100)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(row.setLabel) · \(row.exercise)").font(.subheadline.weight(.medium))
                                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(row.formPct))% form").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().frame(height: 180)
        }
    }
}
