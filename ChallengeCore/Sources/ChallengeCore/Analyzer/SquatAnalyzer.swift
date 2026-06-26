import Foundation

public struct SquatAnalyzer: ExerciseAnalyzer {
    public let info = ExerciseInfo(
        id: "squat",
        displayName: "Squat",
        trackedJoints: [.leftHip, .leftKnee, .leftAnkle, .leftShoulder,
                        .rightHip, .rightKnee, .rightAnkle, .rightShoulder]
    )

    public private(set) var status: TrackingStatus = .outOfFrame

    private var detector = HysteresisRepDetector(downThreshold: 110, upThreshold: 160, minRepDuration: 0.3)
    private let depthTarget: Double = 90        // thigh ~parallel
    private let torsoLeanTolerance: Double = 45  // degrees from vertical
    private let minConfidence: Double = 0.3

    private var repCount = 0
    private var minKneeThisRep = Double.greatestFiniteMagnitude
    private var worstTorsoLeanThisRep = 0.0

    public init() {}

    public mutating func process(_ frame: PoseFrame) -> [RepEvent] {
        guard let knee = bestKneeAngle(frame) else {
            status = .outOfFrame
            return []
        }
        status = ConfidenceGate.status(
            for: frame,
            requiredJoints: [.leftHip, .leftKnee, .leftAnkle],
            minConfidence: minConfidence
        )
        guard status == .tracking else { return [] }

        minKneeThisRep = min(minKneeThisRep, knee)
        if let lean = torsoLean(frame) {
            worstTorsoLeanThisRep = max(worstTorsoLeanThisRep, lean)
        }

        guard detector.update(angle: knee, timestamp: frame.timestamp) else { return [] }

        repCount += 1
        let event = grade(repIndex: repCount)
        minKneeThisRep = .greatestFiniteMagnitude
        worstTorsoLeanThisRep = 0
        return [event]
    }

    public mutating func reset() {
        detector.reset()
        status = .outOfFrame
        repCount = 0
        minKneeThisRep = .greatestFiniteMagnitude
        worstTorsoLeanThisRep = 0
    }

    private func grade(repIndex: Int) -> RepEvent {
        var findings: [Finding] = []
        var score = 1.0
        if minKneeThisRep > depthTarget {
            findings.append(.shallowDepth)
            let shortBy = min(minKneeThisRep - depthTarget, 40)
            score -= 0.5 * (shortBy / 40)
        }
        if worstTorsoLeanThisRep > torsoLeanTolerance {
            findings.append(.torsoLean)
            score -= 0.3
        }
        return RepEvent(repIndex: repIndex, formScore: max(0, score), findings: findings)
    }

    private func bestKneeAngle(_ f: PoseFrame) -> Double? {
        let left = kneeAngle(f, .leftHip, .leftKnee, .leftAnkle)
        let right = kneeAngle(f, .rightHip, .rightKnee, .rightAnkle)
        switch (left, right) {
        case let (l?, r?): return f.confidence(.leftKnee) >= f.confidence(.rightKnee) ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func kneeAngle(_ f: PoseFrame, _ h: JointName, _ k: JointName, _ a: JointName) -> Double? {
        guard let hp = f.point(h), let kp = f.point(k), let ap = f.point(a) else { return nil }
        return AngleMath.angle(at: kp, from: hp, to: ap)
    }

    /// Angle of the shoulder->hip torso vector away from vertical, in degrees.
    private func torsoLean(_ f: PoseFrame) -> Double? {
        guard let s = f.point(.leftShoulder), let h = f.point(.leftHip) else { return nil }
        let dx = s.x - h.x
        let dy = s.y - h.y
        let mag = (dx * dx + dy * dy).squareRoot()
        guard mag > 0 else { return 0 }
        let cosine = min(1, max(-1, dy / mag))
        return acos(cosine) * 180 / .pi
    }
}
