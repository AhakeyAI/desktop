# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R11：initialized generation / unlock quarantine / close ownership

日期：2026-09-07 10:44–11:21 +08
ACK 用户转发的 Codex C4R10 未通过与 C4R11 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`；C4R9 已通过项冻结 @ `fcb40c0`；C4R10 已通过项冻结 @ `b514f1f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R11 行为

| 审查项 | 落地 |
|---|---|
| 初始化 generation 记录 | 新 lockfile（open 前不存在）写入 16 字节 `AKG1` magic + version 1 + UInt64 LE generation。`pread==0` 仅在 `initializeIfEmpty` 时落盘 generation 0；既有空/截断/坏 magic/不支持 version 一律 fail-closed，不得回滚为 0 |
| unlock 隔离 | 测试 hook 在真实 `LOCK_UN` 之前注入。生产路径 `EINTR` 重试；其他失败 poison、从 registry 摘除、关闭 fence 唯一 flock 描述符。Store 在 `shared()` 成功后关闭自己的原始 lock FD，不再保留 flock dup |
| cache detach-before-await | Agent cache `clear()` 先同步 `cached=nil`，再 `await store.close()`。重入 `store(for:)` 得到新 Store，不得拿到正在关闭的实例 |
| close 后入口 | Store `ensureOpen()`：`health`/`accept`/`ingestResources`/`prepare` 抛 `"runtime store is closed"`。fence 在 closed/poisoned 时不碰 FD，抛 `"mutation fence is closed"` / `"mutation fence is quarantined"` |

C4/C4R1–C4R10 已成立语义冻结（对称 cleanup、throwing `current()`、lease/inode registry、explicit close、fresh-reopen 稳定门、facts 写前 bump、root-shared generation、事务内 `terminal_order`、MainActor publish lock、exact-token retry、TerminalTransition 等）。C2 assembler 决策与 C3 WAL/CAS/事务转移/BLE executor 未改行为，仅收口 generation 初始化、unlock 隔离与 close 所有权。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 新 lockfile：16 字节 `AKG1` 记录、generation 0；`close()` 后 `health`/`current()` 拒绝。
- 已推进 generation 后写成 3 字节再写成空文件：均 fail-closed；`publishIfUnchanged(0)` 为 nil，不得把空文件解释成 0。
- `pread` 故障钩子：抛错后同 fence 仍可 `current()`（读故障不 poison）。
- `LOCK_UN` 在 syscall 前注入失败：旧 fence quarantined；同 root 新 Store 可用且 `health` 成功。
- Agent `clear()` 在 `closeWillStart` 悬挂期间并发 `runtimeStoreForTesting()` 得到不同 Store，新实例 `health` 成功。
- 删除重建同路径 root：子进程 `flock(LOCK_EX|LOCK_NB)` 在旧 fence 持锁时对新 lockfile `GOT_LOCK`，在新 fence 持锁时 `BLOCKED`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 连续 5 轮 361/361

swift test
# 1024 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

定向门外的 `testConcurrentAppliesFromTwoClientsSerializeAndDrain` 在 C4R9 HEAD `fcb40c0` 上已是受理顺序竞态（隔离复现：`mid1=accepted`/`mid2=running` 表示 package2 先入 WAL，并非双 runner）。不在 C4R11 白名单，未改该测试。本轮全量首次出现该既有 flake，立即重跑为 1024/2 skipped/0；以重跑为准。

## 审查范围（相对 `b514f1f` / C4R11 开放）

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

C4R11 把新 lockfile 写成可识别的 generation 记录并把事后空/截断视为损坏，把真实 `LOCK_UN` 失败收成 poison/evict/关闭 flock 描述符，并把 cache/Store close 收成 detach-before-await 与 fail-closed 入口。停手提审，不自动进 C5。
