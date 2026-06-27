import Foundation

/// What an exercise is measured in: countable reps, or seconds of holding.
public enum GoalUnit: String, Sendable, Equatable, Codable { case reps, seconds }

/// Static description of a selectable exercise: id, label, and its goal unit.
public struct ExerciseDefinition: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let goalUnit: GoalUnit

    public init(id: String, displayName: String, goalUnit: GoalUnit) {
        self.id = id
        self.displayName = displayName
        self.goalUnit = goalUnit
    }
}

/// What one processed frame produced. `progress` is in the exercise's goal unit
/// (reps so far, or seconds held). `didAdvance` is true on the frame a rep
/// completes (used for rep feedback); always false for time-based holds.
public struct AnalyzerResult: Sendable, Equatable {
    public var progress: Double
    public var didAdvance: Bool
    public var poseVisible: Bool
    public var formCue: String?

    public init(progress: Double, didAdvance: Bool, poseVisible: Bool, formCue: String?) {
        self.progress = progress
        self.didAdvance = didAdvance
        self.poseVisible = poseVisible
        self.formCue = formCue
    }
}

/// Per-exercise strategy (Approach B): each exercise is its own type. Rep-based
/// exercises wrap the shared `RepCounter`; time-based holds accumulate seconds.
public protocol ExerciseAnalyzer {
    var definition: ExerciseDefinition { get }
    var progress: Double { get }
    mutating func process(_ frame: PoseFrame) -> AnalyzerResult
    mutating func reset()
}

/// Push-ups: elbow angle drives reps; body-line (shoulder·hip·ankle) drives the
/// sag/pike form cue.
public struct PushupAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "pushup", displayName: "Push-up", goalUnit: .reps)
    private let config: RepCounterConfig
    private var counter: RepCounter
    private let form: FormEvaluator

    public var progress: Double { Double(counter.count) }

    public init(strictness: Strictness = .lenient, minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(minConfidence: minConfidence) // default = both elbows
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
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: cue)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Squats: knee angle (hip·knee·ankle, both legs averaged) drives reps. Form
/// coaching deferred.
public struct SquatAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "squat", displayName: "Squat", goalUnit: .reps)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftHip, .leftKnee, .leftAnkle),
                JointTriple(.rightHip, .rightKnee, .rightAnkle),
            ])
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Lunges: the more-bent knee drives reps (`.minimum` combination), so either
/// leg's dip counts and alternating legs just works. Form coaching deferred.
public struct LungeAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "lunge", displayName: "Lunge", goalUnit: .reps)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 160, downThreshold: 110, minRangeOfMotion: 40,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftHip, .leftKnee, .leftAnkle),
                JointTriple(.rightHip, .rightKnee, .rightAnkle),
            ],
            combination: .minimum)
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Plank: a time-based hold. Accumulates seconds only while a valid (straight)
/// body line is held; pauses when form breaks or the pose is lost.
public struct PlankAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "plank", displayName: "Plank", goalUnit: .seconds)
    private let form: FormEvaluator
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(strictness: Strictness = .lenient, minConfidence: Double = 0.5) {
        self.form = FormEvaluator(config: FormConfig(strictness: strictness, minConfidence: minConfidence))
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let eval = form.evaluate(frame)
        let visible = eval.bodyLineAngle != nil

        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), maxStep)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        var cue: String?
        if visible && eval.isAcceptable {
            heldSeconds += dt
        } else if visible {
            switch eval.issue {
            case .sagging: cue = "Lift your hips"
            case .piking: cue = "Lower your hips"
            case nil: cue = nil
            }
        }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: visible, formCue: cue)
    }

    public mutating func reset() {
        heldSeconds = 0
        lastTimestamp = nil
    }
}

/// Maps an exercise id to a fresh analyzer, and lists all selectable exercises.
public enum ExerciseRegistry {
    public static let all: [ExerciseDefinition] = [
        PushupAnalyzer().definition,
        SquatAnalyzer().definition,
        LungeAnalyzer().definition,
        PlankAnalyzer().definition,
    ]

    public static func makeAnalyzer(for id: String) -> (any ExerciseAnalyzer)? {
        switch id {
        case "pushup": return PushupAnalyzer()
        case "squat": return SquatAnalyzer()
        case "lunge": return LungeAnalyzer()
        case "plank": return PlankAnalyzer()
        default: return nil
        }
    }
}
