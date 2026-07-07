import Foundation
import Testing
@testable import ChallengeCore

@Suite("ExerciseAnalyzer — per-exercise wrappers over the shared engine")
struct ExerciseAnalyzerTests {

    @Test("Every exercise carries a positive MET value")
    func everyExerciseHasPositiveMET() {
        for def in ExerciseRegistry.all {
            #expect(def.met > 0, "\(def.id) needs a MET value")
        }
    }

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

    /// Torsos with independent hip-flexion angles (for mountain climber).
    private func hipFrame(leftHip: Double, rightHip: Double, t: TimeInterval,
                          confidence: Double = 0.9) -> PoseFrame {
        func side(_ deg: Double) -> (Point2D, Point2D, Point2D) {
            let rad = deg * .pi / 180
            return (Point2D(x: cos(rad), y: sin(rad)), Point2D(x: 0, y: 0), Point2D(x: 1, y: 0))
        }
        let (ls, lh, lk) = side(leftHip)
        let (rs, rh, rk) = side(rightHip)
        func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(ls), .leftHip: jp(lh), .leftKnee: jp(lk),
            .rightShoulder: jp(rs), .rightHip: jp(rh), .rightKnee: jp(rk),
        ])
    }

    /// Side-view plank frame: body horizontal along x, propped on the arms
    /// (elbow/wrist below the shoulder); hip height controls sag/pike.
    private func plankFrame(hipY: Double, t: TimeInterval, confidence: Double = 0.9) -> PoseFrame {
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: confidence)
        }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(0, 1), .rightShoulder: jp(0, 1),
            .leftElbow: jp(0, 0.4), .rightElbow: jp(0, 0.4),
            .leftWrist: jp(0.3, 0.4), .rightWrist: jp(0.3, 0.4),
            .leftHip: jp(1, hipY), .rightHip: jp(1, hipY),
            .leftAnkle: jp(2, 1), .rightAnkle: jp(2, 1),
        ])
    }

    /// Standing/upright body: shoulders above hips above ankles at one x.
    private func uprightFrame(t: TimeInterval, confidence: Double = 0.9) -> PoseFrame {
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: confidence)
        }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(0, 2), .rightShoulder: jp(0, 2),
            .leftHip: jp(0, 1), .rightHip: jp(0, 1),
            .leftAnkle: jp(0, 0), .rightAnkle: jp(0, 0),
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

    @Test("SitupAnalyzer counts one rep from torso flexion")
    func situpCounts() {
        var a = SitupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("GluteBridgeAnalyzer counts one rep from hip extension")
    func gluteBridgeCounts() {
        var a = GluteBridgeAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("GluteBridgeAnalyzer ignores a shallow bridge that never reaches lockout")
    func gluteBridgeIgnoresShallow() {
        var a = GluteBridgeAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(make(120, t)); t += 0.1 } // on the floor (down)
        for _ in 0..<8 { frames.append(make(145, t)); t += 0.1 } // partial lift, below the 155 lockout
        for _ in 0..<8 { frames.append(make(120, t)); t += 0.1 } // back down
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 0)
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

    @Test("MountainClimberAnalyzer counts each knee drive as one rep")
    func mountainClimberCountsEachDrive() {
        var a = MountainClimberAnalyzer()
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // plank
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 90, rightHip: 175, t: t));  t += 0.1 } // left drive
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // back
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 90, t: t));  t += 0.1 } // right drive
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // back
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 2)
    }

    @Test("MountainClimberAnalyzer ignores a symmetric both-knee tuck")
    func mountainClimberIgnoresSymmetricTuck() {
        var a = MountainClimberAnalyzer()
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 90, rightHip: 90, t: t));   t += 0.1 } // both tuck
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 0)
    }

    @Test("MountainClimberAnalyzer ignores a shallow drive that never tucks")
    func mountainClimberIgnoresShallow() {
        var a = MountainClimberAnalyzer()
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 120, rightHip: 175, t: t)); t += 0.1 } // above the 110 tuck line
        for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
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

    @Test("PlankAnalyzer counts while horizontal, absorbs a dip, stops when upright")
    func plankHold() {
        var a = PlankAnalyzer()
        var t = 0.0
        var last: AnalyzerResult?
        // Horizontal hold accumulates time.
        for _ in 0..<8 { last = a.process(plankFrame(hipY: 1.0, t: t)); t += 0.1 }
        #expect(a.progress > 0)
        #expect(last?.poseVisible == true)
        #expect(last?.formCue == nil)

        // A single dip is absorbed by smoothing: still counting, no warning yet.
        let beforeDip = a.progress
        let dip = a.process(plankFrame(hipY: 0.2, t: t)); t += 0.1
        #expect(a.progress > beforeDip)
        #expect(dip.formCue == nil)

        // Standing upright is not a plank: the clock settles and stops.
        for _ in 0..<8 { _ = a.process(uprightFrame(t: t)); t += 0.1 } // transition out
        let afterStanding = a.progress
        for _ in 0..<5 { _ = a.process(uprightFrame(t: t)); t += 0.1 }
        #expect(abs(a.progress - afterStanding) < 1e-6) // fully stopped while upright
    }

    @Test("PlankAnalyzer stops counting when the body collapses to the floor")
    func plankCollapse() {
        var a = PlankAnalyzer()
        var t = 0.0
        for _ in 0..<8 { _ = a.process(plankFrame(hipY: 1.0, t: t)); t += 0.1 } // solid plank
        #expect(a.progress > 0)

        // Hips/thighs sink to the floor: still horizontal overall, but collapsed.
        for _ in 0..<4 { _ = a.process(plankFrame(hipY: 0.1, t: t)); t += 0.1 } // transition
        let afterCollapse = a.progress
        var last: AnalyzerResult?
        for _ in 0..<5 { last = a.process(plankFrame(hipY: 0.1, t: t)); t += 0.1 }
        #expect(abs(a.progress - afterCollapse) < 1e-6) // clock fully stopped
        #expect(last?.formCue == "Lift your hips")       // and tells you why
    }

    @Test("PlankAnalyzer still counts when the feet leave the frame")
    func plankWithoutAnkles() {
        var a = PlankAnalyzer()
        func torsoOnly(t: TimeInterval) -> PoseFrame {
            func jp(_ x: Double, _ y: Double) -> JointPoint {
                JointPoint(location: Point2D(x: x, y: y), confidence: 0.9)
            }
            // Shoulders, propping arms, and hips — feet out of frame.
            return PoseFrame(timestamp: t, joints: [
                .leftShoulder: jp(0, 1), .rightShoulder: jp(0, 1),
                .leftElbow: jp(0, 0.4), .rightElbow: jp(0, 0.4),
                .leftWrist: jp(0.3, 0.4), .rightWrist: jp(0.3, 0.4),
                .leftHip: jp(1, 1), .rightHip: jp(1, 1),
            ])
        }
        var t = 0.0
        var last: AnalyzerResult?
        for _ in 0..<6 { last = a.process(torsoOnly(t: t)); t += 0.1 }
        #expect(a.progress > 0)
        #expect(last?.poseVisible == true)
    }

    @Test("PlankAnalyzer does not count lying flat on the floor (arms not propping)")
    func plankLyingDown() {
        var a = PlankAnalyzer()
        func lyingFrame(t: TimeInterval) -> PoseFrame {
            func jp(_ x: Double, _ y: Double) -> JointPoint {
                JointPoint(location: Point2D(x: x, y: y), confidence: 0.9)
            }
            // Horizontal and straight, but arms lie along the floor (at shoulder
            // height) — nothing is propping the torso up. Not a plank.
            return PoseFrame(timestamp: t, joints: [
                .leftShoulder: jp(0, 1), .rightShoulder: jp(0, 1),
                .leftElbow: jp(0.3, 1), .rightElbow: jp(0.3, 1),
                .leftWrist: jp(0.6, 1), .rightWrist: jp(0.6, 1),
                .leftHip: jp(1, 1), .rightHip: jp(1, 1),
                .leftAnkle: jp(2, 1), .rightAnkle: jp(2, 1),
            ])
        }
        var t = 0.0
        for _ in 0..<10 { _ = a.process(lyingFrame(t: t)); t += 0.1 }
        #expect(a.progress == 0)
    }

    @Test("registry returns fresh analyzers for known ids and nil otherwise")
    func registry() {
        #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "plank")?.definition.goalUnit == .seconds)
        #expect(ExerciseRegistry.makeAnalyzer(for: "situp")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "glutebridge")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
        #expect(Set(ExerciseRegistry.all.map(\.id))
                == ["pushup", "squat", "lunge", "plank", "situp", "glutebridge"])
    }

    @Test("registry lookups resolve ids, with fallbacks for unknown ones")
    func registryLookups() {
        #expect(ExerciseRegistry.definition(for: "plank")?.id == "plank")
        #expect(ExerciseRegistry.definition(for: "moonwalk") == nil)
        #expect(ExerciseRegistry.displayName(for: "pushup") == "Push-up")
        #expect(ExerciseRegistry.displayName(for: "moonwalk") == "moonwalk") // falls back to the id
        #expect(ExerciseRegistry.goalUnit(for: "plank") == .seconds)
        #expect(ExerciseRegistry.goalUnit(for: "squat") == .reps)
        #expect(ExerciseRegistry.goalUnit(for: "moonwalk") == .reps)      // defaults to reps
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
