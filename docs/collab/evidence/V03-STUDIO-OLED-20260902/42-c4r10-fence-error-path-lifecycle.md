# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R10：fence error-path / root lifecycle / contention stability

日期：2026-09-06 22:14–2026-09-07 10:28 +08
ACK 用户转发的 Codex C4R9 未通过与 C4R10 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R10 行为

| 审查项 | 落地 |
|---|---|
| 对称 cleanup | `withExclusiveAccess` 在取得 recursive lock 后走单一路径：`LOCK_EX` → `loadGeneration` → body → depth 配对 decrement → 仅 outermost `LOCK_UN` → 一次 `recursive.unlock`。原错优先于 unlock 错；`LOCK_UN` 失败不再进入会二次 decrement/unlock 的 catch |
| throwing / fail-closed `current` | `current()` 改为 `throws`；短/损坏 generation 文件与 `pread` 故障不再映射为 generation 0 |
| lease / inode / FD | registry 按 retainCount 持有；最后一条 lease 关闭 dup FD 并退出 registry。`fstat` 身份不匹配时丢弃旧 registry 项，不关闭仍被旧 Store 使用的 fence。Store `close()` 先 `sqlite3_close`（BUSY 则 `sqlite3_close_v2`）再放 lease |
| fresh reopen | Agent cache `clear()` 在丢弃缓存前 `await store.close()`。探测 Store 在 reopen 前显式 close，不再只靠延迟 `deinit` |

C4/C4R1–C4R9 已成立语义冻结（facts 写前 bump、root-shared generation、事务内 `terminal_order`、MainActor publish lock、exact-token retry、TerminalTransition 等）。C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor 未改行为，仅收口锁生命周期。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 截断 generation 文件：`current()` fail-closed；写成空文件后同 Store 仍可 `health`/读事务。
- `pread` 故障钩子与 `LOCK_UN` 故障钩子：抛错后同 fence 仍可 `current()`/`health`。
- 删除并重建同路径 root：新 fence ≠ 旧 fence；同新 root 的两 Store 共享新 fence；close 后再开仍可用。
- 显式 `close()` 后同 root 8 轮 reopen；Agent `closeRuntimeStoreForTesting` 后 5 轮独立 Store + Agent cache reopen，无 `database is locked`。
- `testFreshReopenDisconnectBeforeReadyMintsNewEpoch` 在打开下一 Store 前显式 close 探测连接。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 连续 5 轮 358/358

swift test
# 1021 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

定向门外的 `testConcurrentAppliesFromTwoClientsSerializeAndDrain` 在 C4R9 HEAD `fcb40c0` 上已是受理顺序竞态（5 次隔离 3 过 2 不过：`mid1=accepted`/`mid2=running` 表示 package2 先入 WAL，并非双 runner）。不在 C4R10 白名单，未改该测试。全量以本轮 1021/2 skipped/0 为准。

## 审查范围（相对 `fcb40c0` / C4R10 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R10 把 fence 异常路径收成对称释放，把 generation 读改成 fail-closed，给 root registry 加上 lease/inode/FD 生命周期，并在 Store/Agent 缓存 teardown 时显式关闭 SQLite，消除 fresh reopen `database is locked`。停手提审，不自动进 C5。
