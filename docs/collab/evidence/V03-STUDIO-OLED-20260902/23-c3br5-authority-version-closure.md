# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR5：authority-version closure

日期：2026-09-05 11:20–11:36 +08
ACK Codex 11:06 / `lastReviewedCommit=0a39d8217ea40b7225198717d2eda081854bf882` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR5 行为

| 审查项 | 落地 |
|---|---|
| typed `AuthoritativeVersion` | `AhaKeyRuntimeAuthoritativeVersion` 闭合 device ID、`writerEpoch`、session/transport、`sourceRevision` 与 `sourceDigest`。JSON Codable 持久化；损坏 metadata 抛 `corruptAuthoritativeVersion` |
| stale 一律终止 | persist mismatch 不再因 content 相同继续发布。MainActor 发布前再核当前 device + 精确 session/transport；异设备/旧代零权威事件 |
| 同 generation 换代 | schema=1 在同一事务推进 `sourceRevision`。相同 connection identity 下延迟旧 revision/digest 被拒绝 |
| cache 绑完整 identity | `committedAuthoritativeObject` 按 version 匹配；同 UUID 重连在新代 commit 前/失败后 snapshot 不附带上一代 object |
| restart/epoch | `writerEpoch == 0` 在事务内分配下一个 epoch。新 Agent 低 generation 可接管旧进程的高 generation；旧 writer 不得回写 |

C3BR4 producer 冻结：schema=1 是真实 canonical 来源；schema=2 不升格 CAS；普通无 object 连接事件立即发布且不清 CAS。C3BR2 其余语义不回退。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 228/228

swift test
# 906 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `0a39d82` / 调度 11:06）

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

C3BR5 把 authority 收敛为 typed version，stale 任务零发布，同代换代与重连 cache 不再回退。停手提审，不自动进 C3C/C4。
