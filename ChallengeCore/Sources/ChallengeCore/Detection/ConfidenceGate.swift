public enum ConfidenceGate {
    public static func status(for frame: PoseFrame,
                              requiredJoints: [JointName],
                              minConfidence: Double) -> TrackingStatus {
        for name in requiredJoints where frame.joint(name) == nil {
            return .outOfFrame
        }
        for name in requiredJoints where frame.confidence(name) < minConfidence {
            return .lowConfidence
        }
        return .tracking
    }
}
