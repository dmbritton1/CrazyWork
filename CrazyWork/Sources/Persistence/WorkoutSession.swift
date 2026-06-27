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

    /// Total reps across rep-based sets (planks excluded).
    var totalReps: Int {
        sets.filter { $0.goalUnit == "reps" }.reduce(0) { $0 + Int($1.completed) }
    }

    /// Total seconds held across plank/time-based sets.
    var totalHoldSeconds: Int {
        sets.filter { $0.goalUnit == "seconds" }.reduce(0) { $0 + Int($1.completed) }
    }

    var averageFormScore: Double {
        let scored = sets.filter { $0.completed > 0 }
        guard !scored.isEmpty else { return 0 }
        return scored.reduce(0) { $0 + $1.averageFormScore } / Double(scored.count)
    }
}
