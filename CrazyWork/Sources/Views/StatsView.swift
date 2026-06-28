import SwiftUI
import SwiftData
import Charts

/// The Stats tab: lifetime totals, a day-streak, progress trend charts, and a
/// consistency calendar — aggregated across all saved workouts.
struct StatsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HeroStripeBand {
                        Text("Stats").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    if sessions.isEmpty {
                        ContentUnavailableView("No workouts yet",
                                               systemImage: "chart.xyaxis.line",
                                               description: Text("Complete a workout to see your progress."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        statsContent(stats)
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }

    private func statsContent(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            cards(stats)
            HealthMetricsCard()
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Consistency").typography(Typography.headingMd).foregroundStyle(Palette.ink)
                ConsistencyCalendarView(workoutDays: stats.workoutDays)
            }
            trends(stats)
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func cards(_ stats: ProgressStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            statCard("Workouts", "\(stats.totalWorkouts)", "figure.run")
            statCard("Current streak", "\(stats.currentStreak)d", "flame.fill", accent: true)
            statCard("Longest streak", "\(stats.longestStreak)d", "trophy.fill", accent: true)
            statCard("Total reps", "\(stats.totalReps)", "number")
            statCard("Hold time", Self.clock(stats.totalHoldSeconds), "timer")
            statCard("Active time", Self.duration(stats.totalActiveTime), "clock")
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: icon).typography(Typography.captionMd).foregroundStyle(Palette.mute)
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
        }
        .card(surface: Palette.surfaceElevated)
    }

    private func trends(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            chartCard("Reps per workout", color: Palette.brandRed) {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Reps", s.reps))
                        .foregroundStyle(Palette.brandRed)
                }
            }
            chartCard("Hold seconds per workout", color: Palette.accentAqua) {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Seconds", s.holdSeconds))
                        .foregroundStyle(Palette.accentAqua)
                }
            }
            chartCard("Form % per workout", color: Palette.accentGreen) {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Form %", s.formScore * 100))
                        .foregroundStyle(Palette.accentGreen)
                }
                .chartYScale(domain: 0...100)
            }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, color: Color,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
            content()
                .frame(height: 160)
                .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Palette.hairline) } }
                .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Palette.hairline) } }
        }
        .card()
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
