import Foundation

/// IDE 内 Agent 终端 TUI 的 **「Not in allowlist」** 与 `~/.cursor/permissions.json` 里的 **`terminalAllowlist`**
/// 有关（见 Cursor 文档「permissions.json reference」），与 **`~/.cursor/cli-config.json`（CLI 权限）是两套**。
/// 只改 cli-config 不会作用到该 TUI；拨杆为 0 时在此文件合并 `terminalAllowlist` 的前缀项。
enum CursorPermissionsJsonLeverSync {
    private static var permURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("permissions.json", isDirectory: false)
    }

    private static var snapshotURL: URL { permURL.appendingPathExtension("ahakey.lever0.bak") }
    private static var hadNoPriorMarker: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent(".ahakey_had_no_permissions_json", isDirectory: false)
    }

    /// 与文档「Terminal allowlist format」一致：前缀匹配，如 `cd` 可匹配以 `cd ` 开头的整行；另含 `swift` 等以覆盖 `cd … && swift …` 被拆检的情况。
    private static let relaxedTerminalPrefixes: [String] = [
        "cd", "swift", "swift build", "xcodebuild", "git", "npm", "yarn", "pnpm", "bun", "deno", "node",
        "make", "cargo", "go", "python3", "python", "ruby", "bash", "zsh", "sh", "curl", "ls",
    ]

    static func apply(switchStateAuto: Bool) {
        if switchStateAuto {
            applyRelaxed()
        } else {
            restoreIfNeeded()
        }
    }

    private static func applyRelaxed() {
        let dir = permURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: snapshotURL.path) && !fm.fileExists(atPath: hadNoPriorMarker.path) {
            if fm.fileExists(atPath: permURL.path) {
                do {
                    if fm.fileExists(atPath: snapshotURL.path) { try? fm.removeItem(at: snapshotURL) }
                    try fm.copyItem(at: permURL, to: snapshotURL)
                } catch {
                    fprintStderr("CursorPermissionsJsonLeverSync: 无法备份原 permissions.json: \(error.localizedDescription)\n")
                }
            } else {
                try? Data().write(to: hadNoPriorMarker, options: .atomic)
            }
        }

        var root = readJson(permURL) ?? [:]
        var list = stringArray(root["terminalAllowlist"])
        for t in relaxedTerminalPrefixes where !list.contains(t) {
            list.append(t)
        }
        root["terminalAllowlist"] = list
        if !writeJson(root, to: permURL) {
            fprintStderr("CursorPermissionsJsonLeverSync: 无法写回 \(permURL.path)\n")
        }
    }

    private static func restoreIfNeeded() {
        let fm = FileManager.default
        if fm.fileExists(atPath: hadNoPriorMarker.path) {
            try? fm.removeItem(at: hadNoPriorMarker)
            if fm.fileExists(atPath: permURL.path) { try? fm.removeItem(at: permURL) }
            if fm.fileExists(atPath: snapshotURL.path) { try? fm.removeItem(at: snapshotURL) }
            return
        }
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do {
            if fm.fileExists(atPath: permURL.path) { try fm.removeItem(at: permURL) }
            try fm.copyItem(at: snapshotURL, to: permURL)
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
            "lever0SnapshotBakExists": fm.fileExists(atPath: snapshotURL.path),
            "hadNoPriorMarkerExists": fm.fileExists(atPath: hadNoPriorMarker.path),
        ]
        guard let root = readJson(permURL) else { return d }
        let t = stringArray(root["terminalAllowlist"])
        d["terminalAllowlistCount"] = t.count
        d["terminalAllowlistHasPrefix_cd"] = t.contains { $0 == "cd" || $0.hasPrefix("cd:") }
        d["terminalAllowlistHasPrefix_swift"] = t.contains { $0 == "swift" || $0.hasPrefix("swift ") }
        d["mcpAllowlistDefined"] = (root["mcpAllowlist"] != nil)
        return d
    }
}
