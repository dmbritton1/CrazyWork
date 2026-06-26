# WorkoutVision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS workout app that uses the camera + Vision pose detection to count reps and score form for pushups and squats, on top of a generalized, protocol-based `ChallengeCore` engine ported from the WakeupCall repo.

**Architecture:** A pure Swift package (`ChallengeCore`) turns a stream of `PoseFrame`s into `RepEvent`s through per-exercise `ExerciseAnalyzer` conformers that share angle/hysteresis/confidence machinery. A separate iOS app target (`WorkoutVision`) captures camera frames (AVFoundation), maps Vision pose observations into `PoseFrame`s, drives a `SessionCoordinator` that swaps analyzers per exercise, and persists per-set aggregates with SwiftData. The engine never imports UI, AVFoundation, Vision, or SwiftData.

**Tech Stack:** Swift 6, Swift Package Manager (engine), SwiftUI, Vision, AVFoundation, SwiftData, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-06-26-workout-vision-design.md`

---

## Reference: WakeupCall source

This plan ports logic from `https://github.com/dmbritton1/WakeupCall`. Before starting Phase 1, clone it next to this project for reference:

```bash
git clone https://github.com/dmbritton1/WakeupCall ../WakeupCall-ref
```

Use it to crib the existing pushup geometry, the `ChallengeCore` package layout, and the fixture-replay test harness. This plan rebuilds the engine from scratch (it is small) rather than copying files verbatim, so the new abstraction is clean. Where the original pushup constants differ from the placeholders here, prefer the original's tuned values.

---

## File Structure

### Phase 1 — `ChallengeCore` Swift package

```
ChallengeCore/
  Package.swift
  Sources/ChallengeCore/
    Geometry/Point2D.swift              # dependency-free 2D point
    Geometry/AngleMath.swift            # three-joint angle in degrees
    Pose/JointName.swift                # pure enum of tracked joints
    Pose/Joint.swift                    # position + confidence
    Pose/PoseFrame.swift                # timestamped joint dictionary
    Model/ExerciseInfo.swift            # static exercise metadata
    Model/Finding.swift                 # form-issue enum
    Model/RepEvent.swift                # one completed rep
    Model/TrackingStatus.swift          # tracking / lowConfidence / outOfFrame
    Detection/HysteresisRepDetector.swift   # down->up cycle detector
    Detection/ConfidenceGate.swift          # frame -> TrackingStatus
    Analyzer/ExerciseAnalyzer.swift     # the protocol
    Analyzer/PushupAnalyzer.swift
    Analyzer/SquatAnalyzer.swift
    Analyzer/ExerciseRegistry.swift     # id -> analyzer factory
  Tests/ChallengeCoreTests/
    Support/PoseFrameBuilder.swift      # test helper to synthesize frames
    AngleMathTests.swift
    HysteresisRepDetectorTests.swift
    ConfidenceGateTests.swift
    PushupAnalyzerTests.swift
    SquatAnalyzerTests.swift
    ExerciseRegistryTests.swift
```

### Phase 2 — `WorkoutVision` app target

```
WorkoutVision/
  project.yml                          # XcodeGen source of truth
  Sources/
    App/WorkoutVisionApp.swift
    Capture/CameraSession.swift        # AVFoundation capture
    Capture/VisionPoseMapper.swift     # VNHumanBodyPoseObservation -> PoseFrame
    Capture/PosePipeline.swift         # camera -> mapper -> analyzer glue
    Session/PlannedSet.swift           # one planned exercise set
    Session/SessionCoordinator.swift   # workout state machine
    Persistence/WorkoutSession.swift   # @Model
    Persistence/ExerciseSet.swift      # @Model
    Views/BuildWorkoutView.swift
    Views/LiveWorkoutView.swift
    Views/SkeletonOverlay.swift
    Views/SummaryView.swift
    Views/HistoryView.swift
  Tests/
    SessionCoordinatorTests.swift
    PersistenceTests.swift
    VisionPoseMapperTests.swift
```

---

# PHASE 1 — The `ChallengeCore` engine

Pure Swift, no Apple-framework dependencies. Everything here runs with `swift test` on macOS. This phase delivers a fully tested engine as standalone software.

## Task 1: Bootstrap the package

**Files:**
- Create: `ChallengeCore/Package.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Geometry/Point2D.swift`

- [ ] **Step 1: Create the package manifest**

`ChallengeCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChallengeCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "ChallengeCore", targets: ["ChallengeCore"]),
    ],
    targets: [
        .target(name: "ChallengeCore"),
        .testTarget(name: "ChallengeCoreTests", dependencies: ["ChallengeCore"]),
    ]
)
```

- [ ] **Step 2: Add the dependency-free point type**

`ChallengeCore/Sources/ChallengeCore/Geometry/Point2D.swift`:
```swift
public struct Point2D: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
```

- [ ] **Step 3: Verify the package builds**

Run: `cd ChallengeCore && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd ChallengeCore
git add Package.swift Sources
git commit -m "chore: bootstrap ChallengeCore package"
```

## Task 2: AngleMath

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Geometry/AngleMath.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/AngleMathTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/AngleMathTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class AngleMathTests: XCTestCase {
    func testRightAngle() {
        let vertex = Point2D(x: 0, y: 0)
        let a = Point2D(x: 1, y: 0)
        let b = Point2D(x: 0, y: 1)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: a, to: b), 90, accuracy: 0.001)
    }

    func testStraightLine() {
        let vertex = Point2D(x: 0, y: 0)
        let a = Point2D(x: -1, y: 0)
        let b = Point2D(x: 1, y: 0)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: a, to: b), 180, accuracy: 0.001)
    }

    func testZeroDegenerateReturnsZero() {
        let vertex = Point2D(x: 0, y: 0)
        XCTAssertEqual(AngleMath.angle(at: vertex, from: vertex, to: Point2D(x: 1, y: 0)), 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter AngleMathTests`
Expected: FAIL — `AngleMath` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Geometry/AngleMath.swift`:
```swift
import Foundation

public enum AngleMath {
    /// Angle in degrees (0...180) at `vertex` between the rays to `a` and `b`.
    /// Returns 0 if either ray has zero length.
    public static func angle(at vertex: Point2D, from a: Point2D, to b: Point2D) -> Double {
        let v1 = Point2D(x: a.x - vertex.x, y: a.y - vertex.y)
        let v2 = Point2D(x: b.x - vertex.x, y: b.y - vertex.y)
        let mag1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
        let mag2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
        guard mag1 > 0, mag2 > 0 else { return 0 }
        let dot = v1.x * v2.x + v1.y * v2.y
        let cosine = min(1, max(-1, dot / (mag1 * mag2)))
        return acos(cosine) * 180 / .pi
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChallengeCore && swift test --filter AngleMathTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Geometry/AngleMath.swift Tests/ChallengeCoreTests/AngleMathTests.swift
git commit -m "feat: add AngleMath three-joint angle"
```

## Task 3: Pose types

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Pose/JointName.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Pose/Joint.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Pose/PoseFrame.swift`
- Create: `ChallengeCore/Tests/ChallengeCoreTests/Support/PoseFrameBuilder.swift`

- [ ] **Step 1: Add JointName**

`Sources/ChallengeCore/Pose/JointName.swift`:
```swift
public enum JointName: String, CaseIterable, Sendable {
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}
```

- [ ] **Step 2: Add Joint**

`Sources/ChallengeCore/Pose/Joint.swift`:
```swift
public struct Joint: Equatable, Sendable {
    public var position: Point2D
    public var confidence: Double
    public init(position: Point2D, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}
```

- [ ] **Step 3: Add PoseFrame**

`Sources/ChallengeCore/Pose/PoseFrame.swift`:
```swift
import Foundation

public struct PoseFrame: Sendable {
    public var timestamp: TimeInterval
    public var joints: [JointName: Joint]

    public init(timestamp: TimeInterval, joints: [JointName: Joint]) {
        self.timestamp = timestamp
        self.joints = joints
    }

    public func joint(_ name: JointName) -> Joint? { joints[name] }
    public func point(_ name: JointName) -> Point2D? { joints[name]?.position }
    public func confidence(_ name: JointName) -> Double { joints[name]?.confidence ?? 0 }
}
```

- [ ] **Step 4: Add the test helper**

`Tests/ChallengeCoreTests/Support/PoseFrameBuilder.swift`:
```swift
import Foundation
@testable import ChallengeCore

/// Builds PoseFrames for tests. Defaults every joint to confidence 1.
struct PoseFrameBuilder {
    var timestamp: TimeInterval = 0
    var joints: [JointName: Joint] = [:]

    mutating func set(_ name: JointName, _ x: Double, _ y: Double, confidence: Double = 1) {
        joints[name] = Joint(position: Point2D(x: x, y: y), confidence: confidence)
    }

    func build() -> PoseFrame { PoseFrame(timestamp: timestamp, joints: joints) }
}
```

- [ ] **Step 5: Verify build**

Run: `cd ChallengeCore && swift build && swift test --filter AngleMathTests`
Expected: builds; existing tests still PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ChallengeCore/Pose Tests/ChallengeCoreTests/Support
git commit -m "feat: add pose types and test builder"
```

## Task 4: Model types (ExerciseInfo, Finding, RepEvent, TrackingStatus)

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Model/ExerciseInfo.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Model/Finding.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Model/RepEvent.swift`
- Create: `ChallengeCore/Sources/ChallengeCore/Model/TrackingStatus.swift`

- [ ] **Step 1: Add the four value types**

`Sources/ChallengeCore/Model/ExerciseInfo.swift`:
```swift
public struct ExerciseInfo: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let trackedJoints: [JointName]
    public init(id: String, displayName: String, trackedJoints: [JointName]) {
        self.id = id
        self.displayName = displayName
        self.trackedJoints = trackedJoints
    }
}
```

`Sources/ChallengeCore/Model/Finding.swift`:
```swift
public enum Finding: String, Equatable, Sendable {
    case shallowDepth
    case backNotStraight
    case torsoLean
    case kneesCaving
}
```

`Sources/ChallengeCore/Model/RepEvent.swift`:
```swift
public struct RepEvent: Equatable, Sendable {
    public let repIndex: Int
    public let formScore: Double      // 0...1
    public let findings: [Finding]
    public init(repIndex: Int, formScore: Double, findings: [Finding]) {
        self.repIndex = repIndex
        self.formScore = formScore
        self.findings = findings
    }
}
```

`Sources/ChallengeCore/Model/TrackingStatus.swift`:
```swift
public enum TrackingStatus: Equatable, Sendable {
    case tracking
    case lowConfidence
    case outOfFrame
}
```

- [ ] **Step 2: Verify build**

Run: `cd ChallengeCore && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ChallengeCore/Model
git commit -m "feat: add engine model value types"
```

## Task 5: HysteresisRepDetector

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Detection/HysteresisRepDetector.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/HysteresisRepDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/HysteresisRepDetectorTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class HysteresisRepDetectorTests: XCTestCase {
    private func makeDetector() -> HysteresisRepDetector {
        HysteresisRepDetector(downThreshold: 90, upThreshold: 160, minRepDuration: 0.3)
    }

    func testFullCycleCountsOneRep() {
        var d = makeDetector()
        XCTAssertFalse(d.update(angle: 170, timestamp: 0.0)) // up
        XCTAssertFalse(d.update(angle: 80, timestamp: 0.5))  // down
        XCTAssertTrue(d.update(angle: 165, timestamp: 1.0))  // back up -> rep
    }

    func testJitterNearThresholdDoesNotDoubleCount() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        _ = d.update(angle: 80, timestamp: 0.5)
        XCTAssertTrue(d.update(angle: 165, timestamp: 1.0))   // one rep
        XCTAssertFalse(d.update(angle: 158, timestamp: 1.1))  // wiggle, no new rep
        XCTAssertFalse(d.update(angle: 162, timestamp: 1.2))  // still no new rep
    }

    func testTooFastRepIsRejected() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        _ = d.update(angle: 80, timestamp: 0.5)
        XCTAssertFalse(d.update(angle: 165, timestamp: 0.6)) // only 0.1s down, below minRepDuration
    }

    func testPartialDipDoesNotCount() {
        var d = makeDetector()
        _ = d.update(angle: 170, timestamp: 0.0)
        XCTAssertFalse(d.update(angle: 120, timestamp: 0.5)) // never crossed downThreshold
        XCTAssertFalse(d.update(angle: 165, timestamp: 1.0))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter HysteresisRepDetectorTests`
Expected: FAIL — type not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Detection/HysteresisRepDetector.swift`:
```swift
import Foundation

/// Detects a completed down->up rep using two angle thresholds.
/// A rep counts when the angle drops below `downThreshold`, stays down at
/// least `minRepDuration`, then rises back above `upThreshold`.
public struct HysteresisRepDetector {
    public enum Phase: Sendable { case waitingForDown, waitingForUp }

    public let downThreshold: Double
    public let upThreshold: Double
    public let minRepDuration: TimeInterval

    public private(set) var phase: Phase = .waitingForDown
    private var downEnteredAt: TimeInterval?

    public init(downThreshold: Double, upThreshold: Double, minRepDuration: TimeInterval) {
        self.downThreshold = downThreshold
        self.upThreshold = upThreshold
        self.minRepDuration = minRepDuration
    }

    /// Returns true on the frame where a rep completes.
    public mutating func update(angle: Double, timestamp: TimeInterval) -> Bool {
        switch phase {
        case .waitingForDown:
            if angle <= downThreshold {
                phase = .waitingForUp
                downEnteredAt = timestamp
            }
            return false
        case .waitingForUp:
            if angle >= upThreshold {
                let longEnough = (timestamp - (downEnteredAt ?? timestamp)) >= minRepDuration
                phase = .waitingForDown
                downEnteredAt = nil
                return longEnough
            }
            return false
        }
    }

    public mutating func reset() {
        phase = .waitingForDown
        downEnteredAt = nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChallengeCore && swift test --filter HysteresisRepDetectorTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Detection/HysteresisRepDetector.swift Tests/ChallengeCoreTests/HysteresisRepDetectorTests.swift
git commit -m "feat: add hysteresis rep detector"
```

## Task 6: ConfidenceGate

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Detection/ConfidenceGate.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ConfidenceGateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/ConfidenceGateTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class ConfidenceGateTests: XCTestCase {
    private let required: [JointName] = [.leftShoulder, .leftElbow, .leftWrist]

    func testAllConfidentIsTracking() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1); b.set(.leftWrist, 0, 2)
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .tracking)
    }

    func testMissingJointIsOutOfFrame() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1) // no wrist
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .outOfFrame)
    }

    func testLowConfidenceJointIsLowConfidence() {
        var b = PoseFrameBuilder()
        b.set(.leftShoulder, 0, 0); b.set(.leftElbow, 0, 1)
        b.set(.leftWrist, 0, 2, confidence: 0.2)
        XCTAssertEqual(ConfidenceGate.status(for: b.build(), requiredJoints: required, minConfidence: 0.5), .lowConfidence)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter ConfidenceGateTests`
Expected: FAIL — type not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Detection/ConfidenceGate.swift`:
```swift
public enum ConfidenceGate {
    public static func status(for frame: PoseFrame,
                              requiredJoints: [JointName],
                              minConfidence: Double) -> TrackingStatus {
        for name in requiredJoints where frame.joint(name) == nil {
            return .outOfFrame
        }
        for name in requiredJoints where frame.confidence(name) < minConfidence {
            return .lowConfidence
        }
        return .tracking
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChallengeCore && swift test --filter ConfidenceGateTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Detection/ConfidenceGate.swift Tests/ChallengeCoreTests/ConfidenceGateTests.swift
git commit -m "feat: add confidence gate"
```

## Task 7: ExerciseAnalyzer protocol

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Analyzer/ExerciseAnalyzer.swift`

- [ ] **Step 1: Add the protocol**

`Sources/ChallengeCore/Analyzer/ExerciseAnalyzer.swift`:
```swift
public protocol ExerciseAnalyzer {
    var info: ExerciseInfo { get }
    var status: TrackingStatus { get }

    /// Feed one frame; returns any reps that completed on this frame (usually 0 or 1).
    mutating func process(_ frame: PoseFrame) -> [RepEvent]

    /// Clear all internal state (rep count, phase, per-rep accumulators).
    mutating func reset()
}
```

- [ ] **Step 2: Verify build**

Run: `cd ChallengeCore && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ChallengeCore/Analyzer/ExerciseAnalyzer.swift
git commit -m "feat: add ExerciseAnalyzer protocol"
```

## Task 8: PushupAnalyzer

Rep angle = elbow (shoulder·elbow·wrist), using the higher-confidence side. Form: depth (min elbow angle at bottom must reach `depthTarget`) and back straightness (shoulder·hip·ankle must stay near 180° during the rep). The analyzer accumulates the rep's minimum elbow angle and worst back angle, then grades on the up-stroke.

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Analyzer/PushupAnalyzer.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/PushupAnalyzerTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/PushupAnalyzerTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class PushupAnalyzerTests: XCTestCase {
    /// Builds a frame whose left-elbow angle equals `elbow` degrees and whose
    /// back (shoulder-hip-ankle) is straight unless `backAngle` is given.
    private func frame(elbow: Double, backAngle: Double = 180, t: TimeInterval) -> PoseFrame {
        var b = PoseFrameBuilder()
        b.timestamp = t
        // Place elbow at origin; shoulder straight up; wrist at `elbow` degrees from shoulder.
        b.set(.leftElbow, 0, 0)
        b.set(.leftShoulder, 0, 1)
        let rad = elbow * .pi / 180
        b.set(.leftWrist, sin(rad), cos(rad))
        // Back line: shoulder-hip-ankle. Hip at origin of that sub-angle.
        b.set(.leftHip, 5, 0)
        let backRad = backAngle * .pi / 180
        b.set(.leftAnkle, 5 + sin(backRad), -cos(backRad)) // shoulder already set above at (0,1)
        return b.build()
    }

    private func feed(_ a: inout PushupAnalyzer, _ frames: [PoseFrame]) -> [RepEvent] {
        var events: [RepEvent] = []
        for f in frames { events.append(contentsOf: a.process(f)) }
        return events
    }

    func testCountsCleanReps() {
        var a = PushupAnalyzer()
        // Two full reps: up(170) -> down(70) -> up(170), repeated.
        let frames = [
            frame(elbow: 170, t: 0.0), frame(elbow: 70, t: 0.5), frame(elbow: 170, t: 1.0),
            frame(elbow: 170, t: 1.4), frame(elbow: 70, t: 1.9), frame(elbow: 170, t: 2.4),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.repIndex), [1, 2])
    }

    func testShallowRepFlagsDepth() {
        var a = PushupAnalyzer()
        // Bottom only reaches 100 (above the 90 depth target) but still below downThreshold? No:
        // downThreshold is 110 so it registers a rep but flags shallow depth.
        let frames = [
            frame(elbow: 170, t: 0.0), frame(elbow: 100, t: 0.5), frame(elbow: 170, t: 1.0),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].findings.contains(.shallowDepth))
        XCTAssertLessThan(events[0].formScore, 1.0)
    }

    func testInfoIdIsPushup() {
        XCTAssertEqual(PushupAnalyzer().info.id, "pushup")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter PushupAnalyzerTests`
Expected: FAIL — `PushupAnalyzer` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Analyzer/PushupAnalyzer.swift`:
```swift
import Foundation

public struct PushupAnalyzer: ExerciseAnalyzer {
    public let info = ExerciseInfo(
        id: "pushup",
        displayName: "Push-up",
        trackedJoints: [.leftShoulder, .leftElbow, .leftWrist,
                        .rightShoulder, .rightElbow, .rightWrist,
                        .leftHip, .leftAnkle]
    )

    public private(set) var status: TrackingStatus = .outOfFrame

    // Thresholds tuned for elbow angle. downThreshold is generous so shallow
    // reps still register (and get flagged); depthTarget is the "good" bottom.
    private var detector = HysteresisRepDetector(downThreshold: 110, upThreshold: 160, minRepDuration: 0.3)
    private let depthTarget: Double = 90
    private let backStraightTolerance: Double = 25 // degrees from 180
    private let minConfidence: Double = 0.3

    private var repCount = 0
    private var minElbowThisRep = Double.greatestFiniteMagnitude
    private var worstBackDeviationThisRep = 0.0

    public init() {}

    public mutating func process(_ frame: PoseFrame) -> [RepEvent] {
        // Elbow angle from the higher-confidence side.
        guard let elbow = bestElbowAngle(frame) else {
            status = .outOfFrame
            return []
        }
        status = ConfidenceGate.status(
            for: frame,
            requiredJoints: [.leftShoulder, .leftElbow, .leftWrist],
            minConfidence: minConfidence
        )

        // Accumulate per-rep form metrics while we are below the top.
        minElbowThisRep = min(minElbowThisRep, elbow)
        if let back = backAngle(frame) {
            worstBackDeviationThisRep = max(worstBackDeviationThisRep, abs(180 - back))
        }

        guard detector.update(angle: elbow, timestamp: frame.timestamp) else { return [] }

        repCount += 1
        let event = grade(repIndex: repCount)
        minElbowThisRep = .greatestFiniteMagnitude
        worstBackDeviationThisRep = 0
        return [event]
    }

    public mutating func reset() {
        detector.reset()
        status = .outOfFrame
        repCount = 0
        minElbowThisRep = .greatestFiniteMagnitude
        worstBackDeviationThisRep = 0
    }

    private func grade(repIndex: Int) -> RepEvent {
        var findings: [Finding] = []
        var score = 1.0

        if minElbowThisRep > depthTarget {
            findings.append(.shallowDepth)
            // Penalize proportionally to how far short of depth (cap at 0.5).
            let shortBy = min(minElbowThisRep - depthTarget, 40)
            score -= 0.5 * (shortBy / 40)
        }
        if worstBackDeviationThisRep > backStraightTolerance {
            findings.append(.backNotStraight)
            score -= 0.3
        }
        return RepEvent(repIndex: repIndex, formScore: max(0, score), findings: findings)
    }

    private func bestElbowAngle(_ frame: PoseFrame) -> Double? {
        let left = elbowAngle(frame, .leftShoulder, .leftElbow, .leftWrist)
        let right = elbowAngle(frame, .rightShoulder, .rightElbow, .rightWrist)
        switch (left, right) {
        case let (l?, r?): return frame.confidence(.leftElbow) >= frame.confidence(.rightElbow) ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func elbowAngle(_ f: PoseFrame, _ s: JointName, _ e: JointName, _ w: JointName) -> Double? {
        guard let sp = f.point(s), let ep = f.point(e), let wp = f.point(w) else { return nil }
        return AngleMath.angle(at: ep, from: sp, to: wp)
    }

    private func backAngle(_ f: PoseFrame) -> Double? {
        guard let s = f.point(.leftShoulder), let h = f.point(.leftHip), let a = f.point(.leftAnkle) else { return nil }
        return AngleMath.angle(at: h, from: s, to: a)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChallengeCore && swift test --filter PushupAnalyzerTests`
Expected: PASS (3 tests). If `testShallowRepFlagsDepth` mis-asserts because of threshold tuning, adjust the test's `100` value or the analyzer's `downThreshold`/`depthTarget` so a 100° bottom registers a rep AND flags shallow depth — do not weaken the assertion that shallow depth is flagged.

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Analyzer/PushupAnalyzer.swift Tests/ChallengeCoreTests/PushupAnalyzerTests.swift
git commit -m "feat: add PushupAnalyzer"
```

## Task 9: SquatAnalyzer

Rep angle = knee (hip·knee·ankle), higher-confidence side. Form: depth (min knee angle must reach `depthTarget`) and torso lean (shoulder·hip vector vs. vertical must stay within range).

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Analyzer/SquatAnalyzer.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/SquatAnalyzerTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/SquatAnalyzerTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class SquatAnalyzerTests: XCTestCase {
    /// Frame whose knee angle equals `knee` degrees; torso vertical by default.
    private func frame(knee: Double, torsoLeanDeg: Double = 0, t: TimeInterval) -> PoseFrame {
        var b = PoseFrameBuilder()
        b.timestamp = t
        b.set(.leftKnee, 0, 0)
        b.set(.leftHip, 0, 1) // hip straight above knee
        let rad = knee * .pi / 180
        b.set(.leftAnkle, sin(rad), cos(rad)) // ankle at `knee` degrees from hip
        // Torso: shoulder relative to hip, leaned `torsoLeanDeg` from vertical.
        let lean = torsoLeanDeg * .pi / 180
        b.set(.leftShoulder, sin(lean), 1 + cos(lean))
        return b.build()
    }

    private func feed(_ a: inout SquatAnalyzer, _ frames: [PoseFrame]) -> [RepEvent] {
        var events: [RepEvent] = []
        for f in frames { events.append(contentsOf: a.process(f)) }
        return events
    }

    func testCountsCleanReps() {
        var a = SquatAnalyzer()
        let frames = [
            frame(knee: 170, t: 0.0), frame(knee: 80, t: 0.6), frame(knee: 170, t: 1.2),
            frame(knee: 170, t: 1.6), frame(knee: 80, t: 2.2), frame(knee: 170, t: 2.8),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 2)
    }

    func testExcessiveTorsoLeanFlagged() {
        var a = SquatAnalyzer()
        let frames = [
            frame(knee: 170, torsoLeanDeg: 0, t: 0.0),
            frame(knee: 80, torsoLeanDeg: 55, t: 0.6),  // big forward lean at the bottom
            frame(knee: 170, torsoLeanDeg: 0, t: 1.2),
        ]
        let events = feed(&a, frames)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].findings.contains(.torsoLean))
    }

    func testInfoIdIsSquat() {
        XCTAssertEqual(SquatAnalyzer().info.id, "squat")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter SquatAnalyzerTests`
Expected: FAIL — `SquatAnalyzer` not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Analyzer/SquatAnalyzer.swift`:
```swift
import Foundation

public struct SquatAnalyzer: ExerciseAnalyzer {
    public let info = ExerciseInfo(
        id: "squat",
        displayName: "Squat",
        trackedJoints: [.leftHip, .leftKnee, .leftAnkle, .leftShoulder,
                        .rightHip, .rightKnee, .rightAnkle, .rightShoulder]
    )

    public private(set) var status: TrackingStatus = .outOfFrame

    private var detector = HysteresisRepDetector(downThreshold: 110, upThreshold: 160, minRepDuration: 0.3)
    private let depthTarget: Double = 90        // thigh ~parallel
    private let torsoLeanTolerance: Double = 45  // degrees from vertical
    private let minConfidence: Double = 0.3

    private var repCount = 0
    private var minKneeThisRep = Double.greatestFiniteMagnitude
    private var worstTorsoLeanThisRep = 0.0

    public init() {}

    public mutating func process(_ frame: PoseFrame) -> [RepEvent] {
        guard let knee = bestKneeAngle(frame) else {
            status = .outOfFrame
            return []
        }
        status = ConfidenceGate.status(
            for: frame,
            requiredJoints: [.leftHip, .leftKnee, .leftAnkle],
            minConfidence: minConfidence
        )

        minKneeThisRep = min(minKneeThisRep, knee)
        if let lean = torsoLean(frame) {
            worstTorsoLeanThisRep = max(worstTorsoLeanThisRep, lean)
        }

        guard detector.update(angle: knee, timestamp: frame.timestamp) else { return [] }

        repCount += 1
        let event = grade(repIndex: repCount)
        minKneeThisRep = .greatestFiniteMagnitude
        worstTorsoLeanThisRep = 0
        return [event]
    }

    public mutating func reset() {
        detector.reset()
        status = .outOfFrame
        repCount = 0
        minKneeThisRep = .greatestFiniteMagnitude
        worstTorsoLeanThisRep = 0
    }

    private func grade(repIndex: Int) -> RepEvent {
        var findings: [Finding] = []
        var score = 1.0
        if minKneeThisRep > depthTarget {
            findings.append(.shallowDepth)
            let shortBy = min(minKneeThisRep - depthTarget, 40)
            score -= 0.5 * (shortBy / 40)
        }
        if worstTorsoLeanThisRep > torsoLeanTolerance {
            findings.append(.torsoLean)
            score -= 0.3
        }
        return RepEvent(repIndex: repIndex, formScore: max(0, score), findings: findings)
    }

    private func bestKneeAngle(_ f: PoseFrame) -> Double? {
        let left = kneeAngle(f, .leftHip, .leftKnee, .leftAnkle)
        let right = kneeAngle(f, .rightHip, .rightKnee, .rightAnkle)
        switch (left, right) {
        case let (l?, r?): return f.confidence(.leftKnee) >= f.confidence(.rightKnee) ? l : r
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    private func kneeAngle(_ f: PoseFrame, _ h: JointName, _ k: JointName, _ a: JointName) -> Double? {
        guard let hp = f.point(h), let kp = f.point(k), let ap = f.point(a) else { return nil }
        return AngleMath.angle(at: kp, from: hp, to: ap)
    }

    /// Angle of the shoulder->hip torso vector away from vertical, in degrees.
    private func torsoLean(_ f: PoseFrame) -> Double? {
        guard let s = f.point(.leftShoulder), let h = f.point(.leftHip) else { return nil }
        let dx = s.x - h.x
        let dy = s.y - h.y
        let mag = (dx * dx + dy * dy).squareRoot()
        guard mag > 0 else { return 0 }
        // vertical is (0,1); lean = angle between torso vector and vertical.
        let cosine = min(1, max(-1, dy / mag))
        return acos(cosine) * 180 / .pi
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ChallengeCore && swift test --filter SquatAnalyzerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Analyzer/SquatAnalyzer.swift Tests/ChallengeCoreTests/SquatAnalyzerTests.swift
git commit -m "feat: add SquatAnalyzer"
```

## Task 10: ExerciseRegistry

**Files:**
- Create: `ChallengeCore/Sources/ChallengeCore/Analyzer/ExerciseRegistry.swift`
- Test: `ChallengeCore/Tests/ChallengeCoreTests/ExerciseRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ChallengeCoreTests/ExerciseRegistryTests.swift`:
```swift
import XCTest
@testable import ChallengeCore

final class ExerciseRegistryTests: XCTestCase {
    func testKnownIdsReturnFreshAnalyzers() {
        XCTAssertEqual(ExerciseRegistry.makeAnalyzer(for: "pushup")?.info.id, "pushup")
        XCTAssertEqual(ExerciseRegistry.makeAnalyzer(for: "squat")?.info.id, "squat")
    }

    func testUnknownIdReturnsNil() {
        XCTAssertNil(ExerciseRegistry.makeAnalyzer(for: "moonwalk"))
    }

    func testAllExercisesListsKnownIds() {
        let ids = ExerciseRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids), ["pushup", "squat"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ChallengeCore && swift test --filter ExerciseRegistryTests`
Expected: FAIL — type not found.

- [ ] **Step 3: Write minimal implementation**

`Sources/ChallengeCore/Analyzer/ExerciseRegistry.swift`:
```swift
public enum ExerciseRegistry {
    /// Metadata for every selectable exercise (for menus etc.).
    public static let all: [ExerciseInfo] = [
        PushupAnalyzer().info,
        SquatAnalyzer().info,
    ]

    /// A fresh analyzer for the given id, or nil if unknown.
    public static func makeAnalyzer(for id: String) -> (any ExerciseAnalyzer)? {
        switch id {
        case "pushup": return PushupAnalyzer()
        case "squat": return SquatAnalyzer()
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run the full suite**

Run: `cd ChallengeCore && swift test`
Expected: PASS — all tests across all files.

- [ ] **Step 5: Commit**

```bash
git add Sources/ChallengeCore/Analyzer/ExerciseRegistry.swift Tests/ChallengeCoreTests/ExerciseRegistryTests.swift
git commit -m "feat: add ExerciseRegistry"
```

**End of Phase 1: `ChallengeCore` is a complete, fully tested engine.**

---

# PHASE 2 — The `WorkoutVision` app

This phase wires the engine into an iOS app. Pure logic (coordinator, persistence, Vision mapping) is test-driven; camera capture and SwiftUI views are concrete code verified on device. The app depends on the `ChallengeCore` package from Phase 1 via a local path.

## Task 11: Scaffold the app with XcodeGen

**Files:**
- Create: `WorkoutVision/project.yml`
- Create: `WorkoutVision/Sources/App/WorkoutVisionApp.swift`

- [ ] **Step 1: Write the XcodeGen spec**

`WorkoutVision/project.yml`:
```yaml
name: WorkoutVision
options:
  bundleIdPrefix: com.dmbritton
  deploymentTarget:
    iOS: "17.0"
packages:
  ChallengeCore:
    path: ../ChallengeCore
targets:
  WorkoutVision:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies:
      - package: ChallengeCore
    info:
      path: Sources/App/Info.plist
      properties:
        NSCameraUsageDescription: "WorkoutVision uses the camera to count your reps and check your form."
        UILaunchScreen: {}
  WorkoutVisionTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: WorkoutVision
      - package: ChallengeCore
```

- [ ] **Step 2: Add the app entry point**

`WorkoutVision/Sources/App/WorkoutVisionApp.swift`:
```swift
import SwiftUI
import SwiftData

@main
struct WorkoutVisionApp: App {
    var body: some Scene {
        WindowGroup {
            BuildWorkoutView()
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self])
    }
}
```

- [ ] **Step 3: Generate and verify the project**

Run: `cd WorkoutVision && xcodegen generate`
Expected: `Created project at WorkoutVision.xcodeproj`. (This step won't fully build until later tasks add the referenced views/models — that's expected; the goal here is a valid project file.)

- [ ] **Step 4: Commit**

```bash
git add WorkoutVision/project.yml WorkoutVision/Sources/App
git commit -m "chore: scaffold WorkoutVision app with XcodeGen"
```

## Task 12: SwiftData models

**Files:**
- Create: `WorkoutVision/Sources/Persistence/WorkoutSession.swift`
- Create: `WorkoutVision/Sources/Persistence/ExerciseSet.swift`
- Test: `WorkoutVision/Tests/PersistenceTests.swift`

- [ ] **Step 1: Write the failing test**

`WorkoutVision/Tests/PersistenceTests.swift`:
```swift
import XCTest
import SwiftData
@testable import WorkoutVision

final class PersistenceTests: XCTestCase {
    private func inMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutSession.self, ExerciseSet.self, configurations: config)
        return ModelContext(container)
    }

    func testSaveAndFetchSessionWithSets() throws {
        let ctx = try inMemoryContext()
        let session = WorkoutSession(startedAt: Date())
        let set = ExerciseSet(exerciseID: "squat", targetReps: 12, order: 0)
        set.completedReps = 12
        set.averageFormScore = 0.9
        set.findingsSummary = ["shallowDepth": 2]
        session.sets.append(set)
        session.endedAt = Date()
        ctx.insert(session)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].sets.count, 1)
        XCTAssertEqual(fetched[0].sets[0].exerciseID, "squat")
        XCTAssertEqual(fetched[0].sets[0].findingsSummary["shallowDepth"], 2)
        XCTAssertEqual(fetched[0].totalReps, 12)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/PersistenceTests`
Expected: FAIL — models not defined / build error.

- [ ] **Step 3: Implement the models**

`WorkoutVision/Sources/Persistence/ExerciseSet.swift`:
```swift
import Foundation
import SwiftData

@Model
final class ExerciseSet {
    var exerciseID: String
    var targetReps: Int
    var completedReps: Int
    var averageFormScore: Double
    /// Finding rawValue -> count, stored as a small encodable dictionary.
    var findingsSummary: [String: Int]
    var order: Int

    init(exerciseID: String, targetReps: Int, order: Int) {
        self.exerciseID = exerciseID
        self.targetReps = targetReps
        self.completedReps = 0
        self.averageFormScore = 0
        self.findingsSummary = [:]
        self.order = order
    }
}
```

`WorkoutVision/Sources/Persistence/WorkoutSession.swift`:
```swift
import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var startedAt: Date
    var endedAt: Date?
    @Relationship(deleteRule: .cascade) var sets: [ExerciseSet]

    init(startedAt: Date) {
        self.startedAt = startedAt
        self.endedAt = nil
        self.sets = []
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.completedReps } }

    var averageFormScore: Double {
        let scored = sets.filter { $0.completedReps > 0 }
        guard !scored.isEmpty else { return 0 }
        return scored.reduce(0) { $0 + $1.averageFormScore } / Double(scored.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/PersistenceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutVision/Sources/Persistence WorkoutVision/Tests/PersistenceTests.swift
git commit -m "feat: add SwiftData WorkoutSession and ExerciseSet models"
```

## Task 13: SessionCoordinator

The coordinator owns workout state: an ordered list of `PlannedSet`s, the current index, the active analyzer, the live rep count, and live form findings. It exposes a `feed(_:)` entry point that forwards frames to the active analyzer and accumulates results. It is UI-agnostic and testable with a fake frame stream.

**Files:**
- Create: `WorkoutVision/Sources/Session/PlannedSet.swift`
- Create: `WorkoutVision/Sources/Session/SessionCoordinator.swift`
- Test: `WorkoutVision/Tests/SessionCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

`WorkoutVision/Tests/SessionCoordinatorTests.swift`:
```swift
import XCTest
import ChallengeCore
@testable import WorkoutVision

final class SessionCoordinatorTests: XCTestCase {
    /// One squat rep: down then up, repeated `count` times.
    private func squatReps(_ count: Int) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = 0.0
        for _ in 0..<count {
            for knee in [170.0, 80.0, 170.0] {
                var b = PoseFrameBuilderShim()
                b.timestamp = t
                b.knee(knee)
                frames.append(b.build())
                t += 0.5
            }
        }
        return frames
    }

    func testAdvancesToNextSetWhenTargetReached() {
        let plan = [
            PlannedSet(exerciseID: "squat", targetReps: 2),
            PlannedSet(exerciseID: "squat", targetReps: 2),
        ]
        let coord = SessionCoordinator(plan: plan)
        coord.start()
        XCTAssertEqual(coord.currentSetIndex, 0)

        for f in squatReps(2) { coord.feed(f) }

        XCTAssertEqual(coord.currentSetIndex, 1)
        XCTAssertEqual(coord.phase, .resting)
    }

    func testFinishingLastSetCompletesSession() {
        let coord = SessionCoordinator(plan: [PlannedSet(exerciseID: "squat", targetReps: 1)])
        coord.start()
        for f in squatReps(1) { coord.feed(f) }
        XCTAssertEqual(coord.phase, .finished)
    }
}
```

Also create the test shim `WorkoutVision/Tests/PoseFrameBuilderShim.swift`:
```swift
import Foundation
import ChallengeCore

/// Minimal frame builder for app-layer tests (mirrors the engine test helper).
struct PoseFrameBuilderShim {
    var timestamp: TimeInterval = 0
    private var joints: [JointName: Joint] = [:]

    mutating func knee(_ deg: Double) {
        joints[.leftKnee] = Joint(position: Point2D(x: 0, y: 0), confidence: 1)
        joints[.leftHip] = Joint(position: Point2D(x: 0, y: 1), confidence: 1)
        let rad = deg * .pi / 180
        joints[.leftAnkle] = Joint(position: Point2D(x: sin(rad), y: cos(rad)), confidence: 1)
        joints[.leftShoulder] = Joint(position: Point2D(x: 0, y: 2), confidence: 1)
    }

    func build() -> PoseFrame { PoseFrame(timestamp: timestamp, joints: joints) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/SessionCoordinatorTests`
Expected: FAIL — `SessionCoordinator` / `PlannedSet` not defined.

- [ ] **Step 3: Implement PlannedSet and SessionCoordinator**

`WorkoutVision/Sources/Session/PlannedSet.swift`:
```swift
import Foundation

struct PlannedSet: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: String
    let targetReps: Int
}
```

`WorkoutVision/Sources/Session/SessionCoordinator.swift`:
```swift
import Foundation
import Observation
import ChallengeCore

@Observable
final class SessionCoordinator {
    enum Phase: Equatable { case idle, active, resting, finished }

    let plan: [PlannedSet]
    private(set) var currentSetIndex = 0
    private(set) var phase: Phase = .idle
    private(set) var currentReps = 0
    private(set) var lastFindings: [Finding] = []
    private(set) var status: TrackingStatus = .outOfFrame

    /// Completed set results, ready to persist when the session finishes.
    private(set) var results: [SetResult] = []

    private var analyzer: (any ExerciseAnalyzer)?
    private var formScores: [Double] = []
    private var findingCounts: [String: Int] = [:]

    struct SetResult {
        let exerciseID: String
        let targetReps: Int
        let completedReps: Int
        let averageFormScore: Double
        let findingsSummary: [String: Int]
    }

    init(plan: [PlannedSet]) {
        self.plan = plan
    }

    func start() {
        currentSetIndex = 0
        loadCurrentSet()
        phase = plan.isEmpty ? .finished : .active
    }

    /// Call from the rest screen to begin the next set.
    func beginNextSet() {
        guard phase == .resting else { return }
        loadCurrentSet()
        phase = .active
    }

    func feed(_ frame: PoseFrame) {
        guard phase == .active, var analyzer else { return }
        let events = analyzer.process(frame)
        self.status = analyzer.status
        self.analyzer = analyzer // write back the mutated struct

        for event in events {
            currentReps = event.repIndex
            lastFindings = event.findings
            formScores.append(event.formScore)
            for f in event.findings { findingCounts[f.rawValue, default: 0] += 1 }
        }

        if currentReps >= plan[currentSetIndex].targetReps {
            finishCurrentSet()
        }
    }

    private func loadCurrentSet() {
        let set = plan[currentSetIndex]
        analyzer = ExerciseRegistry.makeAnalyzer(for: set.exerciseID)
        analyzer?.reset()
        currentReps = 0
        lastFindings = []
        formScores = []
        findingCounts = [:]
    }

    private func finishCurrentSet() {
        let set = plan[currentSetIndex]
        let avg = formScores.isEmpty ? 0 : formScores.reduce(0, +) / Double(formScores.count)
        results.append(SetResult(
            exerciseID: set.exerciseID,
            targetReps: set.targetReps,
            completedReps: currentReps,
            averageFormScore: avg,
            findingsSummary: findingCounts
        ))

        if currentSetIndex + 1 < plan.count {
            currentSetIndex += 1
            phase = .resting
        } else {
            phase = .finished
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/SessionCoordinatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutVision/Sources/Session WorkoutVision/Tests/SessionCoordinatorTests.swift WorkoutVision/Tests/PoseFrameBuilderShim.swift
git commit -m "feat: add SessionCoordinator workout state machine"
```

## Task 14: VisionPoseMapper

Maps `VNHumanBodyPoseObservation` joint points into the engine's `PoseFrame`. This is the only place Vision's coordinate space and joint names touch the engine's pure types. Test the mapping table with a stubbed observation-like input.

**Files:**
- Create: `WorkoutVision/Sources/Capture/VisionPoseMapper.swift`
- Test: `WorkoutVision/Tests/VisionPoseMapperTests.swift`

- [ ] **Step 1: Write the failing test**

`WorkoutVision/Tests/VisionPoseMapperTests.swift`:
```swift
import XCTest
import CoreGraphics
import ChallengeCore
@testable import WorkoutVision

final class VisionPoseMapperTests: XCTestCase {
    func testMapsRecognizedPointsToPoseFrame() {
        let points: [JointName: (CGPoint, Double)] = [
            .leftElbow: (CGPoint(x: 0.4, y: 0.6), 0.9),
            .leftWrist: (CGPoint(x: 0.4, y: 0.8), 0.2),
        ]
        let frame = VisionPoseMapper.makeFrame(from: points, timestamp: 1.5)

        XCTAssertEqual(frame.timestamp, 1.5)
        XCTAssertEqual(frame.point(.leftElbow), Point2D(x: 0.4, y: 0.6))
        XCTAssertEqual(frame.confidence(.leftElbow), 0.9, accuracy: 0.0001)
        XCTAssertEqual(frame.confidence(.leftWrist), 0.2, accuracy: 0.0001)
        XCTAssertNil(frame.joint(.rightAnkle))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/VisionPoseMapperTests`
Expected: FAIL — type not defined.

- [ ] **Step 3: Implement the mapper**

`WorkoutVision/Sources/Capture/VisionPoseMapper.swift`:
```swift
import Foundation
import CoreGraphics
import Vision
import ChallengeCore

enum VisionPoseMapper {
    /// Vision joint name -> engine joint name.
    static let jointTable: [VNHumanBodyPoseObservation.JointName: JointName] = [
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    /// Pure mapping used by both production code and tests.
    static func makeFrame(from points: [JointName: (CGPoint, Double)], timestamp: TimeInterval) -> PoseFrame {
        var joints: [JointName: Joint] = [:]
        for (name, value) in points {
            joints[name] = Joint(position: Point2D(x: Double(value.0.x), y: Double(value.0.y)),
                                 confidence: value.1)
        }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }

    /// Production entry point: convert a Vision observation into a PoseFrame.
    static func makeFrame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> PoseFrame {
        var points: [JointName: (CGPoint, Double)] = [:]
        for (visionName, engineName) in jointTable {
            if let p = try? observation.recognizedPoint(visionName), p.confidence > 0 {
                points[engineName] = (p.location, Double(p.confidence))
            }
        }
        return makeFrame(from: points, timestamp: timestamp)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd WorkoutVision && xcodebuild test -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:WorkoutVisionTests/VisionPoseMapperTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutVision/Sources/Capture/VisionPoseMapper.swift WorkoutVision/Tests/VisionPoseMapperTests.swift
git commit -m "feat: add VisionPoseMapper"
```

## Task 15: CameraSession + PosePipeline

Camera capture and the Vision request live here. This is device-verified (the simulator has no camera). Crib the capture setup from WakeupCall's existing camera code.

**Files:**
- Create: `WorkoutVision/Sources/Capture/CameraSession.swift`
- Create: `WorkoutVision/Sources/Capture/PosePipeline.swift`

- [ ] **Step 1: Implement CameraSession**

`WorkoutVision/Sources/Capture/CameraSession.swift`:
```swift
import AVFoundation

/// Owns the AVCaptureSession and emits sample buffers to a delegate.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames")
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure() throws {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw NSError(domain: "CameraSession", code: 1)
        }
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func start() { queue.async { [session] in if !session.isRunning { session.startRunning() } } }
    func stop() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }
}
```

- [ ] **Step 2: Implement PosePipeline (glue: buffer -> Vision -> mapper -> coordinator)**

`WorkoutVision/Sources/Capture/PosePipeline.swift`:
```swift
import AVFoundation
import Vision
import ChallengeCore

/// Runs Vision pose detection on camera frames and feeds the coordinator.
final class PosePipeline {
    private let camera = CameraSession()
    private let coordinator: SessionCoordinator

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    func startThrowing() throws {
        try camera.configure()
        camera.onSampleBuffer = { [weak self] buffer in self?.handle(buffer) }
        camera.start()
    }

    func stop() { camera.stop() }

    private func handle(_ buffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        guard let observation = request.results?.first else { return }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        let frame = VisionPoseMapper.makeFrame(from: observation, timestamp: timestamp)
        Task { @MainActor in self.coordinator.feed(frame) }
    }
}
```

- [ ] **Step 3: Verify the app builds**

Run: `cd WorkoutVision && xcodebuild build -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add WorkoutVision/Sources/Capture/CameraSession.swift WorkoutVision/Sources/Capture/PosePipeline.swift
git commit -m "feat: add camera capture and pose pipeline"
```

## Task 15b: Camera permission gate

Spec §8 requires a clear explainer + Settings deep-link when camera access is denied, not a silent failure.

**Files:**
- Create: `WorkoutVision/Sources/Capture/CameraAuthorization.swift`

- [ ] **Step 1: Implement the authorization helper**

`WorkoutVision/Sources/Capture/CameraAuthorization.swift`:
```swift
import AVFoundation

enum CameraAuthorization {
    enum State { case authorized, denied, undetermined }

    static var current: State {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd WorkoutVision && xcodebuild build -scheme WorkoutVision -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add WorkoutVision/Sources/Capture/CameraAuthorization.swift
git commit -m "feat: add camera authorization helper"
```

## Task 16: Views — Build, Live, Skeleton, Summary, History

These are SwiftUI views verified on device. Each is concrete; wire them to the coordinator and SwiftData.

**Files:**
- Create: `WorkoutVision/Sources/Views/BuildWorkoutView.swift`
- Create: `WorkoutVision/Sources/Views/LiveWorkoutView.swift`
- Create: `WorkoutVision/Sources/Views/SkeletonOverlay.swift`
- Create: `WorkoutVision/Sources/Views/SummaryView.swift`
- Create: `WorkoutVision/Sources/Views/HistoryView.swift`

- [ ] **Step 1: BuildWorkoutView (pick exercises + targets, then start)**

`WorkoutVision/Sources/Views/BuildWorkoutView.swift`:
```swift
import SwiftUI
import ChallengeCore

struct BuildWorkoutView: View {
    @State private var plan: [PlannedSet] = []
    @State private var started = false

    var body: some View {
        NavigationStack {
            List {
                Section("Exercises") {
                    ForEach(ExerciseRegistry.all, id: \.id) { info in
                        Button("Add 1 set of \(info.displayName) (×10)") {
                            plan.append(PlannedSet(exerciseID: info.id, targetReps: 10))
                        }
                    }
                }
                Section("Your workout") {
                    if plan.isEmpty { Text("No sets yet").foregroundStyle(.secondary) }
                    ForEach(plan) { set in
                        Text("\(displayName(set.exerciseID)) — \(set.targetReps) reps")
                    }
                    .onDelete { plan.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Build Workout")
            .toolbar {
                NavigationLink("History") { HistoryView() }
            }
            .safeAreaInset(edge: .bottom) {
                NavigationLink("Start Workout") { LiveWorkoutView(plan: plan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.isEmpty)
                    .padding()
            }
        }
    }

    private func displayName(_ id: String) -> String {
        ExerciseRegistry.all.first { $0.id == id }?.displayName ?? id
    }
}
```

- [ ] **Step 2: SkeletonOverlay (draw joints over the preview)**

`WorkoutVision/Sources/Views/SkeletonOverlay.swift`:
```swift
import SwiftUI
import ChallengeCore

/// Draws joint dots from the latest PoseFrame. Coordinates are normalized (0...1).
struct SkeletonOverlay: View {
    let joints: [JointName: Joint]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(joints.keys), id: \.self) { name in
                if let j = joints[name] {
                    Circle()
                        .fill(j.confidence > 0.3 ? Color.green : Color.yellow)
                        .frame(width: 10, height: 10)
                        .position(x: j.position.x * geo.size.width,
                                  y: (1 - j.position.y) * geo.size.height) // Vision y is bottom-up
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: LiveWorkoutView (camera + counter + cues + rest)**

`WorkoutVision/Sources/Views/LiveWorkoutView.swift`:
```swift
import SwiftUI
import SwiftData
import UIKit
import ChallengeCore

struct LiveWorkoutView: View {
    let plan: [PlannedSet]
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator: SessionCoordinator
    @State private var pipeline: PosePipeline?
    @State private var latestJoints: [JointName: Joint] = [:]
    @State private var saved = false
    @State private var cameraDenied = false

    init(plan: [PlannedSet]) {
        self.plan = plan
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SkeletonOverlay(joints: latestJoints).ignoresSafeArea()

            VStack {
                if cameraDenied {
                    VStack(spacing: 12) {
                        Text("Camera access is off").font(.title2).foregroundStyle(.white)
                        Text("WorkoutVision needs the camera to count your reps.").foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                } else if coordinator.phase == .active {
                    let set = plan[coordinator.currentSetIndex]
                    Text("Set \(coordinator.currentSetIndex + 1)/\(plan.count) · \(coordinator.currentReps)/\(set.targetReps)")
                        .font(.title2).foregroundStyle(.white)
                    Text("\(coordinator.currentReps)").font(.system(size: 96, weight: .bold)).foregroundStyle(.white)
                    cueText
                } else if coordinator.phase == .resting {
                    Text("Rest").font(.largeTitle).foregroundStyle(.white)
                    Button("Next set") { coordinator.beginNextSet() }.buttonStyle(.borderedProminent)
                } else if coordinator.phase == .finished {
                    SummaryView(results: coordinator.results)
                        .onAppear { saveIfNeeded() }
                }
            }
            .padding()
        }
        .onAppear { coordinator.start(); Task { await startCamera() } }
        .onDisappear { pipeline?.stop() }
    }

    @ViewBuilder private var cueText: some View {
        switch coordinator.status {
        case .outOfFrame: Text("Step back so I can see you").foregroundStyle(.yellow)
        case .lowConfidence: Text("Improve lighting").foregroundStyle(.yellow)
        case .tracking:
            if let f = coordinator.lastFindings.first {
                Text(cue(for: f)).foregroundStyle(.orange)
            }
        }
    }

    private func cue(for f: Finding) -> String {
        switch f {
        case .shallowDepth: return "Go deeper"
        case .backNotStraight: return "Straighten your back"
        case .torsoLean: return "Keep your chest up"
        case .kneesCaving: return "Push your knees out"
        }
    }

    private func startCamera() async {
        switch CameraAuthorization.current {
        case .denied:
            cameraDenied = true
            return
        case .undetermined:
            let granted = await CameraAuthorization.request()
            if !granted { cameraDenied = true; return }
        case .authorized:
            break
        }
        let p = PosePipeline(coordinator: coordinator)
        do { try p.startThrowing(); pipeline = p } catch { cameraDenied = true }
    }

    private func saveIfNeeded() {
        guard !saved else { return }
        saved = true
        let session = WorkoutSession(startedAt: Date())
        for (i, r) in coordinator.results.enumerated() {
            let set = ExerciseSet(exerciseID: r.exerciseID, targetReps: r.targetReps, order: i)
            set.completedReps = r.completedReps
            set.averageFormScore = r.averageFormScore
            set.findingsSummary = r.findingsSummary
            session.sets.append(set)
        }
        session.endedAt = Date()
        modelContext.insert(session)
        try? modelContext.save()
    }
}
```

- [ ] **Step 4: SummaryView**

`WorkoutVision/Sources/Views/SummaryView.swift`:
```swift
import SwiftUI

struct SummaryView: View {
    let results: [SessionCoordinator.SetResult]

    var body: some View {
        VStack(spacing: 16) {
            Text("Workout Complete").font(.largeTitle).foregroundStyle(.white)
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                VStack {
                    Text("\(r.exerciseID): \(r.completedReps)/\(r.targetReps) reps").foregroundStyle(.white)
                    Text("Form \(Int(r.averageFormScore * 100))%").foregroundStyle(.secondary)
                }
            }
            NavigationLink("Done") { BuildWorkoutView() }.buttonStyle(.borderedProminent)
        }
    }
}
```

- [ ] **Step 5: HistoryView**

`WorkoutVision/Sources/Views/HistoryView.swift`:
```swift
import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        List(sessions) { session in
            VStack(alignment: .leading) {
                Text(session.startedAt, style: .date)
                Text("\(session.totalReps) reps · form \(Int(session.averageFormScore * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("History")
    }
}
```

- [ ] **Step 6: Build and verify on device**

Run: `cd WorkoutVision && xcodebuild build -scheme WorkoutVision -destination 'generic/platform=iOS'`
Expected: `BUILD SUCCEEDED`. Then run on a physical device (camera required): build a workout with squats, prop the phone up, perform reps, confirm: live count increments, "go deeper" appears on shallow reps, set advances at target, summary shows, and the session appears in History.

- [ ] **Step 7: Commit**

```bash
git add WorkoutVision/Sources/Views
git commit -m "feat: add app screens (build, live, summary, history)"
```

**End of Phase 2: working app.**

---

## Notes for the implementer

- **Threshold tuning is expected.** The angle constants in `PushupAnalyzer`/`SquatAnalyzer` (down/up thresholds, depth targets, tolerances) are starting points. Use WakeupCall's tuned pushup values where they exist, and tune squats against real device sessions. Tests assert *behavior* (a shallow rep is flagged), not exact constants — keep them that way.
- **Skeleton overlay live data.** Task 16 keeps the coordinator as the source of truth; if you want the overlay to render every frame (not just on rep completion), add an `onFrame: ((PoseFrame) -> Void)?` callback to `PosePipeline` and set `latestJoints` from it. Left as a v1 polish item.
- **Background/resume (spec §8).** Task 16 stops the pipeline on `onDisappear`; full pause-and-resume of an in-progress set across app backgrounding is a v1 simplification. To complete it, observe `scenePhase` in `LiveWorkoutView`: stop the pipeline on `.background` and restart it on `.active` without resetting `coordinator` (the coordinator's in-progress rep state already persists since it's not recreated). Add when polishing.
- **Sit-ups** are deferred (spec §10). Adding one is: a `SitupAnalyzer` conforming to `ExerciseAnalyzer` + a registry case + a test file — no other changes.
```
