import SwiftUI
import SwiftData

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
                        ContentUnavailableView("No history yet",
                                               systemImage: "clock.arrow.circlepath",
                                               description: Text("Finished workouts show up here."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(session.startedAt, style: .date)
                                    .typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                                Text(summary(session))
                                    .typography(Typography.bodySm).foregroundStyle(Palette.mute)
                            }
                            .card()
                            .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func summary(_ session: WorkoutSession) -> String {
        var parts: [String] = []
        if session.totalReps > 0 { parts.append("\(session.totalReps) reps") }
        if session.totalHoldSeconds > 0 { parts.append("\(session.totalHoldSeconds)s hold") }
        if parts.isEmpty { parts.append("0 reps") }
        parts.append("form \(Int(session.averageFormScore * 100))%")
        return parts.joined(separator: " · ")
    }
}
