# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3CR4：eager lease / connected-lease 解耦 / proven authority

日期：2026-09-05 17:45–17:53 +08
ACK 用户转发的 Codex C3CR3 手工验收 / `lastReviewedCommit=8dfd7da7e5192291f6ca98ea3ac1d25ed79a9ef1` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3CR4 行为

| 审查项 | 落地 |
|---|---|
| eager writer lease | 生产路径在 `poweredOn` 后、`connectAutomatically` 前分配并缓存 store-global lease。测试经 `ensureWriterLeaseForTesting` 在可观察断连前建立。callback 仍要求已缓存 lease，缺 lease 不铸造 epoch |
| 连接事实解耦 | `isRuntimeConnected()` 只看 BLE phase / `peripheral` / 模拟连接，不再把 `cachedWriterLease == nil` 当成 disconnected |
| proven per-device authority | `applyAuthoritativeFieldReadback` 要求 store 已持有且 incoming 精确等于当前 per-device authoritative version；字段 absent/unknown 仍可升 verified，但设备 authority absent 拒绝 |
| 单一 lease decoder | readback 复用 `currentAuthoritativeWriterLeaseUnlocked()`；缺失/损坏 global lease 一律 `.corruptAuthoritativeVersion` |

C3CR3 已闭合项与 C3C/C3B+C3BR1–R7 冻结不回退。

## 反例

- fresh reopen、ready 前再次断连：新进程 lease 铸造新 epoch，旧 60 秒窗口不得被继承。
- fresh reopen、实际 connected 且未缓存 lease：abandon 拒绝，不得用旧 epoch 放行。
- 仅有当前 global lease、无 per-device authority：调用方自造 version 不得建立 verified。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 276/276

swift test
# 954 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `8dfd7da` / 调度 17:37）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `DeviceTransportCore` / BLE lifecycle 状态机。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3CR4 在可观察断连前建立进程 writer lease，把连接事实从 lease 缓存解耦，并要求 verified 证明当前 per-device authority。停手提审，不自动进 C4。
