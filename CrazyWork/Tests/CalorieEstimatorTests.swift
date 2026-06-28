import XCTest
import ChallengeCore
@testable import CrazyWork

final class CalorieEstimatorTests: XCTestCase {
    private func set(_ id: String) -> SessionCoordinator.SetResult {
        SessionCoordinator.SetResult(exerciseID: id, goalUnit: .reps, target: 10,
                                     completed: 10, averageFormScore: 1, findingsSummary: [:])
    }

    func testFullCharacteristicsUsesBMR() {
        // squat MET 5.0, male 80kg 180cm 30yr.
        // BMR = 10*80 + 6.25*180 - 5*30 + 5 = 1780; /1440 = 1.2361 kcal/min
        // kcal = 5.0 * 1.2361 * 20 = 123.6
        let body = BodyCharacteristics(weightKg: 80, heightCm: 180, ageYears: 30, isMale: true)
        let kcal = CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 20, body: body)
        XCTAssertEqual(kcal, 123.6, accuracy: 0.5)
    }

    func testFemaleBMRLower() {
        let male = BodyCharacteristics(weightKg: 70, heightCm: 170, ageYears: 40, isMale: true)
        let female = BodyCharacteristics(weightKg: 70, heightCm: 170, ageYears: 40, isMale: false)
        let m = CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 30, body: male)
        let f = CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 30, body: female)
        XCTAssertGreaterThan(m, f)
    }

    func testWeightOnlyFallback() {
        // No height/age/sex -> MET * 3.5 * kg / 200 * min = 5.0*3.5*70/200*30 = 183.75
        let body = BodyCharacteristics(weightKg: 70, heightCm: nil, ageYears: nil, isMale: nil)
        let kcal = CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 30, body: body)
        XCTAssertEqual(kcal, 183.75, accuracy: 0.5)
    }

    func testNoDataUsesDefaultWeightAndStillPositive() {
        let kcal = CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 30,
                                                 body: BodyCharacteristics())
        XCTAssertGreaterThan(kcal, 0)
    }

    func testUnknownExerciseUsesDefaultMET() {
        let kcal = CalorieEstimator.kilocalories(results: [set("nope")], durationMinutes: 30,
                                                 body: BodyCharacteristics(weightKg: 70))
        XCTAssertGreaterThan(kcal, 0) // defaultMET keeps it finite/positive
    }

    func testZeroDurationIsZero() {
        XCTAssertEqual(CalorieEstimator.kilocalories(results: [set("squat")], durationMinutes: 0,
                                                     body: BodyCharacteristics(weightKg: 70)), 0)
    }
}
