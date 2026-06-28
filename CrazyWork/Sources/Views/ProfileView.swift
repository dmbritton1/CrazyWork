import SwiftUI
import SwiftData
import AVFoundation
import HealthKit

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
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false
    @Query private var sessions: [WorkoutSession]
    @State private var previewSynth = AVSpeechSynthesizer()
    @State private var speechEnder = SpeechSessionEnder()
    /// Loaded off the first render — enumerating system voices synchronously in
    /// `body` (as a `.menu` Picker does outside a Form) blanks the launch frame.
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HeroStripeBand {
                        Text("Profile").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                    }
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerCard
                        settingsCard
                        if HKHealthStore.isHealthDataAvailable() { healthCard }
                        HealthMetricsCard()
                        poseOverlayCard
                    }
                    .padding(.horizontal, Spacing.lg)
                }
                .padding(.bottom, Spacing.lg)
            }
            .tint(Palette.brandRed)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if availableVoices.isEmpty { availableVoices = Self.loadVoices() } }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TextField("Name", text: $displayName)
                .typography(Typography.headingMd).foregroundStyle(Palette.ink)
            HStack {
                stat("Workouts", "\(stats.totalWorkouts)")
                Spacer()
                stat("Streak", "\(stats.currentStreak)d", accent: true)
            }
        }
        .card()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("SETTINGS")
            Toggle("Sound & voice", isOn: $audioEnabled)
                .typography(Typography.bodyMd).foregroundStyle(Palette.ink)
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Picker("Voice", selection: $voiceID) {
                Text("Default").tag("")
                ForEach(availableVoices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                }
            }
            .tint(Palette.body)
            Button { previewVoice() } label: {
                Label("Preview voice", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(TertiaryButtonStyle())
        }
        .card()
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("APPLE HEALTH")
            Toggle("Connect Apple Health", isOn: $healthSyncEnabled)
                .typography(Typography.bodyMd).foregroundStyle(Palette.ink)
                .onChange(of: healthSyncEnabled) { _, isOn in
                    if isOn { Task { try? await HealthStore.shared.requestAuthorization() } }
                }
        }
        .card()
    }

    private var poseOverlayCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("POSE OVERLAY")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(OverlayPreset.all) { preset in
                        PillTab(title: preset.id, isActive: false) { apply(preset) }
                    }
                }
            }
            Picker("Color", selection: $skeletonColor) {
                ForEach(SkeletonColor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .tint(Palette.body)
            Picker("Thickness", selection: $skeletonThickness) {
                ForEach(SkeletonThickness.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .tint(Palette.body)
            Toggle("Show joints", isOn: $skeletonShowJoints)
                .typography(Typography.bodyMd).foregroundStyle(Palette.ink)
            Toggle("Show skeleton", isOn: $skeletonShowSkeleton)
                .typography(Typography.bodyMd).foregroundStyle(Palette.ink)
        }
        .card()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
    }

    private static func loadVoices() -> [AVSpeechSynthesisVoice] {
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

    private func stat(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).typography(Typography.headingXl)
                .foregroundStyle(accent ? Palette.brandRed : Palette.ink)
            Text(title).typography(Typography.captionSm).foregroundStyle(Palette.mute)
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
