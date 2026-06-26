import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var startedAt: Date
    var endedAt: Date?
    @Relationship(deleteRule: .cascade) var sets: [ExerciseSet]

    init(startedAt: Date) {
        self.startedAt = startedAt
        self.endedAt = nil
        self.sets = []
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.completedReps } }

    var averageFormScore: Double {
        let scored = sets.filter { $0.completedReps > 0 }
        guard !scored.isEmpty else { return 0 }
        return scored.reduce(0) { $0 + $1.averageFormScore } / Double(scored.count)
    }
}
