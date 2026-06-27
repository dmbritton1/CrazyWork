import Foundation

/// Three joints whose interior angle at `b` drives rep detection (e.g. the elbow
/// angle shoulder·elbow·wrist for a pushup, or the knee angle hip·knee·ankle for
/// a squat). The counter averages the angle over every triple that clears the
/// confidence gate, so passing both sides makes detection robust to one side
/// being occluded.
public struct JointTriple: Sendable, Equatable, Codable {
    public let a: Joint
    public let b: Joint
    public let c: Joint
    public init(_ a: Joint, _ b: Joint, _ c: Joint) {
        self.a = a
        self.b = b
        self.c = c
    }
}

/// How to combine the angles of multiple rep-joint triples into one rep angle.
/// `.average` suits symmetric moves (pushup/squat: both sides move together);
/// `.minimum` suits one-sided moves (lunge: track whichever knee is most bent).
public enum AngleCombination: Sendable, Equatable { case average, minimum }

/// Tunables for rep detection. Defaults match the pushup engine: UP > 160°,
/// DOWN < 90°, with a hysteresis gap between them so jitter can't double-count.
public struct RepCounterConfig: Sendable, Equatable {
    /// Rep angle above which the limb is considered extended (top of the rep).
    public var upThreshold: Double
    /// Rep angle below which the limb is considered bent (bottom of the rep).
    public var downThreshold: Double
    /// Minimum seconds for a down→up cycle; rejects teleport/bounce cheats.
    public var minRepDuration: TimeInterval
    /// Minimum peak-to-trough angle span within a rep; rejects shallow reps.
    public var minRangeOfMotion: Double
    /// Joints below this confidence are ignored.
    public var minConfidence: Double
    /// Frames of moving-average smoothing applied to the rep angle.
    public var smoothingWindow: Int
    /// The joint triples whose angle is combined to get the rep angle. Defaults
    /// to both elbows (pushup). For a squat, pass both knees.
    public var repJoints: [JointTriple]
    /// How the triple angles are combined into one rep angle.
    public var combination: AngleCombination
    /// Minimum degrees of difference required between the two `repJoints` angles
    /// at some point during the rep. `0` disables the check (symmetric moves like
    /// pushups/squats). A lunge sets this so a symmetric squat — where both knees
    /// bend together — is NOT counted as a lunge. Only applies when there are
    /// exactly two triples.
    public var minAsymmetry: Double

    public init(upThreshold: Double = 160,
                downThreshold: Double = 90,
                minRepDuration: TimeInterval = 0.4,
                minRangeOfMotion: Double = 40,
                minConfidence: Double = 0.5,
                smoothingWindow: Int = 5,
                repJoints: [JointTriple] = [
                    JointTriple(.leftShoulder, .leftElbow, .leftWrist),
                    JointTriple(.rightShoulder, .rightElbow, .rightWrist),
                ],
                combination: AngleCombination = .average,
                minAsymmetry: Double = 0) {
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.minRepDuration = minRepDuration
        self.minRangeOfMotion = minRangeOfMotion
        self.minConfidence = minConfidence
        self.smoothingWindow = smoothingWindow
        self.repJoints = repJoints
        self.combination = combination
        self.minAsymmetry = minAsymmetry
    }
}

/// Coarse phase of the movement.
public enum RepPhase: Sendable, Equatable {
    case unknown
    case up
    case down
}

/// Result of feeding one frame to the counter.
public struct RepUpdate: Sendable, Equatable {
    public var count: Int
    public var phase: RepPhase
    /// True only on the frame that completes a valid rep.
    public var didCompleteRep: Bool
    /// False when no rep joint cleared the confidence gate this frame.
    public var poseVisible: Bool
}

/// Counts reps from a stream of `PoseFrame`s. Pure value type: no I/O, no
/// Vision/AVFoundation — feed it frames (live or replayed from a fixture) and it
/// returns deterministic updates.
public struct RepCounter: Sendable {
    public private(set) var count = 0
    public private(set) var phase: RepPhase = .unknown

    private let config: RepCounterConfig
    private var smoother: MovingAverage

    // Per-rep tracking, valid while `phase == .down`.
    private var downStartTime: TimeInterval?
    private var minAngleInRep = Double.greatestFiniteMagnitude
    private var maxAngleInRep = -Double.greatestFiniteMagnitude
    private var maxAsymmetryInRep = 0.0

    public init(config: RepCounterConfig = RepCounterConfig()) {
        self.config = config
        self.smoother = MovingAverage(windowSize: config.smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> RepUpdate {
        let tripleAngles = config.repJoints.map { tripleAngle(frame, $0) }
        let available = tripleAngles.compactMap { $0 }
        guard let raw = combine(available) else {
            // Pose lost: hold state, count nothing. Recovery resumes cleanly.
            return RepUpdate(count: count, phase: phase, didCompleteRep: false, poseVisible: false)
        }

        let asymmetry = asymmetry(of: tripleAngles)
        let angle = smoother.add(raw)
        var didComplete = false

        switch phase {
        case .unknown:
            if angle > config.upThreshold {
                phase = .up
            } else if angle < config.downThreshold {
                // Started watching mid-bottom; wait for an UP before counting.
                phase = .down
                beginRep(at: frame.timestamp, angle: angle, asymmetry: asymmetry)
            }

        case .up:
            if angle < config.downThreshold {
                phase = .down
                beginRep(at: frame.timestamp, angle: angle, asymmetry: asymmetry)
            }

        case .down:
            track(angle: angle, asymmetry: asymmetry)
            if angle > config.upThreshold {
                if isValidRep(endingAt: frame.timestamp) {
                    count += 1
                    didComplete = true
                }
                phase = .up
            }
        }

        return RepUpdate(count: count, phase: phase, didCompleteRep: didComplete, poseVisible: true)
    }

    // MARK: - Rep bookkeeping

    private mutating func beginRep(at time: TimeInterval, angle: Double, asymmetry: Double?) {
        downStartTime = time
        minAngleInRep = angle
        maxAngleInRep = angle
        maxAsymmetryInRep = asymmetry ?? 0
    }

    private mutating func track(angle: Double, asymmetry: Double?) {
        minAngleInRep = min(minAngleInRep, angle)
        maxAngleInRep = max(maxAngleInRep, angle)
        if let asymmetry { maxAsymmetryInRep = max(maxAsymmetryInRep, asymmetry) }
    }

    private func isValidRep(endingAt time: TimeInterval) -> Bool {
        guard let start = downStartTime else { return false }
        let duration = time - start
        let rom = maxAngleInRep - minAngleInRep
        return duration >= config.minRepDuration
            && rom >= config.minRangeOfMotion
            && maxAsymmetryInRep >= config.minAsymmetry
    }

    // MARK: - Angle extraction

    /// Combine available triple angles into one rep angle. `nil` if none usable.
    private func combine(_ available: [Double]) -> Double? {
        guard !available.isEmpty else { return nil }
        switch config.combination {
        case .average: return available.reduce(0, +) / Double(available.count)
        case .minimum: return available.min()
        }
    }

    /// Absolute difference between the two triple angles, when exactly two are
    /// configured and both were detected this frame. `nil` otherwise — so a frame
    /// where one side is occluded doesn't falsely read as symmetric.
    private func asymmetry(of tripleAngles: [Double?]) -> Double? {
        guard tripleAngles.count == 2, let a = tripleAngles[0], let b = tripleAngles[1] else { return nil }
        return abs(a - b)
    }

    private func tripleAngle(_ frame: PoseFrame, _ t: JointTriple) -> Double? {
        guard let a = frame.point(t.a, minConfidence: config.minConfidence),
              let b = frame.point(t.b, minConfidence: config.minConfidence),
              let c = frame.point(t.c, minConfidence: config.minConfidence) else {
            return nil
        }
        return Geometry.angle(a, b, c)
    }
}
