import Foundation

/// Session phase mirrored to the watch (subset of SessionCoordinator.Phase).
enum SessionPhaseMessage: String, Codable, Sendable {
    case active, resting, finished
}

/// Haptic cues the phone asks the watch to play (used from phase 3 on).
enum HapticCue: String, Codable, Sendable {
    case countdown, setComplete, restOver, workoutComplete
}

/// Commands the wrist can issue against the running phone workout (phase 6).
enum WatchControl: String, Codable, Sendable {
    case skipRest, endWorkout
}

/// Everything that crosses the mirrored workout session's data channel,
/// in both directions. JSON-encoded; compiled into both app targets.
enum WatchMessage: Codable, Equatable, Sendable {
    /// Watch → phone: periodic sensor snapshot.
    case metrics(heartRate: Double, activeEnergyKcal: Double)
    /// Phone → watch: live workout state for the wrist display.
    case progress(exerciseName: String, value: Int, target: Int,
                  setIndex: Int, setCount: Int, phase: SessionPhaseMessage)
    /// Phone → watch: play a haptic.
    case haptic(HapticCue)
    /// Watch → phone: user tapped a control on the wrist.
    case control(WatchControl)
    /// Phone → watch: finish the session.
    case end
    /// Watch → phone: session finished and saved with this measured energy.
    case ended(activeEnergyKcal: Double)

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> WatchMessage {
        try JSONDecoder().decode(WatchMessage.self, from: data)
    }
}
