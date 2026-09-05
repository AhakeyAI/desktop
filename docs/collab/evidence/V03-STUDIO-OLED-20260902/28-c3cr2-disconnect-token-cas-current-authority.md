# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3CR2：disconnect-token CAS / current-authority

日期：2026-09-05 16:45–17:12 +08
ACK 用户转发的 Codex C3CR1 验收 / `lastReviewedCommit=4f9162be827b491c9d7994b73ea3c0c4f9e86df9` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3CR2 行为

| 审查项 | 落地 |
|---|---|
| optional UUID NULL | `operationID` 写 SQL `NULL`；NULL→nil，非 NULL 必须是合法 UUID，空字符串按 `corruptTransaction` |
| callback 当场冻结 | `didDisconnect` 在任何状态清理/重连前冻结 device/session/transport identity，并把冻结值传入 persist Task |
| 进程 lease | `AhaKeyRuntimeConnectionIdentity.writerLease`；mint/clear 走 Agent 已有 `writerLeaseGate`。`isOlder` 先比 lease，无 lease 旧于任何 lease |
| abandon CAS | `.disconnected` 必须携带 observed epoch；`commitAbandon` 要求 durable epoch `==` observed。重连先清 in-memory token 再 persist fence，再 kick |
| delayed mint fence | `clearDisconnectEpochs` 同事务写入 per-device fence；晚到的旧 identity mint 为 no-op |
| current authority | 删除 `AuthoritativeVersion.isOlder`。readback 先证明 incoming `==` 当前 store authority；否则仅 first-establish / 字段同 version 幂等 |
| strict decode | `AuthoritativeVersion` / `BaselineValue` / `ConnectionIdentity` / `DisconnectEpoch` 拒绝未知键与错误 case shape，映射 `corruptRuntimeFact` |

C3CR1 已闭合项与 C3C/C3B+C3BR1–R7 冻结不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 268/268

swift test
# 946 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `4f9162b` / 调度 16:43）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `DeviceTransportCore` / BLE lifecycle。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3CR2 把生产断连 identity 收成 callback 当场冻结值，abandon 按 observed disconnect epoch CAS，重连 fence 使迟到 mint/旧快照 fail-closed；authority readback 只承认当前 store authority；optional UUID 与 typed facts 去掉 sentinel/宽松 decode。停手提审，不自动进 C4。
