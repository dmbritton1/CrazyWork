import Foundation
import StoreKit

/// A currently-held entitlement reduced to the fields that decide Pro access,
/// decoupled from StoreKit's `Transaction` so the access rule is pure & testable.
struct ProEntitlement: Equatable {
    let productID: String
    let expiration: Date?
    let revocationDate: Date?
}

/// Single source of truth for the Pro subscription entitlement. Created once at
/// app launch and injected into the SwiftUI environment.
@MainActor
@Observable
final class Store {
    /// The one canonical list of Pro product IDs. Must match App Store Connect
    /// and `Products.storekit`.
    static let proProductIDs: Set<String> = [
        "com.crazywork.pro.monthly",
        "com.crazywork.pro.yearly",
    ]

    private(set) var isPro = false
    // Not UI state, so exclude it from observation; nonisolated(unsafe) then lets
    // the nonisolated deinit cancel it. Safe: only init writes it, once.
    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init() {
        // React to renewals, refunds, revocations, Family Sharing changes.
        // ponytail: we don't finish() transactions — this is a read-only
        // entitlement model driven purely by currentEntitlements, so re-delivery
        // is harmless. Finish transactions here if we ever process consumables.
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refresh() }
        }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    /// Recompute `isPro` from the current on-device entitlements.
    func refresh() async {
        var entitlements: [ProEntitlement] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }   // ignore unverified
            entitlements.append(ProEntitlement(productID: t.productID,
                                               expiration: t.expirationDate,
                                               revocationDate: t.revocationDate))
        }
        isPro = Self.isProActive(entitlements, productIDs: Self.proProductIDs, now: Date())
    }

    /// Pure access rule: Pro is active iff some held entitlement is for a Pro
    /// product, not revoked, and not expired.
    nonisolated static func isProActive(_ entitlements: [ProEntitlement],
                                        productIDs: Set<String>, now: Date) -> Bool {
        entitlements.contains { e in
            productIDs.contains(e.productID)
                && e.revocationDate == nil
                && (e.expiration == nil || e.expiration! > now)
        }
    }
}
