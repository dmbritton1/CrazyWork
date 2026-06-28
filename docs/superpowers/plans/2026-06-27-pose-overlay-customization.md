# Pose Overlay Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user customize the pose skeleton overlay — color, line thickness, show-joints, show-skeleton — with one-tap presets, all stored in `@AppStorage` and surfaced in the Profile tab.

**Architecture:** Granular `@AppStorage` values are the source of truth; two enums map stored strings to concrete visuals; `SkeletonOverlay` reads the four settings and draws accordingly; `ProfileView` exposes presets (buttons that write the four keys) plus the granular controls.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`, `@AppStorage`, `Form`). Build on iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`. XcodeGen auto-discovers files under `Sources/` on `xcodegen generate` in `CrazyWork/`.

## Global Constraints

- Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).
- Storage keys + defaults (defaults reproduce today's look): `skeletonColor`=`green` (`SkeletonColor`), `skeletonThickness`=`medium` (`SkeletonThickness`), `skeletonShowJoints`=`true` (Bool), `skeletonShowSkeleton`=`true` (Bool).
- No new unit tests — only logic is trivial enum→value mappings and static preset data; verify by build + the existing suite staying green.

> **Spec:** `docs/superpowers/specs/2026-06-27-pose-overlay-customization-design.md`

---

### Task 1: Style types + overlay reads the settings

**Files:**
- Create: `CrazyWork/Sources/Views/SkeletonStyle.swift`
- Modify: `CrazyWork/Sources/Views/SkeletonOverlay.swift`

**Interfaces:**
- Produces: `SkeletonColor` (`.green/.blue/.pink/.white/.orange`, `var color: Color`, `var label: String`), `SkeletonThickness` (`.thin/.medium/.thick`, `var lineWidth: CGFloat`, `var dotRadius: CGFloat`, `var label: String`), `OverlayPreset` (`id`, `color`, `thickness`, `showJoints`, `showSkeleton`; `static let all`). All consumed by Task 2.

- [ ] **Step 1: Create the style types**

Create `CrazyWork/Sources/Views/SkeletonStyle.swift`:

```swift
import SwiftUI

/// Overlay color palette, persisted via `@AppStorage` (String-backed).
enum SkeletonColor: String, CaseIterable {
    case green, blue, pink, white, orange

    var color: Color {
        switch self {
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .white: return .white
        case .orange: return .orange
        }
    }

    var label: String { rawValue.capitalized }
}

/// Overlay line/dot thickness, persisted via `@AppStorage` (String-backed).
enum SkeletonThickness: String, CaseIterable {
    case thin, medium, thick

    var lineWidth: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 3
        case .thick: return 5
        }
    }

    var dotRadius: CGFloat {
        switch self {
        case .thin: return 3
        case .medium: return 4
        case .thick: return 6
        }
    }

    var label: String { rawValue.capitalized }
}

/// A one-tap overlay look. Applying a preset writes the four `@AppStorage` keys.
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

- [ ] **Step 2: Make `SkeletonOverlay` read the settings**

In `CrazyWork/Sources/Views/SkeletonOverlay.swift`, add four `@AppStorage`
properties right after the existing `var minConfidence: Double = 0.3`:

```swift
    @AppStorage("skeletonColor") private var skeletonColor = SkeletonColor.green
    @AppStorage("skeletonThickness") private var skeletonThickness = SkeletonThickness.medium
    @AppStorage("skeletonShowJoints") private var showJoints = true
    @AppStorage("skeletonShowSkeleton") private var showSkeleton = true
```

Replace the `Canvas { … }` block (the bones loop + joints loop) with:

```swift
            Canvas { context, _ in
                guard let frame, showSkeleton else { return }
                let stroke = skeletonColor.color

                for (a, b) in Self.bones {
                    guard let pa = point(a, in: frame, size: size),
                          let pb = point(b, in: frame, size: size) else { continue }
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    context.stroke(path, with: .color(stroke.opacity(0.85)),
                                   lineWidth: skeletonThickness.lineWidth)
                }

                if showJoints {
                    let r = skeletonThickness.dotRadius
                    for joint in ChallengeCore.Joint.allCases {
                        guard let p = point(joint, in: frame, size: size) else { continue }
                        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                        context.fill(dot, with: .color(stroke))
                    }
                }
            }
```

(Leave the surrounding `GeometryReader`/`size`/`.allowsHitTesting(false)` and the
`point(_:in:size:)` helper unchanged.)

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. (With defaults, the overlay looks like before — green bones, medium width — except joint dots are now green instead of yellow.)

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/SkeletonStyle.swift CrazyWork/Sources/Views/SkeletonOverlay.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: skeleton overlay reads color/thickness/visibility from settings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Pose-overlay settings in the Profile tab

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:**
- Consumes: `SkeletonColor`, `SkeletonThickness`, `OverlayPreset` (Task 1), and the four `@AppStorage` keys from Global Constraints.

- [ ] **Step 1: Add the overlay settings storage**

In `CrazyWork/Sources/Views/ProfileView.swift`, add these four properties next to
the existing `@AppStorage` declarations (after `@AppStorage("appearance") …`):

```swift
    @AppStorage("skeletonColor") private var skeletonColor = SkeletonColor.green
    @AppStorage("skeletonThickness") private var skeletonThickness = SkeletonThickness.medium
    @AppStorage("skeletonShowJoints") private var skeletonShowJoints = true
    @AppStorage("skeletonShowSkeleton") private var skeletonShowSkeleton = true
```

- [ ] **Step 2: Add the "Pose overlay" section**

In the `Form`, add this `Section` immediately AFTER the existing
`Section("Settings") { … }` block:

```swift
            Section("Pose overlay") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(OverlayPreset.all) { preset in
                            Button(preset.id) { apply(preset) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Picker("Color", selection: $skeletonColor) {
                    ForEach(SkeletonColor.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Thickness", selection: $skeletonThickness) {
                    ForEach(SkeletonThickness.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show joints", isOn: $skeletonShowJoints)
                Toggle("Show skeleton", isOn: $skeletonShowSkeleton)
            }
```

- [ ] **Step 3: Add the preset-apply helper**

Add this method to `ProfileView` (e.g. right after the existing
`private func stat(_:_:) -> some View` helper):

```swift
    private func apply(_ preset: OverlayPreset) {
        skeletonColor = preset.color
        skeletonThickness = preset.thickness
        skeletonShowJoints = preset.showJoints
        skeletonShowSkeleton = preset.showSkeleton
    }
```

- [ ] **Step 4: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/ProfileView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: Pose overlay settings (presets + color/thickness/toggles) in Profile

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Full verification

- [ ] **Step 1: Engine + app suites**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -2
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: engine pass; app `** TEST SUCCEEDED **`.

- [ ] **Step 2: Manual checklist (note for the user)**

In Profile → Pose overlay: tap each preset (Classic / Neon / Minimal / Hidden)
and watch the Color/Thickness/Show-joints/Show-skeleton controls update; then
start a workout and confirm the overlay reflects color + thickness, that
"Show joints" off hides the dots, and "Show skeleton" off (or the Hidden preset)
shows just the camera.

- [ ] **Step 3: Push**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git push
```

---

## Self-Review Notes

- **Spec coverage:** `SkeletonColor`/`SkeletonThickness`/`OverlayPreset` (Task 1); overlay reads the four keys and master-off/joints-off logic (Task 1); Profile presets + color/thickness/toggles bound to the same keys + apply helper (Task 2). All spec sections map to a task.
- **Build stays green:** Task 1 ships with defaults reproducing the current look (no UI to change them yet); Task 2 adds the controls.
- **Type consistency:** `SkeletonColor`/`SkeletonThickness` (+ `.color`/`.lineWidth`/`.dotRadius`/`.label`), `OverlayPreset.all`, and the four `@AppStorage` keys are used identically in `SkeletonOverlay`, `SkeletonStyle`, and `ProfileView`.
- **`@AppStorage` enums:** `SkeletonColor`/`SkeletonThickness` are `String`-backed `RawRepresentable`, which `@AppStorage` supports (same pattern as the already-shipped `AppearanceMode`).
