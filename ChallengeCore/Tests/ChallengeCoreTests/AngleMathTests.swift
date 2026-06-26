import XCTest
@testable import ChallengeCore

final class AngleMathTests: XCTestCase {
    func testRightAngle() {
        let vertex = Point2D(x: 0, y: 0)
        let a = Point2D(x: 1, y: 0)
        let b = Point2D(x: 0, y: 1)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: a, to: b), 90, accuracy: 0.001)
    }

    func testStraightLine() {
        let vertex = Point2D(x: 0, y: 0)
        let a = Point2D(x: -1, y: 0)
        let b = Point2D(x: 1, y: 0)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: a, to: b), 180, accuracy: 0.001)
    }

    func testZeroDegenerateReturnsZero() {
        let vertex = Point2D(x: 0, y: 0)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: vertex, to: Point2D(x: 1, y: 0)), 0, accuracy: 0.001)
    }
}
