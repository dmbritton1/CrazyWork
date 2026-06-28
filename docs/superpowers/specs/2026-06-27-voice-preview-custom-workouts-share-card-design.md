# Voice Preview, Custom Workouts, Share Card

**Date:** 2026-06-27
**Status:** Approved design

Three small, independent features bundled into one spec. Each can be built and
shipped on its own; they share no code.

---

## Feature 1 — Voice preview button

### Goal

Let the user hear the currently-selected voice before committing to it, from
Profile → Settings.

### Component — `CrazyWork/Sources/Views/ProfileView.swift`

Add a **"Preview voice"** button row inside the existing `Section("Settings")`,
immediately after the `Picker("Voice", …)`.

- The view holds one synthesizer: `@State private var previewSynth = AVSpeechSynthesizer()`.
- On tap, speak a short sample using the same voice-resolution logic the player
  uses, and configure the audio session for playback so it is audible even on
  silent mode:

```swift
            Button {
                previewVoice()
            } label: {
                Label("Preview voice", systemImage: "speaker.wave.2.fill")
            }
```

```swift
    @State private var previewSynth = AVSpeechSynthesizer()

    private func previewVoice() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: "Three. Nice work!")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        }
        previewSynth.speak(utterance)
    }
```

(`voiceID` is the existing `@AppStorage("voiceID")` property; `ProfileView`
already imports `AVFoundation`.)

### Testing

None — a button that resolves a voice and speaks. Verified by build + manual:
pick a voice, tap Preview, hear the sample in that voice.

---

## Feature 2 — Custom workout builder (saved to disk)

### Goal

Let the user save the workout they built and reload it later, alongside the
premade plans.

### Decisions

- Saved workouts appear in a **"My Workouts"** section above the premade plans
  in the Plans tab and load into the builder via the existing `onChoose` flow.
- Editing is **save-new + delete** only: no in-place overwrite or rename. To
  change a saved workout, load it, tweak it, save it again under a new name,
  and delete the old one.

### Component A — `WorkoutEntry` becomes `Codable` (`CrazyWork/Sources/Session/WorkoutEntry.swift`)

So SwiftData can persist `[WorkoutEntry]` directly as a stored attribute (no
child model). Change the declaration to:

```swift
struct WorkoutEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    var exerciseID: String
    var sets: Int
    var target: Int
}
```

(`id` changes from `let` to `var` so the synthesized `Codable` round-trips the
stable id; nothing mutates it.)

### Component B — `SavedWorkout` model (new: `CrazyWork/Sources/Persistence/SavedWorkout.swift`)

```swift
import Foundation
import SwiftData

@Model
final class SavedWorkout {
    var name: String
    var restSeconds: Int
    var createdAt: Date
    var entries: [WorkoutEntry]

    init(name: String, restSeconds: Int, entries: [WorkoutEntry]) {
        self.name = name
        self.restSeconds = restSeconds
        self.createdAt = Date()
        self.entries = entries
    }
}

extension SavedWorkout {
    /// View as a `PremadePlan` so the Plans tab can render + estimate it with
    /// the existing card UI and load it through the same `onChoose` flow.
    var asPlan: PremadePlan {
        PremadePlan(id: "saved-\(persistentModelID.hashValue)",
                    name: name,
                    summary: "Custom workout",
                    entries: entries,
                    restSeconds: restSeconds)
    }
}
```

### Component C — register the model (`CrazyWork/Sources/App/CrazyWorkApp.swift`)

```swift
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self, SavedWorkout.self])
```

### Component D — save from the builder (`CrazyWork/Sources/Views/BuildWorkoutView.swift`)

Add a model context, a name-prompt alert, and a "Save workout" row.

- `@Environment(\.modelContext) private var modelContext`
- `@State private var showingSavePrompt = false`
- `@State private var newName = ""`

Add a section (above or below "Rest between sets"):

```swift
                Section {
                    Button("Save workout") { showingSavePrompt = true }
                        .disabled(entries.isEmpty)
                }
```

Attach the alert as a modifier on the `List`:

```swift
            .alert("Save workout", isPresented: $showingSavePrompt) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Save") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    modelContext.insert(SavedWorkout(name: name, restSeconds: restSeconds, entries: entries))
                    newName = ""
                }
            } message: {
                Text("Save this workout to load again later.")
            }
```

### Component E — load + delete from Plans (`CrazyWork/Sources/Views/PremadePlansView.swift`)

Add `@Environment(\.modelContext) private var modelContext` and
`@Query(sort: \SavedWorkout.createdAt, order: .reverse) private var saved: [SavedWorkout]`.

Restructure the `List` into two sections:

```swift
            List {
                if !saved.isEmpty {
                    Section("My Workouts") {
                        ForEach(saved) { workout in
                            Button { onChoose(workout.asPlan) } label: { card(workout.asPlan) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(saved[i]) }
                        }
                    }
                }
                Section("Plans") {
                    ForEach(PremadePlanCatalog.all) { plan in
                        Button { onChoose(plan) } label: { card(plan) }
                            .buttonStyle(.plain)
                    }
                }
            }
```

`card`, `timeText`, `exerciseSummary`, and the `onChoose` closure are unchanged.
`SavedWorkout.asPlan` carries `entries` + `restSeconds`, so `RootView`'s
existing `onChoose` (sets `entries` / `restSeconds`, switches to the Workout
tab) loads a saved workout exactly like a premade one.

### Testing

One small test (`CrazyWork/Tests/SavedWorkoutTests.swift` or alongside existing
session tests) covering the only non-trivial logic:

- `WorkoutEntry` Codable round-trip: encode `[WorkoutEntry]`, decode, assert
  equality (id, exerciseID, sets, target preserved).
- `SavedWorkout.asPlan` maps `name`/`restSeconds`/`entries` through unchanged.

The SwiftData insert/query/delete and the alert UI are verified by build +
manual: build a workout, Save with a name, see it under "My Workouts", tap to
load it into the builder, swipe to delete.

---

## Feature 3 — Share workout summary card

### Goal

From the post-workout Summary screen, share a clean image card of the workout.

### Component A — `WorkoutShareCard` (new: `CrazyWork/Sources/Views/WorkoutShareCard.swift`)

A compact, self-contained card view (fixed width, e.g. 340pt) rendered to an
image — not shown inline in the app. Content:

- "CrazyWork" wordmark + the date.
- The exercise list (distinct exercise display names, joined with " · ").
- **Total reps**, **total hold seconds** (formatted `m:ss` via
  `LiveWorkoutView.clock`), and **average form %**.

```swift
import SwiftUI
import ChallengeCore

struct WorkoutShareCard: View {
    let date: Date
    let exercises: String      // "Push-up · Squat · Plank"
    let totalReps: Int
    let totalHoldSeconds: Double
    let averageFormPct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CrazyWork").font(.headline.bold())
                Spacer()
                Text(date, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(exercises).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                stat("\(totalReps)", "reps")
                stat(LiveWorkoutView.clock(totalHoldSeconds), "held")
                stat("\(averageFormPct)%", "form")
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
```

### Component B — share from Summary (`CrazyWork/Sources/Views/SummaryView.swift`)

Compute the card totals from `results`, render the card to an `Image` with
`ImageRenderer`, and offer it via `ShareLink` beside the Done button.

- Totals:
  - `totalReps` = sum of `completed` for `goalUnit == .reps`.
  - `totalHoldSeconds` = sum of `completed` for `goalUnit == .seconds`.
  - `averageFormPct` = mean of `averageFormScore` over sets with `completed > 0`,
    `× 100`, rounded (0 when none).
  - `exercises` = distinct `displayName(for:)` in first-seen order, joined `" · "`.
- Render once on demand:

```swift
    @MainActor private func shareImage() -> Image? {
        let renderer = ImageRenderer(content: WorkoutShareCard(
            date: Date(), exercises: exercisesText,
            totalReps: totalReps, totalHoldSeconds: totalHoldSeconds,
            averageFormPct: averageFormPct))
        renderer.scale = UIScreen.main.scale
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
```

- Place the share control above/next to Done:

```swift
                if let image = shareImage() {
                    ShareLink(item: image,
                              preview: SharePreview("My CrazyWork workout", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                }
```

### Testing

None beyond build + manual — pure layout + a `ShareLink`. The totals math is
the same kind already exercised by `WorkoutSession.totalReps` /
`totalHoldSeconds`; no new test. Manual: finish a workout, tap Share, confirm
the image card shows the right totals.

---

## Out of scope (YAGNI)

- Voice rate/pitch controls; multiple sample phrases.
- Overwrite/rename of saved workouts; folders/tags; reordering.
- Sharing from History (no history detail view exists); custom share text,
  multiple card styles, streak/per-set breakdown on the card.
