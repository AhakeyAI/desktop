import SwiftUI

public enum AhaKeyAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public static let storageKey = "AhaKey.AppearanceMode"

    /// 新安装默认深色；已有用户保留其持久化选择。
    public static let defaultMode: AhaKeyAppearanceMode = .dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }

    /// `nil` 表示跟随系统外观。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var next: AhaKeyAppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
}

public enum AhaKeyUI {
    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 12
        public static let pill: CGFloat = 999
    }

    public enum Spacing {
        public static let shell: CGFloat = 5
        public static let page: CGFloat = 24
        public static let panel: CGFloat = 14
    }

    public enum Font {
        public static let largeTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        public static let title1 = SwiftUI.Font.system(size: 20, weight: .semibold)
        public static let title2 = SwiftUI.Font.system(size: 17, weight: .semibold)
        public static let title3 = SwiftUI.Font.system(size: 15, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 15)
        public static let callout = SwiftUI.Font.system(size: 14)
        public static let subhead = SwiftUI.Font.system(size: 13, weight: .medium)
        public static let footnote = SwiftUI.Font.system(size: 12)
        public static let caption = SwiftUI.Font.system(size: 11)
    }

    public enum ColorToken {
        public static var base: Color { Color(nsColor: .windowBackgroundColor) }
        public static var card: Color { Color(nsColor: .controlBackgroundColor) }
        public static var control: Color { Color(nsColor: .textBackgroundColor).opacity(0.72) }
        public static var canvas: Color { Color(nsColor: .underPageBackgroundColor) }
        public static var hover: Color { Color.primary.opacity(0.06) }
        public static var border: Color { Color.primary.opacity(0.10) }
        public static var borderStrong: Color { Color.primary.opacity(0.18) }
        public static var primary: Color { Color.accentColor }
        public static var success: Color { .green }
        public static var warning: Color { .orange }
    }
}

public struct AhaKeySurface: ViewModifier {
    private let radius: CGFloat

    public init(radius: CGFloat = AhaKeyUI.Radius.large) {
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(AhaKeyUI.ColorToken.card.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
            )
    }
}

public struct AhaKeyPanel: ViewModifier {
    private let isRemark: Bool

    public init(isRemark: Bool = false) {
        self.isRemark = isRemark
    }

    public func body(content: Content) -> some View {
        content
            .padding(isRemark ? 12 : AhaKeyUI.Spacing.panel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                    .fill(AhaKeyUI.ColorToken.control.opacity(isRemark ? 0.62 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                    .strokeBorder(
                        isRemark ? AhaKeyUI.ColorToken.borderStrong : AhaKeyUI.ColorToken.border,
                        style: StrokeStyle(lineWidth: 1, dash: isRemark ? [5, 4] : [])
                    )
            )
    }
}

public struct AhaKeyPill: ViewModifier {
    private let accent: Color?

    public init(accent: Color? = nil) {
        self.accent = accent
    }

    public func body(content: Content) -> some View {
        content
            .font(AhaKeyUI.Font.subhead)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.pill, style: .continuous)
                    .fill((accent ?? AhaKeyUI.ColorToken.control).opacity(accent == nil ? 1 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.pill, style: .continuous)
                    .strokeBorder((accent ?? AhaKeyUI.ColorToken.border).opacity(accent == nil ? 1 : 0.35), lineWidth: 1)
            )
    }
}

public struct AhaKeyPlainPanelGroupBoxStyle: GroupBoxStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(AhaKeyUI.Font.subhead.weight(.semibold))
                .foregroundStyle(.primary)
            configuration.content
        }
        .modifier(AhaKeyPanel())
    }
}

public struct AhaKeyPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AhaKeyUI.Font.subhead.weight(.semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(AhaKeyUI.ColorToken.primary.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

public struct AhaKeySecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AhaKeyUI.Font.subhead.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? AhaKeyUI.ColorToken.hover : AhaKeyUI.ColorToken.control)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
            )
    }
}

public struct AhaKeyIconButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? AhaKeyUI.ColorToken.hover : AhaKeyUI.ColorToken.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                    .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
            )
    }
}

public extension View {
    func ahaKeySurface(radius: CGFloat = AhaKeyUI.Radius.large) -> some View {
        modifier(AhaKeySurface(radius: radius))
    }

    func ahaKeyPanel() -> some View {
        modifier(AhaKeyPanel())
    }

    func ahaKeyRemarkPanel() -> some View {
        modifier(AhaKeyPanel(isRemark: true))
    }

    func ahaKeyPill(accent: Color? = nil) -> some View {
        modifier(AhaKeyPill(accent: accent))
    }
}

