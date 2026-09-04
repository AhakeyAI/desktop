# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR3：deviceChanged 权威事件接入 live CAS

日期：2026-09-05 00:21–00:42 +08
ACK Codex 00:12 / `lastReviewedCommit=25a1a5998f26eb9813fab6e1184fcdbff6ee546d` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR3 行为

| 审查项 | 落地 |
|---|---|
| 生产权威事件 | 已有 `deviceChanged` 设备快照。`AhaKeyRuntimeDeviceSnapshot.authoritativeObject` 携带 canonical content；发布该事件时原子写入 `authoritative-object:<deviceID>`。BLE 生产投影暂不填该字段（尚无读回），首次 schema=2 在无对象时继续零写 fail-closed |
| 首次取得 / 换代 | 同一 `deviceChanged` 路径：有非空对象即覆盖 live CAS；断开（`nil` 设备）不清除 CAS。schema=1 `commitOperationOutcome` 仍在同一事务更新 baseline+CAS；schema=2 完成不改写 |
| 测试穿过事件 | Agent 测试经 `simulateDeviceForTesting`（发布 `deviceChanged`）建立/换代 CAS；删除 `recordAuthoritativeObject` 与直写 sealer。覆盖初始建立、换代、accept 后变更、fresh reopen、缺对象零写，以及 authority event → page preflight 端到端 |
| P3 删除重复 metadata | 删除 `sealed-object:*` 的计算、写入与 key。CAS 单一来源仍为 canonical content 的 `authoritativeObjectFingerprint` |

C3BR2 已冻结：typed `writesDevice`、恢复 CAS 门、终态分类、schema=1 原子 baseline+CAS、schema=2 不改 CAS、`0x84` 值域 `0...7` / WAL `0xff` fail-closed。不实现 60 秒 abandon、逐字段 baseline projection、C4 UI。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 217/217

swift test
# 895 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `25a1a59` / 调度 00:12）

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

C3BR3 把 live CAS 接到已有 `deviceChanged` 权威设备快照事件，并删除无读取方的 `sealed-object:*`。停手提审，不自动进 C3C/C4。
