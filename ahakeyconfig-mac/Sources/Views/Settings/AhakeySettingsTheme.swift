import AppKit
import SwiftUI

/// Settings 壳色板：随窗口 `NSAppearance` / `preferredColorScheme` 在浅色与深色间切换。
enum AhakeySettingsTheme {
    static let windowBackground = adaptive(
        "AhakeySettings.windowBackground",
        light: NSColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1), // #F4F4F6
        dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let sidebarBackground = adaptive(
        "AhakeySettings.sidebarBackground",
        light: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.937, alpha: 1), // #ECECEF
        dark: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    )
    static let contentBackground = adaptive(
        "AhakeySettings.contentBackground",
        light: NSColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let cardBackground = adaptive(
        "AhakeySettings.cardBackground",
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
    )
    static let cardHover = adaptive(
        "AhakeySettings.cardHover",
        light: NSColor(srgbRed: 0.941, green: 0.941, blue: 0.949, alpha: 1), // #F0F0F2
        dark: NSColor(srgbRed: 0.19, green: 0.19, blue: 0.20, alpha: 1)
    )

    static let primaryText = adaptive(
        "AhakeySettings.primaryText",
        light: NSColor(white: 0, alpha: 0.88),
        dark: NSColor(white: 1, alpha: 0.95)
    )
    static let secondaryText = adaptive(
        "AhakeySettings.secondaryText",
        light: NSColor(white: 0, alpha: 0.48),
        dark: NSColor(white: 1, alpha: 0.45)
    )
    static let tertiaryText = adaptive(
        "AhakeySettings.tertiaryText",
        light: NSColor(white: 0, alpha: 0.32),
        dark: NSColor(white: 1, alpha: 0.32)
    )

    static let accentBlue = adaptive(
        "AhakeySettings.accentBlue",
        light: NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1), // #007AFF
        dark: NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
    )
    static let proGold = adaptive(
        "AhakeySettings.proGold",
        light: NSColor(srgbRed: 0.72, green: 0.56, blue: 0.18, alpha: 1),
        dark: NSColor(srgbRed: 0.85, green: 0.72, blue: 0.38, alpha: 1)
    )
    static let dangerText = adaptive(
        "AhakeySettings.dangerText",
        light: NSColor(srgbRed: 0.86, green: 0.22, blue: 0.20, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.38, alpha: 1)
    )

    static let sidebarSelection = adaptive(
        "AhakeySettings.sidebarSelection",
        light: NSColor(white: 0, alpha: 0.06),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    static let controlFill = adaptive(
        "AhakeySettings.controlFill",
        light: NSColor(white: 0, alpha: 0.06),
        dark: NSColor(white: 1, alpha: 0.10)
    )
    static let divider = adaptive(
        "AhakeySettings.divider",
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.06)
    )

    static let sidebarWidth: CGFloat = 220
    static let contentPadding: CGFloat = 28
    static let cardCornerRadius: CGFloat = 14
    static let rowPaddingH: CGFloat = 18
    static let rowPaddingV: CGFloat = 14

    static let pageTitleFont = Font.system(size: 26, weight: .bold)
    static let sectionTitleFont = Font.system(size: 13, weight: .semibold)
    static let rowTitleFont = Font.system(size: 14, weight: .medium)
    static let rowSubtitleFont = Font.system(size: 12, weight: .regular)
    static let sidebarItemFont = Font.system(size: 13, weight: .medium)

    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: name, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}
