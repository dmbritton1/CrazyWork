public struct Joint: Equatable, Sendable {
    public var position: Point2D
    public var confidence: Double
    public init(position: Point2D, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}
