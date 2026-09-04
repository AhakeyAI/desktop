# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR2：权威 CAS 生产生命周期与 typed device-write fact

日期：2026-09-04 23:40–23:58 +08
ACK Codex 23:38 / `lastReviewedCommit=d212e6aad2de0119d8f996e6e22710b56ae0e375` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR2 行为

| 审查项 | 落地 |
|---|---|
| 生产 live CAS 写入者 | `recordAuthoritativeObject` 哈希 canonical content 并原子密封。schema=1 `commitOperationOutcome` 在同一事务更新；schema=2 page 完成不改写权威对象。测试只走该生产入口，不再调 sealer |
| 先判 typed device-write | WAL confirmed + 冻结 plan 的 `writesDevice`（program 非空）决定是否要求 live CAS。无设备写：缺/变 CAS 零写 fail-closed。已有设备写：CAS 可缺失/改变，只检 device + compatibility |
| 终态分类 | preflight / mapping reject / permanent / cancel / retryable 共用 `hasDeviceWrites`。local-only 确认后 CAS conflict 为 `failedWithoutWrites` |
| `0x84` 值域 | `AhaKeyRuntimeLightMappingRow.effects` 只允许固件 index `0...7`；package decode 与真 WAL reopen 拒绝 `0xff` |

不实现 60 秒 abandon、逐字段 baseline projection、Studio 页面锁/C4 UI。未改 C2 dirty accepted set、`AhaKeyDeviceProgramSteps`、Views、Hook、安装器。C3BR1 已冻结的 `0x84` 整行/physical-slot/prepare/page-only/FIFO/chunk resume/cancel 保持。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 216/216

swift test
# 894 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `d212e6a` / 调度 23:38）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionEngine.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- 对应 Shared/Agent 精确测试
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 dirty accepted set、DeviceProgramSteps、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3BR2 按任务卡收口权威 CAS 生产生命周期、typed device-write fact 与 `0x84` 值域。停手提审，不自动进 C3C/C4。
