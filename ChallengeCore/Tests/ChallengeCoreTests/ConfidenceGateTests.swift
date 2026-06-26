import XCTest
@testable import ChallengeCore

final class ConfidenceGateTests: XCTestCase {
    private let required: [JointName] = [.leftShoulder, .leftElbow, .leftWrist]

    func testAllConfidentIsTracking() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1); b.set(.leftWrist, 0, 2)
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .tracking)
    }

    func testMissingJointIsOutOfFrame() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1) // no wrist
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .outOfFrame)
    }

    func testLowConfidenceJointIsLowConfidence() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1)
        b.set(.leftWrist, 0, 2, confidence: 0.2)
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .lowConfidence)
    }
}
