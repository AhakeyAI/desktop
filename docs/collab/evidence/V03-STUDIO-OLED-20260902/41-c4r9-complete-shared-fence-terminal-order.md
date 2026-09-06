# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C4R9：complete shared fence / transactional terminal order

日期：2026-09-06 19:07–19:32 +08
ACK 用户转发的 Codex C4R8 未通过与 C4R9 开放。C1–C3 accepted @ `c6e0762`；C4 交互骨架保留 @ `62afcaf`；C4R1 @ `7a838fa`；C4R2 @ `63af334`；C4R3 @ `13240bb`；C4R4 @ `b462eae`；C4R5 已通过项冻结 @ `b030c3b`；C4R6 已通过项冻结 @ `2c2e59f`；C4R7 已通过项冻结 @ `d02d611`；C4R8 已通过项冻结 @ `f37184f`。产品基线 `1ed560b` / 已安装 `0.2.1 (362)` 不受影响。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C5/HIL。未改 `queue.md`。未伪造 Relay `review_decision`。本提交从 HEAD board/任务卡只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C4R9 行为

| 审查项 | 落地 |
|---|---|
| facts 写前推进同一 fence | `confirmStep`、`confirmPageStep`、`applyAuthoritativeFieldReadback`（仅实际改 baseline 时）以及既有 head/epoch/accept 写路径都在 WAL 写前 `beginDurableMutation()` |
| persistence-root 共享 / durable CAS | `AhaKeyRuntimeMutationFence.shared(for:lockFileDescriptor:)` 按 root 复用；世代持久化在跨 Store `flock` 锁文件上。`publishIfUnchanged` 与 facts 读取都在同一把独占锁上重读世代 |
| transactional terminal order | `commitOperationOutcome` 在 `withExclusiveAccess` + `BEGIN IMMEDIATE` 内重新读行、`allocateTerminalOrder()`、写入；`commitAbandon` 同样持锁后在事务内分配 |

C4/C4R1–C4R8 已成立语义冻结（MainActor publish lock 内核 generation、exact-token retry 取消/等待、专用 TerminalTransition、single-hop facts、A 失败不阻断 B、专用 scheduler、full token pending CAS、四档 retry burst、connected B/disconnected A、public typed initializer/legacy wire、A@60/B@90、event-first、strict wire/live-WAL order、reopen wake、FIFO/GIF、无全局 busy timeout）。C2 assembler 决策与 C3 WAL mint/CAS/事务转移/BLE executor 未改行为，仅收紧 fence/order 原子化。未改 Studio 已验收交互、Hook/安装器/固件。

## 反例

- 第二次 proof 返回后 `confirmPageStep`：不发出过期 `eligible=true`。
- 第二次 proof 返回后 authority readback：不发出过期 `eligible=true`。
- 第二次 proof 返回后，同一 persistence root 的第二 Store 提交终态：不发出过期 `eligible=true`。
- 双 Store 同 root：B 的 `confirmPageStep` / readback 使 A 的 `publishIfUnchanged(proofGeneration)` 失败。
- 双 Store 并发终态：`terminal_order` 为唯一单调 `{1,2}`。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests|AhaKeyStudioPageInteractionTests|AhaKeyStudioRuntimeDerivationTests'
# 353/353

swift test
# 1016 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `f37184f` / C4R9 开放）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler dirty/冻结语义、C3 WAL mint/CAS/事务转移/BLE executor、Studio 已验收交互、Hook/安装器/固件。未改 `queue.md` 状态。未进 C5。未改 Agent 发布路径：proof/publish 继续读同一 `mutationFence`，现为 root-shared durable 世代。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C4R9 把 publication fence 收成 persistence-root 共享的锁文件世代，让 confirmed steps/page baselines/readback 参与同一写前 bump，并把 `terminal_order` 放进写事务与跨 Store 独占锁。停手提审，不自动进 C5。
