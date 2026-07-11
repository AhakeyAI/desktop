import Foundation

/// 读取 `~/.kimi/config.toml` 快照。`default_yolo` 也可由 **拨杆→`KimiConfigLeverSync`** 在 `PreToolUse` 写入；已开会话需在 kimi 执行 **`/reload`** 才读新值。PreToolUse 仍仅 **`deny`** 有 hook 侧拦截语义（`runner.py`）。
enum KimiConfigDiagnostic {
    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi/config.toml", isDirectory: false)
    }

    /// 写入 `permission-request.log` 的 `kimiLeverDebug` 块。
    static func snapshotForLog() -> [String: Any] {
        let fm = FileManager.default
        let path = configURL.path
        var d: [String: Any] = [
            "kimiConfigPath": path,
            "kimiConfigExists": fm.fileExists(atPath: path),
            "hookApprovalPolicy": "dial_writes_default_yolo_on_PreToolUse_kimi_reload_to_apply_upstream_deny_only",
        ]
        guard let data = fm.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return d }
        if let regex = try? NSRegularExpression(pattern: #"(?m)^\s*default_yolo\s*=\s*(\S+)"#, options: []),
           let m = regex.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: (raw as NSString).length)),
           m.numberOfRanges > 1 {
            let ns = raw as NSString
            d["default_yolo_lineno_hint"] = "matched"
            d["default_yolo_valueSnippet"] = String(ns.substring(with: m.range(at: 1)).prefix(32))
        } else {
            d["default_yolo_valueSnippet"] = NSNull()
        }
        return d
    }
}
