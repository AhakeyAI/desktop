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
        case sourceSizeUnavailable
        case tooManyFrames(count: Int, max: Int)
    }

    /// 面板物理参数（与固件/AhaKeyCommand 对齐；Shared 不能引用 App 侧常量，故在此处冻结）。
    public static let width = 160
    public static let height = 80
    public static let encodedFrameBytes = width * height * 2 // 25600
    public static let frameSlotBytes = 28_672
    /// Studio 选图输入上限；planner 2 MiB 仍约束 CAS 受理字节，不得在此放宽。
    public static let studioMaxSourceFileBytes = 20 * 1024 * 1024

    /// 预检结果：实际跑过 RGB565 编码后的帧数/尺寸/预算，供申报元数据与二次编码对照。
    public struct NormalizationResult: Equatable, Sendable {
        public let frameCount: Int
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let encodedByteCount: Int
        public let encodedFrames: [Data]
        public let normalizedGIFURL: URL

        public init(
            frameCount: Int,
            pixelWidth: Int,
            pixelHeight: Int,
            encodedByteCount: Int,
            encodedFrames: [Data],
            normalizedGIFURL: URL
        ) {
            self.frameCount = frameCount
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.encodedByteCount = encodedByteCount
            self.encodedFrames = encodedFrames
            self.normalizedGIFURL = normalizedGIFURL
        }
    }

    public static func frameCount(at url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    public static func sourceFileByteCount(at url: URL) -> Int? {
        if let override = testingSourceByteCountOverride {
            return override(url)
        }
        if let v = try? url.resourceValues(forKeys: [.fileSizeKey]), let n = v.fileSize { return n }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? Int {
            return n
        }
        return nil
    }

    /// 测试 seam：强制“大小不可得”或注入字节数。生产路径必须保持 nil。
    public static var testingSourceByteCountOverride: ((URL) -> Int?)?

    /// 源文件必须能证明不超过输入上限：已知大小直接比较；元数据不可得则有界读取，再失败则 fail-closed。
    public static func enforceSourceSizeLimit(at url: URL, maxSourceFileBytes: Int) throws {
        if let n = sourceFileByteCount(at: url) {
            if n > maxSourceFileBytes {
                throw EncodingError.sourceFileTooLarge(fileSize: n, maxBytes: maxSourceFileBytes)
            }
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var total = 0
            while true {
                try Task.checkCancellation()
                if total > maxSourceFileBytes {
                    throw EncodingError.sourceFileTooLarge(fileSize: total, maxBytes: maxSourceFileBytes)
                }
                let chunk = handle.readData(ofLength: min(64 * 1024, maxSourceFileBytes + 1 - total))
                if chunk.isEmpty { break }
                total += chunk.count
            }
            if total > maxSourceFileBytes {
                throw EncodingError.sourceFileTooLarge(fileSize: total, maxBytes: maxSourceFileBytes)
            }
        } catch let error as EncodingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EncodingError.sourceSizeUnavailable
        }
    }

    /// 均匀抽帧下标：与 Agent 二次编码使用同一公式。`maxFrames` 是每素材固定 `framesPerSlot`（当前 30），
    /// 不是本次 0x99 的 `userSlotLimit`；设备总容量仍由 Agent 用协商能力做最终 planner 门禁。
    public static func sampledFrameIndexes(sourceCount: Int, maxFrames: Int) -> [Int] {
        guard sourceCount > 0 else { return [] }
        let cappedCount = max(1, maxFrames)
        if sourceCount <= cappedCount { return Array(0 ..< sourceCount) }
        if cappedCount == 1 { return [0] }
        return (0 ..< cappedCount).map {
            Int((Double($0) * Double(sourceCount - 1) / Double(cappedCount - 1)).rounded())
        }
    }

    /// 从 GIF/PNG/JPEG 等图片源提取帧并编码为 RGB565（每帧恰好 25600B，大端）。
    /// 静态图片按 1 帧处理；帧数超过 maxFrames 时均匀抽帧。
    public static func frames(
        fromImageAt url: URL,
        maxFrames: Int,
        maxSourceFileBytes: Int
    ) throws -> [Data] {
        try rasterizedFrames(
            fromImageAt: url,
            maxFrames: maxFrames,
            maxSourceFileBytes: maxSourceFileBytes
        ).map(\.encoded)
    }

    /// 受理前预检：真实编码 160×80 RGB565，并写出可供 CAS 受理的规范化 GIF。
    /// 申报帧数/宽高必须来自本结果，不得抄源文件元数据。
    public static func normalize(
        fromImageAt url: URL,
        maxFrames: Int,
        maxSourceFileBytes: Int,
        writingGIFTo destinationURL: URL
    ) throws -> NormalizationResult {
        let rasterized = try rasterizedFrames(
            fromImageAt: url,
            maxFrames: maxFrames,
            maxSourceFileBytes: maxSourceFileBytes
        )
        try writeGIF(images: rasterized.map(\.image), to: destinationURL)
        let encodedFrames = rasterized.map(\.encoded)
        return NormalizationResult(
            frameCount: encodedFrames.count,
            pixelWidth: width,
            pixelHeight: height,
            encodedByteCount: encodedFrames.count * encodedFrameBytes,
            encodedFrames: encodedFrames,
            normalizedGIFURL: destinationURL
        )
    }

    /// 编码后的帧拼接为连续字节流（flash 写入程序按 offset/length 切片引用）。
    public static func encodedStream(frames: [Data]) -> Data {
        var stream = Data(capacity: frames.count * encodedFrameBytes)
        for frame in frames { stream.append(frame) }
        return stream
    }

    // MARK: - 私有

    private struct RasterizedFrame {
        let image: CGImage
        let encoded: Data
    }

    private static func rasterizedFrames(
        fromImageAt url: URL,
        maxFrames: Int,
        maxSourceFileBytes: Int
    ) throws -> [RasterizedFrame] {
        try enforceSourceSizeLimit(at: url, maxSourceFileBytes: maxSourceFileBytes)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw EncodingError.cannotCreateImageSource
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw EncodingError.noFrames }

        let indexes = sampledFrameIndexes(sourceCount: count, maxFrames: maxFrames)
        var frames: [RasterizedFrame] = []
        frames.reserveCapacity(indexes.count)
        for index in indexes {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(try encodeFrame(image))
        }
        guard !frames.isEmpty else { throw EncodingError.noFrames }
        return frames
    }

    private static func encodeFrame(_ image: CGImage) throws -> RasterizedFrame {
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
        guard let normalized = context.makeImage() else {
            throw EncodingError.cannotCreateContext
        }

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
        return RasterizedFrame(image: normalized, encoded: data)
    }

    private static func writeGIF(images: [CGImage], to url: URL) throws {
        guard !images.isEmpty else { throw EncodingError.noFrames }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            images.count,
            nil
        ) else {
            throw EncodingError.cannotCreateImageSource
        }
        for image in images {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.cannotCreateImageSource
        }
    }
}
