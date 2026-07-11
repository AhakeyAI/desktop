import AppKit
import SwiftUI

/// 插件市场独立「逛店」色板：与 Settings 工具页刻意区分，形成记忆点。
enum AhakeyPluginMarketTheme {
    static let canvas = adaptive(
        "AhakeyPluginMarket.canvas",
        light: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1),
        dark: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
    )
    static let tileBackground = adaptive(
        "AhakeyPluginMarket.tileBackground",
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1)
    )
    static let chromeBackground = adaptive(
        "AhakeyPluginMarket.chromeBackground",
        light: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 0.92),
        dark: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.92)
    )
    static let primaryText = adaptive(
        "AhakeyPluginMarket.primaryText",
        light: NSColor(white: 0, alpha: 0.90),
        dark: NSColor(white: 1, alpha: 0.96)
    )
    static let secondaryText = adaptive(
        "AhakeyPluginMarket.secondaryText",
        light: NSColor(white: 0, alpha: 0.50),
        dark: NSColor(white: 1, alpha: 0.48)
    )
    static let tertiaryText = adaptive(
        "AhakeyPluginMarket.tertiaryText",
        light: NSColor(white: 0, alpha: 0.34),
        dark: NSColor(white: 1, alpha: 0.34)
    )
    static let accent = adaptive(
        "AhakeyPluginMarket.accent",
        light: NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1),
        dark: NSColor(srgbRed: 0.20, green: 0.58, blue: 1.0, alpha: 1)
    )
    static let divider = adaptive(
        "AhakeyPluginMarket.divider",
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    static let controlFill = adaptive(
        "AhakeyPluginMarket.controlFill",
        light: NSColor(white: 0, alpha: 0.05),
        dark: NSColor(white: 1, alpha: 0.08)
    )

    /// Hero 渐变：冷青蓝 → 深蓝，避免紫系套娃。
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(srgbRed: 0.10, green: 0.42, blue: 0.78, alpha: 1)),
                Color(nsColor: NSColor(srgbRed: 0.05, green: 0.22, blue: 0.48, alpha: 1)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let contentPadding: CGFloat = 28
    static let tileCornerRadius: CGFloat = 18
    static let heroCornerRadius: CGFloat = 22
    static let iconTileSize: CGFloat = 56
    static let iconTileCorner: CGFloat = 14
    static let productIconSize: CGFloat = 72

    static let storeTitleFont = Font.system(size: 30, weight: .bold)
    static let sectionTitleFont = Font.system(size: 16, weight: .semibold)
    static let tileTitleFont = Font.system(size: 14, weight: .semibold)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let metaFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}
