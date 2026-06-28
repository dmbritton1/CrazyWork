# CrazyWork UI Overhaul (Raycast-style) — Design

Date: 2026-06-28
Status: Approved

## Goal

Re-skin the entire CrazyWork app to the design system in `DESIGN.md` (Raycast-style:
near-black dark canvas, hairline-bordered cards, surface-ladder elevation with no
shadows, white/inverting CTA pills, a dominant red accent ramp + complementary aqua
secondary, Inter typography with the `ss03` stylistic set). Build a reusable token +
component foundation, then restyle every screen on top of it.

## Decisions taken (from brainstorming)

- **Typography:** bundle **Inter** (static Regular/Medium/SemiBold) and enable the
  `ss03` stylistic set site-wide via font-descriptor feature attributes. Display tier
  additionally enables `ss02`/`ss08` and disables standard ligatures.
- **Color mode:** the existing System/Light/Dark appearance toggle in Profile is
  **kept**. `DESIGN.md` is dark-only, so light mode is a **derived mirror** (see
  Light-Mode Derivation). Every color token is an adaptive `Color`.
- **Scope:** **all** screens — Build, Plans, Stats, History, Consistency calendar,
  Profile, Live workout, Rest, Summary, Share card, plus the tab bar.
- **List/Form replacement:** system `List`/`Form` are replaced with
  `ScrollView` + `LazyVStack` of `Card`s so the hairline-card-on-canvas look is exact,
  rather than fighting grouped-table chrome.

## Architecture

A new `CrazyWork/Sources/Theme/` foundation that all screens consume. No screen
hardcodes a hex value or a system font after this work — everything routes through the
token layer.

```
Sources/Theme/
  Palette.swift        // adaptive Color tokens (dark = DESIGN.md, light = mirror)
  Typography.swift     // Inter + ss03 Font tokens
  Spacing.swift        // 8px scale 2..96
  Radii.swift          // radius scale 0..full
  ThemeAppearance.swift// UITabBarAppearance / UINavigationBar theming
  Components/
    Card.swift         // surface + hairline + radius + padding modifier
    Buttons.swift      // Primary / Secondary / Tertiary / SecondaryRed / SecondaryAqua
    Badge.swift        // pro / red-soft / aqua-soft / info-soft
    Keycap.swift
    PillTab.swift
    Bands.swift        // HeroStripeBand (red), AquaGlowBand (teal)
    ExerciseTile.swift // SF-Symbol-in-surface-card tile (our app-icon-tile analog)
Sources/Resources/Fonts/
  Inter-Regular.ttf  Inter-Medium.ttf  Inter-SemiBold.ttf
```

### Palette (token → meaning)

All tokens are `static let` adaptive `Color`s on a `Palette` enum, built with
`Color(uiColor: UIColor { trait in trait.userInterfaceStyle == .dark ? darkHex : lightHex })`.

Dark values are copied verbatim from `DESIGN.md`. Carried tokens:

- Surface ladder: `canvas` `#07080a`, `surface` `#0d0d0d`, `surfaceElevated` `#101111`,
  `surfaceCard` `#121212`, `hairline` `#242728`, `hairlineSoft` `rgba(255,255,255,0.08)`,
  `hairlineStrong` `rgba(255,255,255,0.16)`.
- Primary: `primary` (CTA bg), `primaryPressed`, `onPrimary`.
- Text: `ink` `#f4f4f6`, `body` `#cdcdcd`, `mute` `#9c9c9d`, `ash` `#6a6b6c`,
  `stone` `#434345`, `onDark` `#ffffff`.
- Red ramp: `accentRedBright` `#ff8a8a`, `accentRed` `#ff6161`, `brandRed` `#ff3b3b`,
  `brandRedPressed` `#e22d2d`, `accentRedDeep` `#c8202b`, `accentRedInk` `#7a0f15`,
  plus softs `accentRedSoft`, `brandRedSoft`.
- Aqua family: `accentAquaBright` `#7df0ea`, `accentAqua` `#34d6cd`,
  `accentAquaPressed` `#28bdb4`, `accentTealDeep` `#0d8f88`, `accentTealInk` `#07514d`,
  soft `accentAquaSoft`.
- Other semantics: `accentBlue`/`accentBlueSoft`, `accentGreen`/`accentGreenSoft`,
  `accentYellow`/`accentYellowSoft`.
- Gradient stops: `heroStripeStart` `#ff5757`, `heroStripeMid` `#c8202b`,
  `heroStripeEnd` `#7a0f15`, `aquaGlowStart` `#34d6cd`, `aquaGlowEnd` `#07514d`,
  `keyBgStart` `#121212`, `keyBgEnd` `#0d0d0d`.

### Light-Mode Derivation

`DESIGN.md` has no light mode; light values are derived to preserve the same semantic
roles (contrast direction, monochrome high-contrast pill, accents constant):

| Role | Dark | Light |
|---|---|---|
| `canvas` | `#07080a` | `#f7f7f8` |
| `surface` | `#0d0d0d` | `#ffffff` |
| `surfaceElevated` | `#101111` | `#f0f0f2` |
| `surfaceCard` | `#121212` | `#eaeaec` |
| `hairline` | `#242728` | `#e0e0e3` |
| `hairlineStrong` | `rgba(255,255,255,0.16)` | `rgba(0,0,0,0.16)` |
| `hairlineSoft` | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.08)` |
| `ink` | `#f4f4f6` | `#101114` |
| `body` | `#cdcdcd` | `#3a3a3d` |
| `mute` | `#9c9c9d` | `#6a6b6c` |
| `ash` | `#6a6b6c` | `#9c9c9d` |
| `stone` | `#434345` | `#c0c0c4` |
| `onDark` | `#ffffff` | `#101114` (interactive text on light) |
| `primary` (CTA bg) | `#ffffff` | `#101114` |
| `primaryPressed` | `#e8e8e8` | `#2a2a2e` |
| `onPrimary` (CTA text) | `#000000` | `#ffffff` |

Accents (red ramp, aqua family, blue/green/yellow) and all gradient stops are **identical
in both modes** — they are saturated colors, not surface-dependent. Softs use the same
rgba over whatever surface they sit on.

### Typography

`Typography.swift` exposes the 15 tokens from `DESIGN.md` as `Font` values. Inter is
loaded as static weights and wrapped through `UIFont` so feature settings apply:

```swift
enum InterTier { case body, display }

private func interUIFont(size: CGFloat, weight: UIFont.Weight, tier: InterTier) -> UIFont {
    let name: String  // "Inter-Regular" / "Inter-Medium" / "Inter-SemiBold" by weight
    let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    var features: [[UIFontDescriptor.FeatureKey: Int]] = [
        // ss03 = stylistic alternates (type 35), selector 6
        [.type: kStylisticAlternativesType, .selector: 6],
        // calt/kern/liga are on by default in Core Text; ss03 is the addition.
    ]
    if tier == .display {
        features.append([.type: kStylisticAlternativesType, .selector: 4])  // ss02
        features.append([.type: kStylisticAlternativesType, .selector: 16]) // ss08
        features.append([.type: kLigaturesType, .selector: kCommonLigaturesOffSelector]) // liga 0
    }
    let desc = base.fontDescriptor.addingAttributes([.featureSettings: features])
    return UIFont(descriptor: desc, size: size)
}
```

Tokens (size / weight / line-height / tracking) follow the `DESIGN.md` hierarchy table
exactly: `displayXl` 64/600, `displayLg` 56/500, `headingXl` 24/500, `headingLg` 22/500,
`headingMd` 20/500, `headingSm` 18/500, `bodyLg` 18/400, `bodyMd` 16/400,
`bodyStrong` 16/500, `bodySm` 14/400, `bodySmStrong` 14/500, `captionMd` 13/400,
`captionSm` 12/400, `linkMd` 16/500, `buttonMd` 14/500. Line-height is applied via
`.lineSpacing`/`.tracking` modifiers where the token is used (SwiftUI `Font` can't carry
leading), exposed as a `Text` style helper `Typography.style(_:)`.

### Spacing & Radii

`Spacing`: `xxs` 2, `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32, `section` 96.
`Radii`: `none` 0, `xs` 4, `sm` 6, `md` 8, `lg` 10, `xl` 16, `full` 9999.

### Components

- **`Card`** — `ViewModifier`: `.padding(padding)` → `.background(Palette.surface)` →
  `.overlay(RoundedRectangle(cornerRadius: r).stroke(Palette.hairline, lineWidth: 1))`
  → `.clipShape(RoundedRectangle(cornerRadius: r))`. Params: `surface` (default
  `surface`), `radius` (default `Radii.lg`), `padding` (default `Spacing.xl`). No shadow.
  Exposed as `.card()` on `View`.
- **Buttons** — SwiftUI `ButtonStyle`s. `PrimaryButtonStyle` (bg `primary`, text
  `onPrimary`, pill `Radii.md`, pressed → `primaryPressed`). `SecondaryButtonStyle`
  (transparent, text `onDark`). `TertiaryButtonStyle` (bg `surfaceElevated`).
  `SecondaryRedButtonStyle` (bg `brandRedSoft`, text `accentRedBright`),
  `SecondaryAquaButtonStyle` (bg `accentAquaSoft`, text `accentAquaBright`).
- **`Badge`** — small label with variants `.pro` / `.redSoft` / `.aquaSoft` / `.infoSoft`,
  `captionSm`, `Radii.xs`.
- **`Keycap`** — glyph with `keyBgStart→keyBgEnd` gradient, `Radii.xs`, `captionMd`.
- **`PillTab`** — `Radii.full` chip; active flips to `surfaceElevated`/`onDark`.
- **`HeroStripeBand`** — three diagonal stripes `heroStripeStart→Mid→End` over canvas.
- **`AquaGlowBand`** — single teal wash `aquaGlowStart→End` over canvas.
- **`ExerciseTile`** — square `surfaceCard` tile (`Radii.md`) with the exercise's SF
  Symbol; sizes 48 / 64. Symbol per exercise id resolved by a small map (pushup →
  `figure.strengthtraining.functional`, squat → `figure.cross.training`, etc.; fall back
  to `figure.strengthtraining.traditional`).

### Screen Restyles

- **`RootView`** — apply `ThemeAppearance.configure()` on appear: `UITabBarAppearance`
  with `canvas` background, `hairline` top rule, `mute` unselected / `onDark` selected
  item color; `UINavigationBarAppearance` with `canvas` background, `ink` titles,
  Inter large-title font. Tab structure unchanged.
- **`BuildWorkoutView`** — canvas background; exercise rows as `Card`s with
  `ExerciseTile` + name + rep/sec target stepper; primary "Start workout" pill;
  a `HeroStripeBand` header is the page's single red moment.
- **`PremadePlansView`** — `List` → `ScrollView`+`LazyVStack`; each plan is a `Card`
  (name `headingSm`, `~N min` keycap-ish meta, summary `bodySm` in `mute`, exercise
  list). Saved-workout section header in `bodySmStrong`. Swipe-to-delete replaced with a
  trailing delete affordance on saved cards (long-press or edit toggle).
- **`StatsView`** — canvas background; stat tiles as `Card`s; charts recolored to tokens
  (bars `brandRed`, secondary series `accentAqua`, gridlines `hairline`).
- **`HistoryView`** + **`ConsistencyCalendarView`** — `List`/grid → `Card` rows;
  calendar cells use the surface ladder for intensity, `brandRed` for the most-active
  day, `accentAqua` accents for "today".
- **`ProfileView`** — `Form` → `ScrollView` of `Card` sections; toggles/pickers restyled
  on `surfaceElevated` rows; the appearance picker stays (drives the palette). Apple
  Health section (from prior work) keeps its toggle, restyled.
- **`LiveWorkoutView`** — already a dark overlay; retint HUD/cues/rest to tokens (form
  cue text `accentRedBright` for faults, progress accent `accentAqua`), keycaps for any
  shortcut hints.
- **`RestCountdownView`** — canvas background, big `displayLg` countdown in `ink`,
  next-exercise `ExerciseTile`, `AquaGlowBand` as the calm secondary moment.
- **`SummaryView`** — "Workout Complete" `displayLg`; charts recolored to tokens; per-set
  rows as `Card`s; share button as primary pill.
- **`WorkoutShareCard`** — dark `surface` card, `hairline` border, `ink`/`mute` text,
  `brandRed` stat values; fixed colors (it renders to an image, mode-independent — use
  the dark palette constants directly).

## Error / Edge Handling

- **Font load failure** — `UIFont(name:)` falls back to `systemFont(ofSize:weight:)`; the
  app never crashes if a `.ttf` is missing, it just loses the Inter look. The token API is
  identical either way.
- **Appearance toggle** — palette resolves per `UITraitCollection`, so flipping
  System/Light/Dark re-renders correctly with no per-screen code.
- **Decorative bands in light mode** — saturated gradients render identically; they're
  designed to read on either canvas.

## Testing

- `ThemeTests` (CrazyWork/Tests): (1) `Inter-Regular` registers and an Inter descriptor
  carries the `ss03` feature attribute (type 35 / selector 6); (2) a representative
  `Palette` token resolves to distinct non-nil colors for `.dark` vs `.light` trait
  collections; (3) spacing/radii scales are monotonic.
- Visual correctness verified by building and screenshotting key screens
  (Build, Plans, Live, Summary, Profile) in both light and dark — not unit-tested.

## Out of Scope

- No new screens or features; this is purely visual.
- No change to workout logic, persistence, audio, or HealthKit behavior.
- Animations/transitions beyond what tokens imply (pressed states) are not added.
