import Foundation
import HealthKit
import Observation

/// Runs the real workout session on the watch: collects heart rate and active
/// energy via HKLiveWorkoutBuilder, mirrors the session to the phone, and
/// streams metric snapshots over the mirrored data channel.
@MainActor
@Observable
final class WatchSessionController: NSObject {
    static let shared = WatchSessionController()

    private(set) var heartRate: Double?
    private(set) var isRunning = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func begin(with config: HKWorkoutConfiguration) async {
        guard !isRunning else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate),
                                       HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: read)
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                         workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            // Store before the throwing starts so the catch's end() can
            // actually stop a session that already began activity.
            self.session = session
            self.builder = builder
            try await session.startMirroringToCompanionDevice()
            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
            isRunning = true
        } catch {
            // Watch-side failure is non-fatal by design; phone continues alone.
            end()
        }
    }

    /// Stop collecting, save the workout (rings credit, measured calories),
    /// and tell the phone the measured total via `.ended`.
    func end() {
        session?.stopActivity(with: Date())
        session?.end()
        let session = session
        let builder = builder
        Task { @MainActor in
            try? await builder?.endCollection(at: Date())
            // Mirror WorkoutSaveOwner: the watch saves only when it measured
            // energy AND the save succeeded; otherwise discard and ack 0 so
            // the phone writes its estimate. Ack kcal > 0 == "I saved".
            let measured = builder?.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0
            var kcal = 0.0
            if measured > 0, let workout = try? await builder?.finishWorkout() {
                kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?
                    .doubleValue(for: .kilocalorie()) ?? measured
            } else {
                builder?.discardWorkout()
            }
            if let session, let data = try? WatchMessage.ended(activeEnergyKcal: kcal).encoded() {
                session.sendToRemoteWorkoutSession(data: data) { _, _ in }
            }
        }
        self.session = nil
        self.builder = nil
        isRunning = false
        heartRate = nil
    }

    private func send(_ message: WatchMessage) {
        guard let session, let data = try? message.encoded() else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    /// Pull the latest statistics out of the builder and mirror them over.
    private func publishMetrics() {
        guard let builder else { return }
        let hr = builder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let kcal = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
        if let hr { heartRate = hr }
        send(.metrics(heartRate: hr ?? heartRate ?? 0, activeEnergyKcal: kcal))
    }
}

extension WatchSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.publishMetrics() }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {
        Task { @MainActor in self.end() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for item in data {
                guard let message = try? WatchMessage.decode(item) else { continue }
                if case .end = message { self.end() }
            }
        }
    }
}
