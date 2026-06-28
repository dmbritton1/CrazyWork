# Voice Setting

**Date:** 2026-06-27
**Status:** Approved design

## Goal

Let the user choose which voice speaks the workout cues (rep counts, form
warnings, transitions), from the native iOS system voices.

## Context / decision

The app already uses `AVSpeechSynthesizer` (in `WorkoutAudioPlayer`). The
referenced `jamiepine/voicebox` repo is a desktop/server AI voice-cloning studio
(Tauri + Python + Docker), not an iOS library and not on-device — out of scope.
"Change the voice" is delivered natively with `AVSpeechSynthesisVoice`: iOS ships
many system voices, and users can add more in Settings → Accessibility → Spoken
Content. Zero dependencies, on-device.

## Storage key

- `voiceID` — String, default `""` (empty = system default voice). The value is
  an `AVSpeechSynthesisVoice.identifier`.

## Components

### 1. Player applies the voice — `CrazyWork/Sources/Audio/WorkoutAudioPlayer.swift`

`WorkoutAudioPlayer` is a plain `@MainActor` class (not a SwiftUI View), so it
reads `UserDefaults.standard` directly (the same store `@AppStorage` writes to).
In the `.speak(text)` case, after creating the utterance, set its voice when a
stored id resolves:

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

Read per-utterance (cheap) so a change in Profile takes effect on the next
workout. When `voiceID` is empty or doesn't resolve, the synthesizer uses its
default voice (unchanged behavior).

### 2. Voice picker — `CrazyWork/Sources/Views/ProfileView.swift`

Add `@AppStorage("voiceID") private var voiceID = ""`.

In the "Settings" `Section` (after the Appearance picker), add a **"Voice"**
`Picker` bound to `$voiceID`:

- A first row "Default" tagged `""`.
- One row per available voice: `Text("\(voice.name) (\(voice.language))").tag(voice.identifier)`.

The available voices come from a computed helper on the view:

```swift
    private var voices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let matched = all.filter { $0.language.hasPrefix(lang) }
        return (matched.isEmpty ? all : matched).sorted { $0.name < $1.name }
    }
```

(`ProfileView` imports `AVFoundation` for `AVSpeechSynthesisVoice`.)

## Testing

No unit test — the only logic is a `UserDefaults` read, an `AVFoundation` call,
and a trivial language filter; none is meaningfully unit-testable. Verified by
build + manual: pick a voice in Profile, start a workout, hear the rep counts in
that voice; "Default" restores the system voice.

## Out of scope (YAGNI)

- Speech rate / pitch controls.
- A per-voice preview/sample button.
- AI / cloned voices (the voicebox feature) — a separate, server-backed project.
