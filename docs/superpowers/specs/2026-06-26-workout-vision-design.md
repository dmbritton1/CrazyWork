# WorkoutVision — Design Spec

**Date:** 2026-06-26
**Status:** Approved for planning
**Working name:** WorkoutVision (rename TBD)

## 1. Summary

A native iOS workout app that uses the device camera and Apple's Vision
framework to count repetitions and score form across multiple bodyweight
exercises. It adapts the proven pose-analysis logic from the **WakeupCall**
repo (`dmbritton1/WakeupCall`), generalizing its pushup-specific `ChallengeCore`
engine into a multi-exercise engine, and wraps it in a workout-session loop
with saved history.

**v1 scope:** pushups (carried over) + squats (new), with sit-ups optional.
The architecture is built so additional exercises — and higher product layers
(guided programs, gamification, an AI coach) — can bolt on later without
rework.

### North-star vision (context, not v1 scope)

The full product these pieces stack toward:

```
        AI personal trainer        ← conversational layer
        Gamification / challenges   ← motivation layer
        Guided programs             ← structure layer
  ┌─────────────────────────────┐
  │  Universal rep-counter +     │  ← v1: THE FOUNDATION
  │  form coach (the engine)     │
  └─────────────────────────────┘
```

v1 builds only the foundation. Everything above is deliberately out of scope
but must not be architecturally blocked.

## 2. Goals & Non-Goals

### Goals
- Generalize `ChallengeCore` from a single hardcoded exercise to a protocol
  that any exercise can implement.
- Ship a working camera-based rep counter + form coach for **pushups and
  squats**.
- Provide a real "workout app" loop: build a session → perform it with live
  feedback → save it → review history.
- Keep the engine pure (no UI/storage dependencies) and unit-tested via the
  existing fixture-replay approach.

### Non-Goals (v1)
- No AlarmKit / alarm dismissal flow (WakeupCall's original hook) — dropped.
- No widget / Live Activity.
- No guided multi-day programs, gamification, streaks, or social features.
- No AI/conversational coaching.
- No per-rep persisted detail (per-set aggregate only).
- No Android / web / cross-platform — native iOS only.

## 3. Platform & Reuse

- **Platform:** Native iOS, Apple stack only.
  - Swift 6 / SwiftUI (UI)
  - Vision framework (`DetectHumanBodyPoseRequest`) for pose detection
  - AVFoundation (camera capture)
  - SwiftData (persistence)
  - XcodeGen (`project.yml`) as the project source of truth, matching WakeupCall.
- **Reused from WakeupCall:**
  - The capture layer (AVFoundation session → Vision request → pose stream).
  - The `ChallengeCore` Swift package skeleton, geometry helpers, and the
    **fixture-replay test harness** (replays recorded pose sequences; runs on
    macOS with no device/simulator).
  - The existing pushup state-machine logic, refactored to become the first
    conformer of the new protocol.
- **Dropped from WakeupCall:** AlarmKit backend, local-notification alarm
  backend, the widget extension.

## 4. Architecture Overview

Two layers, strictly separated:

1. **`ChallengeCore`** (pure Swift package) — pose frames in, rep events out.
   No UI, no SwiftData, no AVFoundation imports. Independently testable.
2. **`WorkoutVision`** (app target) — camera capture, SwiftUI views, the
   session coordinator, and SwiftData persistence.

```
 Camera (AVFoundation)
        │  CMSampleBuffer
        ▼
 Vision pose request ──► PoseFrame stream
        │
        ▼
 ExerciseAnalyzer (ChallengeCore)  ──► [RepEvent]
        │                                  │
        ▼                                  ▼
 Session Coordinator  ───────────► aggregate into ExerciseSet
        │                                  │
        ▼                                  ▼
 SwiftUI views (live feedback)     SwiftData (WorkoutSession)
```

The engine never knows about the app; the app talks to the engine only through
the `ExerciseAnalyzer` protocol and the `RepEvent` value type.

## 5. The Engine (`ChallengeCore`) — Approach B: protocol-based strategies

We chose **protocol-based exercise strategies** over a declarative config. Each
exercise owns its own state machine and form rules, so a future quirky exercise
(timed plank, jumping jacks) can implement the protocol however it needs,
rather than being forced into one config schema.

### 5.1 Core value types

- **`PoseFrame`** — a timestamped set of body joints, each with a normalized
  position and a confidence value. (Carried/adapted from WakeupCall.)
- **`ExerciseInfo`** — static metadata: `id` (stable string), `displayName`,
  the joints the exercise tracks.
- **`RepEvent`** — emitted when a rep completes. Carries:
  - `repIndex: Int`
  - `formScore: Double` (0.0–1.0)
  - `findings: [Finding]`
- **`Finding`** — a single form note (e.g. `.shallowDepth`, `.backNotStraight`,
  `.kneesCaving`), used for live cues and for aggregation into history.
- **`TrackingStatus`** — `.tracking` / `.lowConfidence` / `.outOfFrame`, so the
  app can render "step back" states. Emitted alongside processing.

### 5.2 The protocol

```swift
protocol ExerciseAnalyzer {
    var info: ExerciseInfo { get }
    var status: TrackingStatus { get }
    mutating func process(_ frame: PoseFrame) -> [RepEvent]
    mutating func reset()
}
```

- `process(_:)` is fed pose frames one at a time and returns any reps that
  completed on that frame (usually 0 or 1). It also updates `status`.
- Each conformer manages its own internal state.

### 5.3 Shared machinery (prevents B from becoming copy-paste)

- **`AngleMath`** — compute a joint angle from three joints (vertex + two
  endpoints).
  - Pushup rep angle: shoulder · **elbow** · wrist
  - Squat rep angle: hip · **knee** · ankle
- **`HysteresisRepDetector`** — a reusable helper that detects a complete
  down→up cycle given two thresholds (a "down" threshold and an "up"
  threshold). The gap between thresholds suppresses jitter and double-counts.
  Also enforces `minRepDuration`. Exercises may use it or roll their own.
- **`ConfidenceGate`** — shared logic for deciding `TrackingStatus` from joint
  confidences and visibility.

### 5.4 v1 conformers

- **`PushupAnalyzer`** — the existing WakeupCall pushup logic, refactored to
  conform. Rep angle = elbow; form rules = depth (elbow below threshold at
  bottom) and body-line straightness (shoulder–hip–ankle roughly collinear).
  Refactoring this first validates that the protocol fits real, proven code.
- **`SquatAnalyzer`** — new. Rep angle = knee; form rules = depth (thigh near
  parallel / knee angle below threshold at bottom), torso lean within range,
  and knee tracking (knees not collapsing inward).
- **`SitupAnalyzer`** *(optional / stretch)* — torso-to-thigh angle drives reps.
- **`ExerciseRegistry`** — maps an exercise `id` → a factory that returns a
  fresh analyzer instance.

### 5.5 Form scoring

Each analyzer produces a per-rep `formScore` in [0,1] by combining its rule
checks (e.g. depth + straightness), plus the list of `Finding`s that explain
any deductions. Scoring weights live inside each analyzer.

## 6. App Shell (`WorkoutVision`)

### 6.1 Layers

- **Capture layer (reused):** AVFoundation camera session → Vision
  `DetectHumanBodyPoseRequest` → `PoseFrame` stream published to the active
  analyzer. Runs pose detection on-device.
- **Session coordinator:** holds the planned sets for the session, tracks
  "set N of M," manages rest between sets, swaps the active `ExerciseAnalyzer`
  via `ExerciseRegistry` when the exercise changes, aggregates `RepEvent`s into
  the current `ExerciseSet`, and decides when a set/session is complete. Also
  surfaces the current `TrackingStatus` to the Live view.
- **Persistence:** SwiftData (Section 7).

### 6.2 Screens

1. **Build Workout** — add exercises into a session and set targets
   (e.g. 3 sets × 12 squats, 3 sets × 10 pushups). Start the session.
2. **Live Workout** — the main screen:
   - Camera preview with a **skeleton overlay** drawn from the detected joints.
   - Large **live rep counter** + set indicator ("Set 2/3 · 7/12").
   - **Real-time form cues** surfaced from the analyzer's `Finding`s
     ("go deeper", "straighten back").
   - A **"step back / get in frame"** state driven by `TrackingStatus`.
3. **Set / Session Summary** — reps completed, average form score, top
   findings; Save.
4. **History** — list of past `WorkoutSession`s + simple progress views
   (total reps over time; per-exercise form-score trend).

### 6.3 Navigation flow

```
Build ──► Live ──(rest)──► Live ... ──► Summary ──► saved ──► History
            └── loops through sets via the coordinator ──┘
```

Each screen maps cleanly to a coordinator state; each is single-purpose.

## 7. Data Model & Persistence (SwiftData)

Per-set aggregate only (no per-rep rows in v1). Exercises live in code (the
registry), referenced by string `exerciseID` — there is no `Exercise` table to
keep in sync.

- **`WorkoutSession`** (`@Model`)
  - `id`
  - `startedAt`, `endedAt`
  - `sets: [ExerciseSet]` (relationship)
  - total reps / average form are computed, not stored.
- **`ExerciseSet`** (`@Model`)
  - `exerciseID` (matches `ExerciseAnalyzer.info.id`)
  - `targetReps`, `completedReps`
  - `averageFormScore`
  - `findingsSummary` — small encodable blob, e.g. `["shallow_depth": 3]`
  - `order` (position within the session)

**Rationale:** `ChallengeCore` never imports SwiftData; the app aggregates
`RepEvent`s into an `ExerciseSet` and persists. Per-rep detail, if ever wanted,
is a purely additive child model later — no migration of existing data.

## 8. Edge Cases & Error Handling

- **Person not fully in frame / low confidence:** analyzer gates on
  `minConfidence`; sub-threshold frames don't count. Live view shows a
  "step back so I can see you" state (`TrackingStatus.outOfFrame` /
  `.lowConfidence`).
- **Jitter / double-counts:** `HysteresisRepDetector` two-threshold band plus
  `minRepDuration`; a fast twitch cannot register two reps.
- **Partial reps:** a rep counts only on a complete down→up cycle. An aborted
  dip resets state without counting but may emit a "didn't go deep enough"
  finding.
- **Multiple people in frame:** track only the single most prominent pose
  (largest / highest-confidence body).
- **No camera permission:** Live screen is gated behind a permission check with
  a clear explainer and a Settings deep-link; never a black-screen crash.
- **Bad lighting / occlusion:** confidence gating; if confidence stays low for
  several seconds, surface a gentle "having trouble seeing you — improve
  lighting?" hint.
- **App backgrounded mid-set:** pause the session and camera; resume cleanly
  without losing the in-progress set.

Responsibility split: confidence/state handling lives **inside each analyzer**;
"is the user trackable right now?" status is surfaced by the
**coordinator/Live view**.

## 9. Testing Strategy

- **Engine (primary coverage):** extend WakeupCall's **fixture-replay** harness.
  Record pose sequences for squats (and sit-ups if included), feed them through
  the relevant analyzer, and assert on rep counts, form scores, and findings.
  Pure, deterministic, runs on macOS with no device. Keep/port the existing
  pushup fixtures as the regression baseline that the refactor must still pass.
- **Shared machinery:** unit-test `AngleMath`, `HysteresisRepDetector`
  (including jitter / partial-rep / debounce cases), and `ConfidenceGate`
  directly.
- **App layer (lighter):** coordinator state-progression tests (set advance,
  rest, session completion) with a stubbed analyzer; basic persistence
  round-trip tests for SwiftData models. UI verified manually on device for v1.

## 10. Open Questions / Future Hooks

- Sit-ups: included in v1 or deferred? (Currently optional/stretch.)
- Final app name.
- Future layers (programs, gamification, AI coach) intentionally deferred; the
  string `exerciseID` boundary and the pure-engine separation are the seams
  they will attach to.
