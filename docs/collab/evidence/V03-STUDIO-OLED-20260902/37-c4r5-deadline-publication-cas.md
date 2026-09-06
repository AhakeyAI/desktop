# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R5：deadline publication CAS / WAL scope

日期：2026-09-06 13:27–13:52 +08
ACK 用户转发的 Codex C4R4 未通过与 C4R5 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 已通过项冻结 @ `7a838fa`；C4R2 已通过项冻结 @ `63af334`；C4R3 已通过项冻结 @ `13240bb`；C4R4 已通过项冻结 @ `b462eae`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R5 行为

| 审查项 | 落地 |
|---|---|
| epoch-token publication CAS | due 路径在 `await` 前冻结完整 `(deviceID, epoch)`。refresh 成功且 `pendingAbandonDeadlines[deviceID] == frozenEpoch` 才写入 `publishedAbandonDeadlines`。store/recovery/projection 失败返回 false，不消费、不清 wake task |
| 失败有界重试 | wake 在 publish 失败后 sleep 20ms 并 `continue` 同一 task，直到成功或取消。测试钩子可注入一次失败后仍在 60s 收到 eligible event |
| 删除全局 busy timeout | `AhaKeyRuntimePersistentStore.init` 不再调用 `sqlite3_busy_timeout`。损坏 fixture 仍在自己的 raw SQLite handle 上设 timeout。reopen 测试对 `locked`/`SQLITE_BUSY` 做 test-only 短重试，不恢复生产 timeout |
| 本地 order throwing | public summary init 与 `withDurableOrder` 走 `parseWire` 并 throw；非法/零 order 不再 catch/`try?` 成 legacy nil。`overlaying` 对已合法副本 `try!`。legacy nil 只来自双缺省旧 wire |

C4/C4R1–C4R4 已成立语义冻结（A@60/B@90、event-first、strict wire/live-WAL order、reopen wake、FIFO/GIF）。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。生产 store 仅删除 busy timeout 一行；其余 store/runner/InMemory/`with*` 的 `try`/`try!` 是 throwing init 的机械编译收口。

## 反例

- 发布失败一次后，同一 epoch 在 60s 仍发出 `eligible == true`，不会被永久 consumed。
- publish gate 内把 pending 换成更新 identity 的新 epoch：旧 wake 不消费新 token；60s 仍 false，90s 新 epoch 才 true。
- fresh Agent 已连接 DEVICE-B 时，断连 A 的 60s 仍 eligible。
- 本地 `queueOrder: 0`、双字段、`withDurableOrder` 零/矛盾均 throw，不得转 legacy nil。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 333/333

swift test
# 996 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `b462eae` / C4R5 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`（删除 busy timeout；合法 summary 构造补 `try`）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyInMemoryRuntimeAdapter.swift`（机械 `try`）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`（机械 `try`/`try!`）
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 其余 summary 构造点的机械 `try`：Agent byte progress、Studio page model/interaction/failure/write-progress、runner、byte projector
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R5 把到期发布收成冻结 epoch token 的成功后再消费，并收回未授权的全局 WAL timeout 与本地 order 静默降级。停手提审，不自动进 C5。
