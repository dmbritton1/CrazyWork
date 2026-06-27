import XCTest
import CoreGraphics
import ChallengeCore
@testable import CrazyWork

final class VisionPoseMapperTests: XCTestCase {
    func testMapsRecognizedPointsToPoseFrame() {
        let points: [JointName: (CGPoint, Double)] = [
            .leftElbow: (CGPoint(x: 0.4, y: 0.6), 0.9),
            .leftWrist: (CGPoint(x: 0.4, y: 0.8), 0.2),
        ]
        let frame = VisionPoseMapper.makeFrame(from: points, timestamp: 1.5)

        XCTAssertEqual(frame.timestamp, 1.5)
        XCTAssertEqual(frame.point(.leftElbow), Point2D(x: 0.4, y: 0.6))
        XCTAssertEqual(frame.confidence(.leftElbow), 0.9, accuracy: 0.0001)
        XCTAssertEqual(frame.confidence(.leftWrist), 0.2, accuracy: 0.0001)
        XCTAssertNil(frame.joint(.rightAnkle))
    }
}
