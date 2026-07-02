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
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Stats").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                            if let since = sinceText {
                                Text(since).typography(Typography.bodyMd).foregroundStyle(Palette.mute)
                            }
                        }
                    }
                    if sessions.isEmpty {
                        EmptyState(icon: "chart.xyaxis.line",
                                   title: "No stats yet",
                                   message: "Finish your first workout and your progress shows up here.")
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

    /// "12 workouts since March" — the hero's one-line lifetime summary.
    private var sinceText: String? {
        guard let first = sessions.first else { return nil }
        let month = first.startedAt.formatted(.dateTime.month(.wide))
        let count = sessions.count
        return "\(count) workout\(count == 1 ? "" : "s") since \(month)"
    }

    private func statsContent(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            cards(stats)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Consistency").typography(Typography.headingMd).foregroundStyle(Palette.ink)
                ConsistencyCalendarView(workoutDays: stats.workoutDays)
                    .frame(maxWidth: .infinity)
                    .card(padding: Spacing.lg)
            }
            trends(stats)
            HealthMetricsCard()
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            RoundedRectangle(cornerRadius: Radii.sm)
                .fill(accent ? Palette.brandRedSoft : Palette.surfaceCard)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent ? Palette.accentRedBright : Palette.body))
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(value).font(Typography.numeral(28))
                    .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
                Text(title).typography(Typography.captionMd).foregroundStyle(Palette.mute)
            }
        }
        .card(surface: Palette.surfaceElevated, padding: Spacing.lg)
    }

    private func trends(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            trendCard("Reps per workout", color: Palette.brandRed, stats: stats) { Double($0.reps) }
            trendCard("Hold seconds per workout", color: Palette.accentAqua, stats: stats) { Double($0.holdSeconds) }
            trendCard("Form % per workout", color: Palette.accentGreen, stats: stats,
                      domain: 0...100) { $0.formScore * 100 }
        }
    }

    /// A trend line in the strand voice: a smooth curve with the series color
    /// dissolving into the canvas beneath it, and a point on the latest value.
    private func trendCard(_ title: String, color: Color, stats: ProgressStats,
                           domain: ClosedRange<Double>? = nil,
                           value: @escaping (SessionSummary) -> Double) -> some View {
        let last = stats.summaries.last
        return ChartCard(title: title) {
            Chart {
                ForEach(stats.summaries, id: \.date) { s in
                    AreaMark(x: .value("Date", s.date), y: .value(title, value(s)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient.trendFill(color))
                    LineMark(x: .value("Date", s.date), y: .value(title, value(s)))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)
                }
                if let last {
                    PointMark(x: .value("Date", last.date), y: .value(title, value(last)))
                        .symbolSize(40)
                        .foregroundStyle(color)
                }
            }
            .modifier(OptionalYDomain(domain: domain))
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

/// Applies a fixed Y domain only when one is given (form % pins to 0–100).
private struct OptionalYDomain: ViewModifier {
    let domain: ClosedRange<Double>?
    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}
