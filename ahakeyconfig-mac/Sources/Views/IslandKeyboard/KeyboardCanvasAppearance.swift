import SwiftUI

/// Visual preset for `AhaKeyKeyboardCanvasView`.
enum KeyboardCanvasAppearance {
    case studioLight
    case vibeBarEmbedded

    var theme: KeyboardCanvasTheme {
        switch self {
        case .studioLight:
            return .studioLight
        case .vibeBarEmbedded:
            return .vibeBarEmbedded
        }
    }

    var layout: KeyboardCanvasLayout {
        switch self {
        case .studioLight:
            return .standard
        case .vibeBarEmbedded:
            return .vibeBarWide
        }
    }
}

/// Coordinate system for the hardware keyboard canvas (109×54 design units by default).
struct KeyboardCanvasLayout {
    let baseWidth: CGFloat
    let baseHeight: CGFloat
    let screwInset: CGFloat
    let keyTrackCenterGen2: CGFloat
    let keyTrackWidthGen2: CGFloat
    let keyTrackCenterX1: CGFloat
    let keyTrackWidthX1: CGFloat
    let magneticPortX: CGFloat
    let magneticSide: CGFloat
    let oledX: CGFloat
    let oledY: CGFloat
    let oledW: CGFloat
    let lightBarXGen2: CGFloat
    let lightBarY: CGFloat
    let lightBarWGen2: CGFloat
    let lightBarX1: CGFloat
    let lightBarWX1: CGFloat

    var aspectRatio: CGFloat { baseWidth / baseHeight }

    var cornerScrewPoints: [CGPoint] {
        let right = baseWidth - screwInset
        let bottom = baseHeight - screwInset
        return [
            CGPoint(x: screwInset, y: screwInset),
            CGPoint(x: right, y: screwInset),
            CGPoint(x: screwInset, y: bottom),
            CGPoint(x: right, y: bottom),
        ]
    }

    static let standard = KeyboardCanvasLayout(
        baseWidth: 109,
        baseHeight: 54,
        screwInset: 5.5,
        keyTrackCenterGen2: 44.5,
        keyTrackWidthGen2: 72,
        keyTrackCenterX1: 43.8,
        keyTrackWidthX1: 67,
        magneticPortX: 75.5,
        magneticSide: 20,
        oledX: 71.3,
        oledY: 7.7,
        oledW: 24.2,
        lightBarXGen2: 9.5,
        lightBarY: 7.7,
        lightBarWGen2: 56.5,
        lightBarX1: 10.2,
        lightBarWX1: 56.3
    )

    /// Extra horizontal span so Key4 and the magnetic port do not overlap in the expanded island.
    static let vibeBarWide = KeyboardCanvasLayout(
        baseWidth: 122,
        baseHeight: 54,
        screwInset: 5.5,
        keyTrackCenterGen2: 42.5,
        keyTrackWidthGen2: 66,
        keyTrackCenterX1: 43.8,
        keyTrackWidthX1: 67,
        magneticPortX: 88.0,
        magneticSide: 20,
        oledX: 83.8,
        oledY: 7.7,
        oledW: 24.2,
        lightBarXGen2: 9.5,
        lightBarY: 7.7,
        lightBarWGen2: 68.0,
        lightBarX1: 10.2,
        lightBarWX1: 56.3
    )
}

struct KeyboardCanvasTheme {
    let chassisFill: AnyShapeStyle
    let chassisStroke: Color
    let chassisShadowColor: Color
    let chassisShadowRadius: CGFloat
    let chassisShadowY: CGFloat
    let innerBezelStroke: Color
    let screwStroke: Color
    let screwFill: Color
    let keyTrackFill: Color
    let keyTrackStroke: Color
    let keyCapFill: AnyShapeStyle
    let keyCapBaseColor: Color
    let keyCapShadowColor: Color
    let keyCapShadowRadius: CGFloat
    let keyCapShadowY: CGFloat
    let keyIconColor: Color
    let keyLabelColor: Color
    let partLabelColor: Color
    let secondaryLabelColor: Color
    let ledSlotFill: Color
    let accentColor: Color
    let hotspotIdleStroke: Color
    let hotspotSelectedStroke: Color
    let hotspotSelectedGlow: Color
    let usesNeumorphicKeyCaps: Bool

    static let studioLight = KeyboardCanvasTheme(
        chassisFill: AnyShapeStyle(
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color(red: 0.92, green: 0.95, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        chassisStroke: Color.black.opacity(0.1),
        chassisShadowColor: Color.black.opacity(0.08),
        chassisShadowRadius: 18,
        chassisShadowY: 14,
        innerBezelStroke: Color.black.opacity(0.06),
        screwStroke: Color.black.opacity(0.14),
        screwFill: Color.white.opacity(0.4),
        keyTrackFill: Color.black.opacity(0.035),
        keyTrackStroke: Color.clear,
        keyCapFill: AnyShapeStyle(
            LinearGradient(
                colors: [Color.white, Color(red: 0.95, green: 0.96, blue: 0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
        ),
        keyCapBaseColor: Color.white,
        keyCapShadowColor: Color.black.opacity(0.12),
        keyCapShadowRadius: 10,
        keyCapShadowY: 4,
        keyIconColor: Color.black.opacity(0.88),
        keyLabelColor: Color.secondary,
        partLabelColor: Color.black.opacity(0.72),
        secondaryLabelColor: Color.secondary,
        ledSlotFill: Color.black.opacity(0.12),
        accentColor: Color.accentColor,
        hotspotIdleStroke: Color.black.opacity(0.015),
        hotspotSelectedStroke: Color.accentColor,
        hotspotSelectedGlow: Color.accentColor.opacity(0.18),
        usesNeumorphicKeyCaps: false
    )

    /// Matches `MacOSVibeBarDesignSystem` tokens (duplicated here so AhaKeyCore stays self-contained).
    static let vibeBarEmbedded = KeyboardCanvasTheme(
        chassisFill: AnyShapeStyle(Color(red: 0.067, green: 0.086, blue: 0.106)),
        chassisStroke: Color.white.opacity(0.08),
        chassisShadowColor: Color.black.opacity(0.25),
        chassisShadowRadius: 8,
        chassisShadowY: 4,
        innerBezelStroke: Color.white.opacity(0.06),
        screwStroke: Color.white.opacity(0.12),
        screwFill: Color(red: 0.047, green: 0.063, blue: 0.078),
        keyTrackFill: Color(red: 0.047, green: 0.063, blue: 0.078),
        keyTrackStroke: Color.white.opacity(0.07),
        keyCapFill: AnyShapeStyle(Color(red: 0.047, green: 0.063, blue: 0.078)),
        keyCapBaseColor: Color(red: 0.047, green: 0.063, blue: 0.078),
        keyCapShadowColor: Color.clear,
        keyCapShadowRadius: 0,
        keyCapShadowY: 0,
        keyIconColor: Color(red: 0.953, green: 0.965, blue: 0.980),
        keyLabelColor: Color(red: 0.651, green: 0.686, blue: 0.729),
        partLabelColor: Color(red: 0.651, green: 0.686, blue: 0.729),
        secondaryLabelColor: Color(red: 0.435, green: 0.471, blue: 0.514),
        ledSlotFill: Color.black.opacity(0.35),
        accentColor: Color(red: 0.337, green: 0.761, blue: 1.000),
        hotspotIdleStroke: Color.white.opacity(0.06),
        hotspotSelectedStroke: Color(red: 0.337, green: 0.761, blue: 1.000),
        hotspotSelectedGlow: Color(red: 0.337, green: 0.761, blue: 1.000).opacity(0.22),
        usesNeumorphicKeyCaps: true
    )
}

struct NeumorphicRecessedSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Color
    let stroke: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.45), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                ),
                                lineWidth: 1
                            )
                    }
                    .overlay(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.08)],
                                    startPoint: .center,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            )
    }
}

extension View {
    func neumorphicRecessed(
        cornerRadius: CGFloat,
        fill: Color,
        stroke: Color = Color.white.opacity(0.07)
    ) -> some View {
        modifier(NeumorphicRecessedSurface(cornerRadius: cornerRadius, fill: fill, stroke: stroke))
    }
}
