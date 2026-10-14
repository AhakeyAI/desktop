import Foundation
import XCTest
@testable import AhaKeyConfig

final class AhaTypeTokenExpiryTests: XCTestCase {
    func testFutureServerExpiryWithFractionalSecondsAllowsAhaType() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T00:00:00Z"))

        XCTAssertTrue(AhaTypeTokenExpiry.isValid("2026-12-15T12:18:42.000+08:00", now: now))
        XCTAssertFalse(AhaTypeTokenExpiry.isValid("2026-09-15T12:18:42.000+08:00", now: now))
    }
}
