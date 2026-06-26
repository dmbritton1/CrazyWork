public enum ExerciseRegistry {
    /// Metadata for every selectable exercise (for menus etc.).
    public static let all: [ExerciseInfo] = [
        PushupAnalyzer().info,
        SquatAnalyzer().info,
    ]

    /// A fresh analyzer for the given id, or nil if unknown.
    public static func makeAnalyzer(for id: String) -> (any ExerciseAnalyzer)? {
        switch id {
        case "pushup": return PushupAnalyzer()
        case "squat": return SquatAnalyzer()
        default: return nil
        }
    }
}
