# Timed Rest + Premade Plans

**Date:** 2026-06-27
**Status:** Approved design

## Goal

Two related additions to the workout-setup and flow:

1. **Timed rest between sets.** Replace the manual "Start next set" button with an
   automatic countdown that advances on its own, plus a builder control to set the
   rest duration for the workout.
2. **Premade plans tab.** A new tab listing a handful of curated workouts, each
   with a description and an estimated completion time. Choosing one loads it into
   the builder to tweak before starting.

## Decisions (from brainstorming)

- **Rest scope:** one rest duration per workout (not per-exercise).
- **Rest controls:** auto-countdown with a single "Skip rest" button (no extend).
- **Premade plan action:** load into the builder to tweak (don't start directly).
- **Navigation:** introduce a `TabView` root (Workout / Plans / History); History
  moves from a toolbar link into its own tab.

## Architecture

Two architectural choices:

- **`TabView` root with shared draft state.** A new `RootView` owns the workout
  draft (`entries` + `restSeconds`) and the selected tab. The Plans tab writes the
  draft and switches to the Workout tab; the builder edits the same draft. This is
  what makes "load a plan into the builder" work without a singleton.
- **Rest countdown lives in the view, not the coordinator.** A dedicated
  `RestCountdownView` owns its own timer and calls the existing
  `coordinator.beginNextSet()` at zero. `SessionCoordinator` stays a pure,
  frame-driven, unit-tested state machine with no wall-clock logic.

```
CrazyWorkApp ─▶ RootView (TabView; holds entries + restSeconds + selectedTab)
                 ├─ Workout: BuildWorkoutView(entries, restSeconds)  ─▶ LiveWorkoutView(plan, restSeconds)
                 ├─ Plans:   PremadePlansView(onChoose) ─▶ writes draft, selects Workout tab
                 └─ History: HistoryView
```

## Components

### 1. `RootView` (new) — `CrazyWork/Sources/Views/RootView.swift`

A `TabView` holding the workout draft and tab selection:

```swift
@State private var entries: [WorkoutEntry] = []
@State private var restSeconds: Int = 30
@State private var selection: Tab = .workout
enum Tab { case workout, plans, history }
```

- **Workout** tab → `BuildWorkoutView(entries: $entries, restSeconds: $restSeconds)`.
- **Plans** tab → `PremadePlansView { plan in entries = plan.entries; restSeconds = plan.restSeconds; selection = .workout }`.
- **History** tab → `HistoryView()`.

`CrazyWorkApp` renders `RootView()` instead of `BuildWorkoutView()` (the
`.modelContainer` modifier stays on the `WindowGroup`).

### 2. Builder changes — `CrazyWork/Sources/Views/BuildWorkoutView.swift`

- Becomes binding-driven: `@Binding var entries: [WorkoutEntry]` and
  `@Binding var restSeconds: Int` (drop the local `@State entries`).
- Add a **"Rest between sets"** stepper in a section: `Stepper("Rest: \(restSeconds)s", value: $restSeconds, in: 0...180, step: 5)`.
- Remove the toolbar `History` `NavigationLink` (History is now a tab).
- The Start button passes rest through: `LiveWorkoutView(plan: WorkoutPlan.expand(entries), restSeconds: restSeconds)`.

### 3. Rest countdown — `LiveWorkoutView` + new `RestCountdownView`

- `LiveWorkoutView` gains `let restSeconds: Int` (updated initializer; the existing
  `coordinator` init is unchanged).
- In the `.resting` branch, replace the current `restView` (the "Start next set"
  button) with `RestCountdownView(seconds: restSeconds, nextExercise: exerciseName) { coordinator.beginNextSet() }`.
- **`RestCountdownView`** (new file `CrazyWork/Sources/Views/RestCountdownView.swift`):
  shows "Rest", a `mm:ss` countdown (reuse `LiveWorkoutView.clock(_:)`), a
  "Next: <exercise>" line, and a "Skip rest" button. It owns `@State private var remaining: Int`,
  initialized to `seconds`, and a `.task` that decrements once per second via
  `try? await Task.sleep(for: .seconds(1))`; when `remaining` reaches 0 it calls
  `onAdvance()`. The "Skip rest" button calls `onAdvance()` immediately. If
  `seconds == 0`, it advances on the first tick (near-instant).
- The camera/preview keeps running during rest (frames are ignored while
  `phase != .active`), so no pipeline changes. The rest audio (beep + "Rest. Next
  up: …") already fires from the `WorkoutEvent.rest` emitted when the set finished.

### 4. Premade plans — `CrazyWork/Sources/Session/PremadePlan.swift` + `PremadePlansView.swift`

Pure model + catalog + estimate:

```swift
struct PremadePlan: Identifiable {
    let id: String
    let name: String
    let summary: String       // one-line description
    let entries: [WorkoutEntry]
    let restSeconds: Int
}

enum PremadePlanCatalog {
    static let all: [PremadePlan] = [ /* ~4 plans built from pushup/squat/lunge/plank */ ]
}

/// Rough completion estimate in seconds: work + inter-set rest.
/// Reps are estimated at `secondsPerRep` each; a timed hold counts its seconds.
func estimatedSeconds(for plan: PremadePlan, secondsPerRep: Double = 3) -> Int
```

`estimatedSeconds` = `Σ_entries entry.sets × workSeconds(entry)` +
`(totalSets − 1) × restSeconds`, where `workSeconds` is `target × secondsPerRep`
for a reps exercise and `target` for a seconds exercise, and `totalSets` is the
sum of all `entry.sets`. Goal unit comes from `ExerciseRegistry`.

Initial catalog (built from the existing four exercises):
- **Express 5** — "A quick full-body hit." pushup 2×10, squat 2×12, plank 1×30; rest 20.
- **Full Body Starter** — "Balanced beginner session." pushup 3×10, squat 3×12, lunge 3×10, plank 2×30; rest 30.
- **Leg Day** — "Lower-body focus." squat 4×12, lunge 3×12, plank 2×45; rest 45.
- **Core & Hold** — "Core and stability." plank 3×30, pushup 3×10; rest 30.

`PremadePlansView` lists each plan as a card: name, `summary`, an estimated-time
label ("~8 min", via `estimatedSeconds` rounded to the nearest minute, floor 1),
and a short exercise summary line (e.g. "Push-up · Squat · Plank"). Tapping a card
calls the `onChoose(plan)` closure passed from `RootView`.

## Testing

Unit-tested (pure logic), in `CrazyWork/Tests/PremadePlanTests.swift`:
- `estimatedSeconds(for:)` on a known plan returns the expected total (hand-computed).
- `PremadePlanCatalog.all` invariants: non-empty; unique ids; every entry's
  `exerciseID` exists in `ExerciseRegistry`; every entry has `sets >= 1`.

Verified by build + manual: the `TabView` wiring, plan-loads-into-builder flow,
the rest stepper, and the `RestCountdownView` auto-advance/skip (timer + UI are
not meaningfully unit-testable).

## Out of scope (YAGNI)

- A spoken 3-2-1 audio countdown at the end of rest (the rest beep already plays;
  the `WorkoutAudioCoach` makes this easy to add later).
- Per-exercise rest durations.
- Persisting a default rest preference across launches.
- Editing/saving user-created plans as reusable templates.
