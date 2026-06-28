# Daily Path Tab — Design

## Overview

A new first tab, **Today**, presenting a Duolingo-style serpentine "path" of
daily workouts. The user does one prescribed workout per day to extend a
streak; the next node stays locked until the calendar day rolls over.
Supplementary bonus workouts are offered as optional extra credit. The path is
a static, infinite muscle-group rotation for now; the rotation array is the
seam where a future data-driven/AI scheduler plugs in.

## Goals

- One prescribed workout per day, gated so the next unlocks only on the next day.
- Advance-on-completion: a skipped day never loses the user's place; the missed
  workout is simply what's waiting next (a make-up). Only the streak resets.
- The rotation hits every major muscle group across one lap with no group
  trained hard two days in a row.
- Sleek serpentine visuals matching the existing dark Raycast-style theme.
- Reuse the existing workout engine (camera/pose/rest/summary) and streak math
  wholesale — no new workout or streak logic.

## Non-goals (deferred)

- Data-driven / AI-generated weekly schedules. Static rotation only for now.
  The `rotation` array is the single seam where this plugs in later.

## The Rotation (static data)

An infinite cycle of **5 day-templates**. Node at position `i` is
`rotation[i % rotation.count]`. Chosen so all 6 pose-detected exercises
(`pushup`, `squat`, `lunge`, `plank`, `situp`, `glutebridge`) appear in a
**main** workout within one lap, with no muscle group hit hard on consecutive
days.

| Node | Focus | Muscle tag | Main workout | Rest | Supplementary (bonus) |
|---|---|---|---|---|---|
| 1 · Upper Push | Push | Chest · Triceps · Shoulders | pushup 3×10 | 30s | Core hold — plank 2×30 |
| 2 · Lower Power | Legs | Quads · Glutes | squat 3×12, lunge 3×10 | 30s | Upper finisher — pushup 2×10 |
| 3 · Core | Core | Abs · Core | situp 3×15, plank 3×30 | 30s | Glute bridge 2×15 |
| 4 · Glutes & Posterior | Posterior | Glutes · Hamstrings | glutebridge 3×15, lunge 3×12 | 30s | Upper push — pushup 2×10 |
| 5 · Full Body | Total | Total body | pushup 2×10, squat 2×12, situp 2×12, plank 1×30 | 25s | Plank challenge — plank 2×45 |

Per-lap main-workout coverage: pushup (1, 5), squat (2, 5), lunge (2, 4),
situp (3, 5), plank (3, 5), glutebridge (4) — all six present. Supplementary
always targets different muscles than that day's main.

## Progression (advance-on-completion)

State: two scalars in `@AppStorage`.

- `pathIndex: Int` — number of nodes finished (also the index of the current
  TODAY node).
- `pathLastCompletedDay: Int` — epoch day number (days since 1970,
  `startOfDay`-based) of the last completed node. `0` / unset means never.

Derived state (pure, testable):

- `isCompletedToday = (pathLastCompletedDay == todayEpochDay)`
- TODAY node = `rotation[pathIndex % count]`.
  - If **not** completed today → TODAY is unlocked and tappable.
  - If completed today → TODAY's main is done; node `pathIndex` is the **next**
    node, locked until the calendar day rolls over.

Completion: when the TODAY workout finishes (`LiveWorkoutView` saves its
session), the path's `onComplete` closure runs. Guarded by
`!isCompletedToday` so it advances at most once per day:

```
if pathLastCompletedDay != todayEpochDay {
    pathIndex += 1
    pathLastCompletedDay = todayEpochDay
}
```

Skip a day → `pathIndex` unchanged, so the same node is still TODAY the next
day (make-up). Only the **streak** resets, via the existing
`ProgressStats.currentStreak` computed from saved `WorkoutSession`s. No new
streak code.

Supplementary workouts run through the same engine but pass **no** `onComplete`
closure — they save to history/stats (and so still help the streak) but never
touch `pathIndex`.

## Visuals — Serpentine trail

New first tab, "Today". Dark `Palette.canvas`, no shadows, hairline borders,
matching the existing theme.

- **Hero:** a `HeroStripeBand` with the 🔥 streak flame and current streak
  count (from `ProgressStats`), plus today's focus headline.
- **Trail:** a `LazyVStack` serpentine — nodes zig-zag left / center / right
  connected by a dashed connector line.
  - Done (`i < pathIndex`): filled red + check glyph.
  - TODAY (`i == pathIndex`, not completed today): pulsing red ring, tappable.
  - Locked (everything ahead, and node `pathIndex` when completed today): dim
    hairline circle, not tappable.
  - Each node shows its focus title + muscle tag beside the circle.
- **Focus card:** the TODAY card. When already done today it flips to
  "Done ✅ — next unlocks tomorrow" and reveals the supplementary cards below.
- **Window rendering:** render indices `max(0, pathIndex-2) … pathIndex+6`
  rather than an unbounded list.

## Wiring & Files

**New files:**

- `Sources/Session/PathProgram.swift` — `PathDay` value type (`id`, `title`,
  `focus`/muscle tag, `entries: [WorkoutEntry]`, `restSeconds`,
  `supplementary: [PathDay]`). Supplementary entries reuse the same `PathDay`
  type (with their own `supplementary` left empty) so there is one value type,
  not two. Plus the static `rotation: [PathDay]`, and `day(at index: Int) ->
  PathDay`
  (`rotation[index % count]`). Plus the pure progression helpers
  (`isCompletedToday`, `todayEpochDay`, advance computation) so they are
  testable without SwiftUI.
- `Sources/Views/PathView.swift` — the serpentine UI, `@AppStorage` state,
  streak via a SwiftData query of `WorkoutSession` → `ProgressStats`, and the
  `onComplete` advance closure. TODAY node and supplementary cards both launch
  the existing `LiveWorkoutView`.
- `Tests/PathProgramTests.swift` — see Testing.

**Edited files:**

- `Sources/Views/RootView.swift` — add a `.path` case to the `Tab` enum, make
  it the **first** tab (label "Today", SF Symbol `flag.checkered`), default
  `selection = .path`.
- `Sources/Views/LiveWorkoutView.swift` — add `var onComplete: (() -> Void)? =
  nil` to the view + its `init` (defaulted, so the existing
  `BuildWorkoutView` call site is unchanged), and call `onComplete?()` inside
  `saveIfNeeded()` after the successful `modelContext.save()`.

No new workout engine, no new streak logic, no new SwiftData model — progress
is two `@AppStorage` scalars.

## Data flow

1. PathView reads `pathIndex` / `pathLastCompletedDay` from `@AppStorage` and
   `WorkoutSession`s via SwiftData → builds `ProgressStats` for the streak.
2. Tapping TODAY pushes `LiveWorkoutView(plan: expand(day.entries),
   restSeconds: day.restSeconds, onComplete: advance)`.
3. On finish, `saveIfNeeded()` persists the `WorkoutSession`, then calls
   `onComplete` → advance closure bumps `pathIndex` + stamps the day (guarded).
4. Returning to PathView, the now-completed node renders done, the next renders
   locked, and supplementary cards appear.
5. Supplementary cards push `LiveWorkoutView` with no `onComplete` — saved but
   no path advance.

## Error handling / edge cases

- Double-run same day: `onComplete` guard (`pathLastCompletedDay !=
  todayEpochDay`) prevents a second advance.
- First launch (never completed): `pathIndex = 0`, `pathLastCompletedDay`
  unset → node 0 is TODAY, unlocked.
- Clock/timezone: epoch day computed from `Calendar.current.startOfDay`,
  matching how `ProgressStats` buckets days, so streak and path agree.

## Testing

One test file, `Tests/PathProgramTests.swift`, asserting:

1. **Coverage:** the union of `exerciseID`s across all main workouts in one lap
   equals the full set of 6 exercises (path hits every necessary muscle group).
2. **Progression (pure):**
   - Completing TODAY advances `pathIndex` by 1 and stamps today; the next node
     reads as locked for the rest of the day.
   - A new calendar day unlocks the next node.
   - A skipped day leaves `pathIndex` unchanged (the missed node is still
     TODAY).
   - The same-day guard prevents a double advance.
