# Voice Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick which native iOS voice speaks the workout cues, via a Voice picker in Profile that the audio player honors.

**Architecture:** A `@AppStorage("voiceID")` String (an `AVSpeechSynthesisVoice.identifier`) chosen in `ProfileView`; `WorkoutAudioPlayer` reads it from `UserDefaults` per utterance and sets `utterance.voice`. Empty = system default. On-device, no dependencies.

**Tech Stack:** Swift 6, SwiftUI (`@AppStorage`, `Picker`), AVFoundation (`AVSpeechSynthesisVoice`). Build on iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`. XcodeGen: `xcodegen generate` in `CrazyWork/`.

## Global Constraints

- Git identity `dmbritton1` / `dacuber01@gmail.com`; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Do NOT push (controller pushes at the end).
- Storage key: `voiceID` — String, default `""` (empty = system default voice; otherwise an `AVSpeechSynthesisVoice.identifier`).
- No new unit tests — only logic is a `UserDefaults` read, an AVFoundation call, and a trivial language filter; verify by build + the existing suite staying green.

> **Spec:** `docs/superpowers/specs/2026-06-27-voice-setting-design.md`

---

### Task 1: Voice selection (player honors it + Profile picker)

**Files:**
- Modify: `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift`
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:**
- Produces/consumes the shared `@AppStorage`/`UserDefaults` key `"voiceID"` (String). No cross-file Swift symbols.

- [ ] **Step 1: Apply the chosen voice in the player**

In `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift`, in `run(_:)`, replace the
`.speak` case:

```swift
        case let .speak(text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
```

with:

```swift
        case let .speak(text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            if let id = UserDefaults.standard.string(forKey: "voiceID"), !id.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: id) {
                utterance.voice = voice
            }
            synthesizer.speak(utterance)
```

(`WorkoutAudioPlayer` already imports `AVFoundation`.)

- [ ] **Step 2: Add the voice storage + picker to `ProfileView`**

In `CrazyWork/Sources/Views/ProfileView.swift`:

(a) Add `import AVFoundation` at the top (after `import SwiftData`).

(b) Add the storage property next to the other `@AppStorage` declarations (after the four `skeleton…` keys):
```swift
    @AppStorage("voiceID") private var voiceID = ""
```

(c) Add the available-voices helper next to the existing private helpers (e.g. after `apply(_:)`):
```swift
    private var voices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let matched = all.filter { $0.language.hasPrefix(lang) }
        return (matched.isEmpty ? all : matched).sorted { $0.name < $1.name }
    }
```

(d) Add a "Voice" `Picker` inside the existing `Section("Settings") { … }`, immediately AFTER the `Picker("Appearance", …) { … }` block:
```swift
                Picker("Voice", selection: $voiceID) {
                    Text("Default").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
```

- [ ] **Step 3: Verify it builds**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild build -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' \
  -project CrazyWork.xcodeproj CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the app test suite (nothing regressed)**

Run:
```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodebuild test -scheme CrazyWork \
  -destination 'platform=iOS Simulator,name=iPhone 17' -project CrazyWork.xcodeproj \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -4
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git add CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift CrazyWork/Sources/Views/ProfileView.swift
git -c user.name="dmbritton1" -c user.email="dacuber01@gmail.com" commit -m "feat: choose the workout voice in Profile (native AVSpeechSynthesisVoice)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Manual verification + push

- [ ] **Step 1: Manual checklist (note for the user)**

In Profile → Settings → Voice: pick a non-default voice; start a workout and
confirm the rep counts / cues speak in that voice; switch back to "Default" and
confirm it returns to the system voice. (More voices can be added in iOS
Settings → Accessibility → Spoken Content and will appear in the list.)

- [ ] **Step 2: Push**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork && git push
```

---

## Self-Review Notes

- **Spec coverage:** `voiceID` storage (Task 1); player applies it per utterance with empty/unresolved → default (Task 1 Step 1); Profile "Voice" picker with "Default" + locale-filtered voices (Task 1 Step 2). All spec sections map to the task.
- **Placeholder scan:** none.
- **Type consistency:** the `"voiceID"` key string is identical in `WorkoutAudioPlayer` (`UserDefaults.standard.string(forKey:)`) and `ProfileView` (`@AppStorage`); both default to empty.
