import Foundation

/// 本地大模型语音转写后整理器（兼容 OpenAI /v1/chat/completions 接口，如 Ollama）。
final class LocalLLMTextCleaner: @unchecked Sendable {
    static let shared = LocalLLMTextCleaner()

    enum Mode: String, CaseIterable, Sendable {
        case ahatype = "ahatype"
        case local = "local"
    }

    enum Keys {
        static let mode = "cleanup.mode"
        static let baseURL = "cleanup.baseURL"
        static let model = "cleanup.model"
        static let apiKey = "cleanup.apiKey"
    }

    enum Defaults {
        static let mode: Mode = .ahatype
        static let baseURL = "http://localhost:11434"
        static let model = "qwen2.5:3b"
        static let apiKey = ""
        static let timeoutInterval: TimeInterval = 30.0
    }

    struct CleanupResult: Equatable, Sendable {
        let text: String
        let failureReason: String?

        init(text: String, failureReason: String? = nil) {
            self.text = text
            self.failureReason = failureReason
        }
    }

    static let defaultSystemPrompt = "clean up dictated text — fix punctuation, remove filler words/false starts, keep the original language(s) and meaning, do not translate, do not answer or add commentary, output only the cleaned text."

    private let session: URLSession
    private let userDefaults: UserDefaults
    private let timeoutInterval: TimeInterval
    private let systemPrompt: String

    init(
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        timeoutInterval: TimeInterval = Defaults.timeoutInterval,
        systemPrompt: String = defaultSystemPrompt
    ) {
        self.session = session
        self.userDefaults = userDefaults
        self.timeoutInterval = timeoutInterval
        self.systemPrompt = systemPrompt
    }

    var currentBaseURL: String {
        let raw = userDefaults.string(forKey: Keys.baseURL)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? Defaults.baseURL : raw
    }

    var currentModel: String {
        let raw = userDefaults.string(forKey: Keys.model)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? Defaults.model : raw
    }

    var currentApiKey: String {
        userDefaults.string(forKey: Keys.apiKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? Defaults.apiKey
    }

    var currentMode: Mode {
        Self.currentMode(userDefaults: userDefaults)
    }

    static func currentMode(userDefaults: UserDefaults = .standard) -> Mode {
        guard let raw = userDefaults.string(forKey: Keys.mode)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let mode = Mode(rawValue: raw.lowercased()) else {
            return Defaults.mode
        }
        return mode
    }

    /// 整理转写文本，任何失败或空结果均返回原文本。
    func clean(_ text: String) async -> String {
        await cleanResult(text).text
    }

    /// 整理转写文本并附带失败原因（若失败则 text 为原始文本，failureReason 非空）。
    func cleanResult(_ text: String) async -> CleanupResult {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return CleanupResult(text: text, failureReason: nil)
        }

        guard let url = Self.resolveEndpointURL(baseURL: currentBaseURL) else {
            return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理端点地址无效，已写入原始转写。", comment: ""))
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let apiKey = currentApiKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmedInput]
            ],
            "stream": false,
            "temperature": 0.1,
            "chat_template_kwargs": [
                "enable_thinking": false
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理请求数据编码失败，已写入原始转写。", comment: ""))
        }
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理响应异常，已写入原始转写。", comment: ""))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let msg = String(format: NSLocalizedString("本地整理请求失败（HTTP %d），已写入原始转写。", comment: ""), httpResponse.statusCode)
                return CleanupResult(text: text, failureReason: msg)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理返回非 JSON，已写入原始转写。", comment: ""))
            }
            guard let rawContent = Self.extractContent(from: json) else {
                return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理返回缺少 content，已写入原始转写。", comment: ""))
            }
            let stripped = Self.stripThinkBlocks(rawContent)
            let polished = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !polished.isEmpty else {
                return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理返回空文本，已写入原始转写。", comment: ""))
            }
            return CleanupResult(text: polished, failureReason: nil)
        } catch let urlError as URLError where urlError.code == .timedOut {
            return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理请求超时，已写入原始转写。", comment: ""))
        } catch {
            return CleanupResult(text: text, failureReason: NSLocalizedString("本地整理服务不可用，已写入原始转写。", comment: ""))
        }
    }

    static func resolveEndpointURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.isEmpty {
            base = Defaults.baseURL
        }
        if !base.contains("://") {
            base = "http://\(base)"
        }
        if base.hasSuffix("/v1/chat/completions") {
            return URL(string: base)
        }
        if base.hasSuffix("/v1") {
            return URL(string: "\(base)/chat/completions")
        }
        return URL(string: "\(base)/v1/chat/completions")
    }

    static func stripThinkBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<think>.*?</think>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var stripped = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")

        // 如果大模型生成中断导致 <think> 没有闭合标签，将未闭合的思考块剔除
        if let unclosedRegex = try? NSRegularExpression(
            pattern: "<think>.*",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) {
            let unclosedRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            stripped = unclosedRegex.stringByReplacingMatches(in: stripped, options: [], range: unclosedRange, withTemplate: "")
        }

        // 剔除任何遗留的孤立闭合标签 </think>
        stripped = stripped.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)

        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractContent(from object: [String: Any]) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            return nil
        }
        if let content = message["content"] as? String {
            return content
        }
        if let contentArray = message["content"] as? [[String: Any]] {
            let texts = contentArray.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined()
            }
        }
        return nil
    }
}
