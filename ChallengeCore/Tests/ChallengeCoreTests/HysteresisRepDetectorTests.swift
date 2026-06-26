import XCTest
@testable import ChallengeCore

final class HysteresisRepDetectorTests: XCTestCase {
    private func makeDetector() -> HysteresisRepDetector {
        HysteresisRepDetector(downThreshold: 90, upThreshold: 160, minRepDuration: 0.3)
    }

    func testFullCycleCountsOneRep() {
        var d = makeDetector()
        XCTAssertFalse(d.update(angle: 170, timestamp: 0.0)) // up
        XCTAssertFalse(d.update(angle: 80, timestamp: 0.5))  // down
        XCTAssertTrue(d.update(angle: 165, timestamp: 1.0))  // back up -> rep
    }

    func testJitterNearThresholdDoesNotDoubleCount() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        _ = d.update(angle: 80, timestamp: 0.5)
        XCTAssertTrue(d.update(angle: 165, timestamp: 1.0))   // one rep
        XCTAssertFalse(d.update(angle: 158, timestamp: 1.1))  // wiggle, no new rep
        XCTAssertFalse(d.update(angle: 162, timestamp: 1.2))  // still no new rep
    }

    func testTooFastRepIsRejected() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        _ = d.update(angle: 80, timestamp: 0.5)
        XCTAssertFalse(d.update(angle: 165, timestamp: 0.6)) // only 0.1s down, below minRepDuration
    }

    func testPartialDipDoesNotCount() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        XCTAssertFalse(d.update(angle: 120, timestamp: 0.5)) // never crossed downThreshold
        XCTAssertFalse(d.update(angle: 165, timestamp: 1.0))
    }
}
