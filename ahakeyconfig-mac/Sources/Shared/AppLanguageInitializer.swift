import Foundation

/// 应用启动时的语言初始化。
///
/// 默认跟随系统首选语言；用户选定语言后保持该选择。
public enum AppLanguageInitializer {
    public static let selectedLanguageKey = "AhaKeySelectedLanguage"
    public static let systemSelection = "system"
    private static let appleLanguagesKey = "AppleLanguages"

    /// 支持的语言标识。
    public static let supportedLanguages = ["zh-Hans", "en"]

    /// 读取全局语言设置，避免应用自己的 AppleLanguages 覆盖系统选择。
    public static func systemPreferredLanguages() -> [String] {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])
            ?? Locale.preferredLanguages
    }

    /// 在应用启动时同步系统语言或用户指定的语言。
    public static func applySystemLanguageIfNeeded(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = systemPreferredLanguages()
    ) {
        let selected = defaults.string(forKey: selectedLanguageKey) ?? systemSelection
        setLanguageSelection(selected, defaults: defaults, preferredLanguages: preferredLanguages)
    }

    public static func setLanguageSelection(
        _ selection: String,
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = systemPreferredLanguages()
    ) {
        let normalized = supportedLanguages.contains(selection) ? selection : systemSelection
        let language = normalized == systemSelection
            ? systemMatchingLanguage(preferredLanguages: preferredLanguages)
            : normalized
        defaults.set(normalized, forKey: selectedLanguageKey)
        if defaults.stringArray(forKey: appleLanguagesKey)?.first != language {
            defaults.set([language], forKey: appleLanguagesKey)
        }
    }

    /// 根据 `Locale.preferredLanguages` 匹配支持的语言，默认英文。
    public static func systemMatchingLanguage(preferredLanguages: [String] = systemPreferredLanguages()) -> String {
        for identifier in preferredLanguages {
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
