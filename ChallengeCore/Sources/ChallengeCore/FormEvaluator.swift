import Foundation

/// How forgiving form checks are. Default lenient.
public enum Strictness: String, Sendable, Codable, CaseIterable {
    case lenient
    case moderate
    case strict

    /// Allowed body-line deviation from straight (180°), in degrees.
    var bodyLineTolerance: Double {
        switch self {
        case .lenient: return 20
        case .moderate: return 12
        case .strict: return 7
        }
    }
}

public struct FormConfig: Sendable, Equatable {
    public var strictness: Strictness
    public var minConfidence: Double

    public init(strictness: Strictness = .lenient, minConfidence: Double = 0.5) {
        self.strictness = strictness
        self.minConfidence = minConfidence
    }
}

/// What's wrong with the body line, if anything.
public enum FormIssue: String, Sendable, Equatable, Codable {
    case sagging   // hips dropped toward the floor
    case piking    // hips raised up
}

public struct FormEvaluation: Sendable, Equatable {
    /// `angle(shoulder, hip, ankle)` in degrees; `nil` when joints are missing.
    public var bodyLineAngle: Double?
    /// True when the body line is straight enough (or can't be judged).
    public var isAcceptable: Bool
    public var issue: FormIssue?
}

/// Evaluates pushup body line from a single frame.
///
/// **Orientation assumption:** the phone is placed for a side view with the
/// screen's y-axis vertical (Vision normalized coords, y-up). Sag vs pike is
/// decided by whether the hip sits below or above the shoulder→ankle line at the
/// hip's x — which is independent of which way the person faces.
public struct FormEvaluator: Sendable {
    private let config: FormConfig

    public init(config: FormConfig = FormConfig()) {
        self.config = config
    }

    public func evaluate(_ frame: PoseFrame) -> FormEvaluation {
        guard let shoulder = midpoint(frame, .leftShoulder, .rightShoulder),
              let hip = midpoint(frame, .leftHip, .rightHip),
              let ankle = midpoint(frame, .leftAnkle, .rightAnkle) else {
            // Can't judge -> don't punish the user for a detector gap.
            return FormEvaluation(bodyLineAngle: nil, isAcceptable: true, issue: nil)
        }

        let lineAngle = Geometry.angle(shoulder, hip, ankle)
        let deviation = 180 - lineAngle
        let acceptable = deviation <= config.strictness.bodyLineTolerance

        var issue: FormIssue?
        if !acceptable {
            issue = hipIsBelowLine(shoulder: shoulder, hip: hip, ankle: ankle) ? .sagging : .piking
        }

        return FormEvaluation(bodyLineAngle: lineAngle, isAcceptable: acceptable, issue: issue)
    }

    /// Is the hip lower (smaller y) than the shoulder→ankle line at the hip's x?
    private func hipIsBelowLine(shoulder: Point2D, hip: Point2D, ankle: Point2D) -> Bool {
        let dx = ankle.x - shoulder.x
        guard abs(dx) > 1e-9 else {
            // Body near-vertical in frame; fall back to comparing to shoulder.
            return hip.y < shoulder.y
        }
        let t = (hip.x - shoulder.x) / dx
        let lineY = shoulder.y + t * (ankle.y - shoulder.y)
        return hip.y < lineY
    }

    /// Average of two same-side joints when both clear the gate; otherwise
    /// whichever single side is available.
    private func midpoint(_ frame: PoseFrame, _ a: Joint, _ b: Joint) -> Point2D? {
        let pa = frame.point(a, minConfidence: config.minConfidence)
        let pb = frame.point(b, minConfidence: config.minConfidence)
        switch (pa, pb) {
        case let (p1?, p2?): return Point2D(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
        case let (p1?, nil): return p1
        case let (nil, p2?): return p2
        case (nil, nil): return nil
        }
    }
}
