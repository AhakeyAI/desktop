import Foundation

/// 应用启动时的语言初始化。
///
/// 首次启动时读取系统首选语言，自动设置为中文或英文；
/// 若用户已手动切换过语言，则不再覆盖。
public enum AppLanguageInitializer {
    private static let selectedLanguageKey = "AhaKeySelectedLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    /// 支持的语言标识。
    public static let supportedLanguages = ["zh-Hans", "en"]

    /// 在应用启动时调用，仅在用户未手动设置过语言时同步系统语言。
    public static func applySystemLanguageIfNeeded() {
        guard UserDefaults.standard.string(forKey: selectedLanguageKey) == nil else {
            return
        }

        let language = systemMatchingLanguage()
        UserDefaults.standard.set([language], forKey: appleLanguagesKey)
        UserDefaults.standard.set(language, forKey: selectedLanguageKey)
    }

    /// 根据 `Locale.preferredLanguages` 匹配支持的语言，默认英文。
    public static func systemMatchingLanguage() -> String {
        let preferred = Locale.preferredLanguages
        for identifier in preferred {
            let lowercased = identifier.lowercased()
            if lowercased.hasPrefix("zh") {
                return "zh-Hans"
            }
            if lowercased.hasPrefix("en") {
                return "en"
            }
        }
        return "en"
    }
}
