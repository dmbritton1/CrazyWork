import Foundation
import SwiftData

@Model
final class ExerciseSet {
    var exerciseID: String
    var targetReps: Int
    var completedReps: Int
    var averageFormScore: Double
    /// Finding rawValue -> count, stored as a small encodable dictionary.
    var findingsSummary: [String: Int]
    var order: Int

    init(exerciseID: String, targetReps: Int, order: Int) {
        self.exerciseID = exerciseID
        self.targetReps = targetReps
        self.completedReps = 0
        self.averageFormScore = 0
        self.findingsSummary = [:]
        self.order = order
    }
}
