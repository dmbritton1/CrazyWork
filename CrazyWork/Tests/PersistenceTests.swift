import XCTest
import SwiftData
@testable import CrazyWork

final class PersistenceTests: XCTestCase {
    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, ExerciseSet.self, configurations: config)
        return ModelContext(container)
    }

    func testSaveAndFetchRepAndHoldSets() throws {
        let ctx = try inMemoryContext()
        let session = WorkoutSession(startedAt: Date())

        let squat = ExerciseSet(exerciseID: "squat", goalUnit: "reps", target: 12, order: 0)
        squat.completed = 12
        squat.averageFormScore = 0.9
        squat.findingsSummary = ["Lift your hips": 2]

        let plank = ExerciseSet(exerciseID: "plank", goalUnit: "seconds", target: 30, order: 1)
        plank.completed = 28

        session.sets.append(squat)
        session.sets.append(plank)
        session.endedAt = Date()
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].sets.count, 2)
        XCTAssertEqual(fetched[0].totalReps, 12)             // rep sets only
        XCTAssertEqual(fetched[0].totalHoldSeconds, 28)      // seconds sets only
        XCTAssertEqual(fetched[0].sets.first { $0.exerciseID == "squat" }?.findingsSummary["Lift your hips"], 2)
    }
}
