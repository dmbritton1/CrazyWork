import XCTest
import ChallengeCore
@testable import CrazyWork

final class SavedWorkoutTests: XCTestCase {
    func testWorkoutEntryCodableRoundTrips() throws {
        let entries = [
            WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10),
            WorkoutEntry(exerciseID: "plank", sets: 2, target: 30),
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([WorkoutEntry].self, from: data)
        XCTAssertEqual(decoded, entries) // id, exerciseID, sets, target all preserved
    }

    func testAsPlanMapsFields() {
        let entries = [WorkoutEntry(exerciseID: "squat", sets: 4, target: 12)]
        let saved = SavedWorkout(name: "My Legs", restSeconds: 45, entries: entries)
        let plan = saved.asPlan
        XCTAssertEqual(plan.name, "My Legs")
        XCTAssertEqual(plan.restSeconds, 45)
        XCTAssertEqual(plan.entries, entries)
        XCTAssertEqual(plan.summary, "Custom workout")
    }
}
