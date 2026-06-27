import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        List(sessions) { session in
            VStack(alignment: .leading) {
                Text(session.startedAt, style: .date)
                Text(summary(session))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
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
