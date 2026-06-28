import XCTest
@testable import CrazyWork

final class HealthMetricsCardTests: XCTestCase {
    func testWeightText() {
        XCTAssertEqual(HealthMetricsCard.weightText(72.4), "72 kg")
        XCTAssertEqual(HealthMetricsCard.weightText(nil), "—")
    }
    func testHeightText() {
        XCTAssertEqual(HealthMetricsCard.heightText(178.6), "179 cm")
        XCTAssertEqual(HealthMetricsCard.heightText(nil), "—")
    }
    func testSexText() {
        XCTAssertEqual(HealthMetricsCard.sexText(true), "Male")
        XCTAssertEqual(HealthMetricsCard.sexText(false), "Female")
        XCTAssertEqual(HealthMetricsCard.sexText(nil), "—")
    }
}
