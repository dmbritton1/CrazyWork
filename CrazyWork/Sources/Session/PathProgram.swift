import Foundation

/// One node on the path: a titled workout with a muscle-group focus tag, plus
/// optional bonus workouts. Supplementary entries reuse this same type with an
/// empty `supplementary` — one value type, not two.
struct PathDay: Identifiable {
    let id: String
    let title: String
    let focus: String           // muscle tag, e.g. "Chest · Triceps · Shoulders"
    let entries: [WorkoutEntry]
    let restSeconds: Int
    let supplementary: [PathDay]
}

/// The static, infinite muscle-group rotation. `day(at:)` wraps, so the path
/// never ends. This array is the single seam a future data-driven scheduler
/// would replace.
enum PathProgram {
    static let rotation: [PathDay] = [
        PathDay(id: "push", title: "Upper Push", focus: "Chest · Triceps · Shoulders",
                entries: [WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "push.core", title: "Core hold", focus: "Core",
                            entries: [WorkoutEntry(exerciseID: "plank", sets: 2, target: 30)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "legs", title: "Lower Power", focus: "Quads · Glutes",
                entries: [WorkoutEntry(exerciseID: "squat", sets: 3, target: 12),
                          WorkoutEntry(exerciseID: "lunge", sets: 3, target: 10)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "legs.upper", title: "Upper finisher", focus: "Chest · Triceps",
                            entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "core", title: "Core", focus: "Abs · Core",
                entries: [WorkoutEntry(exerciseID: "situp", sets: 3, target: 15),
                          WorkoutEntry(exerciseID: "plank", sets: 3, target: 30)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "core.glute", title: "Glute bridge", focus: "Glutes",
                            entries: [WorkoutEntry(exerciseID: "glutebridge", sets: 2, target: 15)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "posterior", title: "Glutes & Posterior", focus: "Glutes · Hamstrings",
                entries: [WorkoutEntry(exerciseID: "glutebridge", sets: 3, target: 15),
                          WorkoutEntry(exerciseID: "lunge", sets: 3, target: 12)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "posterior.upper", title: "Upper push", focus: "Chest · Triceps",
                            entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "full", title: "Full Body", focus: "Total body",
                entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10),
                          WorkoutEntry(exerciseID: "squat", sets: 2, target: 12),
                          WorkoutEntry(exerciseID: "situp", sets: 2, target: 12),
                          WorkoutEntry(exerciseID: "plank", sets: 1, target: 30)],
                restSeconds: 25,
                supplementary: [
                    PathDay(id: "full.plank", title: "Plank challenge", focus: "Core",
                            entries: [WorkoutEntry(exerciseID: "plank", sets: 2, target: 45)],
                            restSeconds: 20, supplementary: [])
                ]),
    ]

    /// The node at an absolute position; wraps forever.
    static func day(at index: Int) -> PathDay {
        let n = rotation.count
        return rotation[((index % n) + n) % n]
    }

    /// Whole calendar days since the reference date, bucketed by `startOfDay`
    /// so it matches how `ProgressStats` groups days (DST-safe).
    static func epochDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day],
                                from: Date(timeIntervalSinceReferenceDate: 0),
                                to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// How a node renders on the trail.
enum NodeState: Equatable { case done, today, lockedNext, locked }

/// Pure progression state. `index` = nodes finished (also the current TODAY
/// node's absolute position). `lastCompletedDay` = epoch day of the last
/// completion, or `Int.min` for never.
struct PathProgress {
    var index: Int
    var lastCompletedDay: Int

    func isCompletedToday(today: Int) -> Bool { lastCompletedDay == today }

    /// Apply a completion stamped on `today`; advances at most once per day.
    func completing(today: Int) -> PathProgress {
        guard lastCompletedDay != today else { return self }
        return PathProgress(index: index + 1, lastCompletedDay: today)
    }

    func state(of nodeIndex: Int, today: Int) -> NodeState {
        if nodeIndex < index { return .done }
        if nodeIndex == index { return isCompletedToday(today: today) ? .lockedNext : .today }
        return .locked
    }
}
