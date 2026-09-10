# 28 — C5G：两击提交收敛到单一可观测编排

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5G）
执行 owner：DSH；验收：Codex
基线：`f2b462236ed357d6889228b01c5982c182f5eb2e`
日期：2026-09-10

## 1. 本轮要解决的问题

R4（clean `f2b4622`）第二次覆盖仍零 WAL、零 `0x97`。Codex 判定现有证据**无法区分**三种停点：

1. 第二次 AXPress 没有进入 Button action；
2. action 进入，但重算 identity/snapshot 后再次 `.requires`/no-op；
3. action 进入 Facade 前被 View 本地状态挡住。

C5F 的 host 绿测是**手工依次调用**两个 ledger、Store/Facade 并手工分发 result，从未经过 SwiftUI Button 的真实编排；因此"绿测通过"不能推出"产品路径正常"。

## 2. 关键现场发现（新增，非推测）

**`projectAssembly(.requiresOverwriteConfirmation)` 本身就把 chrome 投影为 `commitKind = .overwritePage`**（`AhaKeyStudioPageModel.swift:759-772`），即按钮标题「覆盖写入此页」在**没有任何 pending** 时就已经是这个文案。

推论：R3/R4 记录里「按钮保持覆盖写入此页」**不能**作为「pending 已被设置」的证据。这与 Cursor 交接文档 §2.2 的观察一致（"底部已是「覆盖写入此页」…那只说明 assembler 认为需要覆盖"）。本轮 trace 正是为补上这个盲区。

## 3. 实现

新增 `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`：

- `AhaKeyStudioPageSubmissionInput`：一次点击冻结的 typed 值（deviceID + session/transport generation + page/profile + selected set + fields/baselines + explicit intent + retryResidual）。`confirmationIdentity` 与两个 snapshot（pending / confirmed）都由这**同一份值**派生。
- `AhaKeyStudioPageCommitPort`：提交端口协议。生产 adapter `AhaKeyStudioRuntimeStoreCommitPort` 唯一副作用是 `AhaKeyStudioRuntimeClient.commitFrozenPage`。
- `AhaKeyStudioPageCommitCoordinator`（`@MainActor`，`ObservableObject`）：内部持有两个 ledger、exact current identity、单次 in-flight attempt、pending prompt、chrome 投影与一次性 begin/result/failure fan-out。
- typed trace：`pageID / attempt 序号 / confirmed / portCalled / result-or-error 类别 / phase`，**不含**资源字节、文件路径、用户文本或 secret。环形缓冲 64 条，并写 Studio 现有 comm log。
- `AhaKeyStudioPageCommitOutcome`：`.noOp / .requiresOverwriteConfirmation / .missingTrustedPageCache / .unsupportedProfile / .unsupportedPage / .accepted / .failed / .ignoredInFlight`，每个分支在 UI 文案与 trace 中可区分。

View 改造（`AhaKeyStudioView.swift`）：

- 删除 `@State` 的两个 ledger 与 `isSubmittingCurrentPage`；改为 `@StateObject pageCommitCoordinator`，提交中状态由 coordinator 投影。
- 按钮 action 只调 `writeCurrentPage` → `makeSubmissionInput()`（**每次点击仅一次冻结**）→ `coordinator.submit(input, port:)`。
- **await 之后不再重算 `overwriteConfirmationIdentity`**；result consumption 一律使用冻结输入的 identity。C5ER1 的 stale 语义仍由 `observeIdentity` 推进 revision + 作废 in-flight 保证。

## 4. 这个改动让三种停点在下次 HIL 中可区分

| 现象 | 结论 |
|---|---|
| trace 无新 `began` | 第二击未进入 Button action（停点 1） |
| trace 有 `began confirmed=false` | action 进入，但 overwrite decision 仍非 confirmed（停点 2） |
| trace 有 `began confirmed=true` 且 `port=true`，但 `result=requires/noOp` | 冻结输入正确、调用到达 port，停点在 Facade/产品语义层 |
| trace 有 `began confirmed=true`、`port=true`、`result=accepted`，但设备无 `0x97` | 停点在 port 之后（Runtime/设备层） |

## 5. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类，含新增 coordinator） | **199 / 199，0 失败** |
| coordinator 专项（本轮新增） | **11 / 11，0 失败** |
| 全量 Swift（第 1 次） | 1162 tests / 2 skipped / **2 failures**，均与本轮无关（见下） |
| 全量 Swift（第 2 次） | **1162 tests / 2 skipped / 0 failures** |
| App Release（`--product AhaKeyConfig`） | rc=0 |
| Agent Release（`--product ahakeyconfig-agent`） | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| `git diff --check`（本轮改动范围） | 通过 |

### 全量套件里两个 flake（如实记录，非本轮引入）

第 1 次全量出现 2 个失败，两者都与本轮改动零文件交集：

- `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode`：实得 `TIMEOUT`，期望 `BLOCKED`（8.181s）。**这是既有已知稳定性问题**，Codex 在 C4R13/C4R14 的调度文本中已点名（"修复定向 full-suite 下 `testRootDeleteRecreateDoesNotLockStaleInode` 返回 TIMEOUT 的稳定性问题"）。
- `RuntimeXPCServerTests.AhaKeyRuntimeXPCLibXPCClientTests.testConcurrentEncodeAndExchangeStress`：`peerError("busy")`（0.175s）。

**隔离复跑两者均通过**（0.249s / 0.194s）；第 2 次全量为 0 失败。判定为 full-suite 并发下的既有 flake，不声称由本轮修复或引入。

## 6. 本轮证据能证明什么 / 不能证明什么

**能证明**：

- 每次点击只冻结一次；identity、overwrite decision、attempt token、Facade snapshot、result consumption 全部来自同一份冻结输入（`testR4Replay...`）。
- 第二次 exact 点击产生新的单次 attempt、`overwriteConfirmed=true`、port 恰调用 2 次（总）/ 1 次（第二击）。
- 第二次返回 `.noOp` / 再次 `.requires` / throw 三种结果在 outcome 与 trace 中互相可区分，且不再可能"静默保留上一条 toast"。
- device/session/transport/profile/selected-set 任一 mutation 均作废 pending；A→B→A 不复活旧 attempt。
- await 期间的 stale result 不被消费；await 期间登记的新 edit intent 不被旧 result 清除（C5ER1 语义未回退）。
- 真实 mapping + coordinator + 真实 Store/Facade：第二次 apply=1、ingest=0、fieldMask 仅 `screenActiveSet:0`。
- 静态接口门：View 不再持有或分发两个 ledger，按钮只经 coordinator 单一 submit 接口，且不绕过 coordinator 直调 Store 写入口。

**不能证明**（按本卡第 50 行如实报告）：

- **本轮 host 全绿不等于 R4 的 HIL 症状已修复。** coordinator 测试是用 recording port 重放的确定性编排，它证明的是「编排本身正确且可观测」，不是「正式 Studio 的第二次 SwiftUI 点击一定到达 action」。
- 三种停点中真实的是哪一种，仍**必须由下一次 HIL 的 trace 判定**。本轮没有、也不能在 host 上重现"零 port call"。

因此下一步不是继续加 host 测试，而是：**C5G accepted 后另请 `USER-GATE-...-R5`，用 trace 定位停点。** 若 R5 中 trace 显示第二击根本没进入 action，则应判定为 AX/UI 激活问题，另给可自动运行的 macOS UI smoke seam。

## 7. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（新增）
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`（新增）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`（C5F 的 Facade 测试改为经 coordinator）
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler 决策、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。

提交纪律：`board.md` 与 `queue.md` 的工作区 diff 含 Codex/Zcode/Cursor 的既有条目（board 未提交 diff 约 1292 行插入），**本轮提交不吞入它们**，沿用 `f2b4622`/`adfe2a6` 的惯例（历轮提交仅含产品+测试+evidence+当轮任务卡）。board 的本轮 ACK 与提审条目保留为工作区 append-only 记录。
