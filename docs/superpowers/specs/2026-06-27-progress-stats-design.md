# Progress Stats Page

**Date:** 2026-06-27
**Status:** Approved design

## Goal

A new **Stats** tab that lets users track progress across all their workouts:
lifetime totals and a day-streak, progress trend charts over time, and a
consistency calendar. Read-only aggregation over the existing SwiftData history.

## Decisions (from brainstorming)

- **Content:** lifetime totals + streak, progress trend charts, and a consistency
  calendar. (No per-exercise records — explicitly out.)
- **Placement:** a new 4th tab (Workout / Plans / Stats / History).
- **Streak:** day streak (consecutive calendar days with ≥1 workout); an
  un-worked-out today does not break it as long as yesterday counts.

## Architecture

A pure calculator over mapped value structs, rendered by a thin Swift Charts
view — matching the codebase's pure-logic / edge-rendering pattern.

```
WorkoutSession (@Model)  ──map──▶  [SessionSummary]  ──▶  ProgressStats(summaries:now:)  ──▶  StatsView
   (SwiftData @Query)              (plain values)         (pure; unit-tested)               (Charts + calendar)
```

`ProgressStats` operates on plain `SessionSummary` values (not the `@Model`), so
it is unit-tested with hand-built inputs and an injected `now`/`calendar` — no
`ModelContainer` needed. The streak math in particular gets real coverage.

## Components

### 1. Pure stats core — `CrazyWork/Sources/Session/ProgressStats.swift`

```swift
struct SessionSummary: Equatable {
    let date: Date          // session.startedAt
    let reps: Int           // session.totalReps
    let holdSeconds: Int    // session.totalHoldSeconds
    let formScore: Double   // session.averageFormScore (0...1)
    let duration: TimeInterval // endedAt - startedAt (0 if endedAt nil)
}

struct ProgressStats {
    let totalWorkouts: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let totalActiveTime: TimeInterval
    let currentStreak: Int        // days
    let longestStreak: Int        // days
    let summaries: [SessionSummary] // ascending by date, for trend charts
    let workoutDays: Set<Date>      // start-of-day, for the calendar

    init(summaries: [SessionSummary], now: Date = Date(), calendar: Calendar = .current)
}
```

Logic (all pure):
- **Totals:** counts/sums over `summaries`.
- **`summaries`:** stored sorted ascending by `date`.
- **`workoutDays`:** `Set` of `calendar.startOfDay(for: $0.date)` — dedupes
  multiple workouts on the same day.
- **Streaks** (computed from `workoutDays`):
  - `longestStreak` = length of the longest run of consecutive days (each day
    exactly one `calendar` day after the previous).
  - `currentStreak` = the run length ending at `startOfDay(now)` if today is a
    workout day; else the run ending at yesterday if yesterday is a workout day;
    else `0`. (So a not-yet-worked-out today doesn't break the streak.)
  - Empty input → all zeros.

### 2. Stats view — `CrazyWork/Sources/Views/StatsView.swift`

- `@Query(sort: \WorkoutSession.startedAt) private var sessions` → map each to a
  `SessionSummary` → build `ProgressStats`.
- **Empty state:** when `sessions.isEmpty`, show a `ContentUnavailableView`-style
  placeholder ("Complete a workout to see your progress") instead of empty charts.
- Otherwise a `ScrollView` with three sections:
  - **Lifetime cards** (a simple grid of stat cards): total workouts, current
    streak (flame icon), longest streak, total reps, total hold time (`m:ss` via
    a shared formatter), total active time.
  - **Trends** — three compact Swift Charts `LineMark` charts over time
    (x = workout date): reps per workout, hold-seconds per workout, and form %
    per workout (`.chartYScale(domain: 0...100)`). Each in a titled card; reuse
    the `chartCard` pattern from `SummaryView`.
  - **Consistency calendar** — a `ConsistencyCalendarView` (see below).
- Time formatting (`m:ss` / `Xh Ym`) lives in a small helper; reuse
  `LiveWorkoutView.clock(_:)` for `m:ss` where it fits, and a minutes/hours
  helper for total active time.

### 3. Consistency calendar — `CrazyWork/Sources/Views/ConsistencyCalendarView.swift`

- Input: `workoutDays: Set<Date>` and a `calendar`.
- A GitHub-style rolling grid of the last ~15 weeks (105 days, aligned to week
  columns ending at the current week). Each day is a small rounded cell, shaded
  by whether that day is in `workoutDays` (empty = no workout, filled accent =
  worked out). Built with a `LazyHGrid`/`Grid` of week columns.
- Pure presentation given the day set; no business logic beyond date bucketing.

### 4. Navigation — `CrazyWork/Sources/Views/RootView.swift`

Add a 4th tab between Plans and History:

```swift
NavigationStack { StatsView() }
    .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
    .tag(Tab.stats)
```

(`enum Tab` gains a `stats` case.)

## Testing

`CrazyWork/Tests/ProgressStatsTests.swift` (pure, XCTest):
- Totals (workouts, reps, holdSeconds, activeTime) from crafted summaries.
- `longestStreak` across a run with a gap (e.g. 3 consecutive, gap, 2 consecutive
  → 3).
- `currentStreak`: today-is-a-workout-day case; today-empty-but-yesterday case
  (streak preserved); broken case (last workout 2+ days ago → 0). `now` injected.
- `workoutDays` dedupes two summaries on the same calendar day.
- Empty input → all zeros.

The view, charts, and calendar grid are verified by build + manual (not
meaningfully unit-testable).

## Out of scope (YAGNI)

- Per-exercise records / drill-down.
- Selectable time ranges or chart metric pickers.
- Goals/targets and goal progress.
- Editing or deleting history from this page.
