import Foundation
import Testing
@testable import ChallengeCore

@Suite("Fixture replay — record to JSON, replay deterministically")
struct FixtureReplayTests {

    private func armFrame(elbow: Double, t: TimeInterval) -> PoseFrame {
        let rad = elbow * .pi / 180
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: 0.9)
        }
        let s = jp(cos(rad), sin(rad)), e = jp(0, 0), w = jp(1, 0)
        return PoseFrame(timestamp: t, joints: [
            .leftShoulder: s, .leftElbow: e, .leftWrist: w,
            .rightShoulder: s, .rightElbow: e, .rightWrist: w,
        ])
    }

    private var fastConfig: RepCounterConfig {
        RepCounterConfig(upThreshold: 160, downThreshold: 90,
                         minRepDuration: 0.3, minRangeOfMotion: 40,
                         minConfidence: 0.5, smoothingWindow: 1)
    }

    @Test("a recorded fixture round-trips through JSON unchanged")
    func roundTrip() throws {
        let frames = [armFrame(elbow: 170, t: 0), armFrame(elbow: 80, t: 0.5)]
        let original = PoseFixture(name: "rt", poseFrames: frames)
        let data = try original.jsonData()
        let decoded = try PoseFixture.decode(from: data)
        #expect(decoded == original)
    }

    @Test("replaying a recorded 2-rep fixture counts two reps")
    func replayCounts() throws {
        let frames = [
            armFrame(elbow: 170, t: 0.0), armFrame(elbow: 80, t: 0.5),
            armFrame(elbow: 170, t: 1.0), armFrame(elbow: 80, t: 1.5),
            armFrame(elbow: 170, t: 2.0),
        ]
        let fixture = PoseFixture(name: "two_reps", poseFrames: frames)
        let decoded = try PoseFixture.decode(from: fixture.jsonData())
        #expect(FixtureReplay.count(decoded, config: fastConfig) == 2)
    }

    @Test("unknown joint names in a fixture are ignored, not fatal")
    func ignoresUnknownJoints() throws {
        let json = """
        {"name":"junk","frames":[{"t":0,"joints":{"martian":{"location":{"x":0,"y":0},"confidence":0.9}}}]}
        """
        let fixture = try PoseFixture.decode(from: Data(json.utf8))
        let poseFrames = fixture.poseFrames()
        #expect(poseFrames.count == 1)
        #expect(poseFrames[0].joints.isEmpty)
    }
}
