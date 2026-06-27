import Foundation
import Vision
import ChallengeCore

/// Boundary that converts Apple Vision observations into the pure
/// `ChallengeCore.PoseFrame` the engine consumes. No Vision type leaks past
/// here. Vision normalized points use a lower-left origin (y up), which matches
/// `FormEvaluator`'s orientation assumption — so we pass x/y straight through.
enum PoseMapping {
    static func poseFrame(from observation: HumanBodyPoseObservation,
                          timestamp: TimeInterval) -> PoseFrame {
        var joints: [ChallengeCore.Joint: JointPoint] = [:]
        for (visionName, joint) in observation.allJoints() {
            guard let mapped = map(visionName) else { continue }
            let location = joint.location  // NormalizedPoint, origin bottom-left
            joints[mapped] = JointPoint(
                location: Point2D(x: Double(location.x), y: Double(location.y)),
                confidence: Double(joint.confidence))
        }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }

    private static func map(_ name: HumanBodyPoseObservation.PoseJointName) -> ChallengeCore.Joint? {
        switch name {
        case .nose: return .nose
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        case .root: return .root
        default: return nil
        }
    }
}
