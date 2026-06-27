import Foundation
import ChallengeCore

/// Minimal frame builder for app-layer tests (mirrors the engine test helper).
struct PoseFrameBuilderShim {
    var timestamp: TimeInterval = 0
    private var joints: [JointName: Joint] = [:]

    mutating func knee(_ deg: Double) {
        joints[.leftKnee] = Joint(position: Point2D(x: 0, y: 0), confidence: 1)
        joints[.leftHip] = Joint(position: Point2D(x: 0, y: 1), confidence: 1)
        let rad = deg * .pi / 180
        joints[.leftAnkle] = Joint(position: Point2D(x: sin(rad), y: cos(rad)), confidence: 1)
        joints[.leftShoulder] = Joint(position: Point2D(x: 0, y: 2), confidence: 1)
    }

    func build() -> PoseFrame { PoseFrame(timestamp: timestamp, joints: joints) }
}
