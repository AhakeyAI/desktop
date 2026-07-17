import Foundation

/// Kimi 权限模式的统一决策与适配入口。
///
/// 物理拨杆只在这里被解释一次，之后由三个 adapter 分别落地：
/// - 配置 Adapter：写入 `~/.kimi-code/config.toml` 的 `default_permission_mode`，保证未来会话。
/// - Launcher Adapter：`~/.ahakey/bin/kimi` 在新进程启动时注入 `--yolo`（第一阶段）。
/// - 前台 TUI Adapter：实验性 `/yolo on/off` 实时切换当前会话（第二阶段）。
///
/// 任何一层都不应独自解释拨杆状态，避免配置说 manual、launcher 却加 `--yolo` 的冲突。
enum KimiPermissionModeController {
    enum DesiredPermissionMode: String, CustomStringConvertible {
        case manual
        case yolo

        var description: String { rawValue }
    }

    enum ApplyResult: CustomStringConvertible {
        case applied(DesiredPermissionMode)
        case unchanged(DesiredPermissionMode)
        case failed(String)

        var description: String {
            switch self {
            case .applied(let mode): return "applied(\(mode))"
            case .unchanged(let mode): return "unchanged(\(mode))"
            case .failed(let reason): return "failed(\(reason))"
            }
        }
    }

    /// 由拨杆状态决定期望权限模式。
    /// - switchState == 0 → 自动档（yolo）
    /// - switchState != 0 或未知 → 手动档（manual）
    static func desiredMode(for switchState: Int?) -> DesiredPermissionMode {
        switchState == 0 ? .yolo : .manual
    }

    // MARK: - 配置层 Adapter

    /// 把拨杆状态同步到 `~/.kimi-code/config.toml` 的 `default_permission_mode`。
    /// 这是未来新 Kimi 会话的默认权限模式兜底。
    static func applyConfigLayer(forSwitchState switchState: Int?) -> ApplyResult {
        let mode = desiredMode(for: switchState)
        let adapter = ConfigAdapter()
        return adapter.apply(mode: mode)
    }

    /// 读取当前磁盘上配置的默认模式（仅用于诊断）。
    static func readConfiguredMode() -> DesiredPermissionMode? {
        ConfigAdapter().readMode()
    }
}

// MARK: - 配置 Adapter 实现

private extension KimiPermissionModeController {
    final class ConfigAdapter {
        private static var configURL: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".kimi-code/config.toml", isDirectory: false)
        }

        private static var backupURL: URL {
            configURL.appendingPathExtension("ahakey.bak")
        }

        private static var candidateURL: URL {
            configURL.appendingPathExtension("ahakey.candidate")
        }

        func readMode() -> KimiPermissionModeController.DesiredPermissionMode? {
            guard let raw = try? String(contentsOf: Self.configURL, encoding: .utf8) else { return nil }
            guard let line = findTopLevelLine(forKey: "default_permission_mode", in: raw) else { return nil }
            let value = line.components(separatedBy: "=").dropFirst().joined(separator: "=")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
            switch value {
            case "yolo": return .yolo
            case "manual": return .manual
            default: return nil
            }
        }

        func apply(mode: KimiPermissionModeController.DesiredPermissionMode) -> KimiPermissionModeController.ApplyResult {
            let fm = FileManager.default
            let path = Self.configURL.path

            guard fm.fileExists(atPath: path) else {
                KimiHookDebugLog.append(event: "kimi_permission_mode_config_missing", details: ["path": path])
                return .failed("未找到 \(path)")
            }

            guard let raw = try? String(contentsOf: Self.configURL, encoding: .utf8) else {
                return .failed("无法读取 \(path)")
            }

            // 如果已经是对目标值，直接返回，避免无意义写盘。
            if let existingLine = findTopLevelLine(forKey: "default_permission_mode", in: raw),
               lineContains(mode: mode, line: existingLine) {
                return .unchanged(mode)
            }

            // 备份原文件（仅首次写入前保留一份，用于回滚）。
            if !fm.fileExists(atPath: Self.backupURL.path) {
                do {
                    try? fm.removeItem(at: Self.backupURL)
                    try fm.copyItem(at: Self.configURL, to: Self.backupURL)
                    KimiHookDebugLog.append(event: "kimi_permission_mode_backup_created", details: ["to": Self.backupURL.path])
                } catch {
                    KimiHookDebugLog.append(event: "kimi_permission_mode_backup_failed", details: ["error": error.localizedDescription])
                }
            }

            let desiredLine = "default_permission_mode = \"\(mode)\"  # AhaKey: dial \(mode)"
            let updated = replaceOrInsertTopLevel(key: "default_permission_mode", valueLine: desiredLine, in: raw)

            // 先写入候选文件，再做原子替换，避免写坏原配置。
            do {
                try updated.write(to: Self.candidateURL, atomically: true, encoding: .utf8)
            } catch {
                return .failed("无法写入候选文件 \(Self.candidateURL.path)：\(error.localizedDescription)")
            }

            // 基础格式校验：替换后仍应是合法 TOML 顶层键值对结构。
            guard validateCandidate(updated, desiredMode: mode) else {
                return .failed(NSLocalizedString("候选文件格式校验失败，未替换原配置", comment: ""))
            }

            do {
                try? fm.removeItem(at: Self.configURL)
                try fm.moveItem(at: Self.candidateURL, to: Self.configURL)
                KimiHookDebugLog.append(event: "kimi_permission_mode_config_applied", details: [
                    "mode": mode.description,
                    "path": path,
                ])
                return .applied(mode)
            } catch {
                // 尝试从备份恢复。
                if fm.fileExists(atPath: Self.backupURL.path) {
                    try? fm.copyItem(at: Self.backupURL, to: Self.configURL)
                }
                return .failed("原子替换失败：\(error.localizedDescription)")
            }
        }

        // MARK: - 顶层字段编辑器

        /// 在文本中查找指定顶层键所在行（不进入任何 `[section]` 之内）。
        private func findTopLevelLine(forKey key: String, in text: String) -> String? {
            let lines = text.components(separatedBy: .newlines)
            let keyPattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*="#
            guard let regex = try? NSRegularExpression(pattern: keyPattern, options: []) else { return nil }
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") { return nil }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    return line
                }
            }
            return nil
        }

        private func lineContains(mode: KimiPermissionModeController.DesiredPermissionMode, line: String) -> Bool {
            line.contains("\"\(mode)\"") || line.contains("'\(mode)'")
        }

        /// 保留格式地替换或插入顶层键：
        /// - 找到则只改那一行；
        /// - 找不到则插入到第一个 `[section]` 之前。
        private func replaceOrInsertTopLevel(key: String, valueLine: String, in text: String) -> String {
            let lines = text.components(separatedBy: .newlines)
            let keyPattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*="#
            guard let regex = try? NSRegularExpression(pattern: keyPattern, options: []) else {
                return valueLine + "\n\n" + text
            }

            var firstSectionIdx: Int?
            for (idx, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                    firstSectionIdx = idx
                    break
                }
            }

            for (idx, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    var mutable = lines
                    mutable[idx] = valueLine
                    return mutable.joined(separator: "\n")
                }
            }

            var mutable = lines
            let insertAt = firstSectionIdx ?? mutable.count
            mutable.insert(valueLine, at: insertAt)
            // 保证插入位置前后至少有一个空行，避免粘到注释或 section 上。
            if insertAt < mutable.count, !mutable[insertAt + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                mutable.insert("", at: insertAt + 1)
            }
            if insertAt > 0, !mutable[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                mutable.insert("", at: insertAt)
            }
            return mutable.joined(separator: "\n")
        }

        /// 简单校验：候选文件必须仍包含我们期望的顶层键值，且没有意外破坏 `[section]` 结构。
        private func validateCandidate(_ text: String, desiredMode: KimiPermissionModeController.DesiredPermissionMode) -> Bool {
            guard let line = findTopLevelLine(forKey: "default_permission_mode", in: text) else { return false }
            return line.contains("\"\(desiredMode)\"")
        }
    }
}
