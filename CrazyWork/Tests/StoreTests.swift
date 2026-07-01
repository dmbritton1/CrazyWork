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
