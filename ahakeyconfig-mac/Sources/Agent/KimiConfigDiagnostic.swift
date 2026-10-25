import Foundation
import AhaKeyConfigShared

/// Version-aware root permission diagnostics. Never dump provider credentials;
/// native defaults are not evidence of live terminal approval control.
enum KimiConfigDiagnostic {
    private static var configURL: URL {
        KimiConfigPolicySync.productionConfigURL
    }

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
            "kimiConfigurationLayout": KimiConfigPolicySync.productionLocation.layout.rawValue,
        ]
        guard let data = fm.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) else { return d }
        let key = KimiConfigPolicySync.productionLocation.layout == .nativeV2 ? "default_permission_mode" : "default_yolo"
        d["permissionField"] = key
        if let value = KimiConfigPolicySync.permissionValue(in: raw, layout: KimiConfigPolicySync.productionLocation.layout) {
            d[key + "_valueSnippet"] = value
            d["permissionValue"] = value
        } else {
            d[key + "_valueSnippet"] = NSNull()
            d["permissionValue"] = NSNull()
        }
        return d
    }
}
