public protocol ExerciseAnalyzer {
    var info: ExerciseInfo { get }
    var status: TrackingStatus { get }

    /// Feed one frame; returns any reps that completed on this frame (usually 0 or 1).
    mutating func process(_ frame: PoseFrame) -> [RepEvent]

    /// Clear all internal state (rep count, phase, per-rep accumulators).
    mutating func reset()
}
