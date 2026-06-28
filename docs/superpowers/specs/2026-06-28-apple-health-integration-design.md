# Apple Health Integration — Design

Date: 2026-06-28
Status: Approved

## Goal

Two-way HealthKit sync for CrazyWork, opt-in via a Profile toggle.

- **Write:** one `HKWorkout` per finished session — activity type, duration, and an
  estimated active-energy value.
- **Read:** body weight + height/age/biological sex, used *only* to improve the
  calorie estimate that gets written back.

Explicitly out of scope: live heart rate, Apple Watch streaming, background
delivery/observers, reading other apps' workouts, weight-trend UI.

## Components

### 1. `ExerciseDefinition.met` (ChallengeCore)

Add one `Double` field, `met`, to `ExerciseDefinition` and set it for every
exercise. This is the single place per-exercise metadata already lives.

| Exercise | MET |
|----------|-----|
| Push-up  | 3.8 |
| Squat    | 5.0 |
| Lunge    | 4.0 |
| Sit-up   | 3.8 |
| Plank    | 3.3 |

(Calisthenics MET values; close enough for an estimate, tunable later.)

### 2. `CalorieEstimator` (CrazyWork/Sources/Health/CalorieEstimator.swift)

Pure, testable. No HealthKit imports. MET method on a BMR base so all four
reads matter:

- BMR via Mifflin-St Jeor:
  `BMR = 10·kg + 6.25·cm − 5·age + (sex == male ? 5 : −161)`
- Per exercise: `kcal = MET × (BMR / 1440) × activeMinutes`
- Session total = sum across the sets performed.

**Active minutes:** whole-session wall-clock (`endedAt − startedAt`), shared
across exercises proportionally (or simplest: blended single MET × total
minutes). Rest time is included.
`// ponytail: rest time counts as active; add per-set timing if accuracy matters.`

**Fallbacks (always returns a number):**
- Missing height/age/sex → simple formula `kcal = MET × 3.5 × kg / 200 × minutes`.
- Missing weight → default 70 kg.

Signature (illustrative):

```swift
struct BodyCharacteristics {
    var weightKg: Double?
    var heightCm: Double?
    var ageYears: Int?
    var isMale: Bool?
}

enum CalorieEstimator {
    /// Active energy in kilocalories for a finished session.
    static func kilocalories(
        results: [SessionCoordinator.SetResult],
        durationMinutes: Double,
        body: BodyCharacteristics
    ) -> Double
}
```

### 3. `HealthStore` (CrazyWork/Sources/Health/HealthStore.swift)

Thin wrapper over `HKHealthStore`. All HealthKit-specific code lives here so the
estimator stays pure and testable. Guarded by `HKHealthStore.isHealthDataAvailable()`.

- `requestAuthorization() async throws`
  - share: `HKWorkoutType`
  - read: `bodyMass`, `height`, `dateOfBirth` (characteristic), `biologicalSex`
- `body() -> BodyCharacteristics` — latest weight (sample query) + characteristics
  (`dateOfBirth`, `biologicalSex` are direct calls). Nil-tolerant.
- `save(start:end:activeEnergyKcal:) async throws` — builds and finishes an
  `HKWorkout(.functionalStrengthTraining, …)` via `HKWorkoutBuilder`, attaching
  an active-energy sample.

Activity type is always `.functionalStrengthTraining` (one type for the mixed
calisthenics session — not branched per exercise).

### 4. `ProfileView`

New `Section("Apple Health")` containing a single `Toggle("Connect Apple Health",
isOn: $healthSyncEnabled)` bound to `@AppStorage("healthSyncEnabled")` (default
false). Turning it on triggers `HealthStore.requestAuthorization()`. The whole
section is hidden when `HKHealthStore.isHealthDataAvailable()` is false (e.g. iPad).

### 5. `LiveWorkoutView.saveIfNeeded()`

Unchanged SwiftData save stays first and remains the source of truth. After it
succeeds, if `healthSyncEnabled`:

1. `HealthStore.body()` → characteristics
2. `CalorieEstimator.kilocalories(...)`
3. `HealthStore.save(start: session.startedAt, end: session.endedAt, activeEnergyKcal:)`

Any HealthKit failure (denied, unavailable, throw) is caught and logged — it
never blocks the workout, mutates the SwiftData result, or crashes. Read denials
surface as nil characteristics, which the estimator's fallbacks already handle.

## Data flow

```
Profile toggle ON ──► HealthStore.requestAuthorization() ──► system auth sheet

Workout finishes ──► SwiftData save (source of truth)
                 └─► if healthSyncEnabled:
                       HealthStore.body() ─► CalorieEstimator ─► HealthStore.save()
                       └─► HKWorkout appears in Health app / Activity rings
```

## Project configuration (Xcode, not source)

Required before the build will run on device:

- Enable the **HealthKit** capability on the app target.
- Info.plist usage strings:
  - `NSHealthUpdateUsageDescription` — e.g. *"CrazyWork saves your completed
    workouts to Apple Health."*
  - `NSHealthShareUsageDescription` — e.g. *"CrazyWork reads your body metrics to
    estimate calories burned."*

These are applied in Xcode (or by editing the pbxproj/Info.plist directly if the
files are pointed out). They are not Swift source changes.

## Testing

- `CalorieEstimatorTests` (CrazyWork/Tests/): full MET formula with all
  characteristics; Mifflin-St Jeor difference by sex; weight-only fallback;
  no-data fallback (default weight). Matches existing pure-logic test style
  (e.g. `ProgressStatsTests`).
- `HealthStore` is left untested — device-bound HealthKit. Keeping it thin
  (no logic beyond HealthKit plumbing) is the mitigation.

## Decisions taken (defaults)

- Single `.functionalStrengthTraining` activity type for every session, including
  plank-heavy ones. Not branched to `.coreTraining`.
- Rest time is included in the active-minutes used for calories
  (`ponytail:`-marked simplification).
