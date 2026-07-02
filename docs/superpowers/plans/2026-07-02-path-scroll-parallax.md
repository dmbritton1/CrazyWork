# Path Scroll Parallax Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the drifting red glow on the Today path with two content-driven depth effects: a focal-plane depth-of-field on the nodes and parallax separation of the trail's echo strands.

**Architecture:** All changes live in `CrazyWork/Sources/Views/PathView.swift` plus one small test file. The node effect uses iOS 18's `.visualEffect` + `.scrollView` coordinate space (geometry-driven, no new state); the strand effect reuses the existing `scrollY` state. The focus math is a pure static function so it's unit-testable.

**Tech Stack:** SwiftUI (iOS 18), XCTest. Spec: `docs/superpowers/specs/2026-07-02-path-scroll-parallax-design.md`.

## Global Constraints

- Scope: `CrazyWork/Sources/Views/PathView.swift` + one new test file only.
- Reduce motion (`@Environment(\.accessibilityReduceMotion)`): nodes render scale 1.0 / opacity 1.0 / blur 0; strand offsets 0.
- `scrollY` and its `onScrollGeometryChange` capture stay (effect B needs them).
- All build/test commands run from `/Users/dwightbritton/Desktop/CrazyWork/CrazyWork` (the shell cwd does NOT persist between commands — prefix every command with `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork &&`).
- Build: `xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: same command with `test` instead of `build`.
- New files require `xcodegen generate` (run from the same dir) before building.
- SourceKit/LSP diagnostics in this environment are noise (no iOS SDK); xcodebuild output is the source of truth.

---

### Task 1: Remove the red glow

**Files:**
- Modify: `CrazyWork/Sources/Views/PathView.swift:46-80` (the `GeometryReader` glow layer in `body` and the `redGlow` computed property)

**Interfaces:**
- Consumes: nothing.
- Produces: `body` without the glow layer; `scrollY` state and the `onScrollGeometryChange` modifier remain untouched (Task 3 needs them).

- [ ] **Step 1: Delete the glow layer from `body`**

In `PathView.body`, delete this block (currently between `Palette.canvas.ignoresSafeArea()` and `ScrollView {`):

```swift
            GeometryReader { vp in
                redGlow
                    .position(x: vp.size.width / 2
                                + CGFloat(sin(Double(scrollY) / 150)) * vp.size.width * 0.34,
                              y: vp.size.height * 0.42
                                + CGFloat(sin(Double(scrollY) / 260)) * vp.size.height * 0.16)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
```

- [ ] **Step 2: Delete the `redGlow` property**

Delete this entire computed property (including its doc comment):

```swift
    /// A soft red gradient blur that rides along with the scroll and weaves
    /// side to side, drifting around the path behind the dots.
    private var redGlow: some View {
        RadialGradient(colors: [Palette.brandRed.opacity(0.5),
                                Palette.accentRedDeep.opacity(0.22), .clear],
                       center: .center, startRadius: 0, endRadius: 170)
            .frame(width: 340, height: 340)
            .blur(radius: 70)
    }
```

Do NOT remove `@State private var scrollY` or the `.onScrollGeometryChange` modifier — Task 3 uses them.

- [ ] **Step 3: Build to verify**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/PathView.swift && git commit -m "refactor(path): remove scroll-riding red glow"
```

---

### Task 2: Node depth-of-field

**Files:**
- Create: `CrazyWork/Tests/PathFocusTests.swift`
- Modify: `CrazyWork/Sources/Views/PathView.swift` (add `focusT` static func + `reduceMotion` env var; wrap `nodeView` in `.visualEffect` inside `trail`'s `ForEach`)

**Interfaces:**
- Consumes: `trail`'s `ForEach` over `windowIndices` (`nodeView(nodeIndex).position(points[local])`).
- Produces: `static func focusT(midY: CGFloat, viewportHeight: CGFloat) -> CGFloat` on `PathView` — 0 at viewport center, 1 at/beyond the top or bottom edge. Task 4 relies on the visual result only.

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/PathFocusTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class PathFocusTests: XCTestCase {
    func testCenterIsFullFocus() {
        XCTAssertEqual(PathView.focusT(midY: 400, viewportHeight: 800), 0)
    }

    func testEdgesAreFullDefocus() {
        XCTAssertEqual(PathView.focusT(midY: 0, viewportHeight: 800), 1)
        XCTAssertEqual(PathView.focusT(midY: 800, viewportHeight: 800), 1)
    }

    func testBeyondViewportClampsToOne() {
        XCTAssertEqual(PathView.focusT(midY: -300, viewportHeight: 800), 1)
        XCTAssertEqual(PathView.focusT(midY: 1200, viewportHeight: 800), 1)
    }

    func testMidwayIsHalf() {
        XCTAssertEqual(PathView.focusT(midY: 200, viewportHeight: 800), 0.5, accuracy: 0.001)
        XCTAssertEqual(PathView.focusT(midY: 600, viewportHeight: 800), 0.5, accuracy: 0.001)
    }

    func testZeroViewportIsSafe() {
        XCTAssertEqual(PathView.focusT(midY: 100, viewportHeight: 0), 0)
    }
}
```

- [ ] **Step 2: Regenerate project and run test to verify it fails**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CrazyWorkTests/PathFocusTests 2>&1 | tail -5`
Expected: FAIL — compile error, `type 'PathView' has no member 'focusT'`.

- [ ] **Step 3: Implement `focusT`**

Add to `PathView` (below `insideOffset`, before `nodeView`):

```swift
    /// Depth-of-field falloff: 0 when a node's midY sits at the viewport
    /// center, rising to 1 at the top/bottom edge (clamped beyond).
    static func focusT(midY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return 0 }
        let half = viewportHeight / 2
        return min(1, abs(midY - half) / half)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CrazyWorkTests/PathFocusTests 2>&1 | tail -5`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Wire the visual effect**

Add the environment var to `PathView`'s properties (next to the other `@State`/`@AppStorage` vars):

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

In `trail`, change the `ForEach` body from:

```swift
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex).position(points[local])
                }
```

to:

```swift
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex)
                        // Depth-of-field: the node nearest the viewport center
                        // is crisp and full-size; nodes recede toward the edges.
                        .visualEffect { [reduceMotion] content, proxy in
                            let t = reduceMotion ? 0 : Self.focusT(
                                midY: proxy.frame(in: .scrollView).midY,
                                viewportHeight: proxy.bounds(of: .scrollView)?.height ?? 0)
                            return content
                                .scaleEffect(1 - 0.16 * t)
                                .opacity(1 - 0.5 * t)
                                .blur(radius: 2.5 * t)
                        }
                        .position(points[local])
                }
```

Notes for the implementer:
- `proxy.frame(in: .scrollView)` is the node's frame relative to the scroll viewport; `proxy.bounds(of: .scrollView)` is the visible viewport rect (nil outside a scroll view → `focusT` gets 0 height → t = 0 → full focus, per spec).
- The `.visualEffect` goes BEFORE `.position` (it wraps the node; position places it).
- The `.today` node's internal `scaleEffect(1.1)` composes on top — leave it alone.

- [ ] **Step 6: Build to verify**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/PathView.swift CrazyWork/Tests/PathFocusTests.swift CrazyWork/CrazyWork.xcodeproj && git commit -m "feat(path): depth-of-field focus on path nodes"
```

---

### Task 3: Parallax trail strands

**Files:**
- Modify: `CrazyWork/Sources/Views/PathView.swift` (`trail`'s `flowLine` call site; `flowLine` signature + strand offsets)

**Interfaces:**
- Consumes: `scrollY` (`@State`, already fed by `onScrollGeometryChange`), `reduceMotion` (added in Task 2).
- Produces: `flowLine(height:cx:amp:drift:)` — `drift` is the scroll offset (0 under reduce motion).

- [ ] **Step 1: Pass scroll drift into `flowLine`**

In `trail`, change:

```swift
                flowLine(height: height, cx: cx, amp: amp)
```

to:

```swift
                flowLine(height: height, cx: cx, amp: amp,
                         drift: reduceMotion ? 0 : scrollY)
```

- [ ] **Step 2: Offset the echo strands by per-strand parallax factors**

Change `flowLine`'s signature and the four echo strokes (the central grey strand stays fixed). From:

```swift
    private func flowLine(height: CGFloat, cx: CGFloat, amp: CGFloat) -> some View {
```

to:

```swift
    private func flowLine(height: CGFloat, cx: CGFloat, amp: CGFloat, drift: CGFloat) -> some View {
```

and change the `ZStack` body from:

```swift
        return ZStack {
            main.stroke(Palette.hairlineStrong, style: stroke(1.4)).offset(x: 46).opacity(0.30)
            main.stroke(Palette.hairlineStrong, style: stroke(1.4)).offset(x: -50).opacity(0.26)
            a.stroke(Palette.hairlineStrong, style: stroke(1.3)).offset(x: 22).opacity(0.40)
            b.stroke(Palette.hairlineStrong, style: stroke(1.3)).offset(x: -24).opacity(0.40)
            main.stroke(Palette.mute.opacity(0.45), style: stroke(2))   // central strand, grey
        }
```

to:

```swift
        // Parallax: each echo drifts vertically at its own small rate as you
        // scroll, so the woven band separates into near/far layers. The
        // central strand stays locked to the nodes. Strands overrun both
        // edges by rowHeight in ribbonPath, which covers the largest drift.
        return ZStack {
            main.stroke(Palette.hairlineStrong, style: stroke(1.4))
                .offset(x: 46, y: drift * 0.06).opacity(0.30)
            main.stroke(Palette.hairlineStrong, style: stroke(1.4))
                .offset(x: -50, y: drift * -0.08).opacity(0.26)
            a.stroke(Palette.hairlineStrong, style: stroke(1.3))
                .offset(x: 22, y: drift * 0.03).opacity(0.40)
            b.stroke(Palette.hairlineStrong, style: stroke(1.3))
                .offset(x: -24, y: drift * -0.04).opacity(0.40)
            main.stroke(Palette.mute.opacity(0.45), style: stroke(2))   // central strand, grey
        }
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/PathView.swift && git commit -m "feat(path): parallax drift on trail echo strands"
```

---

### Task 4: Full verification

**Files:** none created or modified (screenshots go to the session scratchpad).

**Interfaces:**
- Consumes: everything above.
- Produces: green test suite + visual confirmation.

- [ ] **Step 1: Run the full test suite**

Run: `cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild -project CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -5`
Expected: `Executed 60 tests, with 0 failures` (55 existing + 5 new; exact count may differ slightly — 0 failures is the requirement).

- [ ] **Step 2: Screenshot the Today path**

Build was already installed by the test step's build; install and launch fresh:

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork \
  && xcrun simctl boot "iPhone 17" 2>/dev/null; \
  APP=$(find ~/Library/Developer/Xcode/DerivedData -name "CrazyWork.app" -path "*iphonesimulator*" | head -1) \
  && xcrun simctl install "iPhone 17" "$APP" \
  && xcrun simctl terminate "iPhone 17" com.crazywork.app 2>/dev/null; \
  xcrun simctl launch "iPhone 17" com.crazywork.app -startTab path -seedDemo YES \
  && sleep 6 \
  && xcrun simctl io "iPhone 17" screenshot "$SCRATCHPAD/path-parallax.png"
```

(Substitute `$SCRATCHPAD` with the session scratchpad path; check the actual bundle id in `CrazyWork/project.yml` if `com.crazywork.app` is wrong.)

Expected in the screenshot: no red glow; nodes near the vertical center crisp and full-size; nodes near the hero/top or bottom edge visibly smaller, dimmer, and slightly blurred.

- [ ] **Step 3: Verify scrolled state**

The depth-of-field only proves itself when the focal plane moves. There is no scripted scroll via simctl, so verify the geometry indirectly: the top-most visible node after launch sits near the viewport edge and must render defocused while a mid-screen node renders crisp — both states visible in one screenshot from Step 2. If ambiguous, relaunch and screenshot again after 6s.

- [ ] **Step 4: Report**

No commit (nothing changed). Summarize: tests green, screenshot findings, any visual tuning suggestions (falloff constants live in one place: `0.16` scale, `0.5` opacity, `2.5` blur, and the four strand factors).
