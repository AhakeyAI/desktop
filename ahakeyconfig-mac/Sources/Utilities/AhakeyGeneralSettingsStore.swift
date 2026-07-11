import Foundation

enum AhakeyGeneralSettingsStore {
    static let agentAPIKeyKey = "ahakey.general.agentAPIKey"
    static let languageKey = "ahakey.general.appLanguage"
    static let regionKey = "ahakey.general.appRegion"

    static var agentAPIKey: String {
        UserDefaults.standard.string(forKey: agentAPIKeyKey) ?? ""
    }

    static func setAgentAPIKey(_ value: String) {
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: agentAPIKeyKey)
    }

    static var maskedAgentAPIKey: String {
        let key = agentAPIKey
        guard !key.isEmpty else { return "未配置" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(7))••••\(key.suffix(4))"
    }

    static var appLanguage: AhaKeyAppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: languageKey) ?? AhaKeyAppLanguage.system.rawValue
            return AhaKeyAppLanguage(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: languageKey) }
    }

    static var appRegion: AhaKeyAppRegion {
        get {
            let raw = UserDefaults.standard.string(forKey: regionKey) ?? AhaKeyAppRegion.system.rawValue
            return AhaKeyAppRegion(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: regionKey) }
    }

    static var resolvedLocale: Locale {
        AhaKeyLocaleResolver.locale(language: appLanguage, region: appRegion)
    }
}

enum AhaKeyAppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .zhHans: "简体中文"
        case .english: "English"
        }
    }
}

enum AhaKeyAppRegion: String, CaseIterable, Identifiable {
    case system
    case chinaMainland
    case unitedStates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .chinaMainland: "中国大陆"
        case .unitedStates: "美国"
        }
    }
}

enum AhaKeyLocaleResolver {
    static func locale(language: AhaKeyAppLanguage, region: AhaKeyAppRegion) -> Locale {
        switch (language, region) {
        case (.system, .system):
            return .autoupdatingCurrent
        case (.zhHans, .chinaMainland), (.zhHans, .system):
            return Locale(identifier: "zh_CN")
        case (.zhHans, .unitedStates):
            return Locale(identifier: "zh_Hans_US")
        case (.english, .unitedStates), (.english, .system):
            return Locale(identifier: "en_US")
        case (.english, .chinaMainland):
            return Locale(identifier: "en_CN")
        case (.system, .chinaMainland):
            return Locale(identifier: preferredLanguagePrefix() == "en" ? "en_CN" : "zh_CN")
        case (.system, .unitedStates):
            return Locale(identifier: preferredLanguagePrefix() == "zh" ? "zh_Hans_US" : "en_US")
        }
    }

    private static func preferredLanguagePrefix() -> String {
        let code = Locale.preferredLanguages.first ?? "zh"
        if code.hasPrefix("zh") { return "zh" }
        if code.hasPrefix("en") { return "en" }
        return "zh"
    }
}
