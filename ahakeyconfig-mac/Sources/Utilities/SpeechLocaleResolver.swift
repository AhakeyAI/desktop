import Foundation
import Speech

/// 把语言标签解析成可用的识别语言。不依赖 UI 状态与 MainActor，可单独测试。
enum SpeechLocaleResolver {
    /// - Parameters:
    ///   - preference: 用户显式选择的 identifier；空串表示自动。
    ///   - preferredLanguages: 系统首选语言，按优先级排列。
    ///   - supported: `SFSpeechRecognizer.supportedLocales()`。
    ///   - normalize: 只给出语言码时，决定用哪个地区。默认交给 `SFSpeechRecognizer` 自己判断。
    static func resolve(
        preference: String,
        preferredLanguages: [String],
        supported: Set<Locale>,
        normalize: (String) -> Locale? = defaultRegion(forLanguage:)
    ) -> Locale? {
        if !preference.isEmpty,
           let chosen = supported.first(where: { $0.identifier == preference }) {
            return chosen
        }

        for preferred in preferredLanguages {
            if let hit = match(preferred, in: supported, normalize: normalize) {
                return hit
            }
        }
        return nil
    }

    /// 先按语言 + 地区精确匹配（`zh-Hans-CN` → `zh-CN`），不命中退到只按语言。
    ///
    /// 退化时地区由 `normalize` 决定，不从 `supported` 里挑：那是 `Set`，`en` 有 13 个
    /// 地区变体，取出来的结果不稳定。
    static func match(
        _ identifier: String,
        in supported: Set<Locale>,
        normalize: (String) -> Locale? = defaultRegion(forLanguage:)
    ) -> Locale? {
        let parts = NSLocale.components(fromLocaleIdentifier: identifier)
        guard let language = parts[NSLocale.Key.languageCode.rawValue], !language.isEmpty else { return nil }

        if let region = parts[NSLocale.Key.countryCode.rawValue] {
            let exact = supported.first {
                let c = NSLocale.components(fromLocaleIdentifier: $0.identifier)
                return c[NSLocale.Key.languageCode.rawValue] == language
                    && c[NSLocale.Key.countryCode.rawValue] == region
            }
            if let exact { return exact }
        }

        guard let normalized = normalize(language),
              supported.contains(where: { $0.identifier == normalized.identifier }) else {
            return nil
        }
        return normalized
    }

    static func defaultRegion(forLanguage language: String) -> Locale? {
        SFSpeechRecognizer(locale: Locale(identifier: language))?.locale
    }
}
