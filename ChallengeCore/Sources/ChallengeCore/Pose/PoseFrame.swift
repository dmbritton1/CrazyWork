import Foundation

public struct PoseFrame: Sendable {
    public var timestamp: TimeInterval
    public var joints: [JointName: Joint]

    public init(timestamp: TimeInterval, joints: [JointName: Joint]) {
        self.timestamp = timestamp
        self.joints = joints
    }

    public func joint(_ name: JointName) -> Joint? { joints[name] }
    public func point(_ name: JointName) -> Point2D? { joints[name]?.position }
    public func confidence(_ name: JointName) -> Double { joints[name]?.confidence ?? 0 }
}
