import Testing
@testable import ChallengeCore

@Suite("Geometry.angle — interior angle at vertex B for A-B-C")
struct GeometryTests {

    @Test("right angle is 90 degrees")
    func rightAngle() {
        let a = Point2D(x: 0, y: 1)
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        #expect(abs(Geometry.angle(a, b, c) - 90) < 0.001)
    }

    @Test("straight line is 180 degrees")
    func straightLine() {
        let a = Point2D(x: -1, y: 0)
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        #expect(abs(Geometry.angle(a, b, c) - 180) < 0.001)
    }

    @Test("fully folded is 0 degrees")
    func folded() {
        let a = Point2D(x: 1, y: 0)
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        #expect(abs(Geometry.angle(a, b, c) - 0) < 0.001)
    }

    @Test("forty-five degrees")
    func fortyFive() {
        let a = Point2D(x: 1, y: 1)
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        #expect(abs(Geometry.angle(a, b, c) - 45) < 0.001)
    }

    @Test("degenerate (zero-length segment) returns nil-safe 180")
    func degenerate() {
        let a = Point2D(x: 0, y: 0)
        let b = Point2D(x: 0, y: 0)
        let c = Point2D(x: 1, y: 0)
        #expect(Geometry.angle(a, b, c) == 180)
    }
}
