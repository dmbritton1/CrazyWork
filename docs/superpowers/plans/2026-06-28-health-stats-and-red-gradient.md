# Health Metrics View + Red Gradient Spread Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the body metrics pulled from Apple Health (weight/height/age/sex) in Profile and Stats, spread the red `HeroStripeBand` header onto every tab with subtle red accents, and move the Stats consistency heatmap up under the cards.

**Architecture:** One new self-gating `HealthMetricsCard` reused in Profile + Stats, loading the existing `HealthStore.body()`. Header bands and accent retints are edits to existing views and the shared `PillTab`. No persistence/logic changes.

**Tech Stack:** Swift 6, SwiftUI, HealthKit, XcodeGen, XCTest.

## Global Constraints

- iOS 18.0, `SWIFT_VERSION` 6.0, strict concurrency. XcodeGen: regenerate with `cd CrazyWork && xcodegen generate` after adding files.
- Everything routes through `Palette`/`Typography`/`Spacing`/`Radii` — no hardcoded hex/system fonts.
- Health metrics shown: weight, height, age, sex only — no new HealthKit reads beyond `HealthStore.body()`.
- Red header band goes on every tab (overrides DESIGN.md's once-per-page rule, per user).
- Build/test: `cd CrazyWork && xcodegen generate && xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build` (swap `build`→`test`). Strip font xattrs before a sim install if codesign complains: `xattr -cr <App.app>`.
- Reference spec: `docs/superpowers/specs/2026-06-28-health-stats-and-red-gradient-design.md`.

---

## File Structure

- `CrazyWork/Sources/Theme/Components/HealthMetricsCard.swift` — new gated Health metrics card + pure formatters (create).
- `CrazyWork/Tests/HealthMetricsCardTests.swift` — formatter tests (create).
- `CrazyWork/Sources/Theme/Components/PillTab.swift` — active state → red-tinted (modify).
- `CrazyWork/Sources/Views/StatsView.swift` — hero band, reorder (calendar up), insert Health card, red streak numbers (modify).
- `CrazyWork/Sources/Views/HistoryView.swift` — hero band header (modify).
- `CrazyWork/Sources/Views/ProfileView.swift` — hero band header, insert Health card, red streak number (modify).
- `CrazyWork/Sources/Views/PremadePlansView.swift` — hero band header (modify).

---

### Task 1: HealthMetricsCard + formatter tests

**Files:**
- Create: `CrazyWork/Sources/Theme/Components/HealthMetricsCard.swift`
- Test: `CrazyWork/Tests/HealthMetricsCardTests.swift`

**Interfaces:**
- Consumes: `BodyCharacteristics` (`weightKg/heightCm/ageYears/isMale`), `HealthStore.shared.body() async`.
- Produces: `struct HealthMetricsCard: View`; `HealthMetricsCard.weightText(_:)`, `.heightText(_:)`, `.sexText(_:)`.

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/HealthMetricsCardTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class HealthMetricsCardTests: XCTestCase {
    func testWeightText() {
        XCTAssertEqual(HealthMetricsCard.weightText(72.4), "72 kg")
        XCTAssertEqual(HealthMetricsCard.weightText(nil), "—")
    }
    func testHeightText() {
        XCTAssertEqual(HealthMetricsCard.heightText(178.6), "179 cm")
        XCTAssertEqual(HealthMetricsCard.heightText(nil), "—")
    }
    func testSexText() {
        XCTAssertEqual(HealthMetricsCard.sexText(true), "Male")
        XCTAssertEqual(HealthMetricsCard.sexText(false), "Female")
        XCTAssertEqual(HealthMetricsCard.sexText(nil), "—")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd CrazyWork && xcodegen generate && xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -15`
Expected: FAIL — `HealthMetricsCard` unresolved.

- [ ] **Step 3: Implement HealthMetricsCard**

Create `CrazyWork/Sources/Theme/Components/HealthMetricsCard.swift`:

```swift
import SwiftUI
import HealthKit

/// Shows the body metrics CrazyWork pulls from Apple Health (weight/height/age/sex).
/// Self-gating: renders nothing unless Health is connected and available.
struct HealthMetricsCard: View {
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false
    @State private var metrics: BodyCharacteristics?

    var body: some View {
        if healthSyncEnabled && HKHealthStore.isHealthDataAvailable() {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("FROM APPLE HEALTH").typography(Typography.bodySmStrong)
                    .foregroundStyle(Palette.mute)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.md) {
                    tile("Weight", Self.weightText(metrics?.weightKg))
                    tile("Height", Self.heightText(metrics?.heightCm))
                    tile("Age", metrics?.ageYears.map { "\($0)" } ?? "—")
                    tile("Sex", Self.sexText(metrics?.isMale))
                }
            }
            .card()
            .task { metrics = await HealthStore.shared.body() }
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).typography(Typography.headingXl).foregroundStyle(Palette.ink)
            Text(title).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func weightText(_ kg: Double?) -> String { kg.map { "\(Int($0.rounded())) kg" } ?? "—" }
    static func heightText(_ cm: Double?) -> String { cm.map { "\(Int($0.rounded())) cm" } ?? "—" }
    static func sexText(_ isMale: Bool?) -> String {
        switch isMale { case true: return "Male"; case false: return "Female"; default: return "—" }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the test command from Step 2. Expected: `HealthMetricsCardTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Theme/Components/HealthMetricsCard.swift CrazyWork/Tests/HealthMetricsCardTests.swift
git commit -m "feat(health): HealthMetricsCard showing pulled body metrics"
```

---

### Task 2: PillTab active → red-tinted

**Files:**
- Modify: `CrazyWork/Sources/Theme/Components/PillTab.swift`

**Interfaces:** Consumes `Palette.brandRedSoft`, `Palette.accentRedBright`.

- [ ] **Step 1: Retint the active state**

Replace the active fill/text in `PillTab.body`:

```swift
            Text(title).typography(Typography.bodySm)
                .foregroundStyle(isActive ? Palette.accentRedBright : Palette.body)
                .padding(.vertical, Spacing.xs).padding(.horizontal, Spacing.md)
                .background(isActive ? Palette.brandRedSoft : .clear)
                .clipShape(Capsule())
```

- [ ] **Step 2: Build**

Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Theme/Components/PillTab.swift
git commit -m "feat(ui): red-tinted active PillTab"
```

---

### Task 3: StatsView — hero band, heatmap up, Health card, red streaks

**Files:**
- Modify: `CrazyWork/Sources/Views/StatsView.swift`

**Interfaces:** Consumes `HeroStripeBand`, `HealthMetricsCard`, `Palette.brandRed`.

- [ ] **Step 1: Hide nav bar + hero band header**

In `StatsView.body`, replace `.navigationTitle("Stats")` with `.toolbar(.hidden, for: .navigationBar)`, and restructure so the band always shows above content/empty-state. Change `body` to:

```swift
    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HeroStripeBand {
                        Text("Stats").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    if sessions.isEmpty {
                        ContentUnavailableView("No workouts yet",
                                               systemImage: "chart.xyaxis.line",
                                               description: Text("Complete a workout to see your progress."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        body(stats)
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func body(_ stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            cards(stats)
            HealthMetricsCard()
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Consistency").typography(Typography.headingMd).foregroundStyle(Palette.ink)
                ConsistencyCalendarView(workoutDays: stats.workoutDays)
            }
            trends(stats)
        }
        .padding(.horizontal, Spacing.lg)
    }
```

(Delete the old `content(_:)` method — `body(_:)` replaces it. The band sits full-bleed at the top; the rest is inset with `.padding(.horizontal, Spacing.lg)`. Note the new `body(_:)` helper name does not clash with the `var body`.)

- [ ] **Step 2: Red streak numbers**

In `statCard`, color the streak values red by passing an accent flag. Replace `statCard` and its calls:

```swift
    private func cards(_ stats: ProgressStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            statCard("Workouts", "\(stats.totalWorkouts)", "figure.run")
            statCard("Current streak", "\(stats.currentStreak)d", "flame.fill", accent: true)
            statCard("Longest streak", "\(stats.longestStreak)d", "trophy.fill", accent: true)
            statCard("Total reps", "\(stats.totalReps)", "number")
            statCard("Hold time", Self.clock(stats.totalHoldSeconds), "timer")
            statCard("Active time", Self.duration(stats.totalActiveTime), "clock")
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: icon).typography(Typography.captionMd).foregroundStyle(Palette.mute)
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
        }
        .card(surface: Palette.surfaceElevated)
    }
```

- [ ] **Step 3: Build**

Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Views/StatsView.swift
git commit -m "feat(ui): Stats hero band, heatmap up, Health card, red streaks"
```

---

### Task 4: HistoryView — hero band header

**Files:**
- Modify: `CrazyWork/Sources/Views/HistoryView.swift`

**Interfaces:** Consumes `HeroStripeBand`.

- [ ] **Step 1: Add the band, hide nav bar**

Replace `HistoryView.body` so the band is the first scroll item and the nav bar is hidden:

```swift
    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HeroStripeBand {
                        Text("History").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    if sessions.isEmpty {
                        ContentUnavailableView("No history yet",
                                               systemImage: "clock.arrow.circlepath",
                                               description: Text("Finished workouts show up here."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(sessions) { session in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(session.startedAt, style: .date)
                                    .typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                                Text(summary(session))
                                    .typography(Typography.bodySm).foregroundStyle(Palette.mute)
                            }
                            .card()
                            .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
```

(Keep the existing `summary(_:)` method unchanged.)

- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/HistoryView.swift
git commit -m "feat(ui): History hero band header"
```

---

### Task 5: PremadePlansView — hero band header

**Files:**
- Modify: `CrazyWork/Sources/Views/PremadePlansView.swift`

**Interfaces:** Consumes `HeroStripeBand`.

- [ ] **Step 1: Wrap the title in a band**

In `PremadePlansView.body`, replace the plain title line:

```swift
                        Text("Plans").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                            .padding(.top, Spacing.sm)
```

with a band that spans full width (move it out of the horizontally-padded `LazyVStack` so it's full-bleed). Restructure the scroll content:

```swift
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        HeroStripeBand {
                            Text("Plans").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                        }
                        LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                            if !saved.isEmpty {
                                sectionHeader("MY WORKOUTS")
                                ForEach(saved) { workout in
                                    planCard(workout.asPlan, onDelete: { modelContext.delete(workout) })
                                }
                            }
                            sectionHeader("PLANS")
                            ForEach(PremadePlanCatalog.all) { plan in
                                planCard(plan, onDelete: nil)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.bottom, Spacing.lg)
                }
```

(Keep `.toolbar(.hidden, for: .navigationBar)`, `sectionHeader`, `planCard`, `card`, `timeText`, `exerciseSummary` unchanged.)

- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/PremadePlansView.swift
git commit -m "feat(ui): Plans hero band header"
```

---

### Task 6: ProfileView — hero band header, Health card, red streak

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:** Consumes `HeroStripeBand`, `HealthMetricsCard`, `Palette.brandRed`.

- [ ] **Step 1: Hero band header + hide nav bar**

In `ProfileView.body`, replace `.navigationTitle("Profile")` with `.toolbar(.hidden, for: .navigationBar)` and make the band the first item, full-bleed (outside the `.padding(Spacing.lg)`):

```swift
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HeroStripeBand {
                        Text("Profile").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerCard
                        settingsCard
                        if HKHealthStore.isHealthDataAvailable() { healthCard }
                        HealthMetricsCard()
                        poseOverlayCard
                    }
                    .padding(.horizontal, Spacing.lg)
                }
                .padding(.bottom, Spacing.lg)
            }
            .tint(Palette.brandRed)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if availableVoices.isEmpty { availableVoices = Self.loadVoices() } }
```

- [ ] **Step 2: Red Streak number**

In the `stat(_:_:)` helper, the header card uses it for both Workouts and Streak. Color only the Streak value red by adding an `accent` flag:

```swift
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TextField("Name", text: $displayName)
                .typography(Typography.headingMd).foregroundStyle(Palette.ink)
            HStack {
                stat("Workouts", "\(stats.totalWorkouts)")
                Spacer()
                stat("Streak", "\(stats.currentStreak)d", accent: true)
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
            Text(title).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
    }
```

- [ ] **Step 3: Build.** Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Full test sweep**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "Executed [0-9]+ tests, with 0|\*\* (TEST|BUILD)" | tail -4
```

Expected: `HealthMetricsCardTests` + existing tests pass; TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/ProfileView.swift
git commit -m "feat(ui): Profile hero band, Health metrics card, red streak"
```

---

## Self-Review

**Spec coverage:**
- HealthMetricsCard (weight/height/age/sex, gated, nil→"—") → Task 1. ✓
- Reused in Profile + Stats → Tasks 6 & 3. ✓
- Formatter tests → Task 1. ✓
- Hero band on every tab (Plans/Stats/History/Profile) → Tasks 3,4,5,6. ✓
- Subtle accents: PillTab red → Task 2; red streak/key numbers → Tasks 3 & 6. ✓
- Stats heatmap moved up (after cards, before trends) → Task 3. ✓
- No new HealthKit reads (reuses `HealthStore.body()`) → Task 1. ✓

**Placeholder scan:** none. Tasks 3–6 carry full replacement code for the changed view bodies.

**Type consistency:** `HealthMetricsCard()` no-arg init used in Tasks 3 & 6 matches Task 1. `weightText/heightText/sexText` static signatures match across Task 1 code + test. `HeroStripeBand { }` trailing-closure usage matches its existing definition. `statCard(_:_:_:accent:)` and `stat(_:_:accent:)` added-param calls match their definitions within Tasks 3 and 6. `body(_:)` private helper in Task 3 is distinct from `var body`.
