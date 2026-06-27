import SwiftUI
import ChallengeCore

/// Draws joint dots from the latest PoseFrame. Coordinates are normalized (0...1).
struct SkeletonOverlay: View {
    let joints: [JointName: Joint]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(joints.keys), id: \.self) { name in
                if let j = joints[name] {
                    Circle()
                        .fill(j.confidence > 0.3 ? Color.green : Color.yellow)
                        .frame(width: 10, height: 10)
                        .position(x: j.position.x * geo.size.width,
                                  y: (1 - j.position.y) * geo.size.height) // Vision y is bottom-up
                }
            }
        }
        .allowsHitTesting(false)
    }
}
