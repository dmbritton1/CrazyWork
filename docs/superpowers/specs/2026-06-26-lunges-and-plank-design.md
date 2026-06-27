# Lunges + Plank (time-based exercise) — Design Spec

**Date:** 2026-06-26
**Status:** Approved for planning
**Builds on:** the ported WakeupCall engine (`ChallengeCore`) and the CrazyWork app.

## 1. Summary

Add two exercises to CrazyWork:

- **Lunges** — rep-based; rides the existing `RepCounter`/`ExerciseAnalyzer` path with a small generalization (track the more-bent knee instead of averaging both).
- **Plank** — a **time-based hold**, not a count. Requires generalizing the exercise abstraction from "reps only" to a goal that is either reps or seconds. The plank timer accumulates **only while a valid plank is held** (pause-and-resume; "time under good form").

The unifying change is **Approach A**: one analyzer protocol reporting `progress` toward a goal whose unit is either reps or seconds. Pushups/squats/lunges report reps; plank reports seconds-held. The `SessionCoordinator`, HUD, and persistence become goal-unit-agnostic.

## 2. Goals & Non-Goals

### Goals
- A `LungeAnalyzer` that counts lunges (either leg) through the proven `RepCounter`.
- A `PlankAnalyzer` that accumulates valid-hold seconds, pausing when form breaks or the pose is lost, resuming on recovery.
- Generalize the analyzer/result/coordinator/persistence so rep-based and time-based exercises are first-class peers (no plank-as-fake-reps hack).
- Both exercises selectable in the workout builder with appropriate targets (reps vs. seconds) and shown correctly in the live HUD, summary, and history.

### Non-Goals
- No lunge form coaching in v1 (counts only; `formCue == nil`), mirroring the current squat decision.
- No data-driven threshold tuning / fixture recording in this change (separate future work).
- No per-leg lunge breakdown — both legs combine into one rep total.
- No changes to pushup/squat behavior (their defaults must be preserved).

## 3. Engine changes (`ChallengeCore`)

### 3.1 Rep angle combination (for lunges)
`RepCounter` currently averages the rep angle over all configured `repJoints` triples. Averaging both knees is wrong for a lunge (only one knee bends). Add to `RepCounterConfig`:

```swift
public enum AngleCombination: Sendable, Equatable { case average, minimum }
public var combination: AngleCombination   // default .average
```

In `repAngle(in:)`: with `.average`, unchanged (pushup/squat preserved). With `.minimum`, return the smallest available triple angle — so whichever knee is most bent drives the lunge.

### 3.2 Goal unit + generalized analyzer result
```swift
public enum GoalUnit: String, Sendable, Equatable, Codable { case reps, seconds }
```

`ExerciseDefinition` gains `goalUnit: GoalUnit` (pushup/squat/lunge = `.reps`, plank = `.seconds`).

Replace the rep-specific `AnalyzerResult` with a progress-based one:
```swift
public struct AnalyzerResult: Sendable, Equatable {
    public var progress: Double     // reps so far, or seconds held
    public var didAdvance: Bool     // a rep just completed (false for plank ticks)
    public var poseVisible: Bool
    public var formCue: String?
}
```

`ExerciseAnalyzer` protocol:
```swift
public protocol ExerciseAnalyzer {
    var definition: ExerciseDefinition { get }
    var progress: Double { get }
    mutating func process(_ frame: PoseFrame) -> AnalyzerResult
    mutating func reset()
}
```

Pushup/Squat analyzers map `RepCounter` output: `progress = Double(count)`, `didAdvance = update.didCompleteRep`.

### 3.3 `LungeAnalyzer`
Wraps `RepCounter` configured with both knee triples and `combination: .minimum`, thresholds like the squat (down ≈ 110°, up ≈ 160°, ROM ≈ 40°). `goalUnit = .reps`. `formCue = nil` (deferred).

### 3.4 `PlankAnalyzer`
- `goalUnit = .seconds`.
- Holds a `FormEvaluator` (body-line straightness) and accumulates time from `PoseFrame.timestamp`.
- Per frame: compute `FormEvaluation`.
  - `bodyLineAngle == nil` → pose not visible: `poseVisible = false`, no time added, `formCue = nil`.
  - body line present but `!isAcceptable` → visible but bad form: no time added, `formCue` = sag/pike text ("Lift your hips" / "Lower your hips").
  - acceptable → add `dt = clamp(timestamp - lastTimestamp, 0, maxStep)` to accumulated seconds (`maxStep ≈ 0.5s` so a dropped-frame gap can't add a huge jump). `formCue = nil`.
- `progress` = accumulated valid seconds. `didAdvance = false`.
- `reset()` clears accumulated time and `lastTimestamp`.

### 3.5 Registry
`ExerciseRegistry.all` and `makeAnalyzer(for:)` add `"lunge"` and `"plank"`. Order: pushup, squat, lunge, plank.

## 4. App changes (`CrazyWork`)

### 4.1 Planned/persisted sets
- `PlannedSet`: keep `exerciseID` + `target: Int` (interpreted as reps or seconds per the exercise's `goalUnit`).
- `ExerciseSet` (SwiftData): replace rep-specific fields with unit-aware ones:
  - `exerciseID`, `goalUnit: String`, `target: Int`, `completed: Double`, `averageFormScore: Double`, `findingsSummary: [String:Int]`, `order: Int`.
- `WorkoutSession.totalReps` becomes a small per-unit summary helper (e.g., total reps across rep-sets; planks summarized separately). History shows reps for rep-exercises and held time for planks.

### 4.2 SessionCoordinator
- Track `currentProgress: Double` instead of `currentReps: Int`; expose `currentTarget: Int` and the active exercise's `goalUnit`.
- Completion: `progress >= Double(currentTarget)`.
- Form-score accounting unchanged (fraction of visible frames with acceptable form).
- `SetResult` carries `goalUnit`, `target`, `completed` (Double), `averageFormScore`, `findingsSummary`.

### 4.3 Views
- **BuildWorkoutView:** exercise list from `ExerciseRegistry.all`; default target per unit (reps → 10, seconds → 30). Row label reflects unit ("Squat ×10", "Plank 30s").
- **LiveWorkoutView HUD:** format progress per unit — reps as `"7 / 12"`, seconds as `"0:18 / 0:30"` (mm:ss). Plank shows a "Hold!" affordance; the existing form-cue / reposition banners already cover sag/pike and lost-pose.
- **SummaryView / HistoryView:** show completed value per unit (reps vs. m:ss).

## 5. Testing

- **Engine (Swift Testing):**
  - `RepCounter` `.minimum` combination: a frame where only one knee is bent drives the rep; the straight knee doesn't mask it. Pushup/squat `.average` defaults unchanged (existing suite must stay green).
  - `LungeAnalyzer`: a single-leg down→up cycle counts one rep.
  - `PlankAnalyzer`: holding a straight body line accumulates ~the elapsed time; a sag interval adds no time and surfaces a cue; recovery resumes accumulation; a dropped-frame gap is clamped (no time jump).
- **App (XCTest):**
  - `SessionCoordinator` completes a seconds-goal set when accumulated plank time reaches target, and a reps-goal set as before.
  - Persistence round-trip for a unit-aware `ExerciseSet` (reps set and seconds set).

## 6. Risks / Notes
- Lunge and plank thresholds are heuristic (anatomy-based), consistent with the current squat decision; data-driven tuning is deferred.
- The `AnalyzerResult` rename (`count`→`progress`, `didCompleteRep`→`didAdvance`) and the `ExerciseSet` field changes ripple through the coordinator, views, and persistence tests — all updated in this change.
- Plank validity reuses `FormEvaluator`'s body-line check, whose orientation assumption (side view, y-up) already matches how pushups are framed.
