public struct ExerciseInfo: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let trackedJoints: [JointName]
    public init(id: String, displayName: String, trackedJoints: [JointName]) {
        self.id = id
        self.displayName = displayName
        self.trackedJoints = trackedJoints
    }
}
