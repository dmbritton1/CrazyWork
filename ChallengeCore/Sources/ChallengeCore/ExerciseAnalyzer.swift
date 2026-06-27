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

/// Plank: a time-based hold. Counts seconds while the body is held *horizontal*
/// — the plank position — and pauses when you stand up or the pose is lost.
///
/// Earlier versions thresholded how *straight* the shoulder→hip→ankle line was
/// (≈180°). That needs all three joint groups detected at once (feet often leave
/// the frame in a plank) and "is this line straight" is a jittery signal, so the
/// clock never settled. Instead, mirror the rep counter's recipe — smooth one
/// stable angle and threshold it with hysteresis — but use the body's *tilt from
/// horizontal*. A plank is ~0°, standing is ~90°: a huge, jitter-proof gap. It
/// reads off whichever segment is visible (shoulder→ankle, else shoulder→hip),
/// so missing feet don't break it. Sag/pike is a non-blocking cue, the way the
/// pushup counts reps regardless of form.
public struct PlankAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "plank", displayName: "Plank", goalUnit: .seconds)
    private let form: FormEvaluator
    private let minConfidence: Double
    /// Tilt from horizontal (degrees) allowed to *enter* the hold.
    private let enterTilt: Double
    /// Looser tilt that *breaks* an active hold. The gap above `enterTilt` is the
    /// hysteresis margin, so a brief wobble can't stop the clock.
    private let breakTilt: Double
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private let smoothingWindow: Int
    private var tilt: MovingAverage
    private var holding = false
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(enterTilt: Double = 40, breakTilt: Double = 60,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        // FormEvaluator only supplies the sag/pike direction for the cue.
        self.form = FormEvaluator(config: FormConfig(strictness: .lenient, minConfidence: minConfidence))
        self.minConfidence = minConfidence
        self.enterTilt = enterTilt
        self.breakTilt = breakTilt
        self.smoothingWindow = smoothingWindow
        self.tilt = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), maxStep)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        guard let raw = bodyTilt(frame) else {
            // Can't even tell orientation: pause (keep accumulated time).
            holding = false
            return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: false, formCue: nil)
        }

        let smoothed = tilt.add(raw)
        // Hysteresis: once holding, stay until clearly upright; only enter when flat.
        holding = holding ? smoothed <= breakTilt : smoothed <= enterTilt

        var cue: String?
        if holding {
            heldSeconds += dt
            switch form.evaluate(frame).issue {  // non-blocking coaching
            case .sagging: cue = "Lift your hips"
            case .piking: cue = "Lower your hips"
            case nil: cue = nil
            }
        }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: true, formCue: cue)
    }

    /// Body tilt from horizontal in degrees (0 = flat plank, 90 = standing).
    /// Uses the widest reliably-detected segment so a missing ankle can't break
    /// it; `nil` only when fewer than two joint groups are visible.
    private func bodyTilt(_ frame: PoseFrame) -> Double? {
        let shoulder = midpoint(frame, .leftShoulder, .rightShoulder)
        let hip = midpoint(frame, .leftHip, .rightHip)
        let ankle = midpoint(frame, .leftAnkle, .rightAnkle)
        let segment: (Point2D, Point2D)?
        if let s = shoulder, let a = ankle { segment = (s, a) }       // widest span
        else if let s = shoulder, let h = hip { segment = (s, h) }    // feet out of frame
        else if let h = hip, let a = ankle { segment = (h, a) }       // head out of frame
        else { segment = nil }
        guard let (p, q) = segment else { return nil }
        return atan2(abs(q.y - p.y), abs(q.x - p.x)) * 180 / .pi
    }

    /// Average of two same-side joints when both clear the gate; otherwise the
    /// single available side; `nil` when neither is detected.
    private func midpoint(_ frame: PoseFrame, _ a: Joint, _ b: Joint) -> Point2D? {
        let pa = frame.point(a, minConfidence: minConfidence)
        let pb = frame.point(b, minConfidence: minConfidence)
        switch (pa, pb) {
        case let (p1?, p2?): return Point2D(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        case let (p1?, nil): return p1
        case let (nil, p2?): return p2
        case (nil, nil): return nil
        }
    }

    public mutating func reset() {
        tilt = MovingAverage(windowSize: smoothingWindow)
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
