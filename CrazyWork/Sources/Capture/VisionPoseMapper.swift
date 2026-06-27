import Foundation
import CoreGraphics
import Vision
import ChallengeCore

enum VisionPoseMapper {
    /// Vision joint name -> engine joint name.
    static let jointTable: [VNHumanBodyPoseObservation.JointName: JointName] = [
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    /// Pure mapping used by both production code and tests.
    static func makeFrame(from points: [JointName: (CGPoint, Double)], timestamp: TimeInterval) -> PoseFrame {
        var joints: [JointName: ChallengeCore.Joint] = [:]
        for (name, value) in points {
            joints[name] = ChallengeCore.Joint(position: Point2D(x: Double(value.0.x), y: Double(value.0.y)),
                                               confidence: value.1)
        }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }

    /// Production entry point: convert a Vision observation into a PoseFrame.
    static func makeFrame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> PoseFrame {
        var points: [JointName: (CGPoint, Double)] = [:]
        for (visionName, engineName) in jointTable {
            if let p = try? observation.recognizedPoint(visionName), p.confidence > 0 {
                points[engineName] = (p.location, Double(p.confidence))
            }
        }
        return makeFrame(from: points, timestamp: timestamp)
    }
}
