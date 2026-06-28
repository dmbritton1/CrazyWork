import Foundation
import AVFoundation
import AudioToolbox

/// Executes `AudioAction`s: TTS via a shared speech synthesizer and SFX via
/// built-in iOS system sounds. Owns a `WorkoutAudioCoach` and a `.playback`
/// audio session that ducks the user's music while sounds play. Used on the
/// main thread only. System sound IDs are tunable — swap freely on device.
@MainActor
final class WorkoutAudioPlayer {
    /// When true, every action is a no-op (the in-workout mute toggle).
    var muted = false

    private var coach = WorkoutAudioCoach()
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive = false

    // Built-in iOS system sound IDs (see iphonedevwiki AudioServices list).
    private let tickSound: SystemSoundID = 1104      // keyboard "Tock"
    private let chimeSound: SystemSoundID = 1025      // short completion
    private let restBeepSound: SystemSoundID = 1113   // "Begin Record"
    private let fanfareSound: SystemSoundID = 1407    // upbeat flourish

    /// Translate one workout event into sound. Drains the coach.
    func handle(_ event: WorkoutEvent) {
        for action in coach.handle(event) { run(action) }
    }

    /// Stop speech and release the session so the user's music returns to full
    /// volume. Call when the live workout view goes away.
    func end() {
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }

    private func run(_ action: AudioAction) {
        guard !muted else { return }
        activateSessionIfNeeded()
        switch action {
        case .tick: AudioServicesPlaySystemSound(tickSound)
        case .chime: AudioServicesPlaySystemSound(chimeSound)
        case .restBeep: AudioServicesPlaySystemSound(restBeepSound)
        case .fanfare: AudioServicesPlaySystemSound(fanfareSound)
        case let .speak(text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            if let id = UserDefaults.standard.string(forKey: "voiceID"), !id.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: id) {
                utterance.voice = voice
            }
            synthesizer.speak(utterance)
        }
    }

    private func activateSessionIfNeeded() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .duckOthers)
        try? session.setActive(true)
        sessionActive = true
    }
}
