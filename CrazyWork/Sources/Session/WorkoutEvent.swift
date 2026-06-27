import Foundation

/// A fact the workout produced on one fed frame. The coordinator emits these;
/// it knows nothing about audio. `WorkoutAudioCoach` turns them into sounds.
enum WorkoutEvent: Equatable {
    /// A rep-based exercise just completed rep `count` (the running total).
    case repCompleted(count: Int)
    /// A timed hold (plank) is at `seconds` of `target` seconds, this frame.
    case held(seconds: Double, target: Int)
    /// The current form cue this frame (`nil` when form is fine / pose lost).
    case formCue(String?)
    /// The set at `index` of `total` just finished.
    case setCompleted(index: Int, total: Int)
    /// Entering rest before the next set, which is `nextExerciseName`.
    case rest(nextExerciseName: String)
    /// The whole workout is done.
    case finished
}
