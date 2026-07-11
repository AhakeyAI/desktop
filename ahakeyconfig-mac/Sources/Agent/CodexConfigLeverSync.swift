import Foundation

/// 将键盘拨杆与 Codex `~/.codex/config.toml` 顶层的 **`approval_policy`** 对齐：
/// **自动档 → `"never"`**（不弹审批，直接执行），**手动档 → `"untrusted"`**（除了
/// 纯只读的"已知安全"命令，其余一律暂停询问用户）。
///
/// 注意：项目级 `[projects."<path>"].trust_level` 只控制是否加载该项目本地的 `.codex/`
/// 配置层（config / hooks / rules），**不**决定是否弹出审批确认——那是 `approval_policy`
/// 的职责（官方文档：参见 https://developers.openai.com/codex/config-reference）。
/// 早期版本曾误以为改 `trust_level` 就能让拨杆接管 Codex，经实测无效，已改为
/// `approval_policy`。
///
/// `approval_policy` 的取值语义已通过 Codex 开源仓库源码核实
/// （codex-rs/protocol/src/protocol.rs 中 `enum AskForApproval` 的文档注释）：
///   - `untrusted`（UnlessTrusted）：只有 `is_safe_command()` 判定的"已知安全且仅读文件"
///     的命令会自动放行，其余一律向用户确认——这才是"手动档每条都问"对应的值；
///   - `on-request`（OnRequest，默认值）：由模型自己决定何时询问用户，普通沙箱内命令
///     不会触发询问——实测证明这个值不满足"手动档需每次确认"的诉求（早期版本误用过）；
///   - `never`：从不询问，失败也不上报用户——对应自动档。
/// Codex 的 `PermissionRequest` hook 协议本身不支持 `ask`/`deny`，必须像
/// `KimiConfigLeverSync` 改写 `default_yolo` 一样，直接改写 Codex 自身的审批策略
/// 开关，才能让拨杆真正接管。
enum CodexConfigLeverSync {
    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    static func apply(switchStateAuto: Bool) {
        let desired = switchStateAuto ? "never" : "untrusted"
        let desiredLine = "approval_policy = \"\(desired)\""

        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path),
              let data = fm.contents(atPath: configURL.path),
              let raw = String(data: data, encoding: .utf8) else { return }

        var lines = raw.components(separatedBy: .newlines)

        // approval_policy 是顶层键，必须出现在第一个 `[section]` 之前。
        var firstSectionIdx = lines.count
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                firstSectionIdx = idx
                break
            }
        }

        let pattern = #"^\s*approval_policy\s*="#
        let regex = try? NSRegularExpression(pattern: pattern)
        for idx in 0..<firstSectionIdx {
            let line = lines[idx]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if regex?.firstMatch(in: line, range: range) != nil {
                if line.trimmingCharacters(in: .whitespaces) == desiredLine { return }
                lines[idx] = desiredLine
                write(lines.joined(separator: "\n"))
                return
            }
        }

        lines.insert(desiredLine, at: firstSectionIdx)
        write(lines.joined(separator: "\n"))
    }

    private static func write(_ raw: String) {
        guard let data = raw.data(using: .utf8) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
