import SwiftUI
import SwiftData
import AVFoundation

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
    @AppStorage("skeletonColor") private var skeletonColor = SkeletonColor.green
    @AppStorage("skeletonThickness") private var skeletonThickness = SkeletonThickness.medium
    @AppStorage("skeletonShowJoints") private var skeletonShowJoints = true
    @AppStorage("skeletonShowSkeleton") private var skeletonShowSkeleton = true
    @AppStorage("voiceID") private var voiceID = ""
    @Query private var sessions: [WorkoutSession]
    @State private var previewSynth = AVSpeechSynthesizer()
    @State private var speechEnder = SpeechSessionEnder()

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
                Picker("Voice", selection: $voiceID) {
                    Text("Default").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                Button {
                    previewVoice()
                } label: {
                    Label("Preview voice", systemImage: "speaker.wave.2.fill")
                }
            }
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
        }
        .navigationTitle("Profile")
    }

    private var voices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let matched = all.filter { $0.language.hasPrefix(lang) }
        return (matched.isEmpty ? all : matched).sorted { $0.name < $1.name }
    }

    private func apply(_ preset: OverlayPreset) {
        skeletonColor = preset.color
        skeletonThickness = preset.thickness
        skeletonShowJoints = preset.showJoints
        skeletonShowSkeleton = preset.showSkeleton
    }

    private func previewVoice() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        previewSynth.delegate = speechEnder
        let utterance = AVSpeechUtterance(string: "Three. Nice work!")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        }
        previewSynth.speak(utterance)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Releases the audio session once a voice preview finishes, so other apps'
/// audio stops being ducked the moment the sample ends.
private final class SpeechSessionEnder: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
