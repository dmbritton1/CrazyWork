import Foundation

/// A normalized 2D point. Origin/orientation are defined by the producer; the
/// pure core only does relative geometry, so the convention never leaks in here.
public struct Point2D: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The body joints we care about. Mirrors the subset of Apple Vision's
/// `DetectHumanBodyPoseRequest` joints relevant to pushups and squats. The iOS
/// layer maps Vision joints onto these at the boundary so no Vision type ever
/// reaches the pure core.
public enum Joint: String, Sendable, Codable, CaseIterable {
    case nose
    case neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case root
}

/// A single detected joint: where it is and how sure the detector is.
public struct JointPoint: Sendable, Hashable, Codable {
    public var location: Point2D
    /// Detector confidence in `0...1`.
    public var confidence: Double

    public init(location: Point2D, confidence: Double) {
        self.location = location
        self.confidence = confidence
    }
}

/// One frame of pose data: a timestamp plus whichever joints were detected.
/// This is the *only* input type the rep/form engine consumes — fully `Codable`
/// so real sessions can be recorded to JSON fixtures and replayed on the Mac.
public struct PoseFrame: Sendable, Hashable, Codable {
    /// Seconds. Monotonic within a session; absolute origin is irrelevant.
    public var timestamp: TimeInterval
    public var joints: [Joint: JointPoint]

    public init(timestamp: TimeInterval, joints: [Joint: JointPoint]) {
        self.timestamp = timestamp
        self.joints = joints
    }

    /// The joint's location, but only if it was detected at or above
    /// `minConfidence`. Returns `nil` otherwise so callers never count on a
    /// guessed joint.
    public func point(_ joint: Joint, minConfidence: Double) -> Point2D? {
        guard let jp = joints[joint], jp.confidence >= minConfidence else { return nil }
        return jp.location
    }
}
