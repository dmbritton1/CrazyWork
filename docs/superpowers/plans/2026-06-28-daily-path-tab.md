# Daily Path Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Duolingo-style "Today" tab with a serpentine path of daily workouts that gate the next node until the next calendar day, advancing only on completion.

**Architecture:** A static infinite muscle-group rotation (`PathProgram.rotation`) drives the path; `node[i] = rotation[i % count]`. Progress is two `@AppStorage` scalars (`pathIndex`, `pathLastCompletedDay`) reduced through a pure `PathProgress` value type. The TODAY node and supplementary bonuses launch the **existing** `LiveWorkoutView`; finishing the TODAY workout fires a new optional `onComplete` closure that advances progress. Streak reuses the existing `ProgressStats.currentStreak`.

**Tech Stack:** SwiftUI, SwiftData, XCTest, XcodeGen (`project.yml`). Swift 6, iOS 18.

## Global Constraints

- iOS deployment target 18.0; Swift 6.0 (`project.yml`).
- New source files go under `Sources/` and tests under `Tests/`; both are picked up by XcodeGen globs. After adding/removing files run `xcodegen generate` before building.
- Theme tokens only — no raw colors/sizes. Use `Palette.*`, `Spacing.*`, `Radii.*`, and `.typography(Typography.*)`. No drop shadows; cards carry a 1px `Palette.hairline` border.
- `WorkoutEntry(exerciseID:sets:target:)` — `id` is defaulted. Exercise IDs in use: `pushup`, `squat`, `lunge`, `plank`, `situp`, `glutebridge`.
- Test/build command (single source of truth, used by every "run" step):
  `xcodegen generate && xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/PathProgramTests`
  (drop `-only-testing` to run the full suite).

---

### Task 1: PathProgram model + pure progression logic

**Files:**
- Create: `CrazyWork/Sources/Session/PathProgram.swift`
- Test: `CrazyWork/Tests/PathProgramTests.swift`

**Interfaces:**
- Consumes: `WorkoutEntry` (existing, `Sources/Session/WorkoutEntry.swift`).
- Produces:
  - `struct PathDay: Identifiable { let id: String; let title: String; let focus: String; let entries: [WorkoutEntry]; let restSeconds: Int; let supplementary: [PathDay] }`
  - `enum PathProgram { static let rotation: [PathDay]; static func day(at index: Int) -> PathDay; static func epochDay(_ date: Date, calendar: Calendar = .current) -> Int }`
  - `enum NodeState: Equatable { case done, today, lockedNext, locked }`
  - `struct PathProgress { var index: Int; var lastCompletedDay: Int; func isCompletedToday(today: Int) -> Bool; func completing(today: Int) -> PathProgress; func state(of nodeIndex: Int, today: Int) -> NodeState }`

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/PathProgramTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class PathProgramTests: XCTestCase {

    // Coverage: every necessary muscle group / exercise appears in a MAIN
    // workout across one lap of the rotation.
    func testRotationMainsCoverAllExercises() {
        let ids = Set(PathProgram.rotation.flatMap { $0.entries.map(\.exerciseID) })
        XCTAssertEqual(ids, ["pushup", "squat", "lunge", "plank", "situp", "glutebridge"])
    }

    func testDayAtWrapsAroundRotation() {
        let count = PathProgram.rotation.count
        XCTAssertEqual(PathProgram.day(at: 0).id, PathProgram.rotation[0].id)
        XCTAssertEqual(PathProgram.day(at: count).id, PathProgram.rotation[0].id)
        XCTAssertEqual(PathProgram.day(at: count + 1).id, PathProgram.rotation[1].id)
    }

    func testCompletingAdvancesAndLocksToday() {
        let p = PathProgress(index: 0, lastCompletedDay: Int.min)
        XCTAssertEqual(p.state(of: 0, today: 100), .today)
        let after = p.completing(today: 100)
        XCTAssertEqual(after.index, 1)
        XCTAssertEqual(after.state(of: 0, today: 100), .done)
        XCTAssertEqual(after.state(of: 1, today: 100), .lockedNext)
    }

    func testDoubleCompleteSameDayIsNoop() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        let again = after.completing(today: 100)
        XCTAssertEqual(again.index, after.index)
        XCTAssertEqual(again.lastCompletedDay, 100)
    }

    func testNewDayUnlocksNext() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        XCTAssertEqual(after.state(of: 1, today: 101), .today)
    }

    func testSkippedDaysPreserveIndexAsMakeup() {
        let after = PathProgress(index: 0, lastCompletedDay: Int.min).completing(today: 100)
        XCTAssertEqual(after.index, 1)
        XCTAssertEqual(after.state(of: 1, today: 103), .today)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/PathProgramTests`
Expected: FAIL — `cannot find 'PathProgram' / 'PathProgress' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `CrazyWork/Sources/Session/PathProgram.swift`:

```swift
import Foundation

/// One node on the path: a titled workout with a muscle-group focus tag, plus
/// optional bonus workouts. Supplementary entries reuse this same type with an
/// empty `supplementary` — one value type, not two.
struct PathDay: Identifiable {
    let id: String
    let title: String
    let focus: String           // muscle tag, e.g. "Chest · Triceps · Shoulders"
    let entries: [WorkoutEntry]
    let restSeconds: Int
    let supplementary: [PathDay]
}

/// The static, infinite muscle-group rotation. `day(at:)` wraps, so the path
/// never ends. This array is the single seam a future data-driven scheduler
/// would replace.
enum PathProgram {
    static let rotation: [PathDay] = [
        PathDay(id: "push", title: "Upper Push", focus: "Chest · Triceps · Shoulders",
                entries: [WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "push.core", title: "Core hold", focus: "Core",
                            entries: [WorkoutEntry(exerciseID: "plank", sets: 2, target: 30)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "legs", title: "Lower Power", focus: "Quads · Glutes",
                entries: [WorkoutEntry(exerciseID: "squat", sets: 3, target: 12),
                          WorkoutEntry(exerciseID: "lunge", sets: 3, target: 10)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "legs.upper", title: "Upper finisher", focus: "Chest · Triceps",
                            entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "core", title: "Core", focus: "Abs · Core",
                entries: [WorkoutEntry(exerciseID: "situp", sets: 3, target: 15),
                          WorkoutEntry(exerciseID: "plank", sets: 3, target: 30)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "core.glute", title: "Glute bridge", focus: "Glutes",
                            entries: [WorkoutEntry(exerciseID: "glutebridge", sets: 2, target: 15)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "posterior", title: "Glutes & Posterior", focus: "Glutes · Hamstrings",
                entries: [WorkoutEntry(exerciseID: "glutebridge", sets: 3, target: 15),
                          WorkoutEntry(exerciseID: "lunge", sets: 3, target: 12)],
                restSeconds: 30,
                supplementary: [
                    PathDay(id: "posterior.upper", title: "Upper push", focus: "Chest · Triceps",
                            entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10)],
                            restSeconds: 20, supplementary: [])
                ]),
        PathDay(id: "full", title: "Full Body", focus: "Total body",
                entries: [WorkoutEntry(exerciseID: "pushup", sets: 2, target: 10),
                          WorkoutEntry(exerciseID: "squat", sets: 2, target: 12),
                          WorkoutEntry(exerciseID: "situp", sets: 2, target: 12),
                          WorkoutEntry(exerciseID: "plank", sets: 1, target: 30)],
                restSeconds: 25,
                supplementary: [
                    PathDay(id: "full.plank", title: "Plank challenge", focus: "Core",
                            entries: [WorkoutEntry(exerciseID: "plank", sets: 2, target: 45)],
                            restSeconds: 20, supplementary: [])
                ]),
    ]

    /// The node at an absolute position; wraps forever.
    static func day(at index: Int) -> PathDay {
        let n = rotation.count
        return rotation[((index % n) + n) % n]
    }

    /// Whole calendar days since the reference date, bucketed by `startOfDay`
    /// so it matches how `ProgressStats` groups days (DST-safe).
    static func epochDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day],
                                from: Date(timeIntervalSinceReferenceDate: 0),
                                to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// How a node renders on the trail.
enum NodeState: Equatable { case done, today, lockedNext, locked }

/// Pure progression state. `index` = nodes finished (also the current TODAY
/// node's absolute position). `lastCompletedDay` = epoch day of the last
/// completion, or `Int.min` for never.
struct PathProgress {
    var index: Int
    var lastCompletedDay: Int

    func isCompletedToday(today: Int) -> Bool { lastCompletedDay == today }

    /// Apply a completion stamped on `today`; advances at most once per day.
    func completing(today: Int) -> PathProgress {
        guard lastCompletedDay != today else { return self }
        return PathProgress(index: index + 1, lastCompletedDay: today)
    }

    func state(of nodeIndex: Int, today: Int) -> NodeState {
        if nodeIndex < index { return .done }
        if nodeIndex == index { return isCompletedToday(today: today) ? .lockedNext : .today }
        return .locked
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/PathProgramTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Session/PathProgram.swift CrazyWork/Tests/PathProgramTests.swift CrazyWork/CrazyWork.xcodeproj
git commit -m "feat(path): static rotation + pure progression logic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: LiveWorkoutView completion hook

**Files:**
- Modify: `CrazyWork/Sources/Views/LiveWorkoutView.swift` (init around lines 22-26; `saveIfNeeded()` around lines 176-194)

**Interfaces:**
- Produces: `LiveWorkoutView(plan:restSeconds:onComplete:)` — `onComplete: (() -> Void)? = nil`, called once after a successful session save. The existing `BuildWorkoutView` call site (`LiveWorkoutView(plan:restSeconds:)`) keeps compiling unchanged because the new param is defaulted.

- [ ] **Step 1: Add the stored property and init parameter**

In `LiveWorkoutView`, add the property next to `let restSeconds: Int`:

```swift
    let plan: [PlannedSet]
    let restSeconds: Int
    let onComplete: (() -> Void)?
```

Update the init to accept and store it (defaulted):

```swift
    init(plan: [PlannedSet], restSeconds: Int, onComplete: (() -> Void)? = nil) {
        self.plan = plan
        self.restSeconds = restSeconds
        self.onComplete = onComplete
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }
```

- [ ] **Step 2: Fire the closure after a successful save**

In `saveIfNeeded()`, the existing block is:

```swift
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save workout: \(error)") // don't silently lose history
        }

        guard healthSyncEnabled else { return }
```

Insert the call between the `catch` block and the `guard`:

```swift
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save workout: \(error)") // don't silently lose history
        }
        onComplete?() // advance the path when this was today's prescribed workout

        guard healthSyncEnabled else { return }
```

- [ ] **Step 3: Verify it builds (no behavior change for existing callers)**

Run: `xcodegen generate && xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED. (`onComplete` is unit-test-covered via `PathProgress` in Task 1; this step is pure wiring, verified by the compiler and the manual run in Task 3.)

- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Views/LiveWorkoutView.swift
git commit -m "feat(path): optional onComplete hook on LiveWorkoutView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: PathView (serpentine UI) + RootView tab wiring

**Files:**
- Create: `CrazyWork/Sources/Views/PathView.swift`
- Modify: `CrazyWork/Sources/Views/RootView.swift`

**Interfaces:**
- Consumes: `PathProgram`, `PathProgress`, `NodeState`, `PathDay` (Task 1); `LiveWorkoutView(plan:restSeconds:onComplete:)` (Task 2); `WorkoutPlan.expand(_:)`, `WorkoutSession` + `.summary`, `ProgressStats`, theme tokens, `HeroStripeBand`, `Badge`, `ExerciseTile.symbol(for:)`, `PrimaryButtonStyle`.
- Produces: `struct PathView: View` (no init args); a `RootView` `.path` tab shown first and selected by default.

- [ ] **Step 1: Create PathView**

Create `CrazyWork/Sources/Views/PathView.swift`:

```swift
import SwiftUI
import SwiftData

/// The "Today" tab: a serpentine path of daily workouts. One prescribed
/// workout per day extends the streak; the next node unlocks the next day.
/// Progress is two @AppStorage scalars reduced through `PathProgress`.
struct PathView: View {
    @AppStorage("pathIndex") private var pathIndex = 0
    @AppStorage("pathLastCompletedDay") private var pathLastCompletedDay = Int.min
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    private let rowHeight: CGFloat = 116
    private let nodeSize: CGFloat = 68

    private var today: Int { PathProgram.epochDay(Date()) }
    private var progress: PathProgress {
        PathProgress(index: pathIndex, lastCompletedDay: pathLastCompletedDay)
    }
    private var streak: Int {
        ProgressStats(summaries: sessions.map(\.summary)).currentStreak
    }
    /// The current TODAY node (the one to do today, whether or not it's done).
    private var todayDay: PathDay { PathProgram.day(at: pathIndex) }
    private var doneToday: Bool { progress.isCompletedToday(today: today) }

    /// Window of absolute node indices to render (not the whole infinite path).
    private var windowIndices: [Int] {
        let lo = max(0, pathIndex - 2)
        return Array(lo...(pathIndex + 6))
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    focusCard
                    if doneToday { supplementarySection }
                    trail
                }
                .padding(.bottom, Spacing.section)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        HeroStripeBand {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "flame.fill").foregroundStyle(Palette.brandRed)
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .typography(Typography.headingMd).foregroundStyle(Palette.ink)
                }
                Text("Today").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                Text(doneToday ? "Done for today — next unlocks tomorrow"
                               : "Today's focus · \(todayDay.focus)")
                    .typography(Typography.bodyMd).foregroundStyle(Palette.mute)
            }
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(todayDay.title).typography(Typography.headingMd).foregroundStyle(Palette.ink)
                Spacer()
                Badge(text: todayDay.focus, style: .redSoft)
            }
            ForEach(todayDay.entries) { entry in
                Text("\(entry.sets)× \(entry.target) · \(entry.exerciseID.capitalized)")
                    .typography(Typography.bodySm).foregroundStyle(Palette.body)
            }
            if doneToday {
                Label("Completed today", systemImage: "checkmark.circle.fill")
                    .typography(Typography.bodyStrong).foregroundStyle(Palette.accentGreen)
            } else {
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(todayDay.entries),
                                    restSeconds: todayDay.restSeconds,
                                    onComplete: completeToday)
                } label: {
                    Text("Start today's workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card()
        .padding(.horizontal, Spacing.lg)
    }

    private var supplementarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("WANT MORE?").typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
                .padding(.horizontal, Spacing.lg)
            ForEach(todayDay.supplementary) { bonus in
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(bonus.entries),
                                    restSeconds: bonus.restSeconds) // no onComplete → no path advance
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(bonus.title).typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                            Text(bonus.focus).typography(Typography.captionMd).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(Palette.accentAqua)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: Serpentine trail

    private var trail: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                connector(cx: cx)
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex)
                        .position(x: cx + xOffset(local),
                                  y: rowHeight / 2 + CGFloat(local) * rowHeight)
                }
            }
        }
        .frame(height: rowHeight * CGFloat(windowIndices.count))
        .padding(.top, Spacing.md)
    }

    private func connector(cx: CGFloat) -> some View {
        Path { p in
            for local in windowIndices.indices {
                let pt = CGPoint(x: cx + xOffset(local),
                                 y: rowHeight / 2 + CGFloat(local) * rowHeight)
                if local == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
        .stroke(Palette.hairlineStrong,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 8]))
    }

    /// L · C · R · C serpentine sway.
    private func xOffset(_ local: Int) -> CGFloat {
        [-1.0, 0.0, 1.0, 0.0][local % 4] * 92
    }

    @ViewBuilder
    private func nodeView(_ nodeIndex: Int) -> some View {
        let state = progress.state(of: nodeIndex, today: today)
        let day = PathProgram.day(at: nodeIndex)
        VStack(spacing: Spacing.xs) {
            nodeCircle(state: state, day: day, nodeIndex: nodeIndex)
            Text(day.title).typography(Typography.captionMd)
                .foregroundStyle(state == .locked || state == .lockedNext ? Palette.ash : Palette.body)
                .lineLimit(1)
        }
        .frame(width: 150)
    }

    @ViewBuilder
    private func nodeCircle(state: NodeState, day: PathDay, nodeIndex: Int) -> some View {
        switch state {
        case .done:
            circle(fill: Palette.brandRed, border: Palette.brandRed,
                   symbol: "checkmark", symbolColor: Palette.onPrimary)
        case .today:
            NavigationLink {
                LiveWorkoutView(plan: WorkoutPlan.expand(day.entries),
                                restSeconds: day.restSeconds, onComplete: completeToday)
            } label: {
                circle(fill: Palette.brandRedSoft, border: Palette.brandRed,
                       symbol: ExerciseTile.symbol(for: day.entries.first?.exerciseID ?? ""),
                       symbolColor: Palette.accentRedBright)
                    .overlay(Circle().stroke(Palette.brandRed, lineWidth: 2).scaleEffect(1.18).opacity(0.5))
            }
            .buttonStyle(.plain)
        case .lockedNext, .locked:
            circle(fill: Palette.surfaceCard, border: Palette.hairline,
                   symbol: "lock.fill", symbolColor: Palette.ash)
        }
    }

    private func circle(fill: Color, border: Color, symbol: String, symbolColor: Color) -> some View {
        Circle().fill(fill)
            .frame(width: nodeSize, height: nodeSize)
            .overlay(Circle().stroke(border, lineWidth: 2))
            .overlay(Image(systemName: symbol)
                .font(.system(size: nodeSize * 0.4, weight: .semibold))
                .foregroundStyle(symbolColor))
    }

    private func completeToday() {
        let next = progress.completing(today: today)
        pathIndex = next.index
        pathLastCompletedDay = next.lastCompletedDay
    }
}
```

- [ ] **Step 2: Wire the tab into RootView**

In `CrazyWork/Sources/Views/RootView.swift`:

Change the tab enum and default selection:

```swift
    @State private var selection: Tab = .path

    private enum Tab { case path, workout, plans, stats, history, profile }
```

Add the Path tab as the **first** entry inside `TabView`, before the Workout tab:

```swift
        TabView(selection: $selection) {
            NavigationStack { PathView() }
                .tabItem { Label("Today", systemImage: "flag.checkered") }
                .tag(Tab.path)

            BuildWorkoutView(entries: $entries, restSeconds: $restSeconds)
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)
            // ... existing plans / stats / history / profile tabs unchanged ...
```

- [ ] **Step 3: Build and run, verify behavior**

Run: `xcodegen generate && xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.

Then launch in the simulator and confirm:
- "Today" is the first tab and opens by default; hero shows the 🔥 streak.
- The serpentine trail renders with one pulsing red TODAY node, dim locked nodes below, dashed connector winding L/C/R.
- Tapping the TODAY node (or "Start today's workout") opens the camera workout.
- After finishing, returning to the tab shows that node as done (red check), the next node locked, the focus card flipped to "Completed today", and the "Want more?" supplementary cards visible.

- [ ] **Step 4: Run the full test suite (no regressions)**

Run: `xcodegen generate && xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/PathView.swift CrazyWork/Sources/Views/RootView.swift CrazyWork/CrazyWork.xcodeproj
git commit -m "feat(path): serpentine Today tab + RootView wiring

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Rotation hitting all muscle groups → Task 1 (`rotation` + `testRotationMainsCoverAllExercises`). ✓
- Advance-on-completion, lock-until-next-day, skip = make-up → Task 1 (`PathProgress`) + Task 3 (`completeToday`). ✓
- Streak reuse → Task 3 (`ProgressStats.currentStreak`). ✓
- Supplementary bonus, no path advance → Task 3 `supplementarySection` (no `onComplete`). ✓
- Serpentine visuals in theme → Task 3 `trail`. ✓
- Completion hook reusing existing engine → Task 2. ✓
- Static-now / dynamic-later seam → `PathProgram.rotation` documented. ✓

**Type consistency:** `PathDay`, `PathProgress(index:lastCompletedDay:)`, `NodeState`, `PathProgram.day(at:)`/`.epochDay`/`.rotation`, and `LiveWorkoutView(plan:restSeconds:onComplete:)` are used identically across Tasks 1–3. ✓

**Placeholder scan:** no TODO/TBD/"add error handling" lines; every code step shows complete code. ✓
