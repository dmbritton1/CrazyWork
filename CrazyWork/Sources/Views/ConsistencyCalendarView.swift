import SwiftUI

/// GitHub-style consistency grid: the last ~15 weeks, one cell per day, filled
/// when that day has a workout. Future days in the current week render blank.
struct ConsistencyCalendarView: View {
    let workoutDays: Set<Date>
    var calendar: Calendar = .current
    private let weeks = 15

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            let columns = weekColumns()
            ForEach(columns.indices, id: \.self) { c in
                VStack(spacing: 3) {
                    ForEach(columns[c].indices, id: \.self) { r in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: columns[c][r]))
                            .frame(width: 12, height: 12)
                            .overlay {
                                // Ring marking today, so "now" is findable even before a workout.
                                if let day = columns[c][r], calendar.isDateInToday(day) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Palette.hairlineStrong, lineWidth: 1)
                                }
                            }
                    }
                }
            }
        }
    }

    private func color(for day: Date?) -> Color {
        let today = calendar.startOfDay(for: Date())
        guard let day, day <= today else { return .clear }
        if calendar.isDate(day, inSameDayAs: today) && workoutDays.contains(day) { return Palette.accentAqua }
        return workoutDays.contains(day) ? Palette.brandRed : Palette.surfaceCard
    }

    /// Columns of 7 days (week start..+6), oldest week first, ending this week.
    private func weekColumns() -> [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1 = first weekday
        let thisWeekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let firstWeekStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeekStart)!
        return (0..<weeks).map { w in
            let weekStart = calendar.date(byAdding: .day, value: 7 * w, to: firstWeekStart)!
            return (0..<7).map { d in calendar.date(byAdding: .day, value: d, to: weekStart) }
        }
    }
}
