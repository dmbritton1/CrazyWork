import Foundation
import HealthKit
import Observation

/// Phone side of the mirrored watch workout session. Launches the watch app,
/// adopts the mirrored session, decodes incoming metric messages, and offers
/// a fire-and-forget send channel. Every failure lands in `.unavailable`,
/// which callers treat as "no watch" — never as an error to surface.
@MainActor
@Observable
final class WatchWorkoutMirror: NSObject {
    enum State { case idle, starting, mirroring, unavailable }

    private(set) var state: State = .idle
    private(set) var latestHeartRate: Double?
    private(set) var watchActiveEnergyKcal: Double?
    /// Set when the watch sends `.ended` — its measured total after saving.
    private(set) var watchEndedEnergyKcal: Double?
    /// Fired on the main actor when the wrist issues a command. Set by the
    /// live workout flow; nil drops controls (e.g. after the view is gone).
    var onControl: ((WatchControl) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var endAcknowledgement: CheckedContinuation<Void, Never>?
    private var endTask: Task<Bool, Never>?

    func start() async {
        guard state == .idle, HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        state = .starting
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        do {
            try await store.startWatchApp(toHandle: config)
        } catch {
            state = .unavailable // no watch, app missing, auth denied — all fine
        }
    }

    func send(_ message: WatchMessage) {
        guard state == .mirroring, let session,
              let data = try? message.encoded() else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    /// Ask the watch to finish. Returns true if it acknowledged with `.ended`
    /// within 5 seconds (then `watchEndedEnergyKcal` holds measured energy).
    /// Re-entrant-safe: the natural-finish path and `.onDisappear` both call
    /// this, so concurrent callers share one in-flight end and one result —
    /// the watch is told to finish once, and no caller's `await` is orphaned
    /// (a naive re-entry guard would return a false ack to the save path and
    /// double-write the workout to HealthKit).
    func end() async -> Bool {
        if let endTask { return await endTask.value }
        guard state == .mirroring else { return false }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            self.send(.end)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.endAcknowledgement = cont
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    self?.resumeEndAcknowledgement()
                }
            }
            self.state = .idle
            self.session = nil
            return self.watchEndedEnergyKcal != nil
        }
        endTask = task
        let result = await task.value
        endTask = nil
        return result
    }

    private func adopt(_ session: HKWorkoutSession) {
        session.delegate = self
        self.session = session
        state = .mirroring
    }

    private func resumeEndAcknowledgement() {
        endAcknowledgement?.resume()
        endAcknowledgement = nil
    }

    private func handle(_ message: WatchMessage) {
        switch message {
        case let .metrics(heartRate, activeEnergyKcal):
            if heartRate > 0 { latestHeartRate = heartRate }
            watchActiveEnergyKcal = activeEnergyKcal
        case let .ended(activeEnergyKcal):
            watchEndedEnergyKcal = activeEnergyKcal
            resumeEndAcknowledgement()
        case let .control(control):
            onControl?(control)
        case .progress, .haptic, .end:
            break // phone → watch messages; ignore if echoed back
        }
    }
}

extension WatchWorkoutMirror: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {
        Task { @MainActor in
            self.state = .unavailable
            self.resumeEndAcknowledgement()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for item in data {
                if let message = try? WatchMessage.decode(item) { self.handle(message) }
            }
        }
    }
}
