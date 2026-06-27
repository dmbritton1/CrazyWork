import XCTest
import ChallengeCore
@testable import CrazyWork

final class SessionCoordinatorTests: XCTestCase {
    func testAdvancesToNextSetWhenTargetReached() {
        let plan = [
            PlannedSet(exerciseID: "squat", targetReps: 2),
            PlannedSet(exerciseID: "squat", targetReps: 2),
        ]
        let coord = SessionCoordinator(plan: plan)
        coord.start()
        XCTAssertEqual(coord.currentSetIndex, 0)

        for f in SquatFrames.reps(2) { coord.feed(f) }

        XCTAssertEqual(coord.currentSetIndex, 1)
        XCTAssertEqual(coord.phase, .resting)
    }

    func testFinishingLastSetCompletesSession() {
        let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "squat", targetReps: 1)])
        coord.start()
        for f in SquatFrames.reps(1) { coord.feed(f) }
        XCTAssertEqual(coord.phase, .finished)
        XCTAssertEqual(coord.results.count, 1)
        XCTAssertEqual(coord.results.first?.completedReps, 1)
    }
}
