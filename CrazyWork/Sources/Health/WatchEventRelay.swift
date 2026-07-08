import Foundation

/// Pure policy: turns `WorkoutEvent`s into the `WatchMessage`s the wrist needs
/// — haptic cues on the coach moments (set complete, 3-2-1, workout done) and
/// a `progress` message whenever the visible workout state changes. Stateful
/// only for dedup (last snapshot sent, countdown numbers already buzzed);
/// no clock and no I/O, mirroring `WorkoutAudioCoach`.
struct WatchEventRelay {
    /// The workout state the watch renders. `value` is an Int so per-frame
    /// hold events collapse to one progress message per elapsed second.
    struct Snapshot: Equatable {
        var exerciseName: String
        var value: Int
        var target: Int
        var setIndex: Int
        var setCount: Int
        var phase: SessionPhaseMessage
    }

    private var lastSnapshot: Snapshot?
    private var buzzedCountdown: Set<Int> = []

    mutating func messages(for event: WorkoutEvent, snapshot: Snapshot) -> [WatchMessage] {
        var out: [WatchMessage] = []
        switch event {
        case .setCompleted:
            buzzedCountdown = []
            out.append(.haptic(.setComplete))
        case .finished:
            out.append(.haptic(.workoutComplete))
        case let .held(seconds, target):
            // Same 3-2-1 window arithmetic as WorkoutAudioCoach.plankActions.
            let remaining = Double(target) - seconds
            for n in [3, 2, 1]
            where remaining <= Double(n) && remaining > Double(n) - 1 && !buzzedCountdown.contains(n) {
                buzzedCountdown.insert(n)
                out.append(.haptic(.countdown))
            }
        case .repCompleted, .formCue, .rest:
            break
        }
        if snapshot != lastSnapshot {
            out.append(progressMessage(for: snapshot))
        }
        return out
    }

    /// Builds (and records) a progress message outside the event flow — used
    /// when rest ends, which has no `WorkoutEvent`.
    mutating func progressMessage(for snapshot: Snapshot) -> WatchMessage {
        lastSnapshot = snapshot
        return .progress(exerciseName: snapshot.exerciseName, value: snapshot.value,
                         target: snapshot.target, setIndex: snapshot.setIndex,
                         setCount: snapshot.setCount, phase: snapshot.phase)
    }
}
