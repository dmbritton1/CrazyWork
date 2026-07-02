import SwiftUI
import SwiftData

/// The History tab: finished sessions newest-first, each as a card with the
/// exercises performed, the volume numerals, and a form-quality badge.
struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HeroStripeBand {
                        Text("History").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    if sessions.isEmpty {
                        EmptyState(icon: "clock.arrow.circlepath",
                                   title: "No workouts yet",
                                   message: "Finished workouts land here, newest first.")
                    } else {
                        ForEach(sessions) { session in
                            sessionCard(session)
                                .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sessionCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateText(session.startedAt))
                    .typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                Spacer()
                Badge(text: "\(Int(session.averageFormScore * 100))% form",
                      style: session.averageFormScore >= 0.85 ? .greenSoft : .pro)
            }
            HStack(spacing: Spacing.lg) {
                ForEach(exerciseIDs(session), id: \.self) { id in
                    ExerciseTile(exerciseID: id, size: 36)
                }
                Spacer(minLength: 0)
                if session.totalReps > 0 {
                    metric("\(session.totalReps)", "reps")
                }
                if session.totalHoldSeconds > 0 {
                    metric(StatsView.clock(session.totalHoldSeconds), "held")
                }
            }
        }
        .card(padding: Spacing.lg)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Typography.numeral(22)).foregroundStyle(Palette.ink)
            Text(label).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
    }

    /// "Today" / "Yesterday" / "Mon, Jun 23" — recency reads at a glance.
    private func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Unique exercises in set order, capped so the strip never crowds the metrics.
    private func exerciseIDs(_ session: WorkoutSession) -> [String] {
        var seen = Set<String>()
        let ordered = session.sets.sorted { $0.order < $1.order }
            .compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
        return Array(ordered.prefix(4))
    }
}
