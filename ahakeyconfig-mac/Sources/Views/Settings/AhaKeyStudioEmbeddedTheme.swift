import SwiftUI

/// 嵌入 Settings 硬件 Tab 的 Studio 色板；与 `AhakeySettingsTheme` 共用自适应 token。
enum AhaKeyStudioEmbeddedTheme {
    static var windowBackground: Color { AhakeySettingsTheme.windowBackground }
    static var contentBackground: Color { AhakeySettingsTheme.contentBackground }
    static var cardBackground: Color { AhakeySettingsTheme.cardBackground }
    static var cardHover: Color { AhakeySettingsTheme.cardHover }

    static var primaryText: Color { AhakeySettingsTheme.primaryText }
    static var secondaryText: Color { AhakeySettingsTheme.secondaryText }
    static var tertiaryText: Color { AhakeySettingsTheme.tertiaryText }

    static var accentBlue: Color { AhakeySettingsTheme.accentBlue }
    static var divider: Color { AhakeySettingsTheme.divider }
    static var controlFill: Color { AhakeySettingsTheme.controlFill }
}

enum AhaKeyStudioPresentation {
    case standalone
    case embeddedClient
}
