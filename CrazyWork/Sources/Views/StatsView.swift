import SwiftUI
import SwiftData
import Charts

/// The Stats tab: lifetime totals, a day-streak, progress trend charts, and a
/// consistency calendar — aggregated across all saved workouts.
struct StatsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView("No workouts yet",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Complete a workout to see your progress."))
            } else {
                content(stats)
            }
        }
        .navigationTitle("Stats")
    }

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }

    private func content(_ stats: ProgressStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cards(stats)
                trends(stats)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Consistency").font(.headline)
                    ConsistencyCalendarView(workoutDays: stats.workoutDays)
                }
            }
            .padding()
        }
    }

    private func cards(_ stats: ProgressStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Workouts", "\(stats.totalWorkouts)", "figure.run")
            statCard("Current streak", "\(stats.currentStreak)d", "flame.fill")
            statCard("Longest streak", "\(stats.longestStreak)d", "trophy.fill")
            statCard("Total reps", "\(stats.totalReps)", "number")
            statCard("Hold time", Self.clock(stats.totalHoldSeconds), "timer")
            statCard("Active time", Self.duration(stats.totalActiveTime), "clock")
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func trends(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            chartCard("Reps per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Reps", s.reps))
                }
            }
            chartCard("Hold seconds per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Seconds", s.holdSeconds))
                }
            }
            chartCard("Form % per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Form %", s.formScore * 100))
                }
                .chartYScale(domain: 0...100)
            }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().frame(height: 160)
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
