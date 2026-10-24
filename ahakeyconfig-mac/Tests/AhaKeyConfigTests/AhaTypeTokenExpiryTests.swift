import Foundation
import XCTest
@testable import AhaKeyConfig

final class AhaTypeTokenExpiryTests: XCTestCase {
    func testFutureServerExpiryWithFractionalSecondsAllowsAhaType() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T00:00:00Z"))

        XCTAssertTrue(AhaTypeTokenExpiry.isValid("2026-12-15T12:18:42.000+08:00", now: now))
        XCTAssertFalse(AhaTypeTokenExpiry.isValid("2026-09-15T12:18:42.000+08:00", now: now))
    }

    func testUnreadableExpiryIsNotReportedAsExpired() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T00:00:00Z"))

        XCTAssertEqual(AhaTypeTokenExpiry.status("2026/12/15 12:18", now: now), .unreadable)
        XCTAssertEqual(AhaTypeTokenExpiry.status(NSNull(), now: now), .missing)
        XCTAssertEqual(AhaTypeTokenExpiry.status("2026-09-15T12:18:42.000+08:00", now: now), .expired)
    }

    func testClosedEndpointBusinessErrorIsSummarized() {
        let upstream = #"方舟推理调用异常: 400 Bad Request: "{"error":{"code":"InvalidEndpoint.ClosedEndpoint"}}""#

        XCTAssertEqual(
            AhaTypeTextOptimizer.businessFailureMessage(upstream),
            "AhaType 云端整理服务暂不可用（推理端点已关闭），已写入原始转写。"
        )
    }
}

final class AhaTypeCloudSessionTests: XCTestCase {
    func testServerTokenInvalidEnvelopeIsTreatedAsExpiredSession() {
        // 线上实测：失效 Token 返回 HTTP 200，业务 code=500，data=401。
        XCTAssertTrue(AhaTypeCloudSession.isExpired(httpStatus: 200, object: ["msg": "未登录或Token无效", "code": 500, "data": 401]))
        XCTAssertTrue(AhaTypeCloudSession.isExpired(httpStatus: 200, object: ["code": 401]))
        XCTAssertTrue(AhaTypeCloudSession.isExpired(httpStatus: 401, object: nil))
    }

    func testSuccessfulProfileResponseIsNotExpiredSession() {
        XCTAssertFalse(AhaTypeCloudSession.isExpired(httpStatus: 200, object: [
            "msg": "操作成功",
            "code": 200,
            "data": ["tokenValidUntil": "2026-11-13T16:13:59.000+08:00"],
        ]))
        XCTAssertFalse(AhaTypeCloudSession.isExpired(httpStatus: 200, object: ["msg": "兑换码无效", "code": 500]))
    }
}
