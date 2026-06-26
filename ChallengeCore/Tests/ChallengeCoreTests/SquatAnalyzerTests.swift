import XCTest
@testable import ChallengeCore

final class SquatAnalyzerTests: XCTestCase {
    /// Frame whose knee angle equals `knee` degrees; torso vertical by default.
    private func frame(knee: Double, torsoLeanDeg: Double = 0, t: TimeInterval) -> PoseFrame {
        var b = PoseFrameBuilder()
        b.timestamp = t
        b.set(.leftKnee, 0, 0)
        b.set(.leftHip, 0, 1) // hip straight above knee
        let rad = knee * .pi / 180
        b.set(.leftAnkle, sin(rad), cos(rad)) // ankle at `knee` degrees from hip
        // Torso: shoulder relative to hip, leaned `torsoLeanDeg` from vertical.
        let lean = torsoLeanDeg * .pi / 180
        b.set(.leftShoulder, sin(lean), 1 + cos(lean))
        return b.build()
    }

    private func feed(_ a: inout SquatAnalyzer, _ frames: [PoseFrame]) -> [RepEvent] {
        var events: [RepEvent] = []
        for f in frames { events.append(contentsOf: a.process(f)) }
        return events
    }

    func testCountsCleanReps() {
        var a = SquatAnalyzer()
        let frames = [
            frame(knee: 170, t: 0.0), frame(knee: 80, t: 0.6), frame(knee: 170, t: 1.2),
            frame(knee: 170, t: 1.6), frame(knee: 80, t: 2.2), frame(knee: 170, t: 2.8),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 2)
    }

    func testExcessiveTorsoLeanFlagged() {
        var a = SquatAnalyzer()
        let frames = [
            frame(knee: 170, torsoLeanDeg: 0, t: 0.0),
            frame(knee: 80, torsoLeanDeg: 55, t: 0.6),  // big forward lean at the bottom
            frame(knee: 170, torsoLeanDeg: 0, t: 1.2),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].findings.contains(.torsoLean))
    }

    func testInfoIdIsSquat() {
        XCTAssertEqual(SquatAnalyzer().info.id, "squat")
    }
}
