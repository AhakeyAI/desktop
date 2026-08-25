import CoreGraphics
import Foundation
import ImageIO

// MARK: - OLED RGB565 帧编码核心（WBS-5.6 切片 5b）
//
// 生产唯一实现：App 侧 `OLEDFrameEncoder`（Utilities）与本核心同源——App 壳只负责
// 错误文案与 AhaKeyCommand 常量注入，编码算法全部在这里。Agent（AhaKeyConfigAgent target）
// 经本核心把 CAS 里的 GIF/PNG 源编码为 160×80 RGB565 帧（每帧 25600B），再按 flash
// 物理槽 28672B 步长写地址。绝不允许把 CAS 源字节直接当 flash 数据。

public enum AhaKeyOLEDFrameEncoderCore {

    public enum EncodingError: Error, Equatable {
        case cannotCreateImageSource
        case noFrames
        case cannotCreateContext
        case sourceFileTooLarge(fileSize: Int, maxBytes: Int)
        case tooManyFrames(count: Int, max: Int)
    }

    /// 面板物理参数（与固件/AhaKeyCommand 对齐；Shared 不能引用 App 侧常量，故在此处冻结）。
    public static let width = 160
    public static let height = 80
    public static let encodedFrameBytes = width * height * 2 // 25600
    public static let frameSlotBytes = 28_672

    public static func frameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    public static func sourceFileByteCount(at url: URL) -> Int? {
        if let v = try? url.resourceValues(forKeys: [.fileSizeKey]), let n = v.fileSize { return n }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? Int {
            return n
        }
        return nil
    }

    /// 从 GIF/PNG/JPEG 等图片源提取帧并编码为 RGB565（每帧恰好 25600B，大端）。
    /// 静态图片按 1 帧处理；帧数超过 maxFrames 时均匀抽帧。
    public static func frames(
        fromImageAt url: URL,
        maxFrames: Int,
        maxSourceFileBytes: Int
    ) throws -> [Data] {
        if let n = sourceFileByteCount(at: url), n > maxSourceFileBytes {
            throw EncodingError.sourceFileTooLarge(fileSize: n, maxBytes: maxSourceFileBytes)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw EncodingError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw EncodingError.noFrames }

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
        guard !frames.isEmpty else { throw EncodingError.noFrames }
        return frames
    }

    /// 编码后的帧拼接为连续字节流（flash 写入程序按 offset/length 切片引用）。
    public static func encodedStream(frames: [Data]) -> Data {
        var stream = Data(capacity: frames.count * encodedFrameBytes)
        for frame in frames { stream.append(frame) }
        return stream
    }

    // MARK: - 私有

    private static func encodeFrame(_ image: CGImage) throws -> Data {
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
            throw EncodingError.cannotCreateContext
        }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let drawRect = CGRect(
            x: (Double(width) - Double(image.width) * scale) / 2,
            y: (Double(height) - Double(image.height) * scale) / 2,
            width: Double(image.width) * scale,
            height: Double(image.height) * scale
        )
        context.draw(image, in: drawRect)

        // 每帧恰好 25600B RGB565 大端；flash 物理帧槽 28672B，剩余 3072B 由地址递增留空。
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
