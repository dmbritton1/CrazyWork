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

    @AppStorage("skeletonColor") private var skeletonColor = SkeletonColor.green
    @AppStorage("skeletonThickness") private var skeletonThickness = SkeletonThickness.medium
    @AppStorage("skeletonShowJoints") private var showJoints = true
    @AppStorage("skeletonShowSkeleton") private var showSkeleton = true

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
                guard let frame, showSkeleton else { return }
                let stroke = skeletonColor.color

                for (a, b) in Self.bones {
                    guard let pa = point(a, in: frame, size: size),
                          let pb = point(b, in: frame, size: size) else { continue }
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    context.stroke(path, with: .color(stroke.opacity(0.85)),
                                   lineWidth: skeletonThickness.lineWidth)
                }

                if showJoints {
                    let r = skeletonThickness.dotRadius
                    for joint in ChallengeCore.Joint.allCases {
                        guard let p = point(joint, in: frame, size: size) else { continue }
                        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                        context.fill(dot, with: .color(stroke))
                    }
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
