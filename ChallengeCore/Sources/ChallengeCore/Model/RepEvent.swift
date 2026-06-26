public struct RepEvent: Equatable, Sendable {
    public let repIndex: Int
    public let formScore: Double      // 0...1
    public let findings: [Finding]
    public init(repIndex: Int, formScore: Double, findings: [Finding]) {
        self.repIndex = repIndex
        self.formScore = formScore
        self.findings = findings
    }
}
