import Foundation

/// Static description of a selectable exercise: its id, label, and the rep-counter
/// configuration (rep joints + thresholds) that drives detection.
public struct ExerciseDefinition: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let repConfig: RepCounterConfig

    public init(id: String, displayName: String, repConfig: RepCounterConfig) {
        self.id = id
        self.displayName = displayName
        self.repConfig = repConfig
    }
}

/// What one processed frame produced: live rep count/phase, whether a rep just
/// completed, whether the pose is visible, and a human-readable form cue (nil
/// when form is fine or not evaluated for this exercise).
public struct AnalyzerResult: Sendable, Equatable {
    public var count: Int
    public var phase: RepPhase
    public var didCompleteRep: Bool
    public var poseVisible: Bool
    public var formCue: String?

    public init(count: Int, phase: RepPhase, didCompleteRep: Bool, poseVisible: Bool, formCue: String?) {
        self.count = count
        self.phase = phase
        self.didCompleteRep = didCompleteRep
        self.poseVisible = poseVisible
        self.formCue = formCue
    }
}

/// Per-exercise strategy (Approach B): each exercise is its own type owning a
/// configured `RepCounter` and whatever form logic suits it. Counting itself
/// reuses the shared, proven `RepCounter` machinery.
public protocol ExerciseAnalyzer {
    var definition: ExerciseDefinition { get }
    var count: Int { get }
    mutating func process(_ frame: PoseFrame) -> AnalyzerResult
    mutating func reset()
}

/// Push-ups: elbow angle drives reps; body-line (shoulder·hip·ankle) drives the
/// sag/pike form cue.
public struct PushupAnalyzer: ExerciseAnalyzer {
    public let definition: ExerciseDefinition
    private var counter: RepCounter
    private let form: FormEvaluator

    public var count: Int { counter.count }

    public init(strictness: Strictness = .lenient, minConfidence: Double = 0.5) {
        let config = RepCounterConfig(minConfidence: minConfidence) // default = both elbows
        self.definition = ExerciseDefinition(id: "pushup", displayName: "Push-up", repConfig: config)
        self.counter = RepCounter(config: config)
        self.form = FormEvaluator(config: FormConfig(strictness: strictness, minConfidence: minConfidence))
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        let cue: String?
        switch form.evaluate(frame).issue {
        case .sagging: cue = "Lift your hips"
        case .piking: cue = "Lower your hips"
        case nil: cue = nil
        }
        return AnalyzerResult(count: update.count, phase: update.phase,
                              didCompleteRep: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: cue)
    }

    public mutating func reset() {
        counter = RepCounter(config: definition.repConfig)
    }
}

/// Squats: knee angle (hip·knee·ankle) drives reps. Form coaching is deferred
/// until tuned with recorded squat fixtures; counting uses the same proven
/// machinery as push-ups, just over the knee joints.
public struct SquatAnalyzer: ExerciseAnalyzer {
    public let definition: ExerciseDefinition
    private var counter: RepCounter

    public var count: Int { counter.count }

    public init(minConfidence: Double = 0.5) {
        let config = RepCounterConfig(
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftHip, .leftKnee, .leftAnkle),
                JointTriple(.rightHip, .rightKnee, .rightAnkle),
            ])
        self.definition = ExerciseDefinition(id: "squat", displayName: "Squat", repConfig: config)
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(count: update.count, phase: update.phase,
                              didCompleteRep: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() {
        counter = RepCounter(config: definition.repConfig)
    }
}

/// Maps an exercise id to a fresh analyzer, and lists all selectable exercises.
public enum ExerciseRegistry {
    public static let all: [ExerciseDefinition] = [
        PushupAnalyzer().definition,
        SquatAnalyzer().definition,
    ]

    public static func makeAnalyzer(for id: String) -> (any ExerciseAnalyzer)? {
        switch id {
        case "pushup": return PushupAnalyzer()
        case "squat": return SquatAnalyzer()
        default: return nil
        }
    }
}
