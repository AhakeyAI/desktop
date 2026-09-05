# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3CR1：真断连代际与原子 abandon

日期：2026-09-05 14:05–14:50 +08
ACK Codex 14:00 / `lastReviewedCommit=d02d82665d307e712495c06df703cf42794d4273` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3CR1 行为

| 审查项 | 落地 |
|---|---|
| 真断连 epoch | 只有生产 device-disconnect 铸造 `AhaKeyRuntimeDisconnectEpoch`，冻结 device + session/transport identity。普通 retryable paused/resumable 不起钟 |
| connected ≠ write-ready | abandon 用 `currentConnectionPresence()`；已连接但协商/特征未齐视为 connected，拒绝 abandon |
| 原子 abandon | schema/FIFO/state/epoch/60s/confirmed ledger 重核、终态和 clock 消费同一 `BEGIN IMMEDIATE`。重连或恢复 running 先成功则拒绝；abandon 先提交则终态唯一 |
| authority 防倒退 | 完整 typed `AhaKeyRuntimeAuthoritativeVersion`：absent/unknown 可建立 verified；同代幂等；只有新代可覆盖；旧代 fail-closed 零变更 |
| local residual | `completesResidualField` 与 `sealsCompleteField` 分开。已确认 `page:local:` 离开 residual，不计 device write、不写 `writeConfirmed` |
| typed baseline | `taskAsset` 复用 `AhaKeySHA256Digest` / `AhaKeyMediaType`；`authorityVersion` 取代裸 `UInt64?` |
| Relay 越界 | 删除 `.agent-relay/tasks/V03-OLED-C3C.yaml`、`C4.yaml`、`C5-HIL.yaml` |
| baseline 读回 | page baseline 按 device 读取后用 typed `pageID` 相等过滤，避免 JSON 主键误匹配；abandon 后 WAL checkpoint，reopen 仍保留已确认 `writeConfirmed` |

C3C 已成立语义与 C3B+C3BR1–R7 冻结不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 260/260

swift test
# 938 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `d02d826` / 调度 14:00）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 删除 `.agent-relay/tasks/V03-OLED-C3C.yaml` / `C4.yaml` / `C5-HIL.yaml`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `queue.md` 状态。未进 C4。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3CR1 把 60 秒逃生门收成带 connection identity 的真断连 epoch，并把 abandon 资格/ledger/终态/clock 收进单事务。authority 用 typed version 防倒退且允许 absent 建立 verified；local residual 与 writeConfirmed 分离；越界 Relay YAML 已从产品树删除。停手提审，不自动进 C4。
