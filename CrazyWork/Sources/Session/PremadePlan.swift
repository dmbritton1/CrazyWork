import Foundation
import ChallengeCore

/// A curated, ready-to-load workout: a name, a one-line summary, the exercises
/// (as builder entries), and the rest between sets.
struct PremadePlan: Identifiable {
    let id: String
    let name: String
    let summary: String
    let entries: [WorkoutEntry]
    let restSeconds: Int
}

extension PremadePlan {
    /// Rough completion estimate in seconds: total work plus inter-set rest.
    /// Reps are estimated at `secondsPerRep` each; a timed hold counts its seconds.
    func estimatedSeconds(secondsPerRep: Double = 3) -> Int {
        let totalSets = entries.reduce(0) { $0 + max(0, $1.sets) }
        let work = entries.reduce(0.0) { running, entry in
            let unit = ExerciseRegistry.goalUnit(for: entry.exerciseID)
            let perSet = unit == .reps ? Double(entry.target) * secondsPerRep : Double(entry.target)
            return running + Double(max(0, entry.sets)) * perSet
        }
        let rest = Double(max(0, totalSets - 1)) * Double(restSeconds)
        return Int((work + rest).rounded())
    }
}

/// The built-in plans shown in the Plans tab. Built from the existing exercises.
enum PremadePlanCatalog {
    static let all: [PremadePlan] = [
        PremadePlan(id: "express5", name: "Express 5",
                    summary: "A quick full-body hit.",
                    entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10),
                              WorkoutEntry(exerciseID: "squat", sets: 2, target: 12),
                              WorkoutEntry(exerciseID: "plank", sets: 1, target: 30)],
                    restSeconds: 20),
        PremadePlan(id: "fullBodyStarter", name: "Full Body Starter",
                    summary: "Balanced beginner session.",
                    entries: [WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10),
                              WorkoutEntry(exerciseID: "squat", sets: 3, target: 12),
                              WorkoutEntry(exerciseID: "lunge", sets: 3, target: 10),
                              WorkoutEntry(exerciseID: "plank", sets: 2, target: 30)],
                    restSeconds: 30),
        PremadePlan(id: "legDay", name: "Leg Day",
                    summary: "Lower-body focus.",
                    entries: [WorkoutEntry(exerciseID: "squat", sets: 4, target: 12),
                              WorkoutEntry(exerciseID: "lunge", sets: 3, target: 12),
                              WorkoutEntry(exerciseID: "plank", sets: 2, target: 45)],
                    restSeconds: 45),
        PremadePlan(id: "coreHold", name: "Core & Hold",
                    summary: "Core and stability.",
                    entries: [WorkoutEntry(exerciseID: "plank", sets: 3, target: 30),
                              WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10)],
                    restSeconds: 30),
    ]
}
