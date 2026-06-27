# Audio Coaching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a workout audio layer — a sound effect + spoken count on each rep, spoken form warnings, spoken plank milestones/countdown, and audible set/rest/finish transitions — that ducks the user's music while it plays.

**Architecture:** `SessionCoordinator.feed` returns a list of semantic `WorkoutEvent`s (a testable event seam, no closures or actor coupling). A pure `WorkoutAudioCoach` value type maps events → `[AudioAction]` (cadence, debounce, plank milestones). A `WorkoutAudioPlayer` executes actions via `AVSpeechSynthesizer` + `AudioServices` system sounds and manages the ducking audio session. `ChallengeCore` is untouched.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVSpeechSynthesizer`, `AVAudioSession`), AudioToolbox (`AudioServicesPlaySystemSound`), XCTest. iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`.

> **Spec:** `docs/superpowers/specs/2026-06-27-audio-coaching-design.md`
>
> **Note on the event seam:** The spec sketched an `onEvent` closure. This plan instead has `feed` *return* `[WorkoutEvent]`. Same architecture (coordinator emits facts; pure coach; player executes) but avoids main-actor/closure coupling and makes emission directly unit-testable. `feed`'s return is `@discardableResult`, so existing callers are unaffected.

---

## File Structure

- Create `CrazyWork/Sources/Session/WorkoutEvent.swift` — the `WorkoutEvent` enum.
- Modify `CrazyWork/Sources/Session/SessionCoordinator.swift` — `feed` returns events; `finishCurrentSet` contributes events.
- Create `CrazyWork/Sources/Audio/AudioAction.swift` — the `AudioAction` enum.
- Create `CrazyWork/Sources/Audio/WorkoutAudioCoach.swift` — pure event→action policy.
- Create `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift` — AVFoundation I/O + ducking session.
- Modify `CrazyWork/Sources/Views/LiveWorkoutView.swift` — drain events to the player; mute toggle.
- Modify `CrazyWork/Tests/SessionCoordinatorTests.swift` — assert emitted events.
- Create `CrazyWork/Tests/WorkoutAudioCoachTests.swift` — coach policy tests.

XcodeGen picks up new files under `Sources/` automatically on `xcodegen generate`; new test files under `Tests/` likewise.

---

### Task 1: Event seam — `WorkoutEvent` + coordinator emission

**Files:**
- Create: `CrazyWork/Sources/Session/WorkoutEvent.swift`
- Modify: `CrazyWork/Sources/Session/SessionCoordinator.swift` (`feed` ~60-82, `finishCurrentSet` ~97-115)
- Test: `CrazyWork/Tests/SessionCoordinatorTests.swift`

- [ ] **Step 1: Create the event type**

Create `CrazyWork/Sources/Session/WorkoutEvent.swift`:

```swift
import Foundation

/// A fact the workout produced on one fed frame. The coordinator emits these;
/// it knows nothing about audio. `WorkoutAudioCoach` turns them into sounds.
enum WorkoutEvent: Equatable {
    /// A rep-based exercise just completed rep `count` (the running total).
    case repCompleted(count: Int)
    /// A timed hold (plank) is at `seconds` of `target` seconds, this frame.
    case held(seconds: Double, target: Int)
    /// The current form cue this frame (`nil` when form is fine / pose lost).
    case formCue(String?)
    /// The set at `index` of `total` just finished.
    case setCompleted(index: Int, total: Int)
    /// Entering rest before the next set, which is `nextExerciseName`.
    case rest(nextExerciseName: String)
    /// The whole workout is done.
    case finished
}
```

- [ ] **Step 2: Write the failing emission tests**

Add to `CrazyWork/Tests/SessionCoordinatorTests.swift` (inside the class):

```swift
func testFeedReturnsRepAndCompletionEvents() {
    let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "squat", target: 1)])
    coord.start()
    var events: [WorkoutEvent] = []
    for f in SquatFrames.reps(1) { events += coord.feed(f) }
    XCTAssertTrue(events.contains(.repCompleted(count: 1)))
    XCTAssertTrue(events.contains(.setCompleted(index: 0, total: 1)))
    XCTAssertTrue(events.contains(.finished))
}

func testEmitsRestWithNextExerciseName() {
    let plan = [PlannedSet(exerciseID: "squat", target: 1),
                PlannedSet(exerciseID: "lunge", target: 1)]
    let coord = SessionCoordinator(plan: plan)
    coord.start()
    var events: [WorkoutEvent] = []
    for f in SquatFrames.reps(1) { events += coord.feed(f) }
    XCTAssertTrue(events.contains(.rest(nextExerciseName: "Lunge")))
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```bash
cd CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO \
  -only-testing:CrazyWorkTests/SessionCoordinatorTests 2>&1 | tail -20
```
Expected: FAILS to compile — `feed` returns `Void`, and `WorkoutEvent` cases aren't emitted yet.

- [ ] **Step 4: Make `feed` collect and return events**

In `CrazyWork/Sources/Session/SessionCoordinator.swift`, add a buffer property near the other private state (after `private var cuedFrames = 0`):

```swift
    private var pendingEvents: [WorkoutEvent] = []
```

Replace the whole `feed(_:)` method with:

```swift
    @discardableResult
    func feed(_ frame: PoseFrame) -> [WorkoutEvent] {
        pendingEvents = []
        guard phase == .active, var analyzer else { return [] }
        let result = analyzer.process(frame)
        self.analyzer = analyzer // write back the mutated struct

        poseVisible = result.poseVisible
        currentProgress = result.progress

        if result.poseVisible {
            visibleFrames += 1
            if let cue = result.formCue {
                cuedFrames += 1
                lastFormCue = cue
                cueCounts[cue, default: 0] += 1
            } else {
                lastFormCue = nil
            }
        }

        if result.didAdvance, goalUnit == .reps {
            pendingEvents.append(.repCompleted(count: Int(result.progress)))
        }
        if goalUnit == .seconds {
            pendingEvents.append(.held(seconds: result.progress, target: currentTarget))
        }
        pendingEvents.append(.formCue(result.poseVisible ? result.formCue : nil))

        if currentProgress >= Double(currentTarget) {
            finishCurrentSet()
        }
        return pendingEvents
    }
```

- [ ] **Step 5: Make `finishCurrentSet` contribute events**

Replace the `if currentSetIndex + 1 < plan.count { … } else { … }` tail of `finishCurrentSet()` with:

```swift
        pendingEvents.append(.setCompleted(index: currentSetIndex, total: plan.count))

        if currentSetIndex + 1 < plan.count {
            currentSetIndex += 1
            phase = .resting
            let nextID = plan[currentSetIndex].exerciseID
            let name = ExerciseRegistry.all.first { $0.id == nextID }?.displayName ?? nextID
            pendingEvents.append(.rest(nextExerciseName: name))
        } else {
            phase = .finished
            pendingEvents.append(.finished)
        }
```

(The `results.append(...)` above this stays unchanged; `setCompleted` is appended after the result is recorded.)

- [ ] **Step 6: Run the tests to verify they pass**

Run the same command as Step 3.
Expected: `SessionCoordinatorTests` all pass (the two new tests plus the existing three).

- [ ] **Step 7: Commit**

```bash
git add CrazyWork/Sources/Session/WorkoutEvent.swift \
        CrazyWork/Sources/Session/SessionCoordinator.swift \
        CrazyWork/Tests/SessionCoordinatorTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: emit WorkoutEvents from SessionCoordinator.feed

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Pure policy — `AudioAction` + `WorkoutAudioCoach`

**Files:**
- Create: `CrazyWork/Sources/Audio/AudioAction.swift`
- Create: `CrazyWork/Sources/Audio/WorkoutAudioCoach.swift`
- Test: `CrazyWork/Tests/WorkoutAudioCoachTests.swift`

- [ ] **Step 1: Create the action type**

Create `CrazyWork/Sources/Audio/AudioAction.swift`:

```swift
import Foundation

/// One unit of audio output. Pure data — `WorkoutAudioPlayer` executes it.
enum AudioAction: Equatable {
    case tick        // short blip on a rep / plank milestone
    case chime       // set complete
    case restBeep    // entering rest
    case fanfare     // workout finished
    case speak(String) // TTS phrase
}
```

- [ ] **Step 2: Write the failing coach tests**

Create `CrazyWork/Tests/WorkoutAudioCoachTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class WorkoutAudioCoachTests: XCTestCase {
    func testRepSpeaksNumberWithTick() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.repCompleted(count: 1)), [.tick, .speak("1")])
        XCTAssertEqual(coach.handle(.repCompleted(count: 2)), [.tick, .speak("2")])
    }

    func testCueSpokenOnceUntilItClears() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [.speak("Lower your hips")])
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [])      // repeated -> silent
        XCTAssertEqual(coach.handle(.formCue(nil)), [])                    // cleared -> re-arms
        XCTAssertEqual(coach.handle(.formCue("Lower your hips")), [.speak("Lower your hips")])
    }

    func testPlankAnnouncesTenSecondMilestonesOnce() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.held(seconds: 9.9, target: 35)), [])
        XCTAssertEqual(coach.handle(.held(seconds: 10.0, target: 35)), [.tick, .speak("10 seconds")])
        XCTAssertEqual(coach.handle(.held(seconds: 10.5, target: 35)), [])
        XCTAssertEqual(coach.handle(.held(seconds: 20.0, target: 35)), [.tick, .speak("20 seconds")])
    }

    func testPlankFinalCountdownEachNumberOnce() {
        var coach = WorkoutAudioCoach()
        _ = coach.handle(.held(seconds: 30.0, target: 35)) // clear the 30s milestone first
        XCTAssertEqual(coach.handle(.held(seconds: 32.0, target: 35)), [.speak("three")])
        XCTAssertEqual(coach.handle(.held(seconds: 33.0, target: 35)), [.speak("two")])
        XCTAssertEqual(coach.handle(.held(seconds: 34.0, target: 35)), [.speak("one")])
        XCTAssertEqual(coach.handle(.held(seconds: 34.6, target: 35)), [])
    }

    func testTransitionActions() {
        var coach = WorkoutAudioCoach()
        XCTAssertEqual(coach.handle(.setCompleted(index: 0, total: 2)), [.chime, .speak("Set complete")])
        XCTAssertEqual(coach.handle(.rest(nextExerciseName: "Lunge")),
                       [.restBeep, .speak("Rest. Next up: Lunge")])
        XCTAssertEqual(coach.handle(.finished), [.fanfare, .speak("Workout complete")])
    }

    func testSetCompletedResetsPerSetState() {
        var coach = WorkoutAudioCoach()
        _ = coach.handle(.held(seconds: 20.0, target: 35))   // milestone 20 recorded
        _ = coach.handle(.setCompleted(index: 0, total: 2))  // resets per-set state
        // Next set's plank should announce 10 again from scratch.
        XCTAssertEqual(coach.handle(.held(seconds: 10.0, target: 35)), [.tick, .speak("10 seconds")])
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```bash
cd CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO \
  -only-testing:CrazyWorkTests/WorkoutAudioCoachTests 2>&1 | tail -20
```
Expected: FAILS to compile — `WorkoutAudioCoach` doesn't exist.

- [ ] **Step 4: Implement the coach**

Create `CrazyWork/Sources/Audio/WorkoutAudioCoach.swift`:

```swift
import Foundation

/// Pure policy: turns `WorkoutEvent`s into `AudioAction`s with the right cadence
/// — tick + spoken number per rep, a cue spoken once per occurrence, plank
/// 10-second milestones and a 3-2-1 countdown, and set/rest/finish flourishes.
/// No clock and no I/O, so it is fully deterministic and unit-tested.
struct WorkoutAudioCoach {
    private var lastCue: String?
    private var lastMilestone = 0          // highest 10s mark already announced
    private var spokenCountdown: Set<Int> = []

    mutating func handle(_ event: WorkoutEvent) -> [AudioAction] {
        switch event {
        case let .repCompleted(count):
            return [.tick, .speak("\(count)")]
        case let .held(seconds, target):
            return plankActions(seconds: seconds, target: target)
        case let .formCue(cue):
            return cueActions(cue)
        case .setCompleted:
            resetPerSet()
            return [.chime, .speak("Set complete")]
        case let .rest(name):
            return [.restBeep, .speak("Rest. Next up: \(name)")]
        case .finished:
            return [.fanfare, .speak("Workout complete")]
        }
    }

    private mutating func cueActions(_ cue: String?) -> [AudioAction] {
        defer { lastCue = cue }
        guard let cue, cue != lastCue else { return [] }
        return [.speak(cue)]
    }

    private mutating func plankActions(seconds: Double, target: Int) -> [AudioAction] {
        var actions: [AudioAction] = []
        let milestone = Int(seconds) / 10 * 10          // 0, 10, 20, 30…
        if milestone >= 10, milestone > lastMilestone {
            lastMilestone = milestone
            actions += [.tick, .speak("\(milestone) seconds")]
        }
        let remaining = Double(target) - seconds
        for n in [3, 2, 1]
        where remaining <= Double(n) && remaining > Double(n) - 1 && !spokenCountdown.contains(n) {
            spokenCountdown.insert(n)
            actions.append(.speak(numberWord(n)))
        }
        return actions
    }

    private mutating func resetPerSet() {
        lastCue = nil
        lastMilestone = 0
        spokenCountdown = []
    }

    private func numberWord(_ n: Int) -> String {
        switch n {
        case 3: return "three"
        case 2: return "two"
        default: return "one"
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the same command as Step 3.
Expected: all six `WorkoutAudioCoachTests` pass.

- [ ] **Step 6: Commit**

```bash
git add CrazyWork/Sources/Audio/AudioAction.swift \
        CrazyWork/Sources/Audio/WorkoutAudioCoach.swift \
        CrazyWork/Tests/WorkoutAudioCoachTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: WorkoutAudioCoach maps workout events to audio actions

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: I/O edge — `WorkoutAudioPlayer`

**Files:**
- Create: `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift`

This is a thin AVFoundation adapter (no unit test — verified by build here and on device later).

- [ ] **Step 1: Implement the player**

Create `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift`:

```swift
import Foundation
import AVFoundation
import AudioToolbox

/// Executes `AudioAction`s: TTS via a shared speech synthesizer and SFX via
/// built-in iOS system sounds. Owns a `WorkoutAudioCoach` and a `.playback`
/// audio session that ducks the user's music while sounds play. Used on the
/// main thread only. System sound IDs are tunable — swap freely on device.
@MainActor
final class WorkoutAudioPlayer {
    /// When true, every action is a no-op (the in-workout mute toggle).
    var muted = false

    private var coach = WorkoutAudioCoach()
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive = false

    // Built-in iOS system sound IDs (see iphonedevwiki AudioServices list).
    private let tickSound: SystemSoundID = 1104      // keyboard "Tock"
    private let chimeSound: SystemSoundID = 1025      // short completion
    private let restBeepSound: SystemSoundID = 1113   // "Begin Record"
    private let fanfareSound: SystemSoundID = 1407    // upbeat flourish

    /// Translate one workout event into sound. Drains the coach.
    func handle(_ event: WorkoutEvent) {
        for action in coach.handle(event) { run(action) }
    }

    /// Stop speech and release the session so the user's music returns to full
    /// volume. Call when the live workout view goes away.
    func end() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    private func run(_ action: AudioAction) {
        guard !muted else { return }
        activateSessionIfNeeded()
        switch action {
        case .tick: AudioServicesPlaySystemSound(tickSound)
        case .chime: AudioServicesPlaySystemSound(chimeSound)
        case .restBeep: AudioServicesPlaySystemSound(restBeepSound)
        case .fanfare: AudioServicesPlaySystemSound(fanfareSound)
        case let .speak(text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        }
    }

    private func activateSessionIfNeeded() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        sessionActive = true
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: WorkoutAudioPlayer executes audio actions with music ducking

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire into the live workout + mute toggle

**Files:**
- Modify: `CrazyWork/Sources/Views/LiveWorkoutView.swift`

- [ ] **Step 1: Add the player and mute state**

In `LiveWorkoutView`, add these properties alongside the existing `@State` declarations (after `@State private var saved = false`):

```swift
    @State private var audioPlayer = WorkoutAudioPlayer()
    @AppStorage("workoutAudioEnabled") private var audioEnabled = true
```

- [ ] **Step 2: Drain events to the player in the frame loop**

In `run()`, replace the `for await sample in pipeline.frames { … }` loop body so it feeds the events to the player:

```swift
        for await sample in pipeline.frames {
            latestFrame = sample.frame
            latestImageSize = sample.imageSize
            for event in coordinator.feed(sample.frame) { audioPlayer.handle(event) }
            if coordinator.phase == .finished { break }
        }
        pipeline.stop() // camera off once the workout completes
```

- [ ] **Step 3: Apply mute and tear down the session**

In `run()`, set the initial mute state right after `coordinator.start()`:

```swift
        coordinator.start()
        audioPlayer.muted = !audioEnabled
```

Update the existing `.onDisappear` modifier to also end the audio session:

```swift
        .onDisappear {
            pipeline.stop()
            UIApplication.shared.isIdleTimerDisabled = false // let the screen sleep again
            audioPlayer.end()
        }
```

Add an `.onChange` after the `.onDisappear` modifier so the toggle takes effect live:

```swift
        .onChange(of: audioEnabled) { _, enabled in audioPlayer.muted = !enabled }
```

- [ ] **Step 4: Add a speaker toggle to the HUD**

In the `hud` computed view, wrap its content so the toggle sits above the count. Replace the `hud` property with:

```swift
    private var hud: some View {
        VStack(spacing: 8) {
            Button {
                audioEnabled.toggle()
            } label: {
                Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(audioEnabled ? "Mute audio" : "Unmute audio")

            VStack(spacing: 2) {
                Text(progressText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("Set \(coordinator.currentSetIndex + 1) of \(plan.count) · \(exerciseName)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
```

- [ ] **Step 5: Verify it builds**

Run:
```bash
cd CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add CrazyWork/Sources/Views/LiveWorkoutView.swift CrazyWork/CrazyWork.xcodeproj
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: play workout audio in the live view with a mute toggle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
(`.xcodeproj` is git-ignored; the `git add` of it is harmless if it no-ops.)

---

### Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run the engine tests:
```bash
cd ChallengeCore && swift test 2>&1 | tail -3
```
Expected: all pass.

Run the app tests:
```bash
cd CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -6
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Manual device checklist (note for the user)**

On device, start a workout and confirm: a tick + spoken number on each rep; a spoken cue once when form breaks ("lower your hips"); plank speaks "ten seconds", "twenty seconds", then "three/two/one"; "Set complete" + chime between sets and "Rest. Next up: …"; "Workout complete" at the end; background music dips while speaking and returns after; the speaker button mutes/unmutes and the choice persists.

- [ ] **Step 3: Push**

```bash
git push
```

---

## Self-Review Notes

- **Spec coverage:** rep tick+number (Task 2), spoken cues once-per-occurrence (Task 2), plank 10s milestones + 3-2-1 (Task 2), set/rest/finish (Task 2), system-sound SFX + ducking session (Task 3), event seam (Task 1), wiring + persisted mute (Task 4). All spec sections map to a task.
- **Per-set reset:** handled inside `.setCompleted` (`resetPerSet`) so plank milestones/cue re-arm for the next set with no view wiring — covered by `testSetCompletedResetsPerSetState`.
- **Type consistency:** `WorkoutEvent`/`AudioAction` case names and the `handle`/`end`/`run`/`muted` members are used identically across Tasks 1-4.
