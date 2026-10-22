import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum OLEDFrameEncodingError: LocalizedError {
    case cannotCreateImageSource
    case noFrames
    case cannotCreateContext
    case sourceFileTooLarge(fileSize: Int, maxBytes: Int)
    case tooManyFrames(count: Int, max: Int)
    case invalidTargetCapacity

    var errorDescription: String? {
        switch self {
        case .cannotCreateImageSource:
            return NSLocalizedString("无法读取图片或 GIF。", comment: "")
        case .invalidTargetCapacity:
            return NSLocalizedString("素材位置容量无效，请重新读取键盘。", comment: "")
        case .noFrames:
            return NSLocalizedString("没有可编码的图片帧。", comment: "")
        case .cannotCreateContext:
            return NSLocalizedString("无法创建 LCD 编码上下文。", comment: "")
        case .sourceFileTooLarge(let fileSize, let maxBytes):
            let f = ByteCountFormatter()
            f.allowedUnits = [.useMB, .useKB, .useBytes]
            f.countStyle = .file
            let a = f.string(fromByteCount: Int64(fileSize))
            let b = f.string(fromByteCount: Int64(maxBytes))
            return "图片源文件约 \(a)，超过单文件上限 \(b)。请压缩分辨率、减少帧数或缩短动图后再试。"
        case .tooManyFrames(let count, let max):
            return "当前动图共有 \(count) 帧，超过单模式上限 \(max) 帧。请减少帧数或缩短动图后再试。"
        }
    }
}

enum OLEDFrameEncoder {
    struct PreparedFrames: Sendable {
        let frames: [Data]
        let previewPNG: Data
        let sourceFrameCount: Int
        let wasResized: Bool
    }

    static func adaptedFrames(at url: URL, maximumFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws -> PreparedFrames {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        let indices = try frameSelection(sourceCount: count, maximumFrames: maximumFrames)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(AhaKeyCommand.oledWidth, AhaKeyCommand.oledHeight),
            kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        var encoded: [Data] = [], previewPNG: Data?
        encoded.reserveCapacity(indices.count)
        for index in indices {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else {
                    throw OLEDFrameEncodingError.cannotCreateImageSource
                }
                encoded.append(try encodeFrame(image))
                if previewPNG == nil {
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                        throw OLEDFrameEncodingError.cannotCreateContext
                    }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw OLEDFrameEncodingError.cannotCreateContext }
                    previewPNG = data as Data
                }
            }
        }
        try Task.checkCancellation()
        guard let previewPNG else { throw OLEDFrameEncodingError.noFrames }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let resized = width > AhaKeyCommand.oledWidth || height > AhaKeyCommand.oledHeight || orientation != 1 ||
            (sourceFileByteCount(at: url) ?? 0) > AhaKeyCommand.oledMaxSourceFileBytes
        return PreparedFrames(frames: encoded, previewPNG: previewPNG, sourceFrameCount: count, wasResized: resized)
    }

    /// Keep the whole animation represented, including its first and last frame.
    static func frameSelection(sourceCount: Int, maximumFrames: Int) throws -> [Int] {
        guard sourceCount > 0 else { throw OLEDFrameEncodingError.noFrames }
        guard (1...AhaKeyCommand.oledMaxFramesPerMode).contains(maximumFrames) else { throw OLEDFrameEncodingError.invalidTargetCapacity }
        if sourceCount <= maximumFrames { return Array(0..<sourceCount) }
        if maximumFrames == 1 { return [0] }
        let steps = maximumFrames - 1, span = sourceCount - 1
        let quotient = span / steps, remainder = span % steps
        return (0..<maximumFrames).map { $0 * quotient + ($0 * remainder) / steps }
    }

    static func adaptedFrameCount(at url: URL, maximumFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }
        return try frameSelection(sourceCount: CGImageSourceGetCount(source), maximumFrames: maximumFrames).count
    }
    static func frameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    /// 源 GIF 文件字节数；无法读取时返回 `nil`。
    static func sourceFileByteCount(at url: URL) -> Int? {
        if let v = try? url.resourceValues(forKeys: [.fileSizeKey]), let n = v.fileSize { return n }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? Int {
            return n
        }
        return nil
    }

    /// 若超过 `AhaKeyCommand.oledMaxSourceFileBytes` 则抛出 `sourceFileTooLarge`。
    static func validateGIFSourceFileSize(at url: URL) throws {
        guard let n = sourceFileByteCount(at: url) else {
            return
        }
        guard n <= AhaKeyCommand.oledMaxSourceFileBytes else {
            throw OLEDFrameEncodingError.sourceFileTooLarge(fileSize: n, maxBytes: AhaKeyCommand.oledMaxSourceFileBytes)
        }
    }

    static func validateFrameCount(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw OLEDFrameEncodingError.noFrames
        }
        guard count <= AhaKeyCommand.oledMaxFramesPerMode else {
            throw OLEDFrameEncodingError.tooManyFrames(count: count, max: AhaKeyCommand.oledMaxFramesPerMode)
        }
    }

    static func frames(fromGIFAt url: URL, maximumFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws -> [Data] {
        try validateGIFSourceFileSize(at: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw OLEDFrameEncodingError.noFrames
        }
        guard count <= maximumFrames else {
            throw OLEDFrameEncodingError.tooManyFrames(count: count, max: maximumFrames)
        }

        var frames: [Data] = []
        frames.reserveCapacity(count)
        for index in 0 ..< count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw OLEDFrameEncodingError.cannotCreateImageSource }
            frames.append(try encodeFrame(image))
        }

        guard !frames.isEmpty else {
            throw OLEDFrameEncodingError.noFrames
        }
        return frames
    }

    private static func encodeFrame(_ image: CGImage) throws -> Data {
        let width = AhaKeyCommand.oledWidth
        let height = AhaKeyCommand.oledHeight
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OLEDFrameEncodingError.cannotCreateContext
        }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawWidth = Double(image.width) * scale
        let drawHeight = Double(image.height) * scale
        let drawRect = CGRect(
            x: (Double(width) - drawWidth) / 2,
            y: (Double(height) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        context.draw(image, in: drawRect)

        // 每帧恰好 160*80*2 = 25600 字节 RGB565 大端，原厂 Python 也不做 padding。
        // flash 物理帧槽是 28672 字节，剩下的 3072 字节由 address 递增自然留空。
        var data = Data(capacity: width * height * 2)
        for pixel in stride(from: 0, to: rgba.count, by: bytesPerPixel) {
            let red = UInt16(rgba[pixel])
            let green = UInt16(rgba[pixel + 1])
            let blue = UInt16(rgba[pixel + 2])
            let rgb565 = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
            data.append(UInt8((rgb565 >> 8) & 0xFF))
            data.append(UInt8(rgb565 & 0xFF))
        }
        return data
    }
}
