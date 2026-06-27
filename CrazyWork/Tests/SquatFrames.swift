import Foundation
import ChallengeCore

/// Synthetic squat pose frames for app-layer tests. The knee angle (hip·knee·
/// ankle) on both legs equals `deg`. Enough frames per phase to settle the
/// default moving-average smoother past the up/down thresholds.
enum SquatFrames {
    static func frame(knee deg: Double, t: TimeInterval) -> PoseFrame {
        let rad = deg * .pi / 180
        let hip = Point2D(x: cos(rad), y: sin(rad))
        let knee = Point2D(x: 0, y: 0)
        let ankle = Point2D(x: 1, y: 0)
        func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: 0.9) }
        return PoseFrame(timestamp: t, joints: [
            .leftHip: jp(hip), .leftKnee: jp(knee), .leftAnkle: jp(ankle),
            .rightHip: jp(hip), .rightKnee: jp(knee), .rightAnkle: jp(ankle),
        ])
    }

    /// `n` complete down→up squat cycles (top, bottom, ... ending at the top).
    static func reps(_ n: Int) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<n {
            for _ in 0..<8 { frames.append(frame(knee: 175, t: t)); t += 0.1 }
            for _ in 0..<8 { frames.append(frame(knee: 25, t: t)); t += 0.1 }
        }
        for _ in 0..<8 { frames.append(frame(knee: 175, t: t)); t += 0.1 }
        return frames
    }
}
