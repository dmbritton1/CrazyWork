import Foundation
import SwiftData

/// A user-built workout saved to disk so it can be reloaded later from the
/// Plans tab. Stores the builder entries directly (`WorkoutEntry` is `Codable`).
@Model
final class SavedWorkout {
    var name: String
    var restSeconds: Int
    var createdAt: Date
    var entries: [WorkoutEntry]

    init(name: String, restSeconds: Int, entries: [WorkoutEntry]) {
        self.name = name
        self.restSeconds = restSeconds
        self.createdAt = Date()
        self.entries = entries
    }
}

extension SavedWorkout {
    /// View as a `PremadePlan` so the Plans tab can render + estimate it with
    /// the existing card UI and load it through the same `onChoose` flow.
    var asPlan: PremadePlan {
        PremadePlan(id: "saved-\(persistentModelID.hashValue)",
                    name: name,
                    summary: "Custom workout",
                    entries: entries,
                    restSeconds: restSeconds)
    }
}
