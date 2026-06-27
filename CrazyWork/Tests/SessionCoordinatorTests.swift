import XCTest
import ChallengeCore
@testable import CrazyWork

final class SessionCoordinatorTests: XCTestCase {
    /// A held, straight plank frame at time `t`: horizontal body, propped on the
    /// arms (elbow/wrist below the shoulder) so the analyzer reads a real plank.
    private func plankFrame(_ t: TimeInterval) -> PoseFrame {
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: 0.9)
        }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(0, 1), .rightShoulder: jp(0, 1),
            .leftElbow: jp(0, 0.4), .rightElbow: jp(0, 0.4),
            .leftWrist: jp(0.3, 0.4), .rightWrist: jp(0.3, 0.4),
            .leftHip: jp(1, 1), .rightHip: jp(1, 1),
            .leftAnkle: jp(2, 1), .rightAnkle: jp(2, 1),
        ])
    }

    func testAdvancesToNextSetWhenRepTargetReached() {
        let plan = [
            PlannedSet(exerciseID: "squat", target: 2),
            PlannedSet(exerciseID: "squat", target: 2),
        ]
        let coord = SessionCoordinator(plan: plan)
        coord.start()
        XCTAssertEqual(coord.currentSetIndex, 0)

        for f in SquatFrames.reps(2) { coord.feed(f) }

        XCTAssertEqual(coord.currentSetIndex, 1)
        XCTAssertEqual(coord.phase, .resting)
    }

    func testFinishingLastRepSetCompletesSession() {
        let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "squat", target: 1)])
        coord.start()
        for f in SquatFrames.reps(1) { coord.feed(f) }
        XCTAssertEqual(coord.phase, .finished)
        XCTAssertEqual(coord.results.first?.completed, 1)
    }

    func testPlankSecondsGoalCompletesWhenHeldLongEnough() {
        let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "plank", target: 1)]) // 1 second
        coord.start()
        XCTAssertEqual(coord.goalUnit, .seconds)
        // 15 frames at 0.1s spacing => ~1.4s of valid hold, past the 1s target.
        var t = 0.0
        for _ in 0..<15 { coord.feed(plankFrame(t)); t += 0.1 }
        XCTAssertEqual(coord.phase, .finished)
        XCTAssertGreaterThanOrEqual(coord.results.first?.completed ?? 0, 1.0)
    }
}
