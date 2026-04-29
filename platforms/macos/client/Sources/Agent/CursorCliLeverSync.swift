import Foundation

/// 拨杆为 0 时，临时放宽 `~/.cursor/cli-config.json` 的 `permissions`（等效于不拦常见白名单项）；
/// 非 0 时从首帧快照恢复，与 HookClient 的 `permission` 输出配合使用。
///
/// 说明：仅影响 Cursor 自行读取的全局/配置层；`switchState` 未读到（nil）时不会改文件。
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

    /// 通配符与 Cursor 文档一致。另含显式 `Shell(cd)` / `Shell(swift)` 等：部分版本 Agent 的 TUI 在报
    /// 「Not in allowlist: cd /path, swift …」时未把 `Shell(*)` 与复合命令行对齐，需首词/工具链单独写。
    private static let relaxedAllow: [String] = [
        "Shell(*)", "Shell(cd)", "Shell(swift)", "Shell(bash)", "Shell(zsh)", "Shell(sh)",
        "Read(**/*)", "Write(**/*)", "WebFetch(*)", "Mcp(*:*)",
    ]

    /// 在回写 `permission: allow|ask` 的 **之前** 调用，保证 Cursor 随后读配置时已是宽松/已恢复。
    static func apply(switchStateAuto: Bool) {
        if switchStateAuto {
            applyRelaxed()
        } else {
            restoreIfneeded()
        }
    }

    private static func applyRelaxed() {
        let cursorDir = cliURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: snapshotURL.path) && !fm.fileExists(atPath: hadNoPriorCliMarker.path) {
            if fm.fileExists(atPath: cliURL.path) {
                do {
                    if fm.fileExists(atPath: snapshotURL.path) { try? fm.removeItem(at: snapshotURL) }
                    try fm.copyItem(at: cliURL, to: snapshotURL)
                } catch {
                    fprintStderr("CursorCliLeverSync: 无法备份原 cli-config: \(error.localizedDescription)\n")
                }
            } else {
                do {
                    try Data().write(to: hadNoPriorCliMarker, options: .atomic)
                } catch { /* 忽略 */ }
            }
        }

        var root = readJson(cliURL) ?? [:]
        if root["version"] == nil { root["version"] = 1 }
        var perms = root["permissions"] as? [String: Any] ?? [:]
        var allow = stringArray(from: perms["allow"])
        for token in relaxedAllow {
            if !allow.contains(token) { allow.append(token) }
        }
        perms["allow"] = allow
        if perms["deny"] == nil { perms["deny"] = [String]() }
        root["permissions"] = perms
        root["approvalMode"] = "auto"
        if !writeJson(root, to: cliURL) {
            fprintStderr("CursorCliLeverSync: 无法写回 \(cliURL.path)（仍返回 hook 的 permission）\n")
        }
    }

    private static func restoreIfneeded() {
        let fm = FileManager.default
        if fm.fileExists(atPath: hadNoPriorCliMarker.path) {
            try? fm.removeItem(at: hadNoPriorCliMarker)
            if fm.fileExists(atPath: cliURL.path) {
                try? fm.removeItem(at: cliURL)
            }
            if fm.fileExists(atPath: snapshotURL.path) {
                try? fm.removeItem(at: snapshotURL)
            }
            return
        }
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do {
            if fm.fileExists(atPath: cliURL.path) { try fm.removeItem(at: cliURL) }
            try fm.copyItem(at: snapshotURL, to: cliURL)
            try fm.removeItem(at: snapshotURL)
        } catch {
            fprintStderr("CursorCliLeverSync: 无法从快照恢复 cli-config: \(error.localizedDescription)\n")
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

    private static func stringArray(from v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private static func fprintStderr(_ s: String) {
        FileHandle.standardError.write(Data(s.utf8))
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
