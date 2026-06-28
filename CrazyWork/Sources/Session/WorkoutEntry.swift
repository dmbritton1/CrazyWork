import Foundation

/// A builder row: one exercise repeated for `sets` sets of `target` each
/// (target is reps, or seconds for a timed hold).
struct WorkoutEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    var exerciseID: String
    var sets: Int
    var target: Int
}

enum WorkoutPlan {
    /// Expand builder entries into the flat, ordered list the coordinator runs.
    static func expand(_ entries: [WorkoutEntry]) -> [PlannedSet] {
        entries.flatMap { entry in
            (0..<max(0, entry.sets)).map { _ in
                PlannedSet(exerciseID: entry.exerciseID, target: entry.target)
            }
        }
    }
}
