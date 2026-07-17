import Foundation
import AhaKeyConfigShared

@MainActor
final class AhaTypeTextOptimizer: ObservableObject {
    static let shared = AhaTypeTextOptimizer()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = NSLocalizedString("AhaType 未启用。", comment: "")
    @Published private(set) var lastQuotaSummary = NSLocalizedString("尚未读取 AhaType 配置。", comment: "")

    private let fallbackAPIBase = "https://956798.xyz/prod-api"
    private let keychainService = "lab.jawa.ahakeyconfig.typeless"
    private let keychainAccount = "accessToken"

    private var storedAccessToken: String {
        AhaKeyKeychain.load(service: keychainService, account: keychainAccount) ?? ""
    }

    private init() {
        refreshFromDisk()
    }

    func refreshFromDisk() {
        let config = loadConfig()
        isEnabled = boolValue(config["typeless_enabled"])
        updateStatus(from: config)
    }

    func setEnabled(_ enabled: Bool) {
        var config = loadConfig()
        config["typeless_enabled"] = enabled
        saveConfig(config)
        isEnabled = enabled
        updateStatus(from: config)
    }

    func patchCloudToken(_ token: String) {
        try? AhaKeyKeychain.save(service: keychainService, account: keychainAccount, value: token)
        // 不再把 token 写回 JSON 文件，避免明文泄露。
        refreshFromDisk()
    }

    func setUserProfile(_ profile: [String: Any]) {
        var config = loadConfig()
        config["user"] = [
            "phone": stringValue(profile["phone"]),
            "user_id": stringValue(profile["id"]).isEmpty ? stringValue(profile["user_id"]) : stringValue(profile["id"]),
        ]
        config["token_valid_until"] = profile["token_valid_until"] ?? NSNull()
        for key in ["limit_daily", "limit_weekly", "limit_monthly", "used_daily", "used_weekly", "used_monthly"] {
            config[key] = intValue(profile[key])
        }
        saveConfig(config)
        refreshFromDisk()
    }

    func clearSessionKeepToggle() {
        var config = loadConfig()
        let enabled = boolValue(config["typeless_enabled"])
        AhaKeyKeychain.delete(service: keychainService, account: keychainAccount)
        config["access_token"] = ""
        config["user"] = NSNull()
        config["token_valid_until"] = NSNull()
        for key in ["limit_daily", "limit_weekly", "limit_monthly", "used_daily", "used_weekly", "used_monthly"] {
            config[key] = 0
        }
        config["typeless_enabled"] = enabled
        saveConfig(config)
        refreshFromDisk()
    }

    func processIfEnabled(_ text: String) async -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }

        var config = loadConfig()
        sanitize(&config)
        isEnabled = boolValue(config["typeless_enabled"])
        guard isEnabled else {
            statusMessage = NSLocalizedString("AhaType 未启用，直接写入原始转写。", comment: "")
            return text
        }

        guard tokenIsStillValid(config["token_valid_until"]) else {
            statusMessage = NSLocalizedString("AhaType 登录已过期，直接写入原始转写。", comment: "")
            return text
        }

        let token = storedAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            statusMessage = NSLocalizedString("AhaType 缺少登录令牌，直接写入原始转写。", comment: "")
            return text
        }

        guard let url = URL(string: "\(resolveAPIBase(legacyAPIBase: stringValue(config["api_base"])))/api/v1/typeless/process") else {
            statusMessage = NSLocalizedString("AhaType 云端地址无效，直接写入原始转写。", comment: "")
            return text
        }

        statusMessage = NSLocalizedString("AhaType 整理中…", comment: "")

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": source], options: [])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 else {
                statusMessage = String(format: NSLocalizedString("AhaType 请求失败（HTTP %d），已写入原始转写。", comment: ""), statusCode)
                return text
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                statusMessage = NSLocalizedString("AhaType 返回非 JSON，已写入原始转写。", comment: "")
                return text
            }
            let code = intValue(object["code"])
            guard code == 0 || code == 200 else {
                let message = responseMessage(object)
                statusMessage = message.isEmpty ? NSLocalizedString("AhaType 处理失败，已写入原始转写。", comment: "") : String(format: NSLocalizedString("AhaType 处理失败：%@", comment: ""), message)
                return text
            }
            guard let inner = object["data"] as? [String: Any] else {
                statusMessage = NSLocalizedString("AhaType 返回缺少 data，已写入原始转写。", comment: "")
                return text
            }

            if let quota = inner["quota"] as? [String: Any] {
                mergeQuota(quota, into: &config)
                saveConfig(config)
                updateStatus(from: config)
            }

            let output = stringValue(inner["text"]).isEmpty ? stringValue(inner["result"]) : stringValue(inner["text"])
            let polished = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !polished.isEmpty else {
                statusMessage = NSLocalizedString("AhaType 返回空文本，已写入原始转写。", comment: "")
                return text
            }
            statusMessage = NSLocalizedString("AhaType 已整理，准备粘贴。", comment: "")
            return polished
        } catch {
            statusMessage = NSLocalizedString("AhaType 网络错误，已写入原始转写。", comment: "")
            return text
        }
    }

    private func updateStatus(from config: [String: Any]) {
        let enabled = boolValue(config["typeless_enabled"])
        let token = storedAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = tokenIsStillValid(config["token_valid_until"])

        if !enabled {
            statusMessage = NSLocalizedString("AhaType 未启用。", comment: "")
        } else if token.isEmpty {
            statusMessage = NSLocalizedString("AhaType 已开启，但尚未登录。", comment: "")
        } else if !valid {
            statusMessage = NSLocalizedString("AhaType 已开启，但登录已过期。", comment: "")
        } else {
            statusMessage = NSLocalizedString("AhaType 已开启，语音结果会先经云端整理。", comment: "")
        }

        let daily = quotaLine(title: NSLocalizedString("日", comment: ""), used: config["used_daily"], limit: config["limit_daily"])
        let weekly = quotaLine(title: NSLocalizedString("周", comment: ""), used: config["used_weekly"], limit: config["limit_weekly"])
        let monthly = quotaLine(title: NSLocalizedString("月", comment: ""), used: config["used_monthly"], limit: config["limit_monthly"])
        let validUntil = stringValue(config["token_valid_until"])
        lastQuotaSummary = [daily, weekly, monthly]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !validUntil.isEmpty {
            lastQuotaSummary += lastQuotaSummary.isEmpty ? String(format: NSLocalizedString("有效期 %@", comment: ""), validUntil) : String(format: NSLocalizedString(" · 有效期 %@", comment: ""), validUntil)
        }
        if lastQuotaSummary.isEmpty {
            lastQuotaSummary = NSLocalizedString("暂无配额信息。", comment: "")
        }
    }

    private func quotaLine(title: String, used: Any?, limit: Any?) -> String {
        let usedValue = intValue(used)
        let limitValue = intValue(limit)
        guard usedValue > 0 || limitValue > 0 else { return "" }
        return "\(title) \(usedValue)/\(limitValue)"
    }

    private func resolveAPIBase(legacyAPIBase: String) -> String {
        for key in ["VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"] {
            let value = normalizeAPIBase(ProcessInfo.processInfo.environment[key] ?? "")
            if !value.isEmpty { return value }
        }
        let fallback = normalizeAPIBase(fallbackAPIBase)
        if !fallback.isEmpty { return fallback }
        return normalizeAPIBase(legacyAPIBase)
    }

    private func normalizeAPIBase(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if !value.isEmpty, !value.contains("://") {
            value = "https://\(value)"
        }
        return value
    }

    private func tokenIsStillValid(_ raw: Any?) -> Bool {
        guard let date = parseDate(raw) else { return false }
        return Date() < date
    }

    private func parseDate(_ raw: Any?) -> Date? {
        let value = stringValue(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        return nil
    }

    private func mergeQuota(_ quota: [String: Any], into config: inout [String: Any]) {
        if let validUntil = quota["token_valid_until"] {
            config["token_valid_until"] = validUntil
        }
        for key in ["limit_daily", "limit_weekly", "limit_monthly", "used_daily", "used_weekly", "used_monthly"] {
            if let value = quota[key] {
                config[key] = intValue(value)
            }
        }
        config["quota_updated_at"] = Date().timeIntervalSince1970
    }

    private func loadConfig() -> [String: Any] {
        ensureConfigFileExists()
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return defaultPayload()
        }
        var merged = defaultPayload()
        for (key, value) in object {
            merged[key] = value
        }
        migrateTokenIfNeeded(&merged)
        sanitize(&merged)
        return merged
    }

    /// 一次性迁移：旧版本把 access_token 明文放在 JSON 文件中，发现后迁移到钥匙串并清空文件里的值。
    private func migrateTokenIfNeeded(_ config: inout [String: Any]) {
        guard let token = config["access_token"] as? String, !token.isEmpty else { return }
        try? AhaKeyKeychain.save(service: keychainService, account: keychainAccount, value: token)
        config["access_token"] = ""
        saveConfig(config)
    }

    private func saveConfig(_ config: [String: Any]) {
        var sanitized = defaultPayload()
        for (key, value) in config {
            sanitized[key] = value
        }
        sanitize(&sanitized)
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch {
            statusMessage = NSLocalizedString("AhaType 配置写入失败。", comment: "")
        }
    }

    private func ensureConfigFileExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        saveConfig(defaultPayload())
    }

    private func sanitize(_ config: inout [String: Any]) {
        for key in ["api_base", "token_balance", "typeless_balance"] {
            config.removeValue(forKey: key)
        }
        if var user = config["user"] as? [String: Any] {
            user.removeValue(forKey: "is_admin")
            config["user"] = user
        }
    }

    private func defaultPayload() -> [String: Any] {
        [
            "schema_version": 1,
            "access_token": "",
            "typeless_enabled": false,
            "token_valid_until": NSNull(),
            "limit_daily": 0,
            "limit_weekly": 0,
            "limit_monthly": 0,
            "used_daily": 0,
            "used_weekly": 0,
            "used_monthly": 0,
            "user": NSNull(),
        ]
    }

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VibeKeyboard", isDirectory: true)
            .appendingPathComponent("typeless_config.json")
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private func responseMessage(_ object: [String: Any]) -> String {
        for key in ["errorMsg", "msg", "message", "error"] {
            let value = stringValue(object[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? 0
        default:
            return 0
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes", "on"].contains(string.lowercased())
        default:
            return false
        }
    }
}
