import CryptoKit
import Foundation
import os.log

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "LocalModelStore")

// MARK: - 线程安全的取消标志

final class LocalModelCancellationFlag: @unchecked Sendable {
    private var isCancelledFlag = false
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelledFlag
    }

    func cancel() {
        lock.lock()
        isCancelledFlag = true
        lock.unlock()
    }
}

// MARK: - 模型文件规格描述

/// 单个模型文件的静态元数据（文件名、远程地址、期望大小、SHA256 校验和）
struct LocalModelFileSpec: Hashable, Sendable, Equatable {
    let remoteURL: URL
    let filename: String
    let expectedBytes: Int64
    let sha256: String

    init(remoteURL: URL, filename: String, expectedBytes: Int64, sha256: String) {
        self.remoteURL = remoteURL
        self.filename = filename
        self.expectedBytes = expectedBytes
        self.sha256 = sha256
    }
}

// MARK: - 识别器所需路径模型

/// SenseVoice 识别引擎所需的文件路径
struct LocalSenseVoicePaths: Equatable, Sendable {
    let model: URL
    let tokens: URL

    init(model: URL, tokens: URL) {
        self.model = model
        self.tokens = tokens
    }
}

/// Whisper 识别引擎所需的文件路径
struct LocalWhisperPaths: Equatable, Sendable {
    let encoder: URL
    let decoder: URL
    let tokens: URL

    init(encoder: URL, decoder: URL, tokens: URL) {
        self.encoder = encoder
        self.decoder = decoder
        self.tokens = tokens
    }
}

// MARK: - 支持的本地语音模型

/// 本地语音转写模型类型
enum LocalSpeechModel: Hashable, Sendable, Identifiable {
    case senseVoice
    case whisperTiny
    case whisperBase
    case whisperSmall
    case whisperTurbo
    #if DEBUG
    case testFixture(id: String, displayName: String, files: [LocalModelFileSpec])
    #endif

    /// 模型所在根目录下的文件夹名称
    var id: String {
        switch self {
        case .senseVoice:
            return "sensevoice-2024-07-17"
        case .whisperTiny:
            return "whisper-tiny"
        case .whisperBase:
            return "whisper-base"
        case .whisperSmall:
            return "whisper-small"
        case .whisperTurbo:
            return "whisper-turbo"
        #if DEBUG
        case .testFixture(let id, _, _):
            return id
        #endif
        }
    }

    /// 用户界面展示名称
    var displayName: String {
        switch self {
        case .senseVoice:
            return "SenseVoice (推荐 / 中粤英日韩)"
        case .whisperTiny:
            return "Whisper Tiny"
        case .whisperBase:
            return "Whisper Base (推荐)"
        case .whisperSmall:
            return "Whisper Small"
        case .whisperTurbo:
            return "Whisper Large V3 Turbo"
        #if DEBUG
        case .testFixture(_, let displayName, _):
            return displayName
        #endif
        }
    }

    /// 模型包含的完整文件清单（URL、文件名、预期字节数、SHA256）
    var fileList: [LocalModelFileSpec] {
        switch self {
        case .senseVoice:
            let base = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/"
            return [
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)model.int8.onnx")!,
                    filename: "model.int8.onnx",
                    expectedBytes: 239_233_841,
                    sha256: "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)tokens.txt")!,
                    filename: "tokens.txt",
                    expectedBytes: 315_894,
                    sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
                )
            ]

        case .whisperTiny:
            let base = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/"
            return [
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)tiny-encoder.int8.onnx")!,
                    filename: "tiny-encoder.int8.onnx",
                    expectedBytes: 12_937_772,
                    sha256: "d24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)tiny-decoder.int8.onnx")!,
                    filename: "tiny-decoder.int8.onnx",
                    expectedBytes: 89_855_401,
                    sha256: "d2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)tiny-tokens.txt")!,
                    filename: "tiny-tokens.txt",
                    expectedBytes: 816_730,
                    sha256: "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
                )
            ]

        case .whisperBase:
            let base = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/"
            return [
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)base-encoder.int8.onnx")!,
                    filename: "base-encoder.int8.onnx",
                    expectedBytes: 29_120_534,
                    sha256: "0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)base-decoder.int8.onnx")!,
                    filename: "base-decoder.int8.onnx",
                    expectedBytes: 130_672_026,
                    sha256: "9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)base-tokens.txt")!,
                    filename: "base-tokens.txt",
                    expectedBytes: 816_730,
                    sha256: "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
                )
            ]

        case .whisperSmall:
            let base = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/"
            return [
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)small-encoder.int8.onnx")!,
                    filename: "small-encoder.int8.onnx",
                    expectedBytes: 112_442_483,
                    sha256: "4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)small-decoder.int8.onnx")!,
                    filename: "small-decoder.int8.onnx",
                    expectedBytes: 262_226_114,
                    sha256: "acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)small-tokens.txt")!,
                    filename: "small-tokens.txt",
                    expectedBytes: 816_730,
                    sha256: "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
                )
            ]

        case .whisperTurbo:
            let base = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/2ca6ff69fc878651b770880507669577ac41c2ff/"
            return [
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)turbo-encoder.int8.onnx")!,
                    filename: "turbo-encoder.int8.onnx",
                    expectedBytes: 674_716_297,
                    sha256: "b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)turbo-decoder.int8.onnx")!,
                    filename: "turbo-decoder.int8.onnx",
                    expectedBytes: 361_080_764,
                    sha256: "20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547"
                ),
                LocalModelFileSpec(
                    remoteURL: URL(string: "\(base)turbo-tokens.txt")!,
                    filename: "turbo-tokens.txt",
                    expectedBytes: 816_730,
                    sha256: "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"
                )
            ]

        #if DEBUG
        case .testFixture(_, _, let files):
            return files
        #endif
        }
    }

    /// 模型所有文件累计字节大小
    var totalSize: Int64 {
        fileList.reduce(0) { $0 + $1.expectedBytes }
    }

    var isSenseVoice: Bool {
        switch self {
        case .senseVoice: return true
        default: return false
        }
    }

    var isWhisper: Bool {
        switch self {
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperTurbo: return true
        default: return false
        }
    }

    /// 识别器辅助方法：获取给定目录下的 SenseVoice (model, tokens) 路径
    func senseVoicePaths(in directory: URL) -> LocalSenseVoicePaths? {
        guard isSenseVoice else { return nil }
        return LocalSenseVoicePaths(
            model: directory.appendingPathComponent("model.int8.onnx"),
            tokens: directory.appendingPathComponent("tokens.txt")
        )
    }

    /// 识别器辅助方法：获取给定目录下的 Whisper (encoder, decoder, tokens) 路径
    func whisperPaths(in directory: URL) -> LocalWhisperPaths? {
        guard isWhisper else { return nil }
        let prefix: String
        switch self {
        case .whisperTiny: prefix = "tiny"
        case .whisperBase: prefix = "base"
        case .whisperSmall: prefix = "small"
        case .whisperTurbo: prefix = "turbo"
        default: return nil
        }
        return LocalWhisperPaths(
            encoder: directory.appendingPathComponent("\(prefix)-encoder.int8.onnx"),
            decoder: directory.appendingPathComponent("\(prefix)-decoder.int8.onnx"),
            tokens: directory.appendingPathComponent("\(prefix)-tokens.txt")
        )
    }
}

extension LocalSpeechModel: CaseIterable {
    static var allCases: [LocalSpeechModel] {
        return [.senseVoice, .whisperTiny, .whisperBase, .whisperSmall, .whisperTurbo]
    }
}

// MARK: - 模型状态与错误定义

/// 单个模型在运行时的下载/校验/安装状态
enum LocalModelState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case installed
    case failed(String)
}

enum LocalModelStoreError: LocalizedError, Equatable {
    case fileNotFound(String)
    case sizeMismatch(file: String, expected: Int64, actual: Int64)
    case checksumMismatch(file: String, expected: String, actual: String)
    case downloadFailed(String)
    case importFailed(String)
    case operationCancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let file):
            return "未找到模型文件：\(file)"
        case .sizeMismatch(let file, let expected, let actual):
            return "文件 \"\(file)\" 大小不匹配：期望 \(expected) 字节，实际 \(actual) 字节"
        case .checksumMismatch(let file, _, _):
            return "文件 \"\(file)\" SHA256 校验和不匹配"
        case .downloadFailed(let message):
            return "模型下载失败：\(message)"
        case .importFailed(let message):
            return "模型导入失败：\(message)"
        case .operationCancelled:
            return "操作已取消"
        }
    }
}

// MARK: - 本地语音模型存储管理器

/// 本地语音模型下载、校验、存储管理器
/// 遵循原子写入安全规范：下载/导入只在 `.partial-<id>` 中进行，只有完整校验通过后才原子重命名替换至正式目录。
@MainActor
final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()

    /// 模型存放根目录（默认 ~/Library/Application Support/AhaKey/models）
    let modelsDirectory: URL

    /// 各模型的实时状态映射
    @Published private(set) var states: [LocalSpeechModel: LocalModelState] = [:]

    private let urlSession: URLSession
    private var activeDownloadTasksByModel: [LocalSpeechModel: URLSessionDownloadTask] = [:]
    private var activeCancellationFlags: [LocalSpeechModel: LocalModelCancellationFlag] = [:]
    private var cancelledModels: Set<String> = []

    init(modelsDirectory: URL? = nil, urlSession: URLSession = .shared) {
        if let dir = modelsDirectory {
            self.modelsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.modelsDirectory = appSupport.appendingPathComponent("AhaKey/models", isDirectory: true)
        }
        self.urlSession = urlSession
        self.recoverStaleDirectories()
        self.refreshInstalledStates()
    }

    /// 检查并清理或恢复异常中断遗留的残留目录（.partial-* 与 .backup-*）
    private func recoverStaleDirectories() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelsDirectory.path),
              let items = try? fm.contentsOfDirectory(
                  at: modelsDirectory,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: []
              ) else {
            return
        }

        var backupsByModelId: [String: [(url: URL, date: Date)]] = [:]

        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(".partial-") {
                log.info("清理未完成的残留下载目录: \(name)")
                try? fm.removeItem(at: item)
            } else if name.hasPrefix(".backup-"), let modelId = extractModelId(from: name) {
                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                backupsByModelId[modelId, default: []].append((url: item, date: modDate))
            }
        }

        for (modelId, backups) in backupsByModelId {
            let finalDir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
            if fm.fileExists(atPath: finalDir.path) {
                // 正式目录完好存在，说明此前备份为遗留物，清理即可
                for backup in backups {
                    log.info("清理旧版本残留备份目录: \(backup.url.lastPathComponent)")
                    try? fm.removeItem(at: backup.url)
                }
            } else {
                // 正式目录缺失（崩溃发生于替换中途），按时间降序取最新备份恢复
                let sorted = backups.sorted { $0.date > $1.date }
                if let newest = sorted.first {
                    log.info("从残留备份 \(newest.url.lastPathComponent) 恢复模型目录 \(modelId)")
                    try? fm.moveItem(at: newest.url, to: finalDir)
                }
                for older in sorted.dropFirst() {
                    try? fm.removeItem(at: older.url)
                }
            }
        }
    }

    private func extractModelId(from backupName: String) -> String? {
        guard backupName.hasPrefix(".backup-") else { return nil }
        let remainder = String(backupName.dropFirst(".backup-".count))
        if remainder.count > 37 {
            let hyphenIndex = remainder.index(remainder.endIndex, offsetBy: -37)
            if remainder[hyphenIndex] == "-" {
                return String(remainder[..<hyphenIndex])
            }
        }
        for model in LocalSpeechModel.allCases {
            if remainder.hasPrefix(model.id) {
                return model.id
            }
        }
        return remainder.isEmpty ? nil : remainder
    }

    /// 刷新所有已知模型的已安装状态（根据磁盘文件是否存在且大小吻合）
    func refreshInstalledStates() {
        for model in LocalSpeechModel.allCases {
            if isInstalled(model) {
                states[model] = .installed
            } else if states[model] == nil || states[model] == .installed {
                states[model] = .notInstalled
            }
        }
    }

    /// 获取特定模型的当前状态（若尚未记录则快速查询安装状态）
    func state(for model: LocalSpeechModel) -> LocalModelState {
        if let s = states[model] {
            return s
        }
        return isInstalled(model) ? .installed : .notInstalled
    }

    /// 获取指定模型的正式存储目录
    func modelDirectory(for model: LocalSpeechModel) -> URL {
        modelsDirectory.appendingPathComponent(model.id, isDirectory: true)
    }

    /// 快速检查模型是否已完整安装（只比对文件存在与字节长度，不进行昂贵的全量 SHA256）
    func isInstalled(_ model: LocalSpeechModel) -> Bool {
        let dir = modelDirectory(for: model)
        let fm = FileManager.default
        for file in model.fileList {
            let filePath = dir.appendingPathComponent(file.filename).path
            guard fm.fileExists(atPath: filePath) else { return false }
            guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  size == file.expectedBytes else {
                return false
            }
        }
        return true
    }

    /// 对已安装目录进行全量 SHA256 完整性检验
    func verify(model: LocalSpeechModel) throws {
        let dir = modelDirectory(for: model)
        try verifyDirectory(dir, for: model)
    }

    // MARK: - 识别器路径访问辅助

    /// 获取已安装 SenseVoice 模型路径（未就绪或未安装返回 nil）
    func senseVoicePaths() -> LocalSenseVoicePaths? {
        senseVoicePaths(for: .senseVoice)
    }

    func senseVoicePaths(for model: LocalSpeechModel) -> LocalSenseVoicePaths? {
        guard model.isSenseVoice, isInstalled(model) else { return nil }
        return model.senseVoicePaths(in: modelDirectory(for: model))
    }

    /// 获取已安装 Whisper 模型路径（未就绪或未安装返回 nil）
    func whisperPaths(for model: LocalSpeechModel) -> LocalWhisperPaths? {
        guard model.isWhisper, isInstalled(model) else { return nil }
        return model.whisperPaths(in: modelDirectory(for: model))
    }

    // MARK: - 下载与安装

    /// 下载并校验模型（原子安装至 models/<id>）
    func download(_ model: LocalSpeechModel) async throws {
        guard activeDownloadTasksByModel[model] == nil else {
            log.info("[\(model.id)] 下载已在进行中，跳过重复请求")
            return
        }

        let cancelFlag = LocalModelCancellationFlag()
        activeCancellationFlags[model] = cancelFlag
        defer { activeCancellationFlags.removeValue(forKey: model) }

        cancelledModels.remove(model.id)
        states[model] = .downloading(progress: 0.0)

        let root = modelsDirectory
        let partialDir = root.appendingPathComponent(".partial-\(model.id)", isDirectory: true)
        let finalDir = modelDirectory(for: model)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: partialDir.path) {
                try? fm.removeItem(at: partialDir)
            }
            try fm.createDirectory(at: partialDir, withIntermediateDirectories: true)

            var completedBytes: Int64 = 0
            let totalSize = max(model.totalSize, 1)
            var lastPublishedProgress: Double = 0.0
            var lastPublishedTime: CFAbsoluteTime = 0

            for file in model.fileList {
                try checkCancellation(for: model)
                let dst = partialDir.appendingPathComponent(file.filename)
                let baseCompleted = completedBytes

                try await downloadFile(file: file, for: model, to: dst) { [weak self] currentReceived in
                    guard let self = self else { return }
                    // P0 防御：仅当状态处于 downloading 时才更新进度，避免晚到回调冲掉 verifying 或 installed
                    guard case .downloading = self.states[model] else { return }

                    let clamped = min(max(currentReceived, 0), file.expectedBytes)
                    let totalProgress = Double(baseCompleted + clamped) / Double(totalSize)
                    let now = CFAbsoluteTimeGetCurrent()
                    if (totalProgress - lastPublishedProgress) >= 0.005 || (now - lastPublishedTime) >= 0.2 || totalProgress >= 1.0 {
                        lastPublishedProgress = totalProgress
                        lastPublishedTime = now
                        self.states[model] = .downloading(progress: min(max(totalProgress, 0.0), 1.0))
                    }
                }

                try checkCancellation(for: model)

                // 校验单文件大小
                guard let attrs = try? fm.attributesOfItem(atPath: dst.path),
                      let size = (attrs[.size] as? NSNumber)?.int64Value else {
                    throw LocalModelStoreError.fileNotFound(file.filename)
                }
                guard size == file.expectedBytes else {
                    throw LocalModelStoreError.sizeMismatch(file: file.filename, expected: file.expectedBytes, actual: size)
                }

                completedBytes += file.expectedBytes
            }

            // 校验阶段（在后台 utility 优先级线程池运行，并通过 cancelFlag 响应及时取消）
            states[model] = .verifying
            log.info("[\(model.id)] 开始后台计算 SHA256 校验和...")

            for file in model.fileList {
                try checkCancellation(for: model)
                let filePath = partialDir.appendingPathComponent(file.filename)
                let hash = try await Task.detached(priority: .utility) {
                    try Self.computeSHA256(for: filePath) {
                        cancelFlag.isCancelled
                    }
                }.value
                try checkCancellation(for: model)
                guard hash.lowercased() == file.sha256.lowercased() else {
                    throw LocalModelStoreError.checksumMismatch(file: file.filename, expected: file.sha256, actual: hash)
                }
            }

            try checkCancellation(for: model)

            // 原子替换目录
            try atomicMove(from: partialDir, to: finalDir, modelId: model.id)
            states[model] = .installed
            activeDownloadTasksByModel.removeValue(forKey: model)
            log.info("[\(model.id)] 模型下载与安装成功")
        } catch {
            activeDownloadTasksByModel.removeValue(forKey: model)
            try? fm.removeItem(at: partialDir)

            if isCancellationError(error) || cancelledModels.contains(model.id) {
                cancelledModels.remove(model.id)
                states[model] = isInstalled(model) ? .installed : .notInstalled
                log.info("[\(model.id)] 模型下载已取消")
                throw LocalModelStoreError.operationCancelled
            } else {
                let message = error.localizedDescription
                states[model] = .failed(message)
                log.error("[\(model.id)] 模型安装失败: \(message)")
                throw error
            }
        }
    }

    /// 取消模型的下载或导入，清理临时目录并保留已有安装
    func cancel(_ model: LocalSpeechModel) {
        cancelledModels.insert(model.id)
        activeCancellationFlags.removeValue(forKey: model)?.cancel()
        if let task = activeDownloadTasksByModel.removeValue(forKey: model) {
            task.cancel()
        }
        let partialDir = modelsDirectory.appendingPathComponent(".partial-\(model.id)", isDirectory: true)
        try? FileManager.default.removeItem(at: partialDir)

        states[model] = isInstalled(model) ? .installed : .notInstalled
        log.info("[\(model.id)] 已触发取消")
    }

    /// 删除指定模型文件并标记为未安装
    func delete(_ model: LocalSpeechModel) {
        cancel(model)
        let fm = FileManager.default
        let finalDir = modelDirectory(for: model)
        let partialDir = modelsDirectory.appendingPathComponent(".partial-\(model.id)", isDirectory: true)

        try? fm.removeItem(at: partialDir)
        try? fm.removeItem(at: finalDir)

        states[model] = .notInstalled
        log.info("[\(model.id)] 模型已删除")
    }

    /// 从本地文件夹导入模型（离线备用）
    /// 严格验证大小与 SHA256，通过后原子重命名覆盖
    func importFromFolder(_ model: LocalSpeechModel, from sourceURL: URL) async throws {
        cancel(model)
        cancelledModels.remove(model.id)

        let cancelFlag = LocalModelCancellationFlag()
        activeCancellationFlags[model] = cancelFlag
        defer { activeCancellationFlags.removeValue(forKey: model) }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            let err = LocalModelStoreError.importFailed("指定的来源不是有效的文件夹")
            states[model] = .failed(err.localizedDescription)
            throw err
        }

        let root = modelsDirectory
        let partialDir = root.appendingPathComponent(".partial-\(model.id)", isDirectory: true)
        let finalDir = modelDirectory(for: model)

        states[model] = .verifying

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if fm.fileExists(atPath: partialDir.path) {
                try? fm.removeItem(at: partialDir)
            }
            try fm.createDirectory(at: partialDir, withIntermediateDirectories: true)

            // 先预检所有文件存在性与大小，避免无谓的 IO 复制
            for file in model.fileList {
                try checkCancellation(for: model)
                let srcFile = sourceURL.appendingPathComponent(file.filename)
                guard fm.fileExists(atPath: srcFile.path) else {
                    throw LocalModelStoreError.fileNotFound(file.filename)
                }
                guard let attrs = try? fm.attributesOfItem(atPath: srcFile.path),
                      let size = (attrs[.size] as? NSNumber)?.int64Value else {
                    throw LocalModelStoreError.fileNotFound(file.filename)
                }
                guard size == file.expectedBytes else {
                    throw LocalModelStoreError.sizeMismatch(file: file.filename, expected: file.expectedBytes, actual: size)
                }
            }

            // 流式复制并计算 SHA256（在后台 utility 线程池执行）
            for file in model.fileList {
                try checkCancellation(for: model)
                let srcFile = sourceURL.appendingPathComponent(file.filename)
                let dstFile = partialDir.appendingPathComponent(file.filename)

                let actualHash = try await Task.detached(priority: .utility) {
                    try Self.streamCopyAndComputeSHA256(from: srcFile, to: dstFile, expectedBytes: file.expectedBytes) {
                        cancelFlag.isCancelled
                    }
                }.value
                try checkCancellation(for: model)
                guard actualHash.lowercased() == file.sha256.lowercased() else {
                    throw LocalModelStoreError.checksumMismatch(file: file.filename, expected: file.sha256, actual: actualHash)
                }
            }

            try checkCancellation(for: model)

            try atomicMove(from: partialDir, to: finalDir, modelId: model.id)
            states[model] = .installed
            log.info("[\(model.id)] 文件夹离线导入成功")
        } catch {
            try? fm.removeItem(at: partialDir)
            if isCancellationError(error) || cancelledModels.contains(model.id) {
                cancelledModels.remove(model.id)
                states[model] = isInstalled(model) ? .installed : .notInstalled
                log.info("[\(model.id)] 文件夹导入已取消")
                throw LocalModelStoreError.operationCancelled
            } else {
                let msg = error.localizedDescription
                states[model] = .failed(msg)
                log.error("[\(model.id)] 文件夹导入失败: \(msg)")
                throw error
            }
        }
    }

    // MARK: - 私有辅助方法

    private func checkCancellation(for model: LocalSpeechModel) throws {
        if cancelledModels.contains(model.id) || Task.isCancelled {
            throw LocalModelStoreError.operationCancelled
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let storeErr = error as? LocalModelStoreError, storeErr == .operationCancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// 使用 URLSessionDownloadTask 下载文件到目标路径，并按阈值节流回调下载字节数
    private func downloadFile(
        file: LocalModelFileSpec,
        for model: LocalSpeechModel,
        to destinationURL: URL,
        onProgress: @escaping @MainActor (Int64) -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var resumed = false
                var observation: NSKeyValueObservation?

                func finish(with result: Result<Void, Error>) {
                    guard !resumed else { return }
                    resumed = true
                    observation?.invalidate()
                    observation = nil
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                let task = self.urlSession.downloadTask(with: file.remoteURL) { tempURL, response, error in
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                            finish(with: .failure(CancellationError()))
                        } else {
                            finish(with: .failure(error))
                        }
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                        finish(with: .failure(LocalModelStoreError.downloadFailed("HTTP \(httpResponse.statusCode)")))
                        return
                    }

                    guard let tempURL = tempURL else {
                        finish(with: .failure(LocalModelStoreError.downloadFailed("未生成临时文件")))
                        return
                    }

                    do {
                        let fm = FileManager.default
                        if fm.fileExists(atPath: destinationURL.path) {
                            try fm.removeItem(at: destinationURL)
                        }
                        try fm.moveItem(at: tempURL, to: destinationURL)
                        finish(with: .success(()))
                    } catch {
                        finish(with: .failure(error))
                    }
                }

                var lastReportedBytes: Int64 = 0
                var lastReportedTime: CFAbsoluteTime = 0
                let minDeltaBytes: Int64 = max(file.expectedBytes / 200, 64 * 1024)

                observation = task.observe(\.countOfBytesReceived) { t, _ in
                    let count = t.countOfBytesReceived
                    let now = CFAbsoluteTimeGetCurrent()
                    let deltaBytes = count - lastReportedBytes
                    let deltaTime = now - lastReportedTime

                    if deltaBytes >= minDeltaBytes || deltaTime >= 0.2 || count >= file.expectedBytes {
                        lastReportedBytes = count
                        lastReportedTime = now
                        Task { @MainActor in
                            onProgress(count)
                        }
                    }
                }

                self.activeDownloadTasksByModel[model] = task
                task.resume()
            }
        } onCancel: {
            Task { @MainActor in
                self.activeDownloadTasksByModel[model]?.cancel()
            }
        }
    }

    /// 校验某个目录下的模型文件完整性
    private func verifyDirectory(_ directory: URL, for model: LocalSpeechModel) throws {
        let fm = FileManager.default
        for file in model.fileList {
            let path = directory.appendingPathComponent(file.filename)
            guard fm.fileExists(atPath: path.path) else {
                throw LocalModelStoreError.fileNotFound(file.filename)
            }
            guard let attrs = try? fm.attributesOfItem(atPath: path.path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value else {
                throw LocalModelStoreError.fileNotFound(file.filename)
            }
            guard size == file.expectedBytes else {
                throw LocalModelStoreError.sizeMismatch(file: file.filename, expected: file.expectedBytes, actual: size)
            }
            let hash = try Self.computeSHA256(for: path)
            guard hash.lowercased() == file.sha256.lowercased() else {
                throw LocalModelStoreError.checksumMismatch(file: file.filename, expected: file.sha256, actual: hash)
            }
        }
    }

    /// 流式计算文件的 SHA256 哈希值（1MB 块读取，支持取消标志回调）
    nonisolated static func computeSHA256(
        for fileURL: URL,
        isCancelled: (() -> Bool)? = nil
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB
        while true {
            if isCancelled?() == true || Task.isCancelled {
                throw CancellationError()
            }
            guard let chunk = try handle.read(upToCount: bufferSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 流式复制并实时计算 SHA256（1MB 块读取，支持取消标志回调）
    nonisolated static func streamCopyAndComputeSHA256(
        from source: URL,
        to destination: URL,
        expectedBytes: Int64,
        isCancelled: (() -> Bool)? = nil
    ) throws -> String {
        let inputHandle = try FileHandle(forReadingFrom: source)
        defer { try? inputHandle.close() }

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        fm.createFile(atPath: destination.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destination)
        defer { try? outputHandle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB
        var totalBytesCopied: Int64 = 0

        while true {
            if isCancelled?() == true || Task.isCancelled {
                throw CancellationError()
            }

            guard let chunk = try inputHandle.read(upToCount: bufferSize), !chunk.isEmpty else {
                break
            }
            totalBytesCopied += Int64(chunk.count)
            if totalBytesCopied > expectedBytes {
                throw LocalModelStoreError.sizeMismatch(file: source.lastPathComponent, expected: expectedBytes, actual: totalBytesCopied)
            }
            hasher.update(data: chunk)
            try outputHandle.write(contentsOf: chunk)
        }

        if totalBytesCopied != expectedBytes {
            throw LocalModelStoreError.sizeMismatch(file: source.lastPathComponent, expected: expectedBytes, actual: totalBytesCopied)
        }

        try outputHandle.synchronize()
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 原子替换目录：若 finalDir 已存在，先备份；替换成功后清除备份，失败则自动回退
    private func atomicMove(from partialDir: URL, to finalDir: URL, modelId: String) throws {
        let fm = FileManager.default
        let root = partialDir.deletingLastPathComponent()

        if fm.fileExists(atPath: finalDir.path) {
            let backupDir = root.appendingPathComponent(".backup-\(modelId)-\(UUID().uuidString)", isDirectory: true)
            try fm.moveItem(at: finalDir, to: backupDir)
            do {
                try fm.moveItem(at: partialDir, to: finalDir)
                try? fm.removeItem(at: backupDir)
            } catch {
                try? fm.moveItem(at: backupDir, to: finalDir)
                throw error
            }
        } else {
            try fm.moveItem(at: partialDir, to: finalDir)
        }
    }
}
