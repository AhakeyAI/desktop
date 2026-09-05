# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR6：writer-epoch lease closure

日期：2026-09-05 11:50–12:12 +08
ACK Codex 11:46 / `lastReviewedCommit=7a27ea2717e08e37572f907d6ab7b2b0dde9b179` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR6 行为

| 审查项 | 落地 |
|---|---|
| 进程级 durable writer lease | `allocateAuthoritativeWriterLease()` 在 flock + `BEGIN IMMEDIATE` 下取 store-global 与全部 device version 的 max+1，一次写入 `authoritative-writer-lease`。Agent `AhaKeyAgentWriterLeaseGate` 在 authority task 前分配一次，进程内不可变，全部设备/task 共用 |
| persist 只接受已分配 lease | `persistProjectedAuthoritativeObject` 拒绝 `writerLease == nil`，不再按 `0` 为每个 candidate 铸造 epoch |
| 同 lease 完整比较 | 同一 lease 比较 device、session/transport、source revision/digest。更高 lease 只跳过 generation（允许低代接管），不跳过 source，因此不能靠更大 epoch 回滚 content |
| typed counter | `AhaKeyRuntimeAuthoritativeWriterLease` / `AhaKeyRuntimeAuthoritativeSourceRevision` 从 1 起，init/decode 拒绝 sentinel `0` |
| 单一 identity predicate | 发布与 cache 只走 `committedVersion.matches(current)` |
| 首次并发 | 未 prime 的 fresh Agent：延迟 N → N+1 → 释放 N，N 不得改 CAS / 不得发旧代权威事件 |
| 多设备 | fresh Agent 先接历史 lease 2 的 A 再接 lease 10 的 B，两者都建立 authority；fresh reopen 低 generation 接管多设备高代历史；旧 lease 回写 fail-closed |

C3BR5 冻结：typed Codable `AuthoritativeVersion`、schema=1 同事务推进 source revision/digest、损坏 decode fail-closed、stale 零发布、cache 绑完整 identity、MainActor recheck。C3BR4 producer 不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 237/237

swift test
# 915 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `7a27ea2` / 调度 11:46）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePersistentStoreTests.swift`
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler/dirty/Views/Hook/安装器/固件。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3BR6 把 writer epoch 收成一次分配、进程实例级且对所有设备有效的 durable lease。首次并发与多设备历史不再回滚 CAS 或永久拒绝。停手提审，不自动进 C3C/C4。
