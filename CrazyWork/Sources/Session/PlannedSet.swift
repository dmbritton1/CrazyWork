import Foundation

struct PlannedSet: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: String
    /// Target in the exercise's goal unit: rep count, or seconds to hold.
    let target: Int
}
