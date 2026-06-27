import Foundation

struct PlannedSet: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: String
    let targetReps: Int
}
