# 34 — C5GR6：attach 可重入、多 owner membership 与终态关闭

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR6）
执行 owner：DSH；验收：Codex
基线：`313896b`（C5GR5 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Standards P1 / Spec P1 | detach 后没有 re-activate；保留的 `@StateObject` 再次出现后无法提交（disappear→appear 后 capability 永久失效） | `attach(capability:delegate:)` 改为**幂等**并可重复调用；View `onAppear` 先 `attach()` 再 `observe`；coordinator 暴露 `isAttached` |
| Standards P1 / Spec P1 | 单一 `activeCapability` 使窗口 B 出现后窗口 A 无法推进自己的 stale fence，旧结果可能被错误投影 | 以 **attached membership 集合**取代单一 activeCapability：每个存活 owner 各自推进自己的 observation；全局仍是单一 lease。原 owner 的上下文变化重新能使其旧结果 superseded |
| Standards P1 / Spec P1 | `shutdown()` 不是终态 fence，也未接入生产 client 生命周期；关闭后仍能 activate/start，可能与忽略取消的旧 port 并行 | `isClosed` one-way 终态：关闭后 `attach`/`claim`/`observe` 永久拒绝；接入真实关闭生命周期——`AhaKeyStudioRuntimeClient.disconnect()`（由 `applicationWillTerminate` 调用）现在会 `pageCommitExecutions.shutdown()` |
| Standards P2 | detached capability 的 observation 不回收，随窗口生命周期累积 | `detach` 时回收该 capability 的 observation **仅当其无在途租约**；有租约则保留到结算（否则会破坏 inherited fence）。测试断言 5 次 attach/detach 后 `attachedObservationCount == 0` |

## 2. owner 模型（相对 C5GR5 的变化）

```text
C5GR5：activeCapability（单值，最后 attach 者胜）
       → 窗口 B 出现即夺走 A 的观察权，A 的 stale fence 失效

C5GR6：attached membership（集合）
       ├─ 每个 attached owner 独立 observation，可并行推进
       ├─ 全局仍单一 lease（不按 device 分槽）
       ├─ observe/claim 只要求「attached 且未关闭」
       ├─ cancel/settle 仍只允许 lease 的 owner capability
       └─ completion 仍路由给 execution 冻结的 originating weak delegate
```

关闭语义：`isClosed` 一旦置位不可逆，`attach` 返回 false、`claim` 返回 false、`observe` 直接丢
弃，`lease` 被放弃、port Task 被取消。

## 3. 生命周期接线

`AhaKeyConfigApp.applicationWillTerminate` → `StudioRuntimeStoreHolder.store?.disconnect()`
→ `AhaKeyStudioRuntimeClient.disconnect()` → `pageCommitExecutions.shutdown()`。

测试 `testDisconnectShutsDownCommitRegistry` 直接断言 `disconnect()` 后 `isClosed == true`
且新建 coordinator 无法 attach。

## 4. 测试

coordinator 专项由 39 项增至 **44 项**；交互测试 +1。本轮新增：

- `testReattachAfterDetachRestoresSubmission`：detach（含重复 detach）→ `attach()` 幂等两次 → observe 被接受 → `start` 成功。
- `testSecondWindowAttachDoesNotBreakFirstOwnerStaleFence`：A 在途；B attach 并 observe 别的 identity；A 再推进自己的 observation → A 的旧 accepted 必须 superseded、`lastOutcome` 为 nil、`supersededCount == 1`、B 收不到结果。
- `testShutdownIsOneWayAndFencesAttachAndClaim`：shutdown 后已 attach 的 coordinator 提交被拒、新 coordinator 无法 attach、observation 不再写入、lease 保持 nil。
- `testDetachedObservationIsReclaimedWhenNoLease`：5 轮 attach/detach 后 observation 与 owner 计数归零。
- `testDetachKeepsObservationWhileOwnerLeaseInFlight`：有在途租约时 detach 必须保留 observation。
- `testDisconnectShutsDownCommitRegistry`（交互测试）：真实关闭生命周期接线。
- `testProductionInvocationInFlightSurvivesDisconnectAndSettlesItOut`（交互测试）：用可控挂起 `.apply` 的 transport 把 **production invocation** 真正停在「已进入 port」的状态（弱持有属性本身覆盖不到这一点），再执行 `disconnect()`——断言 one-way fence 生效、租约被放弃、迟到返回不再写 trace、不残留 submitting。

## 5. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **235 / 235，0 失败** |
| coordinator 专项 | **44 / 44，0 失败** |
| 全量 Swift | **未达全绿**——4 次复跑均因既有并发 flake 出现 1–2 个失败（见下），全部位于与本轮零交集的模块 |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR6 改动范围 `git diff --check` | 通过 |

### 全量 flake 明细（如实记录）

4 次 `swift test` 的失败集合：

| 次数 | 失败测试 | 模块 |
|---|---|---|
| 1 | `AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` + `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode` | Agent / Store |
| 2 | `testRootDeleteRecreateDoesNotLockStaleInode` | Store |
| 3 | `AhaKeyAgentByteProgressTests.testProductionAckChainAdvancesSnapshotAndEventsAndSurvivesResnapshot` + `testConcurrentAppliesFromTwoClientsSerializeAndDrain` | Agent |
| 4 | `testConcurrentAppliesFromTwoClientsSerializeAndDrain` | Agent |

补充证据：

- 上述每个失败用例**隔离复跑均通过**；
- `AhaKeyAgentTests` 整类隔离连跑 3 次均 **171/171 通过**；
- `testRootDeleteRecreateDoesNotLockStaleInode` 是 Codex 在 C4R13/C4R14 已点名的既有稳定性问题；
- 同一 Agent flake 在 C5GR3 轮次的第 1 次全量中也出现过（本轮之前）；
- 本轮改动仅触及 Studio page-commit 路径（coordinator / View 的 onAppear / Store 的 `disconnect`），与 Agent 端点、Store 进程锁零文件交集。

结论：全量在当前环境的 fail 属既有并发 flake，**不声称由本轮修复或引入**。若 Codex 要求全量必须绿，建议按既有流程另开 flake 归因卡，或接受「定向全绿 + 失败项隔离复跑全绿」的等价证据口径。

## 6. 已冻结项未被破坏

owner-only cancel、originating weak callback、重复取消幂等、typed returned、app-lifetime 非 static 单租约、删除 deinit cancel、`isSubmitting` 镜像真实占用、`.cancelRequested`/`.cancelSettled` 分型、双次 pre-port fence、per-attempt record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。

## 7. 本轮仍不能证明的事

attach 可重入、多 owner membership、终态关闭与 observation 回收均为 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 8. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`（`disconnect()` 接入 shutdown）
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`（`onAppear` 幂等 attach）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
