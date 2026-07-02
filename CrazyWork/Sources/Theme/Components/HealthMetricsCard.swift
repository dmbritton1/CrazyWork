import SwiftUI
import HealthKit

/// Shows the body metrics CrazyWork pulls from Apple Health (weight/height/age/sex).
/// Self-gating: renders nothing unless Health is connected and available.
struct HealthMetricsCard: View {
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false
    @State private var metrics: BodyCharacteristics?

    var body: some View {
        if healthSyncEnabled && HKHealthStore.isHealthDataAvailable() {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("FROM APPLE HEALTH").typography(Typography.bodySmStrong)
                    .foregroundStyle(Palette.mute)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.md) {
                    tile("Weight", Self.weightText(metrics?.weightKg))
                    tile("Height", Self.heightText(metrics?.heightCm))
                    tile("Age", metrics?.ageYears.map { "\($0)" } ?? "—")
                    tile("Sex", Self.sexText(metrics?.isMale))
                }
            }
            .card()
            .task { metrics = await HealthStore.shared.body() }
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).font(Typography.numeral(24)).foregroundStyle(Palette.ink)
            Text(title).typography(Typography.captionSm).foregroundStyle(Palette.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func weightText(_ kg: Double?) -> String { kg.map { "\(Int($0.rounded())) kg" } ?? "—" }
    static func heightText(_ cm: Double?) -> String { cm.map { "\(Int($0.rounded())) cm" } ?? "—" }
    static func sexText(_ isMale: Bool?) -> String {
        switch isMale { case true: return "Male"; case false: return "Female"; default: return "—" }
    }
}
