import SwiftUI

struct ExerciseTile: View {
    let exerciseID: String
    var size: CGFloat = 48
    var body: some View {
        RoundedRectangle(cornerRadius: Radii.md).fill(Palette.surfaceCard)
            .frame(width: size, height: size)
            .overlay(ExercisePoseIcon(exerciseID: exerciseID)
                .frame(width: size * 0.78, height: size * 0.78))
    }
}

/// Each exercise icon is a tiny skeleton caught in that exercise's key pose —
/// the same stick figure the camera tracks live, so the icon vocabulary IS the
/// product. Poses are joint chains in a unit square, stroked like the pose
/// overlay: round-capped limbs, a solid head, knobs on the working joints, and
/// a faint ground line the figure works against.
struct ExercisePoseIcon: View {
    let exerciseID: String
    var color: Color = Palette.body

    var body: some View {
        Canvas { ctx, size in
            let pose = Self.pose(for: exerciseID)
            let s = min(size.width, size.height)
            let dx = (size.width - s) / 2, dy = (size.height - s) / 2
            func at(_ p: CGPoint) -> CGPoint { CGPoint(x: dx + p.x * s, y: dy + p.y * s) }
            let line = s * 0.075

            if let g = pose.groundY {
                var ground = Path()
                ground.move(to: at(CGPoint(x: 0.04, y: g)))
                ground.addLine(to: at(CGPoint(x: 0.96, y: g)))
                ctx.stroke(ground, with: .color(color.opacity(0.28)),
                           style: StrokeStyle(lineWidth: line * 0.6, lineCap: .round))
            }

            var limbs = Path()
            for chain in pose.chains {
                limbs.move(to: at(chain[0]))
                for p in chain.dropFirst() { limbs.addLine(to: at(p)) }
            }
            ctx.stroke(limbs, with: .color(color),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))

            let r = s * 0.085
            let head = at(pose.head)
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                     with: .color(color))

            let jr = line * 0.8
            for joint in pose.joints {
                let c = at(joint)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - jr, y: c.y - jr, width: jr * 2, height: jr * 2)),
                         with: .color(color))
            }
        }
    }

    struct Pose {
        let head: CGPoint
        let chains: [[CGPoint]]   // polylines: torso/legs/arms
        let joints: [CGPoint]     // knobs on the joints doing the work
        let groundY: CGFloat?
    }

    // All figures face right. Coordinates hand-tuned in a unit square.
    static func pose(for id: String) -> Pose {
        switch id {
        case "pushup":      // mid-rep: straight body on toes, arm strut to the floor
            return Pose(
                head: CGPoint(x: 0.88, y: 0.36),
                chains: [
                    [CGPoint(x: 0.74, y: 0.44), CGPoint(x: 0.44, y: 0.56),
                     CGPoint(x: 0.28, y: 0.62), CGPoint(x: 0.10, y: 0.79)],
                    [CGPoint(x: 0.74, y: 0.44), CGPoint(x: 0.72, y: 0.62), CGPoint(x: 0.71, y: 0.79)],
                ],
                joints: [CGPoint(x: 0.44, y: 0.56), CGPoint(x: 0.72, y: 0.62)],
                groundY: 0.80)
        case "squat":       // deep sit, arms counterbalanced forward
            return Pose(
                head: CGPoint(x: 0.47, y: 0.15),
                chains: [
                    [CGPoint(x: 0.44, y: 0.28), CGPoint(x: 0.36, y: 0.54),
                     CGPoint(x: 0.60, y: 0.60), CGPoint(x: 0.55, y: 0.83), CGPoint(x: 0.66, y: 0.83)],
                    [CGPoint(x: 0.44, y: 0.28), CGPoint(x: 0.70, y: 0.36)],
                ],
                joints: [CGPoint(x: 0.36, y: 0.54), CGPoint(x: 0.60, y: 0.60)],
                groundY: 0.84)
        case "lunge":       // split stance: front knee stacked, back leg driving
            return Pose(
                head: CGPoint(x: 0.52, y: 0.13),
                chains: [
                    [CGPoint(x: 0.50, y: 0.26), CGPoint(x: 0.46, y: 0.52)],
                    [CGPoint(x: 0.46, y: 0.52), CGPoint(x: 0.64, y: 0.58),
                     CGPoint(x: 0.64, y: 0.83), CGPoint(x: 0.73, y: 0.83)],
                    [CGPoint(x: 0.46, y: 0.52), CGPoint(x: 0.30, y: 0.64), CGPoint(x: 0.16, y: 0.83)],
                    [CGPoint(x: 0.50, y: 0.26), CGPoint(x: 0.53, y: 0.46)],
                ],
                joints: [CGPoint(x: 0.46, y: 0.52), CGPoint(x: 0.64, y: 0.58), CGPoint(x: 0.30, y: 0.64)],
                groundY: 0.84)
        case "plank":       // forearm plank: one straight line, elbow under shoulder
            return Pose(
                head: CGPoint(x: 0.88, y: 0.44),
                chains: [
                    [CGPoint(x: 0.74, y: 0.50), CGPoint(x: 0.46, y: 0.55),
                     CGPoint(x: 0.14, y: 0.62), CGPoint(x: 0.10, y: 0.73)],
                    [CGPoint(x: 0.74, y: 0.50), CGPoint(x: 0.74, y: 0.73), CGPoint(x: 0.88, y: 0.73)],
                ],
                joints: [CGPoint(x: 0.46, y: 0.55), CGPoint(x: 0.74, y: 0.73)],
                groundY: 0.74)
        case "situp":       // crunched up: torso curled toward bent knees
            return Pose(
                head: CGPoint(x: 0.80, y: 0.31),
                chains: [
                    [CGPoint(x: 0.74, y: 0.42), CGPoint(x: 0.55, y: 0.64)],
                    [CGPoint(x: 0.55, y: 0.64), CGPoint(x: 0.36, y: 0.44), CGPoint(x: 0.28, y: 0.75)],
                    [CGPoint(x: 0.74, y: 0.42), CGPoint(x: 0.52, y: 0.48)],
                ],
                joints: [CGPoint(x: 0.55, y: 0.64), CGPoint(x: 0.36, y: 0.44)],
                groundY: 0.76)
        case "glutebridge": // shoulders down, hips at the top of the arch
            return Pose(
                head: CGPoint(x: 0.87, y: 0.68),
                chains: [
                    [CGPoint(x: 0.74, y: 0.70), CGPoint(x: 0.48, y: 0.46),
                     CGPoint(x: 0.30, y: 0.44), CGPoint(x: 0.26, y: 0.75)],
                    [CGPoint(x: 0.74, y: 0.70), CGPoint(x: 0.56, y: 0.74)],
                ],
                joints: [CGPoint(x: 0.48, y: 0.46), CGPoint(x: 0.30, y: 0.44)],
                groundY: 0.76)
        case "jumpingjack": // front view mid-flight: arms overhead, legs apart
            return Pose(
                head: CGPoint(x: 0.50, y: 0.13),
                chains: [
                    [CGPoint(x: 0.50, y: 0.26), CGPoint(x: 0.50, y: 0.52)],
                    [CGPoint(x: 0.34, y: 0.10), CGPoint(x: 0.50, y: 0.28)],
                    [CGPoint(x: 0.66, y: 0.10), CGPoint(x: 0.50, y: 0.28)],
                    [CGPoint(x: 0.50, y: 0.52), CGPoint(x: 0.34, y: 0.83)],
                    [CGPoint(x: 0.50, y: 0.52), CGPoint(x: 0.66, y: 0.83)],
                ],
                joints: [CGPoint(x: 0.50, y: 0.28), CGPoint(x: 0.50, y: 0.52)],
                groundY: 0.84)
        case "mountainclimber": // plank base, one knee driven to the chest
            return Pose(
                head: CGPoint(x: 0.88, y: 0.40),
                chains: [
                    [CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.46, y: 0.54),
                     CGPoint(x: 0.24, y: 0.66), CGPoint(x: 0.10, y: 0.80)],
                    [CGPoint(x: 0.46, y: 0.54), CGPoint(x: 0.58, y: 0.66), CGPoint(x: 0.52, y: 0.80)],
                    [CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.73, y: 0.64), CGPoint(x: 0.72, y: 0.80)],
                ],
                joints: [CGPoint(x: 0.46, y: 0.54), CGPoint(x: 0.58, y: 0.66)],
                groundY: 0.81)
        case "wallsit":     // back on the wall line, thighs level, shins vertical
            return Pose(
                head: CGPoint(x: 0.42, y: 0.22),
                chains: [
                    [CGPoint(x: 0.30, y: 0.14), CGPoint(x: 0.30, y: 0.83)],   // the wall
                    [CGPoint(x: 0.38, y: 0.32), CGPoint(x: 0.36, y: 0.56),
                     CGPoint(x: 0.60, y: 0.58), CGPoint(x: 0.60, y: 0.83), CGPoint(x: 0.70, y: 0.83)],
                    [CGPoint(x: 0.38, y: 0.36), CGPoint(x: 0.48, y: 0.52)],
                ],
                joints: [CGPoint(x: 0.36, y: 0.56), CGPoint(x: 0.60, y: 0.58)],
                groundY: 0.84)
        default:            // generic standing figure
            return Pose(
                head: CGPoint(x: 0.50, y: 0.14),
                chains: [
                    [CGPoint(x: 0.50, y: 0.27), CGPoint(x: 0.50, y: 0.54)],
                    [CGPoint(x: 0.50, y: 0.54), CGPoint(x: 0.44, y: 0.83)],
                    [CGPoint(x: 0.50, y: 0.54), CGPoint(x: 0.56, y: 0.83)],
                    [CGPoint(x: 0.50, y: 0.30), CGPoint(x: 0.40, y: 0.48)],
                    [CGPoint(x: 0.50, y: 0.30), CGPoint(x: 0.60, y: 0.48)],
                ],
                joints: [CGPoint(x: 0.50, y: 0.54)],
                groundY: 0.84)
        }
    }
}
