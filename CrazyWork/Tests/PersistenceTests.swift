import XCTest
import SwiftData
@testable import CrazyWork

final class PersistenceTests: XCTestCase {
    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, ExerciseSet.self, configurations: config)
        return ModelContext(container)
    }

    func testSaveAndFetchSessionWithSets() throws {
        let ctx = try inMemoryContext()
        let session = WorkoutSession(startedAt: Date())
        let set = ExerciseSet(exerciseID: "squat", targetReps: 12, order: 0)
        set.completedReps = 12
        set.averageFormScore = 0.9
        set.findingsSummary = ["shallowDepth": 2]
        session.sets.append(set)
        session.endedAt = Date()
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].sets.count, 1)
        XCTAssertEqual(fetched[0].sets[0].exerciseID, "squat")
        XCTAssertEqual(fetched[0].sets[0].findingsSummary["shallowDepth"], 2)
        XCTAssertEqual(fetched[0].totalReps, 12)
    }
}
