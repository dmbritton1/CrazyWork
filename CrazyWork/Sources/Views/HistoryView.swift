import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        List(sessions) { session in
            VStack(alignment: .leading) {
                Text(session.startedAt, style: .date)
                Text("\(session.totalReps) reps · form \(Int(session.averageFormScore * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
    }
}
