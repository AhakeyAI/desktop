# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R7：atomic publication proof / per-device retry / order transition

日期：2026-09-06 16:10–16:43 +08
ACK 用户转发的 Codex C4R6 未通过与 C4R7 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R7 行为

| 审查项 | 落地 |
|---|---|
| consistent publication proof | `abandonPublicationFacts` 一次 actor hop 读取队首/epoch/confirmed/baselines/`mutationGeneration`。证明捕获 `abandonPublicationFence`，boundary gate 后再核 fence+generation；MainActor 发布前再核 fence、断连与 clock。reconnect/clear/head 变更会抬 fence 或 generation，过期 `eligible=true` 不得发出 |
| 绑定 exact token 的新 event | 成功证明必须 `publishRuntimeEvent` 使 sequence 前进，并携带 `epochIdentity`。不再用 `lastPublishedOperationSummaries` 去重结果当 proof。同 `startedAt`、不同 epoch identity 会发出新 sequence |
| per-device retry | `retryAttemptByDevice` / `exhaustedDevices` / `retryWaitDevices` 按设备隔离。A 耗尽 burst 后 B 仍可在自己的 deadline 发布 |
| typed order transition | package `storageID` init 对非 nil order 执行 `requireMatching(state)`。Runner terminal summary 使用 `.terminal(terminalOrder:)`，不再夹带 live queue order |

额外收口：到期 wake 与 reconnect 并发时，test hooks 计数只在 MainActor 更新；`clearDisconnectEpochs` 删除 equal identity epoch，避免过期 epoch 在 lastFrozen 清空后仍被 abandon 消费。

C4/C4R1–C4R6 已成立语义冻结（专用 scheduler actor、full token pending CAS、四档 retry burst、connected B/disconnected A、public typed initializer/legacy wire、A@60/B@90、event-first、strict wire/live-WAL order、reopen wake、FIFO/GIF、无全局 busy timeout）。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- proof 最终发布前注入 reconnect：不发出过期 `eligible=true`。
- proof 最终发布前队首变为 running：不发出过期 `eligible=true`。
- 同 `startedAt`、不同 epoch identity：必须前进新 event sequence。
- A 注入持续失败耗尽 burst 后，B 仍在 t90 发布 eligible event。
- storage init：`.completed` + `.live(queueOrder:)` throw。
- Runner completed/cancel-without-writes：WAL 行为 terminal order，不是 live queue order。
- equal identity reconnect：WAL epoch 被清除。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 342/342

swift test
# 1005 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

`testReconnectClearsFrozenDisconnectBeforeAbandon` 隔离 15/15。

## 审查范围（相对 `2c2e59f` / C4R7 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAbandonDeadlineScheduler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyConfigurationTransactionRunnerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R7 把到期发布收成 fence+generation 一致证明并绑定 exact token 的新 event，把 retry 按设备隔离，并封闭 typed order 的生产 bypass。停手提审，不自动进 C5。
