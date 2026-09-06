# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R8：post-proof fence / tokenized retry / store-owned terminal order

日期：2026-09-06 18:27–18:49 +08
ACK 用户转发的 Codex C4R7 未通过与 C4R8 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R8 行为

| 审查项 | 落地 |
|---|---|
| post-proof publication fence | `AhaKeyRuntimeMutationFence` 在 WAL 写入前 bump；MainActor 发布在同一把锁上 `publishIfUnchanged(expectedGeneration)`。第二次 proof 之后、发布之前的 terminal/reconnect 会抬世代，过期 `eligible=true` 不得发出 |
| tokenized retry tasks | sleeper 携带 exact token + generation，记入 `retryTasks`。upsert/drop/replace/cancel 使旧 task 取消或自行失效；`cancelAllAndWait` 等待 wake 与全部 retry task |
| store-owned terminal order | `AhaKeyRuntimeOperationTerminalTransition` 不携带 projected order。Runner 终态只提交 transition；store 分配真实 `terminal_order` 后再构造 summary |

C4/C4R1–C4R7 已成立语义冻结（single-hop facts、`mutationGeneration`、exact `epochIdentity` + 新 event sequence、A 失败不阻断 B、storage init 校验、专用 scheduler actor、full token pending CAS、四档 retry burst、connected B/disconnected A、public typed initializer/legacy wire、A@60/B@90、event-first、strict wire/live-WAL order、reopen wake、FIFO/GIF、无全局 busy timeout）。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 第二次 proof 返回后提交 head terminal：不发出过期 `eligible=true`。
- 第二次 proof 返回后 reconnect：不发出过期 `eligible=true`。
- N retry sleeping 时替换为 N+1：旧 sleeper 不得增加 refresh 次数；显式 reschedule 后 N+1 仍可发布。
- `cancelAllAndWait` 后 retry task 计数为 0。
- 先提交终态 1，Runner 再 cancel 第二项：WAL `terminal_order == 2`，不是占位 1。
- `AhaKeyRuntimeOperationTerminalTransition` 拒绝非终态。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 347/347

swift test
# 1010 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `d02d611` / C4R8 开放）

修改：

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAbandonDeadlineScheduler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeContractTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyConfigurationTransactionRunnerTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R8 把第二次 proof 与 MainActor 发布收成共享 mutation fence，把 retry sleeper 绑到 exact token/generation，并把终态顺序交回 store 分配。停手提审，不自动进 C5。
