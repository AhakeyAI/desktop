# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3BR1：生产 live CAS、0x84 整行与 device-confirmed 恢复门

日期：2026-09-04 23:05–23:27 +08
ACK Codex 23:02 / `lastReviewedCommit=bf312525fb43413633fff8ab10e59eb97b8f4515` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3BR1 行为

| 审查项 | 落地 |
|---|---|
| 生产 live base CAS | Agent preflight 只读 store 密封 CAS；缺失即 `missingPreconditions` 零写 fail-closed。禁止 fallback 到 package/contract。测试走同一 store API：accept 后改密封值与 fresh Agent reopen 均零 confirmed |
| 0x84 冻结整行 | assembler 用 trusted siblings + dirty overlay 组 9-state row，不把 siblings 扩进 fieldMask；缺 sibling / unknown 未确认 fail-closed。fingerprint 纳入 `lightMappingRows`；执行与恢复只重放这一行，禁止临场补零 |
| device-confirmed 恢复门 | preflight 只在存在非 `page:local:` 确认时放宽 base CAS。local-only 确认后改 CAS 仍 conflict；mixed 包在设备确认前改 CAS 零写拒绝 |
| P3 | 删除未消费的 `notQueueHead`；handshake/snapshot 共用 `AhaKeyConfigurationPackage.advertisedSchemaVersions` |

不实现 60 秒 abandon、逐字段 baseline projection、Studio 页面锁/C4 UI。未改 C2 dirty accepted set、`AhaKeyDeviceProgramSteps`、Views、Hook、安装器。C3B 已冻结的 physical-slot/prepare/page-only/FIFO/chunk resume/cancel 保持。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 210/210

swift test
# 888 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `bf31252` / 调度 23:02）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePersistentStore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPageModel.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- 对应 Shared/Agent 精确测试
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 dirty accepted set、DeviceProgramSteps、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3BR1 按任务卡收口生产 preflight / 0x84 整行 / device-confirmed 恢复门。停手提审，不自动进 C3C/C4。
