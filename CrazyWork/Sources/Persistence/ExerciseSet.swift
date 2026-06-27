import Foundation
import SwiftData

@Model
final class ExerciseSet {
    var exerciseID: String
    /// "reps" or "seconds" — matches the exercise's GoalUnit.
    var goalUnit: String
    /// Target value in the goal unit (rep count, or seconds to hold).
    var target: Int
    /// Achieved value in the goal unit (reps done, or seconds held).
    var completed: Double
    /// Fraction of visible frames with acceptable form (1 = clean).
    var averageFormScore: Double
    /// Form-cue text -> how many frames showed it.
    var findingsSummary: [String: Int]
    var order: Int

    init(exerciseID: String, goalUnit: String, target: Int, order: Int) {
        self.exerciseID = exerciseID
        self.goalUnit = goalUnit
        self.target = target
        self.completed = 0
        self.averageFormScore = 0
        self.findingsSummary = [:]
        self.order = order
    }
}
