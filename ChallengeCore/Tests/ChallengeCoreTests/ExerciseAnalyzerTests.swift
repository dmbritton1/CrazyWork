import Foundation
import Testing
@testable import ChallengeCore

@Suite("ExerciseAnalyzer — per-exercise wrappers over the shared RepCounter")
struct ExerciseAnalyzerTests {

    /// Frame whose averaged angle at vertex `b` equals `deg` on both sides.
    /// `b` at origin, `c` along +x, `a` rotated `deg°` away.
    private func angleFrame(_ deg: Double, t: TimeInterval,
                            left: (Joint, Joint, Joint), right: (Joint, Joint, Joint),
                            confidence: Double = 0.9) -> PoseFrame {
        let rad = deg * .pi / 180
        let a = Point2D(x: cos(rad), y: sin(rad))
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
        return PoseFrame(timestamp: t, joints: [
            left.0: jp(a), left.1: jp(b), left.2: jp(c),
            right.0: jp(a), right.1: jp(b), right.2: jp(c),
        ])
    }

    /// One deep down→up cycle, with enough frames to settle the default
    /// (window-5) smoother past the up/down thresholds.
    private func cycle(_ make: (Double, TimeInterval) -> PoseFrame, start: TimeInterval) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = start
        for _ in 0..<8 { frames.append(make(175, t)); t += 0.1 }   // top
        for _ in 0..<8 { frames.append(make(25, t));  t += 0.1 }   // bottom
        for _ in 0..<8 { frames.append(make(175, t)); t += 0.1 }   // back to top
        return frames
    }

    @Test("PushupAnalyzer counts a rep from elbow motion")
    func pushupCounts() {
        var a = PushupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftElbow, .leftWrist),
                            right: (.rightShoulder, .rightElbow, .rightWrist))
        }
        var last: AnalyzerResult?
        for f in cycle(make, start: 0) { last = a.process(f) }
        #expect(a.count == 1)
        #expect(last?.poseVisible == true)
    }

    @Test("SquatAnalyzer counts a rep from knee motion")
    func squatCounts() {
        var a = SquatAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftHip, .leftKnee, .leftAnkle),
                            right: (.rightHip, .rightKnee, .rightAnkle))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.count == 1)
    }

    @Test("registry returns fresh analyzers for known ids and nil otherwise")
    func registry() {
        #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.id == "pushup")
        #expect(ExerciseRegistry.makeAnalyzer(for: "squat")?.definition.id == "squat")
        #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
        #expect(Set(ExerciseRegistry.all.map(\.id)) == ["pushup", "squat"])
    }

    @Test("reset clears the count")
    func resets() {
        var a = PushupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftElbow, .leftWrist),
                            right: (.rightShoulder, .rightElbow, .rightWrist))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.count == 1)
        a.reset()
        #expect(a.count == 0)
    }
}
