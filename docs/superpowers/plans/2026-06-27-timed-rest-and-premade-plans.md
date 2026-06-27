# Timed Rest + Premade Plans Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual "Start next set" button with an auto-counting rest timer (duration set in the builder), and add a Plans tab of curated workouts that load into the builder.

**Architecture:** A new `RootView` `TabView` owns the editable workout draft (`entries` + `restSeconds`) shared by the Workout and Plans tabs. Rest is a self-driving `RestCountdownView` that calls the existing `coordinator.beginNextSet()` — `SessionCoordinator` is untouched. Premade plans are pure data (`PremadePlan` + catalog + a pure time estimate).

**Tech Stack:** Swift 6, SwiftUI (`TabView`, `.task`), `ChallengeCore` (`ExerciseRegistry`), XCTest. iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`. XcodeGen auto-discovers files under `Sources/`/`Tests/` on `xcodegen generate` in `CrazyWork/`. Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).

> **Spec:** `docs/superpowers/specs/2026-06-27-timed-rest-and-premade-plans-design.md`

---

## File Structure

- Create `CrazyWork/Sources/Session/PremadePlan.swift` — `PremadePlan` model, `estimatedSeconds`, `PremadePlanCatalog`.
- Create `CrazyWork/Sources/Views/PremadePlansView.swift` — the Plans tab list.
- Create `CrazyWork/Sources/Views/RestCountdownView.swift` — self-driving rest timer.
- Create `CrazyWork/Sources/Views/RootView.swift` — the `TabView` root + shared draft.
- Modify `CrazyWork/Sources/App/CrazyWorkApp.swift` — render `RootView`.
- Modify `CrazyWork/Sources/Views/BuildWorkoutView.swift` — binding-driven; rest stepper; drop History toolbar link.
- Modify `CrazyWork/Sources/Views/LiveWorkoutView.swift` — accept `restSeconds`; use `RestCountdownView`.
- Create `CrazyWork/Tests/PremadePlanTests.swift` — pure-logic tests.

**Dependency order:** the pure model (Task 1), the two leaf views (Tasks 2-3) are independent green additions; Task 4 wires the TabView/builder; Task 5 connects rest into the live view.

---

### Task 1: Premade plan model, estimate, and catalog (pure)

**Files:**
- Create: `CrazyWork/Sources/Session/PremadePlan.swift`
- Test: `CrazyWork/Tests/PremadePlanTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CrazyWork/Tests/PremadePlanTests.swift`:

```swift
import XCTest
import ChallengeCore
@testable import CrazyWork

final class PremadePlanTests: XCTestCase {
    func testEstimatedSecondsForExpress5() {
        let plan = PremadePlanCatalog.all.first { $0.id == "express5" }!
        // pushup 2×10×3=60, squat 2×12×3=72, plank 1×30=30 => work 162.
        // 5 total sets => 4 rests × 20s = 80. Total 242.
        XCTAssertEqual(plan.estimatedSeconds(), 242)
    }

    func testCatalogInvariants() {
        let plans = PremadePlanCatalog.all
        XCTAssertFalse(plans.isEmpty)
        let ids = plans.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count) // unique ids
        let known = Set(ExerciseRegistry.all.map(\.id))
        for plan in plans {
            XCTAssertFalse(plan.entries.isEmpty)
            for entry in plan.entries {
                XCTAssertTrue(known.contains(entry.exerciseID), "unknown exercise \(entry.exerciseID)")
                XCTAssertGreaterThanOrEqual(entry.sets, 1)
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO \
  -only-testing:CrazyWorkTests/PremadePlanTests 2>&1 | tail -20
```
Expected: FAILS to compile — `PremadePlan`/`PremadePlanCatalog` don't exist.

- [ ] **Step 3: Implement the model**

Create `CrazyWork/Sources/Session/PremadePlan.swift`:

```swift
import Foundation
import ChallengeCore

/// A curated, ready-to-load workout: a name, a one-line summary, the exercises
/// (as builder entries), and the rest between sets.
struct PremadePlan: Identifiable {
    let id: String
    let name: String
    let summary: String
    let entries: [WorkoutEntry]
    let restSeconds: Int
}

extension PremadePlan {
    /// Rough completion estimate in seconds: total work plus inter-set rest.
    /// Reps are estimated at `secondsPerRep` each; a timed hold counts its seconds.
    func estimatedSeconds(secondsPerRep: Double = 3) -> Int {
        let totalSets = entries.reduce(0) { $0 + max(0, $1.sets) }
        let work = entries.reduce(0.0) { running, entry in
            let unit = ExerciseRegistry.all.first { $0.id == entry.exerciseID }?.goalUnit ?? .reps
            let perSet = unit == .reps ? Double(entry.target) * secondsPerRep : Double(entry.target)
            return running + Double(max(0, entry.sets)) * perSet
        }
        let rest = Double(max(0, totalSets - 1)) * Double(restSeconds)
        return Int((work + rest).rounded())
    }
}

/// The built-in plans shown in the Plans tab. Built from the existing exercises.
enum PremadePlanCatalog {
    static let all: [PremadePlan] = [
        PremadePlan(id: "express5", name: "Express 5",
                    summary: "A quick full-body hit.",
                    entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10),
                              WorkoutEntry(exerciseID: "squat", sets: 2, target: 12),
                              WorkoutEntry(exerciseID: "plank", sets: 1, target: 30)],
                    restSeconds: 20),
        PremadePlan(id: "fullBodyStarter", name: "Full Body Starter",
                    summary: "Balanced beginner session.",
                    entries: [WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10),
                              WorkoutEntry(exerciseID: "squat", sets: 3, target: 12),
                              WorkoutEntry(exerciseID: "lunge", sets: 3, target: 10),
                              WorkoutEntry(exerciseID: "plank", sets: 2, target: 30)],
                    restSeconds: 30),
        PremadePlan(id: "legDay", name: "Leg Day",
                    summary: "Lower-body focus.",
                    entries: [WorkoutEntry(exerciseID: "squat", sets: 4, target: 12),
                              WorkoutEntry(exerciseID: "lunge", sets: 3, target: 12),
                              WorkoutEntry(exerciseID: "plank", sets: 2, target: 45)],
                    restSeconds: 45),
        PremadePlan(id: "coreHold", name: "Core & Hold",
                    summary: "Core and stability.",
                    entries: [WorkoutEntry(exerciseID: "plank", sets: 3, target: 30),
                              WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10)],
                    restSeconds: 30),
    ]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2. Expected: both `PremadePlanTests` pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Session/PremadePlan.swift CrazyWork/Tests/PremadePlanTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: premade workout plan model, catalog, and time estimate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Plans tab view

**Files:**
- Create: `CrazyWork/Sources/Views/PremadePlansView.swift`

No unit test (presentation); verified by build here and wired in Task 4.

- [ ] **Step 1: Implement the view**

Create `CrazyWork/Sources/Views/PremadePlansView.swift`:

```swift
import SwiftUI
import ChallengeCore

/// The Plans tab: curated workouts shown as cards (name, estimated time,
/// description, exercise summary). Choosing one hands the plan back via
/// `onChoose` — `RootView` loads it into the builder and switches tabs.
struct PremadePlansView: View {
    let onChoose: (PremadePlan) -> Void

    var body: some View {
        NavigationStack {
            List(PremadePlanCatalog.all) { plan in
                Button { onChoose(plan) } label: { card(plan) }
                    .buttonStyle(.plain)
            }
            .navigationTitle("Plans")
        }
    }

    private func card(_ plan: PremadePlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.name).font(.headline)
                Spacer()
                Label(timeText(plan), systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(plan.summary).font(.subheadline).foregroundStyle(.secondary)
            Text(exerciseSummary(plan)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func timeText(_ plan: PremadePlan) -> String {
        let minutes = max(1, Int((Double(plan.estimatedSeconds()) / 60).rounded()))
        return "~\(minutes) min"
    }

    private func exerciseSummary(_ plan: PremadePlan) -> String {
        plan.entries
            .map { entry in ExerciseRegistry.all.first { $0.id == entry.exerciseID }?.displayName ?? entry.exerciseID }
            .joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/PremadePlansView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: Plans tab listing premade workouts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Rest countdown view

**Files:**
- Create: `CrazyWork/Sources/Views/RestCountdownView.swift`

No unit test (timer/UI); verified by build here and wired in Task 5.

- [ ] **Step 1: Implement the view**

Create `CrazyWork/Sources/Views/RestCountdownView.swift`:

```swift
import SwiftUI

/// The rest period between sets: a self-driving countdown that advances to the
/// next set at zero, with a button to skip the remaining wait. `onAdvance` is
/// the coordinator's `beginNextSet` (idempotent — only acts while resting), so a
/// skip-and-timeout race is harmless.
struct RestCountdownView: View {
    let seconds: Int
    let nextExercise: String
    let onAdvance: () -> Void

    @State private var remaining: Int

    init(seconds: Int, nextExercise: String, onAdvance: @escaping () -> Void) {
        self.seconds = seconds
        self.nextExercise = nextExercise
        self.onAdvance = onAdvance
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Rest").font(.largeTitle.bold()).foregroundStyle(.white)
            Text(LiveWorkoutView.clock(Double(remaining)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("Next: \(nextExercise)").foregroundStyle(.white.opacity(0.8))
            Button("Skip rest") { onAdvance() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            onAdvance()
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` (`LiveWorkoutView.clock(_:)` is an existing `static func`).

- [ ] **Step 3: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/RestCountdownView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: self-driving RestCountdownView with skip

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: TabView root + binding-driven builder + rest stepper

**Files:**
- Create: `CrazyWork/Sources/Views/RootView.swift`
- Modify: `CrazyWork/Sources/App/CrazyWorkApp.swift`
- Modify: `CrazyWork/Sources/Views/BuildWorkoutView.swift`

- [ ] **Step 1: Create the TabView root**

Create `CrazyWork/Sources/Views/RootView.swift`:

```swift
import SwiftUI

/// App root: tabs for building/running a workout, browsing premade plans, and
/// viewing history. Owns the editable workout draft (`entries` + `restSeconds`)
/// shared by the first two tabs.
struct RootView: View {
    @State private var entries: [WorkoutEntry] = []
    @State private var restSeconds: Int = 30
    @State private var selection: Tab = .workout

    private enum Tab { case workout, plans, history }

    var body: some View {
        TabView(selection: $selection) {
            BuildWorkoutView(entries: $entries, restSeconds: $restSeconds)
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)

            PremadePlansView { plan in
                entries = plan.entries
                restSeconds = plan.restSeconds
                selection = .workout
            }
            .tabItem { Label("Plans", systemImage: "list.bullet.rectangle") }
            .tag(Tab.plans)

            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
    }
}
```

- [ ] **Step 2: Point the app at `RootView`**

In `CrazyWork/Sources/App/CrazyWorkApp.swift`, change the `WindowGroup` content from `BuildWorkoutView()` to `RootView()`:

```swift
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self])
```

- [ ] **Step 3: Make the builder binding-driven and add the rest stepper**

In `CrazyWork/Sources/Views/BuildWorkoutView.swift`:

Replace the stored-state declaration:
```swift
    @State private var entries: [WorkoutEntry] = []
```
with bindings:
```swift
    @Binding var entries: [WorkoutEntry]
    @Binding var restSeconds: Int
```

Add a rest section inside the `List`, immediately AFTER the `Section("Your workout") { … }` block:
```swift
                Section("Rest between sets") {
                    Stepper("Rest: \(restSeconds)s", value: $restSeconds, in: 0...180, step: 5)
                }
```

Remove the History toolbar link — delete this entire modifier:
```swift
            .toolbar {
                NavigationLink("History") { HistoryView() }
            }
```

Leave the `.safeAreaInset` Start button as-is for now (it still calls `LiveWorkoutView(plan: WorkoutPlan.expand(entries))`; rest is wired into the live view in Task 5).

- [ ] **Step 4: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the test suite (nothing regressed)**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild test -scheme CrazyWork \
  -destination 'platform=iOS Simulator,name=iPhone 17' -project CrazyWork.xcodeproj \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/RootView.swift \
        CrazyWork/Sources/App/CrazyWorkApp.swift CrazyWork/Sources/Views/BuildWorkoutView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: TabView root with shared draft; builder rest stepper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Wire timed rest into the live workout

**Files:**
- Modify: `CrazyWork/Sources/Views/LiveWorkoutView.swift`
- Modify: `CrazyWork/Sources/Views/BuildWorkoutView.swift`

- [ ] **Step 1: Give `LiveWorkoutView` a `restSeconds` and use the countdown**

In `CrazyWork/Sources/Views/LiveWorkoutView.swift`:

Add a stored property next to `let plan: [PlannedSet]`:
```swift
    let restSeconds: Int
```

Replace the initializer:
```swift
    init(plan: [PlannedSet]) {
        self.plan = plan
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }
```
with:
```swift
    init(plan: [PlannedSet], restSeconds: Int) {
        self.plan = plan
        self.restSeconds = restSeconds
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }
```

In the `body`, replace the `.resting` case:
```swift
                    case .resting:
                        Spacer()
                        restView
                        Spacer()
```
with the self-driving countdown (a fresh instance per rest via `.id`):
```swift
                    case .resting:
                        Spacer()
                        RestCountdownView(seconds: restSeconds, nextExercise: exerciseName) {
                            coordinator.beginNextSet()
                        }
                        .id(coordinator.currentSetIndex)
                        Spacer()
```

Delete the now-unused `restView` computed property:
```swift
    private var restView: some View {
        VStack(spacing: 12) {
            Text("Rest").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Next: \(exerciseName)").foregroundStyle(.white.opacity(0.8))
            Button("Start next set") { coordinator.beginNextSet() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
```

- [ ] **Step 2: Pass `restSeconds` from the builder's Start button**

In `CrazyWork/Sources/Views/BuildWorkoutView.swift`, update the `.safeAreaInset` Start `NavigationLink` destination from:
```swift
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(entries))
                } label: {
```
to:
```swift
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(entries), restSeconds: restSeconds)
                } label: {
```

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/LiveWorkoutView.swift CrazyWork/Sources/Views/BuildWorkoutView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: auto-counting rest between sets in the live workout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run engine + app test suites**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -2
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: engine all pass; app `** TEST SUCCEEDED **`.

- [ ] **Step 2: Manual device/simulator checklist (note for the user)**

Confirm: three tabs (Workout / Plans / History); each Plans card shows a name, "~N min", description, and exercise summary; tapping a plan fills the builder and switches to the Workout tab; the "Rest between sets" stepper adjusts 0–180s; during a multi-set workout the rest screen counts down and auto-starts the next set at zero; "Skip rest" starts it immediately; the rest beep + "Rest. Next up: …" audio still plays; History still lists past sessions.

- [ ] **Step 3: Push**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git push
```

---

## Self-Review Notes

- **Spec coverage:** TabView root + shared draft (Task 4); History as a tab (Task 4); binding-driven builder + rest stepper (Task 4); `RestCountdownView` auto-advance + Skip (Tasks 3, 5); `LiveWorkoutView(plan:restSeconds:)` (Task 5); `PremadePlan`/catalog/`estimatedSeconds` (Task 1); `PremadePlansView` cards + load-into-builder (Tasks 2, 4); tests for estimate + catalog invariants (Task 1). All spec sections map to a task.
- **Build stays green at every task boundary:** Tasks 1-3 add unreferenced files; Task 4 flips the root and builder together (the Start button still uses the old `LiveWorkoutView(plan:)` initializer until Task 5); Task 5 changes the initializer and its one call site in the same commit.
- **Type consistency:** `PremadePlan(id:name:summary:entries:restSeconds:)`, `estimatedSeconds(secondsPerRep:)`, `PremadePlanCatalog.all`, `BuildWorkoutView(entries:restSeconds:)`, `LiveWorkoutView(plan:restSeconds:)`, and `RestCountdownView(seconds:nextExercise:onAdvance:)` are used identically across tasks.
- **Idempotent advance:** `coordinator.beginNextSet()` already guards `phase == .resting`, so the timeout/skip race in `RestCountdownView` is safe.
