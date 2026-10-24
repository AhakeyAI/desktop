import Foundation
import AhaKeyConfigShared

/// 读取当前 Kimi 配置快照（`KimiConfigLocation.activeConfigURL()`）。拨杆 → `KimiConfigLeverSync` 写入：
/// Kimi Code CLI 2.x 为 `default_permission_mode`（新建会话生效），旧版 kimi-cli 为 `default_yolo`（`/reload` 生效）。
/// 两代 CLI 的 PreToolUse 都只认 **`deny`**，hook 侧无法直接放行。
enum KimiConfigDiagnostic {
    /// 写入 `permission-request.log` 的 `kimiLeverDebug` 块。
    static func snapshotForLog() -> [String: Any] {
        let fm = FileManager.default
        let url = KimiConfigLocation.activeConfigURL()
        let path = url.path
        let legacy = KimiConfigLocation.isLegacy(url)
        var d: [String: Any] = [
            "kimiConfigPath": path,
            "kimiConfigExists": fm.fileExists(atPath: path),
            "kimiConfigGeneration": legacy ? "legacy_kimi_cli" : "kimi_code",
            "hookApprovalPolicy": legacy
                ? "dial_writes_default_yolo_kimi_reload_to_apply_upstream_deny_only"
                : "dial_writes_default_permission_mode_new_sessions_apply_upstream_deny_only",
        ]
        if !legacy {
            d["default_permission_mode"] = KimiPermissionModeSync.configuredMode(configURL: url) ?? NSNull()
            return d
        }
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
