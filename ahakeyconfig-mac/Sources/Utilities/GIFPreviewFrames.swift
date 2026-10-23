import Foundation
import CoreGraphics
import ImageIO

/// Decoded preview frames only; never changes source artwork or device payloads.
@MainActor
final class GIFPreviewFrames {
    private var source: CGImageSource?
    private var loadedPath: String?
    private var maximumPixelSize = 320
    private var sourceSize = CGSize.zero
    private var viewport = CGSize.zero
    private var backingScale: CGFloat = 2
    private let cache = NSCache<NSNumber, CGImage>()
    private(set) var count = 0
    private(set) var thumbnailPixelSize = 320

    // A complete 120-frame Retina LCD loop is about 17 MiB including row
    // alignment. Keep it reusable instead of evicting it just before it loops.
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }

    @discardableResult
    func load(path: String, maximumPixelSize: Int) -> Bool {
        let limit = max(1, maximumPixelSize)
        guard loadedPath != path || self.maximumPixelSize != limit else { return false }
        loadedPath = path
        self.maximumPixelSize = limit
        thumbnailPixelSize = limit
        cache.removeAllObjects()
        source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary)
        count = source.map(CGImageSourceGetCount) ?? 0
        sourceSize = .zero
        if let source, count > 0,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            sourceSize = CGSize(width: width.doubleValue, height: height.doubleValue)
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            if (5...8).contains(orientation) {
                sourceSize = CGSize(width: sourceSize.height, height: sourceSize.width)
            }
        }
        thumbnailPixelSize = fittedPixelLimit()
        return true
    }

    @discardableResult
    func updateViewport(size: CGSize, backingScale: CGFloat) -> Bool {
        // SwiftUI can briefly supply a zero-sized layout while hiding/reparenting.
        // Keep the last valid resolution and its cache through that transition.
        guard size.width.isFinite, size.height.isFinite, backingScale.isFinite,
              size.width > 0, size.height > 0, backingScale > 0 else { return false }
        viewport = size
        self.backingScale = backingScale
        let target = fittedPixelLimit()
        guard target != thumbnailPixelSize else { return false }
        thumbnailPixelSize = target
        cache.removeAllObjects()
        return true
    }

    private func fittedPixelLimit() -> Int {
        guard sourceSize.width > 0, sourceSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return maximumPixelSize }
        // Match contentsGravity.resizeAspect, including Retina backing pixels.
        // A square inside a wide LCD is limited by its displayed height, not by
        // the full LCD width or the fixed maximum used for a large preview.
        let fit = min(viewport.width / sourceSize.width, viewport.height / sourceSize.height)
        let needed = ceil(max(sourceSize.width, sourceSize.height) * fit * backingScale)
        guard needed.isFinite, needed < CGFloat(maximumPixelSize) else { return maximumPixelSize }
        return max(1, Int(needed))
    }

    func image(at index: Int) -> CGImage? {
        guard index >= 0, index < count, let source else { return nil }
        let key = NSNumber(value: index)
        if let frame = cache.object(forKey: key) { return frame }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { return nil }
        cache.setObject(frame, forKey: key, cost: frame.bytesPerRow * frame.height)
        return frame
    }
}
