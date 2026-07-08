import Testing
@testable import CrazyWork

struct WatchEventRelayTests {
    private func snap(value: Int = 0, phase: SessionPhaseMessage = .active,
                      setIndex: Int = 0) -> WatchEventRelay.Snapshot {
        WatchEventRelay.Snapshot(exerciseName: "Push-up", value: value, target: 12,
                                 setIndex: setIndex, setCount: 3, phase: phase)
    }

    @Test func emitsProgressOnlyWhenSnapshotChanges() {
        var relay = WatchEventRelay()
        let first = relay.messages(for: .formCue(nil), snapshot: snap(value: 0))
        #expect(first == [.progress(exerciseName: "Push-up", value: 0, target: 12,
                                    setIndex: 0, setCount: 3, phase: .active)])
        // Same snapshot again (another frame): nothing to send.
        #expect(relay.messages(for: .formCue(nil), snapshot: snap(value: 0)).isEmpty)
        // Value changed: one new progress message.
        let changed = relay.messages(for: .repCompleted(count: 1), snapshot: snap(value: 1))
        #expect(changed.count == 1)
    }

    @Test func setCompletedEmitsHapticAndProgress() {
        var relay = WatchEventRelay()
        _ = relay.messages(for: .formCue(nil), snapshot: snap(value: 11))
        let messages = relay.messages(for: .setCompleted(index: 0, total: 3),
                                      snapshot: snap(value: 0, phase: .resting, setIndex: 1))
        #expect(messages.contains(.haptic(.setComplete)))
        #expect(messages.contains(.progress(exerciseName: "Push-up", value: 0, target: 12,
                                            setIndex: 1, setCount: 3, phase: .resting)))
    }

    @Test func heldCountdownBuzzesOncePerNumber() {
        var relay = WatchEventRelay()
        // 27.5s of a 30s hold → remaining 2.5, inside the "3" window → one tap.
        let first = relay.messages(for: .held(seconds: 27.5, target: 30), snapshot: snap(value: 27))
        #expect(first.contains(.haptic(.countdown)))
        // Same second, later frame: value unchanged, countdown already buzzed.
        #expect(relay.messages(for: .held(seconds: 27.7, target: 30), snapshot: snap(value: 27)).isEmpty)
        // Next second (remaining 1.5): buzzes again for "1".
        let next = relay.messages(for: .held(seconds: 28.5, target: 30), snapshot: snap(value: 28))
        #expect(next.contains(.haptic(.countdown)))
    }

    @Test func countdownResetsAfterSetCompleted() {
        var relay = WatchEventRelay()
        _ = relay.messages(for: .held(seconds: 27.5, target: 30), snapshot: snap(value: 27))
        _ = relay.messages(for: .setCompleted(index: 0, total: 3),
                           snapshot: snap(value: 0, phase: .resting, setIndex: 1))
        // New set, same countdown window: must buzz again.
        let again = relay.messages(for: .held(seconds: 27.5, target: 30),
                                   snapshot: snap(value: 27, setIndex: 1))
        #expect(again.contains(.haptic(.countdown)))
    }

    @Test func finishedEmitsWorkoutCompleteHaptic() {
        var relay = WatchEventRelay()
        let messages = relay.messages(for: .finished, snapshot: snap(value: 12, phase: .finished))
        #expect(messages.contains(.haptic(.workoutComplete)))
    }
}
