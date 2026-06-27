import Foundation

/// Pure policy: turns `WorkoutEvent`s into `AudioAction`s with the right cadence
/// — tick + spoken number per rep, a cue spoken once per occurrence, plank
/// 10-second milestones and a 3-2-1 countdown, and set/rest/finish flourishes.
/// No clock and no I/O, so it is fully deterministic and unit-tested.
struct WorkoutAudioCoach {
    private var lastCue: String?
    private var lastMilestone = 0          // highest 10s mark already announced
    private var spokenCountdown: Set<Int> = []

    mutating func handle(_ event: WorkoutEvent) -> [AudioAction] {
        switch event {
        case let .repCompleted(count):
            return [.tick, .speak("\(count)")]
        case let .held(seconds, target):
            return plankActions(seconds: seconds, target: target)
        case let .formCue(cue):
            return cueActions(cue)
        case .setCompleted:
            resetPerSet()
            return [.chime, .speak("Set complete")]
        case let .rest(name):
            return [.restBeep, .speak("Rest. Next up: \(name)")]
        case .finished:
            return [.fanfare, .speak("Workout complete")]
        }
    }

    private mutating func cueActions(_ cue: String?) -> [AudioAction] {
        defer { lastCue = cue }
        guard let cue, cue != lastCue else { return [] }
        return [.speak(cue)]
    }

    private mutating func plankActions(seconds: Double, target: Int) -> [AudioAction] {
        var actions: [AudioAction] = []
        let milestone = Int(seconds) / 10 * 10          // 0, 10, 20, 30…
        if milestone >= 10, milestone > lastMilestone {
            lastMilestone = milestone
            actions += [.tick, .speak("\(milestone) seconds")]
        }
        // A milestone wins its frame: don't stack a countdown number on top of it.
        guard actions.isEmpty else { return actions }
        let remaining = Double(target) - seconds
        for n in [3, 2, 1]
        where remaining <= Double(n) && remaining > Double(n) - 1 && !spokenCountdown.contains(n) {
            spokenCountdown.insert(n)
            actions.append(.speak(numberWord(n)))
        }
        return actions
    }

    private mutating func resetPerSet() {
        lastCue = nil
        lastMilestone = 0
        spokenCountdown = []
    }

    private func numberWord(_ n: Int) -> String {
        switch n {
        case 3: return "three"
        case 2: return "two"
        default: return "one"
        }
    }
}
