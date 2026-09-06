# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R3：reopen deadline wake / typed order

日期：2026-09-06 10:10–10:20 +08
ACK 用户转发的 Codex C4R2 未通过与 C4R3 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R3 行为

| 审查项 | 落地 |
|---|---|
| reopen deadline wake | fresh Agent snapshot/recovery 从已有 durable FIFO 队首 epoch 按原 `startedAt` arm；未到期睡剩余时间，已到期立即发布。已连接或非队首不 arm |
| typed state/order | `AhaKeyRuntimeDurableOrdering` 与 `state` 一起校验：活队列只有 `queueOrder`，终态只有 `terminalOrder`。WAL `transaction`/`recovery`/`terminal` 同一行读出，不再二次查询 |
| summary clone | 五个 `with*` 收敛到单一 `overlaying`；JSON 仍平铺 `queueOrder`/`terminalOrder`，不编码嵌套 enum |

C4/C4R1/C4R2 已成立语义冻结。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 59s 关闭旧 Agent → fresh Agent snapshot `eligible=false` → 无其它事件到 60s 收到队首 `true` event；非队首不得 `eligible==true`。
- 已到期 reopen：snapshot 即为 `true`，并立即发布 event，不新 mint。
- 已连接 reopen：59s→60s 不 arm，不发布 `eligible==true`。
- 矛盾 JSON：accepted 带两个序号只保留 live `queueOrder`；completed 只保留 `terminalOrder`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 328/328

swift test
# 991 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `63af334` / C4R3 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R3 把 fresh Agent 对已有 durable disconnect epoch 的 60s 到期唤醒、typed state/order 原子投影和 summary clone helper 收成 Runtime snapshot 事实。停手提审，不自动进 C5。
