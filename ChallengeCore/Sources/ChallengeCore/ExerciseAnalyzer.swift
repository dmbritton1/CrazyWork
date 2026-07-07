import Foundation

/// What an exercise is measured in: countable reps, or seconds of holding.
public enum GoalUnit: String, Sendable, Equatable, Codable { case reps, seconds }

/// Static description of a selectable exercise: id, label, and its goal unit.
public struct ExerciseDefinition: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let goalUnit: GoalUnit
    /// Metabolic equivalent for calorie estimation.
    public let met: Double

    public init(id: String, displayName: String, goalUnit: GoalUnit, met: Double) {
        self.id = id
        self.displayName = displayName
        self.goalUnit = goalUnit
        self.met = met
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
    public let definition = ExerciseDefinition(id: "pushup", displayName: "Push-up", goalUnit: .reps, met: 3.8)
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
    public let definition = ExerciseDefinition(id: "squat", displayName: "Squat", goalUnit: .reps, met: 5.0)
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
    public let definition = ExerciseDefinition(id: "lunge", displayName: "Lunge", goalUnit: .reps, met: 4.0)
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

/// Average of two same-side joints when both clear the gate; otherwise the
/// single available side; `nil` when neither is detected. Shared by the
/// hold-style analyzers (plank, wall sit), which read the body as side-view
/// midlines rather than per-side triples.
func sideMidpoint(_ frame: PoseFrame, _ a: Joint, _ b: Joint, minConfidence: Double) -> Point2D? {
    let pa = frame.point(a, minConfidence: minConfidence)
    let pb = frame.point(b, minConfidence: minConfidence)
    switch (pa, pb) {
    case let (p1?, p2?): return Point2D(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    case let (p1?, nil): return p1
    case let (nil, p2?): return p2
    case (nil, nil): return nil
    }
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
/// so missing feet don't break it.
///
/// Being horizontal isn't enough on its own. Two ways to be horizontal that
/// aren't a plank, each with its own gate:
///
/// 1. **Lying flat on the floor** looks identical to a plank from a 2D side view
///    — same horizontal, straight body line. The real difference is that a plank
///    is *propped up on the arms*. So the clock requires an **arm-support** gate:
///    the shoulders must sit clearly above the forearms/hands (a steep arm
///    segment). Arms flat along the floor → not propped → no count.
/// 2. **Bad body line** — hips sagging toward the floor or piked up. A **form
///    gate** pauses the clock once the shoulder→hip→ankle line bends off straight
///    in either direction, and resumes when you fix it. The on-screen warning
///    ("Lift your hips" / "Lower your hips") shows exactly when this gate has
///    paused, so being warned means you are not being credited.
///
/// All three gates (orientation, arm-support, form) use the same smoothed +
/// hysteresis recipe as the rep counter, so none reintroduce single-frame flicker.
public struct PlankAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "plank", displayName: "Plank", goalUnit: .seconds, met: 3.3)
    private let form: FormEvaluator
    private let minConfidence: Double
    /// Tilt from horizontal (degrees) allowed to *enter* the hold.
    private let enterTilt: Double
    /// Looser tilt that *breaks* an active hold. The gap above `enterTilt` is the
    /// hysteresis margin, so a brief wobble can't stop the clock.
    private let breakTilt: Double
    /// Arm steepness (degrees from horizontal) at which the torso reads as
    /// *propped up* on the arms (enter), and the looser steepness that drops it.
    private let proppedEnter: Double
    private let proppedBreak: Double
    /// Body-line deviation from straight (degrees) at which the form gate *pauses*
    /// the clock (and warns), and the tighter deviation at which it *resumes*.
    private let formBreak: Double
    private let formResume: Double
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private let smoothingWindow: Int
    private var tilt: MovingAverage
    private var arm: MovingAverage
    private var line: MovingAverage
    private var holding = false
    private var propped = false
    private var formGood = true
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(enterTilt: Double = 40, breakTilt: Double = 60,
                proppedEnter: Double = 30, proppedBreak: Double = 20,
                formBreak: Double = 22, formResume: Double = 14,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        // FormEvaluator supplies the body-line angle (form gate) and, via a tight
        // tolerance, the sag/pike direction for the warning whenever the gate trips.
        self.form = FormEvaluator(config: FormConfig(strictness: .strict, minConfidence: minConfidence))
        self.minConfidence = minConfidence
        self.enterTilt = enterTilt
        self.breakTilt = breakTilt
        self.proppedEnter = proppedEnter
        self.proppedBreak = proppedBreak
        self.formBreak = formBreak
        self.formResume = formResume
        self.smoothingWindow = smoothingWindow
        self.tilt = MovingAverage(windowSize: smoothingWindow)
        self.arm = MovingAverage(windowSize: smoothingWindow)
        self.line = MovingAverage(windowSize: smoothingWindow)
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

        // Arm-support gate: a plank is propped on the arms (steep shoulder→hand
        // segment); lying flat has arms along the floor (~0°). Unjudgeable frames
        // (arms not detected) hold the last verdict; it defaults to false so a
        // never-established support won't count.
        if let armSteepness = armTilt(frame) {
            let a = arm.add(armSteepness)
            propped = propped ? a >= proppedBreak : a >= proppedEnter
        }

        // Form gate: a smoothed deviation of the shoulder→hip→ankle line off
        // straight pauses the clock in either direction (sag or pike). Unjudgeable
        // frames (e.g. feet out of view) hold the last verdict, which defaults to
        // good so missing feet still count.
        let eval = form.evaluate(frame)
        if let lineAngle = eval.bodyLineAngle {
            let dev = 180 - line.add(lineAngle)
            formGood = formGood ? dev <= formBreak : dev <= formResume
        }

        var cue: String?
        if holding {
            if propped && formGood {
                heldSeconds += dt          // good plank: count, no warning
            } else if propped {
                // Body line broke: warn and stop counting — warning ⇔ paused.
                switch eval.issue {
                case .sagging: cue = "Lift your hips"
                case .piking: cue = "Lower your hips"
                case nil: cue = nil
                }
            }
        }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false, poseVisible: true, formCue: cue)
    }

    /// Steepness (degrees from horizontal) of the arm propping the torso up:
    /// the steepest shoulder→hand or shoulder→elbow segment where the shoulder
    /// sits above the support. ~90° when stacked vertically (high plank), high
    /// for a forearm plank, ~0° when arms lie along the floor. `nil` when the
    /// shoulder or both supports are undetected; `0` when supports exist but none
    /// are below the shoulder (e.g. arms overhead while lying flat).
    private func armTilt(_ frame: PoseFrame) -> Double? {
        guard let shoulder = sideMidpoint(frame, .leftShoulder, .rightShoulder, minConfidence: minConfidence) else { return nil }
        let supports = [sideMidpoint(frame, .leftWrist, .rightWrist, minConfidence: minConfidence),
                        sideMidpoint(frame, .leftElbow, .rightElbow, minConfidence: minConfidence)].compactMap { $0 }
        guard !supports.isEmpty else { return nil }
        let steepnesses = supports.compactMap { s -> Double? in
            guard shoulder.y > s.y else { return nil }   // shoulder must be above the support
            return atan2(abs(shoulder.y - s.y), abs(shoulder.x - s.x)) * 180 / .pi
        }
        return steepnesses.max() ?? 0
    }

    /// Body tilt from horizontal in degrees (0 = flat plank, 90 = standing).
    /// Uses the widest reliably-detected segment so a missing ankle can't break
    /// it; `nil` only when fewer than two joint groups are visible.
    private func bodyTilt(_ frame: PoseFrame) -> Double? {
        let shoulder = sideMidpoint(frame, .leftShoulder, .rightShoulder, minConfidence: minConfidence)
        let hip = sideMidpoint(frame, .leftHip, .rightHip, minConfidence: minConfidence)
        let ankle = sideMidpoint(frame, .leftAnkle, .rightAnkle, minConfidence: minConfidence)
        let segment: (Point2D, Point2D)?
        if let s = shoulder, let a = ankle { segment = (s, a) }       // widest span
        else if let s = shoulder, let h = hip { segment = (s, h) }    // feet out of frame
        else if let h = hip, let a = ankle { segment = (h, a) }       // head out of frame
        else { segment = nil }
        guard let (p, q) = segment else { return nil }
        return atan2(abs(q.y - p.y), abs(q.x - p.x)) * 180 / .pi
    }

    public mutating func reset() {
        tilt = MovingAverage(windowSize: smoothingWindow)
        arm = MovingAverage(windowSize: smoothingWindow)
        line = MovingAverage(windowSize: smoothingWindow)
        holding = false
        propped = false
        formGood = true
        heldSeconds = 0
        lastTimestamp = nil
    }
}

/// Sit-ups: torso-flexion angle (shoulder·hip·knee, both sides averaged) drives
/// reps. Lying flat is extended; crunching up is bent. Form coaching deferred.
public struct SitupAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "situp", displayName: "Sit-up", goalUnit: .reps, met: 3.8)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 130, downThreshold: 90, minRangeOfMotion: 40,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
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

/// Glute bridges: hip-extension angle (shoulder·hip·knee, both sides averaged)
/// drives reps. Hips on the floor is bent; the bridge is extended. The range of
/// motion is narrow, so these thresholds are the on-device tuning knob. Form
/// coaching deferred.
public struct GluteBridgeAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "glutebridge", displayName: "Glute Bridge", goalUnit: .reps, met: 3.5)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 155, downThreshold: 130, minRangeOfMotion: 25,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
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

/// Mountain climbers: hip-flexion angle (shoulder·hip·knee), `.minimum`
/// combination so the driven knee owns the signal — each knee drive is one
/// down→up cycle, so alternating legs counts 1 per drive. `minAsymmetry`
/// rejects a symmetric both-knee tuck. No plank-orientation gate: the user
/// selected the exercise. Form coaching deferred.
public struct MountainClimberAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "mountainclimber", displayName: "Mountain Climber", goalUnit: .reps, met: 8.0)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 150, downThreshold: 110,
            // Climber cadence is the fastest in the app; this is the tuning knob.
            minRepDuration: 0.3,
            minRangeOfMotion: 35,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
            ],
            combination: .minimum,
            minAsymmetry: 30)
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Wall sit: a time-based hold, side-view. Counts seconds while the knees are
/// bent near 90° AND the torso is near vertical, pausing otherwise — the same
/// smoothed + hysteresis gate recipe as the plank, with the plank's per-frame
/// dt cap. The camera cannot see the wall, so a free-standing chair pose also
/// counts (same isometric work). No form cues.
public struct WallSitAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "wallsit", displayName: "Wall Sit", goalUnit: .seconds, met: 4.0)
    /// Knee angle band that *establishes* the hold, and the wider band that
    /// *keeps* it (the extra width is the hysteresis margin). Standing
    /// straightens past the top of the break band; sliding to the floor bends
    /// below the bottom.
    private let kneeEnter: ClosedRange<Double>
    private let kneeBreak: ClosedRange<Double>
    /// Torso tilt from vertical (degrees) allowed to enter / break the hold.
    private let torsoEnterTilt: Double
    private let torsoBreakTilt: Double
    private let minConfidence: Double
    private let smoothingWindow: Int
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private var kneeSmoother: MovingAverage
    private var torsoSmoother: MovingAverage
    /// Defaults false: a hold that was never established never counts.
    private var kneeHeld = false
    /// Defaults true: partial visibility doesn't rob credit once established.
    private var torsoUpright = true
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(kneeEnter: ClosedRange<Double> = 70...110,
                kneeBreak: ClosedRange<Double> = 55...125,
                torsoEnterTilt: Double = 20, torsoBreakTilt: Double = 35,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        self.kneeEnter = kneeEnter
        self.kneeBreak = kneeBreak
        self.torsoEnterTilt = torsoEnterTilt
        self.torsoBreakTilt = torsoBreakTilt
        self.smoothingWindow = smoothingWindow
        self.minConfidence = minConfidence
        self.kneeSmoother = MovingAverage(windowSize: smoothingWindow)
        self.torsoSmoother = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), maxStep)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        // Both gates hold their last verdict on unjudgeable frames.
        let kneeRaw = kneeAngle(frame)
        if let kneeRaw {
            let k = kneeSmoother.add(kneeRaw)
            kneeHeld = kneeHeld ? kneeBreak.contains(k) : kneeEnter.contains(k)
        }
        let torsoRaw = torsoTilt(frame)
        if let torsoRaw {
            let v = torsoSmoother.add(torsoRaw)
            torsoUpright = torsoUpright ? v <= torsoBreakTilt : v <= torsoEnterTilt
        }

        if kneeHeld && torsoUpright { heldSeconds += dt }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false,
                              poseVisible: kneeRaw != nil || torsoRaw != nil, formCue: nil)
    }

    /// Knee angle (hip·knee·ankle) read off the side-view midlines.
    private func kneeAngle(_ frame: PoseFrame) -> Double? {
        guard let hip = sideMidpoint(frame, .leftHip, .rightHip, minConfidence: minConfidence),
              let knee = sideMidpoint(frame, .leftKnee, .rightKnee, minConfidence: minConfidence),
              let ankle = sideMidpoint(frame, .leftAnkle, .rightAnkle, minConfidence: minConfidence) else { return nil }
        return Geometry.angle(hip, knee, ankle)
    }

    /// Torso tilt from *vertical* in degrees (0 = upright against the wall,
    /// 90 = horizontal). `nil` when shoulder or hip is undetected.
    private func torsoTilt(_ frame: PoseFrame) -> Double? {
        guard let shoulder = sideMidpoint(frame, .leftShoulder, .rightShoulder, minConfidence: minConfidence),
              let hip = sideMidpoint(frame, .leftHip, .rightHip, minConfidence: minConfidence) else { return nil }
        return atan2(abs(shoulder.x - hip.x), abs(shoulder.y - hip.y)) * 180 / .pi
    }

    public mutating func reset() {
        kneeSmoother = MovingAverage(windowSize: smoothingWindow)
        torsoSmoother = MovingAverage(windowSize: smoothingWindow)
        kneeHeld = false
        torsoUpright = true
        heldSeconds = 0
        lastTimestamp = nil
    }
}

/// Jumping jacks: the app's first front-facing exercise. Two smoothed signals —
/// arm raise (hip·shoulder·wrist, ~20° at the sides to ~170° overhead) and leg
/// spread (leftAnkle·root·rightAnkle, ~15° together to ~45° apart) — drive a
/// two-state machine. Both signals must clear a gate on the same smoothed frame
/// to change state, so arm-only half-jacks and out-of-sync legs never count;
/// the band between the open and closed thresholds is the hysteresis margin.
/// A closed → open → closed cycle is one rep, subject to a minimum cycle
/// duration measured from leaving `closed` to re-entering it. No form cues.
public struct JumpingJackAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "jumpingjack", displayName: "Jumping Jack", goalUnit: .reps, met: 8.0)

    private let armOpen: Double
    private let armClosed: Double
    private let legOpen: Double
    private let legClosed: Double
    private let minCycleDuration: TimeInterval
    private let smoothingWindow: Int
    private let minConfidence: Double

    private var armSmoother: MovingAverage
    private var legSmoother: MovingAverage
    /// Last smoothed values; held across unjudgeable frames so a brief joint
    /// dropout can't reset the cycle.
    private var lastArm: Double?
    private var lastLeg: Double?

    private enum State { case unknown, closed, open }
    private var state: State = .unknown
    /// Timestamp of the frame that left `closed` (entered `open`); nil outside
    /// a cycle, so a cycle that began mid-open never counts.
    private var cycleStart: TimeInterval?
    private var count = 0

    public var progress: Double { Double(count) }

    public init(armOpen: Double = 140, armClosed: Double = 60,
                legOpen: Double = 35, legClosed: Double = 20,
                minCycleDuration: TimeInterval = 0.35,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        self.armOpen = armOpen
        self.armClosed = armClosed
        self.legOpen = legOpen
        self.legClosed = legClosed
        self.minCycleDuration = minCycleDuration
        self.smoothingWindow = smoothingWindow
        self.minConfidence = minConfidence
        self.armSmoother = MovingAverage(windowSize: smoothingWindow)
        self.legSmoother = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let armRaw = armAngle(frame)
        let legRaw = legAngle(frame)
        if let armRaw { lastArm = armSmoother.add(armRaw) }
        if let legRaw { lastLeg = legSmoother.add(legRaw) }
        let visible = armRaw != nil || legRaw != nil

        // Until both signals have been seen once there is nothing to judge.
        guard let arm = lastArm, let leg = lastLeg else {
            return AnalyzerResult(progress: Double(count), didAdvance: false, poseVisible: visible, formCue: nil)
        }

        var didAdvance = false
        switch state {
        case .unknown:
            if arm <= armClosed && leg <= legClosed {
                state = .closed
            } else if arm >= armOpen && leg >= legOpen {
                state = .open   // started mid-jack; the first close won't count
            }
        case .closed:
            if arm >= armOpen && leg >= legOpen {
                state = .open
                cycleStart = frame.timestamp
            }
        case .open:
            if arm <= armClosed && leg <= legClosed {
                state = .closed
                if let start = cycleStart, frame.timestamp - start >= minCycleDuration {
                    count += 1
                    didAdvance = true
                }
                cycleStart = nil
            }
        }
        return AnalyzerResult(progress: Double(count), didAdvance: didAdvance, poseVisible: visible, formCue: nil)
    }

    /// Arm-raise angle (hip·shoulder·wrist, vertex at the shoulder), averaged
    /// over whichever sides are fully detected. `nil` when neither side is.
    private func armAngle(_ frame: PoseFrame) -> Double? {
        let sides: [(Joint, Joint, Joint)] = [
            (.leftHip, .leftShoulder, .leftWrist),
            (.rightHip, .rightShoulder, .rightWrist),
        ]
        let angles = sides.compactMap { side -> Double? in
            guard let a = frame.point(side.0, minConfidence: minConfidence),
                  let b = frame.point(side.1, minConfidence: minConfidence),
                  let c = frame.point(side.2, minConfidence: minConfidence) else { return nil }
            return Geometry.angle(a, b, c)
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }

    /// Leg-spread angle at the root between the two ankles. `nil` when any of
    /// the three joints is undetected — spread cannot be judged one-legged.
    private func legAngle(_ frame: PoseFrame) -> Double? {
        guard let root = frame.point(.root, minConfidence: minConfidence),
              let left = frame.point(.leftAnkle, minConfidence: minConfidence),
              let right = frame.point(.rightAnkle, minConfidence: minConfidence) else { return nil }
        return Geometry.angle(left, root, right)
    }

    public mutating func reset() {
        armSmoother = MovingAverage(windowSize: smoothingWindow)
        legSmoother = MovingAverage(windowSize: smoothingWindow)
        lastArm = nil
        lastLeg = nil
        state = .unknown
        cycleStart = nil
        count = 0
    }
}

/// Maps an exercise id to a fresh analyzer, and lists all selectable exercises.
public enum ExerciseRegistry {
    public static let all: [ExerciseDefinition] = [
        PushupAnalyzer().definition,
        SquatAnalyzer().definition,
        LungeAnalyzer().definition,
        PlankAnalyzer().definition,
        SitupAnalyzer().definition,
        GluteBridgeAnalyzer().definition,
    ]

    /// The definition for an exercise id, or `nil` if unknown.
    public static func definition(for id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }

    /// The display name for an exercise id, falling back to the raw id.
    public static func displayName(for id: String) -> String {
        definition(for: id)?.displayName ?? id
    }

    /// The goal unit for an exercise id, defaulting to `.reps` when unknown.
    public static func goalUnit(for id: String) -> GoalUnit {
        definition(for: id)?.goalUnit ?? .reps
    }

    public static func makeAnalyzer(for id: String) -> (any ExerciseAnalyzer)? {
        switch id {
        case "pushup": return PushupAnalyzer()
        case "squat": return SquatAnalyzer()
        case "lunge": return LungeAnalyzer()
        case "plank": return PlankAnalyzer()
        case "situp": return SitupAnalyzer()
        case "glutebridge": return GluteBridgeAnalyzer()
        default: return nil
        }
    }
}
