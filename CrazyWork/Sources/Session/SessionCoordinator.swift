import Foundation
import Observation
import ChallengeCore

/// Drives a multi-set workout: swaps the active `ExerciseAnalyzer` per set,
/// accumulates rep/form results, and advances through sets to completion.
/// UI-agnostic; the view feeds it frames on the main actor.
@Observable
final class SessionCoordinator {
    enum Phase: Equatable { case idle, active, resting, finished }

    let plan: [PlannedSet]
    private(set) var currentSetIndex = 0
    private(set) var phase: Phase = .idle
    private(set) var currentReps = 0
    private(set) var poseVisible = false
    private(set) var lastFormCue: String?
    private(set) var results: [SetResult] = []

    private var analyzer: (any ExerciseAnalyzer)?
    private var cueCounts: [String: Int] = [:]
    private var visibleFrames = 0
    private var cuedFrames = 0

    struct SetResult {
        let exerciseID: String
        let targetReps: Int
        let completedReps: Int
        /// Fraction of visible frames with acceptable form (1 = clean).
        let averageFormScore: Double
        /// Form-cue text -> how many frames showed it.
        let findingsSummary: [String: Int]
    }

    var currentTarget: Int {
        plan.indices.contains(currentSetIndex) ? plan[currentSetIndex].targetReps : 0
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

    func feed(_ frame: PoseFrame) {
        guard phase == .active, var analyzer else { return }
        let result = analyzer.process(frame)
        self.analyzer = analyzer // write back the mutated struct

        poseVisible = result.poseVisible
        currentReps = result.count

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

        if result.didCompleteRep, currentReps >= currentTarget {
            finishCurrentSet()
        }
    }

    private func loadCurrentSet() {
        analyzer = ExerciseRegistry.makeAnalyzer(for: plan[currentSetIndex].exerciseID)
        analyzer?.reset()
        currentReps = 0
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
            targetReps: set.targetReps,
            completedReps: currentReps,
            averageFormScore: score,
            findingsSummary: cueCounts
        ))

        if currentSetIndex + 1 < plan.count {
            currentSetIndex += 1
            phase = .resting
        } else {
            phase = .finished
        }
    }
}
