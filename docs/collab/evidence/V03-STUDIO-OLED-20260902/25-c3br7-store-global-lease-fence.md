# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR7：store-global lease fence

日期：2026-09-05 12:25–12:36 +08
ACK Codex 12:20 / `lastReviewedCommit=aeacf4c638c758814d66f9f8b0e47664f12b9971` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR7 行为

| 审查项 | 落地 |
|---|---|
| store-global 写 fence | `persistProjectedAuthoritativeObjectUnlocked` 在 exclusive lock + `BEGIN IMMEDIATE` 内 decode 当前 `authoritative-writer-lease`；incoming 必须精确相等，之后才做 per-device source/generation 检查或写入 |
| 分配即撤销 | 新 lease allocate 后，旧 lease 写尚未被新 writer 触碰的另一设备立即 stale |
| 伪造 future lease | `current+1` 未分配 lease 拒绝，对象/version 零变化 |
| missing/corrupt metadata | 缺少或损坏 `authoritative-writer-lease` 抛 `corruptAuthoritativeVersion`，对象/version 零变化 |
| fixtures | 历史 seed 只走真实 `allocateAuthoritativeWriterLease`，不再用未分配 2/10 直接 persist |

C3BR6 冻结：Agent single-flight 进程 lease、max-across-device allocation、同 lease source/generation、typed nonzero counters、首次并发/多设备接管。C3BR5/4 producer 不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 241/241

swift test
# 第一次：919 tests / 2 skipped / 1 failure
# 失败项：AhaKeyAgentPageExecutionTests.testSameGenerationSchema1ReplacementRejectsDelayedRollback
# 原因：已有延迟用例未等 N 进入 gate，全量负载下 N+1 抢到 delayOnce，waitUntil object-b 超时。非 byte-progress，也非 fence 误拒。
# 修复：给 primed 延迟用例补 waitUntilEntered。单项立即 5/5。
# 第二次：919 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `aeacf4c` / 调度 12:20）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 Agent 生产路径、C2 assembler/dirty/Views/Hook/安装器/固件。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3BR7 把 current store-global writer lease 收成 persist 写 fence。旧 writer 不能再写未触碰设备，未分配/损坏 lease 不能写入。停手提审，不自动进 C3C/C4。
