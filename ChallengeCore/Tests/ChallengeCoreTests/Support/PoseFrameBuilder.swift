import Foundation
@testable import ChallengeCore

/// Builds PoseFrames for tests. Defaults every joint to confidence 1.
struct PoseFrameBuilder {
    var timestamp: TimeInterval = 0
    var joints: [JointName: Joint] = [:]

    mutating func set(_ name: JointName, _ x: Double, _ y: Double, confidence: Double = 1) {
        joints[name] = Joint(position: Point2D(x: x, y: y), confidence: confidence)
    }

    func build() -> PoseFrame { PoseFrame(timestamp: timestamp, joints: joints) }
}
