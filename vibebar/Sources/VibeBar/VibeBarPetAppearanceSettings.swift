import Foundation
import SwiftUI

public enum VibeBarPetSkin: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 默认：色点 + 几何符号。
    case minimalDot
    /// 可选：状态 emoji，支持按状态自定义图标。
    case classicEmoji

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimalDot: "极简圆点"
        case .classicEmoji: "状态 emoji"
        }
    }

    public var detail: String {
        switch self {
        case .minimalDot: "默认 · 色点 + 符号"
        case .classicEmoji: "可选 · 图标可自定义"
        }
    }

    public func glyph(for status: VibeBarAgentStatus) -> String {
        switch self {
        case .classicEmoji:
            return status.petEmoji
        case .minimalDot:
            switch status {
            case .idle: return "●"
            case .listening: return "◉"
            case .thinking: return "◎"
            case .searching: return "◌"
            case .coding: return "◆"
            case .approval: return "▲"
            case .completed: return "★"
            case .error: return "✕"
            }
        }
    }
}

public enum VibeBarPetSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    public var glyphFontSize: CGFloat {
        switch self {
        case .small: 26
        case .medium: 34
        case .large: 42
        }
    }

    public var panelHeight: CGFloat {
        switch self {
        case .small: 58
        case .medium: 70
        case .large: 84
        }
    }
}

public enum VibeBarPetAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case breathe
    case bounce
    case blink

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "无"
        case .breathe: "呼吸"
        case .bounce: "弹跳"
        case .blink: "闪烁"
        }
    }
}

public enum VibeBarPetAnimationSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case slow
    case normal
    case fast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .slow: "慢"
        case .normal: "标准"
        case .fast: "快"
        }
    }

    public var period: TimeInterval {
        switch self {
        case .slow: 2.4
        case .normal: 1.4
        case .fast: 0.8
        }
    }
}

/// 单状态覆盖（高级）。
public struct VibeBarPetStatusOverride: Codable, Equatable, Sendable {
    public var glyph: String?
    public var animationStyle: VibeBarPetAnimationStyle?

    public init(glyph: String? = nil, animationStyle: VibeBarPetAnimationStyle? = nil) {
        self.glyph = glyph
        self.animationStyle = animationStyle
    }
}

public struct VibeBarPetAppearance: Codable, Equatable, Sendable {
    public var skinId: VibeBarPetSkin
    public var showsTaskTitle: Bool
    public var showsProgress: Bool
    public var showsStatusLabel: Bool
    public var petSize: VibeBarPetSize
    public var animationStyle: VibeBarPetAnimationStyle
    public var animationSpeed: VibeBarPetAnimationSpeed
    public var statusOverrides: [String: VibeBarPetStatusOverride]
    public var customAssetPath: String?

    public static let `default` = VibeBarPetAppearance(
        skinId: .minimalDot,
        showsTaskTitle: true,
        showsProgress: true,
        showsStatusLabel: true,
        petSize: .medium,
        animationStyle: .breathe,
        animationSpeed: .normal,
        statusOverrides: [:],
        customAssetPath: nil
    )

    public func glyph(for status: VibeBarAgentStatus) -> String {
        if let override = statusOverrides[status.rawValue]?.glyph, !override.isEmpty {
            return override
        }
        return skinId.glyph(for: status)
    }

    public func animationStyle(for status: VibeBarAgentStatus) -> VibeBarPetAnimationStyle {
        statusOverrides[status.rawValue]?.animationStyle ?? animationStyle
    }

    public var resolvedCustomAssetURL: URL? {
        guard let path = customAssetPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

public enum VibeBarPetAppearanceSettings {
    public static let storageKey = "vibebar.island.petAppearance"
    public static let didChangeNotification = Notification.Name("vibebar.island.petAppearanceDidChange")

    public static var appearance: VibeBarPetAppearance {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode(VibeBarPetAppearance.self, from: data) else {
                return .default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            NotificationCenter.default.post(
                name: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification,
                object: nil
            )
        }
    }

    public static func resetToDefaults() {
        appearance = .default
    }

    public static func update(_ mutate: (inout VibeBarPetAppearance) -> Void) {
        var value = appearance
        mutate(&value)
        appearance = value
    }
}
