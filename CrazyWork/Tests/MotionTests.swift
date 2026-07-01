import XCTest
@testable import CrazyWork

final class MotionTests: XCTestCase {
    func testResolvedReturnsNilUnderReduceMotion() {
        XCTAssertNil(Motion.resolved(Motion.state, reduceMotion: true))
    }

    func testResolvedPassesAnimationWhenReduceMotionOff() {
        XCTAssertNotNil(Motion.resolved(Motion.state, reduceMotion: false))
    }

    func testResolvedNilInputStaysNil() {
        XCTAssertNil(Motion.resolved(nil, reduceMotion: false))
    }
}
