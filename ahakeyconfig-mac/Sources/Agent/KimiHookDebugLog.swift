import Foundation

/// Kimi PreToolUse 等设备侧调试日志：stderr（终端里 kimi 会看到）+ 单行 JSON 写入 **当前工作目录** 下的 `kimi-hook-debug.log`。
enum KimiHookDebugLog {
    private static let logFileName = "kimi-hook-debug.log"

    /// 供 Hook stderr 告知用户到哪看完整 JSON 行日志（绝对路径）。
    static var logPath: String { debugFileURL.path }

    private static var debugFileURL: URL {
        let cwd = FileManager.default.currentDirectoryPath
        let base = cwd.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : cwd
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(logFileName, isDirectory: false)
    }

    private static let isoTs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// stderr 单行，前缀统一便于 `grep`，kimi-cli 将把 hook 工具的 stderr 打出来（视版本而定）。
    static func stderrLine(_ msg: String) {
        let line = "[aha-kimi] \(msg)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// 结构化追加到磁盘（与 `permission-request.log` 等 App diagnostics 分离，避免路径含空格时难找）。
    static func append(event: String, details: [String: Any]) {
        let cwd = FileManager.default.currentDirectoryPath
        var payload: [String: Any] = [
            "ts": isoTs.string(from: Date()),
            "event": event,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "cwd": cwd.isEmpty ? NSNull() : cwd,
        ]
        for (k, v) in details { payload[k] = v }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              var line = String(data: data, encoding: .utf8) else {
            stderrLine("debug log JSON encode failed event=\(event)")
            return
        }
        line += "\n"

        let url = debugFileURL
        let fm = FileManager.default
        do {
            // 日志在 cwd 下，目录应已存在；若为空回退到 home，则保证父目录存在
            if FileManager.default.currentDirectoryPath.isEmpty {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: url.path) {
                try line.data(using: .utf8)?.write(to: url, options: .atomic)
            } else if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            }
        } catch {
            let fallback = "[aha-kimi] append log failed \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(fallback.utf8))
        }
    }
}
