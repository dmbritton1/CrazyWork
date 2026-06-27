import XCTest
@testable import CrazyWork

final class WorkoutPlanTests: XCTestCase {
    func testExpandsEntriesIntoOrderedSets() {
        let entries = [
            WorkoutEntry(exerciseID: "squat", sets: 3, target: 12),
            WorkoutEntry(exerciseID: "plank", sets: 2, target: 30),
        ]
        let plan = WorkoutPlan.expand(entries)
        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(plan.prefix(3).map(\.exerciseID), ["squat", "squat", "squat"])
        XCTAssertEqual(plan.first?.target, 12)
        XCTAssertEqual(plan.last?.exerciseID, "plank")
        XCTAssertEqual(plan.last?.target, 30)
    }

    func testZeroSetsProducesNoPlannedSets() {
        XCTAssertTrue(WorkoutPlan.expand([WorkoutEntry(exerciseID: "squat", sets: 0, target: 10)]).isEmpty)
    }
}
