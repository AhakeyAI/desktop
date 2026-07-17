import CoreGraphics
import Foundation
import ImageIO

enum OLEDFrameEncodingError: LocalizedError {
    case cannotCreateImageSource
    case noFrames
    case cannotCreateContext
    case sourceFileTooLarge(fileSize: Int, maxBytes: Int)
    case tooManyFrames(count: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .cannotCreateImageSource:
            return NSLocalizedString("无法读取图片文件。", comment: "")
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
            return String(format: NSLocalizedString("图片源文件约 %@，超过单文件上限 %@。请压缩分辨率、减少帧数或缩短图片后再试。", comment: ""), a, b)
        case .tooManyFrames(let count, let max):
            return String(format: NSLocalizedString("当前图片共有 %d 帧，超过单模式上限 %d 帧。请减少帧数或缩短图片后再试。", comment: ""), count, max)
        }
    }
}

enum OLEDFrameEncoder {
    static func frameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    /// 源图片文件字节数；无法读取时返回 `nil`。
    static func sourceFileByteCount(at url: URL) -> Int? {
        if let v = try? url.resourceValues(forKeys: [.fileSizeKey]), let n = v.fileSize { return n }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? Int {
            return n
        }
        return nil
    }

    /// 若超过 `AhaKeyCommand.oledMaxSourceFileBytes` 则抛出 `sourceFileTooLarge`。
    static func validateSourceFileSize(at url: URL) throws {
        guard let n = sourceFileByteCount(at: url) else {
            return
        }
        guard n <= AhaKeyCommand.oledMaxSourceFileBytes else {
            throw OLEDFrameEncodingError.sourceFileTooLarge(fileSize: n, maxBytes: AhaKeyCommand.oledMaxSourceFileBytes)
        }
    }

    /// 与 `validateSourceFileSize` 同名别名，任务图代码统一使用。
    static func validateGIFSourceFileSize(at url: URL) throws {
        try validateSourceFileSize(at: url)
    }

    static func validateFrameCount(at url: URL, maxFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw OLEDFrameEncodingError.noFrames
        }
        guard count <= maxFrames else {
            throw OLEDFrameEncodingError.tooManyFrames(count: count, max: maxFrames)
        }
    }

    /// 从 GIF/PNG/JPEG 等图片源提取帧。静态图片（如 PNG）会被当成 1 帧处理；
    /// GIF 帧数超过 `maxFrames` 时均匀抽帧。
    static func frames(fromGIFAt url: URL, maxFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws -> [Data] {
        try validateSourceFileSize(at: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OLEDFrameEncodingError.cannotCreateImageSource
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            throw OLEDFrameEncodingError.noFrames
        }
        let cappedCount = max(1, maxFrames)
        let indexes: [Int]
        if count <= cappedCount {
            indexes = Array(0 ..< count)
        } else if cappedCount == 1 {
            indexes = [0]
        } else {
            indexes = (0 ..< cappedCount).map {
                Int((Double($0) * Double(count - 1) / Double(cappedCount - 1)).rounded())
            }
        }

        var frames: [Data] = []
        frames.reserveCapacity(indexes.count)
        for index in indexes {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(try encodeFrame(image))
        }

        guard !frames.isEmpty else {
            throw OLEDFrameEncodingError.noFrames
        }
        return frames
    }

    /// 旧接口别名，兼容仍调用 `fromImageAt` 的代码。
    static func frames(fromImageAt url: URL) throws -> [Data] {
        try frames(fromGIFAt: url, maxFrames: AhaKeyCommand.oledMaxFramesPerMode)
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
