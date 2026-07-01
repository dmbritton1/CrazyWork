# Responsive Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small, cohesive motion pass — tactile press feedback, spring on key state changes, and subtle content ease-in — all from one shared vocabulary that respects Reduce Motion.

**Architecture:** A single `Motion` file defines three named curves + a Reduce-Motion gate and the reusable view modifiers (`pressScale`, `motion`, `appearTransition`). Press feel is added inside the shared button/card components so it propagates; springs and transitions are applied to a curated list of call sites.

**Tech Stack:** Swift, SwiftUI (iOS 18), XCTest. No new dependencies.

## Global Constraints

- iOS 18 min. SwiftUI. No third-party dependencies.
- **The project is XcodeGen-generated.** New files under `CrazyWork/Sources/` (app) and `CrazyWork/Tests/` (tests) are auto-included ONLY after `cd CrazyWork && xcodegen generate`. Do NOT hand-edit `project.pbxproj`; it and the whole `*.xcodeproj` are gitignored — never commit them. Commit only real source/test files.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Tests: XCTest in `CrazyWork/Tests/`, `@testable import CrazyWork`. The `CrazyWork` scheme already has `CrazyWorkTests` in its test action.
- **One vocabulary — no ad-hoc spring/animation literals at call sites.** Every animation references `Motion.*` and routes through `Motion.resolved(_:reduceMotion:)`.
- Motion values (refined & quick): press `.spring(response: 0.28, dampingFraction: 0.72)`, press scale `0.97`, state `.snappy(duration: 0.30)`, appear `.smooth(duration: 0.32)`, appear rise `8pt`.
- **Do NOT touch** `LiveWorkoutView.swift`, `RestCountdownView.swift`, `SummaryView.swift` — timing-critical.
- Tab-selection animation is out of scope: `RootView` uses a native `TabView`, which animates selection itself.
- `xcodebuild` is verbose — pipe through `xcbeautify` if present else `| tail -40`. Signals: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

---

## File Structure

- `CrazyWork/Sources/Theme/Motion.swift` (new) — vocabulary, gate, and all reusable modifiers.
- `CrazyWork/Tests/MotionTests.swift` (new) — `Motion.resolved` gate test.
- `CrazyWork/Sources/Theme/Components/Buttons.swift` (modify) — press-scale in shared `pill`, new `PressableButtonStyle`.
- `CrazyWork/Sources/Views/ProfileView.swift`, `PathView.swift`, `PremadePlansView.swift`, `StatsView.swift` (modify) — curated pressable cards, state springs, appear transitions.

---

## Task 1: Motion vocabulary + Reduce-Motion gate + modifiers

**Files:**
- Create: `CrazyWork/Sources/Theme/Motion.swift`
- Test: `CrazyWork/Tests/MotionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum Motion` with `static let press/state/appear: Animation` and `static func resolved(_ animation: Animation?, reduceMotion: Bool) -> Animation?`
  - `extension View { func pressScale(_ pressed: Bool) -> some View }`
  - `extension View { func motion<V: Equatable>(_ animation: Animation, value: V) -> some View }`
  - `extension View { func appearTransition() -> some View }`

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/MotionTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class MotionTests: XCTestCase {
    func testResolvedReturnsNilUnderReduceMotion() {
        XCTAssertNil(Motion.resolved(Motion.state, reduceMotion: true))
    }

    func testResolvedPassesAnimationWhenReduceMotionOff() {
        XCTAssertNotNil(Motion.resolved(Motion.state, reduceMotion: false))
    }

    func testResolvedNilInputStaysNil() {
        XCTAssertNil(Motion.resolved(nil, reduceMotion: false))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd CrazyWork && xcodegen generate && cd .. && xcodebuild test -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/MotionTests 2>&1 | tail -20`
Expected: FAIL — compile error, `Motion` not found.

- [ ] **Step 3: Write the implementation**

Create `CrazyWork/Sources/Theme/Motion.swift`:

```swift
import SwiftUI

/// The app's motion vocabulary — refined & quick. Every animation references
/// these curves and routes through `resolved` so it self-disables under
/// Reduce Motion. No ad-hoc spring literals at call sites.
enum Motion {
    static let press: Animation  = .spring(response: 0.28, dampingFraction: 0.72)
    static let state: Animation  = .snappy(duration: 0.30)
    static let appear: Animation = .smooth(duration: 0.32)

    /// Reduce-Motion gate: instant (nil) when the user prefers reduced motion.
    static func resolved(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Subtle tactile scale-down while pressed. Self-disables under Reduce Motion.
private struct PressScale: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduce ? 0.97 : 1)
            .animation(Motion.resolved(Motion.press, reduceMotion: reduce), value: pressed)
    }
}

/// Implicit animation bound to `value`, self-disabling under Reduce Motion.
private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduce), value: value)
    }
}

/// Fade + gentle rise as the view first appears, self-disabling under Reduce Motion.
private struct AppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                if reduce { shown = true }
                else { withAnimation(Motion.appear) { shown = true } }
            }
    }
}

extension View {
    func pressScale(_ pressed: Bool) -> some View { modifier(PressScale(pressed: pressed)) }
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
    func appearTransition() -> some View { modifier(AppearTransition()) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd CrazyWork && xcodegen generate && cd .. && xcodebuild test -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/MotionTests 2>&1 | tail -20`
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Theme/Motion.swift CrazyWork/Tests/MotionTests.swift
git commit -m "feat(motion): shared motion vocabulary + reduce-motion gate + modifiers"
```

---

## Task 2: Tactile press feedback in shared button components

**Files:**
- Modify: `CrazyWork/Sources/Theme/Components/Buttons.swift`

**Interfaces:**
- Consumes: `pressScale(_:)` (Task 1).
- Produces: `struct PressableButtonStyle: ButtonStyle` (for tappable cards, used in Task 3).

- [ ] **Step 1: Add press-scale to the shared `pill` helper and a `PressableButtonStyle`**

In `CrazyWork/Sources/Theme/Components/Buttons.swift`:

(a) Change the `pill` helper to take a `pressed` flag and apply `.pressScale`. Replace:

```swift
@MainActor
private func pill<C: View>(_ c: C, bg: Color, fg: Color) -> some View {
    c.typography(Typography.buttonMd).foregroundStyle(fg)
        .padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.lg)
        .frame(minHeight: 36).background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radii.md))
}
```

with:

```swift
@MainActor
private func pill<C: View>(_ c: C, bg: Color, fg: Color, pressed: Bool) -> some View {
    c.typography(Typography.buttonMd).foregroundStyle(fg)
        .padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.lg)
        .frame(minHeight: 36).background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radii.md))
        .pressScale(pressed)
}
```

(b) Pass `pressed: c.isPressed` from all five styles. Replace each `pill(...)` call to add the argument. The five updated `makeBody` bodies:

```swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.primaryPressed : Palette.primary, fg: Palette.onPrimary, pressed: c.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: .clear, fg: Palette.onDark, pressed: c.isPressed).opacity(c.isPressed ? 0.6 : 1)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: Palette.surfaceElevated, fg: Palette.onDark, pressed: c.isPressed).opacity(c.isPressed ? 0.85 : 1)
    }
}

struct SecondaryRedButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.brandRed.opacity(0.22) : Palette.brandRedSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentRedBright, pressed: c.isPressed)
    }
}

struct SecondaryAquaButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.accentAqua.opacity(0.22) : Palette.accentAquaSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentAquaBright, pressed: c.isPressed)
    }
}
```

(c) Add `PressableButtonStyle` at the end of the file (for tappable non-pill cards):

```swift
/// For tappable cards/rows: no chrome, just the shared tactile press scale.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.pressScale(c.isPressed)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`. (No new files, so no `xcodegen generate` needed.)

- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Theme/Components/Buttons.swift
git commit -m "feat(motion): tactile press scale on all buttons + PressableButtonStyle"
```

---

## Task 3: Pressable feedback on tappable cards (curated call sites)

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`, `PathView.swift`, `PremadePlansView.swift`

**Interfaces:**
- Consumes: `PressableButtonStyle` (Task 2).
- Produces: nothing.

Switch tappable cards from `.buttonStyle(.plain)` to `.buttonStyle(PressableButtonStyle())`.

- [ ] **Step 1: ProfileView Pro row**

In `CrazyWork/Sources/Views/ProfileView.swift`, in `proCard`, change:

```swift
        .buttonStyle(.plain)
        .disabled(store.isPro)
```

to:

```swift
        .buttonStyle(PressableButtonStyle())
        .disabled(store.isPro)
```

- [ ] **Step 2: PathView supplementary bonus rows**

In `CrazyWork/Sources/Views/PathView.swift`, in `supplementarySection`, the `NavigationLink`'s `.buttonStyle(.plain)` (the one wrapping the `.card()` bonus row) → `.buttonStyle(PressableButtonStyle())`:

```swift
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.lg)
```

- [ ] **Step 3: PathView node buttons**

In `CrazyWork/Sources/Views/PathView.swift`, in `nodeView`, the node `Button`'s `.buttonStyle(.plain)` → `.buttonStyle(PressableButtonStyle())`.

- [ ] **Step 4: PremadePlansView cards**

In `CrazyWork/Sources/Views/PremadePlansView.swift`, both `.buttonStyle(.plain)` occurrences (the plan card buttons/links) → `.buttonStyle(PressableButtonStyle())`.

- [ ] **Step 5: Build**

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add CrazyWork/Sources/Views/ProfileView.swift CrazyWork/Sources/Views/PathView.swift CrazyWork/Sources/Views/PremadePlansView.swift
git commit -m "feat(motion): tactile press feedback on tappable cards"
```

---

## Task 4: State-change springs (curated)

**Files:**
- Modify: `CrazyWork/Sources/Views/PathView.swift`, `ProfileView.swift`, `StatsView.swift`

**Interfaces:**
- Consumes: `motion(_:value:)` (Task 1).
- Produces: nothing.

Numbers use `.contentTransition(.numericText())` so digits roll; the change is driven by `.motion(Motion.state, value:)`.

- [ ] **Step 1: PathView streak counter**

In `CrazyWork/Sources/Views/PathView.swift`, `hero`, change:

```swift
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .typography(Typography.headingMd).foregroundStyle(Palette.ink)
```

to:

```swift
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .typography(Typography.headingMd).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                        .motion(Motion.state, value: streak)
```

- [ ] **Step 2: PathView node state transition**

In `CrazyWork/Sources/Views/PathView.swift`, `nodeView`, add a state-driven spring to the circle. After the `nodeCircle(state:day:)` call inside the node's `VStack`, attach `.motion(Motion.state, value: state)` so a node springs as it moves locked → today → done. Concretely, change:

```swift
                nodeCircle(state: state, day: day)
```

to:

```swift
                nodeCircle(state: state, day: day)
                    .motion(Motion.state, value: state)
```

- [ ] **Step 3: ProfileView stat numbers + Pro row flip**

In `CrazyWork/Sources/Views/ProfileView.swift`, `stat(...)`, change:

```swift
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
```

to:

```swift
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
                .contentTransition(.numericText())
                .motion(Motion.state, value: value)
```

Then, in `proCard`, add the flip spring on the label content — attach `.motion(Motion.state, value: store.isPro)` to the `HStack` inside the button's `label` (the one ending in `.card()`), so the "Upgrade to Pro" ⇄ "Pro member" swap animates. Concretely, change:

```swift
            .card()
        }
        .buttonStyle(PressableButtonStyle())
```

to:

```swift
            .card()
            .motion(Motion.state, value: store.isPro)
        }
        .buttonStyle(PressableButtonStyle())
```

- [ ] **Step 4: StatsView metric numbers**

In `CrazyWork/Sources/Views/StatsView.swift`, `statCard(...)`, change:

```swift
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
```

to:

```swift
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
                .contentTransition(.numericText())
                .motion(Motion.state, value: value)
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add CrazyWork/Sources/Views/PathView.swift CrazyWork/Sources/Views/ProfileView.swift CrazyWork/Sources/Views/StatsView.swift
git commit -m "feat(motion): spring state changes on streak, stats, nodes, pro row"
```

---

## Task 5: Content appear-transitions (curated browsing screens)

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`, `PathView.swift`, `PremadePlansView.swift`, `StatsView.swift`

**Interfaces:**
- Consumes: `appearTransition()` (Task 1).
- Produces: nothing.

Apply `.appearTransition()` to the main content cards/sections so they ease in. Apply it to the card containers, NOT to the `HeroStripeBand` hero (its red lines animate already) and NOT inside `ScrollView` row loops that could re-trigger noisily — one call per logical section.

- [ ] **Step 1: ProfileView cards**

In `CrazyWork/Sources/Views/ProfileView.swift`, in `body`, the inner settings `VStack` holds `proCard`, `headerCard`, `settingsCard`, etc. Add `.appearTransition()` to that inner `VStack` (the one with `.padding(.horizontal, Spacing.lg)`) so the card stack eases in as one group:

```swift
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        proCard
                        headerCard
                        settingsCard
                        if HKHealthStore.isHealthDataAvailable() { healthCard }
                        HealthMetricsCard()
                        poseOverlayCard
                    }
                    .padding(.horizontal, Spacing.lg)
                    .appearTransition()
```

- [ ] **Step 2: PathView supplementary section**

In `CrazyWork/Sources/Views/PathView.swift`, `supplementarySection`, add `.appearTransition()` after its `.padding(.horizontal, Spacing.lg)`:

```swift
        }
        .padding(.horizontal, Spacing.lg)
        .appearTransition()
    }
```

- [ ] **Step 3: PremadePlansView plan list**

In `CrazyWork/Sources/Views/PremadePlansView.swift`, attach `.appearTransition()` to the `LazyVStack` that groups the plan cards — i.e. after its trailing `.padding(.horizontal, Spacing.lg)`. Change:

```swift
                            ForEach(PremadePlanCatalog.all) { plan in
                                planCard(plan, onDelete: nil)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
```

to:

```swift
                            ForEach(PremadePlanCatalog.all) { plan in
                                planCard(plan, onDelete: nil)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .appearTransition()
                    }
```

- [ ] **Step 4: StatsView metric cards**

In `CrazyWork/Sources/Views/StatsView.swift`, attach `.appearTransition()` to the `statsContent` `VStack` — after its trailing `.padding(.horizontal, Spacing.lg)`. Change:

```swift
            trends(stats)
            HealthMetricsCard()
        }
        .padding(.horizontal, Spacing.lg)
    }
```

to:

```swift
            trends(stats)
            HealthMetricsCard()
        }
        .padding(.horizontal, Spacing.lg)
        .appearTransition()
    }
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual smoke test (simulator)**

Run the app on iPhone 17 Pro and verify:
1. Tap a button / the Pro row / a plan card → subtle scale-down + spring-back.
2. A number change (e.g. completing a path day updates the streak) rolls with `.numericText`.
3. Browsing screens (Today, Stats, Plans, Profile) ease their cards in.
4. Settings → Accessibility → **Reduce Motion ON** → repeat 1–3: everything is instant, no scale/spring/fade.

- [ ] **Step 7: Commit**

```bash
git add CrazyWork/Sources/Views/ProfileView.swift CrazyWork/Sources/Views/PathView.swift CrazyWork/Sources/Views/PremadePlansView.swift CrazyWork/Sources/Views/StatsView.swift
git commit -m "feat(motion): subtle appear-transitions on browsing screens"
```
