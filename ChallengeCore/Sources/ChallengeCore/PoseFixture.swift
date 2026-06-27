import Foundation

/// A recorded (or hand-authored) session of pose frames, serialized to JSON so
/// the rep/form engine can be tested deterministically on the Mac — including
/// adversarial recordings (arm-waving, half-reps, occlusion).
///
/// Joints are keyed by `Joint.rawValue` strings so the JSON is human-readable
/// and easy to hand-edit.
public struct PoseFixture: Codable, Sendable, Equatable {
    public var name: String
    public var frames: [FixtureFrame]

    public init(name: String, frames: [FixtureFrame]) {
        self.name = name
        self.frames = frames
    }

    /// Build a fixture from live/synthetic frames (recording path).
    public init(name: String, poseFrames: [PoseFrame]) {
        self.name = name
        self.frames = poseFrames.map { frame in
            var joints: [String: JointPoint] = [:]
            for (joint, point) in frame.joints { joints[joint.rawValue] = point }
            return FixtureFrame(t: frame.timestamp, joints: joints)
        }
    }

    /// Convert to engine input. Unrecognized joint names are silently dropped so
    /// a typo or future-joint in a fixture never crashes a replay.
    public func poseFrames() -> [PoseFrame] {
        frames.map { f in
            var joints: [Joint: JointPoint] = [:]
            for (name, point) in f.joints {
                if let joint = Joint(rawValue: name) { joints[joint] = point }
            }
            return PoseFrame(timestamp: f.t, joints: joints)
        }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> PoseFixture {
        try JSONDecoder().decode(PoseFixture.self, from: data)
    }
}

public struct FixtureFrame: Codable, Sendable, Equatable {
    /// Timestamp in seconds.
    public var t: TimeInterval
    /// Joints keyed by `Joint.rawValue`.
    public var joints: [String: JointPoint]

    public init(t: TimeInterval, joints: [String: JointPoint]) {
        self.t = t
        self.joints = joints
    }
}

/// Replays a fixture through the rep engine.
public enum FixtureReplay {
    /// Final rep count after feeding every frame to a fresh `RepCounter`.
    public static func count(_ fixture: PoseFixture, config: RepCounterConfig = RepCounterConfig()) -> Int {
        var counter = RepCounter(config: config)
        for frame in fixture.poseFrames() { _ = counter.process(frame) }
        return counter.count
    }
}
