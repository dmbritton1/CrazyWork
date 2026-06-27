# Progress Stats Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Stats tab showing lifetime totals, a day-streak, progress trend charts, and a consistency calendar aggregated across all saved workouts.

**Architecture:** A pure `ProgressStats` value type (built from plain `SessionSummary` structs mapped from `WorkoutSession`) holds all aggregation/streak math and is unit-tested with an injected `now`. `StatsView` (`@Query` + Swift Charts) and a `ConsistencyCalendarView` render it. Read-only — no model changes.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (`@Query`), Swift Charts, XCTest. iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`. XcodeGen auto-discovers files under `Sources/`/`Tests/` on `xcodegen generate` in `CrazyWork/`. Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).

> **Spec:** `docs/superpowers/specs/2026-06-27-progress-stats-design.md`

---

## File Structure

- Create `CrazyWork/Sources/Session/ProgressStats.swift` — `SessionSummary` + `ProgressStats` (pure totals + streak math).
- Create `CrazyWork/Sources/Views/ConsistencyCalendarView.swift` — GitHub-style day grid.
- Create `CrazyWork/Sources/Views/StatsView.swift` — `@Query` → `ProgressStats`; cards + 3 trend charts + calendar + empty state.
- Modify `CrazyWork/Sources/Views/RootView.swift` — add the Stats tab.
- Create `CrazyWork/Tests/ProgressStatsTests.swift` — pure-logic tests.

**Dependency order:** Task 1 (pure core, independent), Task 2 (calendar view, independent), Task 3 (StatsView, uses 1+2 — a new unreferenced file, compiles standalone), Task 4 (RootView references StatsView).

---

### Task 1: Pure stats core — `ProgressStats`

**Files:**
- Create: `CrazyWork/Sources/Session/ProgressStats.swift`
- Test: `CrazyWork/Tests/ProgressStatsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CrazyWork/Tests/ProgressStatsTests.swift`:

```swift
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
        // Jun 1,2,3 consecutive, gap, Jun 6,7 -> longest 3.
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
        // Worked out through yesterday, nothing today yet -> still counts.
        let s = [day(2026, 6, 5), day(2026, 6, 6)].map { summary($0) }
        let stats = ProgressStats(summaries: s, now: day(2026, 6, 7), calendar: cal)
        XCTAssertEqual(stats.currentStreak, 2)
    }

    func testCurrentStreakBrokenAfterTwoDays() {
        // Last workout 2 days ago -> no current streak.
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO \
  -only-testing:CrazyWorkTests/ProgressStatsTests 2>&1 | tail -20
```
Expected: FAILS to compile — `SessionSummary`/`ProgressStats` don't exist.

- [ ] **Step 3: Implement the model**

Create `CrazyWork/Sources/Session/ProgressStats.swift`:

```swift
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
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
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
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: all seven `ProgressStatsTests` pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Session/ProgressStats.swift CrazyWork/Tests/ProgressStatsTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: ProgressStats — pure totals and day-streak aggregation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Consistency calendar view

**Files:**
- Create: `CrazyWork/Sources/Views/ConsistencyCalendarView.swift`

No unit test (presentation); verified by build.

- [ ] **Step 1: Implement the view**

Create `CrazyWork/Sources/Views/ConsistencyCalendarView.swift`:

```swift
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
                    }
                }
            }
        }
    }

    private func color(for day: Date?) -> Color {
        guard let day, day <= calendar.startOfDay(for: Date()) else { return .clear }
        return workoutDays.contains(day) ? Color.accentColor : Color.gray.opacity(0.2)
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
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/ConsistencyCalendarView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: ConsistencyCalendarView day grid

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Stats view

**Files:**
- Create: `CrazyWork/Sources/Views/StatsView.swift`

No unit test (Charts/`@Query` view); verified by build.

- [ ] **Step 1: Implement the view**

Create `CrazyWork/Sources/Views/StatsView.swift`:

```swift
import SwiftUI
import SwiftData
import Charts

/// The Stats tab: lifetime totals, a day-streak, progress trend charts, and a
/// consistency calendar — aggregated across all saved workouts.
struct StatsView: View {
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView("No workouts yet",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Complete a workout to see your progress."))
            } else {
                content(stats)
            }
        }
        .navigationTitle("Stats")
    }

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map { session in
            SessionSummary(date: session.startedAt,
                           reps: session.totalReps,
                           holdSeconds: session.totalHoldSeconds,
                           formScore: session.averageFormScore,
                           duration: (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt))
        })
    }

    private func content(_ stats: ProgressStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cards(stats)
                trends(stats)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Consistency").font(.headline)
                    ConsistencyCalendarView(workoutDays: stats.workoutDays)
                }
            }
            .padding()
        }
    }

    private func cards(_ stats: ProgressStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Workouts", "\(stats.totalWorkouts)", "figure.run")
            statCard("Current streak", "\(stats.currentStreak)d", "flame.fill")
            statCard("Longest streak", "\(stats.longestStreak)d", "trophy.fill")
            statCard("Total reps", "\(stats.totalReps)", "number")
            statCard("Hold time", Self.clock(stats.totalHoldSeconds), "timer")
            statCard("Active time", Self.duration(stats.totalActiveTime), "clock")
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func trends(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            chartCard("Reps per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Reps", s.reps))
                }
            }
            chartCard("Hold seconds per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Seconds", s.holdSeconds))
                }
            }
            chartCard("Form % per workout") {
                Chart(stats.summaries, id: \.date) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Form %", s.formScore * 100))
                }
                .chartYScale(domain: 0...100)
            }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().frame(height: 160)
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/StatsView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: StatsView — lifetime cards, trend charts, consistency calendar

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Add the Stats tab

**Files:**
- Modify: `CrazyWork/Sources/Views/RootView.swift`

- [ ] **Step 1: Add the `stats` tab case**

In `CrazyWork/Sources/Views/RootView.swift`, change the `Tab` enum:
```swift
    private enum Tab { case workout, plans, history }
```
to:
```swift
    private enum Tab { case workout, plans, stats, history }
```

- [ ] **Step 2: Add the Stats tab between Plans and History**

Insert this tab immediately AFTER the `PremadePlansView { … }.tag(Tab.plans)` block and BEFORE the History `NavigationStack`:
```swift
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(Tab.stats)
```

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/RootView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: add the Stats tab to the root TabView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run engine + app test suites**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -2
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: engine all pass; app `** TEST SUCCEEDED **`.

- [ ] **Step 2: Manual checklist (note for the user)**

Confirm: a 4th "Stats" tab appears; with no history it shows the "Complete a workout to see your progress" placeholder; after workouts it shows the six lifetime cards (workouts, current/longest streak, total reps, hold time, active time), three trend line charts (reps / hold seconds / form % per workout), and the consistency grid with worked-out days filled; the streak number matches expectation.

- [ ] **Step 3: Push**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git push
```

---

## Self-Review Notes

- **Spec coverage:** `SessionSummary`/`ProgressStats` with totals + day-streak + workoutDays (Task 1); streak rule incl. today-vs-yesterday + empty (Task 1 tests); lifetime cards, three trend charts, empty state (Task 3); consistency calendar (Task 2); Stats tab in RootView (Task 4); pure-logic tests (Task 1). All spec sections map to a task.
- **Build stays green at every boundary:** Tasks 1-3 add unreferenced files; Task 4 references `StatsView` in RootView.
- **Type consistency:** `SessionSummary(date:reps:holdSeconds:formScore:duration:)`, `ProgressStats(summaries:now:calendar:)` and its members (`totalWorkouts`/`totalReps`/`totalHoldSeconds`/`totalActiveTime`/`currentStreak`/`longestStreak`/`summaries`/`workoutDays`), `ConsistencyCalendarView(workoutDays:)`, and `Tab.stats` are used identically across tasks.
- **Deviation from spec:** `StatsView` defines its own `clock`/`duration` static formatters (rather than reusing `LiveWorkoutView.clock`) to keep it self-contained — same `m:ss` output.
