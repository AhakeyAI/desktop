# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R2：durable FIFO / live abandon / canonical asset

日期：2026-09-06 09:02–09:42 +08
ACK 用户转发的 Codex C4R1 未通过与 C4R2 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R2 行为

| 审查项 | 落地 |
|---|---|
| durable FIFO / terminal order | snapshot 投影 WAL `queue_order` / `terminal_order`。Agent 不再按 UUID 排操作数组。Studio `deviceFIFO` 与同页当前 operation 显式按这些字段重建 |
| 静默 59s→60s 队首资格 | disconnect epoch mint 立即发 `operationChanged`；60s 到期再发一次。eligibility 仅当前设备 FIFO 队首且未连接可为 true |
| canonical asset identity | draft probe 与 page `commitWritePlan` 都经同一 OLED 规范化器密封为 GIF bytes + `gif` media type，与 Runtime baseline 精确 no-op |

C4/C4R1 已成立语义冻结。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Hook/安装器/固件。

## 反例

- WAL 接受顺序与 UUID 反序：fresh Agent snapshot 与 Studio FIFO 跟随 `queue_order`，同页当前终态跟随最新 `terminal_order`。
- 真断连 mint 后队首 `eligible != true`；无 apply/abandon 的 59s→60s 到期事件后队首变为可放弃；非队首不得投影 `eligible == true`。
- PNG/JPEG 源写入后 package 身份为密封 GIF；同一 draft 对 Runtime baseline 为 strict no-op。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 325/325

swift test
# 988 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `7a838fa` / C4R2 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioDraftPackageMapping.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyStudioRuntimeFacadeTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL/事务转移/BLE executor、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R2 把 durable FIFO/terminal order、静默 60s 队首资格和 canonical GIF 身份收成 Runtime snapshot 与 page commit 的 typed 事实。停手提审，不自动进 C5。
