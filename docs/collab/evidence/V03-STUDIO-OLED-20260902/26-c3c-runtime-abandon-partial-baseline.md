# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3C：Runtime abandon + partial baseline

日期：2026-09-05 13:05–13:40 +08
ACK Codex 13:00 / `lastReviewedCommit=705a2579f101c02b1c224b0de8cb2bb37173a7e6` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3C 行为

| 审查项 | 落地 |
|---|---|
| 同事务 baseline | `confirmPageStep` 在同一 `BEGIN IMMEDIATE` 内插入 confirmed step，并仅在完整 field 设备动作上写入 `writeConfirmed`；不得写 `verified` |
| chunk 不密封 | `page:chunk:` 中间进度不推进 field/resource baseline；`page:bind:` 才密封 picture field 与 resource |
| 权威升格 | 精确相等的 `writeConfirmed` → `verified`；不匹配按权威事实覆盖；不从 Studio cache 升格 |
| 60 秒 abandon | schema=2 FIFO 队首 paused/resumable、仍断连且连续满 60s 才受理；`<60s`、connected/running、非队首、schema=1 拒绝 |
| clock | 可注入；rollback fail-closed；store reopen 不重置已开始窗口；重连清钟，再断连从新起点计时 |
| 终态 | 与 fail-fast 共用 confirmed-ledger / typed `writesDevice`；`page:local:` 不计设备写；释放 FIFO 队首 |
| 合同投影 | operation summary / snapshot 暴露 residual 与 confirmed baselines，供 C4 使用；本切片不接 UI |

C3B+C3BR1–R7 冻结语义不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 251/251

swift test
# 929 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `705a257` / 调度 13:00）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeProductionSeam.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3C 把 schema=2 的 durable 60 秒 abandon 和逐 field/resource `writeConfirmed` baseline 收进 Runtime。partial/no-write 终态、精确 residual、FIFO 释放与 reopen 时钟均有反例。停手提审，不自动进 C4。
