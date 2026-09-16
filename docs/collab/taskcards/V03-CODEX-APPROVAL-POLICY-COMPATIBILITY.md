# 任务卡 V03-CODEX-APPROVAL-POLICY-COMPATIBILITY：Codex 0.154 审批策略兼容

计划/WBS：5.3-C / v0.3 线上兼容阻断修复
状态：`ready / C5J`
执行 owner：DSH
验收：Codex
提出/现场止血：Zcode
基线：`5963fcda20727c50d2d3fb2903b113061e4dfd51`（C5IR8 accepted 后的冻结 HEAD）；工作区 `CodexConfigLeverSync.swift` 修改归本卡

## 问题与用户影响

Codex CLI 0.154 已不接受顶层 `approval_policy = "untrusted"`。现有 `CodexConfigLeverSync` 在拨杆手动档仍写入该值，导致 Codex 在解析 `~/.codex/config.toml` 时直接退出，用户无法启动客户端。Zcode 已完成现场止血：删除用户配置中的坏值，并对已安装 0.2.1 App 的 agent 做 era-matched 单行修复和重签；这些外部修改不是正式产品交付。

权威交接证据：`docs/collab/HANDOVER-ZCODE-TO-DSH-20260916.md`。

## 冻结产品语义

- 自动档：`approval_policy = "never"`。
- 手动档：`approval_policy = "on-request"`，由模型决定何时询问。
- 正式产品任何路径写入 `approval_policy` 时只允许 `on-request` / `never`；`untrusted` 永远不得作为可写值。
- “手动档每条必问”在 Codex 0.154 config 层没有等价值；不得为恢复旧文案重新写入 `untrusted`。
- Cursor、Claude、Kimi 及其他 agent 的 lever sync 不在本卡范围。

## 允许修改

- `ahakeyconfig-mac/Sources/Agent/CodexConfigLeverSync.swift`
- `ahakeyconfig-mac/Sources/Agent/CodexHookHandler.swift`（仅为依赖注入/两个既有调用点接线所需；不得改 Hook 协议语义）
- 新增专用测试：`ahakeyconfig-mac/Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`
- `ahakeyconfig-mac/Package.swift`（仅测试 target 必需接入）
- 若精确扫描发现“Codex 手动档每条确认”的生产文案，可改该句及中英文 localization；当前已知“按各自确认链”无需改
- 本卡、单一 evidence、DSH append-only board 条目

## 禁止事项

- 不修改 `AhaKeyAgentRuntimeEndpointTests.swift`，避免与 C5IR8 当前施工冲突。
- 不改 Cursor/Claude/Kimi 权限同步、Runtime WAL/XPC/BLE、OLED C2–C5、安装器或固件。
- 不读取、覆盖或删除用户真实 `~/.codex/config.toml`、两份现场备份、已安装 App 备份。
- 不把 `/Applications` 二进制替换、codesign 产物或缓存文件提交进仓库。
- 不把现有 board/queue/其他任务卡 dirty 吞入产品提交。
- 不安装、重签、重启 Runtime、push，除非另获精确 USER-GATE。

## 完成定义

### 1. 红能力回归环

先在临时目录配置 fixture 上建立确定性测试，证明旧映射会把手动档写成 `untrusted` 并使“合法值集合”断言失败；修复后转绿。测试不得访问用户真实 home。

推荐深模块形态：用 typed policy（如仅含 `onRequest`/`never` 的 enum）生成字符串，并给同步函数注入测试 config URL；生产入口仍使用现有 `~/.codex/config.toml` 路径。

### 2. 文件语义

- 已有顶层 `untrusted`：手动档改为 `on-request`，自动档改为 `never`。
- 已有合法值：按拨杆精确切换；目标相同保持幂等，不产生无关字节变化。
- 缺少键：插入第一个 TOML section 前。
- 保留其它顶层键、sections、注释、换行和非目标内容；不得重写整个配置语义。
- 无法读取/UTF-8/写入失败保持既有 fail-safe 边界，并有测试或明确返回语义。

### 3. 两个生产调用点

`CodexSessionStart` 与 `CodexPermissionRequest` 必须继续把自动/手动拨杆状态映射到同一 typed policy seam；新增静态或集成断言防止任一调用点绕过 seam 或重新引入字面 `untrusted`。

### 4. 兼容与文案

- 产品可执行代码不得包含将 `untrusted` 写入 `approval_policy` 的路径；注释/迁移 fixture 可保留该历史字面量。
- 检查 UI/localization，不得宣称 Codex 手动档“每条必问”；无错误文案则零改 UI。
- 若本机存在 Codex 0.154，可在隔离 `CODEX_HOME`（或等价临时配置根）运行解析 smoke；不得触碰真实配置。环境不支持隔离时如实标记未执行，不以真实 home 冒险替代。

### 5. 门禁与提交

- 专用测试全绿；相关 Agent/Hook 定向测试全绿。
- 全量 `swift test`、App + Agent Release、identity check、`git diff --check`。
- 产品提交只包含本卡白名单；现场热修、备份和协作 dirty 不进提交。
- evidence 记录当前 Codex 版本、红/绿 fixture、最终允许值集合与未执行项；完成后停手提审。

## 前置与晋级

1. C5IR8 已由 Codex 验收并冻结基线 `5963fcd`。
2. DSH 只执行本卡白名单，不回改 `AhaKeyAgentRuntimeEndpointTests.swift` / `SwiftSourceBoundaryAudit*`。
3. 本卡 accepted 后，15L 才可继续申请下一真机 USER-GATE；旧 HIL 授权不得复用。

## 现场热修边界

- `~/.codex/config.toml` 已删除坏值且有独立备份；不由本卡再次修改。
- 已安装 0.2.1 agent 为 era-matched 临时二进制修复；正式新版安装后自然覆盖。除非另获安装/回滚授权，本卡不操作该二进制。
- 常驻 daemon 未重启；当前修复依赖 Hook 子进程从磁盘启动新二进制。该事实只作现场说明，不是产品验收替代品。
## DSH 执行记录

### [2026-09-16 14:43] DSH：15K-J 完成，停手提审（生产单文件 + 新增专用测试）

- **白名单提交**：`Sources/Agent/CodexConfigLeverSync.swift`（typed `ApprovalPolicy` + 可注入 `configURL` + typed `Outcome`）、新增 `Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`（16 项）、evidence、本卡。**未改** `CodexHookHandler.swift`（两个调用点原样经既有 seam）、`Package.swift`、`AhaKeyAgentRuntimeEndpointTests.swift`、`SwiftSourceBoundaryAudit*`。
- **冻结语义落地**：`ApprovalPolicy` 仅 `onRequest = "on-request"` / `never = "never"`；`forLever(switchStateAuto:)` 做拨杆映射；`untrusted` 不可表示（`ApprovalPolicy(rawValue: "untrusted") == nil`）；唯一写路径 `apply(policy:configURL:)`，生产入口 `apply(switchStateAuto:)` 仍用真实 `~/.codex/config.toml`。
- **文件语义**：已有 `untrusted` → 手动 `on-request` / 自动 `never`；合法值幂等早退（零字节变化）；缺键插入首个 `[section]` 之前（无 section 追加）；其它顶层键/sections/注释/空行/尾换行逐字节保留；缺文件不创建、非 UTF-8 原样保留、写失败 typed `.writeFailed`。
- **红→绿（真实二进制）**：隔离 `CODEX_HOME` 下 codex-cli 0.154.0-alpha.6.2 —— `on-request` / `never` 解析通过（`Not logged in`），`untrusted` 报 `approval_policy = "untrusted" is no longer supported; remove this setting`。真实 `~/.codex/config.toml` 全程只读，sha256 前后一致。
- **mutant（原子化 patch→run→restore+sha）**：M1 还原旧字面映射（手动档 → `untrusted`）→ **6 项永久测试红**；M2 调用点绕过 typed seam → **2 项红**；两次均还原并复核 sha `d39bc744…` / `7370587f…`。
- **门禁**：新类 16/16；Agent/Hook 定向 9 类 183/183；全量第 6 次 **1251 / 2 skipped / 0 failures**；App + Agent Release rc=0；`release identity ok`；工作区与全范围 `git diff --check` **clean**（顺带清除本卡头部 4 行尾空格，此前红点为 `af48d21` 引入）。
- **已登记 flake 披露**：全量前 5 次各命中既有 flake（Agent concurrency / Store inode）；accepted HEAD `5963fcd` 独立 worktree 全量 3/3 命中**同样两项** ⇒ 与本卡改动无关。
- **UI/localization 零改**：审计 `Sources/**` 与中英 `Localizable.strings`，无「手动档每条必问」类描述。
- 未安装/重签/重启 Runtime/push；未动已安装 app 二进制、现场备份与真实配置。证据 `docs/collab/evidence/V03-CODEX-APPROVAL-20260916/01-c5j-codex-approval-policy.md`。
- 需要回复：是（@Codex 复核 15K-J：typed seam、untrusted 迁移与幂等、缺键插入位置、fail-safe 语义、两个调用点不变量、真实 0.154 隔离 smoke、两组 mutant、定向/全量/Release/identity/diff-check）
