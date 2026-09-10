# 29 — C5GR1：失效结果、同步 start 与 trace 自洽性收口

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR1）
执行 owner：DSH；验收：Codex
基线：`d310f41`（C5G 提交）；本机起点 `db4eccd`
日期：2026-09-10

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Standards P1 | 失效 attempt 的结果仍覆盖 `lastOutcome`，并被 View 当作当前页结果展示 | 新增 `isProjectable`；`.superseded` / `.ignoredInFlight` **不写 `lastOutcome`**，View 对二者不更新 toast/status |
| Standards P2 | `.began` 同时记 `portCalled=true` 与 `category=portNotCalled`，自相矛盾 | `.began` 改为 `portCalled=false` + `category=.pending`；删除 `portNotCalled`，新增 `.pending` / `.superseded` / `.inFlightRejected` 与 phase `.rejected`；**新增合法组合矩阵测试**（正向枚举 + 反向拒绝） |
| Spec P1 | `submit` 用冻结 input 覆盖已观测的 live identity | `start` 不再调用 `observeCurrentIdentity`、不再写 `currentIdentity`；进 port 前校验 `currentIdentity == input.confirmationIdentity`，不匹配即 typed superseded 且 port=0 |
| Spec P1 | await 中 identity 变化后旧 accepted/requires/no-op/error 仍被记录与投影 | 新增 coordinator-owned `observationRevision`（仅 `observeIdentity` 递增），attempt 绑定提交时的 revision；await 后 revision 或 identity 任一不匹配即 `.superseded`：不 `applyCommitResult`、不写 `lastOutcome`、不更新 toast |
| Spec P1 | 现有 stale 测试固化了返回旧 `.requiresOverwriteConfirmation` | 重写为断言 `.superseded`；新增 accepted / failure / 前置不一致 / B→A 往返四个失效用例 |
| **任务卡原文（摘要未含）** | Button action 必须**同步**进入 coordinator，不得把 `submit` 放到 View 新建的 Task 后才开始 | 拆为同步 `start(_:port:)` + 内部 async `finish(...)`；`start` 在返回事件循环前完成 clickCount / in-flight / sequence / `isSubmitting=true` / `began` trace。View 不再先建 Task |
| **任务卡原文（摘要未含）** | View outcome 必须携带冻结 pageID，禁止 accepted 后读 live `currentPageID`/`currentPageChrome` | 新增 `AhaKeyStudioPageCommitProjection { pageID, outcome }`；View 的 accepted 分支只用 `projection.pageID`，静态门断言这一点 |

## 2. trace 语义（修复前后）

**修复前（自相矛盾，不能作 HIL oracle）**

| phase | portCalled | category |
|---|---|---|
| `.began` | `true` | `portNotCalled` |

**修复后（严格状态矩阵，每个 phase 内部自洽）**

| phase | portCalled | category | 含义 |
|---|---|---|---|
| `.began` | `false` | `.pending` | action 已同步进入 attempt，port 尚未调用 |
| `.returned` | `true` | `.accepted` / `.noOp` / `.requiresOverwriteConfirmation` / `.missingTrustedPageCache` / `.unsupportedProfile` / `.unsupportedPage` | port 已返回，结果被投影 |
| `.failed` | `true` | `.failed` | port 抛出，结果被投影 |
| `.superseded` | `false` | `.superseded` | 前置一致性失败，未进入 port |
| `.superseded` | `true` | `.superseded` | port 已调用，但 live context 在 await 中变化，结果被作废 |
| `.rejected` | `false` | `.inFlightRejected` | 已有在途 attempt，本次点击未进入 attempt |

矩阵由两个测试守住：`testTraceMatrixRejectsEveryCombinationProducedByKnownPaths`（正向：多路径产生的每个事件都必须在矩阵内）与 `testTraceMatrixRejectsIllegalCombinationsByConstruction`（反向：矩阵外组合确实被判非法，防止断言写成永真）。

新增可观测计数：`observationRevision`、`supersededCount`。

## 3. 两个结构性改动

### 3.1 live identity 的所有权

- **C5G**：`submit` 内部 `observeCurrentIdentity(identity)` 并 `currentIdentity = identity`，冻结输入反而压掉 View 的 live 观测。
- **C5GR1**：live identity **只**由 `observeIdentity`（View 驱动）维护。`start` 只做：
  1. 进 port 前校验 `currentIdentity == input.confirmationIdentity`；
  2. 记下 `revisionAtSubmit`，await 后核对 `observationRevision` 与 `currentIdentity`。
- View 在提交前以本次冻结的 identity 发布观测；`makeSubmissionInput()` 复用 `currentPageSnapshot`，使 `input.confirmationIdentity` 与页面展示所用的 `overwriteConfirmationIdentity` 由同一份快照 + 同一组 generation 派生。

### 3.2 同步 start（决定 trace 能否作为 oracle）

`start` 同步完成 attempt 建立与 `began` 落盘，再由 coordinator 内部启动 async port（`finish`）。因此：

- 「trace 无 `began`」严格等价于「Button action 未触发」——这正是 R5 定位停点 1 的判据；
- 同 tick 的第二次点击立即被 `.rejected / .inFlightRejected` 拒绝，port 调用数不变。

C5ER1 语义保持：ledger 的 `consumeMatchingAttempt` 仍以 `inFlight` + `revision` 判定；coordinator 层的额外校验不放松任何既有约束。

## 4. 测试

coordinator 专项由 11 项增至 **20 项**。新增/重写：

- `testStartIsSynchronousSoBeganAndSubmittingAreVisibleBeforePortReturns`：`start` 返回即 `isSubmitting=true`、`began(portCalled=false,.pending)`；同 tick 第二次 `.ignoredInFlight`；port 恰 1 次。
- `testSubmitBeforePortRejectsWhenFrozenIdentityDiffersFromLive`：live=A、frozen=B → `.superseded`、port=0、`lastOutcome` 仍 nil、`currentIdentity` 未被覆盖。
- `testStaleResultDuringAwaitIsSupersededAndNeverProjected` / `...StaleAccepted...` / `...StaleFailure...`：await 中 context 变化 + 旧 requires/accepted/error → 一律 `.superseded`，不投影、不弹错。
- `testStaleRoundTripBToADuringAwaitStillSupersedes`：A→B→A 往返后旧 accepted 仍失效（revision 已推进）。
- `testAcceptedProjectionCarriesFrozenPageIDNotLivePage`：投影携带冻结 pageID。
- `testProjectableOutcomeStillUpdatesLastOutcome`：有效结果照常投影（防止修复过度为"永不投影"）。
- `testTraceMatrixRejects*`：trace 合法组合矩阵的正反两向。
- `testPortNotCalledGuard...`：改断言 `.rejected` / `.inFlightRejected` / `portCalled=false` / 不可投影。
- `testR4Replay...`：精确 trace 更新为 `.began(portCalled=false,.pending)`，并断言所有 `.began` 不得声称 port 已调用。
- 静态接口门新增：View 必须用 `pageCommitCoordinator.start(`、不得出现 `pageCommitCoordinator.submit(`、结果投影必须用 `AhaKeyStudioPageChromeProjector.pageTitle(projection.pageID)`。

## 5. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **208 / 208，0 失败** |
| coordinator 专项 | **20 / 20，0 失败** |
| 全量 Swift | **1171 tests / 2 skipped / 0 failures**（首次即通过） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR1 改动范围 `git diff --check` | 通过 |

本轮不需 flake 归因：全量首次即 0 失败。

## 6. 已冻结项未被破坏

单次 frozen input（且与展示 identity 同源）；coordinator 内聚双 ledger；View 无直接 ledger / Store bypass（静态门）；recording 与 production port 并存；trace 非敏感且有界（环形 64）。此外真实 mapping → Facade 的 active-only 用例（`testExplicitActiveSetUnknownBaselineTwoClickCommitGoesThroughFacade`）已改为经 coordinator 走通。

## 7. 本轮仍不能证明的事

`superseded` 语义、同步 `start` 时序与 trace 矩阵自洽性是 **host 可判定**的；但 R4 的 HIL 症状属于哪一类停点，仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变：host 全绿不等于 HIL 症状已修复。

## 8. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`（测试改为经同步 `start`）
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
