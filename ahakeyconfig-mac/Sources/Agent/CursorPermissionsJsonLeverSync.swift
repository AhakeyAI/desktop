import AhaKeyConfigShared
import Foundation

/// IDE 内 Agent 终端 TUI 的 **「Not in allowlist」** 与 `~/.cursor/permissions.json` 里的 **`terminalAllowlist`**
/// 有关（见 Cursor 文档「permissions.json reference」），与 **`~/.cursor/cli-config.json`（CLI 权限）是两套**。
/// 只改 cli-config 不会作用到该 TUI；验证自动绑定后临时合并有归属记录的通配项。
enum CursorPermissionsJsonLeverSync {
    private static var permURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("permissions.json", isDirectory: false)
    }

    private static func snapshotURL(for url: URL) -> URL { url.appendingPathExtension("ahakey.lever0.bak") }
    private static func hadNoPriorMarker(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".ahakey_had_no_permissions_json")
    }

    /// Cursor 桌面端在 Hook 返回 allow 后仍执行自身的 Allowlist 检查。
    /// 手动档只撤销 AhaKey 加入的通配项，保留用户后续修改。
    private static let relaxedTerminalPrefixes: [String] = ["*"]

    /// 旧版自动档可能创建了原本不存在的 permissions.json。仅当标记和内容都与
    /// AhaKey 生成的文件完全一致时归档它，避免离线后仍沿用宽松的终端白名单。
    static func removeLegacyGeneratedPermissionsIfSafe() -> Bool {
        removeLegacyGeneratedPermissionsIfSafe(
            in: permURL.deletingLastPathComponent(), managedPrefixes: relaxedTerminalPrefixes
        )
    }

    static func removeLegacyGeneratedPermissionsIfSafe(
        in directory: URL, managedPrefixes: [String]
    ) -> Bool {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".ahakey_had_no_permissions_json")
        let permissions = directory.appendingPathComponent("permissions.json")
        let archive = directory.appendingPathComponent("permissions.json.ahakey.legacy-allowlist.bak")
        guard fm.fileExists(atPath: marker.path),
              !fm.fileExists(atPath: archive.path),
              let root = readJson(permissions), root.count == 1,
              let allowlist = root["terminalAllowlist"] as? [String],
              allowlist == managedPrefixes else { return false }
        do {
            try fm.moveItem(at: permissions, to: archive)
            try fm.removeItem(at: marker)
            return true
        } catch {
            return false
        }
    }

    static func apply(switchStateAuto: Bool) {
        apply(switchStateAuto: switchStateAuto, permissionsURL: permURL)
    }

    static func apply(switchStateAuto: Bool, permissionsURL: URL) {
        _ = CursorApprovalPolicySync.apply(auto: switchStateAuto, kind: .desktop,
            directory: permissionsURL.deletingLastPathComponent(),
            controlDirectory: permissionsURL == permURL ? ApprovalAutomationControl.productionDirectory : permissionsURL.deletingLastPathComponent().appendingPathComponent("control"))
    }

    private static func readJson(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }

    private static func stringArray(_ v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    // MARK: - 诊断

    static func diagnosticSnapshotForLog() -> [String: Any] {
        let fm = FileManager.default
        var d: [String: Any] = [
            "permissionsJsonPath": permURL.path,
            "permissionsJsonExists": fm.fileExists(atPath: permURL.path),
            "lever0SnapshotBakExists": fm.fileExists(atPath: snapshotURL(for: permURL).path),
            "hadNoPriorMarkerExists": fm.fileExists(atPath: hadNoPriorMarker(for: permURL).path),
        ]
        guard let root = readJson(permURL) else { return d }
        let t = stringArray(root["terminalAllowlist"])
        d["terminalAllowlistCount"] = t.count
        d["terminalAllowlistHasPrefix_cd"] = t.contains { $0 == "cd" || $0.hasPrefix("cd:") }
        d["terminalAllowlistHasPrefix_swift"] = t.contains { $0 == "swift" || $0.hasPrefix("swift ") }
        d["terminalAllowlistHasWildcard"] = t.contains("*")
        d["mcpAllowlistDefined"] = (root["mcpAllowlist"] != nil)
        return d
    }
}
