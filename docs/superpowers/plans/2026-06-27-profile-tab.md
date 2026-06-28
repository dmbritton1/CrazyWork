# Profile Tab + Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Profile tab with an editable name + lifetime summary header and two settings — a Sound & voice toggle and a System/Light/Dark appearance picker.

**Architecture:** `@AppStorage`-backed settings, no new persistence model. Appearance applies via `.preferredColorScheme` at the `RootView` `TabView`. The header reuses the existing pure `ProgressStats`; a shared `WorkoutSession.summary` mapping removes the duplication with `StatsView`.

**Tech Stack:** Swift 6, SwiftUI (`Form`, `@AppStorage`, `.preferredColorScheme`), SwiftData (`@Query`). Build on iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`. XcodeGen auto-discovers files under `Sources/` on `xcodegen generate` in `CrazyWork/`.

## Global Constraints

- Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).
- Persisted keys: `workoutAudioEnabled` (existing, Bool, default true), `appearance` (new, `AppearanceMode` String, default `system`), `displayName` (new, String, default "Athlete").
- No new unit tests — the only new logic is a trivial enum switch; verify by build + the existing suite staying green.

> **Spec:** `docs/superpowers/specs/2026-06-27-profile-tab-design.md`

---

### Task 1: Shared `WorkoutSession.summary` mapping

**Files:**
- Modify: `CrazyWork/Sources/Session/ProgressStats.swift` (append an extension)
- Modify: `CrazyWork/Sources/Views/StatsView.swift` (use it)

**Interfaces:**
- Consumes: existing `SessionSummary(date:reps:holdSeconds:formScore:duration:)`, `WorkoutSession` (`startedAt`, `endedAt`, `totalReps`, `totalHoldSeconds`, `averageFormScore`).
- Produces: `WorkoutSession.summary -> SessionSummary` for Task 2 and `StatsView`.

- [ ] **Step 1: Add the extension**

Append to `CrazyWork/Sources/Session/ProgressStats.swift`:

```swift

extension WorkoutSession {
    /// This session reduced to the value type the stats math consumes.
    var summary: SessionSummary {
        SessionSummary(date: startedAt,
                       reps: totalReps,
                       holdSeconds: totalHoldSeconds,
                       formScore: averageFormScore,
                       duration: (endedAt ?? startedAt).timeIntervalSince(startedAt))
    }
}
```

- [ ] **Step 2: Use it in `StatsView`**

In `CrazyWork/Sources/Views/StatsView.swift`, replace the `stats` computed property:

```swift
    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map { session in
            SessionSummary(date: session.startedAt,
                           reps: session.totalReps,
                           holdSeconds: session.totalHoldSeconds,
                           formScore: session.averageFormScore,
                           duration: (session.endedAt ?? session.startedAt).timeIntervalSince(session.startedAt))
        })
    }
```

with:

```swift
    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }
```

- [ ] **Step 3: Verify (build + existing tests green, StatsView unchanged behavior)**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild test -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: `** TEST SUCCEEDED **` (no behavior change; `ProgressStats` tests still pass).

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Session/ProgressStats.swift CrazyWork/Sources/Views/StatsView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "refactor: share WorkoutSession.summary mapping with StatsView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Profile tab, settings, and appearance

**Files:**
- Create: `CrazyWork/Sources/Views/ProfileView.swift` (`AppearanceMode` + `ProfileView`)
- Modify: `CrazyWork/Sources/Views/RootView.swift` (Profile tab + `.preferredColorScheme`)

**Interfaces:**
- Consumes: `WorkoutSession.summary` (Task 1), `ProgressStats(summaries:)`, `@AppStorage` keys from Global Constraints.
- Produces: `AppearanceMode` enum (`system`/`light`/`dark`, `var colorScheme: ColorScheme?`), `ProfileView`, and a `Tab.profile` case.

- [ ] **Step 1: Create `ProfileView.swift` (enum + view)**

Create `CrazyWork/Sources/Views/ProfileView.swift`:

```swift
import SwiftUI
import SwiftData

/// App appearance preference, persisted via `@AppStorage` (String-backed).
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The Profile tab: an editable name, a quick lifetime summary, and the app's
/// settings (sound & voice, appearance).
struct ProfileView: View {
    @AppStorage("displayName") private var displayName = "Athlete"
    @AppStorage("workoutAudioEnabled") private var audioEnabled = true
    @AppStorage("appearance") private var appearance = AppearanceMode.system
    @Query private var sessions: [WorkoutSession]

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
                    .font(.title3.weight(.semibold))
                HStack {
                    stat("Workouts", "\(stats.totalWorkouts)")
                    Spacer()
                    stat("Streak", "\(stats.currentStreak)d")
                }
            }
            Section("Settings") {
                Toggle("Sound & voice", isOn: $audioEnabled)
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        }
        .navigationTitle("Profile")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Add the Profile tab and apply appearance in `RootView`**

In `CrazyWork/Sources/Views/RootView.swift`:

Add an appearance storage property after `@State private var selection: Tab = .workout`:
```swift
    @AppStorage("appearance") private var appearance = AppearanceMode.system
```

Add the `profile` case to the `Tab` enum:
```swift
    private enum Tab { case workout, plans, stats, history, profile }
```

Add the Profile tab immediately AFTER the History `NavigationStack { HistoryView() } … .tag(Tab.history)` block (so it is the last tab):
```swift
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
```

Apply the color scheme to the `TabView` — change the closing of the `TabView` from:
```swift
        }
    }
}
```
to:
```swift
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}
```
(The `.preferredColorScheme` modifier goes on the `TabView`, after its trailing closure.)

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Views/ProfileView.swift CrazyWork/Sources/Views/RootView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: Profile tab with name, lifetime summary, audio + appearance settings

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

Confirm: a 5th "Profile" tab; editing the name persists; the Workouts/Streak counts match the Stats tab; the "Sound & voice" toggle is in sync with the live-HUD mute (flip one, the other follows); the Appearance picker re-themes the whole app immediately (System / Light / Dark) and the choice survives relaunch.

- [ ] **Step 3: Push**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git push
```

---

## Self-Review Notes

- **Spec coverage:** `AppearanceMode` + `.preferredColorScheme` (Task 2); Profile tab (Task 2); header name + lifetime summary (Task 2); Sound & voice toggle on the existing key (Task 2); shared `WorkoutSession.summary` used by both StatsView and ProfileView (Task 1). All spec sections map to a task.
- **Build stays green:** Task 1 is a behavior-preserving refactor (existing tests cover it); Task 2 adds new files + a tab.
- **Type consistency:** `WorkoutSession.summary`, `AppearanceMode` (+ `.colorScheme`/`.label`), `Tab.profile`, and the three `@AppStorage` keys are used identically across tasks.
- **`@AppStorage` enum:** `AppearanceMode` is `String`-backed `RawRepresentable`, which `@AppStorage` supports directly.
