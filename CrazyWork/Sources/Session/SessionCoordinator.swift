import Foundation
import Observation
import ChallengeCore

/// Drives a multi-set workout: swaps the active `ExerciseAnalyzer` per set,
/// accumulates progress/form results, and advances through sets to completion.
/// Goal-unit-agnostic — rep-based and time-based (plank) exercises are peers.
/// UI-agnostic; the view feeds it frames on the main actor.
@Observable
final class SessionCoordinator {
    enum Phase: Equatable { case idle, active, resting, finished }

    let plan: [PlannedSet]
    private(set) var currentSetIndex = 0
    private(set) var phase: Phase = .idle
    /// Current progress in the active exercise's goal unit (reps or seconds).
    private(set) var currentProgress: Double = 0
    private(set) var goalUnit: GoalUnit = .reps
    private(set) var poseVisible = false
    private(set) var lastFormCue: String?
    private(set) var results: [SetResult] = []

    private var analyzer: (any ExerciseAnalyzer)?
    private var cueCounts: [String: Int] = [:]
    private var visibleFrames = 0
    private var cuedFrames = 0
    private var pendingEvents: [WorkoutEvent] = []

    struct SetResult {
        let exerciseID: String
        let goalUnit: GoalUnit
        let target: Int
        let completed: Double
        /// Fraction of visible frames with acceptable form (1 = clean).
        let averageFormScore: Double
        /// Form-cue text -> how many frames showed it.
        let findingsSummary: [String: Int]
    }

    var currentTarget: Int {
        plan.indices.contains(currentSetIndex) ? plan[currentSetIndex].target : 0
    }

    init(plan: [PlannedSet]) {
        self.plan = plan
    }

    func start() {
        currentSetIndex = 0
        loadCurrentSet()
        phase = plan.isEmpty ? .finished : .active
    }

    /// Called from the rest screen to begin the next set.
    func beginNextSet() {
        guard phase == .resting else { return }
        loadCurrentSet()
        phase = .active
    }

    @discardableResult
    func feed(_ frame: PoseFrame) -> [WorkoutEvent] {
        pendingEvents = []
        guard phase == .active, var analyzer else { return [] }
        let result = analyzer.process(frame)
        self.analyzer = analyzer // write back the mutated struct

        poseVisible = result.poseVisible
        currentProgress = result.progress

        if result.poseVisible {
            visibleFrames += 1
            if let cue = result.formCue {
                cuedFrames += 1
                lastFormCue = cue
                cueCounts[cue, default: 0] += 1
            } else {
                lastFormCue = nil
            }
        }

        if result.didAdvance, goalUnit == .reps {
            pendingEvents.append(.repCompleted(count: Int(result.progress)))
        }
        if goalUnit == .seconds {
            pendingEvents.append(.held(seconds: result.progress, target: currentTarget))
        }
        pendingEvents.append(.formCue(result.poseVisible ? result.formCue : nil))

        if currentProgress >= Double(currentTarget) {
            finishCurrentSet()
        }
        return pendingEvents
    }

    private func loadCurrentSet() {
        let analyzer = ExerciseRegistry.makeAnalyzer(for: plan[currentSetIndex].exerciseID)
        self.analyzer = analyzer
        self.analyzer?.reset()
        goalUnit = analyzer?.definition.goalUnit ?? .reps
        currentProgress = 0
        poseVisible = false
        lastFormCue = nil
        cueCounts = [:]
        visibleFrames = 0
        cuedFrames = 0
    }

    private func finishCurrentSet() {
        let set = plan[currentSetIndex]
        let score = visibleFrames > 0 ? max(0, 1 - Double(cuedFrames) / Double(visibleFrames)) : 1
        results.append(SetResult(
            exerciseID: set.exerciseID,
            goalUnit: goalUnit,
            target: set.target,
            completed: currentProgress,
            averageFormScore: score,
            findingsSummary: cueCounts
        ))

        pendingEvents.append(.setCompleted(index: currentSetIndex, total: plan.count))

        if currentSetIndex + 1 < plan.count {
            currentSetIndex += 1
            phase = .resting
            let nextID = plan[currentSetIndex].exerciseID
            let name = ExerciseRegistry.all.first { $0.id == nextID }?.displayName ?? nextID
            pendingEvents.append(.rest(nextExerciseName: name))
        } else {
            phase = .finished
            pendingEvents.append(.finished)
        }
    }
}
