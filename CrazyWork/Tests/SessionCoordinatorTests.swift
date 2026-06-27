import XCTest
import ChallengeCore
@testable import CrazyWork

final class SessionCoordinatorTests: XCTestCase {
    /// One squat rep: down then up, repeated `count` times.
    private func squatReps(_ count: Int) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<count {
            for knee in [170.0, 80.0, 170.0] {
                var b = PoseFrameBuilderShim()
                b.timestamp = t
                b.knee(knee)
                frames.append(b.build())
                t += 0.5
            }
        }
        return frames
    }

    func testAdvancesToNextSetWhenTargetReached() {
        let plan = [
            PlannedSet(exerciseID: "squat", targetReps: 2),
            PlannedSet(exerciseID: "squat", targetReps: 2),
        ]
        let coord = SessionCoordinator(plan: plan)
        coord.start()
        XCTAssertEqual(coord.currentSetIndex, 0)

        for f in squatReps(2) { coord.feed(f) }

        XCTAssertEqual(coord.currentSetIndex, 1)
        XCTAssertEqual(coord.phase, .resting)
    }

    func testFinishingLastSetCompletesSession() {
        let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "squat", targetReps: 1)])
        coord.start()
        for f in squatReps(1) { coord.feed(f) }
        XCTAssertEqual(coord.phase, .finished)
    }
}
