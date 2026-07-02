import XCTest
@testable import CrazyWork

final class PathFocusTests: XCTestCase {
    func testCenterIsFullFocus() {
        XCTAssertEqual(PathView.focusT(midY: 400, viewportHeight: 800), 0)
    }

    func testEdgesAreFullDefocus() {
        XCTAssertEqual(PathView.focusT(midY: 0, viewportHeight: 800), 1)
        XCTAssertEqual(PathView.focusT(midY: 800, viewportHeight: 800), 1)
    }

    func testBeyondViewportClampsToOne() {
        XCTAssertEqual(PathView.focusT(midY: -300, viewportHeight: 800), 1)
        XCTAssertEqual(PathView.focusT(midY: 1200, viewportHeight: 800), 1)
    }

    func testMidwayIsHalf() {
        XCTAssertEqual(PathView.focusT(midY: 200, viewportHeight: 800), 0.5, accuracy: 0.001)
        XCTAssertEqual(PathView.focusT(midY: 600, viewportHeight: 800), 0.5, accuracy: 0.001)
    }

    func testZeroViewportIsSafe() {
        XCTAssertEqual(PathView.focusT(midY: 100, viewportHeight: 0), 0)
    }
}
