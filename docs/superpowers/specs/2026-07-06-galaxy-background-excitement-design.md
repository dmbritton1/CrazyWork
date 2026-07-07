# Galaxy Background Excitement — Design

**Date:** 2026-07-06
**Scope:** `GalaxyBackground` (currently a private struct in `CrazyWork/Sources/Views/PathView.swift`)
**Goal:** Make the Today-tab sky feel alive without breaking the page's rules: the trail ribbon stays the only line on the canvas, everything pauses under Reduce Motion, and no new `@State` enters the render loop.

Three additions: shooting stars, a near bokeh layer, and breathing nebulae. All three stay deterministic (hash-seeded, stateless) like the existing star field.

## 0. File move (enabling refactor)

`PathView.swift` is ~750 lines and growing. Move `GalaxyBackground` (and its new helpers) to its own file, `CrazyWork/Sources/Views/GalaxyBackground.swift`, changing `private` → `internal` so `@testable import` can reach the new pure helpers. No behavior change.

## 1. Shooting stars

A meteor occasionally streaks across the sky; hard scroll flings make them more likely and brighter.

**Scheduling (stateless).** Five meteor "slots". Each slot `i` has a hashed period `P_i` (14…26 s) and fires for `dur = 0.6 s` at the start of each period. Life phase:

```
τ_i(t) = (t mod P_i) / dur     // active iff 0 ≤ τ < 1
```

- Slots 0–2 are always eligible.
- Slots 3–4 are eligible only while `energy > 0.3` — a fling during their window sparks an extra meteor. Stateless gating means an in-flight extra meteor vanishes if energy drops mid-streak; at 0.6 s life and ~0.5 s energy decay this is imperceptible.
- All meteors get an alpha boost `× (0.7 + 0.6 × energy)` so fling-time meteors read brighter.

**Geometry.** Per firing `k` of slot `i`, seed a hash with `(i, k)`:
- Start point: x anywhere, y in the top ⅔ of the viewport.
- Direction: diagonal, hashed left-or-right, components ≈ (±0.8, 0.55), normalized.
- Travel: 180…260 pt over the 0.6 s life, linear.
- Meteors ignore `drift` — they are sky events, not parallax-locked geometry.

**Rendering (no linework).** A chain of ~8 circles trailing the head along the motion vector: radius decays 2.2 → 0.4 pt, alpha decays head → tail. The head gets the existing big-star halo treatment. Whole-life alpha envelope `sin(π·τ)` fades it in and out. Colors: `Palette.ink`, with a hashed 1-in-5 chance of `Palette.accentRedBright`. Drawn in the existing `Canvas` after the star layers.

**Pure helper for tests.**

```swift
/// nil when the slot is dormant; else life phase 0…1.
nonisolated static func meteorPhase(t: TimeInterval, period: Double, duration: Double) -> Double?
```

Position/direction derivation stays in the Canvas closure (visual, verified by eye).

## 2. Near bokeh layer

A fourth star layer, so close it's out of focus. Extend the `Layer` table with a `soft: Bool` flag:

| | count | parallax | size | alpha | soft |
|---|---|---|---|---|---|
| far | 48 | 0.10 | 0.7–1.3 | 0.20 | no |
| mid | 36 | 0.24 | 0.9–1.8 | 0.32 | no |
| near | 24 | 0.44 | 1.3–2.4 | 0.48 | no |
| **bokeh** | **8** | **0.62** | **5–9** | **0.13** | **yes** |

Soft dots render as a radial-gradient fill (center color → clear) instead of a hard circle — fake blur, no `GraphicsContext` filter cost. They skip the twinkle branch; instead a slow wobble `alpha × (1 + 0.2 sin(0.25·t + phase))` keeps them breathing. Tint: mostly `Palette.ink`, the same hashed 5%/5% red/aqua chance as stars. Same wrap-around drift logic as the other layers.

## 3. Breathing nebulae

The two washes stop being static wallpaper:

- **Parallax:** `.offset(y: -drift * 0.05)` — slower than the farthest star layer, so they read as infinitely far.
- **Breathe:** wrap `nebula` in its own `TimelineView(.animation(minimumInterval: 1/8, paused: paused))`. Each wash scales `1 + 0.05 sin(2πt/22 + φ)` and modulates opacity `× (1 + 0.06 sin(2πt/17 + φ′))`, with different phases per wash so they never sync. 8 fps is plenty for 20-second cycles and keeps the cost near zero.
- Light-mode `nebulaDim` behavior unchanged.

## Motion & accessibility

`paused` (Reduce Motion) already freezes the star `TimelineView` and the call site passes `drift = 0`. New behavior under Reduce Motion: no meteors (`guard !paused`), bokeh static (no wobble), nebulae static (paused TimelineView + zeroed breathe amplitude). Nothing moves that didn't before.

## Performance

Everything rides the existing 30 fps Canvas pass plus one 8 fps TimelineView for the nebulae. Adds ~8 gradient dots + ≤5 × 8 meteor circles per frame, no filters, no new state. No measurable cost expected; verify by eye on the simulator (no dropped frames while flinging).

## Testing

One new test file `GalaxyBackgroundTests.swift`:
- `meteorPhase` is nil outside the firing window, 0…1 inside, periodic across `t + P`.
- Existing suites unaffected (`GalaxyBackground` move is mechanical).

## Out of scope

- Milky-way band, today-glow nebula (options 4–5 from the discussion).
- Any linework in the sky; constellation connecting lines.
- Per-star motion beyond the existing parallax/twinkle.

## Tuning knobs (post-implementation, by eye)

- Meteor cadence: slot periods 14–26 s; energy gate 0.3.
- Bokeh: count 8, alpha 0.13, parallax 0.62.
- Nebula breathe: ±5% scale / ±6% opacity, 22 s / 17 s cycles.
