import XCTest
@testable import CrazyWork

final class ProgressStatsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int, h: Int = 12) -> Date {
        DateComponents(calendar: cal, year: y, month: m, day: d, hour: h).date!
    }
    private func summary(_ date: Date, reps: Int = 0, hold: Int = 0,
                         form: Double = 1, duration: TimeInterval = 0) -> SessionSummary {
        SessionSummary(date: date, reps: reps, holdSeconds: hold, formScore: form, duration: duration)
    }

    func testTotals() {
        let s = [summary(day(2026, 6, 1), reps: 10, duration: 60),
                 summary(day(2026, 6, 2), hold: 30, duration: 40)]
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 2), calendar: cal)
        XCTAssertEqual(stats.totalWorkouts, 2)
        XCTAssertEqual(stats.totalReps, 10)
        XCTAssertEqual(stats.totalHoldSeconds, 30)
        XCTAssertEqual(stats.totalActiveTime, 100)
    }

    func testLongestStreakWithGap() {
        let s = [day(2026, 6, 1), day(2026, 6, 2), day(2026, 6, 3),
                 day(2026, 6, 6), day(2026, 6, 7)].map { summary($0) }
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.longestStreak, 3)
    }

    func testCurrentStreakCountsToday() {
        let s = [day(2026, 6, 5), day(2026, 6, 6), day(2026, 6, 7)].map { summary($0) }
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.currentStreak, 3)
    }

    func testCurrentStreakSurvivesEmptyToday() {
        let s = [day(2026, 6, 5), day(2026, 6, 6)].map { summary($0) }
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.currentStreak, 2)
    }

    func testCurrentStreakBrokenAfterTwoDays() {
        let s = [day(2026, 6, 4), day(2026, 6, 5)].map { summary($0) }
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    func testWorkoutDaysDedupesSameDay() {
        let s = [summary(day(2026, 6, 1, h: 8)), summary(day(2026, 6, 1, h: 20))]
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 1), calendar: cal)
        XCTAssertEqual(stats.workoutDays.count, 1)
        XCTAssertEqual(stats.totalWorkouts, 2)
    }

    func testEmptyIsAllZeros() {
        let stats = ProgressStats(summaries: [], now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.totalWorkouts, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
        XCTAssertTrue(stats.workoutDays.isEmpty)
    }
}
