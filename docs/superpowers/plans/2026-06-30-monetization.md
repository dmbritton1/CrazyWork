# Monetization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native StoreKit 2 freemium subscription plumbing so any feature can be reserved for Pro with a `store.isPro` check, with one live entry point (an upgrade row in Profile).

**Architecture:** A `@MainActor @Observable Store` is the single source of truth for the Pro entitlement, derived from `Transaction.currentEntitlements` and kept live by a `Transaction.updates` listener. The paywall is Apple's native `SubscriptionStoreView(productIDs:)` (renders plans, purchase, and Restore for free). A local `Products.storekit` file enables purchase testing in the simulator with no backend.

**Tech Stack:** Swift, SwiftUI, StoreKit 2, XCTest. No third-party dependencies.

## Global Constraints

- iOS 18 minimum deployment target — full StoreKit 2 + `SubscriptionStoreView` available.
- No third-party dependencies (no RevenueCat). Native StoreKit 2 only.
- Pro product IDs (the single canonical list): `com.crazywork.pro.monthly`, `com.crazywork.pro.yearly`. Must match App Store Connect and `Products.storekit`.
- Only `.verified` transactions grant Pro; `.unverified` is always ignored.
- A Restore Purchases path is mandatory (App Store requirement) — provided by the native paywall.
- Marketing copy must be placeholder-free but generic ("Unlock everything in CrazyWork") — no per-feature promises, since no features are gated yet.
- **The project is XcodeGen-generated.** `CrazyWork/project.yml` declares `sources: [Sources]` (app target) and `sources: [Tests]` (test target), so any new file under those folders is auto-included after regenerating. Do NOT hand-edit `project.pbxproj` — after adding/moving files or editing `project.yml`, run `cd CrazyWork && xcodegen generate`, then commit the regenerated `project.pbxproj` alongside your sources.
- Tests are XCTest in `CrazyWork/Tests/`, using `@testable import CrazyWork`.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro` (the simulators available on this machine; there is no iPhone 16).

---

## File Structure

- `CrazyWork/Sources/Monetization/Store.swift` (new) — `Store` observable + `ProEntitlement` value type + pure `isProActive` rule.
- `CrazyWork/Sources/Monetization/PaywallView.swift` (new) — native paywall wrapper.
- `CrazyWork/Sources/Products.storekit` (new) — local StoreKit test config; wired into the run scheme via `project.yml`.
- `CrazyWork/project.yml` (modify) — add `scheme.storeKitConfiguration` to the CrazyWork target so the config is used at run time.
- `CrazyWork/Tests/StoreTests.swift` (new) — unit tests for the entitlement rule.
- `CrazyWork/Sources/App/CrazyWorkApp.swift` (modify) — create + inject `Store`.
- `CrazyWork/Sources/Views/ProfileView.swift` (modify) — upgrade row + paywall sheet.

---

## Task 1: Store — entitlement source of truth + pure rule (unit tested)

**Files:**
- Create: `CrazyWork/Sources/Monetization/Store.swift`
- Test: `CrazyWork/Tests/StoreTests.swift`

**Interfaces:**
- Consumes: nothing (StoreKit only).
- Produces:
  - `struct ProEntitlement: Equatable { let productID: String; let expiration: Date?; let revocationDate: Date? }`
  - `@MainActor @Observable final class Store` with:
    - `static let proProductIDs: Set<String>`
    - `private(set) var isPro: Bool`
    - `func refresh() async`
    - `static func isProActive(_ entitlements: [ProEntitlement], productIDs: Set<String>, now: Date) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `CrazyWork/Tests/StoreTests.swift`:

```swift
import XCTest
@testable import CrazyWork

final class StoreTests: XCTestCase {
    private let ids: Set<String> = ["com.crazywork.pro.monthly", "com.crazywork.pro.yearly"]
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testActiveSubscriptionGrantsPro() {
        let e = ProEntitlement(productID: "com.crazywork.pro.monthly",
                               expiration: now.addingTimeInterval(3600), revocationDate: nil)
        XCTAssertTrue(Store.isProActive([e], productIDs: ids, now: now))
    }

    func testExpiredSubscriptionDeniesPro() {
        let e = ProEntitlement(productID: "com.crazywork.pro.monthly",
                               expiration: now.addingTimeInterval(-3600), revocationDate: nil)
        XCTAssertFalse(Store.isProActive([e], productIDs: ids, now: now))
    }

    func testRevokedSubscriptionDeniesPro() {
        let e = ProEntitlement(productID: "com.crazywork.pro.yearly",
                               expiration: now.addingTimeInterval(3600),
                               revocationDate: now.addingTimeInterval(-60))
        XCTAssertFalse(Store.isProActive([e], productIDs: ids, now: now))
    }

    func testUnknownProductDeniesPro() {
        let e = ProEntitlement(productID: "com.crazywork.other",
                               expiration: now.addingTimeInterval(3600), revocationDate: nil)
        XCTAssertFalse(Store.isProActive([e], productIDs: ids, now: now))
    }

    func testEmptyEntitlementsDeniesPro() {
        XCTAssertFalse(Store.isProActive([], productIDs: ids, now: now))
    }
}
```

The file lands under `Tests/`, which the test target already globs — no manual target step. Regenerate so the new file is in the project:

Run: `cd CrazyWork && xcodegen generate`
Expected: `Created project at .../CrazyWork.xcodeproj`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/StoreTests`
Expected: FAIL — compile error, `ProEntitlement` / `Store` not found.

- [ ] **Step 3: Write the minimal implementation**

Create `CrazyWork/Sources/Monetization/Store.swift`:

```swift
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
    private var updatesTask: Task<Void, Never>?

    init() {
        // React to renewals, refunds, revocations, Family Sharing changes.
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
    static func isProActive(_ entitlements: [ProEntitlement],
                            productIDs: Set<String>, now: Date) -> Bool {
        entitlements.contains { e in
            productIDs.contains(e.productID)
                && e.revocationDate == nil
                && (e.expiration == nil || e.expiration! > now)
        }
    }
}
```

The file lands under `Sources/`, already globbed by the app target. Regenerate so it's in the project:

Run: `cd CrazyWork && xcodegen generate`
Expected: `Created project at .../CrazyWork.xcodeproj`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CrazyWorkTests/StoreTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Monetization/Store.swift CrazyWork/Tests/StoreTests.swift CrazyWork/CrazyWork.xcodeproj/project.pbxproj
git commit -m "feat(monetization): Store entitlement source of truth + pure rule"
```

---

## Task 2: Local StoreKit config + native paywall

**Files:**
- Create: `CrazyWork/Products.storekit`
- Create: `CrazyWork/Sources/Monetization/PaywallView.swift`

**Interfaces:**
- Consumes: `Store.proProductIDs` (Task 1), `Store.isPro` (Task 1) via environment.
- Produces: `struct PaywallView: View` — a self-contained paywall sheet body; dismisses itself once `isPro` becomes true.

- [ ] **Step 1: Create the StoreKit configuration file**

Create `CrazyWork/Sources/Products.storekit` with a subscription group `CrazyWork Pro` holding the two auto-renewable products (prices are placeholders — tune later; they do not affect the code):

```json
{
  "identifier" : "A1B2C3D4",
  "nonRenewingSubscriptions" : [],
  "products" : [],
  "settings" : {
    "_applicationInternalID" : "",
    "_developerTeamID" : "",
    "_failTransactionsEnabled" : false,
    "_locale" : "en_US",
    "_storefront" : "USA",
    "_storeKitErrors" : []
  },
  "subscriptionGroups" : [
    {
      "id" : "20881234",
      "localizations" : [],
      "name" : "CrazyWork Pro",
      "subscriptions" : [
        {
          "adHocOffers" : [],
          "codeOffers" : [],
          "displayPrice" : "4.99",
          "familyShareable" : false,
          "groupNumber" : 1,
          "internalID" : "10001",
          "introductoryOffer" : null,
          "localizations" : [
            {
              "description" : "Unlock everything in CrazyWork.",
              "displayName" : "CrazyWork Pro Monthly",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.crazywork.pro.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "CrazyWork Pro Monthly",
          "subscriptionGroupID" : "20881234",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [],
          "codeOffers" : [],
          "displayPrice" : "39.99",
          "familyShareable" : false,
          "groupNumber" : 1,
          "internalID" : "10002",
          "introductoryOffer" : null,
          "localizations" : [
            {
              "description" : "Unlock everything in CrazyWork.",
              "displayName" : "CrazyWork Pro Yearly",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.crazywork.pro.yearly",
          "recurringSubscriptionPeriod" : "P1Y",
          "referenceName" : "CrazyWork Pro Yearly",
          "subscriptionGroupID" : "20881234",
          "type" : "RecurringSubscription"
        }
      ]
    }
  ],
  "version" : {
    "major" : 4,
    "minor" : 0
  }
}
```

- [ ] **Step 2: Wire the config into the run scheme via `project.yml`**

In `CrazyWork/project.yml`, add a `scheme` block to the `CrazyWork` target (a sibling of its existing `sources:` / `dependencies:` / `info:` keys), so XcodeGen generates a shared scheme that uses the StoreKit config at run time:

```yaml
    scheme:
      storeKitConfiguration: Sources/Products.storekit
```

Then regenerate:

Run: `cd CrazyWork && xcodegen generate`
Expected: `Created project at .../CrazyWork.xcodeproj`. (This also adds `Products.storekit` to the project — XcodeGen treats `.storekit` files specially, not as a bundled app resource.)

- [ ] **Step 3: Write the paywall view**

Create `CrazyWork/Sources/Monetization/PaywallView.swift`:

```swift
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
```

The file lands under `Sources/`, already globbed by the app target. Regenerate:

Run: `cd CrazyWork && xcodegen generate`
Expected: `Created project at .../CrazyWork.xcodeproj`.

- [ ] **Step 4: Verify the project builds clean**

Interactive paywall behavior is verified end-to-end in Task 3; here just confirm compilation:

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Products.storekit CrazyWork/Sources/Monetization/PaywallView.swift CrazyWork/project.yml CrazyWork/CrazyWork.xcodeproj
git commit -m "feat(monetization): local StoreKit config + native paywall view"
```

---

## Task 3: Wire Store into the app + Profile upgrade row (end-to-end)

**Files:**
- Modify: `CrazyWork/Sources/App/CrazyWorkApp.swift`
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:**
- Consumes: `Store` (Task 1), `PaywallView` (Task 2).
- Produces: nothing new — completes the feature.

- [ ] **Step 1: Create and inject the Store at app launch**

In `CrazyWork/Sources/App/CrazyWorkApp.swift`, replace the body:

```swift
import SwiftUI
import SwiftData

@main
struct CrazyWorkApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self, SavedWorkout.self])
    }
}
```

- [ ] **Step 2: Add the upgrade row + paywall sheet to ProfileView**

In `CrazyWork/Sources/Views/ProfileView.swift`:

(a) Add these two properties alongside the other `@State`/`@Environment` declarations near the top of `ProfileView` (after line 44):

```swift
    @Environment(Store.self) private var store
    @State private var showPaywall = false
```

(b) In `body`, insert `proCard` as the first item inside the inner settings `VStack` and attach the sheet. Change:

```swift
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        headerCard
                        settingsCard
```

to:

```swift
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        proCard
                        headerCard
                        settingsCard
```

and add the sheet modifier next to the existing `.task { ... }` on the outer view (after line 72):

```swift
        .sheet(isPresented: $showPaywall) { PaywallView() }
```

(c) Add the `proCard` computed property (place it right before `headerCard`, near line 75):

```swift
    private var proCard: some View {
        Button { if !store.isPro { showPaywall = true } } label: {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(store.isPro ? "Pro member" : "Upgrade to Pro")
                        .typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                    Text(store.isPro ? "Thanks for supporting CrazyWork"
                                     : "Unlock everything in CrazyWork")
                        .typography(Typography.captionMd).foregroundStyle(Palette.mute)
                }
                Spacer()
                Image(systemName: store.isPro ? "checkmark.seal.fill" : "chevron.right")
                    .foregroundStyle(store.isPro ? Palette.brandRed : Palette.mute)
            }
            .card()
        }
        .buttonStyle(.plain)
        .disabled(store.isPro)
    }
```

- [ ] **Step 3: Build**

(Both files already exist in the target — no `xcodegen generate` needed.)

Run: `xcodebuild build -project CrazyWork/CrazyWork.xcodeproj -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual end-to-end smoke test (simulator; StoreKit config is wired into the scheme via `project.yml`)**

Run the app on the iPhone 16 simulator and verify:
1. Profile tab → "Upgrade to Pro" row shows a chevron. Tap it → native paywall appears with Monthly + Yearly plans and a Restore button.
2. Buy Monthly → paywall dismisses automatically → the row now reads "Pro member" with a seal icon and is not tappable.
3. Xcode → Debug → StoreKit → **Manage Transactions** → delete/refund the transaction → return to the app → the row reverts to "Upgrade to Pro" (may require re-foregrounding).
4. Reopen the paywall → tap **Restore** after re-adding the transaction → row returns to "Pro member".

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/App/CrazyWorkApp.swift CrazyWork/Sources/Views/ProfileView.swift
git commit -m "feat(monetization): inject Store + Profile upgrade row and paywall sheet"
```

---

## Pre-release checklist (not part of this plan's tasks — do before shipping)

- Create the subscription group + both products in **App Store Connect** with the exact product IDs.
- Sign the "Paid Applications" agreement.
- Create a **Sandbox Apple ID** and verify purchase + restore on a real device / TestFlight.
- Finalize price points and decide whether to add a free-trial intro offer.
