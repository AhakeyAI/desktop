import Foundation

/// IDE 内 Agent 终端 TUI 的 **「Not in allowlist」** 与 `~/.cursor/permissions.json` 里的 **`terminalAllowlist`**
/// 有关（见 Cursor 文档「permissions.json reference」），与 **`~/.cursor/cli-config.json`（CLI 权限）是两套**。
/// 只改 cli-config 不会作用到该 TUI；拨杆为 0 时在此文件临时合并通配项。
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
    /// 真机验证 `*` 能覆盖任意命令；手动档恢复安装前的完整文件。
    private static let relaxedTerminalPrefixes: [String] = ["*"]

    static func apply(switchStateAuto: Bool) {
        apply(switchStateAuto: switchStateAuto, permissionsURL: permURL)
    }

    static func apply(switchStateAuto: Bool, permissionsURL: URL) {
        if switchStateAuto {
            applyRelaxed(permissionsURL: permissionsURL)
        } else {
            restoreIfNeeded(permissionsURL: permissionsURL)
        }
    }

    private static func applyRelaxed(permissionsURL: URL) {
        let dir = permissionsURL.deletingLastPathComponent()
        let snapshotURL = snapshotURL(for: permissionsURL)
        let hadNoPriorMarker = hadNoPriorMarker(for: permissionsURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: snapshotURL.path) && !fm.fileExists(atPath: hadNoPriorMarker.path) {
            if fm.fileExists(atPath: permissionsURL.path) {
                do {
                    if fm.fileExists(atPath: snapshotURL.path) { try? fm.removeItem(at: snapshotURL) }
                    try fm.copyItem(at: permissionsURL, to: snapshotURL)
                } catch {
                    fprintStderr("CursorPermissionsJsonLeverSync: 无法备份原 permissions.json: \(error.localizedDescription)\n")
                }
            } else {
                try? Data().write(to: hadNoPriorMarker, options: .atomic)
            }
        }

        var root = readJson(permissionsURL) ?? [:]
        var list = stringArray(root["terminalAllowlist"])
        for t in relaxedTerminalPrefixes where !list.contains(t) {
            list.append(t)
        }
        root["terminalAllowlist"] = list
        if !writeJson(root, to: permissionsURL) {
            fprintStderr("CursorPermissionsJsonLeverSync: 无法写回 \(permissionsURL.path)\n")
        }
    }

    private static func restoreIfNeeded(permissionsURL: URL) {
        let snapshotURL = snapshotURL(for: permissionsURL)
        let hadNoPriorMarker = hadNoPriorMarker(for: permissionsURL)
        let fm = FileManager.default
        if fm.fileExists(atPath: hadNoPriorMarker.path) {
            try? fm.removeItem(at: hadNoPriorMarker)
            if fm.fileExists(atPath: permissionsURL.path) { try? fm.removeItem(at: permissionsURL) }
            if fm.fileExists(atPath: snapshotURL.path) { try? fm.removeItem(at: snapshotURL) }
            return
        }
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do {
            if fm.fileExists(atPath: permissionsURL.path) { try fm.removeItem(at: permissionsURL) }
            try fm.copyItem(at: snapshotURL, to: permissionsURL)
            try fm.removeItem(at: snapshotURL)
        } catch {
            fprintStderr("CursorPermissionsJsonLeverSync: 无法从快照恢复 permissions.json: \(error.localizedDescription)\n")
        }
    }

    private static func readJson(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }

    @discardableResult
    private static func writeJson(_ root: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func stringArray(_ v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private static func fprintStderr(_ s: String) {
        FileHandle.standardError.write(Data(s.utf8))
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
