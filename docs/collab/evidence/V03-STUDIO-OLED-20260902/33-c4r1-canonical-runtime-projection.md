# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R1：canonical Runtime projection

日期：2026-09-05 22:58–23:25 +08
ACK 用户转发的 Codex C4 未通过与 C4R1 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R1 行为

| 审查项 | 落地 |
|---|---|
| OLED profile | Agent 把已密封 `AhaKeyOLEDCompatibilityContext` 投影为 optional `device.oledCompatibility`。Studio 只读该 fact；缺省 `unsupported`，禁止从 `protocolState` 猜测 |
| typed page ownership | `AhaKeyRuntimeOperationSummary.pageID` 来自 WAL `pageOperation.pageScope`。fresh Studio 只凭 snapshot 重建页锁/FIFO/去重/页标题 |
| durable 60s | `abandonEligibility` 由 WAL disconnect epoch + Runtime wall clock 投影。Studio 不保存 `disconnectedSince` |
| pageBaselines | `fieldAuthorities()` 只消费 active-device `snapshot.pageBaselines`，保留 task-asset digest/byteCount/mediaType |
| paused / resumable | 页锁定；不得新起 residual operation。abandon 只看 Runtime `eligible` |
| 终态 residual | `failedWithoutWrites` / `failedWithPartialCommit` 且 residual 非空才允许新 operation |
| mixed trust | 当前页任一 `writeConfirmed` →「已写入待验证」；不再因同时存在 verified 显示「已同步」 |
| 完成页 | 不再把可变 `studioDraft` 写入 `lastSyncedDraft` |

C2 assembler 决策与 C3 WAL/事务转移/BLE executor 未改。未改 Hook/安装器/固件。

## 反例

- fresh Studio 从 snapshot 重建 queued/running/paused/resumable 页锁与 FIFO。
- 切换 active device 后，其他设备 operation/baseline 不锁当前页、不进入 authority。
- 新 Studio 实例只凭 snapshot `abandonEligibility.eligible=true` 允许放弃，无本地时钟。
- `currentReady`/`legacyDenied` 无 OLED fact 时 profile 为 unsupported；四种 sealed fact 可分。
- active-device page baseline 保留 task-asset digest/byteCount/mediaType。
- mixed writeConfirmed+verified → 已写入待验证。
- `failedWithoutWrites` + residual 允许新 operation；`resumablePartial` 再提交 `pageAlreadyInFlight`。
- Agent snapshot 投影 pageID、密封 OLED fact，以及满 60s 后 `abandonEligibility.eligible`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 318/318

swift test
# 981 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `62afcaf` / C4R1 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioPageModelTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioRuntimeDerivationTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL/事务转移/BLE executor、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R1 把 OLED profile、页归属、60s 资格和 page baseline 收成 Runtime snapshot 的 typed 事实，fresh Studio 只消费这些投影。停手提审，不自动进 C5。
