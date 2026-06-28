# Sit-up + Glute Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two reps-based bodyweight exercises — Sit-up and Glute Bridge — driven by the hip angle (shoulder·hip·knee), reusing the existing rep engine.

**Architecture:** Two new analyzers in `ExerciseAnalyzer.swift` mirroring `SquatAnalyzer` (average the angle over both sides, no form cues), plus two `ExerciseRegistry` entries. Everything downstream (builder, premade plans, stats, audio, persistence) is registry-driven and needs no changes.

**Tech Stack:** Swift 6, `ChallengeCore` package, Swift Testing (`@Test`/`#expect`). Engine tested with `swift test` in `ChallengeCore/`; app build on iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`.

## Global Constraints

- Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).
- No engine (`RepCounter`) changes — analyzers only.
- New analyzers carry no form cues (parity with `SquatAnalyzer`/`LungeAnalyzer`).

> **Spec:** `docs/superpowers/specs/2026-06-27-situp-glutebridge-design.md`

---

### Task 1: Sit-up + Glute Bridge analyzers and registry entries

**Files:**
- Modify: `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` (add two structs before `public enum ExerciseRegistry`; add two `.all` entries and two `makeAnalyzer` cases)
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift`

**Interfaces:**
- Consumes: existing `RepCounterConfig(upThreshold:downThreshold:minRangeOfMotion:minConfidence:repJoints:)`, `JointTriple`, `RepCounter`, `ExerciseAnalyzer`, `ExerciseDefinition`; test helpers `angleFrame(_:t:left:right:confidence:)` and `cycle(_:start:)` already in the test file.
- Produces: `SitupAnalyzer()` (id `"situp"`), `GluteBridgeAnalyzer()` (id `"glutebridge"`), both `goalUnit .reps`; registry lookups (`ExerciseRegistry.all`, `makeAnalyzer(for:)`) include both.

- [ ] **Step 1: Write the failing tests**

Add these three tests inside the `ExerciseAnalyzerTests` struct in `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift` (e.g. right after the `squatCounts` test):

```swift
    @Test("SitupAnalyzer counts one rep from torso flexion")
    func situpCounts() {
        var a = SitupAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("GluteBridgeAnalyzer counts one rep from hip extension")
    func gluteBridgeCounts() {
        var a = GluteBridgeAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        for f in cycle(make, start: 0) { _ = a.process(f) }
        #expect(a.progress == 1)
    }

    @Test("GluteBridgeAnalyzer ignores a shallow bridge that never reaches lockout")
    func gluteBridgeIgnoresShallow() {
        var a = GluteBridgeAnalyzer()
        let make: (Double, TimeInterval) -> PoseFrame = {
            self.angleFrame($0, t: $1,
                            left: (.leftShoulder, .leftHip, .leftKnee),
                            right: (.rightShoulder, .rightHip, .rightKnee))
        }
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<8 { frames.append(make(120, t)); t += 0.1 } // on the floor (down)
        for _ in 0..<8 { frames.append(make(145, t)); t += 0.1 } // partial lift, below the 155 lockout
        for _ in 0..<8 { frames.append(make(120, t)); t += 0.1 } // back down
        for f in frames { _ = a.process(f) }
        #expect(a.progress == 0)
    }
```

Then update the existing `registry` test in the same file. Replace:

```swift
    func registry() {
        #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "plank")?.definition.goalUnit == .seconds)
        #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
        #expect(Set(ExerciseRegistry.all.map(\.id)) == ["pushup", "squat", "lunge", "plank"])
    }
```

with:

```swift
    func registry() {
        #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "plank")?.definition.goalUnit == .seconds)
        #expect(ExerciseRegistry.makeAnalyzer(for: "situp")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "glutebridge")?.definition.goalUnit == .reps)
        #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
        #expect(Set(ExerciseRegistry.all.map(\.id))
                == ["pushup", "squat", "lunge", "plank", "situp", "glutebridge"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -20
```
Expected: FAILS to compile — `SitupAnalyzer` / `GluteBridgeAnalyzer` don't exist.

- [ ] **Step 3: Add the two analyzers**

In `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift`, insert these two structs immediately BEFORE the `/// Maps an exercise id ...` comment that precedes `public enum ExerciseRegistry`:

```swift
/// Sit-ups: torso-flexion angle (shoulder·hip·knee, both sides averaged) drives
/// reps. Lying flat is extended; crunching up is bent. Form coaching deferred.
public struct SitupAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "situp", displayName: "Sit-up", goalUnit: .reps)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 130, downThreshold: 90, minRangeOfMotion: 40,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
            ])
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}

/// Glute bridges: hip-extension angle (shoulder·hip·knee, both sides averaged)
/// drives reps. Hips on the floor is bent; the bridge is extended. The range of
/// motion is narrow, so these thresholds are the on-device tuning knob. Form
/// coaching deferred.
public struct GluteBridgeAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "glutebridge", displayName: "Glute Bridge", goalUnit: .reps)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 155, downThreshold: 130, minRangeOfMotion: 25,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
            ])
        self.counter = RepCounter(config: config)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let update = counter.process(frame)
        return AnalyzerResult(progress: Double(update.count), didAdvance: update.didCompleteRep,
                              poseVisible: update.poseVisible, formCue: nil)
    }

    public mutating func reset() { counter = RepCounter(config: config) }
}
```

- [ ] **Step 4: Register them**

In the same file, in `ExerciseRegistry`, add the two definitions to `all` (after `PlankAnalyzer().definition,`):

```swift
        PlankAnalyzer().definition,
        SitupAnalyzer().definition,
        GluteBridgeAnalyzer().definition,
    ]
```

and add the two cases to `makeAnalyzer(for:)` (after the `"plank"` case):

```swift
        case "plank": return PlankAnalyzer()
        case "situp": return SitupAnalyzer()
        case "glutebridge": return GluteBridgeAnalyzer()
        default: return nil
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -4
```
Expected: all pass (the three new analyzer tests + the updated `registry` test, plus the existing suite).

- [ ] **Step 6: Confirm the app target still builds (registry change compiles app-side)**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (The builder's "Add exercise" list and stats lookups pick up the two new exercises automatically via `ExerciseRegistry`.)

- [ ] **Step 7: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: add sit-up and glute bridge exercises

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** `SitupAnalyzer` + `GluteBridgeAnalyzer` with the specified ids/names/thresholds and shoulder·hip·knee triples (Step 3); registry entries (Step 4); rep-count tests + shallow-rejection test + registry test update (Step 1); app-build confirmation that downstream is registry-driven (Step 6). All spec sections map to this task.
- **Threshold/arg order:** `RepCounterConfig(upThreshold:downThreshold:minRangeOfMotion:minConfidence:repJoints:)` matches the existing `LungeAnalyzer` call pattern (skipping the defaulted `minRepDuration`/`smoothingWindow`), so it compiles.
- **Test math:** `cycle` drives 175→25→175; for sit-up (up 130 / down 90) and glute bridge (up 155 / down 130) that crosses both thresholds with ROM 150 → exactly one rep each. The shallow test stays between 120 and 145, never crossing the 155 lockout → zero reps.
- **Type consistency:** `SitupAnalyzer`, `GluteBridgeAnalyzer`, ids `"situp"`/`"glutebridge"` used identically in the structs, registry, and tests.
