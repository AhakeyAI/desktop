import CoreGraphics

enum VibeBarHoverGeometry {
    static let hotZoneWidth: CGFloat = 440
    static let hotZoneHeight: CGFloat = 58
    static let expandedInteractionHeight: CGFloat = 210

    static func topHotZone(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - hotZoneWidth / 2,
            y: screenFrame.maxY - hotZoneHeight,
            width: hotZoneWidth,
            height: hotZoneHeight
        )
    }

    static func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { $0.contains(point) }
    }

    static func screenIndex(withTopHotZoneContaining point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { topHotZone(in: $0).contains(point) }
    }

    static func expandedInteractionZone(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - hotZoneWidth / 2,
            y: screenFrame.maxY - expandedInteractionHeight,
            width: hotZoneWidth,
            height: expandedInteractionHeight
        )
    }

    static func screenIndex(withExpandedInteractionZoneContaining point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { expandedInteractionZone(in: $0).contains(point) }
    }
}
