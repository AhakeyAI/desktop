import XCTest
@testable import AhaKeyConfigShared

final class QuotaProfileNormalizerTests: XCTestCase {

    /// 嵌套 quota 展开：/users/me 与 typeless/process 同构时配额在 quota 子对象里，应提升到顶层。
    func testNestedQuotaFieldsArePromotedToTopLevel() {
        let raw: [String: Any] = [
            "phone": "13800000000",
            "quota": [
                "used_daily": 5,
                "limit_daily": 100,
                "used_monthly": 42,
                "token_valid_until": "2026-09-01 00:00:00",
            ],
        ]
        let result = QuotaProfileNormalizer.normalize(raw)
        XCTAssertTrue(result.recognizedAnyField)
        XCTAssertEqual(result.profile["used_daily"] as? Int, 5)
        XCTAssertEqual(result.profile["limit_daily"] as? Int, 100)
        XCTAssertEqual(result.profile["used_monthly"] as? Int, 42)
        XCTAssertEqual(result.profile["token_valid_until"] as? String, "2026-09-01 00:00:00")
    }

    /// camelCase 别名：顶层 camelCase 字段映射到 snake_case 读取形态。
    func testCamelCaseAliasesAreMappedToSnakeCase() {
        let raw: [String: Any] = [
            "usedDaily": 3,
            "limitDaily": 50,
            "userId": "u-1",
            "tokenValidUntil": "2026-09-01 00:00:00",
        ]
        let result = QuotaProfileNormalizer.normalize(raw)
        XCTAssertTrue(result.recognizedAnyField)
        XCTAssertEqual(result.profile["used_daily"] as? Int, 3)
        XCTAssertEqual(result.profile["limit_daily"] as? Int, 50)
        XCTAssertEqual(result.profile["user_id"] as? String, "u-1")
        XCTAssertEqual(result.profile["token_valid_until"] as? String, "2026-09-01 00:00:00")
    }

    /// 空 data / 全不识别字段：判失败（调用方保留旧 profile，不存空 profile）。
    func testEmptyOrUnknownPayloadIsNotRecognized() {
        XCTAssertFalse(QuotaProfileNormalizer.normalize([:]).recognizedAnyField)
        XCTAssertFalse(QuotaProfileNormalizer.normalize(["something_else": 1, "ok": true]).recognizedAnyField)
    }

    /// 顶层已有值优先，嵌套 quota 只补缺。
    func testTopLevelValueWinsOverNestedQuota() {
        let raw: [String: Any] = [
            "used_daily": 7,
            "quota": [
                "used_daily": 99,
                "limit_daily": 100,
            ],
        ]
        let result = QuotaProfileNormalizer.normalize(raw)
        XCTAssertTrue(result.recognizedAnyField)
        XCTAssertEqual(result.profile["used_daily"] as? Int, 7)
        XCTAssertEqual(result.profile["limit_daily"] as? Int, 100)
    }

    /// 余额键：原值透传不换算，记录命中键；嵌套 quota 里的余额键也要识别。
    func testBalanceKeyPassThrough() {
        let topLevel = QuotaProfileNormalizer.normalize(["typeless_balance": 1234])
        XCTAssertEqual(topLevel.balanceKey, "typeless_balance")
        XCTAssertEqual(topLevel.profile["typeless_balance"] as? Int, 1234)
        XCTAssertTrue(topLevel.recognizedAnyField)

        let nested = QuotaProfileNormalizer.normalize(["quota": ["balance": "56.78"]])
        XCTAssertEqual(nested.balanceKey, "balance")
        XCTAssertEqual(nested.profile["balance"] as? String, "56.78")

        let none = QuotaProfileNormalizer.normalize(["phone": "13800000000"])
        XCTAssertNil(none.balanceKey)
    }

    /// policy 子字典：recharge_prices_fen 的 camelCase 别名保持原有行为。
    func testPolicyCamelCaseAliasesArePreserved() {
        let raw: [String: Any] = [
            "policy": ["rechargePricesFen": ["monthly": 100]],
        ]
        let result = QuotaProfileNormalizer.normalize(raw)
        XCTAssertTrue(result.recognizedAnyField)
        let policy = result.profile["policy"] as? [String: Any]
        let prices = policy?["recharge_prices_fen"] as? [String: Any]
        XCTAssertEqual(prices?["monthly"] as? Int, 100)
    }
}
