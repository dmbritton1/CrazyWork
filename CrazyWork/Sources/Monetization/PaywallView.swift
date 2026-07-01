import SwiftUI
import StoreKit

/// The Pro paywall. Wraps Apple's native `SubscriptionStoreView`, which renders
/// the plan options, the purchase button, and the required Restore action. A
/// successful purchase flows through `Transaction.updates` into `Store.isPro`,
/// which dismisses this sheet.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: Store.proProductIDs.sorted()) {
            VStack(spacing: Spacing.sm) {
                Text("CrazyWork Pro")
                    .typography(Typography.displayLg).foregroundStyle(Palette.ink)
                Text("Unlock everything in CrazyWork.")
                    .typography(Typography.bodyMd).foregroundStyle(Palette.mute)
            }
            .multilineTextAlignment(.center)
            .padding(Spacing.lg)
        }
        .storeButton(.visible, for: .restorePurchases)   // App Store requires a restore path
        .subscriptionStoreControlStyle(.prominentPicker)
        .tint(Palette.brandRed)
        .onChange(of: store.isPro) { _, isPro in if isPro { dismiss() } }
    }
}
