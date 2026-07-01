# Monetization — Design Spec

**Date:** 2026-06-30
**Status:** Approved for planning
**Model:** Freemium subscription (native StoreKit 2)

## Goal

Add the subscription/entitlement plumbing so any current or future feature can be
reserved for Pro with a one-line check, without deciding specific gates now. Ship
one real, testable entry point (an upgrade row in Profile). Everything is native —
no third-party SDK, no backend.

## Non-goals (YAGNI until explicitly requested)

- Deciding which features are Pro (features gate later, one at a time).
- Intro offers / free trials, promo codes, win-back offers.
- Receipt-validation server (StoreKit 2 verifies on-device).
- Revenue analytics dashboard, A/B paywalls.
- RevenueCat or any dependency. The `store.isPro` interface is identical if we
  ever migrate, so downstream code won't change.

## Constraints

- iOS 18 minimum (from `project.pbxproj`) → full StoreKit 2 + `SubscriptionStoreView`
  available.
- No existing IAP code; clean slate.
- App Store requirement: a **Restore Purchases** path must exist (native
  `SubscriptionStoreView` provides it).

## Architecture

New folder: `CrazyWork/Sources/Monetization/`

### 1. `Store.swift` — single source of truth

```swift
@Observable final class Store {
    private(set) var isPro = false
    private(set) var products: [Product] = []   // loaded plans, for custom UI if needed
    // init: start Transaction.updates listener, then refresh entitlements
    func load() async            // Product.products(for: productIDs)
    func purchase(_ p: Product) async throws
    func restore() async throws  // AppStore.sync()
    private func refreshEntitlements() async     // recompute isPro from currentEntitlements
}
```

- `isPro` is derived from `Transaction.currentEntitlements`: true iff there is a
  verified, unexpired, non-revoked transaction for a Pro product ID.
- A long-lived `Task` listens to `Transaction.updates` so renewals, refunds, and
  Family Sharing changes flip `isPro` automatically. Each update calls
  `refreshEntitlements()` and `finish()`es the transaction.
- Only `.verified` transactions count entitlement; `.unverified` is ignored.
- Created once at app launch and injected via `.environment(store)`.

### 2. `PaywallView.swift` — the paywall

Thin wrapper over the native paywall:

```swift
SubscriptionStoreView(groupID: Store.subscriptionGroupID) {
    // marketing content: headline + a few bullet rows
}
.subscriptionStorePolicyDestination(...)   // terms/privacy links
```

- Native view renders plan options, purchase button, and **Restore** for free.
- Presented as a `.sheet`. Dismisses itself on successful purchase (isPro flips,
  presenting view reacts).
- Marketing copy is placeholder-free but generic ("Unlock everything in CrazyWork")
  since no concrete gated features exist yet; expand copy as features land.

### 3. `Products.storekit` — local test config

- StoreKit configuration file added to the target and selected in the Run scheme.
- Defines the subscription group and both products so purchase/restore work in the
  simulator with no sandbox account during development.

### 4. Gate pattern (how features use it later)

The only contract downstream code depends on:

```swift
@Environment(Store.self) private var store
if store.isPro { /* premium path */ } else { /* present PaywallView */ }
```

No helper abstraction is built now (nothing to gate yet). When the first real gate
appears and a pattern repeats, extract a helper then — not before.

### 5. Entry point (wired now)

In `ProfileView`, add a "CrazyWork Pro" row:
- Free user → row reads "Upgrade to Pro", tap presents `PaywallView` sheet.
- Pro user → row reads "Pro member" (no action / manage-subscription link).

This makes the whole system live and testable end to end.

## Product configuration

Subscription group: **"CrazyWork Pro"**
- `com.crazywork.pro.monthly` — monthly.
- `com.crazywork.pro.yearly` — yearly, discounted to anchor value.

Created in App Store Connect for release; mirrored in `Products.storekit` for dev.
Product IDs live in one constant list on `Store` (the single place to edit).

## Data flow

```
App launch
  → create Store → inject into environment
  → Store starts Transaction.updates listener
  → Store.refreshEntitlements() → isPro

User taps "Upgrade to Pro" in Profile → PaywallView sheet
  → SubscriptionStoreView → StoreKit purchase
  → verified transaction → updates listener → refreshEntitlements()
  → isPro = true → @Observable notifies → sheet dismisses, Profile row updates
```

## Error handling

- Product load failure (offline): paywall shows the native view's own
  loading/empty state; upgrade row still tappable, retries on next present.
- Purchase cancelled / pending: no state change; `isPro` stays false. No error
  surfaced for user-cancel.
- `.unverified` transactions: ignored for entitlement (never grant Pro).
- Restore with nothing to restore: native view reports it; `isPro` unchanged.

## Testing / verification

- **Unit test** (`StoreTests`): entitlement-derivation logic — given a set of
  transaction states (verified+active, expired, revoked, unverified, wrong product
  ID) the mapping to `isPro` is correct. This is the one piece of real logic worth
  a runnable check; keep it dependency-free (test the pure derivation function, not
  StoreKit itself).
- **Manual smoke test** via `Products.storekit` in the simulator: buy monthly →
  Profile flips to "Pro member" and a gated sample path (temporary `if store.isPro`
  in a debug view) unlocks; use the StoreKit Transaction Manager to expire/refund →
  `isPro` flips back; Restore re-grants.

## Files

- `CrazyWork/Sources/Monetization/Store.swift` (new)
- `CrazyWork/Sources/Monetization/PaywallView.swift` (new)
- `CrazyWork/Products.storekit` (new, added to target + Run scheme)
- `CrazyWork/Sources/App/CrazyWorkApp.swift` (create + inject `Store`)
- `CrazyWork/Sources/Views/ProfileView.swift` (upgrade row + paywall sheet)
- `CrazyWorkTests/StoreTests.swift` (new, entitlement-derivation test)

## Deferred decisions

- Exact price points and yearly discount %.
- Which features become Pro (decided per feature as they ship).
- Whether to add a free trial / intro offer (revisit once conversion data exists).
