# New Exercises: Sit-up + Glute Bridge

**Date:** 2026-06-27
**Status:** Approved design

## Goal

Add two bodyweight, side-view exercises — **Sit-up** and **Glute Bridge** —
that reuse the existing rep engine. Both are reps-based and driven by the hip
angle (`shoulder·hip·knee`). No engine changes; just two analyzers and registry
entries.

## Why these fit cheaply

The codebase uses Approach B: each exercise is an analyzer wrapping the shared
`RepCounter` over a configured joint triple (see `SquatAnalyzer`, which averages
both knees). Both new exercises are the same shape — average the hip angle over
both sides — so each is a config plus a registry line. Everything downstream
(`BuildWorkoutView`, `PremadePlanCatalog`, `StatsView`/`HistoryView`, audio,
persistence) reads `ExerciseRegistry`, so they need no changes.

## Components

### Analyzers — `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift`

Both mirror `SquatAnalyzer`: rep-only, `.average` combination, no form cues
(parity with squat/lunge). Joint triple: `JointTriple(.leftShoulder, .leftHip,
.leftKnee)` and the right-side equivalent.

- **`SitupAnalyzer`** — `id "situp"`, displayName "Sit-up", `goalUnit .reps`.
  Lying flat = extended hip (large angle); crunched up = bent (small). One rep =
  lie → crunch → return. Config: `upThreshold 130, downThreshold 90,
  minRangeOfMotion 40`.
- **`GluteBridgeAnalyzer`** — `id "glutebridge"`, displayName "Glute Bridge",
  `goalUnit .reps`. Hips on floor = bent (small angle); bridge up = extended
  (large). One rep = floor → bridge → floor. Config: `upThreshold 155,
  downThreshold 130, minRangeOfMotion 25`.

Both motions map onto `RepCounter`'s existing up/down hysteresis unchanged: the
counter enters `.down` below `downThreshold` and completes a rep when the angle
returns above `upThreshold`. Sit-up starts at the extended (up) pose and the rep
fires on the return; glute bridge starts at the floor (down) pose and fires on
the bridge. No `RepCounter` changes.

### Registry — same file

Add both definitions to `ExerciseRegistry.all` and both cases to
`makeAnalyzer(for:)` (`"situp"` → `SitupAnalyzer()`, `"glutebridge"` →
`GluteBridgeAnalyzer()`).

## Testing — `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift`

Using the existing `angleFrame` helper with the `shoulder·hip·knee` triple
(mirroring `squatCounts`):

- `situpCounts` — a full cycle through the sit-up thresholds yields one rep.
- `gluteBridgeCounts` — a full cycle through the bridge thresholds yields one rep.
- One shallow-rep rejection: a partial cycle that doesn't clear
  `minRangeOfMotion` yields zero reps (covers the narrow-ROM gate).
- Extend the `registry` test to expect the two new ids and `.reps` goal units.

## Out of scope (YAGNI)

- Form cues (the `FormEvaluator` is push-up body-line specific; squat/lunge have
  none either).
- Any UI, persistence, or premade-plan changes — all registry-driven already.
- Adding the new exercises to existing premade plans (can follow later).

## Real-world note

The thresholds are starting points, not measured. The glute-bridge range of
motion is narrow (~25–30°), so it is the most likely to need on-device tuning;
the threshold constants are the calibration knob.
