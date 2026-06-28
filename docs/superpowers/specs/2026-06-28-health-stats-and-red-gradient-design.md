# Health Metrics View + Red Gradient Spread — Design

Date: 2026-06-28
Status: Approved

## Goal

Three changes on top of the Raycast-style overhaul:

1. **View Health metrics** — after connecting Apple Health, show the body metrics
   CrazyWork pulls (weight, height, age, sex) in both Profile and Stats.
2. **Spread the red gradient** — the `HeroStripeBand` (currently only on Build) goes
   on every tab's header, plus subtle red accents on selected states and key numbers.
3. **Move the heatmap up** — the consistency calendar moves directly under the stat
   cards in Stats (it's currently last).

## Decisions taken (from brainstorming)

- Health metrics shown: **weight, height, age, sex** only — the values already read by
  `HealthStore.body()` for calorie math. No new HealthKit reads.
- Location: **both** Profile (under the Connect toggle) and Stats (a section near top),
  via one reusable component. Two independent `body()` loads is acceptable for a
  read-only display.
- Red gradient: **header band on every tab + subtle accents**. This intentionally
  overrides DESIGN.md's "hero stripe once per page" rule — the user wants it spread.

## Components

### 1. `HealthMetricsCard` (CrazyWork/Sources/Theme/Components/HealthMetricsCard.swift)

Self-contained, reusable, gated:

```swift
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
}
```

Formatting helpers (pure, testable, `static`):
- `weightText(_ kg: Double?) -> String` — `"72 kg"`, nil → `"—"` (rounded to whole kg).
- `heightText(_ cm: Double?) -> String` — `"178 cm"`, nil → `"—"`.
- `sexText(_ isMale: Bool?) -> String` — `true` → `"Male"`, `false` → `"Female"`, nil → `"—"`.
- `tile(_ title:_ value:)` — a `VStack` of value (`Typography.headingXl`, `Palette.ink`)
  over title (`Typography.captionSm`, `Palette.mute`), matching the Stats stat-card look.

When Health is connected but reads were denied, `body()` returns nils and every tile
shows `—` (no crash, no separate error state).

### 2. Red gradient header bands

Wrap each tab's title in `HeroStripeBand` (the component already exists). Pattern,
matching Build:
- Hide the nav bar: `.toolbar(.hidden, for: .navigationBar)`.
- Make `HeroStripeBand { VStack { title … } }` the first item in the scroll content.
- Empty-state screens (Stats/History with no sessions) show the band first, then the
  `ContentUnavailableView` below it.

Applied to: **PremadePlansView, StatsView, HistoryView, ProfileView**. Build is unchanged.

### 3. Subtle red accents

- `PillTab` active state: fill `Palette.brandRedSoft`, text `Palette.accentRedBright`
  (was `surfaceElevated` / `onDark`). This is a shared component change, so the Profile
  pose-overlay preset chips pick it up automatically.
- Key numbers go `Palette.brandRed`: the Stats "Current streak" and "Longest streak"
  card values, and the Profile header "Streak" value. Other stat values stay `ink` so the
  red reads as emphasis, not noise.

### 4. Stats reorder

`StatsView.content(_:)` order becomes: stat cards → **`HealthMetricsCard()`** →
**consistency calendar** → trend charts. (Calendar moves up from last; the Health card
is inserted after the stat cards.)

### 5. Profile placement

In `ProfileView`, insert `HealthMetricsCard()` immediately after the existing
`healthCard` (the Connect toggle). The card self-gates, so it simply renders nothing
until Health is connected.

## Data flow

```
Connect Apple Health toggle ON ──► HealthStore.requestAuthorization()
HealthMetricsCard appears (gated on healthSyncEnabled) ──► .task ──►
   HealthStore.body() ──► weight/height/age/sex ──► four tiles (nil → "—")
```

## Error / edge handling

- Health unavailable or not connected → card renders nothing (gate).
- Reads denied → nils → "—" tiles. No crash.
- Two loads (Profile + Stats) are independent and cheap; values may differ by a second —
  acceptable for read-only display.

## Testing

- `HealthMetricsCardTests` (CrazyWork/Tests): `weightText`, `heightText`, `sexText`
  formatting incl. nil → "—" and rounding.
- Visual verification (build + screenshot) for the header bands, accent colors, Stats
  reorder, and the Health card in both Profile and Stats (connected + not connected).

## Out of scope

- No new HealthKit reads (no active energy, heart rate, or workout history).
- No unit toggle (kg/cm only; imperial is a later add if wanted).
- No refresh control — the card loads once per appearance via `.task`.
