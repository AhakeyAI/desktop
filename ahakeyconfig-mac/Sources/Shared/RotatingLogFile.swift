import Foundation

/// 滚动日志文件：单文件超过 `maxFileSize` 先轮转再写入，最多保留 1 + `maxArchiveCount` 份
///（如 ble-verbose.log → ble-verbose.log.1 → ble-verbose.log.2，最旧的被删除）。
/// 与 UI/actor 无关；调用方负责串行访问（GUI 进程用专用串行 DispatchQueue，测试单线程调用）。
public final class RotatingLogFile {
    public let fileURL: URL
    public let maxFileSize: Int
    /// 归档份数（不含当前文件）。默认 2 → 总共最多 3 份。
    public let maxArchiveCount: Int

    private let fileManager: FileManager

    public init(
        fileURL: URL,
        maxFileSize: Int = 5 * 1024 * 1024,
        maxArchiveCount: Int = 2,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.maxArchiveCount = maxArchiveCount
        self.fileManager = fileManager
    }

    /// 追加一行文本。写入前若当前文件加上该行会超限，则先轮转。
    /// - Returns: 本次写入是否触发了轮转。
    @discardableResult
    public func append(_ line: String) throws -> Bool {
        let didRotate = try rotateIfNeeded(incomingBytes: line.utf8.count)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = line.data(using: .utf8) else { return didRotate }
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try data.write(to: fileURL)
        }
        return didRotate
    }

    /// 当前文件加上 `incomingBytes` 会超限则执行轮转：最旧归档删除，其余顺移，当前文件成为 .1。
    /// - Returns: 是否发生了轮转。
    @discardableResult
    public func rotateIfNeeded(incomingBytes: Int = 0) throws -> Bool {
        let currentSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? nil
        guard let size = currentSize, size + incomingBytes > maxFileSize else { return false }

        if maxArchiveCount > 0 {
            // 最旧归档直接删除
            let oldest = archiveURL(index: maxArchiveCount)
            if fileManager.fileExists(atPath: oldest.path) {
                try fileManager.removeItem(at: oldest)
            }
            // 归档顺移：.(i-1) → .i
            if maxArchiveCount > 1 {
                for index in stride(from: maxArchiveCount, through: 2, by: -1) {
                    let source = archiveURL(index: index - 1)
                    if fileManager.fileExists(atPath: source.path) {
                        try fileManager.moveItem(at: source, to: archiveURL(index: index))
                    }
                }
            }
            // 当前文件 → .1
            try fileManager.moveItem(at: fileURL, to: archiveURL(index: 1))
        } else {
            try fileManager.removeItem(at: fileURL)
        }
        return true
    }

    /// ble-verbose.log 的第 index 份归档（ble-verbose.log.1、ble-verbose.log.2 …）。
    public func archiveURL(index: Int) -> URL {
        fileURL.appendingPathExtension("\(index)")
    }
}
