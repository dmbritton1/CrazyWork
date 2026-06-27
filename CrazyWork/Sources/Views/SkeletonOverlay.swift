import SwiftUI
import ChallengeCore

/// Draws the detected joints + bones over the camera feed. Joints come in
/// Vision's normalized, bottom-left space; `ViewportMapper` maps them through the
/// same aspect-fill transform the preview uses so the skeleton lands on the body
/// rather than drifting.
struct SkeletonOverlay: View {
    let frame: PoseFrame?
    /// Size of the upright camera image the joints were detected in.
    let imageSize: CGSize
    var minConfidence: Double = 0.3

    private static let bones: [(ChallengeCore.Joint, ChallengeCore.Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                guard let frame else { return }

                for (a, b) in Self.bones {
                    guard let pa = point(a, in: frame, size: size),
                          let pb = point(b, in: frame, size: size) else { continue }
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    context.stroke(path, with: .color(.green.opacity(0.8)), lineWidth: 3)
                }

                for joint in ChallengeCore.Joint.allCases {
                    guard let p = point(joint, in: frame, size: size) else { continue }
                    let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.yellow))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ joint: ChallengeCore.Joint, in frame: PoseFrame, size: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0,
              let p = frame.point(joint, minConfidence: minConfidence) else { return nil }
        let mapped = ViewportMapper.aspectFill(
            nx: p.x, ny: p.y,
            imageW: imageSize.width, imageH: imageSize.height,
            viewW: size.width, viewH: size.height)
        return CGPoint(x: mapped.x, y: mapped.y)
    }
}
