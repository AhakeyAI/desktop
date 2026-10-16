import AhaKeyConfigShared
import Foundation

/// Verified auto temporarily adds owned CLI permissions; manual/offline removes only owned values.
enum CursorCliLeverSync {
    private static let cliName = "cli-config.json"
    private static var cliURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent(cliName, isDirectory: false)
    }

    private static var snapshotURL: URL { cliURL.appendingPathExtension("ahakey.lever0.bak") }
    private static var hadNoPriorCliMarker: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent(".ahakey_had_no_cli_config", isDirectory: false)
    }

    /// Serialize owned permission changes with stop/remove revocation.
    static func apply(switchStateAuto: Bool) {
        _ = CursorApprovalPolicySync.apply(auto: switchStateAuto, kind: .cli)
    }

    private static func readJson(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }

    private static func stringArray(from v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    // MARK: - 诊断（permission-request.log）

    /// 写回/恢复后的 `~/.cursor/cli-config.json` 与拨杆同步相关旁路文件状态，供 `HookClient` 记日志。
    static func diagnosticSnapshotForLog() -> [String: Any] {
        let fm = FileManager.default
        var d: [String: Any] = [
            "userCliConfigPath": cliURL.path,
            "userCliConfigExists": fm.fileExists(atPath: cliURL.path),
            "lever0SnapshotBakExists": fm.fileExists(atPath: snapshotURL.path),
            "hadNoPriorCliMarkerExists": fm.fileExists(atPath: hadNoPriorCliMarker.path),
        ]
        guard let root = readJson(cliURL) else { return d }
        d["cliConfigVersion"] = root["version"] as Any
        d["approvalMode"] = root["approvalMode"] as Any
        if let sb = root["sandbox"] {
            d["cliConfigSandboxPreview"] = String(String(describing: sb).prefix(400))
        }
        if let perms = root["permissions"] as? [String: Any] {
            let allow = stringArray(from: perms["allow"])
            let deny = stringArray(from: perms["deny"])
            d["permissionsAllowCount"] = allow.count
            d["permissionsDenyCount"] = deny.count
            d["permissionsHasShellStar"] = allow.contains("Shell(*)")
            d["permissionsAllowHasReadStar"] = allow.contains { $0.hasPrefix("Read(") && $0.contains("*") }
            d["permissionsAllowHasWriteStar"] = allow.contains { $0.hasPrefix("Write(") && $0.contains("*") }
        }
        return d
    }
}
