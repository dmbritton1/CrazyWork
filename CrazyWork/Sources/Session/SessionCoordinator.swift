import Foundation
import Observation
import ChallengeCore

@Observable
final class SessionCoordinator {
    enum Phase: Equatable { case idle, active, resting, finished }

    let plan: [PlannedSet]
    private(set) var currentSetIndex = 0
    private(set) var phase: Phase = .idle
    private(set) var currentReps = 0
    private(set) var lastFindings: [Finding] = []
    private(set) var status: TrackingStatus = .outOfFrame

    /// Completed set results, ready to persist when the session finishes.
    private(set) var results: [SetResult] = []

    private var analyzer: (any ExerciseAnalyzer)?
    private var formScores: [Double] = []
    private var findingCounts: [String: Int] = [:]

    struct SetResult {
        let exerciseID: String
        let targetReps: Int
        let completedReps: Int
        let averageFormScore: Double
        let findingsSummary: [String: Int]
    }

    init(plan: [PlannedSet]) {
        self.plan = plan
    }

    func start() {
        currentSetIndex = 0
        loadCurrentSet()
        phase = plan.isEmpty ? .finished : .active
    }

    /// Call from the rest screen to begin the next set.
    func beginNextSet() {
        guard phase == .resting else { return }
        loadCurrentSet()
        phase = .active
    }

    func feed(_ frame: PoseFrame) {
        guard phase == .active, var analyzer else { return }
        let events = analyzer.process(frame)
        self.status = analyzer.status
        self.analyzer = analyzer // write back the mutated struct

        for event in events {
            currentReps = event.repIndex
            lastFindings = event.findings
            formScores.append(event.formScore)
            for f in event.findings { findingCounts[f.rawValue, default: 0] += 1 }
        }

        if currentReps >= plan[currentSetIndex].targetReps {
            finishCurrentSet()
        }
    }

    private func loadCurrentSet() {
        let set = plan[currentSetIndex]
        analyzer = ExerciseRegistry.makeAnalyzer(for: set.exerciseID)
        analyzer?.reset()
        currentReps = 0
        lastFindings = []
        formScores = []
        findingCounts = [:]
    }

    private func finishCurrentSet() {
        let set = plan[currentSetIndex]
        let avg = formScores.isEmpty ? 0 : formScores.reduce(0, +) / Double(formScores.count)
        results.append(SetResult(
            exerciseID: set.exerciseID,
            targetReps: set.targetReps,
            completedReps: currentReps,
            averageFormScore: avg,
            findingsSummary: findingCounts
        ))

        if currentSetIndex + 1 < plan.count {
            currentSetIndex += 1
            phase = .resting
        } else {
            phase = .finished
        }
    }
}
