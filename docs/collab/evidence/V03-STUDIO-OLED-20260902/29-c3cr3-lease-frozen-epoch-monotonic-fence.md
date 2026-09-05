# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3CR3：lease-frozen epoch / monotonic fence / global-lease readback

日期：2026-09-05 17:22–17:36 +08
ACK 用户转发的 Codex C3CR2 验收 / `lastReviewedCommit=5b8ca57c1a590e802822ee52295628cee2ab0238` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3CR3 行为

| 审查项 | 落地 |
|---|---|
| 同步 writer lease | apply 受理前分配并缓存进程 lease。callback 冻结 identity 必须已持有 lease；缺 lease 不铸造 epoch。异步路径不得再补 nil-lease identity |
| fence 单调 | `clearDisconnectEpochs`：相等幂等，旧 identity 整事务拒绝，只有严格更新的 identity 可覆写 fence |
| fence 失败不恢复 | `scheduleConfigurationRecovery` 仅在 fence 成功后 kick；失败 emit 并保持暂停 |
| global lease readback | `applyAuthoritativeFieldReadback` 同一事务核当前 store-global writer lease，并要求 incoming 等于当前 per-device authority（若已有） |
| Relay 越界 | 删除未授权 `.agent-relay/tasks/RELAY-CLIENT-BOOTSTRAP.yaml` |

C3CR2 已闭合项与 C3C/C3B+C3BR1–R7 冻结不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 273/273

swift test
# 951 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `5b8ca57` / 调度 17:21）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 删除 `.agent-relay/tasks/RELAY-CLIENT-BOOTSTRAP.yaml`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `DeviceTransportCore` / BLE lifecycle。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3CR3 把断连 epoch 收成 callback 已同步持有的 writer lease，fence 单调且失败不恢复，readback 核 store-global lease，并移出未授权 Relay bootstrap 状态文件。停手提审，不自动进 C4。
