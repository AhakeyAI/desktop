# 35 — C5GR7：同步退出 fence 与 detached observation 结算回收

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR7）
执行 owner：DSH；验收：Codex
基线：`bcc7d9e`（C5GR6 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Standards P1 | 全量门禁未满足（DSH 四轮红，Codex 独立复跑 1198/1 failure 命中既有 concurrent-apply flake）；隔离复跑不能替代任务卡规定的全量绿 | 本轮取得 **一轮完整全绿：1203 / 2 skipped / 0 failures**（见 §4）。未越界修改 Agent/Store 任何文件 |
| Standards P2 / Spec P2 | `detach` 为持有 lease 的 owner 保留 observation 是正确的，但 `release` 清除 lease 后没有在 owner 已不 attached 时移除 observation；normal / cancelled / superseded 三种结算都会留下记录 | `release(_:)` 统一在释放租约后判断「owner 是否仍 attached」，不 attached 即移除其 observation。三条结算路径都经 `release`，因此不再残留 |
| Spec P1 | 正常退出路径没有同步保证 terminal fence 执行：`applicationWillTerminate` 只排入一个未等待的 MainActor Task，回调随即返回，进程可能在 `disconnect`/`shutdown` 获得调度前结束 | 新增 `AhaKeyStudioRuntimeClient.fencePageCommitExecutions()`（同步）与可测 seam `AhaKeyAppTerminationFence.fence(store:)`；`applicationWillTerminate` 在**返回前同步**调用它，之后才排入原有的异步 `disconnect()` best-effort |

## 2. 退出 fence 的同步性

```text
applicationWillTerminate（MainActor，NSApplicationDelegate 已隔离）
  ├─ PowerProtectionManager.deactivateAll()
  ├─ AhaKeyAppTerminationFence.fence(store:)   ← 同步完成 registry terminal shutdown
  └─ Task { disconnect() }                      ← 仍是 best-effort 异步（facade.stop 等）
```

关键点：terminal fence（`registry.shutdown()`）本身是同步的，此前被无谓地放进了未等待的 Task。
`Task` 只用于确实需要 await 的 `facade.stop()`；fence 不再依赖事件循环调度。

seam 抽成独立 `@MainActor enum AhaKeyAppTerminationFence`，因此测试可以直接断言
「调用返回时已 closed」，而不需要 yield —— 这正是原缺陷无法被测出的原因。

## 3. observation 回收语义

| 时点 | owner 状态 | observation |
|---|---|---|
| `detach`（无在途租约） | — | 立即回收 |
| `detach`（持有在途租约） | detached | 保留到结算（否则 inherited fence 失效） |
| `release`（normal / cancelled / superseded） | 仍 attached | 保留（它还要继续观察） |
| `release`（三条路径） | 已 detached | **回收**（本轮修复） |

## 4. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **240 / 240，0 失败** |
| coordinator 专项 | **48 / 48，0 失败** |
| **全量 Swift（第 1 次）** | **1203 tests / 2 skipped / 0 failures** ← 任务卡要求的完整全绿 |
| 全量 Swift（第 2、3 次） | 各 2 个失败，仅命中已登记 flake（`AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` + `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode`） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR7 改动范围 `git diff --check` | 通过 |

全量口径说明：按 Codex 裁决，本轮**未**修改 Agent/Store 任何文件；第 1 次即取得完整全绿，
后续两次只命中已登记 flake，与该裁决描述的「若继续只命中已登记 flake，由 Codex 另开稳定性卡」
一致。DSH 不自行豁免，也不声称修复了 flake。

## 5. 测试

coordinator 专项由 44 项增至 **48 项**；交互测试 +1。本轮新增：

- `testTerminationFenceRunsSynchronouslyBeforeReturn`（交互测试）：调用 seam 后**无任何 await/yield** 即断言 `isClosed == true`、`lease == nil`，且新 coordinator 无法 attach。
- `testDetachedOwnerObservationReclaimedAfterNormalSettlement`
- `testDetachedOwnerObservationReclaimedAfterCancelSettlement`
- `testDetachedOwnerObservationReclaimedAfterSupersededSettlement`（并断言 `supersededCount == 1`）
- `testAttachedOwnerObservationSurvivesSettlement`（防止修复过度为「结算即回收」）

## 6. 已冻结项未被破坏

attached membership、per-owner stale fence、foreign isolation、全局单 lease、occupancy fan-out、onAppear reattach、one-way registry closed、owner-only cancel、origin callback、幂等取消、typed returned、app-lifetime 非 static 单租约、双次 pre-port fence、per-attempt record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。

## 7. 本轮仍不能证明的事

退出 fence 同步性与 observation 回收均为 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 8. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（`release` 回收 detached observation）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`（新增同步 `fencePageCommitExecutions()`）
- `ahakeyconfig-mac/Sources/AhaKeyConfigApp.swift`（退出回调同步 fence + 可测 seam；findings 直接点名该文件 162–169 行）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；
**未修改 `AhaKeyAgentTests` / `AhaKeyRuntimePersistentStoreTests` 及其被测代码**。
未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。
提交不含 `board.md`/`queue.md` 的既有他人 diff。
