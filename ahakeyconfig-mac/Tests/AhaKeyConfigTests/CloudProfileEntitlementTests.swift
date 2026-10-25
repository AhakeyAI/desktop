import Foundation
import XCTest
@testable import AhaKeyConfig

final class CloudProfileEntitlementTests: XCTestCase {
    func testMissingServerEntitlementExpiryStaysEmpty() {
        let profile = CloudAccountManager.normalizedProfile([
            "tokenValidUntil": NSNull(),
            "limitDaily": 0,
        ])

        XCTAssertTrue(profile["token_valid_until"] is NSNull)
        XCTAssertFalse(AhaTypeTokenExpiry.isValid(profile["token_valid_until"]))
    }

    func testServerEntitlementExpiryIsPassedThrough() {
        let profile = CloudAccountManager.normalizedProfile([
            "tokenValidUntil": "2026-12-15T12:18:42.000+08:00",
        ])

        XCTAssertEqual(profile["token_valid_until"] as? String, "2026-12-15T12:18:42.000+08:00")
    }
}
