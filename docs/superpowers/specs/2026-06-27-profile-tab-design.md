# Profile Tab + Settings

**Date:** 2026-06-27
**Status:** Approved design

## Goal

A new **Profile** tab: an editable display name and a lifetime summary header,
plus the app's settings — a **Sound & voice** toggle and an **Appearance**
(System / Light / Dark) picker. Both settings wire to real behavior.

## Decisions (from brainstorming)

- Settings: audio on/off and light/dark mode. (Rest default, camera, and form
  strictness were considered and dropped.)
- Profile header: editable display name + a quick lifetime summary (workouts,
  current streak).
- Extras dropped (YAGNI): About/version, clear-history.

## Architecture

Registry/storage-driven, no new persistence model. Settings are `@AppStorage`
values; the lifetime summary reuses the existing pure `ProgressStats`.

## Components

### 1. Appearance mode + tab — `CrazyWork/Sources/Views/RootView.swift`

- Add an `AppearanceMode` enum (in `ProfileView.swift`, see below):
  `enum AppearanceMode: String, CaseIterable { case system, light, dark }` with
  `var colorScheme: ColorScheme?` → `nil` / `.light` / `.dark`.
- `RootView` reads `@AppStorage("appearance")` (default `.system`) and applies
  `.preferredColorScheme(appearance.colorScheme)` to the `TabView` — applies
  app-wide.
- Add a 5th tab after Stats (or before History): `NavigationStack { ProfileView() }`,
  `.tabItem { Label("Profile", systemImage: "person.crop.circle") }`,
  `.tag(Tab.profile)` (the `Tab` enum gains a `profile` case).

### 2. `ProfileView` — `CrazyWork/Sources/Views/ProfileView.swift` (new)

A `Form` with two sections:

- **Header section:**
  - `TextField("Name", text:)` bound to `@AppStorage("displayName")` (default
    "Athlete").
  - Two read-only stat chips — total workouts and current streak — from
    `ProgressStats(summaries: sessions.map(\.summary))` over a
    `@Query private var sessions: [WorkoutSession]`.
- **Settings section:**
  - `Toggle("Sound & voice", isOn:)` bound to the existing
    `@AppStorage("workoutAudioEnabled")` (default true). Same key the live HUD
    mute uses, so the two stay in sync with no extra wiring.
  - `Picker("Appearance", selection:)` bound to `@AppStorage("appearance")`,
    one row per `AppearanceMode` ("System" / "Light" / "Dark").

`AppearanceMode` lives in `ProfileView.swift` (single small file).

### 3. Shared mapping — `WorkoutSession.summary`

`StatsView` currently maps `WorkoutSession → SessionSummary` inline; `ProfileView`
needs the same. Extract a `var summary: SessionSummary` computed property on
`WorkoutSession` (an extension in `ProgressStats.swift` or a small file in the
app target) and use it in both `StatsView` and `ProfileView`, so the mapping
lives in one place:

```swift
extension WorkoutSession {
    var summary: SessionSummary {
        SessionSummary(date: startedAt,
                       reps: totalReps,
                       holdSeconds: totalHoldSeconds,
                       formScore: averageFormScore,
                       duration: (endedAt ?? startedAt).timeIntervalSince(startedAt))
    }
}
```

`StatsView.stats` is updated to `ProgressStats(summaries: sessions.map(\.summary))`.

## Persisted keys

- `workoutAudioEnabled` (existing) — Bool, default true.
- `appearance` (new) — `AppearanceMode` raw String, default `system`.
- `displayName` (new) — String, default "Athlete".

## Testing

The only new logic is `AppearanceMode.colorScheme` (a trivial 3-case switch) —
no unit test warranted. `ProgressStats` is already covered, and the
`WorkoutSession.summary` extension is a straight field map. Verified by build +
manual: toggle audio (syncs with the live HUD), flip appearance (whole app
re-themes), edit the name (persists), header counts match the Stats tab.

## Out of scope (YAGNI)

- About/version row, clear-history button.
- Rest-default, camera front/back, and form-strictness settings (each is a
  later one-row add).
- Any account/sync/profile-photo system.
