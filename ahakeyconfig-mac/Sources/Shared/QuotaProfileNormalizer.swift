import Foundation

/// 云端账号 profile 标准化（配额/余额显示修复）。
/// /users/me、登录响应、支付回执的字段形态不一致：配额可能在顶层（snake_case 或 camelCase），
/// 也可能嵌套在 `quota` 子对象（与 typeless/process 的返回同构，嵌套层键名见
/// AhaTypeTextOptimizer.mergeQuota：snake_case 的 used_*/limit_*/token_valid_until）。
/// 这里统一成顶层 snake_case 读取形态：顶层已有值优先，嵌套 `quota` 补缺。
/// 纯函数，便于单测。
public enum QuotaProfileNormalizer {
    /// 标准化结果。
    public struct Result {
        /// 归一后的 profile（原始字段全保留，只补齐别名/嵌套字段）。
        public let profile: [String: Any]
        /// 是否识别到任何已知字段；false 表示响应形态完全不认识，调用方应视为拉取失败而非存空 profile。
        public let recognizedAnyField: Bool
        /// 命中了哪个余额键（token_balance / typeless_balance / balance），未命中为 nil。
        public let balanceKey: String?

        public init(profile: [String: Any], recognizedAnyField: Bool, balanceKey: String?) {
            self.profile = profile
            self.recognizedAnyField = recognizedAnyField
            self.balanceKey = balanceKey
        }
    }

    /// 顶层字段的 snake_case ← camelCase 别名。
    private static let aliases: [(String, String)] = [
        ("id", "userId"),
        ("user_id", "userId"),
        ("token_valid_until", "tokenValidUntil"),
        ("limit_daily", "limitDaily"),
        ("limit_weekly", "limitWeekly"),
        ("limit_monthly", "limitMonthly"),
        ("used_daily", "usedDaily"),
        ("used_weekly", "usedWeekly"),
        ("used_monthly", "usedMonthly"),
    ]

    /// 余额字段候选键，按优先级取第一个命中的。
    /// 余额单位待后端确认，客户端原值透传不换算。
    private static let balanceKeys = ["token_balance", "typeless_balance", "balance"]

    public static func normalize(_ raw: [String: Any]) -> Result {
        var profile = raw
        let quota = raw["quota"] as? [String: Any]

        for (snake, camel) in aliases where profile[snake] == nil {
            if let value = raw[camel] {
                profile[snake] = value
            } else if let value = quota?[snake] {
                profile[snake] = value
            } else if let value = quota?[camel] {
                profile[snake] = value
            }
        }

        // policy 子字典的 camelCase 别名（保持原有行为）。
        if var policy = profile["policy"] as? [String: Any] {
            let policyAliases: [(String, String)] = [
                ("recharge_prices_fen", "rechargePricesFen"),
                ("default_limit_daily", "defaultLimitDaily"),
                ("default_limit_weekly", "defaultLimitWeekly"),
                ("default_limit_monthly", "defaultLimitMonthly"),
                ("enable_daily", "enableDaily"),
                ("enable_weekly", "enableWeekly"),
                ("enable_monthly", "enableMonthly"),
            ]
            for (snake, camel) in policyAliases where policy[snake] == nil {
                if let value = policy[camel] {
                    policy[snake] = value
                }
            }
            profile["policy"] = policy
        }

        // 余额：原值透传不换算，顶层优先，嵌套 quota 补缺。
        var balanceKey: String?
        for key in balanceKeys where raw[key] != nil {
            balanceKey = key
            break
        }
        if balanceKey == nil, let quota {
            for key in balanceKeys {
                if let value = quota[key] {
                    profile[key] = value
                    balanceKey = key
                    break
                }
            }
        }

        // 是否识别到任何已知字段（用于调用方判断"响应形态不认识 = 拉取失败"）。
        var recognizedKeys = aliases.flatMap { [$0.0, $0.1] }
        recognizedKeys.append(contentsOf: ["phone", "policy", "quota"])
        recognizedKeys.append(contentsOf: balanceKeys)
        let recognized = recognizedKeys.contains { raw[$0] != nil }

        return Result(profile: profile, recognizedAnyField: recognized, balanceKey: balanceKey)
    }
}
