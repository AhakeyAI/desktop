# 36 — C5GR8：移除 init-time attach，never-appeared owner 不再泄漏

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR8）
执行 owner：DSH；验收：Codex
基线：`0abb9ed`（C5GR7 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Spec P1 | `init` 自动 attach 会遗留临时 owner：对象构造后若从未进入 View `onAppear`/`onDisappear`，capability 会永久留在 app-lifetime registry 的 `attached`、`observations` 与 weak-nil `observers` 里 | 删除 `init` 中的 `_ = attach()`。生产 attach 只发生在 View `onAppear`（C5GR6 已改为先 attach 再 observe）；测试构造者显式 `attach()` |

按卡片「C5GR8 只需」四项执行，未做额外改动（未加防御性 prune 等）：

1. 删除 init-time attach ✅
2. 保持 View `onAppear` 先 attach、再 observe ✅（C5GR6 已建立，本轮无需改动 View）
3. transient create/drop 后 owner / observation 为 0 ✅
4. start-before-attach 零 port、attach 后正常提交 ✅

## 2. 生命周期契约（本轮后）

| 路径 | attached | observations | observers |
|---|---|---|---|
| 构造（无 attach） | 不变 | 不变 | 不变 |
| `attach()`（View onAppear） | +1 | +1 | +1 |
| `observeIdentity`（未 attach） | 拒绝、不写入 | — | — |
| `start`（未 attach） | — | 拒绝、零 port | — |
| `detach()`（View onDisappear） | −1 | 无租约即回收 | −1 |
| `detach()`（持有租约） | −1 | 保留至结算，由 `release` 回收 | −1 |

因此「构造后未出现」与「出现后离开」两条路径都不会残留。

## 3. 测试

coordinator 专项由 48 项增至 **52 项**。本轮新增：

- `testTransientCoordinatorWithoutAttachLeavesNoMembership`：构造后不 attach，`observeIdentity` 被拒（`currentIdentity == nil`）；对象出作用域后 `attachedOwnerCount == 0`、`attachedObservationCount == 0`、`lease == nil`。
- `testAttachThenDetachLeavesNoMembership`：attach→observe→detach 往返后两个计数归零。
- `testStartBeforeAttachCallsNoPortAndSucceedsAfterAttach`：未 attach 时 `start` → `.rejected(.ignoredInFlight)`、`port.snapshots.count == 0`、`portCallCount == 0`、`lease == nil`；随后按 View onAppear 的顺序 `attach()` → `observeIdentity` → `start` → `.started`，port 恰调用一次。
- `testViewOnAppearAttachesBeforeObservingIdentity`（卡片要求的 **View 生命周期静态门**）：从 View 源码截取 `.onAppear {` 之后的窗口，断言 `pageCommitCoordinator.attach()` 的位置严格早于 `pageCommitCoordinator.observeIdentity(`。

已有测试的构造点：`makeCoordinator()` 与新增 `makeAttachedCoordinator(_:)` 显式 attach；两处**故意**不 attach 的用例（`testDisconnectShutsDownCommitRegistry`、`testTerminationFenceRunsSynchronouslyBeforeReturn`）保持不 attach，用来断言关闭后 attach 失败——这是它们的测试意图。

## 4. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **244 / 244，0 失败** |
| coordinator 专项 | **52 / 52，0 失败** |
| **全量 Swift（最终树第 3 次）** | **1207 tests / 2 skipped / 0 failures** ← 完整全绿 |
| 全量 Swift（最终树第 1、2 次） | 分别 2 / 1 个失败，仅命中已登记 flake |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR8 改动范围 `git diff --check` | 通过 |

全量明细：

| 次数 | 失败 |
|---|---|
| 加静态门之前的第 1 次 | `AhaKeyAgentByteProgressTests.testProductionAckChainAdvancesSnapshotAndEventsAndSurvivesResnapshot` + `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode` |
| 加静态门之前的第 2 次 | 上述两者 + `AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` |
| 加静态门之前的第 3 次 | **无（0 failures）** |
| 最终树第 1 次 | 上述前两者 |
| 最终树第 2 次 | `AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` |
| **最终树第 3 次** | **无（0 failures）** |

（最终树 = 含本轮全部改动与新增测试；加静态门后重跑全量以确保绿run落在最终树上。）

本轮**未修改** Agent/Store 任何文件，也没有自行豁免门禁。

## 5. 已冻结项未被破坏

同步 termination fence、三类 settlement 回收、attached membership、per-owner stale fence、foreign isolation、全局单 lease、occupancy fan-out、onAppear reattach、one-way closed、owner-only cancel、origin callback、幂等取消、typed returned、双次 pre-port fence、per-attempt record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。

## 6. 本轮仍不能证明的事

membership 生命周期是 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 7. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（删除 init attach + 文档说明）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`（构造点显式 attach）
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

View 本轮**零改动**（onAppear 的 attach 顺序在 C5GR6 已建立）。

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、PersistentStore、ReleaseIdentity、安装器、固件；
未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。
提交不含 `board.md`/`queue.md` 的既有他人 diff。
