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
