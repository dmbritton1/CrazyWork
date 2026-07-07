# Galaxy Background Excitement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shooting stars, a near bokeh layer, and breathing nebulae to the Today-tab galaxy background, per `docs/superpowers/specs/2026-07-06-galaxy-background-excitement-design.md`.

**Architecture:** `GalaxyBackground` moves out of `PathView.swift` into its own file. All three features stay deterministic and stateless: meteors are hash-scheduled slots evaluated from wall-clock time inside the existing 30 fps `Canvas`; bokeh is a fourth entry in the existing `layers` table rendered with a radial-gradient fill; nebula breathing rides a new low-rate (8 fps) `TimelineView`. No new `@State`, no Canvas filters, no new dependencies.

**Tech Stack:** SwiftUI (Canvas, TimelineView), XCTest. iOS app built with Xcode.

## Global Constraints

- **No linework in the sky** — the trail ribbon is the only line on the canvas. Meteors are chains of dots, never a stroked path.
- **Reduce Motion freezes everything** — `paused == true` means: no meteors, no bokeh wobble, no nebula breathe. (`drift` is already 0 at the call site under Reduce Motion.)
- **Deterministic, stateless rendering** — all variation comes from the existing `rand(_:_:_:)` hash or wall-clock `t`; no stored state.
- **Build products must NOT go inside the repo** — the repo lives on iCloud Desktop, which breaks codesign. Always pass the DerivedData path below.
- Build/test from `/Users/dwightbritton/Desktop/CrazyWork/CrazyWork` with:
  ```bash
  DD=/private/tmp/claude-501/-Users-dwightbritton-Desktop-CrazyWork/846804a8-b371-456d-a224-3afea0976f4e/scratchpad/dd
  SIM=E73E73DA-FAB9-4627-A7DE-E80171F56992   # iPhone 17 Pro
  xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" build
  ```
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Move GalaxyBackground to its own file

**Files:**
- Create: `CrazyWork/Sources/Views/GalaxyBackground.swift`
- Modify: `CrazyWork/Sources/Views/PathView.swift` (delete the `GalaxyBackground` struct)

**Interfaces:**
- Consumes: `Palette` colors (existing).
- Produces: `struct GalaxyBackground: View` at **internal** access (was `private`), initializer `GalaxyBackground(drift: CGFloat, energy: CGFloat, paused: Bool)`. Later tasks add to this file; tests reach it via `@testable import CrazyWork`.

- [ ] **Step 1: Create `CrazyWork/Sources/Views/GalaxyBackground.swift`**

Copy the entire `GalaxyBackground` struct out of `PathView.swift` (it starts at the doc comment `/// A deep-space field behind the trail:` and ends at the closing brace before `/// Tapping a path node pops a speech bubble`). The ONLY changes: add the `import SwiftUI` header and drop the `private` keyword from the struct declaration.

```swift
import SwiftUI

/// A deep-space field behind the trail: three star layers at different
/// parallax depths over two barely-there nebula washes. Stars twinkle gently
/// when idle; `energy` (scroll velocity) raises both the number of twinkling
/// stars and their luminosity, so flinging the page makes the sky flare.
/// No linework — the trail ribbon stays the only line on the canvas.
struct GalaxyBackground: View {
    var drift: CGFloat     // scroll offset, for parallax
    var energy: CGFloat    // 0…1 scroll excitement
    var paused: Bool       // Reduce Motion: static sky
    @Environment(\.colorScheme) private var scheme
    /// Ink-tone washes sit on white far louder than on near-black.
    private var nebulaDim: Double { scheme == .dark ? 1 : 0.35 }

    private struct Layer { let count: Int; let parallax: CGFloat
                           let size: ClosedRange<CGFloat>; let alpha: CGFloat }
    private let layers: [Layer] = [
        Layer(count: 48, parallax: 0.10, size: 0.7...1.3, alpha: 0.20),   // far
        Layer(count: 36, parallax: 0.24, size: 0.9...1.8, alpha: 0.32),   // mid
        Layer(count: 24, parallax: 0.44, size: 1.3...2.4, alpha: 0.48),   // near
    ]

    var body: some View {
        ZStack {
            nebula
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let period = size.height + 120   // wrap zone kept offscreen
                    for (li, layer) in layers.enumerated() {
                        for i in 0..<layer.count {
                            let x = rand(li, i, 0) * size.width
                            var y = (rand(li, i, 1) * period - drift * layer.parallax)
                                .truncatingRemainder(dividingBy: period)
                            if y < 0 { y += period }
                            y -= 60
                            let r = layer.size.lowerBound
                                  + (layer.size.upperBound - layer.size.lowerBound) * rand(li, i, 2)
                            // Twinkle: idle, ~1/4 of stars pulse softly; energy
                            // recruits more of them and deepens the pulse.
                            let twinkles = rand(li, i, 3) < 0.25 + 0.55 * Double(energy)
                            let amp = twinkles && !paused ? 0.35 + 0.5 * Double(energy) : 0
                            let pulse = 1 + amp * sin(t * (0.8 + 1.6 * rand(li, i, 4))
                                                      + rand(li, i, 5) * 2 * .pi)
                            let alpha = min(1, Double(layer.alpha)
                                               * (0.7 + 0.6 * rand(li, i, 6))
                                               * pulse * (1 + 0.35 * Double(energy)))
                            let tint = rand(li, i, 7)
                            let color: Color = tint < 0.05 ? Palette.accentRedBright
                                             : tint < 0.10 ? Palette.accentAquaBright
                                             : Palette.ink
                            let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)
                            if r > 2 {   // biggest stars get a faint halo
                                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r, dy: -r)),
                                         with: .color(color.opacity(alpha * 0.15)))
                            }
                            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Two vast, near-invisible color washes at infinite distance — warm
    /// maroon high left, the page's single teal counterpoint low right.
    private var nebula: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.accentRedInk.opacity(0.18 * nebulaDim), .clear],
                                         center: .center, startRadius: 0, endRadius: 330))
                    .frame(width: 660, height: 660)
                    .position(x: geo.size.width * 0.18, y: geo.size.height * 0.28)
                Circle()
                    .fill(RadialGradient(colors: [Palette.accentTealInk.opacity(0.14 * nebulaDim), .clear],
                                         center: .center, startRadius: 0, endRadius: 300))
                    .frame(width: 600, height: 600)
                    .position(x: geo.size.width * 0.88, y: geo.size.height * 0.78)
            }
        }
    }

    /// Deterministic pseudo-random in [0, 1) seeded by (layer, star, channel),
    /// so the sky is stable frame to frame with no stored state.
    private func rand(_ layer: Int, _ star: Int, _ channel: Int) -> Double {
        let n = sin(Double(layer * 7919 + star * 104729 + channel * 1301) * 12.9898) * 43758.5453
        return n - n.rounded(.down)
    }
}
```

- [ ] **Step 2: Delete the struct from `PathView.swift`**

In `CrazyWork/Sources/Views/PathView.swift`, delete from the line `/// A deep-space field behind the trail: three star layers at different` down to (and including) the struct's closing brace — the line `}` immediately before the comment `/// Tapping a path node pops a speech bubble above the circle:`. Nothing else in the file changes; `PathView.body` keeps calling `GalaxyBackground(drift:energy:paused:)` unchanged.

- [ ] **Step 3: Build**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork
DD=/private/tmp/claude-501/-Users-dwightbritton-Desktop-CrazyWork/846804a8-b371-456d-a224-3afea0976f4e/scratchpad/dd
xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork \
  -destination "platform=iOS Simulator,id=E73E73DA-FAB9-4627-A7DE-E80171F56992" \
  -derivedDataPath "$DD" build 2>&1 | grep -E "error|BUILD"
```
Expected: `** BUILD SUCCEEDED **`. If the error is `cannot find 'GalaxyBackground' in scope`, the new file isn't in the target — run `xcodegen generate` at the repo root (there's a `project.yml`) and build again.

- [ ] **Step 4: Run the full test suite (move must not break anything)**

```bash
xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork \
  -destination "platform=iOS Simulator,id=E73E73DA-FAB9-4627-A7DE-E80171F56992" \
  -derivedDataPath "$DD" test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/GalaxyBackground.swift CrazyWork/Sources/Views/PathView.swift
git commit -m "refactor: move GalaxyBackground into its own file

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `meteorPhase` scheduling helper (TDD)

**Files:**
- Modify: `CrazyWork/Sources/Views/GalaxyBackground.swift`
- Test: `CrazyWork/Tests/GalaxyBackgroundTests.swift` (create)

**Interfaces:**
- Produces: `nonisolated static func meteorPhase(t: TimeInterval, period: Double, duration: Double) -> Double?` on `GalaxyBackground` — nil when the slot is dormant, else life phase in [0, 1). Task 3 calls it from the Canvas closure.

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/GalaxyBackgroundTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class GalaxyBackgroundTests: XCTestCase {
    func testPhaseInsideFiringWindow() {
        let τ = GalaxyBackground.meteorPhase(t: 0.3, period: 20, duration: 0.6)
        XCTAssertNotNil(τ)
        XCTAssertEqual(τ!, 0.5, accuracy: 1e-9)
    }

    func testDormantOutsideFiringWindow() {
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 0.6, period: 20, duration: 0.6))
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 10, period: 20, duration: 0.6))
        XCTAssertNil(GalaxyBackground.meteorPhase(t: 19.99, period: 20, duration: 0.6))
    }

    func testPeriodicAcrossCycles() {
        let a = GalaxyBackground.meteorPhase(t: 0.42, period: 20, duration: 0.6)
        let b = GalaxyBackground.meteorPhase(t: 20.42, period: 20, duration: 0.6)
        XCTAssertEqual(a!, b!, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork \
  -destination "platform=iOS Simulator,id=E73E73DA-FAB9-4627-A7DE-E80171F56992" \
  -derivedDataPath "$DD" -only-testing:CrazyWorkTests/GalaxyBackgroundTests test 2>&1 | tail -5
```
Expected: FAIL to build with `type 'GalaxyBackground' has no member 'meteorPhase'`.

- [ ] **Step 3: Implement the helper**

Add to `GalaxyBackground` (below the `rand` function):

```swift
    /// Meteor slot scheduling: each slot fires for `duration` seconds at the
    /// start of every `period`. Returns the life phase 0…1 while firing,
    /// nil while dormant — pure, so the Canvas stays stateless.
    nonisolated static func meteorPhase(t: TimeInterval, period: Double, duration: Double) -> Double? {
        let phase = t.truncatingRemainder(dividingBy: period) / duration
        return phase < 1 ? phase : nil
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`, 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/GalaxyBackground.swift CrazyWork/Tests/GalaxyBackgroundTests.swift
git commit -m "feat: meteor slot scheduling helper for the galaxy background

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Shooting stars

**Files:**
- Modify: `CrazyWork/Sources/Views/GalaxyBackground.swift` (Canvas closure)

**Interfaces:**
- Consumes: `meteorPhase(t:period:duration:)` from Task 2; existing `rand(_:_:_:)`.
- Produces: visual only — no API.

- [ ] **Step 1: Add meteor drawing to the Canvas**

In the `Canvas { ctx, size in … }` closure, immediately AFTER the closing brace of the `for (li, layer) in layers.enumerated()` loop (still inside the Canvas closure), add:

```swift
                    // Shooting stars: five hash-scheduled slots. Three are
                    // always eligible; two more unlock while a fling keeps
                    // `energy` high, so hard scrolls can spark extras. A
                    // meteor is a chain of dots (never a stroked line), and
                    // everything derives from (slot, firing) hashes — no state.
                    if !paused {
                        for slot in 0..<5 {
                            guard slot < 3 || energy > 0.3 else { continue }
                            let period = 14 + rand(9, slot, 0) * 12         // 14…26 s
                            guard let life = Self.meteorPhase(t: t, period: period, duration: 0.6)
                            else { continue }
                            let firing = Int((t / period).rounded(.down))   // reseed each firing
                            let sx = rand(9 + slot, firing, 0) * size.width
                            let sy = rand(9 + slot, firing, 1) * size.height * 0.66
                            let dirX = rand(9 + slot, firing, 2) < 0.5 ? -0.8 : 0.8
                            let mag = hypot(dirX, 0.55)
                            let ux = dirX / mag, uy = 0.55 / mag
                            let travel = 180 + rand(9 + slot, firing, 3) * 80   // 180…260 pt
                            let head = CGPoint(x: sx + ux * travel * life,
                                               y: sy + uy * travel * life)
                            let color: Color = rand(9 + slot, firing, 4) < 0.2
                                             ? Palette.accentRedBright : Palette.ink
                            // Fade in and out over the life; flings brighten.
                            let envelope = sin(.pi * life) * (0.7 + 0.6 * Double(energy))
                            for seg in 0..<8 {
                                let f = Double(seg) / 7
                                let p = CGPoint(x: head.x - ux * 30 * f, y: head.y - uy * 30 * f)
                                let r = 2.2 - 1.8 * f
                                let alpha = envelope * (1 - f * 0.85)
                                let rect = CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)
                                if seg == 0 {   // halo on the head, like the biggest stars
                                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r, dy: -r)),
                                             with: .color(color.opacity(alpha * 0.15)))
                                }
                                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                            }
                        }
                    }
```

Note the star layers use `li` 0–2 as the first hash argument; meteors use `9 + slot` (9–13), so the two populations never share seeds.

- [ ] **Step 2: Build**

Same build command as Task 1 Step 3. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Eyeball with a temporarily fast cadence**

Meteors at 14–26 s cadence are too rare to catch in a screenshot. Temporarily change `let period = 14 + rand(9, slot, 0) * 12` to `let period = 3 + rand(9, slot, 0) * 2`, rebuild, install, launch, and take 4 screenshots ~2 s apart:

```bash
xcrun simctl install E73E73DA-FAB9-4627-A7DE-E80171F56992 "$DD/Build/Products/Debug-iphonesimulator/CrazyWork.app"
xcrun simctl launch E73E73DA-FAB9-4627-A7DE-E80171F56992 com.dmbritton.CrazyWork
for i in 1 2 3 4; do sleep 2; xcrun simctl io E73E73DA-FAB9-4627-A7DE-E80171F56992 screenshot "/tmp/meteor$i.png"; done
```
Expected: at least one screenshot shows a small bright streak (chain of dots with a glowing head) in the top two-thirds of the sky. Check it looks like light, not a drawn line.

- [ ] **Step 4: Restore the real cadence**

Change the period line back to `let period = 14 + rand(9, slot, 0) * 12`. Rebuild (expected: `** BUILD SUCCEEDED **`).

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/GalaxyBackground.swift
git commit -m "feat: shooting stars in the galaxy background

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Near bokeh layer

**Files:**
- Modify: `CrazyWork/Sources/Views/GalaxyBackground.swift` (`Layer` struct, `layers` table, Canvas star loop)

**Interfaces:**
- Consumes: existing `Layer`/`layers`/`rand`.
- Produces: visual only — no API.

- [ ] **Step 1: Add the `soft` flag and the bokeh row**

Replace the `Layer` struct and `layers` table with:

```swift
    private struct Layer { let count: Int; let parallax: CGFloat
                           let size: ClosedRange<CGFloat>; let alpha: CGFloat
                           var soft = false }
    private let layers: [Layer] = [
        Layer(count: 48, parallax: 0.10, size: 0.7...1.3, alpha: 0.20),   // far
        Layer(count: 36, parallax: 0.24, size: 0.9...1.8, alpha: 0.32),   // mid
        Layer(count: 24, parallax: 0.44, size: 1.3...2.4, alpha: 0.48),   // near
        // So close it's out of focus: a handful of big soft dots drifting
        // fastest of all — the "bokeh" plane in front of the stars.
        Layer(count: 8, parallax: 0.62, size: 5...9, alpha: 0.13, soft: true),
    ]
```

- [ ] **Step 2: Render soft dots with a gradient fill**

In the star loop, the current body order is: compute `x`, `y`, `r`, then twinkle (`twinkles`/`amp`/`pulse`), then `alpha`, `tint`/`color`, then draw. Insert a soft branch right after `r` is computed — move the `tint`/`color` lines up into it as shown (they stay where they are for the hard-star path; Swift allows the duplicate `let` since the branch `continue`s):

```swift
                            if layer.soft {
                                // Out-of-focus dot: a radial gradient fakes the
                                // blur (no Canvas filter), and a slow wobble
                                // replaces the twinkle.
                                let tint = rand(li, i, 7)
                                let color: Color = tint < 0.05 ? Palette.accentRedBright
                                                 : tint < 0.10 ? Palette.accentAquaBright
                                                 : Palette.ink
                                let wobble = paused ? 1 : 1 + 0.2 * sin(t * 0.25 + rand(li, i, 4) * 2 * .pi)
                                let alpha = Double(layer.alpha) * (0.7 + 0.6 * rand(li, i, 6)) * wobble
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2,
                                                                width: r, height: r)),
                                         with: .radialGradient(
                                            Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                            center: CGPoint(x: x, y: y),
                                            startRadius: 0, endRadius: r / 2))
                                continue
                            }
```

- [ ] **Step 3: Build, install, screenshot**

Build (Task 1 Step 3 command), install + relaunch + screenshot (Task 3 Step 3 commands, one screenshot is enough). Expected: a few large, soft, faint round glows over the sky; scrolling the trail in the simulator moves them faster than the crisp stars. They must not read as UI elements — if they're too loud, this is the `alpha: 0.13` knob, but ship the spec value first.

- [ ] **Step 4: Run the test suite**

Task 1 Step 4 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Views/GalaxyBackground.swift
git commit -m "feat: near bokeh layer in the galaxy background

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Breathing nebulae

**Files:**
- Modify: `CrazyWork/Sources/Views/GalaxyBackground.swift` (`nebula` view)

**Interfaces:**
- Consumes: existing `drift`, `paused`, `nebulaDim`.
- Produces: visual only — no API.

- [ ] **Step 1: Replace the `nebula` view**

Replace the entire `private var nebula: some View { … }` with:

```swift
    /// Two vast, near-invisible color washes at infinite distance — warm
    /// maroon high left, the page's single teal counterpoint low right.
    /// They breathe on slow, offset cycles (scale ±5%, opacity ±6%) and
    /// drift with scroll slower than the farthest stars, so they read as
    /// alive but infinitely far. 8 fps is plenty for 20-second cycles.
    private var nebula: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: paused)) { timeline in
            let t = paused ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Palette.accentRedInk.opacity(
                                0.18 * nebulaDim * (1 + 0.06 * sin(t / 17 * 2 * .pi))), .clear],
                            center: .center, startRadius: 0, endRadius: 330))
                        .frame(width: 660, height: 660)
                        .scaleEffect(1 + 0.05 * sin(t / 22 * 2 * .pi))
                        .position(x: geo.size.width * 0.18, y: geo.size.height * 0.28)
                    Circle()
                        .fill(RadialGradient(
                            colors: [Palette.accentTealInk.opacity(
                                0.14 * nebulaDim * (1 + 0.06 * sin(t / 17 * 2 * .pi + 2.1))), .clear],
                            center: .center, startRadius: 0, endRadius: 300))
                        .frame(width: 600, height: 600)
                        .scaleEffect(1 + 0.05 * sin(t / 22 * 2 * .pi + 3.7))
                        .position(x: geo.size.width * 0.88, y: geo.size.height * 0.78)
                }
            }
        }
        .offset(y: -drift * 0.05)   // parallax: slower than the farthest stars
    }
```

- [ ] **Step 2: Build, install, verify the breathe**

Build, install, relaunch (same commands as before). Take two screenshots ~8 s apart:

```bash
xcrun simctl io E73E73DA-FAB9-4627-A7DE-E80171F56992 screenshot /tmp/nebula1.png
sleep 8
xcrun simctl io E73E73DA-FAB9-4627-A7DE-E80171F56992 screenshot /tmp/nebula2.png
```
Expected: the maroon wash (upper left) and teal wash (lower right) differ subtly in size/intensity between the two shots. The effect should be barely perceptible in stills — that's correct; it's meant to be subliminal in motion.

- [ ] **Step 3: Run the full test suite**

Task 1 Step 4 command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Views/GalaxyBackground.swift
git commit -m "feat: breathing nebulae with scroll parallax

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] Full test suite green (Task 1 Step 4 command).
- [ ] In the simulator: fling the trail hard — the sky flares (existing) and, within a few flings, an extra/brighter meteor appears (new).
- [ ] Settings → Accessibility → Reduce Motion ON (`xcrun simctl spawn E73E73DA-FAB9-4627-A7DE-E80171F56992 defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`, then relaunch the app): sky fully static — no meteors, no wobble, no breathe. Turn it back off afterward.
