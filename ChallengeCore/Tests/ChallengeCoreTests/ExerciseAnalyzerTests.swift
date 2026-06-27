import Foundation
import Testing
@testable import ChallengeCore

@Suite("ExerciseAnalyzer — per-exercise wrappers over the shared engine")
struct ExerciseAnalyzerTests {

    /// Frame whose angle at vertex `b` equals `deg` on both sides.
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

    /// Legs with independent knee angles (for lunge / minimum-combination).
    private func legFrame(leftKnee: Double, rightKnee: Double, t: TimeInterval,
                          confidence: Double = 0.9) -> PoseFrame {
        func leg(_ deg: Double) -> (Point2D, Point2D, Point2D) {
            let rad = deg * .pi / 180
            return (Point2D(x: cos(rad), y: sin(rad)), Point2D(x: 0, y: 0), Point2D(x: 1, y: 0))
        }
        let (lh, lk, la) = leg(leftKnee)
        let (rh, rk, ra) = leg(rightKnee)
        func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
        return PoseFrame(timestamp: t, joints: [
            .leftHip: jp(lh), .leftKnee: jp(lk), .leftAnkle: jp(la),
            .rightHip: jp(rh), .rightKnee: jp(rk), .rightAnkle: jp(ra),
        ])
    }

    /// Side-view plank frame; hip height controls sag/pike.
    private func plankFrame(hipY: Double, t: TimeInterval, confidence: Double = 0.9) -> PoseFrame {
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: confidence)
        }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(0, 1), .rightShoulder: jp(0, 1),
            .leftHip: jp(1, hipY), .rightHip: jp(1, hipY),
            .leftAnkle: jp(2, 1), .rightAnkle: jp(2, 1),
        ])
    }

    /// One deep down→up cycle, enough frames to settle the window-5 smoother.
    private func cycle(_ make: (Double, TimeInterval) -> PoseFrame, start: TimeInterval) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = start
        for _ in 0..<8 { frames.append(make(175, t)); t += 0.1 }
        for _ in 0..<8 { frames.append(make(25, t));  t += 0.1 }
        for _ in 0..<8 { frames.append(make(175, t)); t += 0.1 }
        return frames
    }

    @Test("PushupAnalyzer reports one rep of progress from elbow motion")
    func pushupCounts() {
        var a = PushupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftElbow, .leftWrist),
                            right: (.rightShoulder, .rightElbow, .rightWrist))
        }
        var last: AnalyzerResult?
        for f in cycle(make, start: 0) { last = a.process(f) }
        #expect(a.progress == 1)
        #expect(last?.poseVisible == true)
    }

    @Test("SquatAnalyzer reports one rep from knee motion")
    func squatCounts() {
        var a = SquatAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftHip, .leftKnee, .leftAnkle),
                            right: (.rightHip, .rightKnee, .rightAnkle))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("LungeAnalyzer counts a one-legged dip (minimum combination)")
    func lungeCounts() {
        var a = LungeAnalyzer()
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 175, rightKnee: 180, t: t)); t += 0.1 }
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 25, rightKnee: 180, t: t));  t += 0.1 }
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 175, rightKnee: 180, t: t)); t += 0.1 }
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("LungeAnalyzer ignores a symmetric squat (both knees bending together)")
    func lungeIgnoresSquat() {
        var a = LungeAnalyzer()
        var frames: [PoseFrame] = []
        var t = 0.0
        // Both knees bend together -> a squat, not a lunge.
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 175, rightKnee: 175, t: t)); t += 0.1 }
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 25, rightKnee: 25, t: t));   t += 0.1 }
        for _ in 0..<8 { frames.append(legFrame(leftKnee: 175, rightKnee: 175, t: t)); t += 0.1 }
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 0)
    }

    @Test("minimum combination tracks the most-bent joint, not the average")
    func minimumCombination() {
        let config = RepCounterConfig(upThreshold: 160, downThreshold: 90,
                                      minRepDuration: 0.3, minRangeOfMotion: 40,
                                      minConfidence: 0.5, smoothingWindow: 1,
                                      repJoints: [JointTriple(.leftHip, .leftKnee, .leftAnkle),
                                                  JointTriple(.rightHip, .rightKnee, .rightAnkle)],
                                      combination: .minimum)
        var rc = RepCounter(config: config)
        _ = rc.process(legFrame(leftKnee: 170, rightKnee: 180, t: 0.0)) // up
        _ = rc.process(legFrame(leftKnee: 80, rightKnee: 180, t: 0.5))  // down (min=80)
        let last = rc.process(legFrame(leftKnee: 170, rightKnee: 180, t: 1.0)) // up -> rep
        #expect(rc.count == 1)
        #expect(last.didCompleteRep)
    }

    @Test("PlankAnalyzer accumulates time only while the body line is held")
    func plankHold() {
        var a = PlankAnalyzer()
        var t = 0.0
        var last: AnalyzerResult?
        for _ in 0..<5 { last = a.process(plankFrame(hipY: 1.0, t: t)); t += 0.1 } // ~0.4s held
        #expect(abs(a.progress - 0.4) < 1e-6)
        #expect(last?.poseVisible == true)

        let sag = a.process(plankFrame(hipY: 0.2, t: t)); t += 0.1            // breaks form
        #expect(abs(a.progress - 0.4) < 1e-6)                                  // no time added
        #expect(sag.formCue == "Lift your hips")

        let recovered = a.process(plankFrame(hipY: 1.0, t: t))                 // resumes
        #expect(a.progress > 0.4)
        #expect(recovered.formCue == nil)
    }

    @Test("registry returns fresh analyzers for known ids and nil otherwise")
    func registry() {
        #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "plank")?.definition.goalUnit == .seconds)
        #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
        #expect(Set(ExerciseRegistry.all.map(\.id)) == ["pushup", "squat", "lunge", "plank"])
    }

    @Test("reset clears progress")
    func resets() {
        var a = PushupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftElbow, .leftWrist),
                            right: (.rightShoulder, .rightElbow, .rightWrist))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
        a.reset()
        #expect(a.progress == 0)
    }
}
