import XCTest
import ChallengeCore
@testable import CrazyWork

final class PremadePlanTests: XCTestCase {
    func testEstimatedSecondsForExpress5() {
        let plan = PremadePlanCatalog.all.first { $0.id == "express5" }!
        // pushup 2×10×3=60, squat 2×12×3=72, plank 1×30=30 => work 162.
        // 5 total sets => 4 rests × 20s = 80. Total 242.
        XCTAssertEqual(plan.estimatedSeconds(), 242)
    }

    func testCatalogInvariants() {
        let plans = PremadePlanCatalog.all
        XCTAssertFalse(plans.isEmpty)
        let ids = plans.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count) // unique ids
        let known = Set(ExerciseRegistry.all.map(\.id))
        for plan in plans {
            XCTAssertFalse(plan.entries.isEmpty)
            for entry in plan.entries {
                XCTAssertTrue(known.contains(entry.exerciseID), "unknown exercise \(entry.exerciseID)")
                XCTAssertGreaterThanOrEqual(entry.sets, 1)
            }
        }
    }
}
