import Foundation

/// 读取 `~/.kimi-code/config.toml` 中 `default_permission_mode` 的快照。
///
/// 该字段由 `KimiPermissionModeController` 在拨杆变化时写入，决定**未来**新 Kimi
/// 会话的默认权限模式。当前已运行会话不受影响，需要靠 launcher 或 `/yolo on/off`
/// 切换。
enum KimiConfigDiagnostic {
    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi-code/config.toml", isDirectory: false)
    }

    /// 写入 `permission-request.log` 的 `kimiLeverDebug` 块。
    static func snapshotForLog() -> [String: Any] {
        let fm = FileManager.default
        let path = configURL.path
        var d: [String: Any] = [
            "kimiConfigPath": path,
            "kimiConfigExists": fm.fileExists(atPath: path),
            "hookApprovalPolicy": "dial_writes_default_permission_mode_for_future_sessions",
        ]
        guard let data = fm.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return d }

        if let regex = try? NSRegularExpression(pattern: #"(?m)^\s*default_permission_mode\s*=\s*[\"']([^\"']+)[\"']"#, options: []),
           let m = regex.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: (raw as NSString).length)),
           m.numberOfRanges > 1 {
            let ns = raw as NSString
            d["default_permission_mode_lineno_hint"] = "matched"
            d["default_permission_mode_valueSnippet"] = String(ns.substring(with: m.range(at: 1)).prefix(32))
        } else {
            d["default_permission_mode_valueSnippet"] = NSNull()
        }
        return d
    }
}
