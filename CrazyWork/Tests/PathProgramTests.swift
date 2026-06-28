import XCTest
@testable import CrazyWork

final class PathProgramTests: XCTestCase {

    // Coverage: every necessary muscle group / exercise appears in a MAIN
    // workout across one lap of the rotation.
    func testRotationMainsCoverAllExercises() {
        let ids = Set(PathProgram.rotation.flatMap { $0.entries.map(\.exerciseID) })
        XCTAssertEqual(ids, ["pushup", "squat", "lunge", "plank", "situp", "glutebridge"])
    }

    func testDayAtWrapsAroundRotation() {
        let count = PathProgram.rotation.count
        XCTAssertEqual(PathProgram.day(at: 0).id, PathProgram.rotation[0].id)
        XCTAssertEqual(PathProgram.day(at: count).id, PathProgram.rotation[0].id)
        XCTAssertEqual(PathProgram.day(at: count + 1).id, PathProgram.rotation[1].id)
    }

    func testCompletingAdvancesAndLocksToday() {
        let p = PathProgress(index: 0, lastCompletedDay: Int.min)
        XCTAssertEqual(p.state(of: 0, today: 100), .today)
        let after = p.completing(today: 100)
        XCTAssertEqual(after.index, 1)
        XCTAssertEqual(after.state(of: 0, today: 100), .done)
        XCTAssertEqual(after.state(of: 1, today: 100), .lockedNext)
    }

    func testDoubleCompleteSameDayIsNoop() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        let again = after.completing(today: 100)
        XCTAssertEqual(again.index, after.index)
        XCTAssertEqual(again.lastCompletedDay, 100)
    }

    func testNewDayUnlocksNext() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        XCTAssertEqual(after.state(of: 1, today: 101), .today)
    }

    func testSkippedDaysPreserveIndexAsMakeup() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        XCTAssertEqual(after.index, 1)
        XCTAssertEqual(after.state(of: 1, today: 103), .today)
    }
}
