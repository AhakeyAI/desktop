# 15K-J evidence：Codex 审批策略兼容（`approval_policy` 只允许 `on-request` / `never`）

- 任务卡：`docs/collab/taskcards/V03-CODEX-APPROVAL-POLICY-COMPATIBILITY.md`
- 基线：`5963fcda20727c50d2d3fb2903b113061e4dfd51`（C5IR8 accepted 后冻结 HEAD）
- 范围：单一生产文件 `Sources/Agent/CodexConfigLeverSync.swift` + 新增专用测试；`CodexHookHandler.swift` **未改**（两个调用点原样经 seam）；`Package.swift` 未改（测试 target 已含 `AhaKeyConfigAgent`）

## 1. 当前 Codex 版本与现场事实

- 本机 `/Applications/ChatGPT.app/Contents/Resources/codex`：`codex-cli 0.154.0-alpha.6.2`（`--version` 实测）。
- 真实 `~/.codex/config.toml` 全程只读观测：smoke 前/后 sha256 均为 `f1b3d0fc1bfba73d61b004b89b8fdeaf45e4921b5567043204e857df50081fd6`（7048 字节）。
- 未安装、未重签、未重启 Runtime、未 push、未触碰已安装 app 二进制与两份现场备份。

## 2. 冻结语义与 typed seam

`CodexConfigLeverSync` 现为深模块：唯一写路径 `apply(policy:configURL:)` 的入参是 typed
`ApprovalPolicy`（`onRequest = "on-request"` / `never = "never"`），因此**类型上不可能**写出 allowlist
之外的取值。`untrusted` 既不是 enum case，`ApprovalPolicy(rawValue: "untrusted") == nil`。

| 拨杆 | policy | 写入行 |
|---|---|---|
| 自动档 | `.never` | `approval_policy = "never"` |
| 手动档 | `.onRequest` | `approval_policy = "on-request"` |

两个生产调用点（`CodexHookHandler.swift:30` `CodexSessionStart`、`:55` `CodexPermissionRequest`）继续调用
既有 `apply(switchStateAuto:)`，由它内部做 `forLever` 映射；调用点零改动。

## 3. 红能力回归环

### 3.1 真实 codex 0.154 隔离解析 smoke（`CODEX_HOME` 指向临时目录）

| # | 隔离 fixture | 命令 | 实测输出 | rc |
|---|---|---|---|---|
| A | `approval_policy = "on-request"` | `CODEX_HOME=$A codex login status` | `Not logged in`（无 config 错误） | 1（仅未登录） |
| B | `approval_policy = "untrusted"` | `CODEX_HOME=$B codex login status` | `Error loading configuration: approval_policy = "untrusted" is no longer supported; remove this setting` | 1 |
| C | `approval_policy = "never"` | `CODEX_HOME=$C codex login status` | `Not logged in` | 1 |

A/C 的两个字面量与 `ApprovalPolicy.onRequest.configLine` / `.never.configLine` 逐字符相同（测试内断言），
B 是旧映射曾写出的值——真机复现了「客户端启动即退出」的根因，且**未触碰真实 home**。

### 3.2 旧映射的确定性反证（app 内测试 + mutant）

- `testLegacyUntrustedMappingFailsTheFrozenAllowlist` 在树内保留旧映射的忠实副本
  （`switchStateAuto ? "never" : "untrusted"`）并断言其手动档取值被冻结 allowlist 拒绝。
- mutant（原子化 `patch → run → restore + sha`）：

| 补丁 | 结果 |
|---|---|
| M1：还原 C5IR8 前的字面映射（手动档 → `untrusted`，绕开 typed policy） | **6 个永久测试红**：迁移(手动)、合法值幂等、两态切换、缺键插入、内容保留、产品树 `untrusted` 扫描 |
| M2：调用点绕过 typed seam（新增 untyped 写入口，`CodexSessionStart` 直用） | **2 个永久测试红**：两个调用点 seam 断言、产品树 `untrusted` 扫描 |

两次 mutant 后均从备份还原并复核 sha256：`CodexConfigLeverSync.swift` = `d39bc744…`、
`CodexHookHandler.swift` = `7370587f…`（与 clean 拷贝逐字节一致）。

## 4. 文件语义矩阵（全部 fixture 在临时目录）

| 场景 | 期望 | 结果 |
|---|---|---|
| 已有 `untrusted`，手动档 | 就地替换为 `on-request`，其余字节不变 | `.replaced` ✓ |
| 已有 `untrusted`，自动档 | 就地替换为 `never` | `.replaced` ✓ |
| 已是目标值 | 幂等早退、**零字节变化** | `.alreadyDesired` ✓ |
| 合法值反向切换 | 精确替换目标行 | `.replaced` ✓ |
| 缺键且有 section | 插入到首个 `[section]` 之前 | `.inserted` ✓ |
| 缺键且无 section | 追加到末尾 | `.inserted` ✓ |
| 注释/空行/键序/sections/尾换行 | 除目标行外逐字节保留 | ✓ |
| 文件不存在 | 不创建、不改 | `.missingConfig` ✓ |
| 非 UTF-8 | 原字节保留 | `.unreadableConfig` ✓ |
| 目录不可写（原子写失败） | typed `.writeFailed`，原内容不变 | ✓ |

fail-safe 语义由 typed `Outcome` 显式表达（不再只有 `try?` 静默）。

## 5. 调用点与产品树结构断言

- `testBothProductionCallsitesRouteThroughTypedSeam`：`Sources/Agent/CodexHookHandler.swift` 中
  `CodexConfigLeverSync.apply(` 恰 2 处且都带 `switchStateAuto:`；注释剥离后无 `untrusted`。
- `testProductSourcesHaveNoUntrustedApprovalPolicyWritePath`：枚举 `Sources/**/*.swift`，注释剥离后
  不得出现 `untrusted`（含 `"untrusted"` 字面量）；除 `CodexConfigLeverSync.swift` 外不得出现
  `approval_policy`。注释里保留历史取值说明是允许的（卡面明确）。

## 6. 兼容与文案

- 产品可执行代码零 `untrusted`：见 §5 产品树扫描；类型层面由 `ApprovalPolicy` 收口。
- UI/localization **零改**：审计 `Sources/**` 与 `Resources/{zh-Hans,en}.lproj/Localizable.strings`，
  无「手动档每条必问 / 每次确认」类描述；既有 `Claude / Cursor / Codex：按各自确认链。`
  与卡面「当前已知无需改」一致。
- 隔离 `CODEX_HOME` parse smoke 已执行（§3.1），未使用真实 home。

## 7. 门禁

| 项 | 结果 |
|---|---|
| 新增专用测试 `CodexConfigLeverSyncTests` | **16 / 16，0 失败** |
| Agent/Hook 定向 9 类（含 endpoint、hook server、hook trust、state plan、watchdog） | **183 / 183，0 失败** |
| 全量 `swift test` | 第 6 次 **1251 tests / 2 skipped / 0 failures（rc=0）**（本轮共 6 次；前 5 次各命中已登记 flake，见 §8） |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| `git diff --check HEAD -- ahakeyconfig-mac`（工作区） | clean |
| `git diff --check 5d1fe1d`（全仓历史范围，含工作区） | **clean**（本轮顺带清除本卡头部 4 行 Markdown 行尾空格，该红点此前为 `af48d21` 引入） |

## 8. 已登记 flake 归属（诚实披露，非本卡引入）

| flake | 本轮隔离/全量观测 | 历史登记 |
|---|---|---|
| `AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` | 单测隔离 8 次 = 5 pass / 3 fail（C5IR8 轮实测）；本轮全量命中 3 次 | 是（C5IR8 前已登记） |
| `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode` | 单测隔离 5 次 = 5 pass；本轮全量命中 2 次（负载敏感） | 是 |

**基线对照（决定性）**：在 accepted HEAD `5963fcd` 的独立 `git worktree` 中跑全量 3 次，
**3/3 失败**且命中**同样这两项** flake（`1235 tests`，与本卡树 `1251` 的差即本卡新增 16 项）。
⇒ 全量 flake 与本卡改动无关，且非本卡引入。worktree 已 `git worktree remove --force` 清理。

## 9. 未执行项

- Codex 0.154 的**交互式**审批行为（弹窗时机）未在真机驱动：需要真实登录态与交互会话，
  与「config 是否能被 0.154 解析」是两个问题；本卡只冻结可写取值集合与解析通过性。
- 未安装 / 未重签 / 未重启 Runtime / 未 push / 未动已安装 app 与现场备份；
  真实 `~/.codex/config.toml` 全程只读（sha256 前后一致）。

---

# C5JR1（返工）：byte-preserving TOML locator + 访问控制结构门

- 返工基线：`d9d117c5990428a9db68d31ded6d8a010847be3d`（C5J 首次提交）
- 退审范围：`5963fcd...d9d117c`；Standards 1 项 + Spec 4 项 blocking，全部在本轮闭合
- 白名单：仅 `Sources/Agent/CodexConfigLeverSync.swift`、`Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`、本 evidence、本卡

## R1. 逐条闭合

| 退审 finding | 处置 |
|---|---|
| **Spec P1**：逐行 `hasPrefix("[")` 误判 section，多行字符串/跨行 array 内的 `[` 会把 policy 插进 value 内部 | 改为**单次 byte-preserving TOML locator**（`TomlPolicyLocator`）：只有「语句起始且不在任何 value 内部」的 `[` 才是 table header；多行 basic/literal string、跨行 array、inline table、注释全部被正确消费跳过 |
| **Spec P2**：`.newlines` 拆分 + `
` 拼回破坏 CRLF/CR | 不再拆分/重排：只对目标 value token 做 `replaceSubrange`，或在精确 byte offset `insert`；LF/CRLF/CR 与尾换行原样保留；插入时按文件检测到的换行风格 |
| **Spec P2**：同值幂等与行尾注释不成立 | 幂等改为**按 TOML 值**判定（解析 value token 的解码值）；切换时只替换字符串 value token，key 周边空白、`=` 两侧空格、引号风格以外的注释与其它字节不动 |
| **Spec P2**：调用点结构门可假绿（换行 callsite 绕过单行计数） | **删除该源码文本门**：raw-policy 写入口改为 `private static func apply(policy:configURL:)`，其它 Source 文件编译期不可调用；对外 seam 仅 `apply(switchStateAuto:)` 与 `apply(switchStateAuto:configURL:)`。不新增任何第二套扫描器 |
| **Standards**：测试又写了一套朴素 `strippingComments`，重开浅层扫描路径 | 已删除（连同产品树 `untrusted` 文本扫描、callsite 行计数测试）。测试只经 `switchStateAuto + fixture URL` seam 验证行为 |
| **文档口径**：不得声称 Codex 全局仅剩两个合法值 | 注释改为「**本产品只写** `on-request` / `never` 两个 scalar 值；官方 `approval_policy` 还支持 granular 形式与其它取值，本卡不写、也不代表全局合法集合」 |

## R2. 定位器语义（单一解析路径）

`TomlPolicyLocator.locate(bytes) -> Result<Selection, Failure>`：

- `Selection.existing(valueRange:value:)` —— 顶层 `approval_policy` 的单行 scalar string value token 字节范围 + 解码值；
- `Selection.absent(offset:prefix:suffix:)` —— 首个**真** table header 行首（无 table 则 EOF，按是否已有尾换行决定是否需要前导换行）；
- `Failure.duplicateKey` / `Failure.unsupported(reason:)` —— **零写 fail-closed**。

支持的语法：bare/quoted/dotted key、basic/literal 单行字符串（含 `\u`/`\U` 转义解码）、多行 basic/literal 字符串、跨行 array（含注释与尾逗号）、inline table、注释、LF/CRLF/CR。
不支持的输入（未闭合字符串/array/inline table/table header、非 scalar value、值后尾随内容、重复顶层 key）一律 typed fail-closed 且字节零变化。

## R3. 永久反例（表驱动，45 行 + 9 个测试）

`testPermanentFixtureRows` 每行断言 Outcome + **精确字节**（成功行）或**零字节变化**（fail-closed 行）：

- 换行保真：CRLF / CR / 无尾换行；CRLF 同值幂等；
- 幂等与形态：`approval_policy="never"` 无空格同值（`alreadyDesired`，零字节）、无空格切换、`'never'` literal 同值与切换、quoted key + tab + 混合空格；
- 行尾注释：同值零写、切换只换 value、CRLF 注释；
- 多行字符串：basic / literal 内含假 `[section]` 与假 `approval_policy`（真 key 只替换一次；只有假 key 时插入到真 table 前）；
- 跨行 array / inline table：内含 `[fake]`；inline table 内的 `approval_policy` 不算顶层 key；
- 缺键插入：首个真 table 前（LF/CRLF/CR）、`[[array of tables]]` 前、无 section 追加、无尾换行、空文件、纯注释、dotted key 不误判；
- 歧义/失败：重复顶层 key → `.duplicateKey`；table 内同名 key 不算重复；未闭合 basic/multiline/array/inline table/table header、非 scalar number/multiline/array、value 后尾随内容 → `.unsupportedSyntax` 且零写。

## R4. 反证（mutant，原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| M1 写回前按 `.newlines` 拆分再用 `\n` 拼回 | `testPermanentFixtureRows` 红（CRLF/CR 行） |
| M2 整行替换 value（丢注释、破坏非规范空格） | `testPermanentFixtureRows` + 幂等测试红 |
| M3 多行 basic string 只吃开头三引号（body 泄漏为代码） | 红（多行字符串假 `[section]` 行） |
| M4 取消重复 key 检测 | 红（重复 key 行） |
| M5 array 只吃开括号（元素泄漏为语句） | 红（跨行 array 行） |
| M6 缺键总是追加到 EOF（忽略首个真 table） | 红（插入位置行 + 幂等测试） |
| M7 单行字符串遇换行不判未闭合 | 红（未闭合值行） |

七个 mutant 全部编译通过且各自点名永久行变红；每次均从备份还原并复核 sha256 `201af18f3ca73b8d10bf86eaa330b1a2b211846916fb934525ad5709ca5bb6cd`（与 clean 拷贝逐字节一致）。

## R5. 真实 codex 0.154 隔离 smoke（`CODEX_HOME` 指向临时目录）

| # | 隔离 fixture | 实测输出 |
|---|---|---|
| D | 真实结构 config + `approval_policy = "on-request"` | `Not logged in`（无 config 错误），rc=1 |
| E | 真实结构 config + `approval_policy = "never"` | `Not logged in`，rc=1 |
| B | `approval_policy = "untrusted"`（负对照） | `Error loading configuration: approval_policy = "untrusted" is no longer supported; remove this setting` |

D/E 的两个字面量由单元测试断言等于 `ApprovalPolicy.onRequest.configLine` / `.never.configLine`。
真实 `~/.codex/config.toml` 全程只读：smoke 前后 sha256 均为 `f1b3d0fc1bfba73d61b004b89b8fdeaf45e4921b5567043204e857df50081fd6`。

## R6. C5JR1 门禁

| 项 | 结果 |
|---|---|
| 专用测试 `CodexConfigLeverSyncTests` | **9 / 9，0 失败**（含 45 行永久反例） |
| Agent/Hook 定向 9 类 | **176 / 176，0 失败** |
| 全量 `swift test` | 第 2 次 **1244 tests / 2 skipped / 0 failures（rc=0）**；第 1 次命中已登记 flake `testConcurrentAppliesFromTwoClientsSerializeAndDrain` |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| `git diff --check HEAD -- ahakeyconfig-mac`（工作区） | clean |
| `git diff --check 5d1fe1d`（全仓历史范围） | clean |

制品 sha256：`CodexConfigLeverSync.swift` = `201af18f3ca73b8d10bf86eaa330b1a2b211846916fb934525ad5709ca5bb6cd`；
`CodexConfigLeverSyncTests.swift` = `aca6d5e973a83e43e4d40b915bec4e485b39a7ac474c9ed53cd690c9340317ed`。

未安装/重签/重启 Runtime/push；未动已安装 app、现场备份与真实配置；15L/R7 未触碰。

---

# C5JR2-D（第二轮同轴返工）：typed locator 四态 + namespace inventory + Hook 事件行为门

- 返工基线：`6c37250`（C5JR1 提交）；产品增量范围 `6c37250...<本轮提交>`（3 文件：locator / hook handler / tests）
- 累计范围（含中间流程提交）：`d9d117c...<本轮提交>` = `80fa4be`（Codex 流程文档，不由本卡改动）+ `6c37250` + 本轮
- 白名单：`Sources/Agent/CodexConfigLeverSync.swift`、必要的 `Sources/Agent/CodexHookHandler.swift`（仅依赖注入）、`Tests/AhaKeyAgentTests/CodexConfigLeverSyncTests.swift`、本 evidence、本卡

## R1. 逐条闭合

| 退审 finding | 处置 |
|---|---|
| **P1 table header 配对**：`[[products]` 被当作已闭合 | `parseTableHeader` 先冻结 header kind（普通 table / array-of-tables），再要求**精确** delimiter：普通恰好 `]`，array-table 恰好 `]]`。`[[x]`、`[x]]`、`[]`、`[[]]`、`[[x]]]` 全部 `.unsupportedSyntax`、零写 |
| **P1 namespace 冲突**：`approval_policy.foo`、`[approval_policy]`、`[approval_policy.granular]` 被当作缺键并插入竞争 scalar | 顶层 key path / table path 的**首段**为 `approval_policy` 时：唯一允许形态是顶层单行 scalar key 本身；dotted key 与任何 table header 一律 `.unsupportedSyntax`、零写。控制组 `a.approval_policy`、`[a.approval_policy]` 仍是普通输入，可正常插入 |
| **P1 Unicode escape 游标**：`\u`/`\U` 未越过 marker | 进入分支后先 `index += 1` 消费 `u`/`U`，再读 4/8 位 hex 并验证 Unicode scalar；`"ne\u0076er"`/`"ne\U00000076er"` 正确解码为 `never`（同值幂等零写、切换只换 value），非法 scalar / 截断 / 非法 hex 仍零写拒绝 |
| **P2 两个 Hook 调用点保证消失** | `CodexHookHandler` 新增最小 `Dependencies` 注入（readStdin / parseContext / sendRequest / appendHookLog / emitPermissionStderr / appendDiagnostic / writeStdout / policySink），两个事件都经**同一个** `syncPolicy(switchState:)` → `policySink`。测试用 recording sink 真实驱动 `handleState(4)`（CodexSessionStart）与 `handlePermissionRequest()`（CodexPermissionRequest），断言 `[true, false]` 且参数由观测到的拨杆状态推导；未观测到状态时不调用。未新增任何浅层扫描器，也未扩展 audit 模块 |
| **P3 遗留 helper** | 删除 `CodexConfigLeverSyncTests.packageRoot` |
| **提审范围申报** | 本轮起产品增量与累计范围分别报告，且显式列出中间的 `80fa4be`（Codex 流程文档，不归本卡） |

## R2. locator 结果（单一事实，调用方只做一次写）

`TomlPolicyLocator.locate(bytes) -> Location`：

- `.existingScalar(range, decoded)` —— 顶层单行 scalar value token + 解码值；
- `.absent(insertionOffset, before, after)` —— 首个真 table header 行首（或 EOF，含换行风格）；
- `.duplicate` —— 顶层重复 scalar；
- `.unsupported(reason)` —— 其余一切（畸形容错之外）**零写**。

`apply` 只按四态分支一次 `replaceSubrange` / `insert`，不再自行推断 TOML。

## R3. 永久矩阵增量（累计 64 行 + 14 个测试）

新增 19 行：

- header 配对：`[[products]`、`[x]]`、`[]`、`[[]]`、`[[x]]]` 全部 fail-closed 零写；`[projects."/x"]` 正例仍可插入；
- namespace：`approval_policy.foo`、`"approval_policy".foo`、`[approval_policy]`、`[approval_policy.granular]`、`[[approval_policy]]`、dotted+scalar 同文件 全部 fail-closed 零写；控制组 `a.approval_policy`（既有行）与 `[a.approval_policy]` 正例插入；
- Unicode：`\u0076` / `\U00000076` 同值零写与切换只换 value；非法 scalar（`\uD800`）、截断（`\u00`）、非法 hex（`\uZZZZ`）零写拒绝；
- Hook 事件（新增 6 个行为测试）：SessionStart 正例 / SessionStart 非 4 值否定 / PermissionRequest 正例 / 两事件同 seam `[true, false]` / 未观测状态零调用。

## R4. 反证（mutant，原子化 patch→run→restore+sha）

| 补丁 | 结果 |
|---|---|
| M1 header 第二个 `]` 改回可选（`[[x]` 被接受） | `testPermanentFixtureRows` 红 |
| M2a dotted-key 首段检查改回精确匹配 | 红 |
| M2b table header namespace 检查删除 | 红 |
| M3 `\u`/`\U` 不越过 marker | 红 |
| M4a `CodexPermissionRequest` 忽略观测状态（硬编码 0） | 3 个 Hook 测试红 |
| M4b `CodexSessionStart` 丢弃观测状态（传 nil） | 2 个 Hook 测试红 |

六个 mutant 全部编译通过、各自点名永久测试变红；每次从备份还原并复核 sha256
（locator `e52dd4d121e2aff89d2da5bc588fb199d08ab56b4b92294de00a2cf07026bbd7`、
handler `9ef9369f086e657b00849a5791b5a8958d15156698401c706158d737ee84fe44`）。

## R5. 真实 codex 0.154 隔离 smoke

| # | 隔离 fixture | 实测 |
|---|---|---|
| A | 真实结构 config + `approval_policy = "on-request"` | `Not logged in`，无 config 错误 |
| B | `approval_policy = "untrusted"`（负对照） | `Error loading configuration: … no longer supported` |
| C | 无 policy 的真实结构 config（插入位形态） | `Not logged in` |

真实 `~/.codex/config.toml` sha256 前后一致（`f1b3d0fc…`）。

## R6. 门禁

| 项 | 结果 |
|---|---|
| `CodexConfigLeverSyncTests` | **14 / 14，0 失败**（含 64 行永久 fixture） |
| Agent/Hook 定向 9 类（Hook handler 改动后） | **181 / 181，0 失败** |
| 全量 `swift test` | 第 5 次 **1249 tests / 2 skipped / 0 failures（rc=0）** |
| `swift build -c release --product AhaKeyConfig` / `ahakeyconfig-agent` | rc=0 / rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| `git diff --check HEAD -- ahakeyconfig-mac`（工作区） | clean |
| `git diff --check 5d1fe1d`（全仓历史范围） | clean |

### flake 归属（诚实披露）

- 全量前 4 次命中已登记 flake：`testConcurrentAppliesFromTwoClientsSerializeAndDrain`、
  `testRootDeleteRecreateDoesNotLockStaleInode`；第 4 次另现一次**未登记**的
  `testV4MigrationAndConcurrentOutcomeShareOneWriteTransaction`（caught persistence error）。
- 该未登记项**单测隔离 8 次 = 8/8 通过**；它属 `AhaKeyRuntimePersistentStore`，与本卡模块无调用关系，
  形态与已登记的 store inode 负载敏感族一致。
- **基线对照**：冻结基线 `6c37250` 独立 worktree 全量 2 次 = 2/2 失败，命中同样两项已登记 flake
  （`1244` vs 本树 `1249`，差即本卡新增 5 个测试）。worktree 已清理。

制品 sha256：`CodexConfigLeverSync.swift` = `e52dd4d1…`、`CodexHookHandler.swift` = `9ef9369f…`、
`CodexConfigLeverSyncTests.swift` = `d6cb1145…`。

未安装/重签/重启 Runtime/push；未动已安装 app、现场备份与真实配置；15L/R7 未触碰。
