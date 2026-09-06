# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R6：proven publication / isolated bounded scheduler / typed order

日期：2026-09-06 15:04–15:53 +08
ACK 用户转发的 Codex C4R5 未通过与 C4R6 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`；C4R3 已通过项冻结 @ `13240bb`；C4R4 已通过项冻结 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R6 行为

| 审查项 | 落地 |
|---|---|
| per-token publication proof | `AhaKeyAbandonDeadlineToken` 含 `operationID + deviceID + full epoch`。`proveAndPublishOneAbandonToken` 要求 durable 队首即该 operation、state 为 paused/resumablePartial、`disconnectEpoch` 精确相等、strict 投影（无 `try?`）、`eligible==true`，并在 `publishOperationChanged` 后核对 `lastPublishedOperationSummaries` 已发出该 event。只返回通过证明的 token set |
| 有界失败重试 | scheduler 失败 burst：20ms / 80ms / 320ms / 1.28s 共 4 次；耗尽后保留 pending token、停止 wake，等待 snapshot/`noteExternalRecoveryTrigger` 再开 |
| scheduler actor 隔离 | `pending`/`published`/`wakeTask`/`scheduledFireAt`/`retryAttempt`/`burstExhausted` 全部收入 `AhaKeyAbandonDeadlineScheduler` actor。XPC snapshot、BLE reconnect、wake 只经 actor API 变更 |
| typed production vs legacy wire | public summary init 只接受 typed `durableOrdering` 并 `requireMatching(state)`。`init(from:)` 是唯一可产生 legacy nil 的路径（双缺省旧 JSON）。WAL/拷贝走 package storage init。生产 `overlaying`/`runner` 不再 `try!` OperationSummary |

C4/C4R1–C4R5 已成立语义冻结（A@60/B@90、event-first、strict wire/live-WAL order、reopen wake、FIFO/GIF、epoch pending CAS、connected B/disconnected A、无全局 busy timeout）。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。store/runner/InMemory 的 typed init/`storageID` 收口属于机械编译配合。

## 反例

- 把 pending token 换成不存在的 operationID：60s 不发出原 operation 的 `eligible==true`；恢复原 token 后仍可发布。
- `runningHead` / `projectionFailure` 注入：不消费、不发 eligible；清除 fault 后仍可发布。
- 持久 refresh 失败：600ms 内尝试次数 ≤4，再等 250ms 次数不再增加；token 仍保留。
- 到期瞬间并发 snapshot + 新 epoch mint/replace：pending 保留替换 token；90s 才 eligible。
- 现代本地 `live(0)` / 活态+terminal order 构造 throw；旧 wire 双缺省 JSON 才得到 `durableOrdering == nil`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 337/337

swift test
# 1000 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `b030c3b` / C4R6 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAbandonDeadlineScheduler.swift`（新增）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`（去掉 OperationSummary `try!`，WAL 拷贝走 storage init）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`（typed production init）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`（abandon 先分配 typed terminal order）
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 其余 summary 构造点的机械 typed-order：Agent byte progress、Studio page model/interaction/failure/write-progress、runner、byte projector
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R6 把到期发布收成逐 token 的 durable head+epoch+eligible event 证明，把 scheduler 整机隔离进 actor 并用有界 burst 代替 50Hz 热循环，并把现代 order API 收成 typed-only。停手提审，不自动进 C5。
