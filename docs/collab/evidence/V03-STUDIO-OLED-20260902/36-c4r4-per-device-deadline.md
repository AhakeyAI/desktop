# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R4：per-device deadline / strict order

日期：2026-09-06 10:48–12:12 +08
ACK 用户转发的 Codex C4R3 未通过与 C4R4 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`；C4R3 已通过项冻结 @ `13240bb`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R4 行为

| 审查项 | 落地 |
|---|---|
| per-device deadline scheduler | 各 disconnected FIFO 队首保留自己的 durable epoch；单 scheduler 只睡最早未发布项。B@90 不得取消 A@60。触发后标记已发布并重算下一 deadline |
| 连接/队首变更 | 仅当该设备是队首且未连接时 arm；已连接或非队首 drop 该设备项后重算。snapshot overlay 只 upsert/drop，结束时若仍有 pending 再 reschedule |
| strict state/order | wire：双缺省兼容 nil；否则必须恰好一个与 state 匹配的正序号，矛盾 JSON throw。当前 WAL live 必须 `queue_order > 0` 且 `terminal_order` 为空；terminal 必须 `terminal_order > 0`（SQL 遗留 `queue_order` 忽略）。损坏行 `corruptTransaction`，不回退 UUID |
| 59→60 反例 | 同进程与 reopen 均从 59s cursor 先等 eligible event，再验 snapshot。另覆盖 A@60 / B@90 互不取消 |

C4/C4R1–C4R3 已成立语义冻结。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- A@60、B@90：59s 两队首均为 false；60s 仅 A 的 eligible event 为 true；90s B 到期。B 的 arm 不得取消 A。
- 同进程与 reopen：59s cursor 后无其它事件到 60s 收到队首 true event，然后 snapshot 亦为 true。
- 矛盾 JSON（live 同时带 `terminalOrder`，terminal 同时带 `queueOrder`）解码失败。
- 当前 WAL live 缺失 `queue_order` 读取失败，不得降为 nil/UUID。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 330/330

swift test
# 993 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `13240bb` / C4R4 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R4 把多设备独立队首 60s 到期调度和矛盾 order 的 fail-closed 收成 Runtime 事实。停手提审，不自动进 C5。
