# Path scroll parallax — design

**Date:** 2026-07-02
**Scope:** `CrazyWork/Sources/Views/PathView.swift` only.

## Problem

The Today path currently has a `redGlow` — a blurred red radial gradient that
rides `scrollY` and weaves side to side via two sine waves
([PathView.swift:74](../../../CrazyWork/Sources/Views/PathView.swift)). It reads
as ambient decoration drifting up and down as you scroll; the content itself
doesn't respond. We want the scroll to feel interactive through structured
depth (parallax), not a moving light.

## Approach

Replace the ambient glow with two content-driven depth effects: a focal-plane
depth-of-field on the nodes (**A**), and parallax separation of the trail's
existing strands (**B**).

### Remove

- The `redGlow` computed view and its `GeometryReader` layer in `body`.
- `scrollY` is **kept** — effect B still needs it. The
  `onScrollGeometryChange` capture stays.

### A — Node depth-of-field

Each node comes into sharp focus as it nears the vertical center of the
viewport and recedes toward the top/bottom edges.

- Apply a `.visualEffect { content, proxy in … }` to each `nodeView` (iOS 18
  native; geometry-driven, no extra `@State`, no re-layout).
- Use the built-in `.scrollView` coordinate space: `proxy.frame(in: .scrollView)`
  gives the node frame relative to the scroll viewport, and
  `proxy.bounds(of: .scrollView)` gives the visible viewport rect (its `midY`
  and `height`).
- Compute `t = min(1, |node.midY − viewport.midY| / (viewport.height / 2))`,
  falling back to `t = 0` (full focus) when `bounds(of:)` is nil.
- Map `t` through a shared falloff to three effects:
  - **scale**: `1.0 → 0.84`
  - **opacity**: `1.0 → 0.5`
  - **blur**: `0 → 2.5` pt
- The `.today` node's existing `scaleEffect(1.1)` composes on top (it stays the
  emphasized node even mid-focus).

### B — Parallax trail strands

`flowLine` already draws a grey central spine plus four fainter offset echoes
([PathView.swift:167](../../../CrazyWork/Sources/Views/PathView.swift)). Give
the echoes relative motion so the woven band separates into near/far layers.

- Pass the existing `scrollY` into `flowLine`.
- Offset each echo strand vertically by a small per-strand factor
  (`scrollY * ~0.03–0.08`, alternating sign between strands).
- The central spine (locked to the nodes) gets **no** offset.
- Strands already overrun the top/bottom by `rowHeight` in `ribbonPath`, so the
  vertical shift never exposes a gap.

## Reduce motion

Both effects gate on `@Environment(\.accessibilityReduceMotion)`, consistent
with the rest of the app's motion handling (`Motion.resolved`,
`PressableButtonStyle`):

- **A**: when reduced, nodes render at scale 1.0, opacity 1.0, blur 0 (the
  `visualEffect` returns the content unmodified).
- **B**: when reduced, strand offsets are 0 (static, current appearance).

## Non-goals

- No background/atmosphere layer (rejected: re-introduces the ambient drift).
- No snap-to-node / haptics.
- No changes outside `PathView.swift`.

## Verification

- `xcodebuild … build` succeeds; existing tests stay green (`… test`).
- Screenshot the Today tab mid-scroll (`-startTab path -seedDemo YES`):
  center node crisp/full-size, edge nodes dimmed/blurred/smaller; no red glow.
