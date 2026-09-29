import CoreGraphics

/// Geometry matches DynamicNotchKit 1.0.0's pinned NotchView/NotchShape layout.
/// Reported content frames exclude its safe-area and shape padding, and window shadows.
enum VibeBarHoverGeometry {
    static func compactFrame(leading: CGRect?, trailing: CGRect?, screen: CGRect, height: CGFloat) -> CGRect? {
        guard let leading, let trailing, height > 0,
              leading.width > 0, trailing.width > 0,
              screen.contains(leading.center), screen.contains(trailing.center),
              leading.maxX <= trailing.minX else { return nil }
        // Each side has 8pt safe-area padding + 6pt shape padding; mask inset is 0.5pt.
        return CGRect(x: leading.minX - 13.5, y: screen.maxY - height,
                      width: trailing.maxX - leading.minX + 27, height: height)
    }

    static func expandedFrame(content: CGRect, screen: CGRect) -> CGRect {
        // 15pt safe-area + 15pt shape padding horizontally, and 15pt bottom inset.
        CGRect(x: content.minX - 29.5, y: content.minY - 15,
               width: content.width + 59, height: screen.maxY - content.minY + 15)
    }

    static func shouldExpand(at point: CGPoint, compactFrame: CGRect?, pressedMouseButtons: Int) -> Bool {
        guard pressedMouseButtons == 0, let compactFrame else { return false }
        return contains(point, frame: compactFrame, topRadius: 6, bottomRadius: 14)
    }

    static func contains(_ point: CGPoint, frame: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return false }
        // AppKit uses a bottom-left origin; this is the same concave-top / rounded-bottom
        // outline as the SwiftUI mask, expressed in global screen coordinates.
        let t = topRadius
        let b = bottomRadius
        let x = frame.minX, y = frame.minY, right = frame.maxX, top = frame.maxY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: top))
        path.addQuadCurve(to: CGPoint(x: x + t, y: top - t), control: CGPoint(x: x + t, y: top))
        path.addLine(to: CGPoint(x: x + t, y: y + b))
        path.addQuadCurve(to: CGPoint(x: x + t + b, y: y), control: CGPoint(x: x + t, y: y))
        path.addLine(to: CGPoint(x: right - t - b, y: y))
        path.addQuadCurve(to: CGPoint(x: right - t, y: y + b), control: CGPoint(x: right - t, y: y))
        path.addLine(to: CGPoint(x: right - t, y: top - t))
        path.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: right - t, y: top))
        path.closeSubpath()
        return path.contains(point)
    }

    static func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { $0.contains(point) }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
