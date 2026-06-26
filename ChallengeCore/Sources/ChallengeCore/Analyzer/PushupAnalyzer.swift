import Foundation

public struct PushupAnalyzer: ExerciseAnalyzer {
    public let info = ExerciseInfo(
        id: "pushup",
        displayName: "Push-up",
        trackedJoints: [.leftShoulder, .leftElbow, .leftWrist,
                        .rightShoulder, .rightElbow, .rightWrist,
                        .leftHip, .leftAnkle]
    )

    public private(set) var status: TrackingStatus = .outOfFrame

    private var detector = HysteresisRepDetector(downThreshold: 110, upThreshold: 160, minRepDuration: 0.3)
    private let depthTarget: Double = 90
    private let backStraightTolerance: Double = 25 // degrees from 180
    private let minConfidence: Double = 0.3

    private var repCount = 0
    private var minElbowThisRep = Double.greatestFiniteMagnitude
    private var worstBackDeviationThisRep = 0.0

    public init() {}

    public mutating func process(_ frame: PoseFrame) -> [RepEvent] {
        guard let elbow = bestElbowAngle(frame) else {
            status = .outOfFrame
            return []
        }
        status = ConfidenceGate.status(
            for: frame,
            requiredJoints: [.leftShoulder, .leftElbow, .leftWrist],
            minConfidence: minConfidence
        )

        minElbowThisRep = min(minElbowThisRep, elbow)
        if let back = backAngle(frame) {
            worstBackDeviationThisRep = max(worstBackDeviationThisRep, abs(180 - back))
        }

        guard detector.update(angle: elbow, timestamp: frame.timestamp) else { return [] }

        repCount += 1
        let event = grade(repIndex: repCount)
        minElbowThisRep = .greatestFiniteMagnitude
        worstBackDeviationThisRep = 0
        return [event]
    }

    public mutating func reset() {
        detector.reset()
        status = .outOfFrame
        repCount = 0
        minElbowThisRep = .greatestFiniteMagnitude
        worstBackDeviationThisRep = 0
    }

    private func grade(repIndex: Int) -> RepEvent {
        var findings: [Finding] = []
        var score = 1.0

        if minElbowThisRep > depthTarget {
            findings.append(.shallowDepth)
            let shortBy = min(minElbowThisRep - depthTarget, 40)
            score -= 0.5 * (shortBy / 40)
        }
        if worstBackDeviationThisRep > backStraightTolerance {
            findings.append(.backNotStraight)
            score -= 0.3
        }
        return RepEvent(repIndex: repIndex, formScore: max(0, score), findings: findings)
    }

    private func bestElbowAngle(_ frame: PoseFrame) -> Double? {
        let left = elbowAngle(frame, .leftShoulder, .leftElbow, .leftWrist)
        let right = elbowAngle(frame, .rightShoulder, .rightElbow, .rightWrist)
        switch (left, right) {
        case let (l?, r?): return frame.confidence(.leftElbow) >= frame.confidence(.rightElbow) ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func elbowAngle(_ f: PoseFrame, _ s: JointName, _ e: JointName, _ w: JointName) -> Double? {
        guard let sp = f.point(s), let ep = f.point(e), let wp = f.point(w) else { return nil }
        return AngleMath.angle(at: ep, from: sp, to: wp)
    }

    private func backAngle(_ f: PoseFrame) -> Double? {
        guard let s = f.point(.leftShoulder), let h = f.point(.leftHip), let a = f.point(.leftAnkle) else { return nil }
        return AngleMath.angle(at: h, from: s, to: a)
    }
}
