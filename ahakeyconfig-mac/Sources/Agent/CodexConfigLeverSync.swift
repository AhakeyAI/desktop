import Foundation

/// 将键盘拨杆与 Codex `~/.codex/config.toml` 顶层的 **`approval_policy`** 对齐：
/// **自动档 → `"never"`**（不弹审批，直接执行），**手动档 → `"on-request"`**（由模型
/// 在需要时暂停询问用户）。
///
/// 历史：手动档曾映射 `"untrusted"`（除已知安全只读命令外一律询问），但 Codex
/// 0.154 起已移除该取值——启动时直接报错
/// `approval_policy = "untrusted" is no longer supported; remove this setting`，
/// 导致客户端无法打开。现取值仅剩 `on-request` / `never`（`codex --help` 实测），
/// 手动档改用 `on-request`。
///
/// 注意：项目级 `[projects."<path>"].trust_level` 只控制是否加载该项目本地的 `.codex/`
/// 配置层（config / hooks / rules），**不**决定是否弹出审批确认——那是 `approval_policy`
/// 的职责（官方文档：参见 https://developers.openai.com/codex/config-reference）。
/// 早期版本曾误以为改 `trust_level` 就能让拨杆接管 Codex，经实测无效，已改为
/// `approval_policy`。
///
/// `approval_policy` 的取值语义已通过 Codex 开源仓库源码核实
/// （codex-rs/protocol/src/protocol.rs 中 `enum AskForApproval` 的文档注释）：
///   - `on-request`（OnRequest，默认值）：由模型自己决定何时询问用户——Codex 0.154 起
///     这是仅剩的"会弹审批"取值，手动档使用；
///   - `never`：从不询问，失败也不上报用户——对应自动档。
/// （旧取值 `untrusted` 已在 0.154 移除，见上文"历史"。）
/// Codex 的 `PermissionRequest` hook 协议本身不支持 `ask`/`deny`，必须像
/// `KimiPermissionModeController` 改写 Kimi 的 `default_permission_mode` 一样，
/// 直接改写 Codex 自身的审批策略开关，才能让拨杆真正接管。
///
/// 深模块边界：唯一写入路径是 `apply(policy:configURL:)`，其入参是 typed
/// `ApprovalPolicy`——因此**类型上不可能**写出 allowlist 之外的取值（含 `untrusted`）。
/// 两个生产 hook 调用点只经 `apply(switchStateAuto:)` 这一个 seam。
enum CodexConfigLeverSync {
    /// 冻结的可写审批策略集合（Codex 0.154 实测仅剩这两个合法值）。
    enum ApprovalPolicy: String, CaseIterable {
        case onRequest = "on-request"
        case never = "never"

        /// 拨杆状态 → policy：自动档 `never`，手动档 `on-request`。
        static func forLever(switchStateAuto: Bool) -> ApprovalPolicy {
            switchStateAuto ? .never : .onRequest
        }

        /// 写进 config.toml 的顶层键行（无缩进，与既有写入位置一致）。
        var configLine: String { "approval_policy = \"\(rawValue)\"" }
    }

    /// 同步结果。fail-safe 语义显式化：读不到 / 非 UTF-8 / 写失败都**不改动**用户配置，
    /// 且不做任何降级写入。
    enum Outcome: Equatable {
        /// 配置文件不存在：不创建。
        case missingConfig
        /// 读取失败或非 UTF-8：不动。
        case unreadableConfig
        /// 已是目标值：幂等早退，零字节变化。
        case alreadyDesired
        /// 就地替换既有顶层键。
        case replaced
        /// 插入到首个 `[section]` 之前（无 section 则追加到末尾）。
        case inserted
        /// 原子写失败：不动（或保留原文件）。
        case writeFailed
    }

    /// 生产配置路径；测试一律注入临时 fixture URL，绝不触碰用户真实 home。
    static var productionConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    /// 生产入口：`CodexSessionStart` / `CodexPermissionRequest` 的唯一 seam。
    static func apply(switchStateAuto: Bool) {
        _ = apply(
            policy: ApprovalPolicy.forLever(switchStateAuto: switchStateAuto),
            configURL: productionConfigURL
        )
    }

    /// 深模块主体：typed policy + 可注入 config URL（测试用 fixture）。
    @discardableResult
    static func apply(policy: ApprovalPolicy, configURL: URL) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .missingConfig }
        guard let data = fm.contents(atPath: configURL.path),
              let raw = String(data: data, encoding: .utf8) else { return .unreadableConfig }

        var lines = raw.components(separatedBy: .newlines)

        // approval_policy 是顶层键，必须出现在第一个 `[section]` 之前。
        var firstSectionIdx = lines.count
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                firstSectionIdx = idx
                break
            }
        }

        let desiredLine = policy.configLine
        let pattern = #"^\s*approval_policy\s*="#
        let regex = try? NSRegularExpression(pattern: pattern)
        for idx in 0..<firstSectionIdx {
            let line = lines[idx]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if regex?.firstMatch(in: line, range: range) != nil {
                if line.trimmingCharacters(in: .whitespaces) == desiredLine { return .alreadyDesired }
                lines[idx] = desiredLine
                return write(lines.joined(separator: "\n"), to: configURL) ? .replaced : .writeFailed
            }
        }

        lines.insert(desiredLine, at: firstSectionIdx)
        return write(lines.joined(separator: "\n"), to: configURL) ? .inserted : .writeFailed
    }

    private static func write(_ raw: String, to url: URL) -> Bool {
        guard let data = raw.data(using: .utf8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
