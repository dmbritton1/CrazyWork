import Foundation
import HealthKit

/// Thin HealthKit wrapper. No business logic — math lives in CalorieEstimator.
@MainActor
final class HealthStore {
    static let shared = HealthStore()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKQuantityType(.height),
         HKQuantityType(.heartRate),
         HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex)]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [HKWorkoutType.workoutType()], read: readTypes)
    }

    /// Best-effort read of body metrics. Missing/denied values come back nil.
    func body() async -> BodyCharacteristics {
        guard isAvailable else { return BodyCharacteristics() }
        var b = BodyCharacteristics()
        b.weightKg = await latestValue(.bodyMass, unit: .gramUnit(with: .kilo))
        b.heightCm = await latestValue(.height, unit: .meterUnit(with: .centi))
        if let comps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: comps) {
            b.ageYears = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: b.isMale = true
            case .female: b.isMale = false
            default: break
            }
        }
        return b
    }

    /// Writes one functional-strength HKWorkout with an active-energy sample.
    func save(start: Date, end: Date, activeEnergyKcal: Double) async throws {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)
        if activeEnergyKcal > 0 {
            let energy = HKQuantity(unit: .kilocalorie(), doubleValue: activeEnergyKcal)
            let sample = HKCumulativeQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                    quantity: energy, start: start, end: end)
            try await builder.addSamples([sample])
        }
        try await builder.endCollection(at: end)
        try await builder.finishWorkout()
    }

    struct HeartRateSample: Equatable {
        let date: Date
        let bpm: Double
    }

    /// All heart-rate samples inside the interval, oldest first. Empty when
    /// unavailable/denied — callers hide their chart, never error.
    func heartRateSeries(start: Date, end: Date) async -> [HeartRateSample] {
        guard isAvailable else { return [] }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { (cont: CheckedContinuation<[HeartRateSample], Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let series = (samples as? [HKQuantitySample])?.map {
                    HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                } ?? []
                cont.resume(returning: series)
            }
            store.execute(q)
        }
    }

    /// Latest sample value for a quantity type, extracted to a Sendable Double
    /// inside the callback (no HKQuantity crosses actors).
    private func latestValue(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(id)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }
}
