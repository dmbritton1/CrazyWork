import Foundation
import Testing
@testable import ChallengeCore

@Suite("RepCounter — UP→DOWN→UP cycles with hysteresis & anti-cheat")
struct RepCounterTests {

    /// Builds a frame whose averaged elbow angle equals `elbow` degrees on both
    /// arms. Elbow at origin, wrist along +x, shoulder rotated `elbow°` away —
    /// so `angle(shoulder, elbow, wrist) == elbow`.
    private func frame(elbow: Double, t: TimeInterval, confidence: Double = 0.9) -> PoseFrame {
        let rad = elbow * .pi / 180
        let shoulder = Point2D(x: cos(rad), y: sin(rad))
        let elbowPt = Point2D(x: 0, y: 0)
        let wrist = Point2D(x: 1, y: 0)
        func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: jp(shoulder), .leftElbow: jp(elbowPt), .leftWrist: jp(wrist),
            .rightShoulder: jp(shoulder), .rightElbow: jp(elbowPt), .rightWrist: jp(wrist),
        ])
    }

    // Fast smoothing-off config so frame angle maps directly to threshold logic.
    private var config: RepCounterConfig {
        RepCounterConfig(upThreshold: 160, downThreshold: 90,
                         minRepDuration: 0.3, minRangeOfMotion: 40,
                         minConfidence: 0.5, smoothingWindow: 1)
    }

    @Test("a clean down-up cycle counts exactly one rep")
    func oneRep() {
        var rc = RepCounter(config: config)
        _ = rc.process(frame(elbow: 170, t: 0.0))   // UP
        _ = rc.process(frame(elbow: 80,  t: 0.5))   // DOWN
        let last = rc.process(frame(elbow: 170, t: 1.0)) // back UP -> rep
        #expect(rc.count == 1)
        #expect(last.didCompleteRep)
    }

    @Test("two cycles count two reps")
    func twoReps() {
        var rc = RepCounter(config: config)
        let angles: [(Double, TimeInterval)] = [
            (170, 0.0), (80, 0.5), (170, 1.0),
            (80, 1.5), (170, 2.0),
        ]
        for (a, t) in angles { _ = rc.process(frame(elbow: a, t: t)) }
        #expect(rc.count == 2)
    }

    @Test("jitter that never crosses the DOWN threshold counts nothing")
    func hysteresisNoFalsePositive() {
        var rc = RepCounter(config: config)
        let angles: [(Double, TimeInterval)] = [
            (165, 0.0), (158, 0.2), (170, 0.4), (155, 0.6), (168, 0.8),
        ]
        for (a, t) in angles { _ = rc.process(frame(elbow: a, t: t)) }
        #expect(rc.count == 0)
    }

    @Test("a half-rep that never reaches depth is rejected")
    func halfRepRejected() {
        var rc = RepCounter(config: config)
        _ = rc.process(frame(elbow: 170, t: 0.0))
        _ = rc.process(frame(elbow: 110, t: 0.5))   // not below 90
        _ = rc.process(frame(elbow: 170, t: 1.0))
        #expect(rc.count == 0)
    }

    @Test("a rep faster than the anti-bounce minimum is rejected")
    func tooFastRejected() {
        var rc = RepCounter(config: config)
        _ = rc.process(frame(elbow: 170, t: 0.00))
        _ = rc.process(frame(elbow: 80,  t: 0.05))
        _ = rc.process(frame(elbow: 170, t: 0.10))  // 0.05s down->up < 0.3
        #expect(rc.count == 0)
    }

    @Test("low-confidence frame reports pose not visible and counts nothing")
    func poseLost() {
        var rc = RepCounter(config: config)
        let u = rc.process(frame(elbow: 170, t: 0.0, confidence: 0.1))
        #expect(u.poseVisible == false)
        #expect(rc.count == 0)
    }

    @Test("pose loss mid-rep does not corrupt the count")
    func poseLossMidRep() {
        var rc = RepCounter(config: config)
        _ = rc.process(frame(elbow: 170, t: 0.0))
        _ = rc.process(frame(elbow: 80,  t: 0.5))
        _ = rc.process(frame(elbow: 85,  t: 0.7, confidence: 0.1)) // dropped
        let last = rc.process(frame(elbow: 170, t: 1.0))           // recovered UP
        #expect(rc.count == 1)
        #expect(last.didCompleteRep)
    }
}
