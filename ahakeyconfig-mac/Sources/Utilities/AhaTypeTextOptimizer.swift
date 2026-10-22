import Foundation

@MainActor
final class AhaTypeTextOptimizer: ObservableObject {
    static let shared = AhaTypeTextOptimizer()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = NSLocalizedString("AhaType 未启用。", comment: "")
    @Published private(set) var lastQuotaSummary = NSLocalizedString("尚未读取 AhaType 配置。", comment: "")

    @Published private(set) var requiresLogin = false
    private let session: URLSession
    private let customConfigURL: URL?
    private let onLoginRequired: ((String?) -> Void)?

    private let fallbackAPIBase = "https://956798.xyz/prod-api"

    init(configURL: URL? = nil, session: URLSession = .shared, onLoginRequired: ((String?) -> Void)? = nil) {
        customConfigURL = configURL
        self.session = session
        self.onLoginRequired = onLoginRequired
        refreshFromDisk()
    }

    func refreshFromDisk() {
        let config = loadConfig()
        isEnabled = boolValue(config["typeless_enabled"])
        updateStatus(from: config)
    }

    var hasConfiguredCloudToken: Bool { !stringValue(loadConfig()["access_token"]).isEmpty }

    func setEnabled(_ enabled: Bool) {
        var config = loadConfig()
        config["typeless_enabled"] = enabled
        saveConfig(config)
        isEnabled = enabled
        updateStatus(from: config)
    }

    func patchCloudToken(_ token: String) {
        var config = loadConfig()
        config["access_token"] = token
        saveConfig(config)
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

    func processIfEnabled(_ text: String, enabledForRecording: Bool? = nil) async -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }

        var config = loadConfig()
        sanitize(&config)
        isEnabled = boolValue(config["typeless_enabled"])
        // A recording can carry an explicit start-time decision. Authentication
        // and token validity below are still checked against current credentials.
        guard enabledForRecording ?? isEnabled else {
            statusMessage = NSLocalizedString("AhaType 未启用，直接写入原始转写。", comment: "")
            return text
        }

        let token = stringValue(config["access_token"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, tokenIsStillValid(config["token_valid_until"]) else {
            requestLogin(token: token)
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
            let (data, response) = try await session.data(for: request)
            guard stringValue(loadConfig()["access_token"]) == token else { return text }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if CloudAuthenticationFailure.matches(status: statusCode, code: object.map { intValue($0["code"]) },
                message: object.map { responseMessage($0) } ?? "") {
                requestLogin(token: token)
                return text
            }
            guard statusCode == 200 else {
                statusMessage = "AhaType 请求失败（HTTP \(statusCode)），已写入原始转写。"
                return text
            }
            guard let object else {
                statusMessage = NSLocalizedString("AhaType 返回非 JSON，已写入原始转写。", comment: "")
                return text
            }
            let code = intValue(object["code"])
            guard code == 0 || code == 200 else {
                let message = responseMessage(object)
                statusMessage = message.isEmpty ? "AhaType 处理失败，已写入原始转写。" : "AhaType 处理失败：\(message)"
                return text
            }
            guard let inner = object["data"] as? [String: Any] else {
                statusMessage = NSLocalizedString("AhaType 返回缺少 data，已写入原始转写。", comment: "")
                return text
            }

            if let quota = inner["quota"] as? [String: Any] {
                var latest = loadConfig()
                guard stringValue(latest["access_token"]) == token else { return text }
                mergeQuota(quota, into: &latest)
                saveConfig(latest)
                isEnabled = boolValue(latest["typeless_enabled"])
                updateStatus(from: latest)
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

    private func requestLogin(token: String) {
        // A late response for an old token must not log out a newer login.
        guard stringValue(loadConfig()["access_token"]) == token else { return }
        clearSessionKeepToggle()
        statusMessage = NSLocalizedString("登录已失效，请重新登录。", comment: "")
        if let onLoginRequired { onLoginRequired(token.isEmpty ? nil : token) }
        else { CloudAccountManager.shared.requireLogin(ifTokenMatches: token.isEmpty ? nil : token) }
    }

    private func updateStatus(from config: [String: Any]) {
        let enabled = boolValue(config["typeless_enabled"])
        let token = stringValue(config["access_token"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = tokenIsStillValid(config["token_valid_until"])

        requiresLogin = enabled && (token.isEmpty || !valid)
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
            lastQuotaSummary += lastQuotaSummary.isEmpty ? "有效期 \(validUntil)" : " · 有效期 \(validUntil)"
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
        AhaTypeTokenExpiry.isValid(raw)
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
        sanitize(&merged)
        return merged
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
        if let customConfigURL { return customConfigURL }
        return FileManager.default.homeDirectoryForCurrentUser
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

enum AhaTypeTokenExpiry {
    static func isValid(_ raw: Any?, now: Date = Date()) -> Bool {
        guard let date = parseDate(raw) else { return false }
        return now < date
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        let value: String
        switch raw {
        case let string as String:
            value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            value = number.stringValue
        default:
            return nil
        }
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
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        return nil
    }
}
