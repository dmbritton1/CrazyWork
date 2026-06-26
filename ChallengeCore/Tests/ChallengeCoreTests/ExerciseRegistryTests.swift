import XCTest
@testable import ChallengeCore

final class ExerciseRegistryTests: XCTestCase {
    func testKnownIdsReturnFreshAnalyzers() {
        XCTAssertEqual(ExerciseRegistry.makeAnalyzer(for: "pushup")?.info.id, "pushup")
        XCTAssertEqual(ExerciseRegistry.makeAnalyzer(for: "squat")?.info.id, "squat")
    }

    func testUnknownIdReturnsNil() {
        XCTAssertNil(ExerciseRegistry.makeAnalyzer(for: "moonwalk"))
    }

    func testAllExercisesListsKnownIds() {
        let ids = ExerciseRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids), ["pushup", "squat"])
    }
}
