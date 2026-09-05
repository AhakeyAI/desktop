# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3CR5：lease allocation fail-closed / poweredOn recheck

日期：2026-09-05 19:14–19:21 +08
ACK 用户转发的 Codex C3CR4 手工验收 / `lastReviewedCommit=5902e723c15d3adc1ce5497ddb621abdf464a57a` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3CR5 行为

| 审查项 | 落地 |
|---|---|
| 分配失败保持离线 | `prepareWriterLeaseThenConnectIfBluetoothPoweredOn` 在 `resolveCachedWriterLease` 失败时 emit 并 return，不得调用 `connectAutomatically()` |
| 错误可观察 | 失败路径 emit `writer lease 分配失败：…`；测试经 `onLog` 断言 |
| 成功才连接 | 仅 lease 成功后，在 MainActor 上重核 Bluetooth 仍为 poweredOn，再 scan/connect |
| 迟到 Task | await 期间 poweredOn 变为 false 时，lease 可已缓存，但不得启动 BLE |
| 同一进程 lease | 失败不进入 allocate；成功重试只 `store.allocate` 一次，后续 poweredOn 复用 `writerLeaseGate` |

C3CR4 已闭合项与 C3CR3/C3C/C3B 冻结不回退。未改 `DeviceTransportCore` / BLE lifecycle 状态机。

## 反例

- 生产顺序：paused WAL + 已有 disconnect epoch → lease 分配失败 → connect 计数 0、无新 epoch、operation 保持 paused/resumable；清除失败后成功重试只分配一次进程 lease 并开始连接；再次调用复用同一 lease。
- await 分配期间 Bluetooth 不再 poweredOn → lease 已缓存，connect 计数不增加。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 278/278

swift test
# 956 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `5902e72` / 调度 18:01）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `AhaKeyRuntimePersistentStore.swift`。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3CR5 把生产 poweredOn 收成 lease 成功且仍 poweredOn 才允许 scan/connect；失败保持离线且错误可观察。停手提审，不自动进 C4。
