# Audio Coaching — sound effects + spoken rep counts and form cues

**Date:** 2026-06-27
**Status:** Approved design

## Goal

Give the live workout an audio layer: a sound effect plus a spoken count on
every rep, spoken form warnings (e.g. "lower your hips"), and audible
transitions between sets and at the finish. Time-based planks get spoken
milestones and a final countdown instead of rep counts. App audio coexists with
the user's own music by ducking it briefly while speaking.

This is purely additive — no existing behavior changes except a small,
audio-agnostic event seam added to `SessionCoordinator`.

## Decisions (from brainstorming)

- **Rep counting:** a short tick the instant a rep completes (instant feedback,
  covers TTS latency) plus TTS speaking the running number ("one… two… three").
- **Plank:** speak a milestone every 10 s ("twenty seconds") with a tick, and a
  spoken 3-2-1 countdown into the finish. No per-second chatter.
- **SFX source:** built-in iOS system sounds (`AudioServices`) — no asset files,
  ships immediately, easy to swap for custom files later.
- **With music:** duck the user's music while speaking/dinging, then restore it.

## Architecture

A pure event→action coach, with audio I/O isolated at the edge. Mirrors the
codebase's existing pattern (pure, tested logic; `AVFoundation` only at the
boundary; `ChallengeCore` stays pure).

```
SessionCoordinator ──onEvent──▶ WorkoutAudioCoach ──[AudioAction]──▶ WorkoutAudioPlayer
   (emits facts)                (pure policy)                        (AVFoundation I/O)
```

All new code lives in the app target under `CrazyWork/Sources/Audio/`. The
coach and its event/action types are pure value types (no `AVFoundation`), so
they are unit-tested with a spy. The player is the only piece that touches audio
hardware.

## Components

### 1. Event seam — `SessionCoordinator`

Add a `WorkoutEvent` enum and `var onEvent: ((WorkoutEvent) -> Void)?`. The
coordinator emits facts; it does not know about audio.

```swift
enum WorkoutEvent: Equatable {
    case repCompleted(count: Int)        // rep exercises, on a completed rep
    case held(seconds: Double, target: Int) // plank, each processed frame
    case formCue(String?)                // current form cue, each frame
    case setCompleted(index: Int, total: Int)
    case rest(nextExerciseName: String)
    case finished
}
```

Emission points (existing methods):
- `feed(_:)`: when `result.didAdvance` and goal is `.reps` →
  `repCompleted(Int(result.progress))`. When goal is `.seconds` →
  `held(result.progress, currentTarget)`. Always →
  `formCue(result.poseVisible ? result.formCue : nil)`.
- `finishCurrentSet()`: `setCompleted(index, total)`, then either
  `rest(nextName)` (more sets) or `finished` (last set). Next name resolved via
  `ExerciseRegistry`.

This is the only change to existing files.

### 2. `WorkoutAudioCoach` (pure policy — the heart)

A value type that consumes `WorkoutEvent`s, holds minimal state, and returns the
audio actions to perform. No clock, no I/O — deterministic and fully testable.

```swift
enum AudioAction: Equatable {
    case tick            // rep / plank milestone
    case chime           // set complete
    case restBeep        // entering rest
    case fanfare         // workout finished
    case speak(String)   // TTS phrase
}

struct WorkoutAudioCoach {
    mutating func handle(_ event: WorkoutEvent) -> [AudioAction]
    mutating func reset()
}
```

Policy:
- `repCompleted(n)` → `[.tick, .speak("\(n)")]`.
- `formCue(cue)` → speak **only on onset/change**: if `cue` is non-nil and
  differs from the last cue, `[.speak(cue)]`; otherwise `[]`. When `cue` becomes
  nil the "last cue" re-arms, so re-entering the same fault speaks again. (No
  clock needed; a persistent fault is spoken once per occurrence.)
- `held(seconds, target)`:
  - Crossing each new 10 s boundary (≥10) → `[.tick, .speak("\(m) seconds")]`.
  - Final countdown: when `remaining = target - seconds` first drops to 3, 2,
    1 → `[.speak("three" | "two" | "one")]`, each spoken once.
- `setCompleted` → `[.chime, .speak("Set complete")]`.
- `rest(name)` → `[.restBeep, .speak("Rest. Next up: \(name)")]`.
- `finished` → `[.fanfare, .speak("Workout complete")]`.

State: last spoken cue, last plank milestone (×10 s), set of spoken countdown
numbers. `reset()` clears all (called per set load).

### 3. `WorkoutAudioPlayer` (I/O edge)

`@MainActor` class that executes `[AudioAction]`:
- TTS via a single shared `AVSpeechSynthesizer`.
- SFX via `AudioServicesPlaySystemSound` with built-in iOS system sound IDs
  (tick = Tock; chime/restBeep/fanfare mapped to suitable system sounds).
- Audio session: `.playback` category with `[.duckOthers, .mixWithOthers]`,
  activated on first use; deactivated with `.notifyOthersOnDeactivation` when the
  workout view goes away so the user's music returns to full volume.
- Honors a `muted` flag (no-ops when muted).

### 4. Wiring + mute — `LiveWorkoutView`

- Owns a `WorkoutAudioPlayer` and a `WorkoutAudioCoach`.
- Sets `coordinator.onEvent = { event in coach.handle(event).forEach(player.run) }`.
- A speaker button in the HUD toggles mute, persisted via
  `@AppStorage("workoutAudioEnabled")` (default on).
- The existing `.onDisappear` also tears down the audio session.

## Testing

`WorkoutAudioCoachTests` (app target, XCTest) drive the pure coach and assert
the returned actions:
- Rep completed → `[.tick, .speak("3")]`.
- Same form cue across many frames → spoken once; clears and re-fires →
  spoken again.
- Plank crossing 10/20/30 s → tick + spoken milestone each; remaining 3/2/1 →
  spoken countdown each once.
- `setCompleted` / `rest` / `finished` → expected actions and phrases.

The player is a thin I/O adapter and is exercised manually on device.

## Out of scope (YAGNI)

- Haptics on reps.
- Custom/branded audio files (system sounds now; the `AudioAction` seam makes
  swapping trivial later).
- Configurable voices/speech rate, and spoken "reposition" prompts (the visual
  banner already covers repositioning).
