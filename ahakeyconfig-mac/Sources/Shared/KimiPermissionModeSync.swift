import Foundation

/// Kimi 配置文件位置。
///
/// Kimi Code CLI 2.x（原生二进制 `~/.kimi-code/bin/kimi`）读取 **`$KIMI_CODE_HOME/config.toml`**，
/// 未设置时为 **`~/.kimi-code/config.toml`**；首次启动会把旧版 Python kimi-cli 的
/// `~/.kimi/config.toml` 迁移过去（含 `[[hooks]]`），之后旧文件不再被读取。
/// 只有本机仍是纯旧版 kimi-cli（没有 Kimi Code 数据目录、只有 `~/.kimi`）时才回落旧路径。
public enum KimiConfigLocation {
    public static func kimiCodeConfigURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let custom = environment["KIMI_CODE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
                .appendingPathComponent("config.toml", isDirectory: false)
        }
        return home.appendingPathComponent(".kimi-code/config.toml", isDirectory: false)
    }

    public static func legacyConfigURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".kimi/config.toml", isDirectory: false)
    }

    /// 当前 Kimi CLI 实际读取的配置文件。
    public static func activeConfigURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        let kimiCode = kimiCodeConfigURL(environment: environment, home: home)
        // 显式 home 是 CLI 的选择，即使尚未首次启动、目录尚不存在也不能回落旧版。
        if let custom = environment["KIMI_CODE_HOME"], !custom.isEmpty { return kimiCode }
        if fileManager.fileExists(atPath: kimiCode.deletingLastPathComponent().path) {
            return kimiCode
        }
        let legacy = legacyConfigURL(home: home)
        return fileManager.fileExists(atPath: legacy.path) ? legacy : kimiCode
    }

    public static func isLegacy(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        url.standardizedFileURL.path == legacyConfigURL(home: home).standardizedFileURL.path
    }
}

/// 将键盘拨杆与 Kimi Code CLI 顶层 **`default_permission_mode`** 对齐：
/// **自动档 → `"yolo"`**，**手动档 → `"manual"`**。
///
/// Kimi Code CLI 的事实边界（2.2.0 实测 + 源码）：
/// - `PreToolUse` hook 只认 `permissionDecision = "deny"`，返回 allow 不会跳过审批弹窗，
///   因此拨杆只能通过权限模式接管。
/// - `default_permission_mode` 只在**新建会话**启动时读取；恢复的会话沿用自身保存的模式，
///   正在运行的会话需在 Kimi 内用 `/yolo`、`/permission` 切换。
/// - `yolo`（Ask When Needed）放行常规编辑与命令，危险命令、提问与计划仍会询问；与旧版
///   `default_yolo = true` 的迁移语义一致。用户若手动设为 `auto`（Never Ask），自动档不降级。
///
/// 文件改写复用 `TomlPolicyLocator`：字节保真、歧义零写，并保留原文件权限（该文件含 API key，通常为 0600）。
public enum KimiPermissionModeSync {
    public static let key = "default_permission_mode"

    enum PermissionMode: String {
        case manual
        case yolo

        static func forLever(switchStateAuto: Bool) -> PermissionMode {
            switchStateAuto ? .yolo : .manual
        }

        /// 已满足该档位、无需改写的现有取值。
        var satisfiedBy: Set<String> {
            switch self {
            case .manual: return ["manual"]
            case .yolo: return ["yolo", "auto"]
            }
        }
    }

    public enum Outcome: Equatable {
        case missingConfig
        case unreadableConfig
        case alreadyDesired
        case replaced
        case inserted
        case writeFailed
        case duplicateKey
        case unsupportedSyntax(reason: String)
    }

    @discardableResult
    public static func apply(switchStateAuto: Bool, configURL: URL) -> Outcome {
        let mode = PermissionMode.forLever(switchStateAuto: switchStateAuto)
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .missingConfig }
        guard let data = fm.contents(atPath: configURL.path),
              String(data: data, encoding: .utf8) != nil else { return .unreadableConfig }
        let bytes = [UInt8](data)

        switch TomlPolicyLocator.locate(bytes, key: key) {
        case .duplicate:
            return .duplicateKey
        case let .unsupported(reason):
            return .unsupportedSyntax(reason: reason)
        case let .existingScalar(range, decoded):
            if mode.satisfiedBy.contains(decoded) { return .alreadyDesired }
            var out = bytes
            out.replaceSubrange(range, with: Array("\"\(mode.rawValue)\"".utf8))
            return write(out, to: configURL) ? .replaced : .writeFailed
        case let .absent(insertionOffset, before, after):
            var insertion = before
            insertion.append(contentsOf: Array("\(key) = \"\(mode.rawValue)\"".utf8))
            insertion.append(contentsOf: after)
            var out = bytes
            out.insert(contentsOf: insertion, at: insertionOffset)
            return write(out, to: configURL) ? .inserted : .writeFailed
        }
    }

    /// 诊断用：读出当前顶层取值（缺键或无法安全解析时为 nil）。
    public static func configuredMode(configURL: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: configURL.path) else { return nil }
        if case let .existingScalar(_, decoded) = TomlPolicyLocator.locate([UInt8](data), key: key) {
            return decoded
        }
        return nil
    }

    private static func write(_ bytes: [UInt8], to url: URL) -> Bool {
        let fm = FileManager.default
        let permissions = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        do {
            try Data(bytes).write(to: url, options: .atomic)
        } catch {
            return false
        }
        // 原子写会新建文件并按 umask 赋权；恢复原权限，避免把 0600 的凭据文件放宽为 0644。
        if let permissions {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        return true
    }
}

/// AhaKey 管理的 Kimi `[[hooks]]` 文本编辑。
public enum KimiHookConfigText {
    /// 删掉不在 AhaKey 标记块内、指向 AhaKey agent 的 `[[hooks]]` 条目。
    ///
    /// 一个 `[[hooks]]` 条目到下一个 table header（任意 `[`）或 AhaKey 标记为止：Kimi Code 迁移后
    /// hooks 位于 `[thinking]` / `[providers…]` / `[models…]` 之前，不能把后续 table 当成 hook 的一部分删掉。
    public static func removingBareAhaKeyHooks(from config: String, blockMarkers: Set<String>) -> String {
        let lines = config.components(separatedBy: .newlines)
        var kept: [String] = []
        var idx = 0

        while idx < lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[[hooks]]" else {
                kept.append(lines[idx])
                idx += 1
                continue
            }

            var block = [lines[idx]]
            idx += 1
            while idx < lines.count {
                let nextTrimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("[") || blockMarkers.contains(nextTrimmed) {
                    break
                }
                block.append(lines[idx])
                idx += 1
            }

            let joined = block.joined(separator: "\n")
            let isAhaKey = joined.contains("ahakeyconfig-agent") || joined.contains("ahakey-state")
            if isAhaKey, joined.contains("hook Kimi") {
                continue
            }
            kept.append(contentsOf: block)
        }

        return kept.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
