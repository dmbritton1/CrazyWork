# Voice Preview, Custom Workouts, Share Card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three independent features to the CrazyWork iOS app: a voice-preview button in Profile, custom workouts saved to disk and reloadable from the Plans tab, and a shareable image card on the post-workout Summary screen.

**Architecture:** Native SwiftUI + AVFoundation + SwiftData throughout. The voice preview reuses the existing `voiceID` `@AppStorage` key. Custom workouts add one `@Model` (`SavedWorkout`) holding a `Codable` `[WorkoutEntry]`, surfaced through the existing `PremadePlan` card UI and `onChoose` flow. The share card renders a dedicated SwiftUI view to a `UIImage` via `ImageRenderer` and shares it through `ShareLink`.

**Tech Stack:** Swift 6, SwiftUI (`@AppStorage`, `@Query`, `@Environment(\.modelContext)`, `ImageRenderer`, `ShareLink`), AVFoundation (`AVSpeechSynthesizer`, `AVSpeechSynthesisVoice`, `AVAudioSession`), SwiftData (`@Model`), XCTest. Build on the iPhone 17 simulator; `.xcodeproj` is git-ignored and regenerated via `xcodegen generate` in `CrazyWork/`.

## Global Constraints

- Git identity `dmbritton1` / `dacuber01@gmail.com`; every commit ends with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).
- Storage key `voiceID` (String, existing) is reused as-is — do not rename.
- Saved-workout editing is **save-new + delete only** — no in-place overwrite or rename.
- The share card is reachable **only** from the Summary screen — do not add it to History.
- PONYTAIL: minimal, native-first; reuse existing helpers (`ExerciseRegistry`, `PremadePlan`, `LiveWorkoutView.clock`, the existing `card`/`onChoose` flow). Add no new dependencies and no scope beyond this plan.
- Tests are XCTest in `CrazyWork/Tests/` (`@testable import CrazyWork`), picked up automatically by the `CrazyWorkTests` bundle (`sources: [Tests]` in `CrazyWork/project.yml`).

> **Spec:** `docs/superpowers/specs/2026-06-27-voice-preview-custom-workouts-share-card-design.md`

### Build & test commands (used throughout)

Build:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

Test:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: `** TEST SUCCEEDED **`.

---

### Task 1: Voice preview button (Profile)

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:**
- Consumes: the existing `@AppStorage("voiceID") private var voiceID = ""` already declared in `ProfileView`.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Add the preview synthesizer + helper**

In `CrazyWork/Sources/Views/ProfileView.swift`, add a `@State` synthesizer next to the other `@AppStorage`/`@Query` properties (e.g. directly after `@Query private var sessions: [WorkoutSession]`):

```swift
    @State private var previewSynth = AVSpeechSynthesizer()
```

Add this helper alongside the existing private helpers (e.g. directly after the `apply(_:)` method):

```swift
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

(`ProfileView` already imports `AVFoundation`.)

- [ ] **Step 2: Add the button row under the Voice picker**

Inside the existing `Section("Settings")`, immediately AFTER the `Picker("Voice", selection: $voiceID) { … }` block, add:

```swift
                Button {
                    previewVoice()
                } label: {
                    Label("Preview voice", systemImage: "speaker.wave.2.fill")
                }
```

- [ ] **Step 3: Build**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the test suite (nothing regressed)**

Run the test command from Global Constraints. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/ProfileView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: preview the selected workout voice in Profile

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Custom-workout data layer (`WorkoutEntry` Codable + `SavedWorkout` model)

**Files:**
- Modify: `CrazyWork/Sources/Session/WorkoutEntry.swift`
- Create: `CrazyWork/Sources/Persistence/SavedWorkout.swift`
- Modify: `CrazyWork/Sources/App/CrazyWorkApp.swift`
- Create: `CrazyWork/Tests/SavedWorkoutTests.swift`

**Interfaces:**
- Consumes: `PremadePlan` (`init(id:name:summary:entries:restSeconds:)`) from `CrazyWork/Sources/Session/PremadePlan.swift`; `WorkoutEntry(exerciseID:sets:target:)` from `WorkoutEntry.swift`.
- Produces:
  - `WorkoutEntry: Codable` (now also `Codable`, `id` is `var`).
  - `final class SavedWorkout` with `init(name: String, restSeconds: Int, entries: [WorkoutEntry])`, stored `name: String`, `restSeconds: Int`, `createdAt: Date`, `entries: [WorkoutEntry]`, and computed `var asPlan: PremadePlan`.

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/SavedWorkoutTests.swift`:

```swift
import XCTest
import ChallengeCore
@testable import CrazyWork

final class SavedWorkoutTests: XCTestCase {
    func testWorkoutEntryCodableRoundTrips() throws {
        let entries = [
            WorkoutEntry(exerciseID: "pushup", sets: 3, target: 10),
            WorkoutEntry(exerciseID: "plank", sets: 2, target: 30),
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([WorkoutEntry].self, from: data)
        XCTAssertEqual(decoded, entries) // id, exerciseID, sets, target all preserved
    }

    func testAsPlanMapsFields() {
        let entries = [WorkoutEntry(exerciseID: "squat", sets: 4, target: 12)]
        let saved = SavedWorkout(name: "My Legs", restSeconds: 45, entries: entries)
        let plan = saved.asPlan
        XCTAssertEqual(plan.name, "My Legs")
        XCTAssertEqual(plan.restSeconds, 45)
        XCTAssertEqual(plan.entries, entries)
        XCTAssertEqual(plan.summary, "Custom workout")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: FAIL — `WorkoutEntry` is not `Codable` and `SavedWorkout` does not exist (compile error).

- [ ] **Step 3: Make `WorkoutEntry` Codable**

In `CrazyWork/Sources/Session/WorkoutEntry.swift`, change the struct declaration so `id` is a `var` and the type conforms to `Codable`:

```swift
struct WorkoutEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    var exerciseID: String
    var sets: Int
    var target: Int
}
```

(Only the first two lines change: `let id` → `var id`, and `Codable` is added to the conformance list. The rest of the file — the `WorkoutPlan.expand` enum — is unchanged.)

- [ ] **Step 4: Create the `SavedWorkout` model**

Create `CrazyWork/Sources/Persistence/SavedWorkout.swift`:

```swift
import Foundation
import SwiftData

/// A user-built workout saved to disk so it can be reloaded later from the
/// Plans tab. Stores the builder entries directly (`WorkoutEntry` is `Codable`).
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

- [ ] **Step 5: Register the model in the container**

In `CrazyWork/Sources/App/CrazyWorkApp.swift`, add `SavedWorkout.self` to the model container:

```swift
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self, SavedWorkout.self])
```

- [ ] **Step 6: Run the test to verify it passes**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Session/WorkoutEntry.swift CrazyWork/Sources/Persistence/SavedWorkout.swift CrazyWork/Sources/App/CrazyWorkApp.swift CrazyWork/Tests/SavedWorkoutTests.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: SavedWorkout model + Codable WorkoutEntry for custom workouts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Custom-workout UI (save in builder, load/delete in Plans)

**Files:**
- Modify: `CrazyWork/Sources/Views/BuildWorkoutView.swift`
- Modify: `CrazyWork/Sources/Views/PremadePlansView.swift`

**Interfaces:**
- Consumes: `SavedWorkout(name:restSeconds:entries:)` and `SavedWorkout.asPlan` from Task 2; the existing `onChoose: (PremadePlan) -> Void` closure and private `card(_:)` helper in `PremadePlansView`; the existing `@Binding var entries`/`@Binding var restSeconds` in `BuildWorkoutView`.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Add save state + context to the builder**

In `CrazyWork/Sources/Views/BuildWorkoutView.swift`, add these properties at the top of `BuildWorkoutView` (after the existing `@Binding var restSeconds: Int`):

```swift
    @Environment(\.modelContext) private var modelContext
    @State private var showingSavePrompt = false
    @State private var newName = ""
```

- [ ] **Step 2: Add the "Save workout" section**

In `BuildWorkoutView`'s `List`, add a new `Section` immediately AFTER the existing `Section("Rest between sets") { … }`:

```swift
                Section {
                    Button("Save workout") { showingSavePrompt = true }
                        .disabled(entries.isEmpty)
                }
```

- [ ] **Step 3: Add the name-prompt alert**

Attach this modifier to the `List` (place it directly after the existing `.navigationTitle("Build Workout")` line, before `.safeAreaInset(...)`):

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

- [ ] **Step 4: Build the builder changes**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Add query + context to the Plans view**

In `CrazyWork/Sources/Views/PremadePlansView.swift`, add `import SwiftData` at the top (after `import ChallengeCore`), and add these properties to `PremadePlansView` (after the existing `let onChoose: (PremadePlan) -> Void`):

```swift
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWorkout.createdAt, order: .reverse) private var saved: [SavedWorkout]
```

- [ ] **Step 6: Restructure the list into "My Workouts" + "Plans"**

Replace the existing `List(PremadePlanCatalog.all) { plan in … }` block (the whole `List(...) { … }` call inside the `NavigationStack`) with:

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
            .navigationTitle("Plans")
```

(The private `card(_:)`, `timeText(_:)`, and `exerciseSummary(_:)` helpers are unchanged.)

- [ ] **Step 7: Build the Plans changes**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Run the test suite (nothing regressed)**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/BuildWorkoutView.swift CrazyWork/Sources/Views/PremadePlansView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: save custom workouts and reload them from the Plans tab

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Shareable summary card

**Files:**
- Create: `CrazyWork/Sources/Views/WorkoutShareCard.swift`
- Modify: `CrazyWork/Sources/Views/SummaryView.swift`

**Interfaces:**
- Consumes: `SummaryView`'s existing `results: [SessionCoordinator.SetResult]` (each `SetResult` has `exerciseID: String`, `target: Int`, `completed: Double`, `goalUnit: GoalUnit`, `averageFormScore: Double`); `ExerciseRegistry.displayName(for:)`; `LiveWorkoutView.clock(_:)` (formats seconds as `m:ss`).
- Produces: `struct WorkoutShareCard` with `init(date:exercises:totalReps:totalHoldSeconds:averageFormPct:)`.

- [ ] **Step 1: Create the share card view**

Create `CrazyWork/Sources/Views/WorkoutShareCard.swift`:

```swift
import SwiftUI
import ChallengeCore

/// A compact, fixed-width card rendered to an image for sharing — not shown
/// inline in the app.
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

- [ ] **Step 2: Build to confirm the card compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Add the card totals + image render to `SummaryView`**

In `CrazyWork/Sources/Views/SummaryView.swift`, add these computed properties and the render helper inside `SummaryView` (e.g. after the existing `rows` computed property). They derive the card inputs from the existing `results`:

```swift
    private var totalReps: Int {
        results.filter { $0.goalUnit == .reps }.reduce(0) { $0 + Int($1.completed) }
    }

    private var totalHoldSeconds: Double {
        results.filter { $0.goalUnit == .seconds }.reduce(0) { $0 + $1.completed }
    }

    private var averageFormPct: Int {
        let scored = results.filter { $0.completed > 0 }
        guard !scored.isEmpty else { return 0 }
        let mean = scored.reduce(0.0) { $0 + $1.averageFormScore } / Double(scored.count)
        return Int((mean * 100).rounded())
    }

    private var exercisesText: String {
        var seen = Set<String>()
        var names: [String] = []
        for r in results {
            let name = ExerciseRegistry.displayName(for: r.exerciseID)
            if seen.insert(name).inserted { names.append(name) }
        }
        return names.joined(separator: " · ")
    }

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

- [ ] **Step 4: Add the ShareLink to the Summary body**

In `SummaryView`'s `body`, immediately BEFORE the existing `Button("Done") { dismiss() }`, add:

```swift
                if let image = shareImage() {
                    ShareLink(item: image,
                              preview: SharePreview("My CrazyWork workout", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                }
```

- [ ] **Step 5: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the test suite (nothing regressed)**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/WorkoutShareCard.swift CrazyWork/Sources/Views/SummaryView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: share a workout summary card from the Summary screen

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:**
  - Feature 1 (voice preview button) → Task 1 (synth + helper + button row, same voice-resolution as the player, `.playback` session).
  - Feature 2 (custom workouts) → Task 2 (`WorkoutEntry` Codable, `SavedWorkout` model + `asPlan`, container registration, the one small test) + Task 3 (save in builder, "My Workouts" load + swipe-delete in Plans).
  - Feature 3 (share card) → Task 4 (`WorkoutShareCard`, totals from `results`, `ImageRenderer` + `ShareLink` on Summary).
- **Placeholder scan:** none — every code step shows complete code.
- **Type consistency:** `SavedWorkout(name:restSeconds:entries:)` and `asPlan` are defined in Task 2 and consumed identically in Task 3; `WorkoutShareCard(date:exercises:totalReps:totalHoldSeconds:averageFormPct:)` is defined in Task 4 Step 1 and called with the same labels in Task 4 Step 3; `LiveWorkoutView.clock` is an existing static used by both `SummaryView` and the card. The `"voiceID"` key matches the existing player/`ProfileView` usage.
- **Ordering:** Task 2 (data + `asPlan`) precedes Task 3 (UI consuming them); Task 4 Step 1 (card) precedes Step 3 (which references `WorkoutShareCard`).
