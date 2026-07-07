# Jumping Jack, Mountain Climber, Wall Sit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three camera-tracked exercises to ChallengeCore — jumping jacks (dual-signal rep state machine), mountain climbers (RepCounter config), wall sits (gated hold clock) — plus registry entries and picker tiles.

**Architecture:** All analyzers live in `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` alongside the existing six, conforming to the `ExerciseAnalyzer` protocol. Mountain climber wraps the existing `RepCounter`; wall sit mirrors `PlankAnalyzer`'s accumulate-while-gated clock; jumping jack is a new two-signal state machine reusing `MovingAverage` and `Geometry.angle`. Registration is one array + one switch in `ExerciseRegistry`; the rest of the app (builder, live view, watch, calories) drives off the registry.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`@Test`/`#expect` — NOT XCTest), SwiftUI Canvas for tiles.

**Spec:** `docs/superpowers/specs/2026-07-06-new-exercises-design.md`

## Global Constraints

- Exercise ids are exactly `"jumpingjack"`, `"mountainclimber"`, `"wallsit"`; display names `"Jumping Jack"`, `"Mountain Climber"`, `"Wall Sit"`; METs `8.0`, `8.0`, `4.0`.
- ChallengeCore is a pure core: no Vision/AVFoundation/UIKit imports, value types only.
- All analyzer thresholds are `init` parameters with defaults (house convention: on-device tuning knobs).
- **Build products must never land inside the repo** (iCloud Desktop xattrs break codesign). Core tests: `swift test --scratch-path "$TMPDIR/challengecore-build"` run from `ChallengeCore/`. App builds: pass `SYMROOT="$TMPDIR/crazywork-symroot"`.
- Tests use the Swift Testing framework, matching `ExerciseAnalyzerTests.swift` style: private frame-builder helpers, `#expect`.
- Do NOT modify `RepCounter.swift`, `PathProgram.swift`, watch code, or persistence.
- Commit after each task with a `feat:`/`test:` conventional message ending in the Claude co-author trailer.

---

### Task 1: `MountainClimberAnalyzer` (RepCounter config)

**Files:**
- Modify: `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` (insert after `GluteBridgeAnalyzer`, before `ExerciseRegistry`)
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift`

**Interfaces:**
- Consumes: `RepCounter`, `RepCounterConfig`, `JointTriple`, `ExerciseAnalyzer` protocol (all existing).
- Produces: `public struct MountainClimberAnalyzer: ExerciseAnalyzer` with `init(minConfidence: Double = 0.5)`; definition id `"mountainclimber"`. Task 4 registers it.

- [ ] **Step 1: Write the failing tests**

Add to `ExerciseAnalyzerTests` (inside the struct). First a frame helper for independent left/right hip-flexion angles, mirroring the existing `legFrame` helper:

```swift
/// Torsos with independent hip-flexion angles (for mountain climber).
private func hipFrame(leftHip: Double, rightHip: Double, t: TimeInterval,
                      confidence: Double = 0.9) -> PoseFrame {
    func side(_ deg: Double) -> (Point2D, Point2D, Point2D) {
        let rad = deg * .pi / 180
        return (Point2D(x: cos(rad), y: sin(rad)), Point2D(x: 0, y: 0), Point2D(x: 1, y: 0))
    }
    let (ls, lh, lk) = side(leftHip)
    let (rs, rh, rk) = side(rightHip)
    func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
    return PoseFrame(timestamp: t, joints: [
        .leftShoulder: jp(ls), .leftHip: jp(lh), .leftKnee: jp(lk),
        .rightShoulder: jp(rs), .rightHip: jp(rh), .rightKnee: jp(rk),
    ])
}

@Test("MountainClimberAnalyzer counts each knee drive as one rep")
func mountainClimberCountsEachDrive() {
    var a = MountainClimberAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // plank
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 90, rightHip: 175, t: t));  t += 0.1 } // left drive
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // back
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 90, t: t));  t += 0.1 } // right drive
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 } // back
    for f in frames { _ = a.process(f) }
    #expect(a.progress == 2)
}

@Test("MountainClimberAnalyzer ignores a symmetric both-knee tuck")
func mountainClimberIgnoresSymmetricTuck() {
    var a = MountainClimberAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 90, rightHip: 90, t: t));   t += 0.1 } // both tuck
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
    for f in frames { _ = a.process(f) }
    #expect(a.progress == 0)
}

@Test("MountainClimberAnalyzer ignores a shallow drive that never tucks")
func mountainClimberIgnoresShallow() {
    var a = MountainClimberAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 120, rightHip: 175, t: t)); t += 0.1 } // above the 110 tuck line
    for _ in 0..<8 { frames.append(hipFrame(leftHip: 175, rightHip: 175, t: t)); t += 0.1 }
    for f in frames { _ = a.process(f) }
    #expect(a.progress == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: compile error — `cannot find 'MountainClimberAnalyzer' in scope`.

- [ ] **Step 3: Implement the analyzer**

Insert into `ExerciseAnalyzer.swift` after `GluteBridgeAnalyzer` (before `ExerciseRegistry`):

```swift
/// Mountain climbers: hip-flexion angle (shoulder·hip·knee), `.minimum`
/// combination so the driven knee owns the signal — each knee drive is one
/// down→up cycle, so alternating legs counts 1 per drive. `minAsymmetry`
/// rejects a symmetric both-knee tuck. No plank-orientation gate: the user
/// selected the exercise. Form coaching deferred.
public struct MountainClimberAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "mountainclimber", displayName: "Mountain Climber", goalUnit: .reps, met: 8.0)
    private let config: RepCounterConfig
    private var counter: RepCounter

    public var progress: Double { Double(counter.count) }

    public init(minConfidence: Double = 0.5) {
        self.config = RepCounterConfig(
            upThreshold: 150, downThreshold: 110,
            // Climber cadence is the fastest in the app; this is the tuning knob.
            minRepDuration: 0.3,
            minRangeOfMotion: 35,
            minConfidence: minConfidence,
            repJoints: [
                JointTriple(.leftShoulder, .leftHip, .leftKnee),
                JointTriple(.rightShoulder, .rightHip, .rightKnee),
            ],
            combination: .minimum,
            minAsymmetry: 30)
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: all tests PASS (existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add ChallengeCore
git commit -m "feat(core): mountain climber analyzer — each knee drive counts one rep"
```

---

### Task 2: `WallSitAnalyzer` (gated hold clock) + shared `sideMidpoint` helper

**Files:**
- Modify: `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` (extract `PlankAnalyzer.midpoint` to a file-scope helper; insert `WallSitAnalyzer` after `MountainClimberAnalyzer`)
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift`

**Interfaces:**
- Consumes: `MovingAverage`, `Geometry.angle`, `PoseFrame.point(_:minConfidence:)` (existing).
- Produces: `public struct WallSitAnalyzer: ExerciseAnalyzer` with `init(kneeEnter: ClosedRange<Double> = 70...110, kneeBreak: ClosedRange<Double> = 55...125, torsoEnterTilt: Double = 20, torsoBreakTilt: Double = 35, smoothingWindow: Int = 5, minConfidence: Double = 0.5)`; definition id `"wallsit"`, goal unit `.seconds`. Also internal file-scope `func sideMidpoint(_ frame: PoseFrame, _ a: Joint, _ b: Joint, minConfidence: Double) -> Point2D?` used by both `PlankAnalyzer` and `WallSitAnalyzer`. Task 4 registers the analyzer.

- [ ] **Step 1: Write the failing tests**

Add to `ExerciseAnalyzerTests`:

```swift
/// Side-view wall sit: knee vertex at the origin with the given interior angle,
/// shoulder placed so the torso tilts `torsoTilt` degrees off vertical.
private func wallSitFrame(knee: Double, torsoTilt: Double, t: TimeInterval,
                          kneeConfidence: Double = 0.9) -> PoseFrame {
    let kRad = knee * .pi / 180, tRad = torsoTilt * .pi / 180
    let hip = Point2D(x: cos(kRad), y: sin(kRad))
    let kneeP = Point2D(x: 0, y: 0)
    let ankle = Point2D(x: 1, y: 0)
    let shoulder = Point2D(x: hip.x + sin(tRad), y: hip.y + cos(tRad))
    func jp(_ p: Point2D, _ c: Double = 0.9) -> JointPoint { JointPoint(location: p, confidence: c) }
    return PoseFrame(timestamp: t, joints: [
        .leftShoulder: jp(shoulder), .rightShoulder: jp(shoulder),
        .leftHip: jp(hip), .rightHip: jp(hip),
        .leftKnee: jp(kneeP, kneeConfidence), .rightKnee: jp(kneeP, kneeConfidence),
        .leftAnkle: jp(ankle), .rightAnkle: jp(ankle),
    ])
}

@Test("WallSitAnalyzer accumulates seconds at ~90° knees with a vertical torso")
func wallSitAccumulates() {
    var a = WallSitAnalyzer()
    var t = 0.0
    var last: AnalyzerResult?
    for _ in 0..<10 { last = a.process(wallSitFrame(knee: 90, torsoTilt: 5, t: t)); t += 0.1 }
    #expect(a.progress > 0)
    #expect(last?.poseVisible == true)
}

@Test("WallSitAnalyzer pauses when standing up, keeping accumulated time")
func wallSitPausesOnStanding() {
    var a = WallSitAnalyzer()
    var t = 0.0
    for _ in 0..<10 { _ = a.process(wallSitFrame(knee: 90, torsoTilt: 5, t: t)); t += 0.1 }
    let held = a.progress
    #expect(held > 0)
    for _ in 0..<8 { _ = a.process(wallSitFrame(knee: 175, torsoTilt: 5, t: t)); t += 0.1 } // stand (transition)
    let afterStanding = a.progress
    for _ in 0..<5 { _ = a.process(wallSitFrame(knee: 175, torsoTilt: 5, t: t)); t += 0.1 }
    #expect(abs(a.progress - afterStanding) < 1e-6) // fully stopped
    #expect(a.progress >= held)                      // pause never erases time
}

@Test("WallSitAnalyzer pauses when the torso leans far off vertical")
func wallSitPausesOnLean() {
    var a = WallSitAnalyzer()
    var t = 0.0
    for _ in 0..<10 { _ = a.process(wallSitFrame(knee: 90, torsoTilt: 5, t: t)); t += 0.1 }
    #expect(a.progress > 0)
    for _ in 0..<8 { _ = a.process(wallSitFrame(knee: 90, torsoTilt: 60, t: t)); t += 0.1 } // lean (transition)
    let afterLean = a.progress
    for _ in 0..<5 { _ = a.process(wallSitFrame(knee: 90, torsoTilt: 60, t: t)); t += 0.1 }
    #expect(abs(a.progress - afterLean) < 1e-6)
}

@Test("WallSitAnalyzer never counts a hold that was never established")
func wallSitNeverEstablished() {
    var a = WallSitAnalyzer()
    var t = 0.0
    // Torso is upright but the knees are never detected: the knee gate's
    // default-false verdict must keep the clock at zero.
    for _ in 0..<10 { _ = a.process(wallSitFrame(knee: 90, torsoTilt: 5, t: t, kneeConfidence: 0.1)); t += 0.1 }
    #expect(a.progress == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: compile error — `cannot find 'WallSitAnalyzer' in scope`.

- [ ] **Step 3: Extract the shared midpoint helper**

In `ExerciseAnalyzer.swift`, add at file scope (just above `PlankAnalyzer`):

```swift
/// Average of two same-side joints when both clear the gate; otherwise the
/// single available side; `nil` when neither is detected. Shared by the
/// hold-style analyzers (plank, wall sit), which read the body as side-view
/// midlines rather than per-side triples.
func sideMidpoint(_ frame: PoseFrame, _ a: Joint, _ b: Joint, minConfidence: Double) -> Point2D? {
    let pa = frame.point(a, minConfidence: minConfidence)
    let pb = frame.point(b, minConfidence: minConfidence)
    switch (pa, pb) {
    case let (p1?, p2?): return Point2D(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    case let (p1?, nil): return p1
    case let (nil, p2?): return p2
    case (nil, nil): return nil
    }
}
```

Then in `PlankAnalyzer`: delete its `private func midpoint(_:_:_:)` and replace every call site (three in `armTilt`, three in `bodyTilt`) — each `midpoint(frame, X, Y)` becomes `sideMidpoint(frame, X, Y, minConfidence: minConfidence)`.

- [ ] **Step 4: Implement `WallSitAnalyzer`**

Insert after `MountainClimberAnalyzer`:

```swift
/// Wall sit: a time-based hold, side-view. Counts seconds while the knees are
/// bent near 90° AND the torso is near vertical, pausing otherwise — the same
/// smoothed + hysteresis gate recipe as the plank, with the plank's per-frame
/// dt cap. The camera cannot see the wall, so a free-standing chair pose also
/// counts (same isometric work). No form cues.
public struct WallSitAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "wallsit", displayName: "Wall Sit", goalUnit: .seconds, met: 4.0)
    /// Knee angle band that *establishes* the hold, and the wider band that
    /// *keeps* it (the extra width is the hysteresis margin). Standing
    /// straightens past the top of the break band; sliding to the floor bends
    /// below the bottom.
    private let kneeEnter: ClosedRange<Double>
    private let kneeBreak: ClosedRange<Double>
    /// Torso tilt from vertical (degrees) allowed to enter / break the hold.
    private let torsoEnterTilt: Double
    private let torsoBreakTilt: Double
    private let minConfidence: Double
    private let smoothingWindow: Int
    /// Cap per-frame time added, so a dropped-frame gap can't add a huge jump.
    private let maxStep: TimeInterval = 0.5
    private var kneeSmoother: MovingAverage
    private var torsoSmoother: MovingAverage
    /// Defaults false: a hold that was never established never counts.
    private var kneeHeld = false
    /// Defaults true: partial visibility doesn't rob credit once established.
    private var torsoUpright = true
    private var heldSeconds: Double = 0
    private var lastTimestamp: TimeInterval?

    public var progress: Double { heldSeconds }

    public init(kneeEnter: ClosedRange<Double> = 70...110,
                kneeBreak: ClosedRange<Double> = 55...125,
                torsoEnterTilt: Double = 20, torsoBreakTilt: Double = 35,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        self.kneeEnter = kneeEnter
        self.kneeBreak = kneeBreak
        self.torsoEnterTilt = torsoEnterTilt
        self.torsoBreakTilt = torsoBreakTilt
        self.smoothingWindow = smoothingWindow
        self.minConfidence = minConfidence
        self.kneeSmoother = MovingAverage(windowSize: smoothingWindow)
        self.torsoSmoother = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(frame.timestamp - last, 0), maxStep)
        } else {
            dt = 0
        }
        lastTimestamp = frame.timestamp

        // Both gates hold their last verdict on unjudgeable frames.
        let kneeRaw = kneeAngle(frame)
        if let kneeRaw {
            let k = kneeSmoother.add(kneeRaw)
            kneeHeld = kneeHeld ? kneeBreak.contains(k) : kneeEnter.contains(k)
        }
        let torsoRaw = torsoTilt(frame)
        if let torsoRaw {
            let v = torsoSmoother.add(torsoRaw)
            torsoUpright = torsoUpright ? v <= torsoBreakTilt : v <= torsoEnterTilt
        }

        if kneeHeld && torsoUpright { heldSeconds += dt }
        return AnalyzerResult(progress: heldSeconds, didAdvance: false,
                              poseVisible: kneeRaw != nil || torsoRaw != nil, formCue: nil)
    }

    /// Knee angle (hip·knee·ankle) read off the side-view midlines.
    private func kneeAngle(_ frame: PoseFrame) -> Double? {
        guard let hip = sideMidpoint(frame, .leftHip, .rightHip, minConfidence: minConfidence),
              let knee = sideMidpoint(frame, .leftKnee, .rightKnee, minConfidence: minConfidence),
              let ankle = sideMidpoint(frame, .leftAnkle, .rightAnkle, minConfidence: minConfidence) else { return nil }
        return Geometry.angle(hip, knee, ankle)
    }

    /// Torso tilt from *vertical* in degrees (0 = upright against the wall,
    /// 90 = horizontal). `nil` when shoulder or hip is undetected.
    private func torsoTilt(_ frame: PoseFrame) -> Double? {
        guard let shoulder = sideMidpoint(frame, .leftShoulder, .rightShoulder, minConfidence: minConfidence),
              let hip = sideMidpoint(frame, .leftHip, .rightHip, minConfidence: minConfidence) else { return nil }
        return atan2(abs(shoulder.x - hip.x), abs(shoulder.y - hip.y)) * 180 / .pi
    }

    public mutating func reset() {
        kneeSmoother = MovingAverage(windowSize: smoothingWindow)
        torsoSmoother = MovingAverage(windowSize: smoothingWindow)
        kneeHeld = false
        torsoUpright = true
        heldSeconds = 0
        lastTimestamp = nil
    }
}
```

- [ ] **Step 5: Run the FULL core test suite (plank refactor must not regress)**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build"`
Expected: all tests PASS, including every existing `PlankAnalyzer` test.

- [ ] **Step 6: Commit**

```bash
git add ChallengeCore
git commit -m "feat(core): wall sit hold analyzer; share side-midpoint helper with plank"
```

---

### Task 3: `JumpingJackAnalyzer` (dual-signal state machine)

**Files:**
- Modify: `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` (insert after `WallSitAnalyzer`, before `ExerciseRegistry`)
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift`

**Interfaces:**
- Consumes: `MovingAverage`, `Geometry.angle`, `PoseFrame.point(_:minConfidence:)` (existing).
- Produces: `public struct JumpingJackAnalyzer: ExerciseAnalyzer` with `init(armOpen: Double = 140, armClosed: Double = 60, legOpen: Double = 35, legClosed: Double = 20, minCycleDuration: TimeInterval = 0.35, smoothingWindow: Int = 5, minConfidence: Double = 0.5)`; definition id `"jumpingjack"`. Task 4 registers it.

- [ ] **Step 1: Write the failing tests**

Add to `ExerciseAnalyzerTests`:

```swift
/// Front-facing jack frame. The arm signal (hip·shoulder·wrist, vertex at the
/// shoulder) and leg signal (leftAnkle·root·rightAnkle, vertex at root) are
/// built from disjoint joint clusters so each angle can be set independently.
private func jackFrame(arm: Double, leg: Double, t: TimeInterval,
                       confidence: Double = 0.9) -> PoseFrame {
    let armRad = arm * .pi / 180, legRad = leg * .pi / 180
    let shoulder = Point2D(x: 0, y: 0)
    let hip = Point2D(x: cos(armRad), y: sin(armRad))
    let wrist = Point2D(x: 1, y: 0)
    let root = Point2D(x: 5, y: 5)
    let leftAnkle = Point2D(x: 5 + cos(legRad), y: 5 + sin(legRad))
    let rightAnkle = Point2D(x: 6, y: 5)
    func jp(_ p: Point2D) -> JointPoint { JointPoint(location: p, confidence: confidence) }
    return PoseFrame(timestamp: t, joints: [
        .leftShoulder: jp(shoulder), .rightShoulder: jp(shoulder),
        .leftHip: jp(hip), .rightHip: jp(hip),
        .leftWrist: jp(wrist), .rightWrist: jp(wrist),
        .root: jp(root),
        .leftAnkle: jp(leftAnkle), .rightAnkle: jp(rightAnkle),
    ])
}

/// One full jack cycle (closed → open → closed) at the given frame spacing.
private func jackCycle(start: TimeInterval, dt: TimeInterval) -> [PoseFrame] {
    var frames: [PoseFrame] = []
    var t = start
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));   t += dt }
    for _ in 0..<8 { frames.append(jackFrame(arm: 175, leg: 50, t: t)); t += dt }
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));   t += dt }
    return frames
}

@Test("JumpingJackAnalyzer counts a full synchronized cycle")
func jackCounts() {
    var a = JumpingJackAnalyzer()
    var last: AnalyzerResult?
    for f in jackCycle(start: 0, dt: 0.1) { last = a.process(f) }
    #expect(a.progress == 1)
    #expect(last?.poseVisible == true)
}

@Test("JumpingJackAnalyzer ignores arm-only half-jacks (legs never spread)")
func jackIgnoresArmsOnly() {
    var a = JumpingJackAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));  t += 0.1 }
    for _ in 0..<8 { frames.append(jackFrame(arm: 175, leg: 8, t: t)); t += 0.1 } // arms up, legs together
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));  t += 0.1 }
    for f in frames { _ = a.process(f) }
    #expect(a.progress == 0)
}

@Test("JumpingJackAnalyzer ignores leg-only cycles (arms never raise)")
func jackIgnoresLegsOnly() {
    var a = JumpingJackAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));  t += 0.1 }
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 50, t: t)); t += 0.1 } // legs out, arms down
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));  t += 0.1 }
    for f in frames { _ = a.process(f) }
    #expect(a.progress == 0)
}

@Test("JumpingJackAnalyzer holds state through a mid-cycle dropout")
func jackSurvivesDropout() {
    var a = JumpingJackAnalyzer()
    var frames: [PoseFrame] = []
    var t = 0.0
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));   t += 0.1 }
    for _ in 0..<4 { frames.append(jackFrame(arm: 175, leg: 50, t: t)); t += 0.1 }
    for _ in 0..<3 { frames.append(jackFrame(arm: 175, leg: 50, t: t, confidence: 0.1)); t += 0.1 } // pose lost
    for _ in 0..<4 { frames.append(jackFrame(arm: 175, leg: 50, t: t)); t += 0.1 }
    for _ in 0..<8 { frames.append(jackFrame(arm: 15, leg: 8, t: t));   t += 0.1 }
    var sawInvisible = false
    for f in frames {
        let r = a.process(f)
        if !r.poseVisible { sawInvisible = true }
    }
    #expect(a.progress == 1)     // dropout did not reset the cycle
    #expect(sawInvisible)        // and the lost frames reported pose-not-visible
}

@Test("JumpingJackAnalyzer rejects a bounce faster than the minimum cycle")
func jackRejectsBounce() {
    var a = JumpingJackAnalyzer()
    // Same shape as a real cycle but compressed to ~0.16s, under the 0.35s floor.
    for f in jackCycle(start: 0, dt: 0.02) { _ = a.process(f) }
    #expect(a.progress == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: compile error — `cannot find 'JumpingJackAnalyzer' in scope`.

- [ ] **Step 3: Implement the analyzer**

Insert after `WallSitAnalyzer`:

```swift
/// Jumping jacks: the app's first front-facing exercise. Two smoothed signals —
/// arm raise (hip·shoulder·wrist, ~20° at the sides to ~170° overhead) and leg
/// spread (leftAnkle·root·rightAnkle, ~15° together to ~45° apart) — drive a
/// two-state machine. Both signals must clear a gate on the same smoothed frame
/// to change state, so arm-only half-jacks and out-of-sync legs never count;
/// the band between the open and closed thresholds is the hysteresis margin.
/// A closed → open → closed cycle is one rep, subject to a minimum cycle
/// duration measured from leaving `closed` to re-entering it. No form cues.
public struct JumpingJackAnalyzer: ExerciseAnalyzer {
    public let definition = ExerciseDefinition(id: "jumpingjack", displayName: "Jumping Jack", goalUnit: .reps, met: 8.0)

    private let armOpen: Double
    private let armClosed: Double
    private let legOpen: Double
    private let legClosed: Double
    private let minCycleDuration: TimeInterval
    private let smoothingWindow: Int
    private let minConfidence: Double

    private var armSmoother: MovingAverage
    private var legSmoother: MovingAverage
    /// Last smoothed values; held across unjudgeable frames so a brief joint
    /// dropout can't reset the cycle.
    private var lastArm: Double?
    private var lastLeg: Double?

    private enum State { case unknown, closed, open }
    private var state: State = .unknown
    /// Timestamp of the frame that left `closed` (entered `open`); nil outside
    /// a cycle, so a cycle that began mid-open never counts.
    private var cycleStart: TimeInterval?
    private var count = 0

    public var progress: Double { Double(count) }

    public init(armOpen: Double = 140, armClosed: Double = 60,
                legOpen: Double = 35, legClosed: Double = 20,
                minCycleDuration: TimeInterval = 0.35,
                smoothingWindow: Int = 5, minConfidence: Double = 0.5) {
        self.armOpen = armOpen
        self.armClosed = armClosed
        self.legOpen = legOpen
        self.legClosed = legClosed
        self.minCycleDuration = minCycleDuration
        self.smoothingWindow = smoothingWindow
        self.minConfidence = minConfidence
        self.armSmoother = MovingAverage(windowSize: smoothingWindow)
        self.legSmoother = MovingAverage(windowSize: smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerResult {
        let armRaw = armAngle(frame)
        let legRaw = legAngle(frame)
        if let armRaw { lastArm = armSmoother.add(armRaw) }
        if let legRaw { lastLeg = legSmoother.add(legRaw) }
        let visible = armRaw != nil || legRaw != nil

        // Until both signals have been seen once there is nothing to judge.
        guard let arm = lastArm, let leg = lastLeg else {
            return AnalyzerResult(progress: Double(count), didAdvance: false, poseVisible: visible, formCue: nil)
        }

        var didAdvance = false
        switch state {
        case .unknown:
            if arm <= armClosed && leg <= legClosed {
                state = .closed
            } else if arm >= armOpen && leg >= legOpen {
                state = .open   // started mid-jack; the first close won't count
            }
        case .closed:
            if arm >= armOpen && leg >= legOpen {
                state = .open
                cycleStart = frame.timestamp
            }
        case .open:
            if arm <= armClosed && leg <= legClosed {
                state = .closed
                if let start = cycleStart, frame.timestamp - start >= minCycleDuration {
                    count += 1
                    didAdvance = true
                }
                cycleStart = nil
            }
        }
        return AnalyzerResult(progress: Double(count), didAdvance: didAdvance, poseVisible: visible, formCue: nil)
    }

    /// Arm-raise angle (hip·shoulder·wrist, vertex at the shoulder), averaged
    /// over whichever sides are fully detected. `nil` when neither side is.
    private func armAngle(_ frame: PoseFrame) -> Double? {
        let sides: [(Joint, Joint, Joint)] = [
            (.leftHip, .leftShoulder, .leftWrist),
            (.rightHip, .rightShoulder, .rightWrist),
        ]
        let angles = sides.compactMap { side -> Double? in
            guard let a = frame.point(side.0, minConfidence: minConfidence),
                  let b = frame.point(side.1, minConfidence: minConfidence),
                  let c = frame.point(side.2, minConfidence: minConfidence) else { return nil }
            return Geometry.angle(a, b, c)
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }

    /// Leg-spread angle at the root between the two ankles. `nil` when any of
    /// the three joints is undetected — spread cannot be judged one-legged.
    private func legAngle(_ frame: PoseFrame) -> Double? {
        guard let root = frame.point(.root, minConfidence: minConfidence),
              let left = frame.point(.leftAnkle, minConfidence: minConfidence),
              let right = frame.point(.rightAnkle, minConfidence: minConfidence) else { return nil }
        return Geometry.angle(left, root, right)
    }

    public mutating func reset() {
        armSmoother = MovingAverage(windowSize: smoothingWindow)
        legSmoother = MovingAverage(windowSize: smoothingWindow)
        lastArm = nil
        lastLeg = nil
        state = .unknown
        cycleStart = nil
        count = 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: all tests PASS (5 new jack tests included).

- [ ] **Step 5: Commit**

```bash
git add ChallengeCore
git commit -m "feat(core): jumping jack analyzer — dual-signal arm/leg state machine"
```

---

### Task 4: Register the three exercises

**Files:**
- Modify: `ChallengeCore/Sources/ChallengeCore/ExerciseAnalyzer.swift` (`ExerciseRegistry.all` and `makeAnalyzer(for:)`)
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseAnalyzerTests.swift` (existing `registry` test)

**Interfaces:**
- Consumes: the three analyzers from Tasks 1–3.
- Produces: registry knows ids `"jumpingjack"`, `"mountainclimber"`, `"wallsit"`. Everything downstream (builder UI, live workout, watch, `CalorieEstimator`) picks them up from here.

- [ ] **Step 1: Update the registry test to expect the new ids (failing first)**

In the existing `registry` test, replace the two assertions on unknown/all ids so the test reads:

```swift
@Test("registry returns fresh analyzers for known ids and nil otherwise")
func registry() {
    #expect(ExerciseRegistry.makeAnalyzer(for: "pushup")?.definition.goalUnit == .reps)
    #expect(ExerciseRegistry.makeAnalyzer(for: "plank")?.definition.goalUnit == .seconds)
    #expect(ExerciseRegistry.makeAnalyzer(for: "situp")?.definition.goalUnit == .reps)
    #expect(ExerciseRegistry.makeAnalyzer(for: "glutebridge")?.definition.goalUnit == .reps)
    #expect(ExerciseRegistry.makeAnalyzer(for: "jumpingjack")?.definition.goalUnit == .reps)
    #expect(ExerciseRegistry.makeAnalyzer(for: "mountainclimber")?.definition.goalUnit == .reps)
    #expect(ExerciseRegistry.makeAnalyzer(for: "wallsit")?.definition.goalUnit == .seconds)
    #expect(ExerciseRegistry.makeAnalyzer(for: "moonwalk") == nil)
    #expect(Set(ExerciseRegistry.all.map(\.id))
            == ["pushup", "squat", "lunge", "plank", "situp", "glutebridge",
                "jumpingjack", "mountainclimber", "wallsit"])
}
```

- [ ] **Step 2: Run to verify the updated test fails**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build" --filter ExerciseAnalyzerTests`
Expected: `registry` FAILS (nil analyzers / set mismatch); everything else passes.

- [ ] **Step 3: Register the exercises**

In `ExerciseRegistry.all`, append after `GluteBridgeAnalyzer().definition`:

```swift
        JumpingJackAnalyzer().definition,
        MountainClimberAnalyzer().definition,
        WallSitAnalyzer().definition,
```

In `makeAnalyzer(for:)`, add before `default`:

```swift
        case "jumpingjack": return JumpingJackAnalyzer()
        case "mountainclimber": return MountainClimberAnalyzer()
        case "wallsit": return WallSitAnalyzer()
```

- [ ] **Step 4: Run the FULL core suite**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build"`
Expected: all tests PASS (the MET sweep test now covers the new definitions too).

- [ ] **Step 5: Commit**

```bash
git add ChallengeCore
git commit -m "feat(core): register jumping jack, mountain climber, wall sit"
```

---

### Task 5: Picker tiles for the three exercises

**Files:**
- Modify: `CrazyWork/Sources/Theme/Components/ExerciseTile.swift` (three cases in `ExercisePoseIcon.pose(for:)`, before `default`)

**Interfaces:**
- Consumes: `ExercisePoseIcon.Pose` (existing struct: `head`, `chains`, `joints`, `groundY`).
- Produces: pose figures for ids `"jumpingjack"`, `"mountainclimber"`, `"wallsit"`. No API changes.

- [ ] **Step 1: Add the three pose cases**

Insert before the `default:` case in `pose(for:)`:

```swift
        case "jumpingjack": // front view mid-flight: arms overhead, legs apart
            return Pose(
                head: CGPoint(x: 0.50, y: 0.13),
                chains: [
                    [CGPoint(x: 0.50, y: 0.26), CGPoint(x: 0.50, y: 0.52)],
                    [CGPoint(x: 0.34, y: 0.10), CGPoint(x: 0.50, y: 0.28)],
                    [CGPoint(x: 0.66, y: 0.10), CGPoint(x: 0.50, y: 0.28)],
                    [CGPoint(x: 0.50, y: 0.52), CGPoint(x: 0.34, y: 0.83)],
                    [CGPoint(x: 0.50, y: 0.52), CGPoint(x: 0.66, y: 0.83)],
                ],
                joints: [CGPoint(x: 0.50, y: 0.28), CGPoint(x: 0.50, y: 0.52)],
                groundY: 0.84)
        case "mountainclimber": // plank base, one knee driven to the chest
            return Pose(
                head: CGPoint(x: 0.88, y: 0.40),
                chains: [
                    [CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.46, y: 0.54),
                     CGPoint(x: 0.24, y: 0.66), CGPoint(x: 0.10, y: 0.80)],
                    [CGPoint(x: 0.46, y: 0.54), CGPoint(x: 0.58, y: 0.66), CGPoint(x: 0.52, y: 0.80)],
                    [CGPoint(x: 0.74, y: 0.46), CGPoint(x: 0.73, y: 0.64), CGPoint(x: 0.72, y: 0.80)],
                ],
                joints: [CGPoint(x: 0.46, y: 0.54), CGPoint(x: 0.58, y: 0.66)],
                groundY: 0.81)
        case "wallsit": // back on the wall line, thighs level, shins vertical
            return Pose(
                head: CGPoint(x: 0.42, y: 0.22),
                chains: [
                    [CGPoint(x: 0.30, y: 0.14), CGPoint(x: 0.30, y: 0.83)],   // the wall
                    [CGPoint(x: 0.38, y: 0.32), CGPoint(x: 0.36, y: 0.56),
                     CGPoint(x: 0.60, y: 0.58), CGPoint(x: 0.60, y: 0.83), CGPoint(x: 0.70, y: 0.83)],
                    [CGPoint(x: 0.38, y: 0.36), CGPoint(x: 0.48, y: 0.52)],
                ],
                joints: [CGPoint(x: 0.36, y: 0.56), CGPoint(x: 0.60, y: 0.58)],
                groundY: 0.84)
```

- [ ] **Step 2: Verify the app still builds**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork && xcodebuild -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'generic/platform=iOS Simulator' build SYMROOT="$TMPDIR/crazywork-symroot" | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Theme/Components/ExerciseTile.swift
git commit -m "feat(ui): picker pose figures for jumping jack, mountain climber, wall sit"
```

---

## Verification (after all tasks)

1. `cd ChallengeCore && swift test --scratch-path "$TMPDIR/challengecore-build"` → all pass.
2. `xcodebuild -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'generic/platform=iOS Simulator' build SYMROOT="$TMPDIR/crazywork-symroot"` → succeeds.
3. Spec coverage: every requirement in `2026-07-06-new-exercises-design.md` sections 1–5 maps to Tasks 3, 1, 2, 4, 5 respectively.
