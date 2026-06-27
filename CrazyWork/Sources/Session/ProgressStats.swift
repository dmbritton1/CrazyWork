import Foundation

/// One workout reduced to the numbers the stats page needs. A plain value type
/// so the stats math is testable without a SwiftData container.
struct SessionSummary: Equatable {
    let date: Date
    let reps: Int
    let holdSeconds: Int
    let formScore: Double      // 0...1
    let duration: TimeInterval
}

/// Aggregate progress across all workouts. Pure — built from `SessionSummary`s
/// with an injectable `now`/`calendar` for deterministic tests.
struct ProgressStats {
    let totalWorkouts: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let totalActiveTime: TimeInterval
    let currentStreak: Int          // days
    let longestStreak: Int          // days
    let summaries: [SessionSummary] // ascending by date, for trend charts
    let workoutDays: Set<Date>      // start-of-day, for the calendar

    init(summaries: [SessionSummary], now: Date = Date(), calendar: Calendar = .current) {
        let sorted = summaries.sorted { $0.date < $1.date }
        self.summaries = sorted
        self.totalWorkouts = sorted.count
        self.totalReps = sorted.reduce(0) { $0 + $1.reps }
        self.totalHoldSeconds = sorted.reduce(0) { $0 + $1.holdSeconds }
        self.totalActiveTime = sorted.reduce(0) { $0 + $1.duration }

        let days = Set(sorted.map { calendar.startOfDay(for: $0.date) })
        self.workoutDays = days
        self.longestStreak = Self.longestStreak(days: days, calendar: calendar)
        self.currentStreak = Self.currentStreak(days: days, now: now, calendar: calendar)
    }

    private static func longestStreak(days: Set<Date>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if let next = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               calendar.isDate(next, inSameDayAs: sorted[i]) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        return longest
    }

    private static func currentStreak(days: Set<Date>, now: Date, calendar: Calendar) -> Int {
        guard !days.isEmpty,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        else { return 0 }
        let today = calendar.startOfDay(for: now)
        // Anchor at today if worked out today, else yesterday, else no streak.
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
