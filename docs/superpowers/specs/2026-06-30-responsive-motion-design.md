# Responsive Motion — Design Spec

**Date:** 2026-06-30
**Status:** Approved for planning
**Feel:** Refined & quick — tight springs, barely-there overshoot, iOS-system-like.

## Goal

Make the app feel more tactile and alive through a small, cohesive motion pass:
tactile press feedback on interactive elements, spring on key state changes, and
a subtle ease-in on browsing-screen content. All motion references one shared
vocabulary so it stays consistent, and all of it respects Reduce Motion.

## Principles

- **One vocabulary, referenced everywhere.** No ad-hoc `.spring(...)` literals at
  call sites — everything uses `Motion.*` curves.
- **Leverage over sweep.** The high-value press feel is added inside shared
  components (button styles, a pressable card style) so it propagates from ~2
  edits. Springs and transitions are applied to a *curated* list, not every view.
- **Restraint.** Refined, quick, subtle. Never bouncy or attention-grabbing.
- **Accessibility is not optional.** Every animation routes through a
  Reduce-Motion gate that returns instant (no animation) when the user has that
  setting on.

## Non-goals (YAGNI)

- No third-party animation library (Pow, etc.).
- No animating "everything" — state-springs/transitions are the curated set below.
- Do **not** touch the live-workout timing surfaces (`LiveWorkoutView`,
  `RestCountdownView`, `SummaryView` countdowns/audio-synced animations) — they
  have their own critical timing.
- No changes to native sheet/navigation transitions (already spring).

## Architecture

### 1. Motion vocabulary — `CrazyWork/Sources/Theme/Motion.swift` (new)

```swift
enum Motion {
    static let press: Animation  = .spring(response: 0.28, dampingFraction: 0.72) // tactile tap
    static let state: Animation  = .snappy(duration: 0.30)                        // value/state change
    static let appear: Animation = .smooth(duration: 0.32)                        // content ease-in

    /// Reduce-Motion gate. Pure so it's unit-testable.
    static func resolved(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
```

Plus two reduce-motion-aware View helpers in the same file:

```swift
extension View {
    /// Implicit animation that self-disables under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View { … }

    /// Subtle fade + rise as the view appears; self-disables under Reduce Motion.
    func appearTransition() -> some View { … }
}
```

- `motion(_:value:)` wraps `.animation(Motion.resolved(animation, reduceMotion:), value:)`,
  reading `@Environment(\.accessibilityReduceMotion)`.
- `appearTransition()` animates opacity 0→1 and offset y 8→0 with `Motion.appear`
  on first appear (an `@State private var shown` toggled in `.onAppear`), gated by
  Reduce Motion (when reduced: shown starts true, no animation).

### 2. Tactile press feedback (global via shared components)

**a. Pill buttons —** `CrazyWork/Sources/Theme/Components/Buttons.swift` (modify).
Add a subtle press-scale to the shared `pill(...)` helper so all five existing
styles gain it from one edit. The helper gains a `pressed: Bool` parameter and
applies, via a small reduce-motion-aware wrapper:
`.scaleEffect(pressed ? 0.97 : 1)` animated with `Motion.press`. Each
`makeBody` passes `pressed: c.isPressed`. No other change to the styles' existing
opacity/color press states.

**b. Pressable cards —** add `PressableButtonStyle` to `Buttons.swift`:

```swift
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .scaleEffect(c.isPressed ? 0.97 : 1)   // reduce-motion-gated internally
            .animation(…Motion.press…, value: c.isPressed)
    }
}
```

Tappable cards currently using `.buttonStyle(.plain)` switch to
`.buttonStyle(PressableButtonStyle())`. Both scale effects go through the same
reduce-motion gate (a shared private `PressScale` view or an inline
environment read) so the press disables cleanly.

### 3. State-change springs (curated — `Motion.state`)

Applied via `.motion(Motion.state, value:)` or `withAnimation(Motion.resolved(...))`:

- **Streak counter** — `PathView` hero `Text("\(streak) day…")` animates on change.
- **Stat numbers** — `ProfileView.stat(...)` (Workouts/Streak) and `StatsView`
  headline metrics animate on value change.
- **Path node state** — `PathView.nodeCircle` scale/color as a node moves
  locked → today → done.
- **Pro row flip** — `ProfileView.proCard` label/icon swap when `store.isPro`
  changes.
- **Tab selection** — `RootView` selected-tab indicator (if a custom tab bar;
  otherwise skip — native `TabView` already animates).

### 4. Content transitions (curated — `.appearTransition()`)

Applied to the main content sections/cards of the browsing screens only:

- `PathView` — hero + supplementary section (not the animated ribbon itself).
- `StatsView` — metric cards.
- `PremadePlansView` — plan cards.
- `ProfileView` — the settings/pro/header cards.

### 5. Accessibility gate

`Motion.resolved(_:reduceMotion:)` is the single chokepoint. The `motion(...)` and
`appearTransition()` modifiers and both press-scale paths read
`@Environment(\.accessibilityReduceMotion)` and pass it through `resolved`. Result:
Reduce Motion → every effect becomes instant, no partial states.

## Data flow

State/props change → the owning view's `.motion(Motion.state, value:)` (or a
`withAnimation` block) animates the change with the shared curve, unless Reduce
Motion is on, in which case `resolved` returns `nil` and the change is instant.
Press feedback is local to the button/card style and needs no external state.

## Error handling

Not applicable — this is presentation-only. The one correctness concern is
avoiding unintended implicit animations: use scoped `.motion(_:value:)` /
`.animation(_:value:)` bound to a specific value, never a blanket `.animation()`.

## Testing / verification

- **Unit test** (`MotionTests`): `Motion.resolved` — returns `nil` when
  `reduceMotion` is true, returns the passed animation when false. This is the one
  piece of real logic (the accessibility gate); keep it pure and dependency-free.
- **Manual smoke test** (simulator, iPhone 17 Pro):
  1. Tap the Pro row / a plan card / a primary button → visible subtle scale-down
     and spring-back.
  2. Trigger a state change (complete a path day, or watch a stat update) → springs
     in rather than snapping.
  3. Open a browsing screen → cards ease in.
  4. Settings → Accessibility → **Reduce Motion ON** → repeat 1–3: everything is
     instant, no scale/spring/fade.

## Files

- `CrazyWork/Sources/Theme/Motion.swift` (new) — vocabulary, `resolved`,
  `motion(_:value:)`, `appearTransition()`.
- `CrazyWork/Sources/Theme/Components/Buttons.swift` (modify) — press-scale in
  `pill`, new `PressableButtonStyle`.
- `CrazyWork/Sources/Views/PathView.swift` (modify) — streak, node state,
  pressable nodes/rows, appear transitions.
- `CrazyWork/Sources/Views/ProfileView.swift` (modify) — stat numbers, proCard
  flip + pressable, appear transitions.
- `CrazyWork/Sources/Views/StatsView.swift` (modify) — metric springs + appear.
- `CrazyWork/Sources/Views/PremadePlansView.swift` (modify) — pressable plan
  cards + appear.
- `CrazyWork/Sources/Views/HistoryView.swift`, `BuildWorkoutView.swift` (modify) —
  pressable rows where they use `.buttonStyle(.plain)` on cards.
- `CrazyWork/Tests/MotionTests.swift` (new) — `resolved` gate test.

## Deferred decisions

- Exact scale amount (0.97 vs 0.96) and spring response are tunable knobs; the
  spec's values are the starting point, adjusted by feel during the manual smoke
  test.
- Whether to extend appear-transitions to `HistoryView` lists (skipped initially —
  long lists animating in can feel busy; revisit after seeing the curated set).
