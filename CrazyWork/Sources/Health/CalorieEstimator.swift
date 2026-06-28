import Foundation
import ChallengeCore

/// Body metrics read from Health, all optional — the estimator degrades gracefully.
struct BodyCharacteristics {
    var weightKg: Double?
    var heightCm: Double?
    var ageYears: Int?
    var isMale: Bool?
}

/// Pure calorie math. MET method on a Mifflin-St Jeor BMR base when full
/// characteristics are available; weight-only fallback otherwise.
enum CalorieEstimator {
    static let defaultWeightKg = 70.0
    static let defaultMET = 3.5

    /// Active energy (kcal) for a finished session.
    static func kilocalories(results: [SessionCoordinator.SetResult],
                             durationMinutes: Double,
                             body: BodyCharacteristics) -> Double {
        guard durationMinutes > 0, !results.isEmpty else { return 0 }
        // ponytail: rest time counts as active; add per-set timing if accuracy matters.
        let mets = results.map { ExerciseRegistry.definition(for: $0.exerciseID)?.met ?? defaultMET }
        let met = mets.reduce(0, +) / Double(mets.count)
        let weight = body.weightKg ?? defaultWeightKg

        if let h = body.heightCm, let age = body.ageYears, let male = body.isMale {
            let bmr = 10 * weight + 6.25 * h - 5 * Double(age) + (male ? 5 : -161)
            return met * (bmr / 1440) * durationMinutes
        }
        // Weight-only classic MET formula.
        return met * 3.5 * weight / 200 * durationMinutes
    }
}
