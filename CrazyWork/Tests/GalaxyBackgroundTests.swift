import XCTest
@testable import CrazyWork

final class GalaxyBackgroundTests: XCTestCase {
    func testPhaseInsideFiringWindow() {
        let τ = GalaxyBackground.meteorPhase(t: 0.3, period: 20, duration: 0.6)
        XCTAssertNotNil(τ)
        XCTAssertEqual(τ!, 0.5, accuracy: 1e-9)
    }

    func testDormantOutsideFiringWindow() {
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 0.6, period: 20, duration: 0.6))
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 10, period: 20, duration: 0.6))
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 19.99, period: 20, duration: 0.6))
    }

    func testPeriodicAcrossCycles() {
        let a = GalaxyBackground.meteorPhase(t: 0.42, period: 20, duration: 0.6)
        let b = GalaxyBackground.meteorPhase(t: 20.42, period: 20, duration: 0.6)
        XCTAssertEqual(a!, b!, accuracy: 1e-9)
    }
}
