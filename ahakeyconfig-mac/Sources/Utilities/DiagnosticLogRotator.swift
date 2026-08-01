import Foundation

/// 诊断日志的按大小轮转。
///
/// 语音诊断日志逐字记录了用户说出口的每一句话，既不能无限增长，也不该在轮转时
/// 把全部历史一次抹掉，所以按 `base` → `base.1` → … 的顺序挪，最老的一份丢弃。
enum DiagnosticLogRotator {
    /// 单个文件的上限。
    static let maxBytes = 1024 * 1024
    /// 含当前正在写的那份在内，最多保留几个文件。磁盘占用上限约 `maxBytes * maxFiles`。
    static let maxFiles = 5

    /// 当前文件超过上限时轮转一次；未超过或文件不存在则什么都不做。
    ///
    /// 轮转后 `url` 不存在，由调用方新建。
    static func rotateIfNeeded(
        at url: URL,
        maxBytes: Int = maxBytes,
        maxFiles: Int = maxFiles,
        fileManager: FileManager = .default
    ) {
        guard maxFiles > 0 else { return }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size >= maxBytes else { return }

        // 历史份共 maxFiles - 1 个，编号 1...maxFiles-1；序号越大越老。
        let oldestIndex = maxFiles - 1
        if oldestIndex >= 1 {
            try? fileManager.removeItem(at: rotatedURL(for: url, index: oldestIndex))
        }
        for index in stride(from: oldestIndex - 1, through: 1, by: -1) {
            let from = rotatedURL(for: url, index: index)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.moveItem(at: from, to: rotatedURL(for: url, index: index + 1))
        }

        if oldestIndex >= 1 {
            try? fileManager.moveItem(at: url, to: rotatedURL(for: url, index: 1))
        } else {
            // 只允许留一个文件时没有历史可言，直接丢弃当前这份。
            try? fileManager.removeItem(at: url)
        }
    }

    static func rotatedURL(for url: URL, index: Int) -> URL {
        url.appendingPathExtension("\(index)")
    }
}
