import Foundation

/// One unit of audio output. Pure data — `WorkoutAudioPlayer` executes it.
enum AudioAction: Equatable {
    case tick        // short blip on a rep / plank milestone
    case chime       // set complete
    case restBeep    // entering rest
    case fanfare     // workout finished
    case speak(String) // TTS phrase
}
