# Pose Overlay Customization

**Date:** 2026-06-27
**Status:** Approved design

## Goal

Let the user customize the pose-detection skeleton overlay: pick a color, line
thickness, toggle the joint dots, and toggle the whole overlay — with a few
one-tap presets that set those values. Settings live in the Profile tab and the
overlay reads them.

## Decisions (from brainstorming)

- Both presets and granular controls. **Granular `@AppStorage` values are the
  single source of truth; each preset is a button that writes them** (no
  separate "active preset" state).
- Knobs: skeleton color, line thickness, show joints, show skeleton (master).
- Presets: Classic, Neon, Minimal, Hidden.

## Architecture

`@AppStorage`-backed settings (no model). Two small enums map a stored raw
String to concrete visual values; `SkeletonOverlay` reads the four settings and
draws accordingly; `ProfileView` exposes presets + controls bound to the same
keys.

## Storage keys (defaults reproduce today's look)

- `skeletonColor` — `SkeletonColor` raw String, default `green`.
- `skeletonThickness` — `SkeletonThickness` raw String, default `medium`.
- `skeletonShowJoints` — Bool, default `true`.
- `skeletonShowSkeleton` — Bool, default `true`.

## Components

### 1. Style types — `CrazyWork/Sources/Views/SkeletonStyle.swift` (new)

```swift
enum SkeletonColor: String, CaseIterable {
    case green, blue, pink, white, orange
    var color: Color { … }   // green→.green, blue→.blue, pink→.pink, white→.white, orange→.orange
    var label: String { … }  // "Green", "Blue", …
}

enum SkeletonThickness: String, CaseIterable {
    case thin, medium, thick
    var lineWidth: CGFloat { thin 2, medium 3, thick 5 }
    var dotRadius: CGFloat { thin 3, medium 4, thick 6 }
    var label: String { "Thin"/"Medium"/"Thick" }
}

struct OverlayPreset: Identifiable {
    let id: String          // also the display name
    let color: SkeletonColor
    let thickness: SkeletonThickness
    let showJoints: Bool
    let showSkeleton: Bool

    static let all: [OverlayPreset] = [
        OverlayPreset(id: "Classic", color: .green, thickness: .medium, showJoints: true,  showSkeleton: true),
        OverlayPreset(id: "Neon",    color: .pink,  thickness: .thick,  showJoints: true,  showSkeleton: true),
        OverlayPreset(id: "Minimal", color: .white, thickness: .thin,   showJoints: false, showSkeleton: true),
        OverlayPreset(id: "Hidden",  color: .green, thickness: .medium, showJoints: true,  showSkeleton: false),
    ]
}
```

These mappings are the only "logic" — trivial switches, no unit test.

### 2. Overlay reads the settings — `CrazyWork/Sources/Views/SkeletonOverlay.swift`

Add four `@AppStorage` properties matching the keys/defaults above
(`skeletonColor: SkeletonColor`, `skeletonThickness: SkeletonThickness`,
`skeletonShowJoints: Bool`, `skeletonShowSkeleton: Bool`). In the `Canvas`:

- If `!skeletonShowSkeleton`, draw nothing (master off → camera only).
- Else stroke each bone with `skeletonColor.color` at `skeletonThickness.lineWidth`.
- Draw joint dots with `skeletonColor.color` at radius `skeletonThickness.dotRadius`
  only when `skeletonShowJoints` is true.

Replaces the current hardcoded `.green.opacity(0.8)` / `lineWidth 3` bones and
`.yellow` / radius-4 dots. (Joint dots now match the chosen color rather than
always yellow.)

### 3. Settings UI — `CrazyWork/Sources/Views/ProfileView.swift`

Add a **"Pose overlay"** `Section`:

- A presets row: a button per `OverlayPreset.all`; tapping one writes the four
  `@AppStorage` values (`skeletonColor = preset.color`, etc.).
- `Picker("Color")` over `SkeletonColor.allCases` (bound to `skeletonColor`).
- `Picker("Thickness")` over `SkeletonThickness.allCases` (bound to `skeletonThickness`).
- `Toggle("Show joints")` (bound to `skeletonShowJoints`).
- `Toggle("Show skeleton")` (bound to `skeletonShowSkeleton`).

`ProfileView` declares the same four `@AppStorage` keys (and binds the controls
to them); the preset buttons assign to those bindings.

## Testing

No unit tests — the only logic is trivial enum→value mappings and static preset
data; `Canvas` drawing is not meaningfully unit-testable. Verified by build +
manual: change color/thickness/toggles and tap each preset, start a workout, see
the overlay reflect it; "Hidden" (or Show-skeleton off) shows just the camera.

## Out of scope (YAGNI)

- Glow/blur effects, per-joint colors, opacity sliders.
- A live in-workout overlay control (settings live in Profile; the next workout
  picks them up — and they update reactively within a session anyway).
- Custom/hex colors beyond the fixed palette.
