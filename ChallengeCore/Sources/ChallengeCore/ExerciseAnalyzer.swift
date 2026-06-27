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
            combination: .minimum,
            // A lunge bends one knee far more than the other; require that gap so
            // a symmetric squat (both knees bending together) is not miscounted.
            minAsymmetry: 35)
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Plank: a time-based hold. Accumulates seconds while a roughly-straight body
/// line is held; pauses when form clearly breaks or the pose is lost.
///
/// Unlike the pushup coach (which grades a known-good plank tightly), this only
/// needs to know "is the user holding the position." A forearm plank rides a few
/// degrees off perfectly straight and the raw joints jitter, so a tight
/// single-frame gate flickers the clock on and off. Three things keep it steady:
/// the body-line angle is smoothed, the hold/break thresholds differ
/// (hysteresis, so brief wobble doesn't stop the clock), and the band is wider
/// than the pushup tolerance.
public struct PlankAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "plank", displayName: "Plank", goalUnit: .seconds)
    private let form: FormEvaluator
    /// Deviation from straight (180°) allowed to *enter* the hold.
    private let holdTolerance: Double
    /// Looser deviation that *breaks* an active hold. The gap above `holdTolerance`
    /// is the hysteresis margin.
    private let breakTolerance: Double
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private let smoothingWindow: Int
    private var angle: MovingAverage
    private var holding = false
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(holdTolerance: Double = 30, breakTolerance: Double = 45,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        // Lenient strictness here only supplies the sag/pike direction; the
        // hold decision uses our own wider, smoothed band below.
        self.form = FormEvaluator(config: FormConfig(strictness: .lenient, minConfidence: minConfidence))
        self.holdTolerance = holdTolerance
        self.breakTolerance = breakTolerance
        self.smoothingWindow = smoothingWindow
        self.angle = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let eval = form.evaluate(frame)
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), maxStep)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        guard let raw = eval.bodyLineAngle else {
            // Pose not judgeable: pause (keep accumulated time), don't reset.
            holding = false
            return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: false, formCue: nil)
        }

        let deviation = 180 - angle.add(raw)
        // Hysteresis: once holding, stay until clearly broken; only (re)enter tight.
        holding = holding ? deviation <= breakTolerance : deviation <= holdTolerance

        var cue: String?
        if holding {
            heldSeconds += dt
        } else {
            switch eval.issue {
            case .sagging: cue = "Lift your hips"
            case .piking: cue = "Lower your hips"
            case nil: cue = nil
            }
        }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: true, formCue: cue)
    }

    public mutating func reset() {
        angle = MovingAverage(windowSize: smoothingWindow)
        holding = false
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
