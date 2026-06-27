import Testing
@testable import ChallengeCore

@Suite("PoseFrame — confidence-gated joint access")
struct PoseFrameTests {

    private func frame() -> PoseFrame {
        PoseFrame(timestamp: 1.0, joints: [
            .leftShoulder: JointPoint(location: Point2D(x: 0.2, y: 0.5), confidence: 0.9),
            .leftElbow:    JointPoint(location: Point2D(x: 0.3, y: 0.5), confidence: 0.4),
        ])
    }

    @Test("returns point when confidence clears the gate")
    func aboveGate() {
        let p = frame().point(.leftShoulder, minConfidence: 0.5)
        #expect(p == Point2D(x: 0.2, y: 0.5))
    }

    @Test("returns nil when confidence is below the gate")
    func belowGate() {
        #expect(frame().point(.leftElbow, minConfidence: 0.5) == nil)
    }

    @Test("returns nil for an absent joint")
    func missing() {
        #expect(frame().point(.rightWrist, minConfidence: 0.5) == nil)
    }
}
