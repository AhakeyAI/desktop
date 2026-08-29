import AhaKeyConfigShared
import Foundation
import ImageIO

// App 侧壳：编码算法已下沉 `AhaKeyOLEDFrameEncoderCore`（Shared，Agent 同源复用）。
// 本文件只保留 AhaKeyCommand 常量注入与本地化错误文案，Views 调用面不变。

enum OLEDFrameEncodingError: LocalizedError {
    case cannotCreateImageSource
    case noFrames
    case cannotCreateContext
        case sourceFileTooLarge(fileSize: Int, maxBytes: Int)
        case sourceSizeUnavailable
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
        case .sourceSizeUnavailable:
            return NSLocalizedString("无法确认图片文件大小，拒绝绕过 20 MB 输入上限。", comment: "")
        case .tooManyFrames(let count, let max):
            return String(format: NSLocalizedString("当前图片共有 %d 帧，超过单模式上限 %d 帧。请减少帧数或缩短图片后再试。", comment: ""), count, max)
        }
    }

    /// Shared 核心错误 → App 文案错误（编码路径唯一，文案留在 App 侧）。
    init(_ core: AhaKeyOLEDFrameEncoderCore.EncodingError) {
        switch core {
        case .cannotCreateImageSource: self = .cannotCreateImageSource
        case .noFrames: self = .noFrames
        case .cannotCreateContext: self = .cannotCreateContext
        case .sourceFileTooLarge(let s, let m): self = .sourceFileTooLarge(fileSize: s, maxBytes: m)
        case .sourceSizeUnavailable: self = .sourceSizeUnavailable
        case .tooManyFrames(let c, let m): self = .tooManyFrames(count: c, max: m)
        }
    }
}

enum OLEDFrameEncoder {
    static func frameCount(at url: URL) -> Int {
        AhaKeyOLEDFrameEncoderCore.frameCount(at: url)
    }

    /// 源图片文件字节数；无法读取时返回 `nil`。
    static func sourceFileByteCount(at url: URL) -> Int? {
        AhaKeyOLEDFrameEncoderCore.sourceFileByteCount(at: url)
    }

    /// 若超过 `AhaKeyCommand.oledMaxSourceFileBytes` 则抛出 `sourceFileTooLarge`。
    /// 文件大小不可读取时 fail-closed，不得跳过上限。
    static func validateSourceFileSize(at url: URL) throws {
        do {
            try AhaKeyOLEDFrameEncoderCore.enforceSourceSizeLimit(
                at: url,
                maxSourceFileBytes: AhaKeyCommand.oledMaxSourceFileBytes
            )
        } catch let error as AhaKeyOLEDFrameEncoderCore.EncodingError {
            throw OLEDFrameEncodingError(error)
        }
    }

    /// 与 `validateSourceFileSize` 同名别名，任务图代码统一使用。
    static func validateGIFSourceFileSize(at url: URL) throws {
        try validateSourceFileSize(at: url)
    }

    static func validateFrameCount(at url: URL, maxFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws {
        let count = AhaKeyOLEDFrameEncoderCore.frameCount(at: url)
        guard count > 0 else { throw OLEDFrameEncodingError.noFrames }
        guard count <= maxFrames else {
            throw OLEDFrameEncodingError.tooManyFrames(count: count, max: maxFrames)
        }
    }

    /// 从 GIF/PNG/JPEG 等图片源提取帧。静态图片（如 PNG）会被当成 1 帧处理；
    /// GIF 帧数超过 `maxFrames` 时均匀抽帧。
    static func frames(fromGIFAt url: URL, maxFrames: Int = AhaKeyCommand.oledMaxFramesPerMode) throws -> [Data] {
        do {
            return try AhaKeyOLEDFrameEncoderCore.frames(
                fromImageAt: url,
                maxFrames: maxFrames,
                maxSourceFileBytes: AhaKeyCommand.oledMaxSourceFileBytes
            )
        } catch let error as AhaKeyOLEDFrameEncoderCore.EncodingError {
            throw OLEDFrameEncodingError(error)
        }
    }

    /// 受理前预检：真实 160×80 编码 + 容量抽帧，并写出规范化 GIF。
    static func normalize(
        fromImageAt url: URL,
        maxFrames: Int = AhaKeyCommand.oledMaxFramesPerMode,
        writingGIFTo destinationURL: URL
    ) throws -> AhaKeyOLEDFrameEncoderCore.NormalizationResult {
        do {
            return try AhaKeyOLEDFrameEncoderCore.normalize(
                fromImageAt: url,
                maxFrames: maxFrames,
                maxSourceFileBytes: AhaKeyCommand.oledMaxSourceFileBytes,
                writingGIFTo: destinationURL
            )
        } catch let error as AhaKeyOLEDFrameEncoderCore.EncodingError {
            throw OLEDFrameEncodingError(error)
        }
    }

    /// 旧接口别名，兼容仍调用 `fromImageAt` 的代码。
    static func frames(fromImageAt url: URL) throws -> [Data] {
        try frames(fromGIFAt: url, maxFrames: AhaKeyCommand.oledMaxFramesPerMode)
    }
}
