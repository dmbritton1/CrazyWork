import XCTest
@testable import ChallengeCore

final class PushupAnalyzerTests: XCTestCase {
    /// Builds a frame whose left-elbow angle equals `elbow` degrees and whose
    /// back (shoulder-hip-ankle) is straight unless `backAngle` is given.
    private func frame(elbow: Double, backAngle: Double = 180, t: TimeInterval) -> PoseFrame {
        var b = PoseFrameBuilder()
        b.timestamp = t
        // Place elbow at origin; shoulder straight up; wrist at `elbow` degrees from shoulder.
        b.set(.leftElbow, 0, 0)
        b.set(.leftShoulder, 0, 1)
        let rad = elbow * .pi / 180
        b.set(.leftWrist, sin(rad), cos(rad))
        // Back line: shoulder-hip-ankle. Hip at origin of that sub-angle.
        b.set(.leftHip, 5, 0)
        let backRad = backAngle * .pi / 180
        b.set(.leftAnkle, 5 + sin(backRad), -cos(backRad)) // shoulder already set above at (0,1)
        return b.build()
    }

    private func feed(_ a: inout PushupAnalyzer, _ frames: [PoseFrame]) -> [RepEvent] {
        var events: [RepEvent] = []
        for f in frames { events.append(contentsOf: a.process(f)) }
        return events
    }

    func testCountsCleanReps() {
        var a = PushupAnalyzer()
        let frames = [
            frame(elbow: 170, t: 0.0), frame(elbow: 70, t: 0.5), frame(elbow: 170, t: 1.0),
            frame(elbow: 170, t: 1.4), frame(elbow: 70, t: 1.9), frame(elbow: 170, t: 2.4),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.repIndex), [1, 2])
    }

    func testShallowRepFlagsDepth() {
        var a = PushupAnalyzer()
        let frames = [
            frame(elbow: 170, t: 0.0), frame(elbow: 100, t: 0.5), frame(elbow: 170, t: 1.0),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].findings.contains(.shallowDepth))
        XCTAssertLessThan(events[0].formScore, 1.0)
    }

    func testInfoIdIsPushup() {
        XCTAssertEqual(PushupAnalyzer().info.id, "pushup")
    }
}
