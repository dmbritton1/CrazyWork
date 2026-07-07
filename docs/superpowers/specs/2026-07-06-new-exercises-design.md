# Three New Camera-Tracked Exercises: Jumping Jack, Mountain Climber, Wall Sit

**Date:** 2026-07-06
**Status:** Approved

## Goal

Add three exercises to ChallengeCore's camera tracking: jumping jacks (rep-based,
front-facing — the app's first), mountain climbers (rep-based, side-view), and
wall sits (time-based hold, side-view). Full app surface: analyzers + registry,
picker tiles, and tests. Premade Path programs are not changed.

## Decisions made during brainstorming

- **Jumping jack rep** requires arms *and* legs — arm-only half-jacks must not count.
- **Jack engine**: a dedicated dual-signal state machine (not an arm `RepCounter`
  with a leg check, and not a generalized `RepCounter`), so arm/leg synchronization
  is enforced at every state gate.
- **Mountain climber rep** = each knee drive (not left+right pairs).
- **Wall sit** gates on knee angle + torso verticality; no spoken form cues.
- **Scope**: analyzers, registry, `ExerciseTile` figures, tests. No `PathProgram`
  edits, no `RepCounter` changes, no watch/persistence changes (exercise ids are
  plain strings end-to-end and everything else drives off `ExerciseRegistry`).

## 1. `JumpingJackAnalyzer` (new state machine)

Definition: `("jumpingjack", "Jumping Jack", .reps, met: 8.0)`. Front-facing camera.

Two smoothed signals, each a `MovingAverage(windowSize: 5)`:

- **Arm raise**: hip·shoulder·wrist angle per side, sides averaged; a single
  detected side is used alone (mirrors `RepCounter`). Arms down ≈ 20°,
  overhead ≈ 170°.
- **Leg spread**: the leftAnkle·root·rightAnkle angle (vertex at root). Feet
  together ≈ 15°, jack stance ≈ 40–50°.

State machine with two states, hysteresis built into dual thresholds:

- Enter **open**: arms ≥ 140° AND legs ≥ 35° on the same smoothed frame.
- Enter **closed**: arms ≤ 60° AND legs ≤ 20°.
- Between the bands: hold current state (anti-jitter margin).
- `closed → open → closed` = one rep; `didAdvance` true on that frame.
- Minimum cycle duration 0.35 s, measured from leaving `closed` to re-entering
  it, rejects bounce double-counts.

Requiring both signals at each gate simultaneously is the synchronization
mechanism: arms-only or legs-only cycles never reach `open`.

Dropout handling (plank precedent): a signal whose joints fall below
`minConfidence` (default 0.5) holds its last smoothed value; `poseVisible` is
false only when neither signal is judgeable, and state is held, never reset.

All thresholds are `init` parameters with the defaults above (on-device tuning
knobs, house convention). No form cues (deferred, like squat/lunge).

## 2. `MountainClimberAnalyzer` (RepCounter config)

Definition: `("mountainclimber", "Mountain Climber", .reps, met: 8.0)`. Side-view.

A `RepCounter` wrapper, structurally a faster lunge:

```
RepCounterConfig(
    upThreshold: 150,        // leg extended back in plank
    downThreshold: 110,      // knee tucked toward chest
    minRepDuration: 0.3,     // fastest cadence in the app; primary tuning knob
    minRangeOfMotion: 35,
    repJoints: [shoulder·hip·knee left, shoulder·hip·knee right],
    combination: .minimum,   // the driven knee owns the signal; alternation works
    minAsymmetry: 30)        // both-knees tuck (crunch-like) does not count
```

Each knee drive is one down→up cycle of the minimum hip-flexion angle → each
drive counts 1 rep. No plank-orientation gate: the user selected the exercise;
standing high-knees counting as climbers is accepted. Form cues deferred.

## 3. `WallSitAnalyzer` (hold clock)

Definition: `("wallsit", "Wall Sit", .seconds, met: 4.0)`. Side-view. A
slimmed-down `PlankAnalyzer`: same accumulate-`dt`-while-gated clock, same
0.5 s per-frame `dt` cap, two gates, no cues. The camera cannot see the wall;
a free-standing chair pose counts, which is acceptable (same isometric work).

- **Knee gate** (position gate): smoothed knee angle (hip·knee·ankle, sides
  averaged via the plank's midpoint helper). Enter inside 70–110°, break
  outside 55–125° (widened band = hysteresis). Undetected knees hold the last
  verdict, **defaulting to false** — a never-established hold never counts
  (mirrors the plank arm-support gate).
- **Torso gate**: shoulder→hip tilt from *vertical*: enter ≤ 20°, break > 35°.
  Undetected torso holds the last verdict, **defaulting to true** (mirrors the
  plank form gate — partial visibility doesn't rob credit once established).

Clock runs only while both gates hold. Standing up straightens the knee past
125° and breaks the gate; sliding down the wall bends it below 55° and breaks
it too; leaning forward past 35° breaks the torso gate.
Pausing keeps accumulated seconds. All thresholds are `init` parameters.

## 4. Integration

- `ExerciseRegistry.all` gains the three definitions; `makeAnalyzer(for:)`
  gains the three cases. This is the single registration point — builder, live
  workout, watch, and `CalorieEstimator` (via `met`) pick them up automatically.
- `ExerciseTile.swift`: three new pose-figure cases in the existing stick-figure
  style — jack mid-flight (arms up, legs apart), climber (plank, one knee
  tucked), wall sit (seated against a vertical line).

## 5. Testing (`ExerciseAnalyzerTests.swift`, synthetic `PoseFrame` sequences)

- **Jumping jack**: full synchronized cycles count; arms-only cycles count 0;
  legs-only cycles count 0; mid-cycle joint dropout does not reset state;
  sub-0.35 s bounce does not double-count.
- **Mountain climber**: alternating knee drives count 1 each; symmetric
  both-knee tuck counts 0; shallow drives below range-of-motion count 0.
- **Wall sit**: accumulates at ~90° knee + vertical torso; standing pauses;
  leaning past the torso break pauses; accumulated time survives a pause;
  never-established knee gate counts 0 even with a vertical torso.

## Out of scope

`PathProgram.swift` premade plans, `RepCounter` changes, form cues for the new
exercises, watch code, persistence.
