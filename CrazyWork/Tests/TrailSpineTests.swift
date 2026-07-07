import XCTest
@testable import CrazyWork

final class TrailSpineTests: XCTestCase {
    // Serpentine anchors like the trail produces: alternating sides, jittered y.
    private let anchors = [CGPoint(x: 80, y: 240), CGPoint(x: 310, y: 410),
                           CGPoint(x: 95, y: 620), CGPoint(x: 290, y: 790)]
    private var spine: TrailSpine { TrailSpine(anchors: anchors, cx: 196, overrun: 188) }

    func testPassesThroughEveryAnchor() {
        for a in anchors {
            XCTAssertEqual(spine.x(a.y), a.x, accuracy: 0.001)
        }
    }

    func testTurnsAroundAtInteriorAnchors() {
        // With alternating sides the tangent at an interior anchor is near
        // level, so the anchor is a local extremum: points just above and
        // below sit on the same side, closer to center.
        let a = anchors[1]
        XCTAssertLessThan(spine.x(a.y - 20), a.x)
        XCTAssertLessThan(spine.x(a.y + 20), a.x)
    }

    func testDefinedAndFiniteAcrossOverrunRange() {
        // ribbonPath samples from -rowHeight to height + rowHeight.
        var y: CGFloat = -188
        while y <= 1000 {
            XCTAssertTrue(spine.x(y).isFinite, "non-finite x at y=\(y)")
            y += 6
        }
    }
}
