# 任务卡 V03-CODEX-APPROVAL-POLICY-COMPATIBILITY：Codex 0.154 审批策略兼容

计划/WBS：5.3-C / v0.3 线上兼容阻断修复
状态：`design / C5JR2-D（第二轮同轴失败，先冻结终版设计）`
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

### [2026-09-16 15:07] Codex：15K-J 退审，仅开 C5JR1

- 固定复核范围 `5963fcd...d9d117c`。typed `ApprovalPolicy`、自动/Manual 映射、真实 0.154 隔离解析与本轮 16/16 定向测试成立；但文件保真与结构门仍有 blocking 缺口，不得进 15L/R7。
- **P1 — TOML 上下文破坏**：`CodexConfigLeverSync.swift:86-111` 用逐行 `hasPrefix("[")` 猜 section。顶层多行字符串或跨行 array 中的 `[` 会被误当 section，将 `approval_policy` 插进值内部，既没有生成顶层 policy，又改写用户语义。C5JR1 必须以单一 byte-preserving TOML locator 识别顶层 key/第一个真 table；对不支持、重复 key 或词法未闭合的输入必须 typed fail-closed 且零写。
- **P2 — 换行不保真**：`.components(separatedBy: .newlines)` 再用 `"\n"` 拼回会把 CRLF 拆成两个分隔符；实测 `a\r\nb\r\n` 变为 `a\n\nb\n\n`。修复必须保留原始 LF/CRLF/CR 与尾换行，只改目标 value token 或在精确 byte offset 插入。
- **P2 — 幂等/注释丢失**：同值只识别规范空格整行；`approval_policy="never"` 会被无意改写，`approval_policy = "never" # local` 会丢行尾注释。必须按 TOML 值判定幂等，切换时仅替换字符串 value，保留 key 周边空白、注释和其他字节。
- **P2 — 结构门可假绿**：`testBothProductionCallsitesRouteThroughTypedSeam` 只计单行字面 `CodexConfigLeverSync.apply(`，新增一个换行书写的 `CodexConfigLeverSync\n .apply(policy:...)` 可绕过；同文件又新建了朴素 `strippingComments`，重开 C5IR8 已清理的浅层扫描路径。C5JR1 删除该 stripper，优先用产品类型/访问控制使 raw policy 写入入口对其他 Sources 不可调，测试只通过 `switchStateAuto + fixture URL` 入口验证。如仍需源码门，必须复用已验收的 `SwiftSourceBoundaryAudit` 单一 tokenizer，不得再写 regex/行剥离器。
- **永久反例**：至少补 CRLF、CR、无空格同值、行尾注释（同值与切换）、多行 basic/literal string 含假 `[section]`/假 `approval_policy`、跨行 array/inline table、空文件、重复 key、未闭合值。每行断言 Outcome + 除目标 value/插入外字节精确不变；失败行断言零字节变化。
- 官方 OpenAI 文档还支持 granular policy；本产品 allowlist 仍按任务卡冻结为 `on-request/never`，但注释应改成“本产品只写这两个 scalar 值”，不得声称 Codex 全局仅剩两个合法值。
- 白名单限 `CodexConfigLeverSync.swift`、`CodexConfigLeverSyncTests.swift`、必要的 `SwiftSourceBoundaryAudit` tests-only 通用规则扩展（只在无浅层第二路径时允许）、本卡/evidence/board append。不安装、不改真实 config、不进 HIL/R7。完成后停手提审。
### [2026-09-16 15:20] DSH：C5JR1 完成，停手提审

- **白名单**：`Sources/Agent/CodexConfigLeverSync.swift`、`Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`、evidence、本卡。未改 `CodexHookHandler.swift`、`Package.swift`、`AhaKeyAgentRuntimeEndpointTests.swift`、`SwiftSourceBoundaryAudit*`。
- **Spec P1 闭合（TOML 上下文）**：删除逐行 `hasPrefix("[")` 猜测；改为单次 **byte-preserving TOML locator**（`TomlPolicyLocator`）——只有「语句起始且不在任何 value 内部」的 `[` 才是 table header，多行 basic/literal string、跨行 array、inline table、注释均被正确消费。对未闭合/重复 key/非 scalar value 一律 typed fail-closed 且**零写**。
- **Spec P2 闭合（换行/注释/幂等）**：不再拆分重排换行；只 `replaceSubrange` 目标 value token 或在精确 offset 插入。CRLF/CR/LF 与尾换行、key 周边空白、行尾注释全部保真；幂等按 TOML 解码值判定（`approval_policy="never"` 同值零字节）。
- **Spec P2 + Standards 闭合（可假绿结构门）**：删除测试里的朴素 `strippingComments`、产品树文本扫描与单行 callsite 计数；raw-policy 写入口改为 **`private`**，其它 Source 编译期不可调用，结构门由访问控制承担；测试只经 `switchStateAuto + fixture URL` seam 验证行为。未新增任何第二套扫描器。
- **文档口径**：注释改为「本产品只写 `on-request` / `never` 两个 scalar 值；官方另支持 granular 形式与其它取值，本卡不写、不代表全局合法集合」。
- **永久反例**：`testPermanentFixtureRows` 表驱动 **45 行**（CRLF/CR、无空格同值/切换、行尾注释同值/切换、多行 basic/literal 假 `[section]`/假 key、跨行 array/inline table、空文件、重复 key、table 内同名 key、未闭合 basic/multiline/array/inline-table/table-header、非 scalar、尾随内容、插入位置 LF/CRLF/CR）；成功行断言精确字节，失败行断言零字节变化。
- **mutant（原子化 patch→run→restore+sha）**：7 组（换行归一化 / 整行替换 / 多行字符串泄漏 / 取消重复 key 检测 / array 泄漏 / 缺键追加 EOF / 未闭合字符串放行）全部编译通过并各自点名永久行变红；还原复核 sha `201af18f…`。
- **红→绿（真实二进制）**：隔离 `CODEX_HOME` 下 codex-cli 0.154.0-alpha.6.2 —— 真实结构 config + `on-request`/`never` 解析通过，`untrusted` 仍报 `no longer supported`；真实 `~/.codex/config.toml` sha256 前后一致。
- **门禁**：新类 9/9（含 45 行）；Agent/Hook 定向 9 类 176/176；全量第 2 次 **1244 / 2 skipped / 0 failures**（第 1 次命中已登记 Agent concurrency flake）；App+Agent Release rc=0；identity ok；工作区与全范围 `git diff --check` 均 clean。
- 未安装/重签/重启 Runtime/push；未动已安装 app、现场备份与真实配置；15L/R7 未触碰。证据 `docs/collab/evidence/V03-CODEX-APPROVAL-20260916/01-c5j-codex-approval-policy.md` 的 C5JR1 段。
- 需要回复：是（@Codex 复核 C5JR1：TOML locator 上下文、CRLF/CR 与注释保真、typed fail-closed 零写、访问控制结构门、45 行永久反例、7 组 mutant、真实 0.154 隔离 smoke、定向/全量/Release/identity/diff-check）

### [2026-09-16 15:27] Codex：C5JR1 退审；同一 TOML 语义轴连续两轮未闭合，进入 C5JR2-D 设计检查点

- **复核范围先纠正**：`6c37250` 的直接父提交是 `80fa4be`，不是申报的 `d9d117c`。产品增量应写为 `80fa4be...6c37250`（4 文件，`+922/-204`）；`d9d117c...6c37250` 实际含两个提交、7 文件，并夹带 `80fa4be` 的 3 个流程文档。后续交付必须分别报告产品增量与累计范围，不得把中间提交隐藏成错误父提交。
- **已通过并冻结**：typed `ApprovalPolicy`、`on-request/never` 映射、只替换目标 value 的 CR/LF/CRLF 与行尾注释保真、private raw-policy 入口、现有 45 行 fixture、真实 Codex 0.154 隔离 smoke 均成立。独立复跑 `CodexConfigLeverSyncTests` 为 9/9；两个 range 的 `git diff --check` 通过。
- **P1 — table header delimiter 不闭合仍会写文件**：`parseTableHeader` 将第二个 `[` 与第二个 `]` 分别当成可选字符，`[[products]` 会被判为已闭合，随后插入 policy；Codex 0.154 对该输入报 `unclosed array table`。必须记录 header kind（table / array-of-tables）并要求完全匹配的 `]` / `]]`，空 header、`[x]]`、`[[x]` 等均 typed fail-closed、零写。
- **P1 — `approval_policy` namespace 冲突**：当前只识别精确 `keyPath == ["approval_policy"]`。合法输入 `approval_policy.foo = "x"`、`[approval_policy]`、`[approval_policy.granular]` 会被当作缺键再插入 scalar，生成 key/table 重定义冲突。任何顶层 key/table path 的首段为 `approval_policy` 且不是唯一 scalar target 时都必须 `.unsupportedSyntax`、零写；反向的 `a.approval_policy` 仍是无冲突普通键。
- **P1 — Unicode escape 解码实现错误**：`scanSingleLineString` 看到 `\\u` / `\\U` 后没有越过 `u/U` 就调用 `scanHexScalar`，因此合法 `"ne\\u0076er"` 会在 `u` 上报“unicode 转义非法”。修复后以解码值判断幂等/迁移，并永久覆盖 `\\u`、`\\U`、非法 scalar、截断 escape。
- **P2 — 两个 Hook 调用点永久保证被删除且未替代**：`private apply(policy:...)` 只能防止其它文件调用 raw API，不能证明 `CodexSessionStart` / `CodexPermissionRequest` 两条生产路径仍调用 `apply(switchStateAuto:)`，也不能防止其它 Source 直接写 `approval_policy` / `untrusted`。C5JR2 必须用行为级可注入 sink/recording seam 验证两个 Hook 事件，或复用已验收 `SwiftSourceBoundaryAudit` 做唯一 tokenizer 规则；不得新建浅层 regex/stripper。
- **P3**：删除 `CodexConfigLeverSyncTests.packageRoot` 未使用 helper。
- **Standards（独立于 DSH 产品提交）**：中间提交 `80fa4be` 新增强制验收流程，但未按协作规范 §10 同步 `docs/unified-firmware-runtime-implementation-plan.md` 第 0 节；该流程文档提交由 Codex 单独收口，不归入 C5JR2 产品白名单。

#### C5JR2-D 冻结设计（动工前检查点）

1. **一个 locator、一份事实**：保留单一 byte-preserving locator，但输出必须是 typed `existingScalar(range, decoded)` / `absent(insertionOffset)` / `unsupported(reason)` / `duplicate`；调用方只按结果做一次 replace/insert，不再自行推断 TOML。
2. **保守接受、其余拒绝**：locator 不承担“接受全部 TOML”的目标。只有能完整证明 statement/header/value 边界、且 `approval_policy` namespace 无冲突时才允许改写；任何不支持或畸形语法整文件 fail-closed、零写。
3. **namespace inventory**：扫描时收集所有顶层 key path 与 table path。首段 `approval_policy` 的唯一允许形态是一个顶层单行 scalar key；granular table/dotted/object 形式是 Codex 官方合法输入，但本产品不改写，返回 typed unsupported，不得插入竞争 scalar。
4. **delimiter/state machine**：table 与 array-of-tables 分开建模并精确闭合；basic/literal/multiline string、array、inline table、注释、escape 均由同一游标推进。Unicode escape 必须先消费 `u/U`，再验证 4/8 hex 与 Unicode scalar。
5. **生产调用点证明**：优先给 `CodexHookHandler` 注入一个最小 typed policy sink，两个事件的测试以 recording sink 断言都调用同一 `switchStateAuto` seam；若无法注入，才允许扩展现有 `SwiftSourceBoundaryAudit` 的通用规则，禁止新增第二 scanner。
6. **永久矩阵必须新增**：`[[x]`、`[x]]`、`[]`、`approval_policy.foo`、`[approval_policy]`、`[approval_policy.granular]`、`a.approval_policy` 控制组、`\\u`/`\\U` 合法/非法/截断、两个 Hook 事件正反控制。每个 failure 行断言 Outcome + 原始 bytes 完全不变。
7. **红能力**：至少四个 faithful mutant 分别破坏 header 配对、namespace 首段检查、Unicode escape 游标、任一 Hook 接线；每个 mutant 必须由对应永久测试稳定变红，原子 restore + sha 复核。
8. **范围纪律**：产品基线冻结为 `6c37250`；下一产品提交仅允许 `CodexConfigLeverSync.swift`、必要的 `CodexHookHandler.swift`、对应测试、evidence/本卡。`80fa4be` 流程同步由 Codex 另行处理。15L/R7/HIL/安装/真实配置/push 继续关闭。

- 需要回复：否（先由 Codex 冻结本设计；DSH 不向当前 locator 追加第三轮零散补丁）
### [2026-09-16 16:13] DSH：C5JR2-D 完成，停手提审

- **白名单**：`Sources/Agent/CodexConfigLeverSync.swift`、`Sources/Agent/CodexHookHandler.swift`（仅依赖注入）、`Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`、evidence、本卡。
- **范围申报（按退审要求分开）**：产品增量 `6c37250...<本轮提交>`（3 文件）；累计范围 `d9d117c...<本轮提交>`，含中间的 `80fa4be`（Codex 流程文档，不归本卡）。不再把中间提交省略成错误父提交。
- **P1 header 配对**：`parseTableHeader` 先冻结 header kind，再要求精确 delimiter（table 恰好 `]`，array-table 恰好 `]]`）；`[[x]`、`[x]]`、`[]`、`[[]]`、`[[x]]]` 全部 `.unsupportedSyntax` 零写。
- **P1 namespace**：顶层 key/table path 首段为 `approval_policy` 时，唯一允许形态是顶层单行 scalar key；`approval_policy.foo`、`"approval_policy".foo`、`[approval_policy]`、`[approval_policy.granular]`、`[[approval_policy]]` 一律零写拒绝；`a.approval_policy` / `[a.approval_policy]` 为无冲突控制组。
- **P1 Unicode 游标**：`\u`/`\U` 分支先消费 marker 再读 4/8 hex 并验证 scalar；`"ne\u0076er"`、`"ne\U00000076er"` 正确解码为 `never`（同值零写 / 切换只换 value），非法 scalar、截断、非法 hex 零写。
- **P2 Hook 调用点**：`CodexHookHandler` 新增最小 `Dependencies` 注入（stdin/context/socket/日志/stderr/diagnostic/stdout/policySink），两个事件都经同一 `syncPolicy(switchState:)`；新增 6 个行为测试用 recording sink 真实驱动 `CodexSessionStart` 与 `CodexPermissionRequest`，断言 `[true, false]` 且参数来自观测状态，未观测时零调用。未新建浅层 scanner，也未扩展 audit 模块。
- **P3**：删除未使用的 `packageRoot`。
- **locator 结果**：改为 typed 四态 `.existingScalar` / `.absent` / `.duplicate` / `.unsupported(reason)`，调用方只做一次 replace/insert。
- **永久矩阵**：表驱动累计 **64 行** + 14 个测试（新增 header 配对 6 行、namespace 7 行、Unicode 6 行 + 5 个 Hook 行为测试）；failure 行断言原始 bytes 完全不变。
- **mutant（原子化 patch→run→restore+sha）**：6 组——header 第二个 `]` 可选 / dotted-key 首段检查回退 / table namespace 检查删除 / `\u`/`\U` 不越过 marker / PermissionRequest 硬编码状态 / SessionStart 丢弃状态；全部编译通过并各自点名永久测试变红，还原复核 sha `e52dd4d1…`、`9ef9369f…`。
- **门禁**：新类 14/14；Agent/Hook 定向 9 类 181/181；全量第 5 次 **1249 / 2 skipped / 0 failures**；双 Release rc=0；identity ok；工作区与全范围 `git diff --check` clean。
- **flake 披露**：全量前 4 次命中两项已登记 flake；第 4 次另现一次未登记的 `testV4MigrationAndConcurrentOutcomeShareOneWriteTransaction`（**单测隔离 8/8 通过**，属 Store 负载敏感族，与本卡模块无调用关系）。基线 `6c37250` 独立 worktree 全量 2/2 同样命中已登记两项。
- 真实 codex 0.154 隔离 smoke 通过；真实 `~/.codex/config.toml` 全程只读（sha 前后一致）。未安装/重签/重启/push；15L/R7 未触碰。证据 C5JR2-D 段。
- 需要回复：是（@Codex 复核 C5JR2-D：typed 四态 locator、header 精确配对、namespace inventory、Unicode 游标、Hook 事件 recording sink 行为门、64 行永久反例、6 组 mutant、定向/全量/Release/identity/diff-check）
